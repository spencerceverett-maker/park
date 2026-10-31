import AppKit
import SwiftUI

/// Every spacing, radius and timing value in one place.
enum Theme {
    static let outerPadding: CGFloat = 8
    static let rowPadding: CGFloat = 8
    static let rowRadius: CGFloat = 8
    static let rowHeight: CGFloat = 48
    static let maxVisibleRows = 6

    /// Parking-sign blue, Park's brand color (the website, the logo, the walkthrough).
    static let brand = Color(red: 0x1E / 255, green: 0x50 / 255, blue: 0xA8 / 255)

    static let hover = Color.primary.opacity(0.06)
    static let pressed = Color.primary.opacity(0.1)
    static let hairline = Color.primary.opacity(0.08)

    /// Critically damped: settles without overshoot.
    static let spring = Animation.spring(response: 0.32, dampingFraction: 1)
    static let quick = Animation.easeOut(duration: 0.12)

    static func title(_ text: Text) -> some View {
        text.font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
    }
}

/// App icons are looked up once and cached; NSWorkspace icon loads are not free.
enum AppIcons {
    private static var cache: [String: NSImage] = [:]

    static func icon(for bundleID: String) -> NSImage {
        if let cached = cache[bundleID] { return cached }
        let image: NSImage
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: .application)
        }
        cache[bundleID] = image
        return image
    }

    static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return bundleID }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}

enum RelativeTime {
    static func string(for date: Date, now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "Just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "\(Int(seconds / 3600))h ago" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if seconds < 6 * 86_400 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Joins names the way people write them: "Chrome", "Chrome and Figma", "Chrome, Figma and Warp", "Chrome, Figma and 2 more".
enum NameList {
    static func string(_ names: [String], limit: Int = 3) -> String {
        switch names.count {
        case 0: return ""
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default:
            if names.count <= limit {
                return names.dropLast().joined(separator: ", ") + " and " + names.last!
            }
            return names.prefix(limit - 1).joined(separator: ", ") + " and \(names.count - limit + 1) more"
        }
    }
}
