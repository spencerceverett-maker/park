import AppKit
import ApplicationServices

/// Notion desktop. Notion keeps each window's tabs in state.json and rewrites it as its windows change,
/// so tabs are read from there and joined to on-screen windows by frame and active tab title.
/// Restores with File ▸ New Window (which opens on the current desktop without activating Notion),
/// then one notion:// link per tab: the first replaces the new window's starting tab, the rest open as tabs.
enum NotionAdapter {
    static let bundleID = "notion.id"

    private static let stateURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Notion/state.json")

    private struct State: Decodable {
        struct History: Decodable { let appRestorationState: Restoration? }
        struct Restoration: Decodable { let windows: [WindowState] }
        let history: History
    }

    struct WindowState: Decodable {
        struct DisplayState: Decodable { let normalBounds: Bounds }
        struct Bounds: Decodable { let x: Double, y: Double, width: Double, height: Double }
        struct Tab: Decodable { let tabId: String; let url: String; let title: String? }
        let windowId: String
        let displayState: DisplayState
        let activeTabIdMap: [String: String]?
        let activeTabSectionId: String?
        let tabs: [Tab]

        var frame: CGRect {
            let b = displayState.normalBounds
            return CGRect(x: b.x, y: b.y, width: b.width, height: b.height)
        }
        var activeIndex: Int? {
            guard let id = activeTabIdMap?[activeTabSectionId ?? "ungrouped"] else { return nil }
            return tabs.firstIndex { $0.tabId == id }
        }
    }

    static let unmatchedNote = "A Notion window stayed open because Park couldn’t read its tabs. Click the window once, then park again."

    // MARK: Capture

    /// What to park for each Notion window on this desktop. A window with no entry couldn't be matched
    /// to Notion's saved state, so it stays open.
    static func capture(_ windows: [ParkableWindow]) -> [CGWindowID: ParkedWindow.Content] {
        match(windows, readStates())
    }

    static func readStates() -> [WindowState] {
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return [] }
        return state.history.appRestorationState?.windows ?? []
    }

    /// Notion saves a window only after it has had focus, and a new window starts with a copy of another
    /// window's frame. So a window is matched only when exactly one saved window has its frame AND its
    /// active tab's title is the window's title. Anything else stays open.
    static func match(_ windows: [ParkableWindow], _ states: [WindowState]) -> [CGWindowID: ParkedWindow.Content] {
        var result: [CGWindowID: ParkedWindow.Content] = [:]
        for window in windows {
            guard let title = window.title, !title.isEmpty else { continue }
            let candidates = states.filter { state in
                guard state.frame.isClose(to: window.frame), let active = state.activeIndex else { return false }
                return state.tabs[active].title == title
            }
            guard candidates.count == 1, let state = candidates.first, let active = state.activeIndex else { continue }
            let tabs = state.tabs.compactMap { tab -> BrowserTab? in
                guard deepLink(tab.url) != nil else { return nil }
                return BrowserTab(url: tab.url, title: tab.title ?? "")
            }
            // Every tab must be reopenable, or the window isn't parked at all.
            guard tabs.count == state.tabs.count else { continue }
            result[window.windowID] = .notion(tabs: tabs, activeIndex: active)
        }
        return result
    }

    /// https://app.notion.com/p/… → notion://app.notion.com/p/…, optionally asking for a new tab.
    /// Only Notion's own pages are reopened.
    static func deepLink(_ url: String, newTab: Bool = false) -> URL? {
        guard var parts = URLComponents(string: url), parts.scheme == "https",
              let host = parts.host, host == "notion.so" || host.hasSuffix(".notion.so") || host == "notion.com" || host.hasSuffix(".notion.com")
        else { return nil }
        parts.scheme = "notion"
        if newTab {
            parts.queryItems = (parts.queryItems ?? []) + [URLQueryItem(name: "deepLinkOpenNewTab", value: "true")]
        }
        return parts.url
    }

    /// The page a URL shows, for spotting tabs already open in another window.
    static func pageKey(_ url: String) -> String? {
        guard let parts = URLComponents(string: url), let host = parts.host else { return nil }
        return host + parts.path
    }

    // MARK: Restore

    /// Reopens one parked Notion window with its tabs on the current desktop.
    static func restore(tabs: [BrowserTab], activeIndex: Int, frame: CGRect?) -> Bool {
        let wasRunning = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).contains { !$0.isTerminated }
        guard !tabs.isEmpty, let app = Launcher.ensureRunning(bundleID: bundleID, settle: wasRunning ? 0 : 4) else { return false }
        let pid = app.processIdentifier
        let before = Set(AX.windows(pid: pid).map(\.1))

        // A link to a page that is already open makes Notion jump to that tab, maybe on another desktop.
        let openElsewhere = Set(readStates().flatMap(\.tabs).compactMap { pageKey($0.url) })

        AXMenu.click(pid: pid, "File", "New Window")
        var created: (AXUIElement, CGWindowID)?
        let deadline = Date().addingTimeInterval(8)
        while created == nil && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            created = AX.windows(pid: pid).first { !before.contains($0.1) }
        }
        guard let (window, _) = created else { return false }

        // Open the active tab last so it ends up selected. The first link replaces the starting tab.
        var ordered = tabs
        if tabs.indices.contains(activeIndex) { ordered.append(ordered.remove(at: activeIndex)) }
        var opened = 0
        for (index, tab) in ordered.enumerated() {
            if index > 0, let key = pageKey(tab.url), openElsewhere.contains(key) { continue }
            guard let url = deepLink(tab.url, newTab: opened > 0) else { continue }
            NSWorkspace.shared.open(url, configuration: .background)
            opened += 1
            Thread.sleep(forTimeInterval: 1.5)
        }

        if let frame { AX.setFrame(window, Screens.fit(frame)) }
        return opened > 0
    }
}
