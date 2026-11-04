import XCTest
import CoreGraphics
@testable import PressIfCore

final class SecurityTests: XCTestCase {
    private let activeWindow = WindowIdentity(title: "Document", bounds: CGRect(x: 100, y: 200, width: 800, height: 600))

    func testCaptureSelectsFocusedWindowWithDuplicateTitle() throws {
        let other = WindowIdentity(title: activeWindow.title, bounds: CGRect(x: 1000, y: 200, width: 800, height: 600))
        XCTAssertEqual(try WindowSelection.index(of: activeWindow, in: [other, activeWindow]), 1)
    }

    func testCaptureNeverFallsBackToAnotherWindow() {
        let other = WindowIdentity(title: "Private document", bounds: activeWindow.bounds)
        XCTAssertThrowsError(try WindowSelection.index(of: activeWindow, in: [other]))
        XCTAssertThrowsError(try WindowSelection.index(of: activeWindow, in: []))
    }

    func testAmbiguousAndInvalidCaptureBoundsAreRejected() {
        XCTAssertThrowsError(try WindowSelection.index(of: activeWindow, in: [activeWindow, activeWindow]))
        let empty = WindowIdentity(title: "Document", bounds: .zero)
        XCTAssertThrowsError(try WindowSelection.index(of: empty, in: [empty]))
    }

    func testCaptureAllowsOnlyRoundingDifferences() throws {
        let rounded = WindowIdentity(title: activeWindow.title, bounds: activeWindow.bounds.offsetBy(dx: 0.5, dy: -0.5))
        let moved = WindowIdentity(title: activeWindow.title, bounds: activeWindow.bounds.offsetBy(dx: 10, dy: 0))
        XCTAssertEqual(try WindowSelection.index(of: activeWindow, in: [rounded]), 0)
        XCTAssertThrowsError(try WindowSelection.index(of: activeWindow, in: [moved]))
    }

    func testUntitledWindowsStillRequireUniqueBounds() throws {
        let window = WindowIdentity(title: "", bounds: activeWindow.bounds)
        XCTAssertEqual(try WindowSelection.index(of: window, in: [window]), 0)
        XCTAssertThrowsError(try WindowSelection.index(of: window, in: [window, window]))
    }

    func testCredentialsUseOnlySupportedExplicitSources() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("META_API_KEY='file-test-value'\n".utf8).write(to: url)
        XCTAssertNil(Credentials.load(environment: [:]))
        XCTAssertEqual(Credentials.load(environment: [:], envFile: url), "file-test-value")
        XCTAssertEqual(Credentials.load(environment: ["MODEL_API_KEY": "environment-test-value"], envFile: url), "environment-test-value")
        try Data("UNRELATED_KEY=ignored-test-value\n".utf8).write(to: url)
        XCTAssertNil(Credentials.load(environment: [:], envFile: url))
    }

    func testSavingSecuresAnExistingPublicTaskDirectory() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        let store = TaskStore(url: folder.appendingPathComponent("tasks.json"))
        try store.save([])
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: store.url.path)
        try store.save([])
        for (url, expected) in [(folder, 0o700), (store.url, 0o600)] {
            let mode = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
            XCTAssertEqual(mode?.intValue, expected)
        }
    }
}
