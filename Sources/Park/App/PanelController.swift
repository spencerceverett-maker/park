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
        close()
    }

    // MARK: - Layout

    private func position() {
        guard let button = statusButton, let buttonWindow = button.window else { return }
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen ?? NSScreen.main
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
