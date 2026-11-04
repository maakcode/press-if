import Foundation

public enum TaskState: String, Codable, Sendable {
    case scheduled, running, completed, needsReview, failed, paused, missed

    public var label: String {
        switch self {
        case .scheduled: return "Scheduled"
        case .running: return "Running"
        case .completed: return "Verified"
        case .needsReview: return "Needs review"
        case .failed: return "Stopped"
        case .paused: return "Paused"
        case .missed: return "Missed"
        }
    }
}

public struct TaskEvent: Codable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public let message: String

    public init(_ message: String, date: Date = Date()) {
        self.id = UUID()
        self.date = date
        self.message = message
    }
}

public struct ScheduledJob: Codable, Identifiable, Sendable {
    public let id: UUID
    public let request: String
    public let document: RequestDocument?
    public let plan: AutomationPlan
    public let timeZoneID: String
    public let createdAt: Date
    public var runAt: Date
    public var state: TaskState
    public var events: [TaskEvent]

    public init(request: String, plan: AutomationPlan, runAt: Date, timeZone: TimeZone, now: Date = Date(), document: RequestDocument? = nil) {
        id = UUID()
        self.request = request
        self.document = document
        self.plan = plan
        self.runAt = runAt
        timeZoneID = timeZone.identifier
        createdAt = now
        state = .scheduled
        events = [TaskEvent("Plan reviewed and scheduled.", date: now)]
    }

    public mutating func record(_ message: String) {
        events.append(TaskEvent(message))
        if events.count > 120 { events.removeFirst(events.count - 120) }
    }
}

public struct TaskStore {
    public let url: URL
    public init(url: URL) { self.url = url }

    public func load() throws -> [ScheduledJob] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([ScheduledJob].self, from: Data(contentsOf: url))
    }

    public func save(_ jobs: [ScheduledJob]) throws {
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        let data = try JSONEncoder().encode(jobs)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

public enum DispatchPolicy {
    public static let maximumLateness: TimeInterval = 30

    public static func recovered(_ jobs: [ScheduledJob]) -> [ScheduledJob] {
        jobs.map { job in
            guard job.state == .scheduled || job.state == .running else { return job }
            var recovered = job
            recovered.state = .paused
            recovered.record("Task paused after the app restarted.")
            return recovered
        }
    }

    public static func due(_ jobs: [ScheduledJob], now: Date) -> ScheduledJob? {
        jobs.filter { $0.state == .scheduled && $0.runAt <= now && now.timeIntervalSince($0.runAt) <= maximumLateness }
            .min { $0.runAt < $1.runAt }
    }
}
