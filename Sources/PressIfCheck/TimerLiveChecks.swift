import Foundation
import PressIfCore

enum TimerLiveChecks {
    static func run(client: MetaClient, apps: [AppIdentity], now: Date, zone: TimeZone) async -> [CheckResult] {
        var results: [CheckResult] = []
        do {
            let plan = try await client.plan(request: "5초 뒤 시계 앱의 타이머에서 15분 카운트다운을 시작해", apps: apps, now: now, timeZone: zone)
            let settings = plan.steps.filter { $0.action == .setValue }
            let values: [(Set<String>, Double)] = [(Set(["시간", "시", "hours", "hour"]), 0), (Set(["분", "minutes", "minute"]), 15), (Set(["초", "seconds", "second"]), 0)]
            let componentsMatch = values.allSatisfy { names, number in settings.contains { names.contains($0.target?.lowercased() ?? "") && $0.number == number } }
            let correct = plan.schedule.kind == .after && plan.schedule.seconds == 5 && settings.count == 3 && componentsMatch
                && !plan.steps.contains { $0.action == .input } && plan.steps.last?.action == .click
                && ["시작", "start"].contains(plan.steps.last?.target?.lowercased() ?? "")
            CheckMain.record("countdown_plan_resets_all_components", correct, String(decoding: try JSONEncoder().encode(plan), as: UTF8.self), to: &results)
        } catch { CheckMain.record("countdown_plan_resets_all_components", false, error.localizedDescription, to: &results) }
        do {
            let screen = ScreenObservation(app: "com.apple.clock", elements: [
                numeric("hours", 3, "3시간", maximum: 23), numeric("minutes", 0, "0분", maximum: 59), numeric("seconds", 15, "15초", maximum: 59),
                ScreenElement(id: "label", role: "AXTextField", label: "타이머", value: "15분 타이머"),
                ScreenElement(id: "ocr", role: "OCRText", label: "분"),
                ScreenElement(id: "start", role: "AXButton", label: "시작")
            ])
            let decision = try await client.select(step: ActionStep(action: .setValue, target: "분", context: "타이머", number: 15), observation: screen, image: nil)
            CheckMain.record("numeric_control_unit_and_capability_selection", decision.elementID == "minutes", decision.reason, to: &results)
        } catch { CheckMain.record("numeric_control_unit_and_capability_selection", false, error.localizedDescription, to: &results) }
        let criteria = "15분 타이머가 실행 중이며 남은 시간이 줄어든다."
        do {
            let screen = ScreenObservation(app: "com.apple.clock", elements: [numeric("minutes", 15, "15분", maximum: 59), ScreenElement(id: "start", role: "AXButton", label: "시작")])
            let result = try await client.assess(criteria: criteria, earlier: screen, current: screen, image: nil)
            CheckMain.record("configured_countdown_is_not_running", result.verdict != .completed, result.explanation, to: &results)
        } catch { CheckMain.record("configured_countdown_is_not_running", false, error.localizedDescription, to: &results) }
        do {
            let earlier = countdown("14:59")
            let current = countdown("14:57")
            let result = try await client.assess(criteria: criteria, earlier: earlier, current: current, image: nil)
            CheckMain.record("decreasing_countdown_evidence", result.verdict == .completed && result.hasGroundedEvidence(in: current), result.explanation, to: &results)
        } catch { CheckMain.record("decreasing_countdown_evidence", false, error.localizedDescription, to: &results) }
        return results
    }

    private static func numeric(_ id: String, _ value: Double, _ description: String, maximum: Double) -> ScreenElement {
        ScreenElement(id: id, role: "AXSlider", label: "", value: String(value), context: "타이머",
                      numericControl: NumericControlState(value: value, valueDescription: description, minimum: 0, maximum: maximum, settable: true))
    }

    private static func countdown(_ remaining: String) -> ScreenObservation {
        ScreenObservation(app: "com.apple.clock", elements: [ScreenElement(id: "duration", role: "AXStaticText", label: "15분", actionable: false), ScreenElement(id: "remaining", role: "AXStaticText", label: remaining, actionable: false), ScreenElement(id: "pause", role: "AXButton", label: "일시 정지")])
    }
}
