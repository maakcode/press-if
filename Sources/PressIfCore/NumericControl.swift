import Foundation

public struct NumericControlState: Codable, Equatable, Sendable {
    public let value: Double
    public let valueDescription: String
    public let minimum: Double?
    public let maximum: Double?
    public let settable: Bool
    public let nativeScaleMatchesDisplay: Bool

    public init(value: Double, valueDescription: String, minimum: Double? = nil, maximum: Double? = nil, settable: Bool, nativeScaleMatchesDisplay: Bool = true) {
        self.value = value
        self.valueDescription = valueDescription
        self.minimum = minimum
        self.maximum = maximum
        self.settable = settable
        self.nativeScaleMatchesDisplay = nativeScaleMatchesDisplay
    }

    public static func read(valueText: String, valueDescription: String, minimum: Double?, maximum: Double?, settable: Bool) -> NumericControlState? {
        let raw = number(from: valueText)
        let displayed = number(from: valueDescription)
        guard let value = displayed ?? raw else { return nil }
        let directNumber = Double(valueText.trimmingCharacters(in: .whitespacesAndNewlines))
        let descriptionIsNumeric = valueDescription.isEmpty || Double(valueDescription.trimmingCharacters(in: .whitespacesAndNewlines)) == directNumber
        let sameScale = directNumber != nil && descriptionIsNumeric
        return NumericControlState(value: value, valueDescription: valueDescription.isEmpty ? valueText : valueDescription,
                                   minimum: sameScale ? minimum : nil, maximum: sameScale ? maximum : nil,
                                   settable: settable, nativeScaleMatchesDisplay: sameScale)
    }

    public static func number(from text: String) -> Double? {
        let scanner = Scanner(string: text)
        scanner.locale = Locale(identifier: "en_US_POSIX")
        guard let number = scanner.scanDouble(), number.isFinite else { return nil }
        let suffix = text[scanner.currentIndex...]
        let units = CharacterSet.letters.union(.whitespaces).union(CharacterSet(charactersIn: "%°"))
        guard suffix.unicodeScalars.allSatisfy({ units.contains($0) }) else { return nil }
        return number
    }
}

public enum NumericControlPolicy {
    public static let roles: Set<String> = ["AXSlider", "AXIncrementor"]

    public static func validateNumber(_ number: Double) throws {
        guard number.isFinite, number.rounded() == number, (0...9999).contains(number) else {
            throw PressError.message("Enter a whole number from 0 to 9999.")
        }
    }

    public static func validate(_ number: Double, on element: ScreenElement) throws {
        try validateNumber(number)
        guard element.actionable, roles.contains(element.role), let control = element.numericControl, control.settable else {
            throw PressError.message("Could not find an editable numeric control.")
        }
        guard control.value.isFinite,
              control.minimum.map({ $0.isFinite && number >= $0 }) ?? true,
              control.maximum.map({ $0.isFinite && number <= $0 }) ?? true else {
            throw PressError.message("The requested value is outside this control's range.")
        }
    }

    public static func verify(_ number: Double, on element: ScreenElement) throws {
        try validate(number, on: element)
        guard element.numericControl?.value == number else {
            let actual = element.numericControl?.valueDescription ?? element.value
            throw PressError.message("Stopped: the displayed value \(actual) does not match \(number.formatted()).")
        }
    }
}
