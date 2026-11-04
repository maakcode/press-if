import XCTest
@testable import PressIfCore

final class NumericControlTests: XCTestCase {
    func testTimerPlanSupportsZeroAndMinuteComponents() throws {
        let app = AppIdentity(bundleID: "com.apple.clock", name: "Clock")
        let steps = [ActionStep(action: .launch, appID: app.bundleID),
                     ActionStep(action: .click, target: "타이머"),
                     ActionStep(action: .setValue, target: "시간", context: "타이머", number: 0),
                     ActionStep(action: .setValue, target: "분", context: "타이머", number: 15),
                     ActionStep(action: .setValue, target: "초", context: "타이머", number: 0),
                     ActionStep(action: .click, target: "시작")]
        let plan = AutomationPlan(title: "15분 타이머", schedule: ScheduleIntent(kind: .after, seconds: 5), steps: steps, successCriteria: "15분의 남은 시간이 감소한다")
        try plan.validate(apps: [app])
        XCTAssertEqual(try JSONDecoder().decode(AutomationPlan.self, from: JSONEncoder().encode(plan)), plan)
    }

    func testNumericInputRejectsInvalidValuesAndMissingTarget() {
        for value in [Double.nan, .infinity, -1, 1.5, 10000] {
            XCTAssertThrowsError(try NumericControlPolicy.validateNumber(value))
        }
        let app = AppIdentity(bundleID: "clock", name: "Clock")
        for step in [ActionStep(action: .setValue, target: "분"), ActionStep(action: .setValue, number: 15),
                     ActionStep(action: .setValue, target: "분", text: "15분", number: 15)] {
            let plan = AutomationPlan(title: "timer", schedule: ScheduleIntent(kind: .now), steps: [ActionStep(action: .launch, appID: app.bundleID), step], successCriteria: "running")
            XCTAssertThrowsError(try plan.validate(apps: [app]))
        }
    }

    func testNumericSelectionRejectsTextOCRDisabledAndReadOnlyControls() {
        for element in [slider(role: "OCRText"), slider(role: "AXTextField"), slider(actionable: false), slider(settable: false),
                        ScreenElement(id: "empty", role: "AXSlider", label: "분")] {
            XCTAssertThrowsError(try NumericControlPolicy.validate(15, on: element))
        }
        XCTAssertNoThrow(try NumericControlPolicy.validate(15, on: slider()))
    }

    func testObservedRangeIsEnforcedBeforeSettingValue() {
        XCTAssertNoThrow(try NumericControlPolicy.validate(0, on: slider()))
        XCTAssertNoThrow(try NumericControlPolicy.validate(59, on: slider()))
        XCTAssertThrowsError(try NumericControlPolicy.validate(60, on: slider()))
    }

    func testReportedSetterSuccessCannotReplaceActualReadback() {
        XCTAssertThrowsError(try NumericControlPolicy.verify(15, on: slider(value: 0)))
        XCTAssertThrowsError(try NumericControlPolicy.verify(15, on: slider(value: 16)))
        XCTAssertNoThrow(try NumericControlPolicy.verify(15, on: slider(value: 15)))
    }

    func testLocalizedNumericValuesDoNotConfuseCompositeTimes() {
        XCTAssertEqual(NumericControlState.number(from: "3시간"), 3)
        XCTAssertEqual(NumericControlState.number(from: "15분"), 15)
        XCTAssertEqual(NumericControlState.number(from: "0 seconds"), 0)
        XCTAssertNil(NumericControlState.number(from: "03:15:00"))
        XCTAssertNil(NumericControlState.number(from: "3시간 15분"))
        XCTAssertNil(NumericControlState.number(from: "타이머"))
    }

    func testTimerDisplayUnitsAreNotComparedToNativeSliderRange() throws {
        let state = try XCTUnwrap(NumericControlState.read(valueText: "0.25", valueDescription: "15분", minimum: 0, maximum: 1, settable: true))
        XCTAssertEqual(state.value, 15)
        XCTAssertFalse(state.nativeScaleMatchesDisplay)
        XCTAssertNil(state.minimum)
        XCTAssertNil(state.maximum)
        let element = ScreenElement(id: "minutes", role: "AXSlider", label: "", numericControl: state)
        XCTAssertNoThrow(try NumericControlPolicy.verify(15, on: element))
        XCTAssertThrowsError(try NumericControlPolicy.verify(16, on: element))
        let zero = try XCTUnwrap(NumericControlState.read(valueText: "0분", valueDescription: "", minimum: 0, maximum: 1, settable: true))
        XCTAssertEqual(zero.value, 0)
        XCTAssertFalse(zero.nativeScaleMatchesDisplay)
    }

    func testNativeNumericRangeIsRetainedWhenUnitsMatch() throws {
        let state = try XCTUnwrap(NumericControlState.read(valueText: "30", valueDescription: "", minimum: 0, maximum: 100, settable: true))
        XCTAssertEqual(state.value, 30)
        XCTAssertTrue(state.nativeScaleMatchesDisplay)
        XCTAssertEqual(state.minimum, 0)
        XCTAssertEqual(state.maximum, 100)
        let element = ScreenElement(id: "value", role: "AXSlider", label: "", numericControl: state)
        XCTAssertThrowsError(try NumericControlPolicy.validate(101, on: element))
    }

    func testExistingPlansAndObservationsDecodeWithoutNumericFields() throws {
        let step = try JSONDecoder().decode(ActionStep.self, from: Data(#"{"action":"input","text":"Press If"}"#.utf8))
        XCTAssertEqual(step.text, "Press If")
        XCTAssertNil(step.number)
        let element = try JSONDecoder().decode(ScreenElement.self, from: Data(#"{"id":"start","role":"AXButton","label":"시작","value":"","context":"","actionable":true}"#.utf8))
        XCTAssertNil(element.numericControl)
    }

    private func slider(role: String = "AXSlider", value: Double = 0, actionable: Bool = true, settable: Bool = true) -> ScreenElement {
        ScreenElement(id: "minutes", role: role, label: "", value: "\(value)분", context: "타이머", actionable: actionable,
                      numericControl: NumericControlState(value: value, valueDescription: "\(value)분", minimum: 0, maximum: 59, settable: settable))
    }
}
