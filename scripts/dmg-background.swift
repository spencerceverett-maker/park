// Renders the background for Park's disk image window, in one of several styles, plus the layout
// Finder needs (window size and icon positions) as layout.json, which scripts/dmg-settings.py reads.
//
// Usage: swift scripts/dmg-background.swift <out-dir> [--style=current|lot|dawn|editorial|menubar|ticket] [--preview]
//   → background.png (1x), background@2x.png, layout.json
//   --preview also writes preview.png: the background in a macOS window with the real icons and labels,
//   exactly as Finder will show it.
import AppKit
import CoreImage

let args = CommandLine.arguments
let outDir = args[1]
let style = args.first { $0.hasPrefix("--style=") }.map { String($0.dropFirst(8)) } ?? "current"
let wantsPreview = args.contains("--preview")
let repoRoot = FileManager.default.currentDirectoryPath   // run from the repository root, as release.sh does

// MARK: - Palette (the website's tokens)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let ink = rgb(0x1D1D1F), gray = rgb(0x6E6E73), gray2 = rgb(0x86868B), canvas = rgb(0xF5F5F7)
let sign = rgb(0x1E50A8), night = rgb(0x0B1B36), dusk = rgb(0x163E86), dawn = rgb(0x9CC0EA),
    horizon = rgb(0xCFE0F5), firstLight = rgb(0xE3EEFA)

// MARK: - Layout per style

struct Layout {
    var width: CGFloat, height: CGFloat
    var app: CGPoint, applications: CGPoint      // icon centers, top-left coordinates (Finder's)
    var iconSize: CGFloat = 112
    var textSize: CGFloat = 13
}

let layouts: [String: Layout] = [
    "current":   Layout(width: 640, height: 400, app: CGPoint(x: 180, y: 212), applications: CGPoint(x: 460, y: 212)),
    "lot":       Layout(width: 660, height: 440, app: CGPoint(x: 150, y: 318), applications: CGPoint(x: 452, y: 176), iconSize: 104),
    "dawn":      Layout(width: 660, height: 420, app: CGPoint(x: 196, y: 262), applications: CGPoint(x: 464, y: 262)),
    "editorial": Layout(width: 720, height: 420, app: CGPoint(x: 476, y: 214), applications: CGPoint(x: 628, y: 214), iconSize: 104),
    "menubar":   Layout(width: 660, height: 440, app: CGPoint(x: 196, y: 300), applications: CGPoint(x: 464, y: 300)),
    "ticket":    Layout(width: 660, height: 440, app: CGPoint(x: 196, y: 306), applications: CGPoint(x: 464, y: 306)),
]
guard let layout = layouts[style] else { fatalError("unknown style \(style); one of \(layouts.keys.sorted())") }
let W = layout.width, H = layout.height

// MARK: - Drawing helpers (top-left coordinates, in points)

func flip(_ top: CGFloat) -> CGFloat { H - top }
func rect(_ x: CGFloat, _ top: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x, y: H - top - h, width: w, height: h) }
func pt(_ x: CGFloat, _ top: CGFloat) -> CGPoint { CGPoint(x: x, y: H - top) }

@discardableResult
func text(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat = 0, top: CGFloat, width: CGFloat? = nil,
          align: NSTextAlignment = .center, tracking: CGFloat = 0, lineHeight: CGFloat? = nil) -> CGFloat {
    let para = NSMutableParagraphStyle(); para.alignment = align
    if let lineHeight { para.minimumLineHeight = lineHeight; para.maximumLineHeight = lineHeight }
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: tracking, .paragraphStyle: para])
    let w = width ?? W
    let h = str.boundingRect(with: NSSize(width: w, height: 1000), options: .usesLineFragmentOrigin).height
    str.draw(with: rect(x, top, w, h), options: .usesLineFragmentOrigin)
    return h
}

func sf(_ size: CGFloat, _ weight: NSFont.Weight, rounded: Bool = false, mono: Bool = false) -> NSFont {
    if mono { return NSFont.monospacedSystemFont(ofSize: size, weight: weight) }
    let f = NSFont.systemFont(ofSize: size, weight: weight)
    if rounded, let d = f.fontDescriptor.withDesign(.rounded) { return NSFont(descriptor: d, size: size)! }
    return f
}

