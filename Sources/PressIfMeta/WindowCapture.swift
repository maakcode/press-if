import AppKit
import ScreenCaptureKit
import Vision
import PressIfCore

struct CapturedWindow {
    let png: Data
    let bounds: CGRect
    let image: CGImage
}

@MainActor
enum WindowCapture {
    static func capture(pid: pid_t, expected: WindowIdentity) async throws -> CapturedWindow {
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        let windows = content.windows.filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width > 120 && $0.frame.height > 80 }
        let identities = windows.map { WindowIdentity(title: $0.title ?? "", bounds: $0.frame) }
        let window = windows[try WindowSelection.index(of: expected, in: identities)]
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = Double(filter.pointPixelScale)
        configuration.width = Int(window.frame.width * scale)
        configuration.height = Int(window.frame.height * scale)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        let preview = try modelPreview(image)
        guard let png = NSBitmapImageRep(cgImage: preview).representation(using: .png, properties: [:]) else {
            throw PressError.message("Could not capture the app window.")
        }
        return CapturedWindow(png: png, bounds: window.frame, image: image)
    }

    private static func modelPreview(_ image: CGImage) throws -> CGImage {
        guard image.width > 1400 else { return image }
        let height = Int((Double(image.height) * 1400 / Double(image.width)).rounded())
        guard let context = CGContext(data: nil, width: 1400, height: height, bitsPerComponent: 8, bytesPerRow: 1400 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw PressError.message("Could not prepare the window image.")
        }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1400, height: height))
        guard let preview = context.makeImage() else { throw PressError.message("Could not prepare the window image.") }
        return preview
    }

    static func textElements(in capture: CapturedWindow) throws -> [(String, CGRect)] {
        let requests = [Float(0), Float(1.0 / 32.0)].map { minimumTextHeight in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = false
            request.minimumTextHeight = minimumTextHeight
            return request
        }
        try VNImageRequestHandler(cgImage: capture.image).perform(requests)
        return requests.flatMap { $0.results ?? [] }.compactMap { result in
            guard let text = result.topCandidates(1).first, text.confidence >= 0.55 else { return nil }
            let box = result.boundingBox
            let bounds = CGRect(x: capture.bounds.minX + box.minX * capture.bounds.width,
                                y: capture.bounds.minY + (1 - box.maxY) * capture.bounds.height,
                                width: box.width * capture.bounds.width,
                                height: box.height * capture.bounds.height)
            return (text.string, bounds)
        }
    }
}
