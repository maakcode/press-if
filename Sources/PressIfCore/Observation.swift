import Foundation

public struct ScreenElement: Codable, Equatable, Sendable {
    public let id: String
    public let role: String
    public let label: String
    public let value: String
    public let context: String
    public let actionable: Bool
    public let numericControl: NumericControlState?

    public init(id: String, role: String, label: String, value: String = "", context: String = "", actionable: Bool = true, numericControl: NumericControlState? = nil) {
        self.id = id
        self.role = role
        self.label = label
        self.value = value
        self.context = context
        self.actionable = actionable
        self.numericControl = numericControl
    }
}

public struct ScreenObservation: Codable, Sendable {
    public let app: String
    public let capturedAt: Date
    public let elements: [ScreenElement]

    public init(app: String, capturedAt: Date = Date(), elements: [ScreenElement]) {
        self.app = app
        self.capturedAt = capturedAt
        self.elements = elements
    }
}

public struct TargetDecision: Codable, Sendable {
    public let elementID: String?
    public let reason: String

    public func validated(in observation: ScreenObservation, requireActionable: Bool = true) throws -> ScreenElement {
        guard let elementID, let element = observation.elements.first(where: { $0.id == elementID }),
              !requireActionable || element.actionable else {
            throw PressError.targetUnavailable(reason.isEmpty ? "Could not confidently identify the target on screen." : reason)
        }
        return element
    }
}

public struct CompletionAssessment: Codable, Sendable {
    public enum Verdict: String, Codable, Sendable { case completed, incomplete, uncertain }
    public let verdict: Verdict
    public let explanation: String
    public let evidenceIDs: [String]

    public func hasGroundedEvidence(in observation: ScreenObservation) -> Bool {
        let available = Set(observation.elements.map(\.id))
        return !evidenceIDs.isEmpty && evidenceIDs.allSatisfy { available.contains($0) }
    }
}
