import AppKit

/// Finds, parks and restores windows. All window work runs on one serial background queue:
/// it blocks on Apple Events and Accessibility, and none of it may run concurrently.
final class Engine {
    private let queue = DispatchQueue(label: "com.spencereverett.park.engine", qos: .userInitiated)
    private var pendingMeasurements: [Spot.ID: (roots: Set<pid_t>, before: UInt64)] = [:]

    /// Apps that keep running when their windows are parked: background companions people expect
    /// to stay open, and Warp (whose own session restore would duplicate windows on relaunch).
    static let neverQuit: Set<String> = [
        "com.apple.finder", "com.spotify.client", "com.apple.Music", "com.tinyspeck.slackmacgap",
        "com.apple.MobileSMS", "com.apple.mail", "com.apple.iCal", WarpAdapter.bundleID,
    ]

    struct ParkResult {
        var spot: Spot
        /// Plain-language notes about windows that were left open, e.g. waiting on a permission.
        var notes: [String]
    }

    // MARK: - Preview

    func preview() async -> DesktopPreview {
        await run {
            let windows = CurrentSpace.windows()
            var bundleIDs: [String] = []
            var names: [String] = []
            for window in windows {
                guard let id = window.bundleID, !bundleIDs.contains(id) else { continue }
                bundleIDs.append(id)
                names.append(window.appName)
            }
            return DesktopPreview(windowCount: windows.count, bundleIDs: bundleIDs, appNames: names)
        }
    }

    // MARK: - Park

    /// - Parameters:
    ///   - only: restrict to these windows (used by the self-test so it never touches real work).
    ///   - dryRun: capture everything but close nothing.
    func parkCurrentDesktop(quitApps: Bool, only: Set<CGWindowID>? = nil, dryRun: Bool = false) async throws -> ParkResult {
        try await runThrowing { [self] in try park(quitApps: quitApps, only: only, dryRun: dryRun) }
    }

    func currentWindowIDs() async -> Set<CGWindowID> {
        await run { Set(CurrentSpace.windows().map(\.windowID)) }
    }