var cg: CGContext { NSGraphicsContext.current!.cgContext }

/// Fine film grain, so large gradients don't band and flat surfaces feel physical. Seeded: renders are repeatable.
func grain(_ amount: CGFloat, in r: NSRect, seed: UInt64 = 7) {
    let k = cg.ctm.a   // device pixels per point
    let w = Int(r.width * k), h = Int(r.height * k)
    var state = seed
    var bytes = [UInt8](repeating: 0, count: w * h * 4)
    for i in 0..<(w * h) {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let v = UInt8((state >> 33) & 0xFF)
        bytes[i * 4] = v; bytes[i * 4 + 1] = v; bytes[i * 4 + 2] = v; bytes[i * 4 + 3] = 255
    }
    let provider = CGDataProvider(data: Data(bytes) as CFData)!
    let image = CGImage(width: w, height: h, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                        provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    cg.saveGState(); cg.setBlendMode(.softLight); cg.setAlpha(amount); cg.draw(image, in: r); cg.restoreGState()
}

func vgradient(_ stops: [(NSColor, CGFloat)], in r: NSRect) {
    NSGradient(colors: stops.map(\.0), atLocations: stops.map(\.1), colorSpace: .sRGB)!.draw(in: r, angle: -90)
}

/// A smooth arrow along a quadratic curve, with a small open chevron at the end.
func curvedArrow(from a: CGPoint, to b: CGPoint, control c: CGPoint, color: NSColor, width: CGFloat, head: CGFloat = 7, dash: [CGFloat]? = nil) {
    let path = NSBezierPath(); path.move(to: a); path.curve(to: b, controlPoint1: CGPoint(x: (a.x + 2 * c.x) / 3, y: (a.y + 2 * c.y) / 3),
                                                            controlPoint2: CGPoint(x: (b.x + 2 * c.x) / 3, y: (b.y + 2 * c.y) / 3))
    path.lineWidth = width; path.lineCapStyle = .round
    if let dash { path.setLineDash(dash, count: dash.count, phase: 0) }
    color.setStroke(); path.stroke()
    let angle = atan2(b.y - c.y, b.x - c.x)
    let chevron = NSBezierPath()
    chevron.move(to: CGPoint(x: b.x - head * cos(angle - 0.55), y: b.y - head * sin(angle - 0.55)))
    chevron.line(to: b)
    chevron.line(to: CGPoint(x: b.x - head * cos(angle + 0.55), y: b.y - head * sin(angle + 0.55)))
    chevron.lineWidth = width; chevron.lineCapStyle = .round; chevron.lineJoinStyle = .round
    chevron.stroke()
}

func symbol(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight, color: NSColor, center: CGPoint) {
    let config = NSImage.SymbolConfiguration(pointSize: size, weight: weight).applying(.init(paletteColors: [color]))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
    img.draw(in: NSRect(x: center.x - img.size.width / 2, y: center.y - img.size.height / 2, width: img.size.width, height: img.size.height))
}

// MARK: - Styles

/// The original: light canvas, instruction, dotted path, dashed bay.
func drawCurrent() {
    canvas.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    NSGradient(colors: [rgb(0xCFE0F5, 0.55), rgb(0xE3EEFA, 0.25), rgb(0xF5F5F7, 0)])!.draw(in: NSRect(x: 0, y: 0, width: W, height: 150), angle: 90)
    text("Park it in Applications", sf(22, .semibold), ink, top: 38, tracking: -0.4)
    text("Drag Park onto the Applications folder, then open it from there.", sf(13, .regular), gray, top: 72, tracking: -0.05)
    let bay = NSBezierPath(roundedRect: rect(460 - 78, 212 - 76, 156, 168), xRadius: 22, yRadius: 22)
    bay.lineWidth = 1.5; bay.setLineDash([6, 5], count: 2, phase: 0)
    rgb(0x1E50A8, 0.32).setStroke(); bay.stroke(); rgb(0x1E50A8, 0.035).setFill(); bay.fill()
    for i in 0..<9 {
        let t = CGFloat(i) / 8, from = pt(252, 206), to = pt(356, 206), c = pt(304, 188)
        let p = CGPoint(x: (1 - t) * (1 - t) * from.x + 2 * (1 - t) * t * c.x + t * t * to.x,
                        y: (1 - t) * (1 - t) * from.y + 2 * (1 - t) * t * c.y + t * t * to.y)
        let r: CGFloat = 1.6 + 0.6 * t
        rgb(0x1E50A8, 0.22 + 0.4 * t).setFill(); NSBezierPath(ovalIn: NSRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)).fill()
    }
    curvedArrow(from: pt(356, 206), to: pt(368, 206), control: pt(362, 206), color: rgb(0x1E50A8, 0.65), width: 2.2)
}

