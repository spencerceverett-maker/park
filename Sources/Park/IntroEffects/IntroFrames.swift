import AppKit

/// Renders stills of the intro effects for design review, composited over a screenshot (or a plain
/// desktop) so they're judged against real content.
enum IntroFrames {
    static let times: [Double] = [0.25, 0.7, 1.2, 1.7, 2.2, 2.6]

    static func render(name: String, to directory: String, background: String?) {
        guard let renderer = IntroRenderer() else { print("Metal unavailable"); return }
        let effects = name == "all" ? IntroEffect.allCases : [IntroEffect(rawValue: name)].compactMap { $0 }
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)

        let backdrop = background.flatMap { NSImage(contentsOfFile: $0) }
        // Default: a 1512×982-point screen at 2x, with Park's icon near the clock.
        let pixelSize = backdrop.map { image -> CGSize in
            let rep = image.representations.first
            return CGSize(width: rep?.pixelsWide ?? 3024, height: rep?.pixelsHigh ?? 1964)
        } ?? CGSize(width: 3024, height: 1964)
        let scale: CGFloat = 2
        let origin = CGPoint(x: (pixelSize.width / scale - 210) * scale, y: 12 * scale)

        for effect in effects {
            for t in times {
                guard let frame = renderer.frame(effect, at: t, size: pixelSize, origin: origin, scale: scale) else { continue }
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(pixelSize.width), pixelsHigh: Int(pixelSize.height),
                                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState()
                NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                let rect = NSRect(origin: .zero, size: pixelSize)
                if let backdrop {
                    backdrop.draw(in: rect)
                } else {
                    // A light, busy-ish desktop: the hardest case for light to read on.
                    NSColor(white: 0.93, alpha: 1).setFill(); rect.fill()
                    NSColor.white.setFill()
                    NSBezierPath(roundedRect: NSRect(x: 300, y: 300, width: 1500, height: 1100), xRadius: 24, yRadius: 24).fill()
                    NSColor(srgbRed: 0.13, green: 0.14, blue: 0.16, alpha: 1).setFill()
                    NSBezierPath(roundedRect: NSRect(x: 1600, y: 500, width: 1100, height: 800), xRadius: 24, yRadius: 24).fill()
                    NSColor(white: 0.85, alpha: 1).setFill(); NSRect(x: 0, y: pixelSize.height - 48, width: pixelSize.width, height: 48).fill()
                }
                NSGraphicsContext.current?.cgContext.draw(frame, in: rect)
                NSGraphicsContext.restoreGraphicsState()
                let path = "\(directory)/\(effect.rawValue)-\(String(format: "%.2f", t)).jpg"
                try? rep.representation(using: .jpeg, properties: [.compressionFactor: 0.8])?.write(to: URL(fileURLWithPath: path))
            }
            print("rendered \(effect.rawValue)")
        }
    }
}
