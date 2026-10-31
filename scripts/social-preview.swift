import AppKit
// Usage: build/Park.app/Contents/MacOS/Park --snapshot panel.png --clear --3x
//        swift scripts/social-preview.swift panel.png docs/icon.png out@2x.png
import CoreImage

// Apple-style social card: headline left, a slice of a Mac screen right with the real Park panel in glass.
let args = CommandLine.arguments
let panelImage = NSImage(contentsOfFile: args[1])!
let iconImage = NSImage(contentsOfFile: args[2])!
let out = args[3]
let k: CGFloat = 2                       // render at 2x, 1280×640 points
let W: CGFloat = 1280, H: CGFloat = 640

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
// Top-left coordinates, like a design tool.
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * k, y: (H - y - h) * k, width: w * k, height: h * k) }

// --- Wallpaper: soft color field in the icon's indigo family, warmed at the bottom.
func wallpaper(size: CGSize) -> CGImage {
    let ctx = CIContext()
    var image = CIImage(color: CIColor(color: rgb(0x2E2F9E))!).cropped(to: CGRect(origin: .zero, size: size))
    let blobs: [(CGFloat, CGFloat, CGFloat, NSColor)] = [
        (0.15, 0.85, 0.55, rgb(0x5B6CFF)), (0.75, 0.95, 0.5, rgb(0x8A5CF6)),
        (0.95, 0.35, 0.55, rgb(0x2EC5D3, 0.9)), (0.35, 0.10, 0.6, rgb(0xFF9A7B, 0.95)),
        (0.60, 0.50, 0.35, rgb(0xC6B8FF, 0.7)),
    ]
    for (x, y, r, c) in blobs {
        let g = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: size.width * x, y: size.height * y),
            "inputRadius0": 0, "inputRadius1": size.width * r,
            "inputColor0": CIColor(color: c)!, "inputColor1": CIColor(red: 0, green: 0, blue: 0, alpha: 0),
        ])!.outputImage!.cropped(to: image.extent)
        image = g.composited(over: image)
    }
    image = image.clampedToExtent().applyingGaussianBlur(sigma: 40).cropped(to: CGRect(origin: .zero, size: size))
    return ctx.createCGImage(image, from: image.extent)!
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W * k), pixelsHigh: Int(H * k), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let gctx = NSGraphicsContext(bitmapImageRep: rep)!
gctx.imageInterpolation = .high
NSGraphicsContext.current = gctx
let cg = gctx.cgContext

// Canvas: Apple's light product-page gray.
rgb(0xF5F5F7).setFill(); NSRect(x: 0, y: 0, width: W * k, height: H * k).fill()

// --- Text column
func text(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, x: CGFloat, y: CGFloat, tracking: CGFloat = 0, width: CGFloat = 1000, lineHeight: CGFloat? = nil) {
    let font = NSFont.systemFont(ofSize: size * k, weight: weight)
    let para = NSMutableParagraphStyle()
    if let lineHeight { para.minimumLineHeight = lineHeight * k; para.maximumLineHeight = lineHeight * k }
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .kern: tracking * k, .paragraphStyle: para])
    let bounds = str.boundingRect(with: NSSize(width: width * k, height: 2000), options: [.usesLineFragmentOrigin])
    str.draw(with: NSRect(x: x * k, y: (H - y) * k - bounds.height, width: width * k, height: bounds.height), options: [.usesLineFragmentOrigin])
}

let left: CGFloat = 84
iconImage.draw(in: R(left - 4, 150, 52, 52))
text("Park for Mac", size: 21, weight: .semibold, color: rgb(0x1D1D1F), x: left + 58, y: 163, tracking: -0.2)
text("Put a desktop away.", size: 58, weight: .semibold, color: rgb(0x1D1D1F), x: left, y: 232, tracking: -1.6)
text("Pick it up later.", size: 58, weight: .semibold, color: rgb(0x86868B), x: left, y: 298, tracking: -1.6)
text("Close every window on a desktop to free up memory. Bring it all back, exactly as it was, in one click.",
     size: 21, weight: .regular, color: rgb(0x6E6E73), x: left, y: 392, tracking: -0.1, width: 470, lineHeight: 29)
