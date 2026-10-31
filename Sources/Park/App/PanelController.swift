import AppKit
import SwiftUI

/// A borderless panel that drops down from the menu bar icon, sized to fit its SwiftUI content.
final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) {
        (delegate as? PanelController)?.close()
    }
}

/// The blurred, translucent background macOS uses for popovers and menus.
struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    static let width: CGFloat = 340
    private static let cornerRadius: CGFloat = 14

    private let panel: Panel
    private let model: AppModel
    private weak var statusButton: NSStatusBarButton?
    private var outsideClickMonitor: Any?
    /// Guards the close animation's completion against a reopen that happened mid-animation.
    private var generation = 0

    var isOpen: Bool { panel.isVisible }
    /// While pinned (the guided tour), clicking elsewhere doesn't close the panel.
    var isPinned = false
    var frame: NSRect { panel.frame }
    var windowNumber: Int { panel.windowNumber }

    init(model: AppModel, statusButton: NSStatusBarButton) {
        self.model = model
        self.statusButton = statusButton
        panel = Panel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 200),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        super.init()

        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .none
        panel.delegate = self

        let root = PanelView(onHeightChange: { [weak self] height in
            self?.resize(toHeight: height)
        })
        .environment(model)
        .background(VisualEffect(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
        )
        .frame(maxHeight: .infinity, alignment: .top)
        .ignoresSafeArea()

        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        // A borderless panel has no title bar; don't let SwiftUI inset the content for one.
        hosting.safeAreaRegions = []
        panel.contentView = hosting

        model.dismissPanel = { [weak self] in self?.close() }
    }

    func toggle() {
        isOpen ? close() : open()
    }

    func open() {
        generation += 1
        model.openCount += 1
        model.refresh()
        position()
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
        statusButton?.highlight(true)
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard self?.isPinned == false else { return }
            self?.close()
        }
    }

    func close() {
        guard panel.isVisible else { return }
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
        statusButton?.highlight(false)
        let closing = generation
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.1
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == closing else { return }
                self.panel.orderOut(nil)
            }
        })
    }

    func windowDidResignKey(_ notification: Notification) {
        // Clicking another app's window closes the panel, like a menu.
        guard !isPinned else { return }
        close()
    }

    // MARK: - Where things are on screen

    /// Whether Park's menu bar icon can actually be seen. A full menu bar on a notched Mac hides
    /// the newest icons behind the camera housing, and macOS then doesn't show them at all.
    var isStatusItemVisible: Bool {
        guard let button = statusButton, let window = button.window, window.isVisible,
              window.occlusionState.contains(.visible) else { return false }
        let rect = window.convertToScreen(button.convert(button.bounds, to: nil))
        guard rect.width > 0, let screen = window.screen ?? NSScreen.main, screen.frame.intersects(rect) else { return false }
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let notch = NSRect(x: left.maxX, y: left.minY, width: right.minX - left.maxX, height: left.height)
            if notch.intersects(rect.insetBy(dx: 2, dy: 2)) { return false }
        }
        return true
    }

    /// Park's menu bar icon on screen, or, when it's hidden, the spot just right of the notch where
    /// the panel opens instead. The tour and the intro effect start here.
    var statusAnchor: NSRect {
        if isStatusItemVisible, let button = statusButton, let window = button.window {
            return window.convertToScreen(button.convert(button.bounds, to: nil))
        }
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        let x = (screen.auxiliaryTopRightArea?.minX ?? screen.frame.midX) + 24
        return NSRect(x: x, y: screen.frame.maxY - max(menuBarHeight, 24), width: 24, height: max(menuBarHeight, 24))
    }

    /// A panel element's frame in screen coordinates.
    func screenRect(for anchor: TourAnchor) -> NSRect? {
        guard panel.isVisible, let local = model.anchors[anchor] else { return nil }
        let origin = panel.frame.origin, height = panel.frame.height
        return NSRect(x: origin.x + local.minX, y: origin.y + height - local.maxY, width: local.width, height: local.height)
    }

    // MARK: - Layout

    private func position() {
        // When the icon is hidden behind the notch, open just right of it instead of nowhere.
        let buttonRect = statusAnchor
        let screen = (isStatusItemVisible ? statusButton?.window?.screen : nil) ?? NSScreen.main
        let visible = screen?.visibleFrame ?? .zero
        let height = panel.frame.height

        var x = buttonRect.midX - Self.width / 2
        x = min(max(x, visible.minX + 8), visible.maxX - Self.width - 8)
        let top = buttonRect.minY - 6
        panel.setFrame(NSRect(x: x, y: top - height, width: Self.width, height: height), display: false)
    }

    /// Keeps the top edge pinned under the menu bar while the content grows or shrinks.
    private func resize(toHeight height: CGFloat) {
        let height = ceil(height)
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        let top = frame.maxY
        frame.size.height = height
        frame.origin.y = top - height
        panel.setFrame(frame, display: true, animate: false)
        panel.invalidateShadow()
    }
}
