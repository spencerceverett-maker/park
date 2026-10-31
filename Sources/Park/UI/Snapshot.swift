import AppKit
import SwiftUI

/// Renders the panel to a PNG with sample data, for design review without touching real windows.
/// Usage: Park --snapshot out.png [--dark] [--empty] [--permission]
@MainActor
enum Snapshot {
    nonisolated static let isRendering = CommandLine.arguments.contains("--snapshot")

    static func render(to path: String, arguments: [String]) {
        let dark = arguments.contains("--dark")
        // --intro-frame=<seconds> draws one frame of the first-launch light over a sample desktop.
        if let flag = arguments.first(where: { $0.hasPrefix("--intro-frame=") }),
           let t = Double(flag.dropFirst("--intro-frame=".count)) {
            renderIntroFrame(at: t, to: path)
            return
        }
        // --onboarding=move|practice|practice-parked|practice-restored|access|access-granted|try|try-done
        if let flag = arguments.first(where: { $0.hasPrefix("--onboarding=") }) {
            let name = String(flag.dropFirst("--onboarding=".count))
            let step: OnboardingView.Step = switch name {
            case "move": .move
            case "access", "access-granted": .access
            case "try", "try-done": .tryIt
            default: .practice
            }
            let practice: PracticeDesk.Phase = name == "practice-parked" ? .parked : name == "practice-restored" ? .restored : .ready
            let view = OnboardingView(step: step, includesMove: true,
                                      granted: name == "access-granted" ? true : (name == "access" ? false : nil),
                                      practice: practice, opened: name == "try-done")
            write(view.background(Color(nsColor: dark ? NSColor(white: 0.15, alpha: 1) : .windowBackgroundColor))
                    .environment(\.colorScheme, dark ? .dark : .light), to: path, scale: 2, opaque: true)
            return
        }
        let store = SpotStore(fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("park-snapshot-\(UUID()).json"))
        if !arguments.contains("--empty") {
            for spot in sampleSpots.reversed() { store.insert(spot) }
        }
        let model = AppModel(store: store, engine: Engine())
        model.hasAccessibility = !arguments.contains("--permission")
        model.preview = DesktopPreview(
            windowCount: 5,
            bundleIDs: ["com.google.Chrome", "com.figma.Desktop", "dev.warp.Warp-Stable"],
            appNames: ["Chrome", "Figma", "Warp"]
        )
        if arguments.contains("--running") { model.preview?.runningCommands = ["claude", "npm run dev"] }
        model.memory = MemoryStats(used: 12_400_000_000, total: 17_179_869_184)
        if arguments.contains("--toast") { model.toast = Toast(message: "Deleted “Website refresh”", undo: {}) }

        // --clear leaves the background transparent, for compositing over a real material.
        let clear = arguments.contains("--clear")
        let view = PanelView()
            .environment(model)
            .background(clear ? Color.clear : Color(nsColor: dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.97, alpha: 1)))
            .environment(\.colorScheme, dark ? .dark : .light)

        write(view, to: path, scale: arguments.contains("--3x") ? 3 : 2, opaque: !clear)
    }

    private static func renderIntroFrame(at t: Double, to path: String) {
        let size = CGSize(width: 1512, height: 982)
        guard let renderer = IntroLight.Renderer(), let light = renderer.frame(at: t, size: size) else {
            print("intro light unavailable"); return
        }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let ctx = NSGraphicsContext.current!.cgContext
        // A stand-in desktop: a light, neutral wallpaper with a couple of windows, so the veil and beams read.
        NSGradient(colors: [NSColor(white: 0.86, alpha: 1), NSColor(white: 0.72, alpha: 1)])!.draw(in: CGRect(origin: .zero, size: size), angle: -90)
        for r in [CGRect(x: 120, y: 260, width: 560, height: 420), CGRect(x: 820, y: 180, width: 520, height: 380)] {
            NSColor(white: 0.97, alpha: 1).setFill(); NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12).fill()
        }
        ctx.draw(light, in: CGRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }

    private static func write(_ view: some View, to path: String, scale: CGFloat, opaque: Bool) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        renderer.isOpaque = opaque
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) else {
            print("snapshot failed")
            return
        }
        try? png.write(to: URL(fileURLWithPath: path))
        print("wrote \(path)")
    }

    private static var sampleSpots: [Spot] {
        let now = Date()
        func browser(_ n: Int) -> ParkedWindow {
            ParkedWindow(bundleID: "com.google.Chrome", appName: "Chrome", title: "Linear",
                         content: .browser(tabs: Array(repeating: BrowserTab(url: "https://linear.app", title: "Linear"), count: n), activeIndex: 0, incognito: false))
        }
        let figma = ParkedWindow(bundleID: "com.figma.Desktop", appName: "Figma", title: "Onboarding redesign",
                                 content: .figma(files: [FigmaFile(url: "https://www.figma.com/design/x", title: "Onboarding redesign")], activeIndex: 0))
        let warp = ParkedWindow(bundleID: "dev.warp.Warp-Stable", appName: "Warp", title: "api-server",
                                content: .terminal(tabs: [TerminalTab(title: nil, layout: .pane(directory: "~/Developer/api-server", command: "npm run dev", focused: true))], activeIndex: 0))
        let notion = ParkedWindow(bundleID: "notion.id", appName: "Notion", title: nil, content: .app)
        let slack = ParkedWindow(bundleID: "com.tinyspeck.slackmacgap", appName: "Slack", title: nil, content: .app)
        let linear = ParkedWindow(bundleID: "com.linear", appName: "Linear", title: nil, content: .app)
        return [
            Spot(name: "Onboarding redesign", createdAt: now.addingTimeInterval(-60 * 42),
                 windows: [figma, browser(8), warp], freedBytes: 2_300_000_000),
            Spot(name: "Q4 launch plan", createdAt: now.addingTimeInterval(-3600 * 26),
                 windows: [figma, browser(3), notion, linear, slack], freedBytes: 1_100_000_000),
            Spot(name: "api-server", createdAt: now.addingTimeInterval(-3600 * 24 * 4),
                 windows: [warp, browser(2)], freedBytes: nil),
        ]
    }
}
