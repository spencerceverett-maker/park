import AppKit
// Renders every social card direction; docs/social-preview.jpg is 04-full-bleed.
// Usage: build/Park.app/Contents/MacOS/Park --snapshot light.png --clear --3x
//        build/Park.app/Contents/MacOS/Park --snapshot dark.png --clear --3x --dark
//        swift scripts/social-cards.swift light.png dark.png docs/icon.png out-dir
import CoreImage

// Ten social-card directions built from the same parts: the real panel, the wallpaper, the icon, SF type.
let a = CommandLine.arguments
let lightPanel = NSImage(contentsOfFile: a[1])!, darkPanel = NSImage(contentsOfFile: a[2])!
let icon = NSImage(contentsOfFile: a[3])!
let outDir = a[4]
let k: CGFloat = 2, W: CGFloat = 1280, H: CGFloat = 640
let ci = CIContext()

func rgb(_ hex: UInt32, _ al: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: al)
}
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * k, y: (H - y - h) * k, width: w * k, height: h * k) }
var cg: CGContext { NSGraphicsContext.current!.cgContext }

enum Palette { case violet, dusk, mono, dawn }
func wallpaper(_ size: CGSize, _ p: Palette = .violet) -> CGImage {
    let base: NSColor, blobs: [(CGFloat, CGFloat, CGFloat, NSColor)]
    switch p {
    case .violet:
        base = rgb(0x2E2F9E)
        blobs = [(0.15, 0.85, 0.55, rgb(0x5B6CFF)), (0.75, 0.95, 0.5, rgb(0x8A5CF6)), (0.95, 0.35, 0.55, rgb(0x2EC5D3, 0.9)),
                 (0.35, 0.10, 0.6, rgb(0xFF9A7B, 0.95)), (0.60, 0.50, 0.35, rgb(0xC6B8FF, 0.7))]
    case .dusk:
        base = rgb(0x120F2E)
        blobs = [(0.2, 0.2, 0.5, rgb(0xFF7A59, 0.9)), (0.8, 0.3, 0.5, rgb(0x6D4AFF, 0.9)), (0.5, 0.9, 0.6, rgb(0x1E2A78)), (0.9, 0.9, 0.4, rgb(0xF2B8A0, 0.6))]
    case .dawn:
        // The website's hero: a Mac desktop just before sunrise, blues only (hue 211–219°).
        base = rgb(0x163E86)
        blobs = [(0.05, 1.00, 0.70, rgb(0x0B1B36)), (0.55, 0.85, 0.45, rgb(0x163E86)), (0.60, 0.45, 0.55, rgb(0x1E50A8)),
                 (0.85, 0.15, 0.55, rgb(0x9CC0EA)), (0.40, -0.05, 0.55, rgb(0xCFE0F5)), (0.95, -0.05, 0.35, rgb(0xE3EEFA, 0.9))]
    case .mono:
        base = rgb(0xD9DBE3)
        blobs = [(0.2, 0.8, 0.6, rgb(0xFFFFFF)), (0.8, 0.2, 0.6, rgb(0xB8BCCB)), (0.6, 0.6, 0.4, rgb(0xEEF0F6))]
    }
    var img = CIImage(color: CIColor(color: base)!).cropped(to: CGRect(origin: .zero, size: size))
    for (x, y, r, c) in blobs {
        let g = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: size.width * x, y: size.height * y), "inputRadius0": 0, "inputRadius1": max(size.width, size.height) * r,
            "inputColor0": CIColor(color: c)!, "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0)])!.outputImage!.cropped(to: img.extent)
        img = g.composited(over: img)
    }
    img = img.clampedToExtent().applyingGaussianBlur(sigma: 40).cropped(to: CGRect(origin: .zero, size: size))
    return ci.createCGImage(img, from: img.extent)!
}

