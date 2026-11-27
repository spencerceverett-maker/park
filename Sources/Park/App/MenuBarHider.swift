import AppKit

/// Hides other apps' menu bar icons behind Park.
///
/// A divider item sits to the left of Park's icon. While collapsed, the divider is made very wide,
/// so macOS pushes every icon to its left off the screen. While expanded, it shrinks to a thin line
/// and those icons come back. You choose which icons hide by ⌘-dragging them across the line.
/// This uses only the public status item API, so it needs no extra permission.
@MainActor
final class MenuBarHider {
    /// Wide enough to push the hidden icons past the left edge of any screen.
    private static let collapsedLength: CGFloat = 10_000
    private static let expandedLength: CGFloat = 13
    /// How long hidden icons stay visible after the panel closes, so you can reach one.
    private static let lingerDelay: TimeInterval = 2.5

    private let parkButton: NSStatusBarButton
    private var divider: NSStatusItem?
    private var collapseTimer: Timer?

    private(set) var isExpanded = false

    init(parkButton: NSStatusBarButton) {
        self.parkButton = parkButton
    }

    var isEnabled: Bool { divider != nil }

    /// Adds or removes the divider. A new divider starts expanded when `expanded` is true,
    /// so turning the feature on from the open panel shows the line to drag icons across.
    func setEnabled(_ enabled: Bool, expanded: Bool = false) {
        if enabled, divider == nil {
            // A new status item goes to the left of the existing ones, so this lands just left of Park.
            let item = NSStatusBar.system.statusItem(withLength: Self.expandedLength)
            item.autosaveName = "ParkDivider"
            item.button?.image = Self.lineImage
            item.button?.image?.accessibilityDescription = "Park: icons to the left of this line hide"
            divider = item
            // Start open and collapse after the pause: right after launch macOS hasn't placed the
            // items yet, so the check that keeps Park itself visible can't run until then.
            expand()
            if !expanded { collapseSoon() }
        } else if !enabled, let item = divider {
            collapseTimer?.invalidate()
            NSStatusBar.system.removeStatusItem(item)
            divider = nil
            isExpanded = false
        }
    }

    /// Shows the hidden icons, for example while Park's panel is open.
    func expand() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        guard let divider else { return }
        divider.length = Self.expandedLength
        isExpanded = true
    }

    /// Hides the icons again after a short pause. It waits while the pointer is in the menu bar or
    /// another app's menu is open, because you're probably using one of the revealed icons.
    func collapseSoon() {
        guard divider != nil else { return }
        collapseTimer?.invalidate()
        collapseTimer = Timer.scheduledTimer(withTimeInterval: Self.lingerDelay, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.isPointerInMenuBar || Self.isOtherMenuOpen { return }
                self.collapse()
            }
        }
    }

    private func collapse() {
        collapseTimer?.invalidate()
        collapseTimer = nil
        guard let divider else { return }
        // If the divider was dragged to the right of Park, collapsing would hide Park too. Stay open.
        guard isDividerLeftOfPark else { expand(); return }
        divider.length = Self.collapsedLength
        isExpanded = false
    }

    // MARK: - Checks

    private var isDividerLeftOfPark: Bool {
        guard let dividerX = divider?.button?.window?.frame.minX,
              let parkX = parkButton.window?.frame.minX else { return true }
        return dividerX < parkX
    }

    private var isPointerInMenuBar: Bool {
        let point = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) else { return false }
        let barHeight = max(screen.frame.maxY - screen.visibleFrame.maxY, 24)
        return point.y >= screen.frame.maxY - barHeight
    }

    /// True when another app shows a menu, such as one from a revealed icon. Window layer and owner
    /// are readable without the Screen Recording permission.
    private static var isOtherMenuOpen: Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return false }
        let menuLevel = Int(CGWindowLevelForKey(.popUpMenuWindow))
        return windows.contains { info in
            (info[kCGWindowLayer as String] as? Int) == menuLevel
                && (info[kCGWindowOwnerPID as String] as? Int32) != me
        }
    }

    // MARK: - Look

    /// A short vertical line, drawn as a template so it follows the menu bar's color.
    private static let lineImage: NSImage = {
        let image = NSImage(size: NSSize(width: 4, height: 16), flipped: false) { rect in
            // Half strength: a quiet guide, not another icon.
            NSColor.black.withAlphaComponent(0.5).setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 1, width: 2, height: rect.height - 2), xRadius: 1, yRadius: 1).fill()
            return true
        }
        image.isTemplate = true
        return image
    }()
}
