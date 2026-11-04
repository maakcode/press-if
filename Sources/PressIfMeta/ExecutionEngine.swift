import AppKit
import ApplicationServices
import PressIfCore

@MainActor
final class ExecutionEngine {
    private let catalog: DesktopCatalog
    private let screen = DesktopScreen()

    init(catalog: DesktopCatalog) { self.catalog = catalog }

    func run(plan: AutomationPlan, client: MetaClient, includeImages: Bool, referenceImages: [ReferenceImage] = [], log: @escaping (String) throws -> Void) async throws -> CompletionAssessment {
        guard AXIsProcessTrusted() else { throw PressError.message("Allow Accessibility for Press If in System Settings.") }
        try plan.validate(apps: catalog.apps, referenceImages: referenceImages)
        if !referenceImages.isEmpty && (!includeImages || !CGPreflightScreenCaptureAccess()) {
            throw PressError.message("Enable Screen Recording and window image analysis to find buttons by image.")
        }
        var application: NSRunningApplication?
        var numericSettings: [(handle: ElementHandle, number: Double)] = []
        var numericWindowTitle = ""
        for (index, step) in plan.steps.enumerated() {
            try Task.checkCancellation()
            try log("\(index + 1)/\(plan.steps.count) · \(step.label)")
            if step.action == .launch {
                application = try await catalog.activate(step.appID!)
                numericSettings = []
                continue
            }
            guard let application else { throw PressError.message("Specify an app to open first.") }
            try screen.ensureForeground(application)
            switch step.action {
            case .launch: break
            case .click:
                let reference = referenceImages.first { $0.id == step.referenceImageID }
                let snapshot = try await screen.observe(application: application, includeImage: includeImages, reference: reference)
                let decision = try await client.select(step: step, observation: snapshot.observation, image: snapshot.image, reference: reference)
                guard let handle = snapshot.handles.first(where: { $0.description.id == decision.elementID }) else { throw PressError.message("Could not find the target control.") }
                let current = try await screen.revalidated(handle, previous: snapshot, application: application, includeImage: includeImages, reference: reference)
                try await screen.verifyNumbers(numericSettings, windowTitle: numericWindowTitle, application: application)
                try Task.checkCancellation()
                try screen.click(current, application: application)
                numericSettings = []
                try log(decision.reason)
                try await Task.sleep(for: .milliseconds(600))
            case .setValue:
                let snapshot = try await screen.observe(application: application, includeImage: includeImages)
                let decision = try await client.select(step: step, observation: snapshot.observation, image: snapshot.image)
                guard let handle = snapshot.handles.first(where: { $0.description.id == decision.elementID }), let number = step.number else {
                    throw PressError.message("Could not find the numeric control.")
                }
                let current = try await screen.revalidated(handle, previous: snapshot, application: application, includeImage: false, requireUnchangedValue: true)
                try await screen.setNumber(number, on: current, previous: snapshot, application: application)
                numericSettings.removeAll { $0.handle.bounds == current.bounds && $0.handle.description.role == current.description.role }
                numericSettings.append((current, number))
                numericWindowTitle = snapshot.windowTitle
                try log("\(step.label) · Value verified")
            case .input:
                try screen.ensureTextInput(application)
                try DesktopKeyboard.type(step.text!) { try screen.ensureTextInput(application) }
            case .shortcut:
                try screen.ensureForeground(application)
                try DesktopKeyboard.press(step.keys!)
                try await Task.sleep(for: .milliseconds(400))
            case .wait:
                try await Task.sleep(for: .seconds(step.seconds!))
            case .waitFor:
                try await waitFor(step, application: application, client: client, includeImages: includeImages)
            }
        }
        guard let application else { throw PressError.message("No app was opened.") }
        try log("Actions delivered. Checking the result on screen.")
        let earlier = try await screen.observe(application: application, includeImage: includeImages)
        try await Task.sleep(for: .seconds(1.2))
        let current = try await screen.observe(application: application, includeImage: includeImages)
        let assessment = try await client.assess(criteria: plan.successCriteria, earlier: earlier.observation, current: current.observation, image: current.image)
        try Task.checkCancellation()
        try log(assessment.explanation)
        return assessment
    }

    private func waitFor(_ step: ActionStep, application: NSRunningApplication, client: MetaClient, includeImages: Bool) async throws {
        let deadline = Date().addingTimeInterval(step.seconds ?? 20)
        var latestReason = "The requested target did not appear."
        for _ in 0..<3 {
            try Task.checkCancellation()
            guard Date() < deadline else { break }
            let snapshot = try await screen.observe(application: application, includeImage: includeImages)
            do {
                _ = try await client.select(step: step, observation: snapshot.observation, image: snapshot.image)
                guard Date() <= deadline else { break }
                return
            } catch is CancellationError { throw CancellationError() }
            catch { latestReason = error.localizedDescription }
            try await Task.sleep(for: .seconds(1))
        }
        throw PressError.message(latestReason)
    }
}
