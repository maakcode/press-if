import AppKit
import PressIfCore

@MainActor
enum DesktopKeyboard {
    static func type(_ text: String, verifyFocus: () throws -> Void) throws {
        for character in text {
            try Task.checkCancellation()
            try verifyFocus()
            let units = Array(String(character).utf16)
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true), let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else {
                throw PressError.message("Could not create a keyboard input event.")
            }
            units.withUnsafeBufferPointer { buffer in
                if let address = buffer.baseAddress {
                    down.keyboardSetUnicodeString(stringLength: units.count, unicodeString: address)
                    up.keyboardSetUnicodeString(stringLength: units.count, unicodeString: address)
                }
            }
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    static func press(_ keys: [String]) throws {
        try KeyCombination.validate(keys)
        let ordinary = keys.first { !KeyCombination.modifiers.contains($0) }!
        guard let code = codes[ordinary], let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true), let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else {
            throw PressError.message("This key combination is not supported.")
        }
        let modifiers: [String: CGEventFlags] = ["command": .maskCommand, "control": .maskControl, "option": .maskAlternate, "shift": .maskShift]
        let flags = keys.reduce(CGEventFlags()) { value, key in value.union(modifiers[key] ?? []) }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private static let codes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23,
        "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40,
        "n": 45, "m": 46, "return": 36, "tab": 48, "space": 49, "delete": 51, "escape": 53,
        "left": 123, "right": 124, "down": 125, "up": 126
    ]
}