    private func park(quitApps: Bool, only: Set<CGWindowID>?, dryRun: Bool) throws -> ParkResult {
        let space = Spaces.activeSpace
        let windows = CurrentSpace.windows().filter { $0.bundleID != nil && (only?.contains($0.windowID) ?? true) }
        guard !windows.isEmpty else { throw ParkError.nothingToPark }

        var notes: [String] = []
        var contents: [CGWindowID: ParkedWindow.Content] = [:]
        var browserIDs: [CGWindowID: Int] = [:]
        var finderIDs: [CGWindowID: Int] = [:]
        /// Windows we can't capture faithfully stay open rather than lose their contents.
        var leaveOpen = Set<CGWindowID>()

        let byApp = Dictionary(grouping: windows) { $0.bundleID! }
        for (bundleID, appWindows) in byApp {
            let name = appWindows[0].appName
            switch bundleID {
            case _ where Chrome.family.contains(bundleID):
                do {
                    let snapshots = try Chrome.listWindows(bundleID: bundleID)
                    let matches = try Chrome.match(appWindows, snapshots, bundleID: bundleID)
                    for window in appWindows {
                        guard let snapshot = matches[window.windowID] else { leaveOpen.insert(window.windowID); continue }
                        contents[window.windowID] = .browser(
                            tabs: snapshot.tabs.map { BrowserTab(url: $0.url, title: $0.title) },
                            activeIndex: max(0, snapshot.activeTabIndex - 1),
                            incognito: snapshot.mode == "incognito")
                        browserIDs[window.windowID] = snapshot.chromeWindowID
                    }
                } catch {
                    appWindows.forEach { leaveOpen.insert($0.windowID) }
                    notes.append("\(name) stayed open. Allow Park to control \(name) in System Settings → Privacy & Security → Automation.")
                }

            case FigmaAdapter.bundleID:
                let captured = FigmaAdapter.capture(appWindows)
                for window in appWindows {
                    switch captured[window.windowID] {
                    case .app?: break   // only the file browser: parks as the app itself
                    case let content?: contents[window.windowID] = content
                    case nil:
                        leaveOpen.insert(window.windowID)
                        notes.append("A Figma window stayed open because its tabs couldn’t be read. Try again in a few seconds.")
                    }
                }

            case WarpAdapter.bundleID:
                let captured = WarpAdapter.capture(appWindows)
                contents.merge(captured) { $1 }
                for window in appWindows where captured[window.windowID] == nil { leaveOpen.insert(window.windowID) }

            case Finder.bundleID:
                do {
                    let snapshots = try Finder.listWindows()
                    for window in appWindows {
                        guard let snapshot = Finder.match(window, snapshots), let path = snapshot.path else {
                            leaveOpen.insert(window.windowID); continue
                        }
                        contents[window.windowID] = .folder(path: path)
                        finderIDs[window.windowID] = snapshot.finderWindowID
                    }
                } catch {
                    appWindows.forEach { leaveOpen.insert($0.windowID) }
                    notes.append("Finder windows stayed open. Allow Park to control Finder in System Settings → Privacy & Security → Automation.")
                }

            default:
                for window in appWindows {
                    if let url = window.documentURL, url.isFileURL {
                        contents[window.windowID] = .document(path: url.path)
                    }
                }
            }
        }

        let parkable = windows.filter { !leaveOpen.contains($0.windowID) }
        guard !parkable.isEmpty else { throw ParkError.nothingParkable(notes) }

        if dryRun {
            let parked = parkable.map {
                ParkedWindow(bundleID: $0.bundleID!, appName: $0.appName, title: $0.title, frame: $0.frame,
                             content: contents[$0.windowID] ?? .app)
            }
            return ParkResult(spot: Spot(name: Self.name(for: parked), createdAt: Date(), windows: parked), notes: notes)
        }

        // Switching desktops mid-park would close the wrong windows.
        guard Spaces.activeSpace == space else { throw ParkError.desktopChanged }

        // Decide which apps can be quit outright: nothing of theirs lives on another desktop.
        let apps = Dictionary(grouping: parkable) { $0.pid }
        var quitPIDs = Set<pid_t>()
        if quitApps {
            for (pid, appWindows) in apps {
                guard let app = NSRunningApplication(processIdentifier: pid), let id = app.bundleIdentifier,
                      !Self.neverQuit.contains(id),
                      appWindows.count == windows.filter({ $0.pid == pid }).count,
                      QuitPolicy.windowsElsewhere(pid: pid).isEmpty else { continue }
                quitPIDs.insert(pid)
            }
        }
        let roots = Set(apps.keys)
        let before = Processes.footprint(ofTreesRootedAt: roots)

        // Close. Apps that will be quit and have nothing app-specific to restore are just quit,
        // so their own state restoration brings their windows back on relaunch.
        var closed = Set<CGWindowID>()
        for window in parkable {
            let quitWithoutClosing = quitPIDs.contains(window.pid) && apps[window.pid]!.allSatisfy { contents[$0.windowID] == nil }
            if quitWithoutClosing { closed.insert(window.windowID); continue }
            if let id = browserIDs[window.windowID], let bundleID = window.bundleID {
                if (try? Chrome.close(chromeWindowID: id, bundleID: bundleID)) != nil { closed.insert(window.windowID) }
            } else if let id = finderIDs[window.windowID] {
                if (try? Finder.close(finderWindowID: id)) != nil { closed.insert(window.windowID) }
            } else if AXClose.close(window) == .closed {
                closed.insert(window.windowID)
            }
        }

        for pid in quitPIDs {
            // Only quit when every window of the app was handled.
            guard apps[pid]!.allSatisfy({ closed.contains($0.windowID) }),
                  let app = NSRunningApplication(processIdentifier: pid) else { continue }
            app.terminate()
        }
        waitForTermination(of: quitPIDs, timeout: 6)
        for pid in quitPIDs {
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { continue }
            // Still running: probably asking about unsaved changes. Its windows count as open.
            for window in apps[pid] ?? [] where AXClose.windowExists(window.windowID, pid: pid) {
                closed.remove(window.windowID)
            }
            notes.append("\(app.localizedName ?? "An app") is asking about unsaved changes.")
        }

        let parked: [ParkedWindow] = parkable.filter { closed.contains($0.windowID) }.map { window in
            ParkedWindow(bundleID: window.bundleID!, appName: window.appName, title: window.title,
                         frame: window.frame, content: contents[window.windowID] ?? .app)
        }
        let stuck = parkable.count - parked.count
        if stuck > 0, notes.isEmpty {
            notes.append(stuck == 1 ? "1 window couldn’t be closed." : "\(stuck) windows couldn’t be closed.")
        }
        guard !parked.isEmpty else { throw ParkError.nothingParkable(notes) }

        let spot = Spot(name: Self.name(for: parked), createdAt: Date(), windows: parked)
        pendingMeasurements[spot.id] = (roots, before)
        return ParkResult(spot: spot, notes: notes)
    }

