import Foundation
import CoreGraphics

public struct WindowIdentity: Equatable, Sendable {
    public let title: String
    public let bounds: CGRect

    public init(title: String, bounds: CGRect) {
        self.title = title
        self.bounds = bounds
    }
}

public enum WindowSelection {
    public static func index(of expected: WindowIdentity, in windows: [WindowIdentity]) throws -> Int {
        let bounds = expected.bounds
        guard !bounds.isEmpty, [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite) else {
            throw PressError.message("Could not identify the active window bounds.")
        }
        let matches = windows.indices.filter { index in
            let candidate = windows[index]
            return candidate.title == expected.title &&
                abs(candidate.bounds.minX - bounds.minX) <= 1 && abs(candidate.bounds.minY - bounds.minY) <= 1 &&
                abs(candidate.bounds.width - bounds.width) <= 1 && abs(candidate.bounds.height - bounds.height) <= 1
        }
        guard matches.count == 1, let index = matches.first else {
            throw PressError.message("Could not uniquely identify the active window. No window image was captured.")
        }
        return index
    }
}
