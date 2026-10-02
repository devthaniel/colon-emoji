// Renders Resources/AppIcon.icns. Usage: swift scripts/render_icon.swift
import AppKit

let canvasSize: CGFloat = 1024
// Apple's macOS icon grid: the tile is 824pt inside a 1024pt canvas, leaving room for the drop shadow.
let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let tileCornerRadius: CGFloat = 185

func renderMaster() -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvasSize), pixelsHigh: Int(canvasSize),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: tileCornerRadius, yRadius: tileCornerRadius)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -12)
    shadow.shadowBlurRadius = 28
    shadow.set()
    NSColor.black.setFill()
    tilePath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let background = NSGradient(colors: [
        NSColor(srgbRed: 1.00, green: 0.42, blue: 0.45, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.62, blue: 0.27, alpha: 1),
        NSColor(srgbRed: 1.00, green: 0.80, blue: 0.30, alpha: 1),
    ])!
    background.draw(in: tilePath, angle: 90)

    NSGraphicsContext.saveGraphicsState()
    tilePath.addClip()
    let sheen = NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
    sheen.draw(in: NSRect(x: tileRect.minX, y: tileRect.midY, width: tileRect.width, height: tileRect.height / 2), angle: -90)
    NSGraphicsContext.restoreGraphicsState()

    let colonDotDiameter: CGFloat = 118
    let colonCenterX = tileRect.minX + 205
    for dotCenterY in [tileRect.midY + 110, tileRect.midY - 110] {
        NSGraphicsContext.saveGraphicsState()
        let dotShadow = NSShadow()
        dotShadow.shadowColor = NSColor(srgbRed: 0.6, green: 0.15, blue: 0.1, alpha: 0.35)
        dotShadow.shadowOffset = NSSize(width: 0, height: -6)
        dotShadow.shadowBlurRadius = 10
        dotShadow.set()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: NSRect(
            x: colonCenterX - colonDotDiameter / 2, y: dotCenterY - colonDotDiameter / 2,
            width: colonDotDiameter, height: colonDotDiameter
        )).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    let emoji = "😄" as NSString
    let emojiAttributes: [NSAttributedString.Key: Any] = [.font: NSFont(name: "Apple Color Emoji", size: 400)!]
    let emojiSize = emoji.size(withAttributes: emojiAttributes)
    let emojiCenterX = tileRect.minX + 540
    NSGraphicsContext.saveGraphicsState()
    let emojiShadow = NSShadow()
    emojiShadow.shadowColor = NSColor(srgbRed: 0.6, green: 0.15, blue: 0.1, alpha: 0.35)
    emojiShadow.shadowOffset = NSSize(width: 0, height: -10)
    emojiShadow.shadowBlurRadius = 18
    emojiShadow.set()
    emoji.draw(at: NSPoint(x: emojiCenterX - emojiSize.width / 2, y: tileRect.midY - emojiSize.height / 2), withAttributes: emojiAttributes)
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}

func resized(_ master: NSBitmapImageRep, to pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels), from: .zero, operation: .copy, fraction: 1, respectFlipped: false, hints: nil)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

let projectDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let iconsetDir = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconsetDir)
try! FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let master = renderMaster()
for pointSize in [16, 32, 128, 256, 512] {
    try! resized(master, to: pointSize).write(to: iconsetDir.appendingPathComponent("icon_\(pointSize)x\(pointSize).png"))
    try! resized(master, to: pointSize * 2).write(to: iconsetDir.appendingPathComponent("icon_\(pointSize)x\(pointSize)@2x.png"))
}
try! master.representation(using: .png, properties: [:])!.write(to: projectDir.appendingPathComponent("Resources/AppIcon-1024.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconsetDir.path, "-o", projectDir.appendingPathComponent("Resources/AppIcon.icns").path]
try! iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "wrote Resources/AppIcon.icns" : "iconutil failed")