    private func waitForTermination(of pids: Set<pid_t>, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let running = pids.contains { NSRunningApplication(processIdentifier: $0).map { !$0.isTerminated } ?? false }
            if !running { return }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    /// Names a spot after what it's about: the Figma file, the project folder, the page, or the apps.
    static func name(for windows: [ParkedWindow]) -> String {
        for window in windows {
            if case .figma(let files, let active) = window.content, files.indices.contains(active) {
                return files[active].title
            }
        }
        let home = NSHomeDirectory()
        for window in windows {
            if case .terminal(let tabs, let active) = window.content, tabs.indices.contains(active),
               let directory = tabs[active].layout.panes.first?.directory, directory != home {
                return (directory as NSString).lastPathComponent
            }
        }
        for window in windows {
            if case .document(let path) = window.content { return (path as NSString).lastPathComponent }
            if case .folder(let path) = window.content, path != home + "/" { return (path as NSString).lastPathComponent }
        }
        for window in windows {
            if case .browser(let tabs, let active, _) = window.content, tabs.indices.contains(active) {
                let title = Self.shortTitle(tabs[active].title)
                if !title.isEmpty { return title }
            }
        }
        var seen = Set<String>()
        return NameList.string(windows.compactMap { seen.insert($0.appName).inserted ? $0.appName : nil })
    }

    /// "Inbox (3) - you@example.com - Gmail" → "Inbox (3)"; page titles usually lead with what matters.
    private static func shortTitle(_ title: String) -> String {
        let separators = [" - ", " – ", " — ", " | ", " · "]
        var result = title
        for separator in separators {
            if let range = result.range(of: separator) { result = String(result[..<range.lowerBound]) }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

    func measureFreedMemory(for spot: Spot) async -> UInt64? {
        guard let pending = await run({ [self] in pendingMeasurements.removeValue(forKey: spot.id) }) else { return nil }
        // Renderer and helper processes exit over a few seconds.
        try? await Task.sleep(for: .seconds(4))
        let after = await run { Processes.footprint(ofTreesRootedAt: pending.roots) }
        return pending.before > after ? pending.before - after : 0
    }

    // MARK: - Restore

    /// Reopens a spot's windows on the current desktop. Returns the windows that could not be restored.
    func restore(_ spot: Spot) async -> [ParkedWindow] {
        await run { [self] in restoreSync(spot) }
    }

    private func restoreSync(_ spot: Spot) -> [ParkedWindow] {
        var failures: [ParkedWindow] = []
        var reopenedApps = Set<String>()
        var freshBrowserWindows: [String: Set<Int>] = [:]

        // Back to front, so the window that was frontmost ends up frontmost.
        for window in spot.windows.reversed() {
            let ok: Bool
            switch window.content {
            case .browser(let tabs, let activeIndex, let incognito):
                let wasRunning = isRunning(window.bundleID)
                guard Launcher.ensureRunning(bundleID: window.bundleID, settle: wasRunning ? 0 : 2) != nil else { ok = false; break }
                if !wasRunning, freshBrowserWindows[window.bundleID] == nil {
                    // A browser launched fresh may open its own blank window; remember it to tidy up after.
                    let blank = (try? Chrome.listWindows(bundleID: window.bundleID))?
                        .filter { $0.tabs.count == 1 && $0.tabs[0].url.hasSuffix("://newtab/") }.map(\.chromeWindowID) ?? []
                    freshBrowserWindows[window.bundleID] = Set(blank)
                }
                let snapshot = ChromeWindowSnapshot(
                    chromeWindowID: 0, mode: incognito ? "incognito" : "normal",
                    bounds: window.frame ?? CGRect(x: 80, y: 80, width: 1280, height: 860),
                    activeTabIndex: activeIndex + 1, tabs: tabs.map { ChromeTab(url: $0.url, title: $0.title) },
                    givenName: "", minimized: false, title: "")
                ok = (try? Chrome.restore(snapshot, bundleID: window.bundleID)) != nil

            case .figma(let files, let activeIndex):
                ok = FigmaAdapter.restore(files: files, activeIndex: activeIndex, frame: window.frame)

            case .terminal(let tabs, let activeIndex):
                ok = WarpAdapter.restore(tabs: tabs, activeIndex: activeIndex)

            case .folder(let path):
                guard FileManager.default.fileExists(atPath: path) else { ok = false; break }
                let frame = window.frame ?? CGRect(x: 120, y: 120, width: 900, height: 560)
                let snapshot = FinderWindowSnapshot(finderWindowID: 0, path: path, bounds: frame,
                                                    currentView: "icon view", collapsed: false, name: "")
                if (try? Finder.restore(snapshot)) == nil {
                    Finder.restoreWithoutAutomation(path: path, frame: frame)
                }
                ok = true

            case .document(let path):
                ok = openDocument(path, bundleID: window.bundleID, frame: window.frame)

            case .app:
                // One launch (or reopen) per app; apps restore their own windows when relaunched.
                if reopenedApps.insert(window.bundleID).inserted {
                    ok = reopen(window.bundleID, frame: spot.windows.filter { $0.bundleID == window.bundleID }.count == 1 ? window.frame : nil)
                } else {
                    ok = true
                }
            }
            if !ok { failures.append(window) }
        }

        for (bundleID, blankIDs) in freshBrowserWindows {
            for id in blankIDs { try? Chrome.close(chromeWindowID: id, bundleID: bundleID) }
        }
        if let front = spot.windows.first { bringForward(front.bundleID) }
        return failures.reversed()
    }

    private func isRunning(_ bundleID: String) -> Bool {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
    }

    private func openDocument(_ path: String, bundleID: String, frame: CGRect?) -> Bool {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path),
              let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let done = DispatchSemaphore(value: 0)
        var opened: NSRunningApplication?
        NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: .background) { app, _ in
            opened = app
            done.signal()
        }
        _ = done.wait(timeout: .now() + 15)
        guard let app = opened else { return false }
        if let frame { place(pid: app.processIdentifier, frame: frame) { AX.attr($0, kAXDocumentAttribute) == url.absoluteString } }
        return true
    }

    private func reopen(_ bundleID: String, frame: CGRect?) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let before = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first
            .map { Set(AX.windows(pid: $0.processIdentifier).map(\.1)) } ?? []
        let done = DispatchSemaphore(value: 0)
        var opened: NSRunningApplication?
        // Opening a running app sends it a "reopen", which brings back a window if it has none here.
        // It must not activate: activating an app whose windows are on other desktops switches you there.
        NSWorkspace.shared.openApplication(at: appURL, configuration: .background) { app, _ in
            opened = app
            done.signal()
        }
        _ = done.wait(timeout: .now() + 15)
        guard let app = opened else { return false }
        let isNew: (AXUIElement) -> Bool = { element in AX.windowID(element).map { !before.contains($0) } ?? false }
        if !waitForWindow(pid: app.processIdentifier, timeout: 3, where: isNew) {
            // Some apps ignore reopen while running in the background; ask for a window directly.
            AXMenu.click(pid: app.processIdentifier, "File", "New Window")
        }
        if let frame { place(pid: app.processIdentifier, frame: frame, where: isNew) }
        return true
    }

