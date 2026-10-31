// Park's DMG window: a quiet, precise surface in the spirit of Linear's installer.
// Writes background.png (1x), background@2x.png and layout.json for scripts/dmg-settings.py;
// with --preview, also preview.png: the window as Finder will show it, with the real icons.
//
// Usage: swift scripts/dmg-quiet.swift <out-dir> [--preview]
import AppKit

let args = CommandLine.arguments
let outDir = args[1]
let wantsPreview = args.contains("--preview")
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

// Layout, in points. Finder positions icons by their centers; labels sit below.
let window = CGSize(width: 640, height: 400)
let iconSize: CGFloat = 128
let appCenter = CGPoint(x: 200, y: 182)
let appsCenter = CGPoint(x: 440, y: 182)

let ink = NSColor(srgbRed: 0x1D / 255, green: 0x1D / 255, blue: 0x1F / 255, alpha: 1)
let sign = NSColor(srgbRed: 0x1E / 255, green: 0x50 / 255, blue: 0xA8 / 255, alpha: 1)

/// Draws into a bitmap of `size` points at `scale`, with a top-left origin (Finder's coordinates).
/// AppKit drawing (images, text) goes through a flipped graphics context so it comes out upright.
func render(_ size: CGSize = window, scale: CGFloat, _ draw: (CGContext) -> Void) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let cg = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    cg.translateBy(x: 0, y: size.height * scale)
    cg.scaleBy(x: scale, y: -scale)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: true)
    NSGraphicsContext.current!.imageInterpolation = .high
    draw(cg)
    NSGraphicsContext.restoreGraphicsState()
    rep.size = size   // set after drawing, so AppKit doesn't pre-scale the context
    return rep
}

func background(_ cg: CGContext, scale: CGFloat) {
    let hair = 1 / scale

    // Canvas.
    cg.setFillColor(NSColor.white.cgColor)
    cg.fill(CGRect(origin: .zero, size: window))

    // One inset surface, a hair cooler than the canvas.
    let surface = CGRect(x: 20, y: 20, width: window.width - 40, height: window.height - 40)
    let surfacePath = CGPath(roundedRect: surface, cornerWidth: 14, cornerHeight: 14, transform: nil)
    cg.saveGState()
    cg.addPath(surfacePath); cg.clip()
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let fill = CGGradient(colorsSpace: space, colors: [
        NSColor(srgbRed: 0.982, green: 0.986, blue: 0.992, alpha: 1).cgColor,
        NSColor(srgbRed: 0.962, green: 0.970, blue: 0.982, alpha: 1).cgColor,
    ] as CFArray, locations: [0, 1])!
    cg.drawLinearGradient(fill, start: CGPoint(x: 0, y: surface.minY), end: CGPoint(x: 0, y: surface.maxY), options: [])

    // A fine grid that dissolves toward the edges: drawn into a layer, then masked radially.
    let gridLayer = CGLayer(cg, size: CGSize(width: window.width * scale, height: window.height * scale), auxiliaryInfo: nil)!
    let g = gridLayer.context!
    g.scaleBy(x: scale, y: scale)
    let step: CGFloat = 10
    var x = surface.minX + step
    var column = 1
    while x < surface.maxX {
        let major = column % 5 == 0
        g.setStrokeColor(ink.withAlphaComponent(major ? 0.11 : 0.055).cgColor)
        g.setLineWidth(hair)
        let px = (x * scale).rounded() / scale + hair / 2   // pixel-aligned hairlines
        g.move(to: CGPoint(x: px, y: surface.minY)); g.addLine(to: CGPoint(x: px, y: surface.maxY)); g.strokePath()
        x += step; column += 1
    }
    var y = surface.minY + step
    var row = 1
    while y < surface.maxY {
        let major = row % 5 == 0
        g.setStrokeColor(ink.withAlphaComponent(major ? 0.11 : 0.055).cgColor)
        g.setLineWidth(hair)
        let py = (y * scale).rounded() / scale + hair / 2
        g.move(to: CGPoint(x: surface.minX, y: py)); g.addLine(to: CGPoint(x: surface.maxX, y: py)); g.strokePath()
        y += step; row += 1
    }
    // Radial falloff: the grid is clearest around the icons and fades out before the edges.
    let maskRep = render(scale: scale) { m in
        m.setFillColor(NSColor.black.cgColor); m.fill(CGRect(origin: .zero, size: window))
        let fade = CGGradient(colorsSpace: CGColorSpaceCreateDeviceGray(),
                              colors: [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0.55), CGColor(gray: 1, alpha: 0)] as CFArray,
                              locations: [0, 0.45, 1])!
        m.saveGState()
        m.translateBy(x: window.width / 2, y: 182)
        m.scaleBy(x: 1, y: 0.62)
        m.drawRadialGradient(fade, startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 330, options: [])
        m.restoreGState()
    }
    cg.saveGState()
    cg.clip(to: CGRect(origin: .zero, size: window), mask: alphaMask(from: maskRep))
    cg.draw(gridLayer, in: CGRect(origin: .zero, size: window))
    cg.restoreGState()
    cg.restoreGState()

    // Hairline edge on the surface, with a whisper of inner light on top.
    cg.addPath(surfacePath)
    cg.setStrokeColor(ink.withAlphaComponent(0.09).cgColor)
    cg.setLineWidth(hair)
    cg.strokePath()

    // Five chevrons between the icons, brightening toward Applications; only the last carries the brand blue.
    let gapStart = appCenter.x + iconSize / 2, gapEnd = appsCenter.x - iconSize / 2
    let count = 5, spacing: CGFloat = 14, w: CGFloat = 6.5, h: CGFloat = 13
    let total = CGFloat(count - 1) * spacing + w
    let firstX = (gapStart + gapEnd) / 2 - total / 2
    let alphas: [CGFloat] = [0.14, 0.26, 0.42, 0.62, 1]
    cg.setLineWidth(1.8)
    cg.setLineCap(.round); cg.setLineJoin(.round)
    for i in 0..<count {
        let cx = firstX + CGFloat(i) * spacing
        let color = i == count - 1 ? sign : ink.withAlphaComponent(alphas[i])
        cg.setStrokeColor(color.cgColor)
        cg.move(to: CGPoint(x: cx, y: appCenter.y - h / 2))
        cg.addLine(to: CGPoint(x: cx + w, y: appCenter.y))
        cg.addLine(to: CGPoint(x: cx, y: appCenter.y + h / 2))
        cg.strokePath()
    }
}

