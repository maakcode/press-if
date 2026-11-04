import Foundation

public actor MetaClient {
    public static let defaultModel = "muse-spark-1.3"
    private let apiKey: String
    private let model: String
    private let session: URLSession

    public init(apiKey: String, model: String = MetaClient.defaultModel) {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.model = model
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }

    public func plan(request: String, apps: [AppIdentity], now: Date, timeZone: TimeZone) async throws -> AutomationPlan {
        try await plan(document: RequestDocument(text: request), apps: apps, now: now, timeZone: timeZone)
    }

    public func plan(document: RequestDocument, apps: [AppIdentity], now: Date, timeZone: TimeZone) async throws -> AutomationPlan {
        try document.validate()
        let clock = ISO8601DateFormatter()
        clock.timeZone = timeZone
        let context = PlanningContext(request: document.plainText, currentLocalTime: clock.string(from: now), timeZone: timeZone.identifier, installedApps: apps)
        var orderedContent: [[String: Any]] = []
        for part in document.parts {
            switch part {
            case .text(let text): orderedContent.append(["type": "text", "text": text])
            case .image(let reference):
                orderedContent.append(["type": "text", "text": "INLINE_REFERENCE_IMAGE id=\(reference.id). This image occurs at this exact position in the user's sentence."])
                orderedContent.append(imageContent(reference.png))
            }
        }
        let result: AutomationPlan = try await complete(
            instructions: MetaPrompts.planning,
            text: try jsonText(context),
            extraContent: orderedContent,
            schema: MetaSchemas.plan,
            name: "automation_plan"
        )
        try result.validate(apps: apps, referenceImages: document.images)
        _ = try result.schedule.resolve(now: now, timeZone: timeZone)
        return result
    }

    public func select(step: ActionStep, observation: ScreenObservation, image: Data?, reference: ReferenceImage? = nil) async throws -> TargetDecision {
        let context = SelectionContext(requestedStep: step, screen: observation)
        var extra: [[String: Any]] = []
        if let reference {
            guard image != nil, reference.id == step.referenceImageID else { throw PressError.message("Both the reference image and the current window image are required.") }
            extra = [["type": "text", "text": "REFERENCE_BUTTON_TO_FIND id=\(reference.id)"], imageContent(reference.png), ["type": "text", "text": "CURRENT_WINDOW_SCREENSHOT follows. Find the same visual button, using only ImageMatch candidates."]]
        }
        let result: TargetDecision = try await complete(
            instructions: MetaPrompts.selection,
            text: try jsonText(context),
            image: image,
            extraContent: extra,
            schema: MetaSchemas.selection,
            name: "screen_target"
        )
        let selected = try result.validated(in: observation, requireActionable: step.action != .waitFor)
        if step.action == .setValue, let number = step.number { try NumericControlPolicy.validate(number, on: selected) }
        if reference != nil && selected.role != "ImageMatch" { throw PressError.message("Could not confirm a matching area on screen.") }
        return result
    }

    public func assess(criteria: String, earlier: ScreenObservation, current: ScreenObservation, image: Data?) async throws -> CompletionAssessment {
        let context = AssessmentContext(successCriteria: criteria, earlierScreen: earlier, currentScreen: current)
        let result: CompletionAssessment = try await complete(
            instructions: MetaPrompts.assessment,
            text: try jsonText(context),
            image: image,
            schema: MetaSchemas.assessment,
            name: "completion_assessment"
        )
        if result.verdict == .completed && !result.hasGroundedEvidence(in: current) {
            throw PressError.message("The completion assessment has no verifiable screen evidence.")
        }
        return result
    }

    private func complete<Result: Decodable>(instructions: String, text: String, image: Data? = nil, extraContent: [[String: Any]] = [], schema: [String: Any], name: String) async throws -> Result {
        guard !apiKey.isEmpty else { throw PressError.message("Enter an API key in Settings.") }
        guard apiKey.rangeOfCharacter(from: .newlines) == nil else { throw PressError.message("The API key format is invalid.") }
        var content: [[String: Any]] = [["type": "text", "text": text]]
        content.append(contentsOf: extraContent)
        if let image {
            content.append(imageContent(image))
        }
        let body: [String: Any] = [
            "model": model,
            "messages": [["role": "system", "content": instructions], ["role": "user", "content": content]],
            "response_format": ["type": "json_schema", "json_schema": ["name": name, "strict": true, "schema": schema]],
            "reasoning_effort": "low",
            "max_completion_tokens": 8192,
            "stream": false
        ]
        var request = URLRequest(url: URL(string: "https://api.meta.ai/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer " + apiKey, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await session.data(for: request)
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse else { throw PressError.message("Could not read the model response.") }
        guard (200...299).contains(response.statusCode) else {
            let detail: String
            switch response.statusCode {
            case 401: detail = "Check your API key."
            case 403: detail = "Check model access and supported regions for your project."
            case 429: detail = "Check your usage limit or credits, then try again."
            default: detail = "Try again in a moment."
            }
            throw PressError.message("Model API error \(response.statusCode). \(detail)")
        }
        let envelope = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let choice = envelope.choices.first, choice.finish_reason == "stop",
              let text = choice.message.content, let json = text.data(using: .utf8) else {
            throw PressError.message("The model response was incomplete. No actions were run.")
        }
        do { return try JSONDecoder().decode(Result.self, from: json) }
        catch { throw PressError.message("The model returned an invalid plan. Preview again.") }
    }

    private func jsonText<Value: Encodable>(_ value: Value) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    private func imageContent(_ png: Data) -> [String: Any] {
        ["type": "image_url", "image_url": ["url": "data:image/png;base64," + png.base64EncodedString()]]
    }
}

private struct PlanningContext: Encodable {
    let request: String
    let currentLocalTime: String
    let timeZone: String
    let installedApps: [AppIdentity]
}

private struct SelectionContext: Encodable {
    let requestedStep: ActionStep
    let screen: ScreenObservation
}

private struct AssessmentContext: Encodable {
    let successCriteria: String
    let earlierScreen: ScreenObservation
    let currentScreen: ScreenObservation
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let content: String? }
        let message: Message
        let finish_reason: String?
    }
    let choices: [Choice]
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
