import Foundation
import CoreGraphics

/// A parked desktop: everything that was open on one Space, saved so it can be reopened later.
struct Spot: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var name: String
    var createdAt: Date
    var windows: [ParkedWindow]
    /// Memory released by parking, measured from the affected apps' process footprints.
    var freedBytes: UInt64?

    /// Bundle IDs in first-seen order, one per app. Drives the icon stack.
    var bundleIDs: [String] {
        var seen = Set<String>()
        return windows.compactMap { seen.insert($0.bundleID).inserted ? $0.bundleID : nil }
    }

    /// "1 window" / "6 windows".
    var summary: String {
        windows.count == 1 ? "1 window" : "\(windows.count) windows"
    }
}

/// One window (or one app with no restorable state) as it was when parked.
struct ParkedWindow: Codable, Identifiable, Equatable, Hashable {
    var id = UUID()
    var bundleID: String
    var appName: String
    var title: String?
    /// Window frame in AppKit-agnostic top-left screen coordinates (as reported by AX/CG).
    var frame: CGRect?
    var content: Content

    enum Content: Codable, Equatable, Hashable {
        /// A Chromium browser window and its tabs, in order.
        case browser(tabs: [BrowserTab], activeIndex: Int, incognito: Bool)
        /// Figma desktop window with one or more file tabs.
        case figma(files: [FigmaFile], activeIndex: Int)
        /// Terminal window: tabs, each with its split panes and working directories.
        case terminal(tabs: [TerminalTab], activeIndex: Int)
        /// Finder window showing a folder.
        case folder(path: String)
        /// A document-based app window with a file open.
        case document(path: String)
        /// Nothing restorable beyond the app itself.
        case app
    }

    var tabCount: Int {
        switch content {
        case .browser(let tabs, _, _): return tabs.count
        case .figma(let files, _): return files.count
        case .terminal(let tabs, _): return tabs.count
        default: return 1
        }
    }
}

struct BrowserTab: Codable, Equatable, Hashable {
    var url: String
    var title: String
}

struct FigmaFile: Codable, Equatable, Hashable {
    /// Full https URL that reopens the file (keeps node-id when known).
    var url: String
    var title: String
}

struct TerminalTab: Codable, Equatable, Hashable {
    var title: String?
    var layout: TerminalLayout
}

indirect enum TerminalLayout: Codable, Equatable, Hashable {
    /// A shell. `command` is what was running when parked (e.g. "npm run dev"); it's shown, never re-run automatically.
    case pane(directory: String, command: String?, focused: Bool)
    case split(horizontal: Bool, panes: [TerminalLayout])

    var panes: [(directory: String, command: String?)] {
        switch self {
        case .pane(let directory, let command, _): return [(directory, command)]
        case .split(_, let panes): return panes.flatMap(\.panes)
        }
    }
}
