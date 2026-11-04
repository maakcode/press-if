import AppKit

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let formats = [(16, "icon_16x16"), (32, "icon_16x16@2x"), (32, "icon_32x32"), (64, "icon_32x32@2x"), (128, "icon_128x128"), (256, "icon_128x128@2x"), (256, "icon_256x256"), (512, "icon_256x256@2x"), (512, "icon_512x512"), (1024, "icon_512x512@2x")]
for (pixels, name) in formats {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let background = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 200, yRadius: 200)
    NSColor(srgbRed: 0.98, green: 0.98, blue: 0.98, alpha: 1).setFill()
    background.fill()
    NSColor(srgbRed: 0.898, green: 0.898, blue: 0.898, alpha: 1).setStroke()
    background.lineWidth = 3
    background.stroke()
    let arrow = NSBezierPath()
    arrow.move(to: NSPoint(x: 288, y: 770))
    arrow.line(to: NSPoint(x: 302, y: 310))
    arrow.line(to: NSPoint(x: 420, y: 421))
    arrow.line(to: NSPoint(x: 505, y: 249))
    arrow.line(to: NSPoint(x: 610, y: 300))
    arrow.line(to: NSPoint(x: 526, y: 468))
    arrow.line(to: NSPoint(x: 690, y: 486))
    arrow.close()
    NSColor(srgbRed: 0.09, green: 0.09, blue: 0.09, alpha: 1).setFill()
    arrow.fill()
    NSColor(srgbRed: 16.0 / 255, green: 78.0 / 255, blue: 100.0 / 255, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 617, y: 611, width: 208, height: 208)).fill()
    let hand = NSBezierPath()
    hand.move(to: NSPoint(x: 721, y: 768))
    hand.line(to: NSPoint(x: 721, y: 714))
    hand.line(to: NSPoint(x: 760, y: 689))
    hand.lineWidth = 18
    hand.lineCapStyle = .round
    hand.lineJoinStyle = .round
    NSColor.white.setStroke()
    hand.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
}
