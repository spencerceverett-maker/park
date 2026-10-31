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

        // One Park at a time: a second launch asks the running one to show its panel, then quits.
        // (After a move to Applications the old copy is still quitting, so that launch goes ahead.)
        if !DevMode.isOn, !arguments.contains(Installer.relaunchArgument), SingleInstance.handOffToRunningCopy() { return }

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
    /// The carousel walkthrough, kept for reference (branch `onboarding-carousel`); the guided tour replaced it.
    private let onboarding = OnboardingController()
    private var tour: GuidedTour!
    private var moveCard: MoveCardWindow?

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
        // Turning it off in the ··· menu is remembered and never overridden. Only from Applications:
        // a login item registered from the disk image or Downloads would point at the wrong copy.
        if !DevMode.isOn && Installer.isInApplicationsFolder && !Defaults.bool(forKey: "didSetUpLoginItem") {
            LoginItem.set(true)
            Defaults.set(true, forKey: "didSetUpLoginItem")
        }

        // ⌃⌥P opens the panel, even when the menu bar icon is hidden behind the notch.
        panelHotKey = HotKey(keyCode: 35, modifiers: [.control, .option]) { [weak self] in
            self?.panel.toggle()
            NotificationCenter.default.post(name: .parkPanelHotKey, object: nil)
        }
        // ⌃⌥⌘P parks the current desktop without opening the panel.
        hotKey = HotKey(keyCode: 35, modifiers: [.control, .option, .command]) { [weak self] in
            self?.parkFromHotKey()
        }

        tour = GuidedTour(model: model, panel: panel)
        model.showOnboarding = { [weak self] in self?.tour.start(playIntro: false) }
        SingleInstance.listen { [weak self] in self?.panel.open() }

        let finished = Defaults.bool(forKey: GuidedTour.didCompleteKey) || Defaults.bool(forKey: OnboardingController.didFinishKey)
        if !finished || DevMode.forcesTour {
            // First launch: the tour, on the real desktop. The intro plays once, never after the relaunch
            // from "Move to Applications".
            let playIntro = !Defaults.bool(forKey: GuidedTour.didPlayIntroKey) || DevMode.forcesTour
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.tour.start(playIntro: playIntro) }
        } else if !Installer.isInApplicationsFolder && !DevMode.isOn {
            // Opened from the disk image or Downloads again: offer the move on its own.
            let card = MoveCardWindow()
            card.onNotNow = { [weak self] in self?.moveCard = nil }
            card.show()
            moveCard = card
        } else if !AXIsProcessTrusted() {
            // Access was turned off since: the panel's permission step explains it.
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
            // Anything worth reading (a window left open, an error) needs the panel; success is a quick pulse.
            if model.errorMessage != nil { panel.open() } else { Feedback.flash(statusItem.button) }
        }
    }
}

/// Keeps Park to one running copy, using a distributed notification between copies.
enum SingleInstance {
    private static let showPanel = Notification.Name(DevMode.isOn ? "com.spencereverett.park.dev.showPanel" : "com.spencereverett.park.showPanel")

    /// Returns true if another Park is running; that copy is asked to show its panel.
    static func handOffToRunningCopy() -> Bool {
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0.processIdentifier != me && !$0.isTerminated }
        guard !others.isEmpty else { return false }
        DistributedNotificationCenter.default().postNotificationName(showPanel, object: nil, userInfo: nil, deliverImmediately: true)
        return true
    }

    static func listen(_ handler: @escaping @MainActor () -> Void) {
        DistributedNotificationCenter.default().addObserver(forName: showPanel, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
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
