import Foundation

/// PARK_DEV_INSTANCE=1 runs a separate test copy alongside the real Park: its own settings and parked
/// desktops, no single-instance hand-off, no login item. For trying first-run flows without touching
/// the installed app.
enum DevMode {
    static let isOn = ProcessInfo.processInfo.environment["PARK_DEV_INSTANCE"] == "1"
    static let arguments = CommandLine.arguments

    /// `--tour` starts the guided tour on launch, whatever has been seen before.
    static var forcesTour: Bool { arguments.contains("--tour") }
    /// `--tour-autoplay` presses each button by itself, for recording the tour.
    static var autoplay: Bool { arguments.contains("--tour-autoplay") }
    /// `--tour-shots <dir>` captures every step's windows into a folder.
    static var shotsDirectory: URL? {
        guard let i = arguments.firstIndex(of: "--tour-shots"), i + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[i + 1], isDirectory: true)
    }
}

/// Park's settings. A dev instance keeps its own, so it never changes the real app's.
let Defaults: UserDefaults = DevMode.isOn ? (UserDefaults(suiteName: "com.spencereverett.park.dev") ?? .standard) : .standard
