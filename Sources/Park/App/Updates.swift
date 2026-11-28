import AppKit
import Sparkle

/// In-app updates through Sparkle. The feed is `appcast.xml` on the latest GitHub release, which
/// `scripts/publish.sh` writes and signs. Sparkle asks once (on the second launch) whether to check
/// automatically, then checks about once a day.
@MainActor
final class Updates: NSObject, SPUStandardUserDriverDelegate {
    static let shared = Updates()

    private var controller: SPUStandardUpdaterController!

    override private init() {
        super.init()
        // Dev builds and snapshot renders don't check: they aren't signed releases.
        let start = !DevMode.isOn && !Snapshot.isRendering
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: nil, userDriverDelegate: self)
    }

    /// Starts the updater. Called once at launch.
    func start() { _ = controller }

    /// The ··· menu's "Check for Updates…".
    func checkNow() {
        NSApp.activate()
        controller.checkForUpdates(nil)
    }

    // MARK: - SPUStandardUserDriverDelegate

    // Park lives in the menu bar with no Dock icon, so a scheduled update alert could open behind
    // other windows. Bring Park forward when Sparkle shows it.
    // Sparkle calls these on the main thread.
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        MainActor.assumeIsolated {
            NSApp.activate()
            // Since macOS 14 a menu bar app can't take focus on its own, so the window would open
            // behind whatever you're using. Once Sparkle has shown it, put it in front anyway.
            DispatchQueue.main.async {
                for window in NSApp.windows where window.isVisible && Self.isSparkleWindow(window) {
                    window.orderFrontRegardless()
                }
            }
        }
    }

    private static func isSparkleWindow(_ window: NSWindow) -> Bool {
        guard let controller = window.windowController else { return false }
        return NSStringFromClass(type(of: controller)).hasPrefix("SU")
    }
}
