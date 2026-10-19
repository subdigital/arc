#!/usr/bin/env swift
// Draws the placeholder app icon and writes Resources/AppIcon.icns (needs iconutil).
// Usage: swift scripts/make-icon.swift
import AppKit

func render(size: Int) -> Data {
    let scale = CGFloat(size)
    let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        let inset = scale * 0.08
        let body = rect.insetBy(dx: inset, dy: inset)
        let path = NSBezierPath(roundedRect: body, xRadius: scale * 0.22, yRadius: scale * 0.22)
        NSGradient(colors: [NSColor(red: 0.43, green: 0.47, blue: 0.90, alpha: 1), NSColor(red: 0.30, green: 0.34, blue: 0.74, alpha: 1)])!
            .draw(in: path, angle: -90)

        // A status-style circle with a check mark.
        let circle = NSBezierPath(ovalIn: body.insetBy(dx: scale * 0.22, dy: scale * 0.22))
        NSColor.white.withAlphaComponent(0.95).setStroke()
        circle.lineWidth = scale * 0.045
        circle.stroke()
        let check = NSBezierPath()
        check.move(to: NSPoint(x: scale * 0.37, y: scale * 0.50))
        check.line(to: NSPoint(x: scale * 0.46, y: scale * 0.40))
        check.line(to: NSPoint(x: scale * 0.64, y: scale * 0.61))
        check.lineWidth = scale * 0.055
        check.lineCapStyle = .round
        check.lineJoinStyle = .round
        check.stroke()
        return true
    }
    let tiff = image.tiffRepresentation!
    return NSBitmapImageRep(data: tiff)!.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let output = root.appendingPathComponent("Resources/AppIcon.icns")
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try process.run()
process.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print("Wrote \(output.path)")
