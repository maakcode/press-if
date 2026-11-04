import Foundation
import PressIfCore
import PressIfImaging

enum ImageLiveChecks {
    static func run(client: MetaClient, folder: URL) async -> [CheckResult] {
        var results: [CheckResult] = []
        do {
            let play = try ImageImport.reference(data: Data(contentsOf: folder.appendingPathComponent("play.png")), name: "play.png")
            let stop = try ImageImport.reference(data: Data(contentsOf: folder.appendingPathComponent("stop.png")), name: "stop.png")
            let document = RequestDocument(parts: [.text("5초 후 Image Match Lab 앱에서 "), .image(play), .text(" 누르고 1초 기다린 뒤 "), .image(stop), .text(" 눌러")])
            let plan = try await client.plan(document: document, apps: [AppIdentity(bundleID: "com.maakcode.press-if.image-fixture", name: "Image Match Lab")], now: Date(), timeZone: TimeZone(identifier: "Asia/Seoul")!)
            let ids = plan.steps.compactMap(\.referenceImageID)
            let correct = ids == [play.id, stop.id] && plan.schedule.kind == .after && plan.schedule.seconds == 5 && plan.steps.map(\.action) == [.launch, .click, .wait, .click]
            CheckMain.record("inline_image_order_and_step_binding", correct, String(decoding: try JSONEncoder().encode(plan), as: UTF8.self), to: &results)
            let scene = try Data(contentsOf: folder.appendingPathComponent("scene.png"))
            let source = try ImageImport.decode(scene)
            let playMatches = try ImageSearch.matches(reference: ImageImport.decode(play.png), screen: source)
            let stopMatches = try ImageSearch.matches(reference: ImageImport.decode(stop.png), screen: source)
            guard playMatches.count == 1, stopMatches.count == 1 else { throw PressError.message("Fixture search did not locate both icons uniquely") }
            let elements = [element(stopMatches[0], id: "candidate-0"), element(playMatches[0], id: "candidate-1")]
            let selection = try await client.select(step: ActionStep(action: .click, target: "첨부한 아이콘", referenceImageID: play.id), observation: ScreenObservation(app: "fixture", elements: elements), image: scene, reference: play)
            CheckMain.record("reference_and_current_screenshot_choose_unlabelled_icon", selection.elementID == "candidate-1", selection.reason, to: &results)
            let duplicate = try Data(contentsOf: folder.appendingPathComponent("duplicate.png"))
            let duplicateMatches = try ImageSearch.matches(reference: ImageImport.decode(play.png), screen: ImageImport.decode(duplicate))
            guard duplicateMatches.count == 2 else { throw PressError.message("Fixture must expose two distinct matching icons") }
            do {
                _ = try await client.select(step: ActionStep(action: .click, target: "첨부한 아이콘", referenceImageID: play.id), observation: ScreenObservation(app: "fixture", elements: duplicateMatches.enumerated().map { element($0.element, id: "candidate-\($0.offset)") }), image: duplicate, reference: play)
                CheckMain.record("ambiguous_duplicate_image_rejected", false, "Model selected an ambiguous match", to: &results)
            } catch PressError.targetUnavailable(let reason) {
                CheckMain.record("ambiguous_duplicate_image_rejected", true, reason, to: &results)
            }
        } catch { CheckMain.record("image_pipeline", false, error.localizedDescription, to: &results) }
        return results
    }

    private static func element(_ match: ImageMatch, id: String) -> ScreenElement {
        let box = match.normalizedRect
        let context = "normalized top-left x=\(box.minX), y=\(box.minY), width=\(box.width), height=\(box.height)"
        return ScreenElement(id: id, role: "ImageMatch", label: "첨부 이미지와 일치하는 영역", context: context)
    }
}
