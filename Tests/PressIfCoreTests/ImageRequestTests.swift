import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import PressIfCore
import PressIfImaging

final class ImageRequestTests: XCTestCase {
    func testTextAndImagesKeepExactOrderAcrossPersistence() throws {
        let first = try reference()
        let second = try reference(stop: true)
        let document = RequestDocument(parts: [.text("시계에서 "), .image(first), .text(" 누른 뒤 "), .image(second), .text(" 눌러")])
        try document.validate()
        let decoded = try JSONDecoder().decode(RequestDocument.self, from: JSONEncoder().encode(document))
        XCTAssertEqual(decoded, document)
        XCTAssertEqual(decoded.plainText, "시계에서 [Image 1] 누른 뒤 [Image 2] 눌러")
        XCTAssertEqual(decoded.images.map(\.id), [first.id, second.id])
    }

    func testPlanCannotDropOrInventImageReferences() throws {
        let image = try reference()
        let app = AppIdentity(bundleID: "test.app", name: "Test")
        let launch = ActionStep(action: .launch, appID: app.bundleID)
        func plan(_ id: String?) -> AutomationPlan {
            AutomationPlan(title: "이미지 버튼", schedule: ScheduleIntent(kind: .now), steps: [launch, ActionStep(action: .click, target: "재생", referenceImageID: id)], successCriteria: "재생됨")
        }
        XCTAssertThrowsError(try plan(nil).validate(apps: [app], referenceImages: [image]))
        XCTAssertThrowsError(try plan("invented").validate(apps: [app], referenceImages: [image]))
        XCTAssertNoThrow(try plan(image.id).validate(apps: [app], referenceImages: [image]))
    }

    func testOldTextOnlyJobsRemainReadable() throws {
        let plan = AutomationPlan(title: "기존 작업", schedule: ScheduleIntent(kind: .after, seconds: 60), steps: [ActionStep(action: .launch, appID: "com.apple.clock")], successCriteria: "창 표시")
        let job = ScheduledJob(request: "시계 열어", plan: plan, runAt: Date(), timeZone: .current)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? [String: Any])
        json.removeValue(forKey: "document")
        let decoded = try JSONDecoder().decode(ScheduledJob.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(decoded.document)
        XCTAssertEqual(decoded.request, job.request)
    }

    func testImageSurvivesSavedJobReload() throws {
        let image = try reference()
        let document = RequestDocument(parts: [.text("시계에서 "), .image(image), .text(" 눌러")])
        let plan = AutomationPlan(title: "이미지", schedule: ScheduleIntent(kind: .now), steps: [ActionStep(action: .launch, appID: "com.apple.clock"), ActionStep(action: .click, target: "버튼", referenceImageID: image.id)], successCriteria: "상태 변경")
        let store = TaskStore(url: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("tasks.json"))
        try store.save([ScheduledJob(request: document.plainText, plan: plan, runAt: Date(), timeZone: .current, document: document)])
        XCTAssertEqual(try store.load().first?.document, document)
    }

    func testInvalidAndDuplicateImagesRejected() throws {
        XCTAssertThrowsError(try ImageImport.reference(data: Data("not an image".utf8), name: "broken"))
        let image = try reference()
        XCTAssertThrowsError(try RequestDocument(parts: [.text("클릭"), .image(image), .image(image)]).validate())
    }

    func testFindsIconWithoutAnyText() throws {
        let icon = button()
        let screenshot = scene([(icon, CGRect(x: 79, y: 41, width: 32, height: 24))])
        let matches = try ImageSearch.matches(reference: icon, screen: screenshot)
        let match = try XCTUnwrap(matches.first)
        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(match.normalizedRect.minX * 220, 79, accuracy: 1)
        XCTAssertEqual(match.normalizedRect.minY * 160, 41, accuracy: 1)
    }

    func testRetinaReferenceFindsOneTimesScreen() throws {
        let actual = button()
        let retina = button(size: CGSize(width: 64, height: 48))
        let matches = try ImageSearch.matches(reference: retina, screen: scene([(actual, CGRect(x: 80, y: 40, width: 32, height: 24))]))
        let match = try XCTUnwrap(matches.first)
        XCTAssertEqual(match.normalizedRect.width * 220, 32, accuracy: 1)
        XCTAssertEqual(match.normalizedRect.height * 160, 24, accuracy: 1)
    }

    func testTwoIdenticalButtonsRemainTwoCandidates() throws {
        let icon = button()
        let screenshot = scene([(icon, CGRect(x: 31, y: 41, width: 32, height: 24)), (icon, CGRect(x: 143, y: 85, width: 32, height: 24))])
        let matches = try ImageSearch.matches(reference: icon, screen: screenshot)
        XCTAssertEqual(matches.count, 2)
    }

    func testSmallTransportButtonsOnRetinaWindow() throws {
        let frames = [CGRect(x: 816, y: 24, width: 72, height: 72), CGRect(x: 912, y: 24, width: 72, height: 72)]
        let screenshot = scene(frames.enumerated().map { index, frame in
            (button(size: frame.size, stop: index == 1), frame)
        }, size: CGSize(width: 3456, height: 192))
        for frame in frames {
            let icon = try XCTUnwrap(screenshot.cropping(to: frame))
            let matches = try ImageSearch.matches(reference: icon, screen: screenshot)
            XCTAssertEqual(matches.count, 1)
            let match = try XCTUnwrap(matches.first)
            XCTAssertEqual(match.normalizedRect.midX * Double(screenshot.width), frame.midX, accuracy: 2)
            XCTAssertEqual(match.normalizedRect.midY * Double(screenshot.height), frame.midY, accuracy: 2)
        }
    }

    func testSimilarColorWithDifferentSymbolIsNotMatch() throws {
        let matches = try ImageSearch.matches(reference: button(), screen: scene([(button(stop: true), CGRect(x: 79, y: 41, width: 32, height: 24))]))
        XCTAssertTrue(matches.isEmpty)
    }

    func testBlankImageDoesNotMatchBlankAreas() throws {
        let context = makeContext(width: 32, height: 24)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        XCTAssertTrue(try ImageSearch.matches(reference: context.makeImage()!, screen: scene([])).isEmpty)
    }

    private func reference(stop: Bool = false) throws -> ReferenceImage {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, button(stop: stop), nil)
        CGImageDestinationFinalize(destination)
        return try ImageImport.reference(data: data as Data, name: "button.png")
    }

    private func button(size: CGSize = CGSize(width: 32, height: 24), stop: Bool = false) -> CGImage {
        let context = makeContext(width: Int(size.width), height: Int(size.height))
        context.scaleBy(x: size.width / 32, y: size.height / 24)
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 32, height: 24))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        if stop { context.fill(CGRect(x: 10, y: 6, width: 12, height: 12)) }
        else {
            context.move(to: CGPoint(x: 11, y: 5))
            context.addLine(to: CGPoint(x: 24, y: 12))
            context.addLine(to: CGPoint(x: 11, y: 19))
            context.closePath()
            context.fillPath()
        }
        return context.makeImage()!
    }

    private func scene(_ buttons: [(CGImage, CGRect)], size: CGSize = CGSize(width: 220, height: 160)) -> CGImage {
        let context = makeContext(width: Int(size.width), height: Int(size.height))
        context.setFillColor(CGColor(gray: 0.93, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        for (button, frame) in buttons {
            let drawingFrame = CGRect(x: frame.minX, y: size.height - frame.maxY, width: frame.width, height: frame.height)
            context.draw(button, in: drawingFrame)
        }
        return context.makeImage()!
    }

    private func makeContext(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }
}
