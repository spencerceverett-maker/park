import AppKit
import Darwin
import SQLite3

/// Warp terminal. Window, tab and split layout come from Warp's own SQLite state (read-only, WAL mode),
/// working directories and running commands from the shell processes. Restores through a temporary
/// Warp launch configuration, which recreates tabs, splits and directories in one window.
enum WarpAdapter {
    static let bundleID = "dev.warp.Warp-Stable"

    private static let databasePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Group Containers/2BBY89MBSN.dev.warp/Library/Application Support/dev.warp.Warp-Stable/warp.sqlite").path
    private static let launchDirectory = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".warp/launch_configurations")

    // MARK: Capture

    private struct WindowState {
        /// Warp stores y relative to the primary screen's height; this is the AX/CG top-left frame.
        let frame: CGRect
        let activeTabIndex: Int
        var tabs: [TerminalTab]
    }

    /// One shell's live state, joined to a pane by session UUID or, failing that, by directory.
    private struct Shell { let pid: pid_t; let directory: String?; let sessionUUID: String?; let running: String? }

    static func capture(_ windows: [ParkableWindow]) -> [CGWindowID: ParkedWindow.Content] {
        let states = readWindowStates()
        var used = Set<Int>()
        var result: [CGWindowID: ParkedWindow.Content] = [:]
        for window in windows {
            guard let index = states.indices.first(where: { !used.contains($0) && states[$0].frame.isClose(to: window.frame) })
            else { continue }
            used.insert(index)
            result[window.windowID] = .terminal(tabs: states[index].tabs, activeIndex: states[index].activeTabIndex)
        }
        return result
    }

    private static func readWindowStates() -> [WindowState] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(databasePath, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(db) }

        let nodes = rows(db, """
            SELECT n.id, n.tab_id, n.parent_pane_node_id AS parent, n.is_leaf, b.horizontal,
                   l.is_focused, tp.uuid, tp.cwd
            FROM pane_nodes n
            LEFT JOIN pane_branches b ON b.pane_node_id = n.id
            LEFT JOIN pane_leaves l ON l.pane_node_id = n.id
            LEFT JOIN terminal_panes tp ON tp.id = n.id
            ORDER BY n.id
            """)
        let shells = liveShells()
        var claimed = Set<pid_t>()

        func build(_ id: Int) -> TerminalLayout? {
            guard let node = nodes.first(where: { $0["id"] as? Int == id }) else { return nil }
            if (node["is_leaf"] as? Int) == 1 {
                let uuid = (node["uuid"] as? Data).map { $0.map { String(format: "%02x", $0) }.joined() }
                var directory = node["cwd"] as? String
                var running: String?
                let exact = shells.first { $0.sessionUUID != nil && $0.sessionUUID == uuid }
                let byDirectory = shells.first { !claimed.contains($0.pid) && $0.sessionUUID == nil && $0.directory == directory }
                if let shell = exact ?? byDirectory {
                    claimed.insert(shell.pid)
                    directory = shell.directory ?? directory
                    running = shell.running
                }
                return .pane(directory: directory ?? NSHomeDirectory(), command: running, focused: (node["is_focused"] as? Int) == 1)
            }
            let children = nodes.filter { $0["parent"] as? Int == id }.compactMap { ($0["id"] as? Int).flatMap(build) }
            return .split(horizontal: (node["horizontal"] as? Int) == 1, panes: children)
        }

        let tabs = rows(db, "SELECT id, window_id, custom_title FROM tabs ORDER BY id")
        let screenHeight = NSScreen.screens.first?.frame.height ?? 0
        return rows(db, "SELECT * FROM windows ORDER BY id").map { window in
            let windowID = window["id"] as? Int
            let windowTabs: [TerminalTab] = tabs.filter { $0["window_id"] as? Int == windowID }.compactMap { tab in
                guard let root = nodes.first(where: { $0["tab_id"] as? Int == tab["id"] as? Int && $0["parent"] == nil }),
                      let rootID = root["id"] as? Int, let layout = build(rootID) else { return nil }
                return TerminalTab(title: tab["custom_title"] as? String, layout: layout)
            }
            let frame = CGRect(x: window["origin_x"] as? Double ?? 0,
                               y: (window["origin_y"] as? Double ?? 0) + screenHeight,
                               width: window["window_width"] as? Double ?? 0,
                               height: window["window_height"] as? Double ?? 0)
            return WindowState(frame: frame, activeTabIndex: window["active_tab_index"] as? Int ?? 0, tabs: windowTabs)
        }
    }

    /// Shells are children of Warp's `terminal-server` process, one tty each. The foreground process group
    /// of each tty tells whether something (a dev server, claude) is running in it.
    private static func liveShells() -> [Shell] {
        guard let warp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
        else { return [] }
        let processes = Processes.all()
        let server = processes.first { $0.ppid == warp && Processes.arguments($0.pid).args.contains("terminal-server") }?.pid ?? warp
        return processes.filter { $0.ppid == server }.map { shell in
            let onTTY = processes.filter { $0.tdev == shell.tdev && $0.pid != shell.pid }
            let uuid = onTTY.lazy.compactMap { Processes.arguments($0.pid).env["WARP_TERMINAL_SESSION_UUID"] }.first
            var running: String?
            if shell.tpgid > 0, shell.tpgid != shell.pgid, let leader = processes.first(where: { $0.pid == shell.tpgid }) {
                let args = Processes.arguments(leader.pid).args
                running = args.isEmpty ? leader.comm : Processes.displayCommand(args)
            }
            return Shell(pid: shell.pid, directory: Processes.workingDirectory(shell.pid),
                         sessionUUID: uuid?.lowercased().replacingOccurrences(of: "-", with: ""), running: running)
        }
    }

    // MARK: Restore

    /// Writes a launch configuration into Warp's folder, opens it, and removes it once Warp has read it.
    /// (Warp ignores launch configs outside that folder, and escaped slashes break parsing.)
    static func restore(tabs: [TerminalTab], activeIndex: Int) -> Bool {
        guard !tabs.isEmpty else { return false }
        let name = "park-\(UUID().uuidString.prefix(8).lowercased())"
        let file = launchDirectory.appendingPathComponent("\(name).yaml")
        do {
            try FileManager.default.createDirectory(at: launchDirectory, withIntermediateDirectories: true)
            try launchConfig(name: name, tabs: tabs, activeIndex: activeIndex).write(to: file, atomically: false, encoding: .utf8)
        } catch {
            return false
        }
        _ = Launcher.ensureRunning(bundleID: bundleID, settle: 2)
        Thread.sleep(forTimeInterval: 1)
        guard let url = URL(string: "warp://launch/\(name).yaml") else { return false }
        NSWorkspace.shared.open(url)
        DispatchQueue.global().asyncAfter(deadline: .now() + 5) {
            try? FileManager.default.removeItem(at: file)
        }
        return true
    }

    /// JSON is valid YAML, and JSONSerialization handles all quoting.
    private static func launchConfig(name: String, tabs: [TerminalTab], activeIndex: Int) throws -> String {
        func layout(_ node: TerminalLayout) -> [String: Any] {
            switch node {
            case .pane(let directory, _, let focused):
                var pane: [String: Any] = ["cwd": directory]
                if focused { pane["is_focused"] = true }
                return pane
            case .split(let horizontal, let panes):
                return ["split_direction": horizontal ? "horizontal" : "vertical", "panes": panes.map(layout)]
            }
        }
        let tabObjects: [[String: Any]] = tabs.map { tab in
            var object: [String: Any] = ["layout": layout(tab.layout)]
            if let title = tab.title { object["title"] = title }
            return object
        }
        let config: [String: Any] = [
            "name": name,
            "active_window_index": 0,
            "windows": [["active_tab_index": min(activeIndex, tabs.count - 1), "tabs": tabObjects]],
        ]
        let data = try JSONSerialization.data(withJSONObject: config, options: [.withoutEscapingSlashes, .sortedKeys])
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    // MARK: SQLite

    private static func rows(_ db: OpaquePointer?, _ sql: String) -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var result: [[String: Any]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for i in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, i))
                switch sqlite3_column_type(statement, i) {
                case SQLITE_INTEGER: row[name] = Int(sqlite3_column_int64(statement, i))
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement, i)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(statement, i))
                case SQLITE_BLOB:
                    if let bytes = sqlite3_column_blob(statement, i) {
                        row[name] = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, i)))
                    }
                default: break
                }
            }
            result.append(row)
        }
        return result
    }
}

extension CGRect {
    func isClose(to other: CGRect, tolerance: CGFloat = 2) -> Bool {
        abs(minX - other.minX) <= tolerance && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}