text("Free and open source", size: 17, weight: .medium, color: rgb(0x1D1D1F), x: left, y: 484, tracking: -0.1)

// --- Screen slice, bleeding off the right and bottom edges.
let screen = R(668, 64, 700, 640)
let screenPath = NSBezierPath(roundedRect: screen, xRadius: 26 * k, yRadius: 26 * k)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -18 * k), blur: 50 * k, color: rgb(0x1D1D1F, 0.18).cgColor)
rgb(0x2E2F9E).setFill(); screenPath.fill()
cg.restoreGState()
let wall = wallpaper(size: CGSize(width: screen.width, height: screen.height))
cg.saveGState(); screenPath.addClip()
cg.draw(wall, in: screen)

// Menu bar: frosted strip.
let barH: CGFloat = 30
let bar = R(668, 64, 700, barH)
NSColor(white: 1, alpha: 0.22).setFill(); bar.fill()
func symbol(_ name: String, _ size: CGFloat, _ weight: NSFont.Weight, at p: NSPoint, color: NSColor = .white) {
    let config = NSImage.SymbolConfiguration(pointSize: size * k, weight: weight).applying(.init(paletteColors: [color]))
    guard let img = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return }
    img.draw(at: NSPoint(x: p.x - img.size.width / 2, y: p.y - img.size.height / 2), from: .zero, operation: .sourceOver, fraction: 1)
}
let barMidY = (H - 64 - barH / 2) * k
// Park's icon, highlighted because its panel is open.
let parkX: CGFloat = 1004
NSColor(white: 1, alpha: 0.28).setFill()
NSBezierPath(roundedRect: NSRect(x: (parkX - 15) * k, y: barMidY - 11 * k, width: 30 * k, height: 22 * k), xRadius: 6 * k, yRadius: 6 * k).fill()
symbol("parkingsign.circle", 15, .medium, at: NSPoint(x: parkX * k, y: barMidY))
symbol("wifi", 14, .medium, at: NSPoint(x: 1046 * k, y: barMidY))
symbol("battery.75percent", 15, .regular, at: NSPoint(x: 1082 * k, y: barMidY))
let clock = NSAttributedString(string: "Mon Jun 9  9:41 AM", attributes: [.font: NSFont.systemFont(ofSize: 13.5 * k, weight: .medium), .foregroundColor: NSColor.white])
clock.draw(at: NSPoint(x: 1112 * k, y: barMidY - clock.size().height / 2))

// --- The panel, in frosted glass, hanging under the icon.
let scale: CGFloat = 400 / 340
let pw = 340 * scale, ph = panelImage.size.height / panelImage.size.width * pw
let panelRect = R(parkX - pw / 2 - 26, 64 + barH + 7, pw, ph)
let radius = 14 * scale * k
let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: radius, yRadius: radius)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -14 * k), blur: 40 * k, color: NSColor(white: 0, alpha: 0.32).cgColor)
NSColor(white: 1, alpha: 1).setFill(); panelPath.fill()
cg.restoreGState()
// Real frosted glass: the wallpaper behind the panel, blurred hard, under a light veil.
cg.saveGState(); panelPath.addClip()
let ci = CIImage(cgImage: wall)
let local = CGRect(x: panelRect.minX - screen.minX, y: panelRect.minY - screen.minY, width: panelRect.width, height: panelRect.height)
let frosted = ci.clampedToExtent().applyingGaussianBlur(sigma: 30 * k).cropped(to: local)
if let f = CIContext().createCGImage(frosted, from: local) { cg.draw(f, in: panelRect) }
NSColor(white: 0.985, alpha: 0.72).setFill(); panelRect.fill()
panelImage.draw(in: panelRect)
cg.restoreGState()
NSColor(white: 1, alpha: 0.7).setStroke(); panelPath.lineWidth = 1 * k; panelPath.stroke()
cg.restoreGState()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("ok")