/// A top-down row of garage stalls: cool concrete, painted bays with numbers and wheel stops,
/// Applications parked in the middle bay, and a painted turn arrow leading Park in from the aisle.
func drawLot() {
    vgradient([(rgb(0xEEF0F3), 0), (rgb(0xE6E9ED), 0.6), (rgb(0xDFE3E8), 1)], in: NSRect(x: 0, y: 0, width: W, height: H))
    grain(0.2, in: NSRect(x: 0, y: 0, width: W, height: H), seed: 11)

    // Stalls: four painted lines make three bays, open toward the aisle below; a head line across the top.
    let paint = rgb(0x1E50A8, 0.88)
    let bayW: CGFloat = 150, top: CGFloat = 64, bottom: CGFloat = 268, lineW: CGFloat = 5
    let firstX = 452 - bayW * 1.5   // the middle bay is centered on the Applications icon
    paint.setFill()
    rect(firstX, top, bayW * 3 + lineW, lineW).fill()
    for i in 0...3 { rect(firstX + CGFloat(i) * bayW, top, lineW, bottom - top).fill() }
    for i in 0..<3 {
        let x = firstX + CGFloat(i) * bayW
        // Bay number, painted small near the head line.
        text(String(format: "%02d", i + 11), sf(11, .bold, mono: true), rgb(0x1E50A8, 0.6), x: x + 14, top: top + 14, width: 40, align: .left)
        // Wheel stop: a pale block with a short hard shadow.
        let stop = rect(x + bayW / 2 - 34, top + 16, 68, 9)
        cg.saveGState(); cg.setShadow(offset: CGSize(width: 0, height: -2), blur: 2, color: NSColor(white: 0, alpha: 0.18).cgColor)
        rgb(0xF6F7F9).setFill(); NSBezierPath(roundedRect: stop, xRadius: 3, yRadius: 3).fill()
        cg.restoreGState()
    }
    // The empty bays get a faint painted P, the reserved one is left clear for Applications.
    for i in [0, 2] {
        let x = firstX + CGFloat(i) * bayW
        text("P", sf(46, .heavy, rounded: true), rgb(0x1E50A8, 0.13), x: x, top: 140, width: bayW, align: .center)
    }

    // Aisle: a dashed center line, and a painted turn arrow from Park's spot up into the middle bay.
    let dash = NSBezierPath(); dash.move(to: pt(0, 392)); dash.line(to: pt(W, 392))
    dash.lineWidth = 3; dash.setLineDash([18, 14], count: 2, phase: 0); NSColor(white: 1, alpha: 0.9).setStroke(); dash.stroke()
    let turn = NSBezierPath()
    let a = pt(214, 318), c1 = pt(380, 318), b = pt(452, 262)
    turn.move(to: a); turn.curve(to: b, controlPoint1: c1, controlPoint2: pt(452, 300))
    turn.lineWidth = 9; turn.lineCapStyle = .butt; NSColor(white: 1, alpha: 0.95).setStroke(); turn.stroke()
    let head = NSBezierPath()
    head.move(to: CGPoint(x: b.x - 15, y: b.y - 1)); head.line(to: CGPoint(x: b.x, y: b.y + 22)); head.line(to: CGPoint(x: b.x + 15, y: b.y - 1)); head.close()
    NSColor(white: 1, alpha: 0.95).setFill(); head.fill()
    grain(0.3, in: NSRect(x: 0, y: 0, width: W, height: H), seed: 23)   // wear on the paint

    text("Pull in to Applications", sf(15, .semibold), ink, x: 28, top: 22, width: 220, align: .left, tracking: -0.2)
    text("Drag Park into the open bay.", sf(12, .regular), gray, x: 28, top: 42, width: 220, align: .left)
}