@discardableResult
func text(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight, _ color: NSColor, x: CGFloat, y: CGFloat, tracking: CGFloat? = nil,
          width: CGFloat = 1100, lh: CGFloat? = nil, align: NSTextAlignment = .left, mono: Bool = false, rounded: Bool = false) -> CGFloat {
    var font = mono ? NSFont.monospacedSystemFont(ofSize: size * k, weight: weight) : NSFont.systemFont(ofSize: size * k, weight: weight)
    if rounded, let d = font.fontDescriptor.withDesign(.rounded) { font = NSFont(descriptor: d, size: size * k)! }
    let para = NSMutableParagraphStyle(); para.alignment = align
    if let lh { para.minimumLineHeight = lh * k; para.maximumLineHeight = lh * k }
    let t = tracking ?? (size >= 40 ? -size * 0.028 : size >= 20 ? -size * 0.01 : 0)
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: t * k, .paragraphStyle: para])
    let b = str.boundingRect(with: NSSize(width: width * k, height: 4000), options: [.usesLineFragmentOrigin])
    str.draw(with: NSRect(x: x * k, y: (H - y) * k - b.height, width: width * k, height: b.height), options: [.usesLineFragmentOrigin])
    return b.height / k
}

func symbol(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight, cx: CGFloat, cy: CGFloat, color: NSColor = .white) {
    let cfg = NSImage.SymbolConfiguration(pointSize: size * k, weight: weight).applying(.init(paletteColors: [color]))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) else { return }
    img.draw(at: NSPoint(x: cx * k - img.size.width / 2, y: (H - cy) * k - img.size.height / 2), from: .zero, operation: .sourceOver, fraction: 1)
}

/// Menu bar strip across `rect` (top-left points) with Park highlighted at `parkX`.
func menuBar(x: CGFloat, y: CGFloat, w: CGFloat, parkX: CGFloat, dark: Bool = false, clock: Bool = true) {
    (dark ? NSColor(white: 0, alpha: 0.25) : NSColor(white: 1, alpha: 0.22)).setFill(); R(x, y, w, 30).fill()
    NSColor(white: 1, alpha: 0.28).setFill()
    NSBezierPath(roundedRect: R(parkX - 15, y + 4, 30, 22), xRadius: 6 * k, yRadius: 6 * k).fill()
    symbol("parkingsign.circle", 15, .medium, cx: parkX, cy: y + 15)
    symbol("wifi", 14, .medium, cx: parkX + 42, cy: y + 15)
    symbol("battery.75percent", 15, .regular, cx: parkX + 78, cy: y + 15)
    if clock && parkX + 108 < x + w - 60 {
        let c = NSAttributedString(string: "Mon Jun 9  9:41 AM", attributes: [.font: NSFont.systemFont(ofSize: 13.5 * k, weight: .medium), .foregroundColor: NSColor.white])
        c.draw(at: NSPoint(x: (parkX + 108) * k, y: (H - y - 15) * k - c.size().height / 2))
    }
}

/// The real panel in frosted glass. `wall` is the image drawn in `wallRect` (device px) behind it.
func glassPanel(_ panel: NSImage, x: CGFloat, y: CGFloat, width: CGFloat, wall: CGImage?, wallRect: NSRect?, dark: Bool = false, shadow: CGFloat = 0.32) -> NSRect {
    let s = width / 340, h = panel.size.height / panel.size.width * width
    let rect = R(x, y, width, h), r = 14 * s * k
    let path = NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r)
    cg.saveGState(); cg.setShadow(offset: CGSize(width: 0, height: -14 * k), blur: 40 * k, color: NSColor(white: 0, alpha: shadow).cgColor)
    (dark ? rgb(0x1C1C1E) : .white).setFill(); path.fill(); cg.restoreGState()
    cg.saveGState(); path.addClip()
    if let wall, let wallRect {
        let local = CGRect(x: rect.minX - wallRect.minX, y: rect.minY - wallRect.minY, width: rect.width, height: rect.height)
        let f = CIImage(cgImage: wall).clampedToExtent().applyingGaussianBlur(sigma: 30 * k).cropped(to: local)
        if let g = ci.createCGImage(f, from: local) { cg.draw(g, in: rect) }
        (dark ? NSColor(white: 0.11, alpha: 0.72) : NSColor(white: 0.985, alpha: 0.72)).setFill(); rect.fill()
    }
    panel.draw(in: rect)
    cg.restoreGState()
    (dark ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 1, alpha: 0.7)).setStroke(); path.lineWidth = 1 * k; path.stroke()
    return rect
}

