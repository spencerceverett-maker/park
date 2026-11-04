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

    init() {
        // Accessibility timeouts are set per app (see AX.windows). Don't set one on the system-wide
        // element: doing so makes _AXUIElementGetWindow fail for every window (verified on macOS 26).
        queue.async { WarpAdapter.removeLeftoverLaunchConfigs() }
    }

    struct ParkResult {
        var spot: Spot
        /// Plain-language notes about windows that were left open, e.g. waiting on a permission.
        var notes: [String]
    }

    // MARK: - Preview

    /// - Parameter only: restrict to these windows (the guided tour's practice windows).
    func preview(only: Set<CGWindowID>? = nil) async -> DesktopPreview {
        await run {
            let windows = CurrentSpace.windows().filter { only?.contains($0.windowID) ?? true }
            var bundleIDs: [String] = []
            var names: [String] = []
            for window in windows {
                guard let id = window.bundleID, !bundleIDs.contains(id) else { continue }
                bundleIDs.append(id)
                names.append(window.appName)
            }
            var commands: [String] = []
            let terminals = windows.filter { $0.bundleID == WarpAdapter.bundleID }
            if !terminals.isEmpty {
                for case .terminal(let tabs, _) in WarpAdapter.capture(terminals).values {
                    for pane in tabs.flatMap(\.layout.panes) {
                        if let command = pane.command, !commands.contains(command) { commands.append(command) }
                    }
                }
            }
            return DesktopPreview(windowCount: windows.count, bundleIDs: bundleIDs, appNames: names, runningCommands: commands)
        }
    }

    // MARK: - Park

    /// - Parameters:
    ///   - only: restrict to these windows (used by the self-test so it never touches real work).
    ///   - dryRun: capture everything but close nothing.
    ///   - onWaiting: called with the names of apps Park is waiting on (an app asked a question before
    ///     closing), and with nil once it stops waiting. Called on the engine's queue.
    func parkCurrentDesktop(quitApps: Bool, only: Set<CGWindowID>? = nil, dryRun: Bool = false,
                            onWaiting: @escaping ([String]?) -> Void = { _ in }) async throws -> ParkResult {
        try await runThrowing { [self] in try park(quitApps: quitApps, only: only, dryRun: dryRun, onWaiting: onWaiting) }
    }

    func currentWindowIDs() async -> Set<CGWindowID> {
        await run { Set(CurrentSpace.windows().map(\.windowID)) }
    }

    private func park(quitApps: Bool, only: Set<CGWindowID>?, dryRun: Bool, onWaiting: ([String]?) -> Void) throws -> ParkResult {
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
                        if snapshot.mode == "incognito" {
                            // Saving incognito tabs to disk would defeat the point of incognito.
                            leaveOpen.insert(window.windowID)
                            notes.append("Incognito windows stay open, so their tabs are never saved.")
                            continue
                        }
                        contents[window.windowID] = .browser(
                            tabs: snapshot.tabs.map { BrowserTab(url: $0.url, title: $0.title) },
                            activeIndex: max(0, snapshot.activeTabIndex - 1),
                            incognito: snapshot.mode == "incognito")
                        browserIDs[window.windowID] = snapshot.chromeWindowID
                    }
                } catch {
                    appWindows.forEach { leaveOpen.insert($0.windowID) }
                    Log.write("\(name) scripting failed: \(error)")
                    notes.append("\(name) stayed open. Allow Park to control \(name) in System Settings → Privacy & Security → Automation.")
                }

            case FigmaAdapter.bundleID:
                let captured = FigmaAdapter.capture(appWindows)
                for window in appWindows {
                    switch captured[window.windowID] {
                    case .content(.app)?: break
                    case .content(let content)?: contents[window.windowID] = content
                    case .keepOpen(let reason)?:
                        leaveOpen.insert(window.windowID)
                        if !notes.contains(reason) { notes.append(reason) }
                    case nil:
                        leaveOpen.insert(window.windowID)
                        notes.append("A Figma window stayed open because Park couldn’t tell which file it shows. Try again in a few seconds.")
                    }
                }

            case WarpAdapter.bundleID:
                let captured = WarpAdapter.capture(appWindows)
                contents.merge(captured) { $1 }
                let unmatched = appWindows.filter { captured[$0.windowID] == nil }
                if !unmatched.isEmpty {
                    unmatched.forEach { leaveOpen.insert($0.windowID) }
                    notes.append("A Warp window stayed open because Park couldn’t read its tabs.")
                }

            case NotionAdapter.bundleID:
                // If Notion can be quit, it brings back its own windows and tabs when it opens again.
                if quitApps, QuitPolicy.windowsElsewhere(pid: appWindows[0].pid).isEmpty { break }
                let captured = NotionAdapter.capture(appWindows)
                contents.merge(captured) { $1 }
                let unmatched = appWindows.filter { captured[$0.windowID] == nil }
                if !unmatched.isEmpty {
                    unmatched.forEach { leaveOpen.insert($0.windowID) }
                    notes.append(NotionAdapter.unmatchedNote)
                }

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
                    Log.write("Finder scripting failed: \(error)")
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

        // Decide which apps can be quit outright: every window of theirs is parkable, nothing of theirs
        // lives on another desktop, and they have no other windows here that Park didn't list.
        var quitPIDs = Set<pid_t>()
        if quitApps {
            for (pid, appWindows) in Dictionary(grouping: windows, by: \.pid) {
                guard appWindows.allSatisfy({ !leaveOpen.contains($0.windowID) }),
                      let app = NSRunningApplication(processIdentifier: pid), let id = app.bundleIdentifier,
                      !Self.neverQuit.contains(id), !Self.unsupportedTabApps.contains(id),
                      QuitPolicy.windowsElsewhere(pid: pid).isEmpty,
                      Self.unlistedWindows(pid: pid, known: Set(appWindows.map(\.windowID))).isEmpty else { continue }
                quitPIDs.insert(pid)
            }
        }

        // A window with nothing app-specific to restore can only be closed safely if its app is quit
        // (and restores itself on relaunch), or if reopening the app brings back the same thing.
        var keptApps: [String] = []
        for window in windows where contents[window.windowID] == nil && !leaveOpen.contains(window.windowID) {
            let id = window.bundleID!
            if Self.unsupportedTabApps.contains(id) {
                leaveOpen.insert(window.windowID)
                if !keptApps.contains(window.appName) {
                    keptApps.append(window.appName)
                    notes.append("\(window.appName) stayed open. Park can’t save its tabs yet.")
                }
            } else if !quitPIDs.contains(window.pid) && !Self.reopensAsIs(window, among: windows) {
                leaveOpen.insert(window.windowID)
                if !keptApps.contains(window.appName) {
                    keptApps.append(window.appName)
                    notes.append(QuitPolicy.windowsElsewhere(pid: window.pid).isEmpty
                        ? "\(window.appName) stayed open. Park can’t reopen each of its windows without quitting it."
                        : "\(window.appName) stayed open because it’s also in use elsewhere, and Park can’t reopen that exact window.")
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

        let apps = Dictionary(grouping: parkable) { $0.pid }
        let roots = Set(apps.keys)
        let before = Processes.footprint(ofTreesRootedAt: roots)

        // Record everything before closing anything, so a crash mid-park can't lose windows.
        let spotID = UUID()
        func parked(_ windows: [ParkableWindow]) -> [ParkedWindow] {
            windows.map {
                ParkedWindow(bundleID: $0.bundleID!, appName: $0.appName, title: $0.title, frame: $0.frame,
                             content: contents[$0.windowID] ?? .app)
            }
        }
        let planned = parked(parkable)
        SpotStore.writePending(Spot(id: spotID, name: Self.name(for: planned), createdAt: Date(), windows: planned))

        // Close. Apps that will be quit and have nothing app-specific to restore are just quit,
        // so their own state restoration brings their windows back on relaunch.
        var closed = Set<CGWindowID>()
        /// Windows that got the close command but are still open, usually because their app is asking
        /// a question first ("Stop the running process?", "Save changes?").
        var asking: [ParkableWindow] = []
        var quitWithoutClosing = Set<pid_t>()
        for pid in quitPIDs where apps[pid]?.allSatisfy({ contents[$0.windowID] == nil }) == true {
            quitWithoutClosing.insert(pid)
        }
        for window in parkable {
            if quitWithoutClosing.contains(window.pid) { closed.insert(window.windowID); continue }
            if let id = browserIDs[window.windowID], let bundleID = window.bundleID {
                // A "Leave site?" prompt keeps a window open even when the close command succeeds.
                if (try? Chrome.close(chromeWindowID: id, bundleID: bundleID)) != nil {
                    if Self.waitUntilGone(window.windowID, pid: window.pid) { closed.insert(window.windowID) } else { asking.append(window) }
                }
            } else if let id = finderIDs[window.windowID] {
                if (try? Finder.close(finderWindowID: id)) != nil {
                    if Self.waitUntilGone(window.windowID, pid: window.pid) { closed.insert(window.windowID) } else { asking.append(window) }
                }
            } else {
                switch AXClose.close(window) {
                case .closed: closed.insert(window.windowID)
                case .stillOpen: asking.append(window)
                case .noCloseButton, .notTrusted: break
                }
            }
        }

        // Wait for the person to answer. Without this, a window that closes after Park moves on is
        // closed but never saved.
        let answered = awaitAnswers(asking, notes: &notes, onWaiting: onWaiting)
        closed.formUnion(answered)

        var terminated = Set<pid_t>()
        for pid in quitPIDs {
            let known = Set(apps[pid]!.map(\.windowID))
            // Only quit when every window was handled, and nothing new appeared on this desktop meanwhile.
            guard known.isSubset(of: closed), Self.unlistedWindows(pid: pid, known: known).isEmpty,
                  let app = NSRunningApplication(processIdentifier: pid) else {
                if quitWithoutClosing.contains(pid) { closed.subtract(known) }
                continue
            }
            app.terminate()
            terminated.insert(pid)
        }
        waitForTermination(of: terminated, timeout: 8)
        // Still running with its windows here: it's probably asking about unsaved changes. If its
        // windows are gone it's just slow to quit, and they're parked.
        let quitAsking = terminated.flatMap { pid -> [ParkableWindow] in
            guard let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return [] }
            return (apps[pid] ?? []).filter { AXClose.windowExists($0.windowID, pid: pid) }
        }
        quitAsking.forEach { closed.remove($0.windowID) }
        closed.formUnion(awaitAnswers(quitAsking, notes: &notes, onWaiting: onWaiting))

        let closedWindows = parked(parkable.filter { closed.contains($0.windowID) })
        let stuck = parkable.count - closedWindows.count
        if stuck > 0, notes.isEmpty {
            notes.append(stuck == 1 ? "1 window couldn’t be closed." : "\(stuck) windows couldn’t be closed.")
        }
        guard !closedWindows.isEmpty else {
            SpotStore.clearPending()
            throw ParkError.nothingParkable(notes)
        }

        let spot = Spot(id: spotID, name: Self.name(for: closedWindows), createdAt: Date(), windows: closedWindows)
        pendingMeasurements[spot.id] = (roots, before)
        return ParkResult(spot: spot, notes: notes)
    }

    /// Apps where closing a window and reopening the app later brings back the same view.
    static let reopensLosslessly: Set<String> = [
        "com.tinyspeck.slackmacgap", "com.apple.MobileSMS", "com.apple.mail", "com.spotify.client", "com.apple.Music",
        "com.apple.iCal", "notion.id", "com.linear", "com.hnc.Discord", "com.anthropic.claudefordesktop",
        "com.openai.chat", "com.granola.app", "com.apple.Notes", "com.apple.reminders", "com.apple.systempreferences",
    ]

    /// Closing a window and reopening its app brings back the same view only when that window is the
    /// app's one window anywhere. With more windows, or windows on another desktop, a reopen does
    /// nothing (the app already has a window), so the closed windows would be lost.
    static func reopensAsIs(_ window: ParkableWindow, among windows: [ParkableWindow]) -> Bool {
        guard let id = window.bundleID, reopensLosslessly.contains(id) else { return false }
        return windows.filter { $0.pid == window.pid }.count == 1 && QuitPolicy.windowsElsewhere(pid: window.pid).isEmpty
    }

    /// Apps with tabs or sessions Park can't capture yet. Their windows are never closed.
    static let unsupportedTabApps: Set<String> = [
        "com.apple.Safari", "org.mozilla.firefox", "com.apple.Terminal", "com.googlecode.iterm2",
    ]

    /// Windows of an app on this desktop that Park didn't list (dialogs, inactive native tabs, tiny windows,
    /// windows opened while parking). Quitting the app would close them without saving anything.
    static func unlistedWindows(pid: pid_t, known: Set<CGWindowID>) -> Set<CGWindowID> {
        Set(AX.windows(pid: pid).map(\.1)).subtracting(known)
    }

    static func waitUntilGone(_ windowID: CGWindowID, pid: pid_t, timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !AXClose.windowExists(windowID, pid: pid) { return true }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return !AXClose.windowExists(windowID, pid: pid)
    }

    /// How long Park waits for someone to answer an app's question before it gives up on that window.
    static let answerTimeout: TimeInterval = 60

    /// Waits while apps ask a question before closing. Returns the windows that closed: they're parked.
    /// A window stays open (and isn't parked) when its question goes away and the window is still there,
    /// which means the person chose Cancel, or when time runs out. A question still showing when time
    /// runs out is cancelled where possible, so the window can't close later without being saved.
    private func awaitAnswers(_ windows: [ParkableWindow], notes: inout [String],
                              onWaiting: ([String]?) -> Void) -> Set<CGWindowID> {
        guard !windows.isEmpty else { return [] }
        var pending = windows
        var closed = Set<CGWindowID>()
        var keptOpen: [ParkableWindow] = []
        /// Windows whose question Accessibility could see. Apps that draw their own (Warp) never get here,
        /// so for them Park can only wait.
        var sawQuestion = Set<CGWindowID>()
        let deadline = Date().addingTimeInterval(Self.answerTimeout)
        var lastReported: [String] = []
        while !pending.isEmpty, Date() < deadline {
            pending.removeAll { window in
                if !AXClose.windowExists(window.windowID, pid: window.pid) {
                    closed.insert(window.windowID)
                    return true
                }
                if AXClose.question(for: window) != nil {
                    sawQuestion.insert(window.windowID)
                } else if sawQuestion.contains(window.windowID) {
                    keptOpen.append(window)   // the question went away and the window didn't: Cancel
                    return true
                }
                return false
            }
            var names: [String] = []
            for window in pending where !names.contains(window.appName) { names.append(window.appName) }
            if !names.isEmpty, names != lastReported {
                onWaiting(names)
                lastReported = names
            }
            if !pending.isEmpty { Thread.sleep(forTimeInterval: 0.25) }
        }
        onWaiting(nil)

        for window in pending {
            if let question = AXClose.question(for: window) { AXClose.cancel(question) }
        }
        var noted: [String] = []
        for window in keptOpen + pending where !noted.contains(window.appName) {
            noted.append(window.appName)
            notes.append(pending.contains(where: { $0.appName == window.appName })
                ? "\(window.appName) was still asking a question, so its window stayed open and wasn’t parked."
                : "\(window.appName) stayed open because you chose to keep it.")
        }
        return closed
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
            if case .notion(let tabs, let active) = window.content, tabs.indices.contains(active) {
                let title = Self.shortTitle(tabs[active].title)
                if !title.isEmpty { return title }
            }
        }
        var seen = Set<String>()
        return NameList.string(windows.compactMap { seen.insert($0.appName).inserted ? $0.appName : nil })
    }

    /// "Inbox (3) - you@example.com - Gmail" → "Inbox (3)"; page titles usually lead with what matters.
    static func shortTitle(_ title: String) -> String {
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
                    bounds: Screens.fit(window.frame ?? CGRect(x: 80, y: 80, width: 1280, height: 860)),
                    activeTabIndex: activeIndex + 1, tabs: tabs.map { ChromeTab(url: Self.safeTabURL($0.url), title: $0.title) },
                    givenName: "", minimized: false, title: "")
                ok = (try? Chrome.restore(snapshot, bundleID: window.bundleID)) != nil

            case .figma(let files, let activeIndex):
                ok = FigmaAdapter.restore(files: files, activeIndex: activeIndex, frame: window.frame.map(Screens.fit))

            case .terminal(let tabs, let activeIndex):
                ok = WarpAdapter.restore(tabs: tabs, activeIndex: activeIndex)

            case .notion(let tabs, let activeIndex):
                ok = NotionAdapter.restore(tabs: tabs, activeIndex: activeIndex, frame: window.frame)

            case .folder(let path):
                guard FileManager.default.fileExists(atPath: path) else { ok = false; break }
                let frame = Screens.fit(window.frame ?? CGRect(x: 120, y: 120, width: 900, height: 560))
                let snapshot = FinderWindowSnapshot(finderWindowID: 0, path: path, bounds: frame,
                                                    currentView: "icon view", collapsed: false, name: "")
                if (try? Finder.restore(snapshot)) != nil {
                    ok = true
                } else {
                    ok = Finder.restoreWithoutAutomation(path: path, frame: frame)
                }

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

    /// Tab URLs come back from disk; only reopen ordinary pages, never script URLs.
    static func safeTabURL(_ string: String) -> String {
        let allowed: Set<String> = ["http", "https", "file", "chrome", "about", "chrome-extension", "edge", "brave", "vivaldi"]
        guard let scheme = URL(string: string)?.scheme?.lowercased(), allowed.contains(scheme) else { return "about:blank" }
        return string
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
        let showsDocument: (AXUIElement) -> Bool = { AX.attr($0, kAXDocumentAttribute) == url.absoluteString }
        if let frame {
            place(pid: app.processIdentifier, frame: frame, where: showsDocument)
        }
        // Apps that don't report their document can't be checked; the open itself succeeded.
        return true
    }

    private func reopen(_ bundleID: String, frame: CGRect?) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return false }
        let wasRunning = isRunning(bundleID)
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
        // An app launched from scratch can take a while to draw its first window.
        var appeared = waitForWindow(pid: app.processIdentifier, timeout: wasRunning ? 3 : 12, where: isNew)
        if !appeared {
            // Some apps ignore reopen while running in the background; ask for a window directly.
            AXMenu.click(pid: app.processIdentifier, "File", "New Window")
            appeared = waitForWindow(pid: app.processIdentifier, timeout: 3, where: isNew)
        }
        // No window came back: report it, so the parked desktop is kept instead of deleted.
        guard appeared else { return false }
        if let frame { place(pid: app.processIdentifier, frame: frame, where: isNew) }
        return true
    }

    /// Brings an app forward only if it has a window on this desktop, so macOS doesn't switch desktops.
    /// Some apps list windows from every desktop in Accessibility, so check this desktop's windows.
    private func bringForward(_ bundleID: String) {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return }
        let here = Set(CurrentSpace.windows().filter { $0.pid == app.processIdentifier }.map(\.windowID))
        guard let (window, _) = AX.windows(pid: app.processIdentifier).first(where: { here.contains($0.1) }) else { return }
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
                AX.setFrame(element, Screens.fit(frame))
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

/// Display geometry in the top-left coordinates AX, CG and AppleScript use. Safe off the main thread.
enum Screens {
    static var frames: [CGRect] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)
        return displays.prefix(Int(count)).map { CGDisplayBounds($0) }
    }

    /// Keeps a saved frame if it's mostly on a connected display; otherwise moves it onto the main display,
    /// shrinking it to fit. Parking on an external monitor and restoring on a laptop would otherwise
    /// put windows out of sight.
    static func fit(_ frame: CGRect) -> CGRect {
        let screens = frames
        // No display information (locked screen, no window-server session): leave the frame alone.
        guard !screens.isEmpty, !CGDisplayBounds(CGMainDisplayID()).isEmpty else { return frame }
        let visibleArea = screens.map { $0.intersection(frame) }.filter { !$0.isNull }.map { $0.width * $0.height }.max() ?? 0
        if visibleArea >= frame.width * frame.height * 0.5 { return frame }
        let main = CGDisplayBounds(CGMainDisplayID())
        let menuBar: CGFloat = 40
        let width = min(frame.width, main.width - 40)
        let height = min(frame.height, main.height - menuBar - 20)
        return CGRect(x: main.minX + (main.width - width) / 2, y: main.minY + menuBar, width: width, height: height)
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