    /// Brings an app forward only if it has a window on this desktop, so macOS doesn't switch desktops.
    private func bringForward(_ bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first,
              let (window, _) = AX.windows(pid: app.processIdentifier).first else { return }
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        app.activate()
    }

    private func waitForWindow(pid: pid_t, timeout: TimeInterval, where predicate: (AXUIElement) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if AX.windows(pid: pid).contains(where: { predicate($0.0) }) { return true }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    /// Waits briefly for a window matching `predicate` to appear on this desktop, then moves it into place.
    private func place(pid: pid_t, frame: CGRect, where predicate: (AXUIElement) -> Bool) {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            if let (element, _) = AX.windows(pid: pid).first(where: { predicate($0.0) }) {
                AX.setFrame(element, frame)
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
    }

    // MARK: - Queue

    private func run<T>(_ work: @escaping () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: work()) }
        }
    }

    private func runThrowing<T>(_ work: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { continuation.resume(with: Result { try work() }) }
        }
    }
}

extension NSWorkspace.OpenConfiguration {
    /// Opens without activating. Activation is done separately, once a window exists on this desktop.
    static var background: NSWorkspace.OpenConfiguration {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        return configuration
    }
}

enum ParkError: LocalizedError {
    case nothingToPark
    case nothingParkable([String])
    case desktopChanged

    var errorDescription: String? {
        switch self {
        case .nothingToPark: return "There’s nothing on this desktop to park."
        case .nothingParkable(let notes): return notes.first ?? "None of these windows could be parked."
        case .desktopChanged: return "You switched desktops while parking, so nothing was closed. Try again."
        }
    }
}