/// A rounded "screen" filled with wallpaper; returns the wallpaper and its device rect for glass sampling.
func screen(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, radius: CGFloat = 26, palette: Palette = .violet, shadow: Bool = true) -> (CGImage, NSRect) {
    let rect = R(x, y, w, h), path = NSBezierPath(roundedRect: rect, xRadius: radius * k, yRadius: radius * k)
    if shadow {
        cg.saveGState(); cg.setShadow(offset: CGSize(width: 0, height: -18 * k), blur: 50 * k, color: rgb(0x1D1D1F, 0.18).cgColor)
        rgb(0x2E2F9E).setFill(); path.fill(); cg.restoreGState()
    }
    let wall = wallpaper(rect.size, palette)
    cg.saveGState(); path.addClip(); cg.draw(wall, in: rect); cg.restoreGState()
    return (wall, rect)
}

func clip(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, radius: CGFloat, _ body: () -> Void) {
    cg.saveGState(); NSBezierPath(roundedRect: R(x, y, w, h), xRadius: radius * k, yRadius: radius * k).addClip(); body(); cg.restoreGState()
}

func fill(_ c: NSColor) { c.setFill(); NSRect(x: 0, y: 0, width: W * k, height: H * k).fill() }

/// A generic app window, used for "before" clutter.
func mockWindow(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, title: String, tint: NSColor) {
    let rect = R(x, y, w, h), path = NSBezierPath(roundedRect: rect, xRadius: 12 * k, yRadius: 12 * k)
    cg.saveGState(); cg.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 30 * k, color: NSColor(white: 0, alpha: 0.3).cgColor)
    NSColor(white: 0.98, alpha: 1).setFill(); path.fill(); cg.restoreGState()
    cg.saveGState(); path.addClip()
    rgb(0xECECEF).setFill(); R(x, y, w, 28).fill()
    for (i, c) in [rgb(0xFF5F57), rgb(0xFEBC2E), rgb(0x28C840)].enumerated() {
        c.setFill(); NSBezierPath(ovalIn: R(x + 12 + CGFloat(i) * 18, y + 9, 11, 11)).fill()
    }
    text(title, 12, .semibold, rgb(0x6E6E73), x: x + 72, y: y + 7)
    tint.withAlphaComponent(0.14).setFill(); R(x + 14, y + 42, w * 0.55, 14).fill()
    for i in 0..<5 { rgb(0xD8D8DE).setFill(); R(x + 14, y + 70 + CGFloat(i) * 22, w * (0.85 - CGFloat(i % 3) * 0.12), 9).fill() }
    tint.withAlphaComponent(0.5).setFill(); NSBezierPath(roundedRect: R(x + w - 120, y + h - 70, 100, 50), xRadius: 8 * k, yRadius: 8 * k).fill()
    cg.restoreGState()
}

let ink = rgb(0x1D1D1F), gray = rgb(0x86868B), body = rgb(0x6E6E73), canvas = rgb(0xF5F5F7)

func render(_ n: Int, _ name: String, _ draw: () -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * k), pixelsHigh: Int(H * k), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let g = NSGraphicsContext(bitmapImageRep: rep)!; g.imageInterpolation = .high; NSGraphicsContext.current = g
    draw()
    NSGraphicsContext.restoreGraphicsState()
    let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!
    try! jpg.write(to: URL(fileURLWithPath: "\(outDir)/\(String(format: "%02d", n))-\(name).jpg"))
    print(n, name, jpg.count / 1024, "KB")
}

