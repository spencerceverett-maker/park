import AppKit

/// The moment on first launch before the tour begins. Swappable: each case plays from Park's
/// menu bar icon (or where the panel opens when the icon is hidden), hands off to the tour partway
/// through, and finishes on its own. Reduce Motion skips straight to the hand-off.
@MainActor
enum IntroEffect {
    /// Soft shafts of dawn-blue light pouring down from the menu bar (IntroLight's Metal shader).
    case rays
    // case ripple — a single glassy ripple from the icon settling into a glow; drop in here.

    static var current: IntroEffect = .rays

    /// Plays the effect. Keep the returned object alive until `done` is called.
    func play(from anchor: NSRect, handoff: @escaping () -> Void, done: @escaping () -> Void) -> AnyObject? {
        switch self {
        case .rays:
            let player = IntroLight.Player()
            player.play(from: CGPoint(x: anchor.midX, y: anchor.midY), handoff: handoff, done: done)
            return player
        }
    }
}