/// The website's hero: a Mac desktop just before sunrise, with one quiet arc carrying Park home.
func drawDawn() {
    vgradient([(night, 0), (dusk, 0.3), (sign, 0.52), (dawn, 0.78), (horizon, 0.93), (firstLight, 1)],
              in: NSRect(x: 0, y: 0, width: W, height: H))
    // First light on the horizon: a wide, low ellipse, the only highlight in the frame.
    let glow = NSGradient(colors: [rgb(0xF1F6FD, 0.75), rgb(0xE3EEFA, 0)])!
    glow.draw(fromCenter: pt(W / 2, H + 40), radius: 0, toCenter: pt(W / 2, H + 40), radius: 340, options: [])
    // A handful of stars still out, high and faint.
    for (x, top, r, a) in [(84.0, 34.0, 0.9, 0.55), (152, 92, 0.7, 0.4), (538, 28, 1.0, 0.5), (604, 74, 0.7, 0.35), (418, 46, 0.6, 0.35), (246, 22, 0.6, 0.3)] as [(CGFloat, CGFloat, CGFloat, CGFloat)] {
        NSColor(white: 1, alpha: a).setFill(); NSBezierPath(ovalIn: NSRect(x: x - r, y: flip(top) - r, width: 2 * r, height: 2 * r)).fill()
    }
    grain(0.16, in: NSRect(x: 0, y: 0, width: W, height: H), seed: 5)

    text("Park for Mac", sf(12, .semibold), NSColor(white: 1, alpha: 0.7), top: 44, tracking: 0.2)
    text("Bring it in before sunrise.", sf(24, .semibold), .white, top: 64, tracking: -0.5)
    text("Drag Park onto Applications, then open it from there.", sf(13, .regular), NSColor(white: 1, alpha: 0.72), top: 100, tracking: -0.05)

    // One arc from Park to Applications, over the top, like a car's path into a bay.
    curvedArrow(from: pt(250, 222), to: pt(410, 222), control: pt(330, 168), color: NSColor(white: 1, alpha: 0.85), width: 1.6, head: 8)
}

/// Editorial: one big quiet wordmark, the tagline, and the instruction set like a caption.
func drawEditorial() {
    vgradient([(rgb(0xFFFFFF), 0), (rgb(0xF5F5F7), 1)], in: NSRect(x: 0, y: 0, width: W, height: H))
    // Wordmark: "Park" in ink, the full stop in parking-sign blue.
    let word = NSMutableAttributedString(string: "Park", attributes: [.font: sf(120, .bold), .foregroundColor: ink, .kern: -6])
    word.append(NSAttributedString(string: ".", attributes: [.font: sf(120, .bold), .foregroundColor: sign]))
    word.draw(at: CGPoint(x: 44, y: flip(170)))
    text("Put a desktop away.\nPick it up later.", sf(17, .medium), gray, x: 50, top: 190, width: 300, align: .left, tracking: -0.2, lineHeight: 22)
    // Caption, bottom left, with a hairline above it.
    rgb(0xD2D2D7).setFill(); NSRect(x: 50, y: flip(352), width: 280, height: 0.5).fill()
    text("To install, drag Park onto the Applications folder.", sf(12, .regular), gray2, x: 50, top: 364, width: 320, align: .left)
    // Between the icons: a hairline arrow.
    curvedArrow(from: pt(536, 210), to: pt(568, 210), control: pt(552, 210), color: rgb(0x86868B), width: 1.2, head: 5)
    // A thin vertical rule separating story from action.
    rgb(0xE5E5EA).setFill(); NSRect(x: 396, y: flip(332), width: 0.5, height: 236).fill()
}

