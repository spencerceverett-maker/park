import AppKit

/// Moves Park into an Applications folder when it's opened from somewhere temporary (the disk image,
/// Downloads), then relaunches from there. macOS ties login items and permissions to where an app lives,
/// so this belongs before anything else on first launch.
enum Installer {
    /// Passed to the copy launched from Applications, so the single-instance check lets it start
    /// while this copy is still quitting.
    static let relaunchArgument = "--after-move"

    static var bundleURL: URL { Bundle.main.bundleURL.resolvingSymlinksInPath() }

    static var isInApplicationsFolder: Bool {
        let parent = bundleURL.deletingLastPathComponent().path
        let userApps = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path
        return parent == "/Applications" || parent.hasPrefix("/Applications/") || parent == userApps || parent.hasPrefix(userApps + "/")
    }

    /// Running straight from the mounted disk image.
    static var isOnDiskImage: Bool { bundleURL.path.hasPrefix("/Volumes/") }

    /// /Applications when it's writable (the usual case), otherwise ~/Applications.
    static var destination: URL {
        let system = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let folder = FileManager.default.isWritableFile(atPath: system.path)
            ? system
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        return folder.appendingPathComponent(bundleURL.lastPathComponent)
    }

    enum Failure: LocalizedError {
        case copy(Error)
        var errorDescription: String? {
            switch self {
            case .copy(let error): return "Park couldn’t be moved: \(error.localizedDescription) You can drag it to Applications yourself."
            }
        }
    }

    /// Copies Park into Applications, replacing an older copy, opens the new copy, and quits this one.
    /// When run from the disk image, the image is ejected once this copy has quit.
    static func moveToApplicationsAndRelaunch() throws {
        let target = destination
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: target.path) {
                // An older Park: put it in the Trash rather than deleting it outright.
                try fm.trashItem(at: target, resultingItemURL: nil)
            }
            try fm.copyItem(at: bundleURL, to: target)
        } catch {
            throw Failure.copy(error)
        }

        if isOnDiskImage {
            // Eject the disk image after this process exits (it can't eject the volume it runs from).
            let volume = "/Volumes/" + bundleURL.pathComponents[2]
            let eject = Process()
            eject.executableURL = URL(fileURLWithPath: "/bin/sh")
            eject.arguments = ["-c", "sleep 1.5; /usr/bin/hdiutil detach \"$0\" -quiet", volume]
            try? eject.run()
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.arguments = [relaunchArgument]
        NSWorkspace.shared.openApplication(at: target, configuration: configuration) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}
