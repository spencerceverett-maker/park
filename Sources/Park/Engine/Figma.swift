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

    enum Capture: Equatable {
        case content(ParkedWindow.Content)
        /// The window can't be parked faithfully; it stays open and the reason is shown.
        case keepOpen(String)
    }

    /// What to park for each Figma window on this desktop, keyed by window ID. A window with no entry
    /// couldn't be matched to Figma's saved state, so it stays open.
    static func capture(_ windows: [ParkableWindow]) -> [CGWindowID: Capture] {
        var result: [CGWindowID: Capture] = [:]
        // Figma writes new windows to settings.json a few seconds late; give it a moment before giving up.
        for attempt in 0..<3 {
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

    /// Settings list Figma windows on every desktop, and maximized windows on two desktops share a frame.
    /// A window is matched only when exactly one saved window fits; anything ambiguous stays open.
    private static func match(_ windows: [ParkableWindow], _ states: [WindowState]) -> [CGWindowID: Capture] {
        var result: [CGWindowID: Capture] = [:]
        for window in windows {
            var candidates = states.filter { $0.frame.isClose(to: window.frame) }
            if candidates.count > 1 {
                candidates = candidates.filter { $0.activeTab?.title == window.title }
            } else if candidates.isEmpty, let title = window.title, !title.isEmpty {
                // Maximized windows are stored with a slightly different height; fall back to a unique title.
                let byTitle = states.filter { $0.activeTab?.title == title }
                if byTitle.count == 1 { candidates = byTitle }
            }
            guard candidates.count == 1, let state = candidates.first else { continue }

            if state.tabs.isEmpty {
                result[window.windowID] = .content(.app)   // only the file browser
                continue
            }
            if state.tabs.contains(where: { $0.params.contains("localFileKey=") }) {
                result[window.windowID] = .keepOpen("A Figma window stayed open because it has an unsaved local file.")
                continue
            }
            // design, FigJam and Slides files all live under /file/; prototypes and presenter views don't.
            guard state.tabs.allSatisfy({ $0.path.hasPrefix("/file/") }) else {
                result[window.windowID] = .keepOpen("A Figma window stayed open because it has a prototype or presentation tab Park can’t reopen.")
                continue
            }
            let files = state.tabs.map { FigmaFile(url: deepLink($0), title: $0.title) }
            let active = state.tabs.firstIndex { $0.path == state.activeTabPath } ?? 0
            result[window.windowID] = .content(.figma(files: files, activeIndex: active))
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
        // A busy Figma can report the click as failed and still open the window, so judge by the window.
        AXMenu.click(pid: pid, "File", "New Window")
        var created: AXUIElement?
        let deadline = Date().addingTimeInterval(8)
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
            guard let url = URL(string: file.url), url.scheme == "figma" else { continue }
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