/// The top of a Mac: a slice of the dawn wallpaper with a real menu bar, Park's glyph highlighted
/// and a note pointing at it. Below, the install itself.
func drawMenubar() {
    canvas.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
    vgradient([(rgb(0xF5F5F7), 0), (rgb(0xEEF1F5), 1)], in: NSRect(x: 0, y: 0, width: W, height: flip(150)))
    // Wallpaper slice.
    let wall = rect(0, 0, W, 150)
    vgradient([(dusk, 0), (sign, 0.45), (dawn, 0.85), (horizon, 1)], in: wall)
    grain(0.14, in: wall, seed: 9)
    // Menu bar: translucent, white text, items in the real order.
    NSColor(white: 1, alpha: 0.2).setFill(); rect(0, 0, W, 26).fill()
    NSColor(white: 1, alpha: 0.25).setFill(); rect(0, 26, W, 0.5).fill()
    symbol("apple.logo", 13, .medium, color: .white, center: pt(22, 13))
    var x: CGFloat = 42
    for (i, item) in ["Finder", "File", "Edit", "View", "Go", "Window"].enumerated() {
        let font = sf(13, i == 0 ? .bold : .regular)
        let s = NSAttributedString(string: item, attributes: [.font: font, .foregroundColor: NSColor.white])
        s.draw(at: CGPoint(x: x, y: flip(13) - s.size().height / 2)); x += s.size().width + 16
    }
    let glyph = pt(W - 172, 13)
    NSColor(white: 1, alpha: 0.32).setFill()
    NSBezierPath(roundedRect: NSRect(x: glyph.x - 14, y: glyph.y - 10, width: 28, height: 20), xRadius: 5, yRadius: 5).fill()
    symbol("parkingsign.circle", 14, .medium, color: .white, center: glyph)
    symbol("wifi", 13, .medium, color: .white, center: pt(W - 134, 13))
    symbol("battery.75percent", 15, .regular, color: .white, center: pt(W - 100, 13))
    let clock = NSAttributedString(string: "9:41", attributes: [.font: sf(13, .medium), .foregroundColor: NSColor.white])
    clock.draw(at: CGPoint(x: W - 66, y: flip(13) - clock.size().height / 2))

    // Note under the glyph: a small frosted tag with a caret, the way macOS tooltips sit under menu bar items.
    let tag = rect(glyph.x - 92, 40, 184, 54)
    cg.saveGState(); cg.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: rgb(0x0B1B36, 0.28).cgColor)
    let tagPath = NSBezierPath(roundedRect: tag, xRadius: 12, yRadius: 12)
    let caret = NSBezierPath(); caret.move(to: CGPoint(x: glyph.x - 7, y: tag.maxY)); caret.line(to: CGPoint(x: glyph.x, y: tag.maxY + 7)); caret.line(to: CGPoint(x: glyph.x + 7, y: tag.maxY)); caret.close()
    NSColor(white: 1, alpha: 0.94).setFill(); tagPath.fill(); caret.fill()
    cg.restoreGState()
    text("Park lives up here.", sf(13, .semibold), ink, x: tag.minX, top: 49, width: tag.width, tracking: -0.1)
    text("Press ⌃⌥P to open it anytime.", sf(11.5, .regular), gray, x: tag.minX, top: 68, width: tag.width)

    text("Drag Park onto Applications to install it.", sf(15, .semibold), ink, top: 174, tracking: -0.2)
    curvedArrow(from: pt(266, 296), to: pt(392, 296), control: pt(329, 280), color: rgb(0x1E50A8, 0.75), width: 1.8, head: 7)
}

