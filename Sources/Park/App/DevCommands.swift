import AppKit

/// Command-line entry points for checking the engine without the UI.
///   Park --dry-run    print what parking this desktop would save; closes nothing
///   Park --self-test  open throwaway windows, park and restore only those, and report
///   Park --intro-lab  play the first-launch intro candidates live and compare them
///   Park --intro=<ripple|dawn|clearing|lanes> [--speed=0.5] [--anchor=clock]  play one, then quit
///   Park --intro-frames=<name|all> <outdir> [--background=<png>]  render stills for design review
enum DevCommands {
    static func run(_ arguments: [String]) -> Bool {
        if arguments.contains("--intro-lab") {
            MainActor.assumeIsolated { IntroLab.run() }
            return true
        }
        if let flag = arguments.first(where: { $0.hasPrefix("--intro=") }),
           let effect = IntroEffect(rawValue: String(flag.dropFirst("--intro=".count))) {
            let speed = arguments.first(where: { $0.hasPrefix("--speed=") }).flatMap { Double($0.dropFirst("--speed=".count)) } ?? 1
            let anchor: IntroAnchor.Source = arguments.contains("--anchor=clock") ? .nearClock : .parkIcon
            MainActor.assumeIsolated { IntroLab.playOnce(effect, speed: speed, anchor: anchor) }
            return true
        }
        if let index = arguments.firstIndex(where: { $0.hasPrefix("--intro-frames=") }), index + 1 < arguments.count {
            let name = String(arguments[index].dropFirst("--intro-frames=".count))
            let background = arguments.first(where: { $0.hasPrefix("--background=") }).map { String($0.dropFirst("--background=".count)) }
            IntroFrames.render(name: name, to: arguments[index + 1], background: background)
            return true
        }
        if arguments.contains("--dry-run") {
            block { await dryRun() }
            return true
        }
        if arguments.contains("--self-test") {
            block { await selfTest() }
            return true
        }
        return false
    }

