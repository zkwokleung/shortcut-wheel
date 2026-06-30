#!/usr/bin/env swift

// Renders the ShortcutWheel app icon and menu-bar template image straight from the
// app's own palette and geometry, so the icon is regenerable and stays in sync with
// the product. Run: `swift scripts/render-icons.swift`
//
// Geometry mirrors Sources/Overlay/WheelGeometry.swift (clockwise-from-top angles,
// constant-width wedge gaps) and the annular-sector trimming in
// Sources/Overlay/AnnularSector.swift. Palette mirrors the default wheel in
// Sources/Model/Wheel.swift.

import AppKit
import Foundation

// MARK: - Palette

let palette = [0x5B8DEF, 0x5BD6C0, 0x57B894, 0xEF6F6C, 0xE0A458, 0x9B8CEF]
let bgTop = 0x1C1F26
let bgBottom = 0x0E1014

func srgb(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha)
}

// MARK: - Wedge path (annular sector with constant-width gap)

/// A wedge between `innerR` and `outerR`, spanning `[startT, endT]` where angles are
/// measured clockwise from the top (12 o'clock). `gap` is the constant-width spoke
/// trimmed between neighbours, inset more at the inner arc than the outer one.
func wedgePath(center c: CGPoint, innerR: CGFloat, outerR: CGFloat,
               startT: CGFloat, endT: CGFloat, gap: CGFloat) -> NSBezierPath {
    let span = endT - startT
    let maxInset = span / 2 * 0.9
    let outerInset = min(gap / 2 / outerR, maxInset)
    let innerInset = min(gap / 2 / max(innerR, 1), maxInset)

    // y-up context: top is +y, so a clockwise-from-top angle t maps to (sin t, cos t).
    func pt(_ r: CGFloat, _ t: CGFloat) -> CGPoint {
        CGPoint(x: c.x + r * sin(t), y: c.y + r * cos(t))
    }

    let steps = 48
    let path = NSBezierPath()

    let oStart = startT + outerInset, oEnd = endT - outerInset
    path.move(to: pt(outerR, oStart))
    for i in 1...steps {
        path.line(to: pt(outerR, oStart + (oEnd - oStart) * CGFloat(i) / CGFloat(steps)))
    }

    let iStart = startT + innerInset, iEnd = endT - innerInset
    path.line(to: pt(innerR, iEnd))
    for i in 1...steps {
        path.line(to: pt(innerR, iEnd + (iStart - iEnd) * CGFloat(i) / CGFloat(steps)))
    }
    path.close()
    return path
}

// MARK: - Bitmap helper

func renderPNG(size: Int, draw: (CGFloat) -> Void) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                              isPlanar: false, colorSpaceName: .deviceRGB,
                              bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.clear.set()
    NSRect(x: 0, y: 0, width: size, height: size).fill(using: .copy)
    draw(CGFloat(size))
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// MARK: - App icon

func drawAppIcon(_ s: CGFloat) {
    let scale = s / 1024
    let c = CGPoint(x: s / 2, y: s / 2)

    // macOS "squircle": content inset ~100px on the 1024 grid, corner radius 22.37%.
    let inset = 100 * scale
    let side = s - 2 * inset
    let squircle = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: side, height: side),
                               xRadius: side * 0.2237, yRadius: side * 0.2237)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 40 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
    shadow.set()
    NSGradient(starting: srgb(bgBottom), ending: srgb(bgTop))!.draw(in: squircle, angle: 90)
    NSGraphicsContext.restoreGraphicsState()

    let outerR = 250 * scale, innerR = 104 * scale, hubR = 60 * scale
    let gap = 12 * scale
    let slice = 2 * CGFloat.pi / CGFloat(palette.count)

    for (i, hex) in palette.enumerated() {
        let center = CGFloat(i) * slice
        let path = wedgePath(center: c, innerR: innerR, outerR: outerR,
                             startT: center - slice / 2, endT: center + slice / 2, gap: gap)
        srgb(hex).setFill()
        path.fill()
        NSColor.white.withAlphaComponent(0.14).setStroke()
        path.lineWidth = 2 * scale
        path.stroke()
    }

    let hub = NSBezierPath(ovalIn: NSRect(x: c.x - hubR, y: c.y - hubR, width: 2 * hubR, height: 2 * hubR))
    srgb(bgBottom).setFill()
    hub.fill()
    NSColor.white.withAlphaComponent(0.18).setStroke()
    hub.lineWidth = 3 * scale
    hub.stroke()
}

// MARK: - Menu-bar template (monochrome, alpha-only)

func drawMenuBarIcon(_ s: CGFloat) {
    let c = CGPoint(x: s / 2, y: s / 2)
    let outerR = s * 0.46, innerR = s * 0.23
    let gap = s * 0.09
    let slice = 2 * CGFloat.pi / CGFloat(palette.count)

    NSColor.black.setFill()
    for i in 0..<palette.count {
        let center = CGFloat(i) * slice
        wedgePath(center: c, innerR: innerR, outerR: outerR,
                  startT: center - slice / 2, endT: center + slice / 2, gap: gap).fill()
    }
}

// MARK: - Output

let scriptDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
let root = scriptDir.deletingLastPathComponent()
let appIconDir = root.appendingPathComponent("Assets.xcassets/AppIcon.appiconset")
let menuBarDir = root.appendingPathComponent("Assets.xcassets/MenuBarIcon.imageset")
let fm = FileManager.default
try fm.createDirectory(at: appIconDir, withIntermediateDirectories: true)
try fm.createDirectory(at: menuBarDir, withIntermediateDirectories: true)

for size in [16, 32, 64, 128, 256, 512, 1024] {
    let data = renderPNG(size: size, draw: drawAppIcon)
    try data.write(to: appIconDir.appendingPathComponent("icon_\(size).png"))
    print("wrote AppIcon icon_\(size).png")
}

for size in [18, 36] {
    let data = renderPNG(size: size, draw: drawMenuBarIcon)
    try data.write(to: menuBarDir.appendingPathComponent("menubar_\(size).png"))
    print("wrote MenuBarIcon menubar_\(size).png")
}
