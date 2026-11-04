import XCTest
@testable import PressIfCore

final class BehaviorTests: XCTestCase {
    private let zone = TimeZone(identifier: "Asia/Seoul")!
    private let clock = AppIdentity(bundleID: "com.apple.clock", name: "Clock", aliases: ["시계"])

    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }

    func testAbsoluteTimeDoesNotBecomeDelay() throws {
        let now = date("2026-11-03T16:00:00+09:00")
        let schedule = ScheduleIntent(kind: .at, time: "17:10")
        XCTAssertEqual(try schedule.resolve(now: now, timeZone: zone), date("2026-11-03T17:10:00+09:00"))
    }

    func testPastTimeNeverSilentlyRollsToTomorrow() {
        XCTAssertThrowsError(try ScheduleIntent(kind: .at, time: "17:10").resolve(now: date("2026-11-03T18:00:00+09:00"), timeZone: zone))
    }

    func testExplicitTomorrow() throws {
        XCTAssertEqual(try ScheduleIntent(kind: .at, date: "2026-11-04", time: "09:00").resolve(now: date("2026-11-03T18:00:00+09:00"), timeZone: zone), date("2026-11-04T09:00:00+09:00"))
    }

    func testImpossibleDateRejectedInsteadOfNormalized() {
        XCTAssertThrowsError(try ScheduleIntent(kind: .at, date: "2027-02-31", time: "09:00").resolve(now: date("2026-11-03T18:00:00+09:00"), timeZone: zone))
    }

    func testOutOfRangeClockRejected() {
        for time in ["24:00", "17:61", "nine", "9:00"] {
            XCTAssertThrowsError(try ScheduleIntent(kind: .at, time: time).resolve(now: Date(), timeZone: zone))
        }
    }

    func testNonexistentDSTClockRejected() {
        XCTAssertThrowsError(try ScheduleIntent(kind: .at, date: "2027-03-14", time: "02:30").resolve(now: date("2027-03-13T10:00:00Z"), timeZone: TimeZone(identifier: "America/New_York")!))
    }

    func testRelativeTimeAndBounds() throws {
        let now = Date()
        XCTAssertEqual(try ScheduleIntent(kind: .after, seconds: 300).resolve(now: now, timeZone: zone), now.addingTimeInterval(300))
        for seconds in [-1, 0, 604801] {
            XCTAssertThrowsError(try ScheduleIntent(kind: .after, seconds: seconds).resolve(now: now, timeZone: zone))
        }
    }

    func testDailyCrossesMidnightInUserTimeZone() throws {
        XCTAssertEqual(try ScheduleIntent(kind: .daily, time: "09:00").resolve(now: date("2026-11-03T18:00:00+09:00"), timeZone: zone), date("2026-11-04T09:00:00+09:00"))
    }

    func testPlanRejectsUninstalledApplication() {
        let plan = makePlan(steps: [ActionStep(action: .launch, appID: "made.up.app")])
        XCTAssertThrowsError(try plan.validate(apps: [clock]))
    }

    func testPlanRequiresApplicationBeforeInput() {
        XCTAssertThrowsError(try makePlan(steps: [ActionStep(action: .click, target: "시작")]).validate(apps: [clock]))
    }

    func testPlanWithClockNavigationIsExecutable() throws {
        try makePlan(steps: [ActionStep(action: .launch, appID: clock.bundleID), ActionStep(action: .click, target: "스톱워치"), ActionStep(action: .click, target: "시작")]).validate(apps: [clock])
    }

    func testInvalidShortcutAndUnboundedWaitRejected() {
        XCTAssertThrowsError(try KeyCombination.validate(["command", "rm -rf"]))
        XCTAssertThrowsError(try KeyCombination.validate(["command", "command", "t"]))
        XCTAssertThrowsError(try makePlan(steps: [ActionStep(action: .launch, appID: clock.bundleID), ActionStep(action: .wait, seconds: 600)]).validate(apps: [clock]))
    }

    func testClarificationIsNeverAnExecutablePlan() {
        let plan = AutomationPlan(title: "확인 필요", schedule: ScheduleIntent(kind: .now), steps: [], successCriteria: "", clarification: "어느 앱인가요?")
        XCTAssertThrowsError(try plan.validate(apps: [clock]))
    }

    func testInventedOrDisabledTargetRejected() throws {
        let screen = ScreenObservation(app: clock.bundleID, elements: [ScreenElement(id: "a", role: "AXButton", label: "Start", actionable: false)])
        let invented = try JSONDecoder().decode(TargetDecision.self, from: Data(#"{"elementID":"fake","reason":"target"}"#.utf8))
        let disabled = try JSONDecoder().decode(TargetDecision.self, from: Data(#"{"elementID":"a","reason":"target"}"#.utf8))
        XCTAssertThrowsError(try invented.validated(in: screen))
        XCTAssertThrowsError(try disabled.validated(in: screen))
        XCTAssertNoThrow(try disabled.validated(in: screen, requireActionable: false))
    }

    func testCompletionNeedsCurrentScreenEvidence() throws {
        let screen = ScreenObservation(app: clock.bundleID, elements: [ScreenElement(id: "a", role: "AXButton", label: "Stop")])
        for evidence in ["[]", "[\"missing\"]"] {
            let data = Data("{\"verdict\":\"completed\",\"explanation\":\"done\",\"evidenceIDs\":\(evidence)}".utf8)
            XCTAssertFalse(try JSONDecoder().decode(CompletionAssessment.self, from: data).hasGroundedEvidence(in: screen))
        }
    }

    func testRelaunchPausesPendingAndRunningJobs() {
        let now = Date()
        let pending = ScheduledJob(request: "test", plan: makePlan(), runAt: now, timeZone: zone)
        var running = pending
        running.state = .running
        var completed = pending
        completed.state = .completed
        let recovered = DispatchPolicy.recovered([pending, running, completed])
        XCTAssertEqual(recovered.map(\.state), [.paused, .paused, .completed])
    }

    func testDispatchDoesNotExecuteEarlyLateOrPausedJobs() {
        let now = Date()
        var job = ScheduledJob(request: "test", plan: makePlan(), runAt: now.addingTimeInterval(1), timeZone: zone)
        XCTAssertNil(DispatchPolicy.due([job], now: now))
        job.runAt = now.addingTimeInterval(-31)
        XCTAssertNil(DispatchPolicy.due([job], now: now))
        job.runAt = now
        XCTAssertNotNil(DispatchPolicy.due([job], now: now))
        job.state = .paused
        XCTAssertNil(DispatchPolicy.due([job], now: now))
    }

    func testStorePreservesRequestAndPrivatePermissions() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = TaskStore(url: folder.appendingPathComponent("tasks.json"))
        let job = ScheduledJob(request: "시계.app에서 시작", plan: makePlan(), runAt: Date(), timeZone: zone)
        try store.save([job])
        let restored = try store.load()
        XCTAssertEqual(restored.first?.request, job.request)
        XCTAssertEqual(restored.first?.plan, job.plan)
        let mode = try FileManager.default.attributesOfItem(atPath: store.url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    func testCorruptStoreThrowsInsteadOfDroppingJobs() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("corrupt".utf8).write(to: url)
        XCTAssertThrowsError(try TaskStore(url: url).load())
    }

    func testEnvParserPreservesQuotedEqualsAndPrefersExplicitEnvironment() {
        let values = Credentials.parseEnv("# example\nexport MODEL_API_KEY='test=a=b'\n")
        XCTAssertEqual(values["MODEL_API_KEY"], "test=a=b")
        XCTAssertEqual(Credentials.load(environment: ["MODEL_API_KEY": "explicit"]), "explicit")
    }

    private func makePlan(steps: [ActionStep]? = nil) -> AutomationPlan {
        AutomationPlan(title: "시계", schedule: ScheduleIntent(kind: .at, time: "17:10"), steps: steps ?? [ActionStep(action: .launch, appID: clock.bundleID)], successCriteria: "시계 창이 보인다")
    }
}