    private static func block(_ work: @escaping () async -> Void) {
        let done = DispatchSemaphore(value: 0)
        Task.detached { await work(); done.signal() }
        while done.wait(timeout: .now() + 0.05) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    private static func dryRun() async {
        print("Desktop detection: \(Private.hasSpaces && Private.getWindow != nil ? "full" : "conservative (private calls unavailable)")")
        print("Accessibility: \(AXIsProcessTrusted() ? "granted" : "not granted")")
        do {
            let result = try await Engine().parkCurrentDesktop(quitApps: false, dryRun: true)
            print("Would park “\(result.spot.name)” — \(result.spot.summary)")
            for window in result.spot.windows { print("  " + describe(window)) }
            for note in result.notes { print("  note: \(note)") }
        } catch {
            print("error: \(error.localizedDescription)")
        }
    }

    static func describe(_ window: ParkedWindow) -> String {
        let head = "\(window.appName) [\(window.title ?? "")]"
        switch window.content {
        case .browser(let tabs, let active, let incognito):
            return head + " browser \(tabs.count) tabs, active \(active)\(incognito ? " incognito" : ""): " + tabs.prefix(3).map(\.url).joined(separator: ", ")
        case .figma(let files, let active):
            return head + " figma \(files.count) files, active \(active): " + files.map(\.title).joined(separator: ", ")
        case .terminal(let tabs, let active):
            let described = tabs.map { tab in
                tab.layout.panes.map { pane in pane.directory + (pane.command.map { " (\($0))" } ?? "") }.joined(separator: " | ")
            }
            return head + " terminal \(tabs.count) tabs, active \(active): " + described.joined(separator: "; ")
        case .folder(let path): return head + " folder \(path)"
        case .document(let path): return head + " document \(path)"
        case .app: return head + " app"
        }
    }

    private static func selfTest() async {
        let engine = Engine()
        let before = await engine.currentWindowIDs()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("park-selftest")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let document = folder.appendingPathComponent("Park self-test.txt")
        try? "Park self-test".write(to: document, atomically: true, encoding: .utf8)

        print("Opening test windows…")
        _ = try? AppleScript.run("""
        tell application id "com.google.Chrome"
          set w to make new window
          set URL of active tab of w to "https://example.com/"
          tell w to make new tab at end of tabs with properties {URL:"https://example.org/"}
          set bounds of w to {200, 140, 1100, 800}
        end tell
        """)
        _ = try? await NSWorkspace.shared.open([document], withApplicationAt: URL(fileURLWithPath: "/System/Applications/TextEdit.app"),
                                configuration: NSWorkspace.OpenConfiguration())
        if CommandLine.arguments.contains("--warp") {
            print("Opening a test Warp window…")
            _ = WarpAdapter.restore(tabs: [
                TerminalTab(title: nil, layout: .pane(directory: folder.path, command: nil, focused: true)),
                TerminalTab(title: "Park test", layout: .split(horizontal: true, panes: [
                    .pane(directory: NSTemporaryDirectory(), command: nil, focused: false),
                    .pane(directory: folder.path, command: nil, focused: true),
                ])),
            ], activeIndex: 1)
        }
        if let index = CommandLine.arguments.firstIndex(of: "--figma"), index + 1 < CommandLine.arguments.count {
            print("Opening a test Figma window…")
            let ok = FigmaAdapter.restore(files: [FigmaFile(url: CommandLine.arguments[index + 1], title: "test")], activeIndex: 0,
                                          frame: CGRect(x: 160, y: 120, width: 1200, height: 800))
            print(ok ? "  Figma window created" : "  ✗ Figma window not created")
        }
        try? await Task.sleep(for: .seconds(4))

        let fresh = await engine.currentWindowIDs().subtracting(before)
        print("New windows on this desktop: \(fresh.count)")
        for window in CurrentSpace.windows() where fresh.contains(window.windowID) {
            print("  \(window.appName) “\(window.title ?? "")” ax=\(window.ax != nil) doc=\(window.documentURL?.lastPathComponent ?? "none") elsewhere=\(QuitPolicy.windowsElsewhere(pid: window.pid).count)")
        }
        do {
            let result = try await engine.parkCurrentDesktop(quitApps: false, only: fresh)
            SpotStore.clearPending()
            print("Parked “\(result.spot.name)”:")
            for window in result.spot.windows { print("  " + describe(window)) }
            for note in result.notes { print("  note: \(note)") }
            try? await Task.sleep(for: .seconds(1))
            let stillOpen = await engine.currentWindowIDs().intersection(fresh)
            print(stillOpen.isEmpty ? "✓ all test windows closed" : "✗ still open: \(stillOpen)")

            print("Restoring…")
            let failures = await engine.restore(result.spot)
            try? await Task.sleep(for: .seconds(2))
            let restored = await engine.currentWindowIDs().subtracting(before)
            print(failures.isEmpty ? "✓ restore reported no failures" : "✗ failures: \(failures.map(\.appName))")
            print("Windows back on this desktop: \(restored.count)")

            // Check the browser tabs came back, then clean up.
            let check = try await engine.parkCurrentDesktop(quitApps: false, only: restored)
            SpotStore.clearPending()
            for window in check.spot.windows { print("  back: " + describe(window)) }
            print("Cleaned up test windows.")
        } catch {
            print("✗ error: \(error.localizedDescription)")
            if case ParkError.nothingParkable(let notes) = error { notes.forEach { print("  note: \($0)") } }
            // Close whatever the test opened so nothing is left behind.
            for window in CurrentSpace.windows() where !before.contains(window.windowID) { AXClose.close(window) }
        }
        _ = try? AppleScript.run("tell application id \"com.apple.TextEdit\" to quit saving no")
        try? FileManager.default.removeItem(at: folder)
    }
}
