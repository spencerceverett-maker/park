import AppKit
import SwiftUI

/// Renders the panel to a PNG with sample data, for design review without touching real windows.
/// Usage: Park --snapshot out.png [--dark] [--empty] [--permission]
@MainActor
enum Snapshot {
    nonisolated static let isRendering = CommandLine.arguments.contains("--snapshot")

    static func render(to path: String, arguments: [String]) {
        let dark = arguments.contains("--dark")
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
        model.memory = MemoryStats(used: 12_400_000_000, total: 17_179_869_184)
        if arguments.contains("--toast") { model.toast = Toast(message: "Deleted “Website refresh”", undo: {}) }

        let view = PanelView()
            .environment(model)
            .background(Color(nsColor: dark ? NSColor(white: 0.16, alpha: 1) : NSColor(white: 0.97, alpha: 1)))
            .environment(\.colorScheme, dark ? .dark : .light)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
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
