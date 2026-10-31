import AppKit
import SwiftUI

@main
enum ParkMain {
    static func main() {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--snapshot"), index + 1 < arguments.count {
            MainActor.assumeIsolated { Snapshot.render(to: arguments[index + 1], arguments: arguments) }
            return
        }

        if DevCommands.run(arguments) { return }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: PanelController!
    private var hotKey: HotKey?
    private var panelHotKey: HotKey?
    private let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = StatusIcon.image
            button.image?.accessibilityDescription = "Park"
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        panel = PanelController(model: model, statusButton: statusItem.button!)

        // A menu bar app you forget to launch is no help: open at login by default.
        // Turning it off in the ··· menu is remembered and never overridden.
        if !UserDefaults.standard.bool(forKey: "didSetUpLoginItem") {
            LoginItem.set(true)
            UserDefaults.standard.set(true, forKey: "didSetUpLoginItem")
        }

        // ⌃⌥P opens the panel, even when the menu bar icon is hidden behind the notch.
        panelHotKey = HotKey(keyCode: 35, modifiers: [.control, .option]) { [weak self] in
            self?.panel.toggle()
        }
        // ⌃⌥⌘P parks the current desktop without opening the panel.
        hotKey = HotKey(keyCode: 35, modifiers: [.control, .option, .command]) { [weak self] in
            self?.parkFromHotKey()
        }

        if !AXIsProcessTrusted() {
            // First launch: open the panel so the permission step is the first thing seen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.panel.open() }
        }
    }

    @objc private func togglePanel() {
        panel.toggle()
    }

    private func parkFromHotKey() {
        guard AXIsProcessTrusted() else { panel.open(); return }
        Task { @MainActor in
            let preview = await model.engine.preview()
            guard preview.windowCount > 0 else { NSSound.beep(); return }
            await model.park()
            Feedback.flash(statusItem.button)
        }
    }
}

enum Feedback {
    /// Briefly pulses the menu bar icon to confirm a hotkey park.
    static func flash(_ button: NSStatusBarButton?) {
        guard let button else { return }
        button.highlight(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { button.highlight(false) }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}