// 1 — Apple product page: headline left, screen slice right.
render(1, "product-page") {
    fill(canvas)
    icon.draw(in: R(80, 150, 52, 52))
    text("Park for Mac", 21, .semibold, ink, x: 142, y: 163)
    text("Put a desktop away.", 58, .semibold, ink, x: 84, y: 232)
    text("Pick it up later.", 58, .semibold, gray, x: 84, y: 298)
    text("Close every window on a desktop to free up memory. Bring it all back, exactly as it was, in one click.", 21, .regular, body, x: 84, y: 392, width: 470, lh: 29)
    text("Free and open source", 17, .medium, ink, x: 84, y: 484)
    let (wall, wr) = screen(x: 668, y: 64, w: 700, h: 640)
    clip(x: 668, y: 64, w: 700, h: 640, radius: 26) {
        menuBar(x: 668, y: 64, w: 700, parkX: 1004)
        _ = glassPanel(lightPanel, x: 778, y: 101, width: 400, wall: wall, wallRect: wr)
    }
}

// 2 — Dark keynote: black canvas, white type, dusk wallpaper.
render(2, "keynote-dark") {
    fill(.black)
    icon.draw(in: R(80, 150, 52, 52))
    text("Park for Mac", 21, .semibold, .white, x: 142, y: 163)
    text("Put a desktop away.", 58, .semibold, .white, x: 84, y: 232)
    text("Pick it up later.", 58, .semibold, rgb(0x86868B), x: 84, y: 298)
    text("Close every window on a desktop to free up memory. Bring it all back, exactly as it was, in one click.", 21, .regular, rgb(0xA1A1A6), x: 84, y: 392, width: 470, lh: 29)
    text("Free and open source", 17, .medium, .white, x: 84, y: 484)
    let (wall, wr) = screen(x: 668, y: 64, w: 700, h: 640, palette: .dusk, shadow: false)
    clip(x: 668, y: 64, w: 700, h: 640, radius: 26) {
        menuBar(x: 668, y: 64, w: 700, parkX: 1004, dark: true)
        _ = glassPanel(darkPanel, x: 778, y: 101, width: 400, wall: wall, wallRect: wr, dark: true, shadow: 0.5)
    }
}

// 3 — Centered hero: headline on top, panel rising from the bottom edge.
render(3, "centered-hero") {
    fill(canvas)
    text("Park for Mac", 19, .semibold, gray, x: 0, y: 56, width: W, align: .center)
    text("Put a desktop away. Pick it up later.", 52, .semibold, ink, x: 0, y: 86, width: W, align: .center)
    let (wall, wr) = screen(x: 240, y: 190, w: 800, h: 520)
    clip(x: 240, y: 190, w: 800, h: 520, radius: 26) {
        menuBar(x: 240, y: 190, w: 800, parkX: 760)
        _ = glassPanel(lightPanel, x: 540, y: 227, width: 400, wall: wall, wallRect: wr)
    }
}

// 4 — Full bleed: wallpaper everywhere, white type on color, glass panel.
render(4, "full-bleed") {
    let wall = wallpaper(CGSize(width: W * k, height: H * k), .dawn); let wr = NSRect(x: 0, y: 0, width: W * k, height: H * k)
    cg.draw(wall, in: wr)
    menuBar(x: 0, y: 0, w: W, parkX: 960)
    icon.draw(in: R(80, 170, 52, 52))
    text("Park for Mac", 21, .semibold, .white, x: 142, y: 183)
    text("Put a desktop away.\nPick it up later.", 60, .semibold, .white, x: 84, y: 250, lh: 66)
    text("Free and open source", 18, .medium, NSColor(white: 1, alpha: 0.8), x: 84, y: 410)
    _ = glassPanel(lightPanel, x: 760, y: 37, width: 410, wall: wall, wallRect: wr)
}

