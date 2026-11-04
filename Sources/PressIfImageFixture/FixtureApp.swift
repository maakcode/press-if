import AppKit

enum FixtureArt {
    static func button(stop: Bool, pixels: Int = 184) -> NSImage {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels * 76 / 92, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 92, y: CGFloat(pixels) / 92)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 92, height: 76).fill()
        NSColor(red: 0.2, green: 0.4, blue: 0.9, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 10, y: 10, width: 72, height: 56), xRadius: 12, yRadius: 12).fill()
        NSColor.white.setFill()
        if stop { NSRect(x: 34, y: 26, width: 24, height: 24).fill() }
        else {
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: 36, y: 22))
            arrow.line(to: NSPoint(x: 62, y: 38))
            arrow.line(to: NSPoint(x: 36, y: 54))
            arrow.close()
            arrow.fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: 92, height: 76))
        image.addRepresentation(bitmap)
        return image
    }

    static func png(_ image: NSImage) -> Data {
        NSBitmapImageRep(data: image.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    }

    static func export(to folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try png(button(stop: false)).write(to: folder.appendingPathComponent("play.png"))
        try png(button(stop: true)).write(to: folder.appendingPathComponent("stop.png"))
        let scene = NSImage(size: NSSize(width: 600, height: 320))
        scene.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 600, height: 320).fill()
        button(stop: false).draw(in: NSRect(x: 100, y: 120, width: 92, height: 76))
        button(stop: true).draw(in: NSRect(x: 380, y: 120, width: 92, height: 76))
        scene.unlockFocus()
        try png(scene).write(to: folder.appendingPathComponent("scene.png"))
        let duplicate = NSImage(size: NSSize(width: 600, height: 320))
        duplicate.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 600, height: 320).fill()
        button(stop: false).draw(in: NSRect(x: 100, y: 120, width: 92, height: 76))
        button(stop: false).draw(in: NSRect(x: 380, y: 120, width: 92, height: 76))
        duplicate.unlockFocus()
        try png(duplicate).write(to: folder.appendingPathComponent("duplicate.png"))
    }
}

final class IconCanvas: NSView {
    var onPlay: (() -> Void)?
    var onStop: (() -> Void)?
    let playFrame = NSRect(x: 100, y: 45, width: 92, height: 76)
    let stopFrame = NSRect(x: 380, y: 45, width: 92, height: 76)

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        FixtureArt.button(stop: false).draw(in: playFrame)
        FixtureArt.button(stop: true).draw(in: stopFrame)
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if playFrame.contains(point) { onPlay?() }
        if stopFrame.contains(point) { onStop?() }
    }
}

final class FixtureDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 340), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Image Match Lab"
        window.backgroundColor = .white
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 340))
        let heading = NSTextField(labelWithString: "이미지 버튼 실행 검증")
        heading.font = .systemFont(ofSize: 23, weight: .bold)
        heading.frame = NSRect(x: 40, y: 270, width: 520, height: 34)
        let status = NSTextField(labelWithString: "대기 중 · 아직 누른 버튼 없음")
        status.font = .systemFont(ofSize: 16)
        status.frame = NSRect(x: 40, y: 220, width: 520, height: 30)
        status.setAccessibilityIdentifier("image-fixture-result")
        let canvas = IconCanvas(frame: NSRect(x: 0, y: 40, width: 600, height: 160))
        canvas.onPlay = { status.stringValue = "이미지 버튼 실행 완료 · 재생 중" }
        canvas.onStop = { status.stringValue = "정지 버튼 실행 완료 · 정지됨" }
        content.addSubview(heading)
        content.addSubview(status)
        content.addSubview(canvas)
        window.contentView = content
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        self.window = window
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct FixtureMain {
    @MainActor static func main() throws {
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--export" {
            try FixtureArt.export(to: URL(fileURLWithPath: CommandLine.arguments[2]))
            return
        }
        let app = NSApplication.shared
        let delegate = FixtureDelegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
