import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// What's on the current desktop right now, shown before parking.
struct DesktopPreview: Equatable {
    var windowCount: Int
    var bundleIDs: [String]
    var appNames: [String]
    /// Commands running in terminals on this desktop; they stop once their windows close.
    var runningCommands: [String] = []

    static let empty = DesktopPreview(windowCount: 0, bundleIDs: [], appNames: [])
}

/// A short-lived message at the bottom of the panel, optionally with an undo action.
struct Toast: Identifiable, Equatable {
    let id = UUID()
    var message: String
    var undoTitle = "Undo"
    var undo: (() -> Void)?

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

/// Coordinates the store, the engine and everything the panel displays.
@MainActor
@Observable
final class AppModel {
    let store: SpotStore
    let engine: Engine

    /// nil until the first look at the current desktop finishes.
    var preview: DesktopPreview?
    var hasAccessibility = AXIsProcessTrusted()
    var isParking = false
    var restoringID: Spot.ID?
    var justParkedID: Spot.ID?
    var toast: Toast?
    var memory = MemoryStats.current()
    var errorMessage: String?

    /// Called by the panel controller to close itself (e.g. right before restoring windows).
    var dismissPanel: () -> Void = {}

    private var toastTask: Task<Void, Never>?

    init(store: SpotStore = SpotStore(), engine: Engine = Engine()) {
        self.store = store
        self.engine = engine
        if !Snapshot.isRendering { store.recoverPending() }
    }

    /// Quit apps whose windows are all on the parked desktop. Frees the most memory.
    var quitApps: Bool {
        get { access(keyPath: \.quitApps); return UserDefaults.standard.object(forKey: "quitApps") as? Bool ?? true }
        set { withMutation(keyPath: \.quitApps) { UserDefaults.standard.set(newValue, forKey: "quitApps") } }
    }

    private var previewTask: Task<Void, Never>?

    /// Bumped each time the panel opens, so views can reset transient state like keyboard selection.
    var openCount = 0

    /// Refresh everything the panel shows. Called each time the panel opens.
    @MainActor
    func refresh() {
        hasAccessibility = AXIsProcessTrusted()
        memory = MemoryStats.current()
        guard hasAccessibility else { preview = .empty; return }
        previewTask?.cancel()
        previewTask = Task { @MainActor in
            let fresh = await engine.preview()
            guard !Task.isCancelled else { return }
            withAnimation(Theme.spring) { preview = fresh }
        }
    }

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
        }
    }

    @MainActor
    func park() async {
        guard !isParking else { return }
        isParking = true
        errorMessage = nil
        defer { isParking = false }

        do {
            let result = try await engine.parkCurrentDesktop(quitApps: quitApps)
            let spot = result.spot
            Log.write("parked \(spot.windows.count) windows (\(Set(spot.windows.map(\.appName)).sorted().joined(separator: ", "))); \(result.notes.count) notes")
            withAnimation(Theme.spring) {
                store.insert(spot)
                justParkedID = spot.id
            }
            SpotStore.clearPending()
            preview = await engine.preview()
            if let note = result.notes.first {
                errorMessage = note
            } else {
                showToast("Parked \(spot.summary)")
            }
            // Memory is released gradually as processes exit; measure once things settle.
            Task { @MainActor in
                if let freed = await engine.measureFreedMemory(for: spot) {
                    store.setFreedBytes(spot.id, freed)
                }
                memory = MemoryStats.current()
                try? await Task.sleep(for: .seconds(1.6))
                if justParkedID == spot.id { justParkedID = nil }
            }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    func restore(_ spot: Spot) async {
        guard restoringID == nil else { return }
        restoringID = spot.id
        defer { restoringID = nil }

        // Get the panel out of the way so restored windows come forward cleanly.
        dismissPanel()
        let failures = await engine.restore(spot)
        Log.write("restored \(spot.windows.count - failures.count) of \(spot.windows.count) windows; failed: \(failures.map(\.appName))")
        if failures.isEmpty {
            guard let index = store.spots.firstIndex(where: { $0.id == spot.id }) else { return }
            store.remove(spot.id)
            // Keep a way back for a while in case something didn't come back the way it should have.
            showToast("Restored “\(spot.name)”", undoTitle: "Put back", duration: .seconds(600)) { [weak self] in
                self?.store.restore(spot, at: index)
            }
        } else if failures.count == spot.windows.count {
            errorMessage = "Couldn’t reopen “\(spot.name)”. It’s still here."
        } else {
            // Keep only what didn't come back, so nothing is lost.
            var remaining = spot
            remaining.windows = failures
            store.update(remaining)
        }
        refresh()
    }

    func delete(_ spot: Spot) {
        guard let index = store.spots.firstIndex(of: spot) else { return }
        store.remove(spot.id)
        showToast("Deleted “\(spot.name)”") { [weak self] in
            self?.store.restore(spot, at: index)
        }
    }

    func showToast(_ message: String, undoTitle: String = "Undo", duration: Duration = .seconds(5), undo: (() -> Void)? = nil) {
        toastTask?.cancel()
        toast = Toast(message: message, undoTitle: undoTitle, undo: undo)
        toastTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.toast = nil
        }
    }
}
