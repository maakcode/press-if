import AppKit
import SwiftUI
import ApplicationServices
import PressIfCore

@MainActor
final class AppModel: ObservableObject {
    @Published var document = RequestDocument()
    @Published var preview: AutomationPlan?
    @Published var previewDate: Date?
    @Published var jobs: [ScheduledJob] = []
    @Published var selectedJobID: UUID?
    @Published var interpreting = false
    @Published var runningID: UUID?
    @Published var error: String?
    @Published var showSettings = false
    @Published var apiKey = ""
    @Published var credentialSource = "No API key"
    @Published var modelName = MetaClient.defaultModel
    @Published var includeScreenshots = false
    @Published var accessibilityGranted = false
    @Published var screenGranted = false
    let catalog = DesktopCatalog()
    private let store: TaskStore
    private var preparedRequest = ""
    private var preparedDocument = RequestDocument()
    private var storageHealthy = true
    private var interpretationTask: Task<Void, Never>?
    private var executionTask: Task<Void, Never>?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PressIfMeta", isDirectory: true)
        store = TaskStore(url: support.appendingPathComponent("tasks.json"))
        modelName = UserDefaults.standard.string(forKey: "metaModel") ?? MetaClient.defaultModel
        includeScreenshots = UserDefaults.standard.object(forKey: "includeScreenshots") as? Bool ?? false
        catalog.refresh()
        loadCredential()
        do {
            let stored = try store.load()
            jobs = DispatchPolicy.recovered(stored)
            if !stored.isEmpty { try store.save(jobs) }
        } catch {
            storageHealthy = false
            self.error = "Could not read saved tasks. Saving and execution are paused. \(error.localizedDescription)"
        }
        refreshPermissions()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stopAll(reason: "Task stopped because your Mac went to sleep.") }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.stopAll(reason: "Task stopped because the session was locked.") }
        })
    }

    var selectedJob: ScheduledJob? { jobs.first { $0.id == selectedJobID } }
    var request: String {
        get { document.plainText }
        set { document = RequestDocument(text: newValue) }
    }
    var previewIsCurrent: Bool { document == preparedDocument }
    var imagePermissionsReady: Bool { document.images.isEmpty || (includeScreenshots && screenGranted) }
    var pendingCount: Int { jobs.filter { $0.state == .scheduled }.count }

    func interpret() {
        guard !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !interpreting else { return }
        guard !apiKey.isEmpty else { showSettings = true; return }
        selectedJobID = nil
        preview = nil
        previewDate = nil
        error = nil
        interpreting = true
        catalog.refresh()
        let original = document
        let client = makeClient()
        let apps = catalog.apps
        let now = Date()
        let zone = TimeZone.current
        interpretationTask = Task {
            defer { interpreting = false; interpretationTask = nil }
            do {
                let result = try await client.plan(document: original, apps: apps, now: now, timeZone: zone)
                try Task.checkCancellation()
                guard document == original else { return }
                previewDate = try result.schedule.resolve(now: Date(), timeZone: zone)
                preparedRequest = original.plainText
                preparedDocument = original
                preview = result
            } catch is CancellationError { }
            catch { self.error = error.localizedDescription }
        }
    }

    func savePreview() {
        guard let preview, previewIsCurrent else {
            error = "Your request changed. Preview the plan again."
            return
        }
        do {
            try document.validate()
            try preview.validate(apps: catalog.apps, referenceImages: document.images)
            guard imagePermissionsReady else { throw PressError.message("Enable Screen Recording and window image analysis to find buttons by image.") }
            let now = Date()
            let date = try preview.schedule.resolve(now: now, timeZone: .current)
            let job = ScheduledJob(request: preparedRequest, plan: preview, runAt: date, timeZone: .current, now: now, document: document)
            try replaceJobs([job] + jobs)
            selectedJobID = job.id
            self.preview = nil
            previewDate = nil
            request = ""
            error = nil
        } catch { self.error = error.localizedDescription }
    }

    func newRequest(_ text: String = "") {
        interpretationTask?.cancel()
        selectedJobID = nil
        preview = nil
        previewDate = nil
        request = text
        error = nil
    }

    func newRequest(document: RequestDocument) {
        newRequest()
        self.document = document
    }

    func pause(_ id: UUID) {
        if runningID == id { executionTask?.cancel() }
        do { try update(id) { $0.state = .paused; $0.record("Paused by you.") } }
        catch { self.error = error.localizedDescription }
    }

    func resume(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }), job.state == .paused else { return }
        do {
            let now = Date()
            let date: Date
            if job.plan.schedule.kind == .daily {
                date = try job.plan.schedule.resolve(now: now, timeZone: TimeZone(identifier: job.timeZoneID) ?? .current)
            } else {
                guard job.runAt > now else { throw PressError.message("The scheduled time has passed. Create a new task with a future time.") }
                date = job.runAt
            }
            try update(id) { $0.runAt = date; $0.state = .scheduled; $0.record("Task resumed.") }
        } catch { self.error = error.localizedDescription }
    }

    func remove(_ id: UUID) {
        guard runningID != id else { return }
        do {
            try replaceJobs(jobs.filter { $0.id != id })
            if selectedJobID == id { selectedJobID = nil }
        } catch { self.error = error.localizedDescription }
    }

    func stopAll(reason: String = "All tasks stopped by you.") {
        executionTask?.cancel()
        interpretationTask?.cancel()
        var next = jobs
        for index in next.indices where next[index].state == .scheduled || next[index].state == .running {
            next[index].state = .paused
            next[index].record(reason)
        }
        do { try replaceJobs(next) }
        catch { self.error = error.localizedDescription }
    }

    func saveSettings() {
        do {
            apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            try SecretStore.save(apiKey)
            credentialSource = apiKey.isEmpty ? "No API key" : "Stored in Keychain"
            UserDefaults.standard.set(modelName, forKey: "metaModel")
            UserDefaults.standard.set(includeScreenshots, forKey: "includeScreenshots")
            showSettings = false
        } catch { self.error = error.localizedDescription }
    }

    func refreshPermissions() {
        accessibilityGranted = AXIsProcessTrusted()
        screenGranted = CGPreflightScreenCaptureAccess()
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        openPrivacy("Privacy_Accessibility")
    }

    func requestScreenAccess() {
        CGRequestScreenCaptureAccess()
        openPrivacy("Privacy_ScreenCapture")
    }

    private func openPrivacy(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?" + pane) { NSWorkspace.shared.open(url) }
    }

    private func loadCredential() {
        if let key = SecretStore.read(), !key.isEmpty {
            apiKey = key
            credentialSource = "Stored in Keychain"
            return
        }
        if let key = Credentials.load() {
            apiKey = key
            credentialSource = "From environment"
        } else { credentialSource = "No API key" }
    }

    private func makeClient() -> MetaClient { MetaClient(apiKey: apiKey, model: modelName) }

    private func tick() {
        refreshPermissions()
        guard runningID == nil, storageHealthy else { return }
        let now = Date()
        var changed = jobs
        var hasMissed = false
        for index in changed.indices where changed[index].state == .scheduled && now.timeIntervalSince(changed[index].runAt) > DispatchPolicy.maximumLateness {
            changed[index].state = .missed
            changed[index].record("Skipped: the scheduled time passed by more than 30 seconds.")
            hasMissed = true
        }
        if hasMissed {
            do { try replaceJobs(changed) }
            catch { self.error = error.localizedDescription; return }
        }
        guard let job = DispatchPolicy.due(jobs, now: now) else { return }
        launch(job)
    }

    private func launch(_ job: ScheduledJob) {
        do { try update(job.id) { $0.state = .running; $0.record("Scheduled time reached. Starting automation.") } }
        catch { self.error = error.localizedDescription; return }
        runningID = job.id
        let client = makeClient()
        let engine = ExecutionEngine(catalog: catalog)
        let includeImages = includeScreenshots
        executionTask = Task {
            defer { runningID = nil; executionTask = nil }
            do {
                let result = try await engine.run(plan: job.plan, client: client, includeImages: includeImages, referenceImages: job.document?.images ?? []) { [self] message in
                    try update(job.id) { $0.record(message) }
                }
                try Task.checkCancellation()
                try update(job.id) { $0.state = result.verdict == .completed ? .completed : .needsReview }
                if job.plan.schedule.kind == .daily && result.verdict == .completed {
                    let nextDate = try job.plan.schedule.resolve(now: Date(), timeZone: TimeZone(identifier: job.timeZoneID) ?? .current)
                    try update(job.id) { $0.runAt = nextDate; $0.state = .scheduled; $0.record("Scheduled for the same time tomorrow.") }
                }
            } catch is CancellationError {
                try? update(job.id) { $0.state = .paused; $0.record("Task canceled. Inputs already delivered remain in effect.") }
            } catch {
                if Task.isCancelled {
                    try? update(job.id) { $0.state = .paused; $0.record("Task canceled.") }
                } else {
                    self.error = error.localizedDescription
                    try? update(job.id) { $0.state = .failed; $0.record(error.localizedDescription) }
                }
            }
        }
    }

    private func update(_ id: UUID, change: (inout ScheduledJob) -> Void) throws {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        var next = jobs
        change(&next[index])
        try replaceJobs(next)
    }

    private func replaceJobs(_ value: [ScheduledJob]) throws {
        guard storageHealthy else { throw PressError.message("Saved tasks could not be read. Restore the task file and reopen Press If.") }
        do { try store.save(value) }
        catch { storageHealthy = false; executionTask?.cancel(); throw error }
        jobs = value
    }
}
