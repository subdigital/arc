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
        NSGradient(colors: [NSColor(red: 0.16, green: 0.16, blue: 0.20, alpha: 1), NSColor(red: 0.06, green: 0.06, blue: 0.08, alpha: 1)])!
            .draw(in: path, angle: -90)
        NSColor(white: 1, alpha: 0.08).setStroke()
        path.lineWidth = max(1, scale * 0.006)
        path.stroke()

        // A simple arc in the accent color.
        let center = NSPoint(x: scale * 0.5, y: scale * 0.29)
        let arc = NSBezierPath()
        arc.appendArc(withCenter: center, radius: scale * 0.30, startAngle: 20, endAngle: 160)
        arc.lineWidth = scale * 0.085
        arc.lineCapStyle = .round
        NSColor(red: 0.45, green: 0.50, blue: 0.95, alpha: 1).setStroke()
        arc.stroke()
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
