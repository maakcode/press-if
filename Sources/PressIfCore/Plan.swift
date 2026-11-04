import Foundation

public struct AppIdentity: Codable, Equatable, Sendable {
    public let bundleID: String
    public let name: String
    public let aliases: [String]

    public init(bundleID: String, name: String, aliases: [String] = []) {
        self.bundleID = bundleID
        self.name = name
        self.aliases = aliases
    }
}

public enum ActionKind: String, Codable, Sendable {
    case launch, click, input, setValue, shortcut, wait, waitFor
}

public struct ActionStep: Codable, Equatable, Sendable {
    public let action: ActionKind
    public let appID: String?
    public let target: String?
    public let context: String?
    public let text: String?
    public let keys: [String]?
    public let seconds: Double?
    public let referenceImageID: String?
    public let number: Double?

    public init(action: ActionKind, appID: String? = nil, target: String? = nil, context: String? = nil, text: String? = nil, keys: [String]? = nil, seconds: Double? = nil, referenceImageID: String? = nil, number: Double? = nil) {
        self.action = action
        self.appID = appID
        self.target = target
        self.context = context
        self.text = text
        self.keys = keys
        self.seconds = seconds
        self.referenceImageID = referenceImageID
        self.number = number
    }

    public var label: String {
        switch action {
        case .launch: return "Open app"
        case .click: return referenceImageID == nil ? "Click \(target ?? "control")" : "Find \(target ?? "button") by image"
        case .input: return "Type text"
        case .setValue: return "\(target ?? "Value") → \((number ?? 0).formatted(.number.grouping(.never)))"
        case .shortcut: return (keys ?? []).joined(separator: " + ")
        case .wait: return "Wait \(Int(seconds ?? 1)) sec"
        case .waitFor: return "Wait for \(target ?? "control")"
        }
    }

    public var symbol: String {
        switch action {
        case .launch: return "macwindow"
        case .click: return referenceImageID == nil ? "cursorarrow.click" : "photo.badge.magnifyingglass"
        case .input: return "text.cursor"
        case .setValue: return "slider.horizontal.3"
        case .shortcut: return "keyboard"
        case .wait, .waitFor: return "hourglass"
        }
    }
}

public struct AutomationPlan: Codable, Equatable, Sendable {
    public let title: String
    public let schedule: ScheduleIntent
    public let steps: [ActionStep]
    public let successCriteria: String
    public let clarification: String?

    public init(title: String, schedule: ScheduleIntent, steps: [ActionStep], successCriteria: String, clarification: String? = nil) {
        self.title = title
        self.schedule = schedule
        self.steps = steps
        self.successCriteria = successCriteria
        self.clarification = clarification
    }

    public func validate(apps: [AppIdentity], referenceImages: [ReferenceImage] = []) throws {
        if let clarification, !clarification.isEmpty { throw PressError.message(clarification) }
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !successCriteria.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PressError.message("The plan needs a title and a success check. Rephrase your request.")
        }
        guard (1...16).contains(steps.count), steps.first?.action == .launch else {
            throw PressError.message("The plan must contain 1–16 steps and start by opening an app.")
        }
        let appIDs = Set(apps.map(\.bundleID))
        let imageIDs = Set(referenceImages.map(\.id))
        let referencedIDs = Set(steps.compactMap(\.referenceImageID))
        guard referencedIDs == imageIDs else {
            throw PressError.message("Some images are missing from the plan. Preview again.")
        }
        for step in steps {
            if step.referenceImageID != nil && step.action != .click {
                throw PressError.message("Reference images can only be used for click steps.")
            }
            switch step.action {
            case .launch:
                guard let appID = step.appID, appIDs.contains(appID) else {
                    throw PressError.message("The planned app is not in the installed app list.")
                }
            case .click, .waitFor:
                guard let target = step.target, !target.isEmpty, target.count <= 300 else {
                    throw PressError.message("The target control is unclear.")
                }
            case .input:
                guard let text = step.text, !text.isEmpty, text.count <= 4000 else {
                    throw PressError.message("The text to type is empty or too long.")
                }
            case .setValue:
                guard let target = step.target, !target.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, target.count <= 300,
                      let number = step.number, step.text == nil else {
                    throw PressError.message("The numeric step needs a target and a value.")
                }
                try NumericControlPolicy.validateNumber(number)
            case .shortcut:
                try KeyCombination.validate(step.keys ?? [])
            case .wait:
                guard let seconds = step.seconds, seconds.isFinite, (0.1...60).contains(seconds) else {
                    throw PressError.message("Set a wait time from 0.1 to 60 seconds.")
                }
            }
            if step.action == .waitFor, let seconds = step.seconds, !seconds.isFinite || !(1...60).contains(seconds) {
                throw PressError.message("Set a screen wait time from 1 to 60 seconds.")
            }
        }
    }
}

public enum KeyCombination {
    public static let modifiers: Set<String> = ["command", "control", "option", "shift"]
    public static let namedKeys: Set<String> = ["return", "tab", "escape", "space", "delete", "up", "down", "left", "right"]

    public static func validate(_ keys: [String]) throws {
        let ordinary = keys.filter { !modifiers.contains($0) }
        let singleCharacter = ordinary.first.map { $0.count == 1 && $0.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").contains($0) } } ?? false
        guard (1...5).contains(keys.count), Set(keys).count == keys.count,
              ordinary.count == 1, singleCharacter || namedKeys.contains(ordinary[0]) else {
            throw PressError.message("This keyboard shortcut is not supported.")
        }
    }
}

public enum PressError: LocalizedError, Sendable {
    case message(String)
    case targetUnavailable(String)
    public var errorDescription: String? {
        switch self { case .message(let message), .targetUnavailable(let message): return message }
    }
}
