import AppKit
import ApplicationServices

/// Figma desktop. Figma keeps its open windows and tabs in settings.json, rewritten live, so tabs
/// are read from there and joined to on-screen windows by frame (falling back to the active tab's title).
enum FigmaAdapter {
    static let bundleID = "com.figma.Desktop"

    private static let settingsURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Figma/settings.json")

    private struct Settings: Decodable { let windows: [WindowState] }

    private struct WindowState: Decodable {
        let id: String
        let x: Double, y: Double, width: Double, height: Double
        let tabs: [Tab]
        let activeTabPath: String?
        var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
        var activeTab: Tab? { tabs.first { $0.path == activeTabPath } }
    }

    struct Tab: Decodable {
        let path: String      // "/file/<key>"
        let title: String
        let params: String    // "?node-id=…&p=f&viewport=…&t=…"
    }

    /// Parked content for each Figma window on this desktop, keyed by window ID. Windows showing only the
    /// file browser come back as `.app`. Windows whose tabs can't be read are left out, so they stay open.
    static func capture(_ windows: [ParkableWindow]) -> [CGWindowID: ParkedWindow.Content] {
        var result: [CGWindowID: ParkedWindow.Content] = [:]
        // Figma writes new windows to settings.json a few seconds late; give it a moment before giving up.
        for attempt in 0..<4 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 1.5) }
            result = match(windows, readStates())
            if result.count == windows.count { break }
        }
        return result
    }

    private static func readStates() -> [WindowState] {
        guard let data = try? Data(contentsOf: settingsURL),
              let states = try? JSONDecoder().decode(Settings.self, from: data).windows else { return [] }
        return states
    }

    private static func match(_ windows: [ParkableWindow], _ states: [WindowState]) -> [CGWindowID: ParkedWindow.Content] {
        var used = Set<String>()
        var result: [CGWindowID: ParkedWindow.Content] = [:]
        for window in windows {
            let byFrame = states.first { !used.contains($0.id) && $0.frame.isClose(to: window.frame) }
            let byTitle = states.first { !used.contains($0.id) && $0.activeTab?.title == window.title }
            guard let state = byFrame ?? byTitle else { continue }
            used.insert(state.id)
            // Local, never-saved files can't be reopened by link.
            let tabs = state.tabs.filter { !$0.params.contains("localFileKey=") && $0.path.hasPrefix("/file/") }
            if tabs.isEmpty {
                if state.tabs.isEmpty { result[window.windowID] = .app }
                continue
            }
            let files = tabs.map { FigmaFile(url: deepLink($0), title: $0.title) }
            let active = tabs.firstIndex { $0.path == state.activeTabPath } ?? 0
            result[window.windowID] = .figma(files: files, activeIndex: active)
        }
        return result
    }

    /// `figma://file/<key>/<slug>?<params>` opens a file as a new tab in the focused window and keeps the
    /// page, selection and viewport. Figma's per-session tokens are dropped.
    static func deepLink(_ tab: Tab) -> String {
        let key = tab.path.split(separator: "/").last.map(String.init) ?? ""
        let slug = tab.title.replacingOccurrences(of: " ", with: "-")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "file"
        let params = tab.params.hasPrefix("?") ? String(tab.params.dropFirst()) : tab.params
        let kept = params.split(separator: "&")
            .filter { !$0.hasPrefix("t=") && !$0.hasPrefix("fuid=") }
            .joined(separator: "&")
        return "figma://file/\(key)/\(slug)" + (kept.isEmpty ? "" : "?\(kept)")
    }

    /// Reopens one parked Figma window with all its tabs on the current desktop.
    /// File ▸ New Window creates the window here; each deep link then lands in it as a tab.
    static func restore(files: [FigmaFile], activeIndex: Int, frame: CGRect?) -> Bool {
        guard let app = Launcher.ensureRunning(bundleID: bundleID, settle: 4) else { return false }
        let pid = app.processIdentifier
        let before = Set(AX.windows(pid: pid).map(\.1))

        // Create the window before activating Figma: activating an app whose windows are all on other
        // desktops switches you to one of them. New windows always appear on the current desktop.
        guard AXMenu.click(pid: pid, "File", "New Window") else { return false }
        var created: AXUIElement?
        let deadline = Date().addingTimeInterval(5)
        while created == nil && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
            created = AX.windows(pid: pid).first { !before.contains($0.1) }?.0
        }
        guard let window = created else { return false }
        AXUIElementSetAttributeValue(window, kAXMainAttribute as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(window, kAXRaiseAction as CFString)
        app.activate()
        Thread.sleep(forTimeInterval: 1)

        // Open the active tab last so it ends up selected.
        var ordered = files
        if files.indices.contains(activeIndex) { ordered.append(ordered.remove(at: activeIndex)) }
        for file in ordered {
            guard let url = URL(string: file.url) else { continue }
            NSWorkspace.shared.open(url)
            Thread.sleep(forTimeInterval: 1.5)
        }

        if let frame { AX.setFrame(window, frame) }
        return true
    }
}

/// Clicks an app's menu bar item through Accessibility. Acts on the app's focused window.
enum AXMenu {
    @discardableResult
    static func click(pid: pid_t, _ menu: String, _ item: String) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        guard let bar = AX.element(app, kAXMenuBarAttribute) else { return false }
        let tops: [AXUIElement] = AX.attr(bar, kAXChildrenAttribute) ?? []
        for top in tops where (AX.attr(top, kAXTitleAttribute) as String?) == menu {
            let menus: [AXUIElement] = AX.attr(top, kAXChildrenAttribute) ?? []
            for menu in menus {
                let items: [AXUIElement] = AX.attr(menu, kAXChildrenAttribute) ?? []
                for entry in items where (AX.attr(entry, kAXTitleAttribute) as String?) == item {
                    return AXUIElementPerformAction(entry, kAXPressAction as CFString) == .success
                }
            }
        }
        return false
    }
}