// 5 — App Store minimal: big icon, name, one line.
render(5, "icon-minimal") {
    fill(canvas)
    cg.saveGState(); cg.setShadow(offset: CGSize(width: 0, height: -16 * k), blur: 40 * k, color: rgb(0x2E2F9E, 0.35).cgColor)
    icon.draw(in: R(W / 2 - 110, 92, 220, 220)); cg.restoreGState()
    text("Park", 76, .bold, ink, x: 0, y: 330, width: W, align: .center)
    text("Put a desktop away. Pick it up later.", 28, .medium, gray, x: 0, y: 432, width: W, align: .center)
    text("Free and open source for macOS", 18, .medium, body, x: 0, y: 520, width: W, align: .center)
}

// 6 — Before / after: cluttered desktop vs. a clean one with the panel.
render(6, "before-after") {
    fill(canvas)
    text("Park for Mac", 19, .semibold, gray, x: 0, y: 40, width: W, align: .center)
    text("Put a desktop away. Pick it up later.", 44, .semibold, ink, x: 0, y: 68, width: W, align: .center)
    let (wallA, _) = screen(x: 64, y: 170, w: 560, h: 410, radius: 20)
    _ = wallA
    clip(x: 64, y: 170, w: 560, h: 410, radius: 20) {
        menuBar(x: 64, y: 170, w: 560, parkX: 470, clock: false)
        mockWindow(x: 92, y: 220, w: 330, h: 230, title: "Onboarding redesign — Figma", tint: rgb(0xA259FF))
        mockWindow(x: 250, y: 280, w: 330, h: 230, title: "localhost:3000", tint: rgb(0x0A84FF))
        mockWindow(x: 160, y: 360, w: 300, h: 190, title: "api-server — zsh", tint: rgb(0x30D158))
    }
    let (wall, wr) = screen(x: 656, y: 170, w: 560, h: 410, radius: 20)
    clip(x: 656, y: 170, w: 560, h: 410, radius: 20) {
        menuBar(x: 656, y: 170, w: 560, parkX: 1062, clock: false)
        _ = glassPanel(lightPanel, x: 902, y: 207, width: 300, wall: wall, wallRect: wr)
    }
    text("Before", 15, .semibold, gray, x: 64, y: 594, width: 560, align: .center)
    text("After: 2.3 GB back", 15, .semibold, ink, x: 656, y: 594, width: 560, align: .center)
}

// 7 — Typographic: one huge word.
render(7, "typographic") {
    fill(canvas)
    text("Park.", 230, .bold, ink, x: 70, y: 120, tracking: -9)
    text("Put a desktop away. Pick it up later.", 30, .semibold, ink, x: 84, y: 432)
    text("A free, open-source menu bar app for Mac.", 22, .regular, gray, x: 84, y: 478)
    let (wall, wr) = screen(x: 860, y: 90, w: 470, h: 600, radius: 24)
    clip(x: 860, y: 90, w: 470, h: 600, radius: 24) {
        menuBar(x: 860, y: 90, w: 470, parkX: 1060, clock: false)
        _ = glassPanel(lightPanel, x: 896, y: 127, width: 340, wall: wall, wallRect: wr)
    }
}

// 8 — The number: memory freed as the headline.
render(8, "memory-stat") {
    fill(canvas)
    text("Park for Mac", 19, .semibold, gray, x: 84, y: 140)
    text("2.3 GB", 132, .bold, ink, x: 78, y: 170, tracking: -5)
    text("back, in one click.", 52, .semibold, gray, x: 84, y: 330)
    text("Park closes every window on a desktop and reopens it all, exactly as it was, when you need it.", 20, .regular, body, x: 84, y: 420, width: 500, lh: 28)
    let (wall, wr) = screen(x: 668, y: 64, w: 700, h: 640)
    clip(x: 668, y: 64, w: 700, h: 640, radius: 26) {
        menuBar(x: 668, y: 64, w: 700, parkX: 1004)
        _ = glassPanel(lightPanel, x: 778, y: 101, width: 400, wall: wall, wallRect: wr)
    }
}