/// A parking ticket, printed for Park: a tactile stub with the essentials, then the install below.
func drawTicket() {
    vgradient([(rgb(0xF2F4F7), 0), (rgb(0xE8EBEF), 1)], in: NSRect(x: 0, y: 0, width: W, height: H))
    grain(0.12, in: NSRect(x: 0, y: 0, width: W, height: H), seed: 3)

    // The ticket, tilted by a hair so it reads as an object, not a panel.
    let tw: CGFloat = 400, th: CGFloat = 132
    let ticket = NSRect(x: (W - tw) / 2, y: flip(30) - th, width: tw, height: th)
    cg.saveGState()
    cg.translateBy(x: ticket.midX, y: ticket.midY); cg.rotate(by: -0.8 * .pi / 180); cg.translateBy(x: -ticket.midX, y: -ticket.midY)
    // Paper with notches at the perforation.
    let stubW: CGFloat = 112
    let perfX = ticket.minX + stubW
    let notchR: CGFloat = 9
    // Paper with two bites taken out at the perforation, cut with real path subtraction so the
    // shadow follows the notches too.
    let notches = CGMutablePath()
    notches.addEllipse(in: CGRect(x: perfX - notchR, y: ticket.maxY - notchR, width: 2 * notchR, height: 2 * notchR))
    notches.addEllipse(in: CGRect(x: perfX - notchR, y: ticket.minY - notchR, width: 2 * notchR, height: 2 * notchR))
    let paper = CGPath(roundedRect: ticket, cornerWidth: 10, cornerHeight: 10, transform: nil).subtracting(notches)
    cg.saveGState()
    cg.setShadow(offset: CGSize(width: 0, height: -8), blur: 22, color: rgb(0x0B1B36, 0.16).cgColor)
    cg.addPath(paper); cg.setFillColor(rgb(0xFDFDFE).cgColor); cg.fillPath()
    cg.restoreGState()
    cg.saveGState(); cg.addPath(paper); cg.clip()
    // Stub: parking-sign blue with the P.
    sign.setFill(); NSRect(x: ticket.minX, y: ticket.minY, width: stubW, height: th).fill()
    let p = NSAttributedString(string: "P", attributes: [.font: sf(64, .heavy, rounded: true), .foregroundColor: NSColor.white])
    p.draw(at: CGPoint(x: ticket.minX + (stubW - p.size().width) / 2, y: ticket.midY - p.size().height / 2 + 2))
    grain(0.18, in: ticket, seed: 31)   // paper tooth
    cg.restoreGState()
    // Perforation.
    let perf = NSBezierPath(); perf.move(to: CGPoint(x: perfX, y: ticket.minY + notchR + 3)); perf.line(to: CGPoint(x: perfX, y: ticket.maxY - notchR - 3))
    perf.lineWidth = 1.2; perf.setLineDash([2, 3.5], count: 2, phase: 0); rgb(0x1D1D1F, 0.25).setStroke(); perf.stroke()
    // Printed fields, monospaced like a real ticket printer.
    let left = perfX + 22
    func field(_ label: String, _ value: String, top: CGFloat) {
        let l = NSAttributedString(string: label, attributes: [.font: sf(9.5, .medium, mono: true), .foregroundColor: gray2, .kern: 0.8])
        let v = NSAttributedString(string: value, attributes: [.font: sf(11, .semibold, mono: true), .foregroundColor: ink])
        l.draw(at: CGPoint(x: left, y: ticket.maxY - top - l.size().height))
        v.draw(at: CGPoint(x: left + 74, y: ticket.maxY - top - v.size().height))
    }
    let title = NSAttributedString(string: "PARK FOR MAC", attributes: [.font: sf(13, .bold, mono: true), .foregroundColor: ink, .kern: 1.2])
    title.draw(at: CGPoint(x: left, y: ticket.maxY - 20 - title.size().height))
    field("ENTRY", "1.0", top: 48)
    field("BAY", "Applications", top: 68)
    field("RATE", "Free, forever", top: 88)
    // Barcode, right edge.
    var bx = ticket.maxX - 74
    var seed: UInt64 = 42
    while bx < ticket.maxX - 22 {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        let w: CGFloat = [1, 1, 2, 1, 3][Int((seed >> 40) % 5)]
        rgb(0x1D1D1F, 0.85).setFill(); NSRect(x: bx, y: ticket.minY + 22, width: w, height: th - 44).fill()
        bx += w + [1, 2, 1, 3][Int((seed >> 20) % 4)]
    }
    cg.restoreGState()

    text("Drag Park onto Applications to park it.", sf(13, .regular), gray, top: 190, tracking: -0.05)
    curvedArrow(from: pt(266, 302), to: pt(392, 302), control: pt(329, 286), color: rgb(0x1E50A8, 0.7), width: 1.8, head: 7)
}

// MARK: - Render