/// Turns a white-on-black rendering into an alpha mask image.
func alphaMask(from rep: NSBitmapImageRep) -> CGImage {
    let w = rep.pixelsWide, h = rep.pixelsHigh
    var bytes = [UInt8](repeating: 0, count: w * h)
    let data = rep.bitmapData!
    for i in 0..<(w * h) { bytes[i] = data[i * 4] }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    return CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: w,
                   space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGBitmapInfo(rawValue: 0),
                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)!
}

func write(_ rep: NSBitmapImageRep, _ name: String) {
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
}

try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
write(render(scale: 1) { background($0, scale: 1) }, "background.png")
let retina = render(scale: 2) { background($0, scale: 2) }
write(retina, "background@2x.png")
let layout: [String: Any] = [
    "style": "quiet", "window": [Int(window.width), Int(window.height)], "icon_size": Int(iconSize), "text_size": 13,
    "app": [Int(appCenter.x), Int(appCenter.y)], "applications": [Int(appsCenter.x), Int(appsCenter.y)],
]
try! JSONSerialization.data(withJSONObject: layout, options: [.prettyPrinted, .sortedKeys])
    .write(to: URL(fileURLWithPath: "\(outDir)/layout.json"))

// Preview: the window as Finder shows it, with the real icons and labels, on a neutral desk.
if wantsPreview {
    let appIcon = NSImage(contentsOf: root.appendingPathComponent("brand/app-icon-1024.png"))!
    let appsIcon = NSWorkspace.shared.icon(forFile: "/Applications")
    let titleBar: CGFloat = 28, margin: CGFloat = 60
    let canvas = CGSize(width: window.width + margin * 2, height: window.height + titleBar + margin * 2)
    let backgroundImage = NSImage(size: window); backgroundImage.addRepresentation(retina)
    let preview = render(canvas, scale: 2) { cg in
        NSColor(srgbRed: 0.93, green: 0.94, blue: 0.95, alpha: 1).setFill(); NSRect(origin: .zero, size: canvas).fill()
        let frame = NSRect(x: margin, y: margin, width: window.width, height: window.height + titleBar)
        let shape = NSBezierPath(roundedRect: frame, xRadius: 12, yRadius: 12)
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: 0, height: 12), blur: 30, color: NSColor.black.withAlphaComponent(0.22).cgColor)
        NSColor.white.setFill(); shape.fill()
        cg.restoreGState()
        cg.saveGState(); shape.addClip()
        NSColor(white: 0.985, alpha: 1).setFill(); NSRect(x: frame.minX, y: frame.minY, width: frame.width, height: titleBar).fill()
        let lights = [NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1), NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1),
                      NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1)]
        for (i, c) in lights.enumerated() {
            c.setFill(); NSBezierPath(ovalIn: NSRect(x: frame.minX + 12 + CGFloat(i) * 20, y: frame.minY + 8, width: 12, height: 12)).fill()
        }
        let title = NSAttributedString(string: "Park", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                                                                      .foregroundColor: NSColor(white: 0.3, alpha: 1)])
        title.draw(at: NSPoint(x: frame.midX - title.size().width / 2, y: frame.minY + 6))
        let content = NSRect(x: frame.minX, y: frame.minY + titleBar, width: window.width, height: window.height)
        backgroundImage.draw(in: content, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        for (icon, center, label) in [(appIcon, appCenter, "Park"), (appsIcon, appsCenter, "Applications")] {
            let r = NSRect(x: content.minX + center.x - iconSize / 2, y: content.minY + center.y - iconSize / 2,
                           width: iconSize, height: iconSize)
            icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            let text = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.black])
            text.draw(at: NSPoint(x: content.minX + center.x - text.size().width / 2, y: r.maxY + 4))
        }
        cg.restoreGState()
    }
    write(preview, "preview.png")
}
print("wrote \(outDir)")