// 9 — Spec sheet: panel with technical callouts in mono, Pinterest-trend style.
render(9, "spec-sheet") {
    fill(rgb(0xEDEDF0))
    rgb(0xD9D9DE).setFill()
    for i in stride(from: CGFloat(0), through: W, by: 40) { R(i, 0, 0.5, H).fill() }
    for j in stride(from: CGFloat(0), through: H, by: 40) { R(0, j, W, 0.5).fill() }
    let (wall, wr) = screen(x: 420, y: 70, w: 440, h: 500, radius: 22, palette: .mono, shadow: true)
    var panelRect = NSRect.zero
    clip(x: 420, y: 70, w: 440, h: 500, radius: 22) {
        menuBar(x: 420, y: 70, w: 440, parkX: 640, clock: false)
        panelRect = glassPanel(lightPanel, x: 470, y: 107, width: 340, wall: wall, wallRect: wr, shadow: 0.2)
    }
    func callout(_ label: String, _ detail: String, from: CGPoint, to: CGPoint, right: Bool) {
        let path = NSBezierPath(); path.move(to: NSPoint(x: from.x * k, y: (H - from.y) * k)); path.line(to: NSPoint(x: to.x * k, y: (H - to.y) * k))
        ink.withAlphaComponent(0.5).setStroke(); path.lineWidth = 1 * k; path.stroke()
        ink.setFill(); NSBezierPath(ovalIn: R(from.x - 3, from.y - 3, 6, 6)).fill()
        let x = right ? to.x + 10 : to.x - 230
        text(label, 12, .semibold, ink, x: x, y: to.y - 18, width: 220, align: right ? .left : .right, mono: true)
        text(detail, 12, .regular, body, x: x, y: to.y, width: 220, align: right ? .left : .right, mono: true)
    }
    callout("[01] PARK", "Every window on this desktop", from: CGPoint(x: 560, y: 160), to: CGPoint(x: 380, y: 160), right: false)
    callout("[02] PARKED", "Tabs, files and folders, saved", from: CGPoint(x: 520, y: 270), to: CGPoint(x: 380, y: 300), right: false)
    callout("[03] MEMORY", "2.3 GB freed", from: CGPoint(x: 780, y: 270), to: CGPoint(x: 900, y: 250), right: true)
    callout("[04] RESTORE", "Exactly as it was", from: CGPoint(x: 770, y: 330), to: CGPoint(x: 900, y: 380), right: true)
    _ = panelRect
    text("PARK FOR MAC", 13, .semibold, ink, x: 40, y: 32, mono: true)
    text("FREE · OPEN SOURCE", 13, .regular, body, x: 1060, y: 32, width: 180, align: .right, mono: true)
    text("Put a desktop away. Pick it up later.", 30, .semibold, ink, x: 0, y: 588, width: W, align: .center)
}

// 10 — Glass card on color: the panel floats alone, headline beneath, soft dusk field.
render(10, "floating-glass") {
    let wall = wallpaper(CGSize(width: W * k, height: H * k), .dusk); let wr = NSRect(x: 0, y: 0, width: W * k, height: H * k)
    cg.draw(wall, in: wr)
    _ = glassPanel(darkPanel, x: 120, y: 112, width: 430, wall: wall, wallRect: wr, dark: true, shadow: 0.55)
    icon.draw(in: R(660, 176, 56, 56))
    text("Put a desktop away.\nPick it up later.", 56, .semibold, .white, x: 660, y: 256, lh: 62)
    text("Park for Mac · Free and open source", 19, .medium, NSColor(white: 1, alpha: 0.7), x: 660, y: 400)
}