func renderBackground(scale k: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * k), pixelsHigh: Int(H * k), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)   // points, so the 2x image carries 144 dpi
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!; ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    switch style {
    case "lot": drawLot()
    case "dawn": drawDawn()
    case "editorial": drawEditorial()
    case "menubar": drawMenubar()
    case "ticket": drawTicket()
    default: drawCurrent()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

try! FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)
let bg1 = renderBackground(scale: 1), bg2 = renderBackground(scale: 2)
try! bg1.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/background.png"))
try! bg2.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/background@2x.png"))
let layoutJSON: [String: Any] = [
    "style": style, "window": [W, H], "icon_size": layout.iconSize, "text_size": layout.textSize,
    "app": [layout.app.x, layout.app.y], "applications": [layout.applications.x, layout.applications.y],
]
try! JSONSerialization.data(withJSONObject: layoutJSON, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: "\(outDir)/layout.json"))
print("wrote \(outDir)/background.png, background@2x.png, layout.json (\(style))")

// MARK: - Preview: the window as Finder will show it

if wantsPreview {
    let appIcon = NSImage(contentsOfFile: "\(repoRoot)/brand/app-icon-1024.png")!
    let appsIcon = NSWorkspace.shared.icon(forFile: "/Applications")   // the icon Finder shows for the alias
    let k: CGFloat = 2, margin: CGFloat = 56, titleBar: CGFloat = 28
    let PW = W + margin * 2, PH = H + titleBar + margin * 2
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(PW * k), pixelsHigh: Int(PH * k), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: PW, height: PH)
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!; ctx.imageInterpolation = .high
    NSGraphicsContext.current = ctx
    let c = ctx.cgContext
    // Desktop behind the window.
    NSGradient(colors: [rgb(0xDDE2E8), rgb(0xCDD3DB)])!.draw(in: NSRect(x: 0, y: 0, width: PW, height: PH), angle: -90)
    let win = NSRect(x: margin, y: margin, width: W, height: H + titleBar)
    let winPath = NSBezierPath(roundedRect: win, xRadius: 12, yRadius: 12)
    c.saveGState(); c.setShadow(offset: CGSize(width: 0, height: -16), blur: 44, color: NSColor(white: 0, alpha: 0.32).cgColor)
    NSColor.white.setFill(); winPath.fill(); c.restoreGState()
    c.saveGState(); winPath.addClip()
    // Title bar.
    rgb(0xF2F2F4).setFill(); NSRect(x: win.minX, y: win.maxY - titleBar, width: W, height: titleBar).fill()
    rgb(0xD8D8DC).setFill(); NSRect(x: win.minX, y: win.maxY - titleBar, width: W, height: 0.5).fill()
    for (i, color) in [rgb(0xFF5F57), rgb(0xFEBC2E), rgb(0x28C840)].enumerated() {
        color.setFill(); NSBezierPath(ovalIn: NSRect(x: win.minX + 14 + CGFloat(i) * 20, y: win.maxY - titleBar / 2 - 6, width: 12, height: 12)).fill()
    }
    let title = NSAttributedString(string: "Park", attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: rgb(0x4A4A4F)])
    title.draw(at: CGPoint(x: win.midX - title.size().width / 2, y: win.maxY - titleBar / 2 - title.size().height / 2))
    // Content: the 2x background, then icons and labels the way Finder draws them.
    let content = NSRect(x: win.minX, y: win.minY, width: W, height: H)
    NSImage(cgImage: bg2.cgImage!, size: NSSize(width: W, height: H)).draw(in: content)
    func place(_ icon: NSImage, _ label: String, _ center: CGPoint) {
        let s = layout.iconSize
        let cx = content.minX + center.x, cy = content.maxY - center.y
        icon.draw(in: NSRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s))
        let l = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: layout.textSize), .foregroundColor: NSColor(white: 0, alpha: 0.85)])
        l.draw(at: CGPoint(x: cx - l.size().width / 2, y: cy - s / 2 - 4 - l.size().height))
    }
    place(appIcon, "Park", layout.app)
    place(appsIcon, "Applications", layout.applications)
    c.restoreGState()
    NSColor(white: 0, alpha: 0.12).setStroke(); winPath.lineWidth = 0.5; winPath.stroke()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/preview.png"))
    print("wrote \(outDir)/preview.png")
}
