import ApplicationServices
import Foundation
import PressIfCore

@MainActor
enum DesktopNumericControl {
    static func state(of element: AXUIElement) -> NumericControlState? {
        guard let role = attribute(element, kAXRoleAttribute) as? String, NumericControlPolicy.roles.contains(role) else { return nil }
        let raw = attribute(element, kAXValueAttribute)
        let valueText = (raw as? String) ?? (raw as? NSNumber)?.stringValue ?? ""
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable)
        let description = attribute(element, kAXValueDescriptionAttribute) as? String ?? ""
        return NumericControlState.read(valueText: valueText, valueDescription: description,
                                        minimum: number(attribute(element, kAXMinValueAttribute)),
                                        maximum: number(attribute(element, kAXMaxValueAttribute)),
                                        settable: result == .success && settable.boolValue)
    }

    static func writeNumber(_ number: Double, to element: AXUIElement) throws -> Bool {
        guard state(of: element)?.nativeScaleMatchesDisplay == true,
              attribute(element, kAXValueAttribute) is NSNumber else { return false }
        guard AXUIElementSetAttributeValue(element, kAXValueAttribute as CFString, NSNumber(value: number)) == .success else {
            throw PressError.message("Could not set the numeric control.")
        }
        return true
    }

    private static func number(_ value: CFTypeRef?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return NumericControlState.number(from: text) }
        return nil
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }
}
