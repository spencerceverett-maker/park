import AppKit
import ApplicationServices
import Observation
import SwiftUI

/// First launch, taught with the real thing: Park's actual panel opens from the menu bar, two practice
/// windows open on this desktop, and small callouts beside the panel walk through parking and restoring
/// them. Each step waits for something real to happen (permission granted, windows parked, restored,
/// ⌃⌥P pressed). The tour only ever touches its own practice windows.
@MainActor
final class GuidedTour {
    static let didCompleteKey = "didCompleteTour"
    static let didPlayIntroKey = "didPlayIntroLight"

    enum Step: String {
        case idle, moveCard, intro, notch, access, preparing, meet, park, parked, restore, success, hotkey, hotkeyDone
    }

    private let model: AppModel
    private let panel: PanelController
    private let practice = PracticeWindows()
    private let callout = CalloutWindow()
    private var moveCard: MoveCardWindow?
    private var effect: AnyObject?

    private(set) var step: Step = .idle
    var isRunning: Bool { step != .idle }

    private var ticker: Timer?
    private var stepTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var keyMonitors: [Any] = []
    private var paused = false
    private var shots = 0

    init(model: AppModel, panel: PanelController) {
        self.model = model
        self.panel = panel
        callout.onSkip = { [weak self] in self?.finish() }
    }

    // MARK: - Start

    /// Starts the tour. On a true first launch the intro effect plays first, from Park's icon.
    func start(playIntro: Bool) {
        guard !isRunning else { return }
        installObservers()
        if !Installer.isInApplicationsFolder && !DevMode.isOn {
            go(.moveCard)
            let card = MoveCardWindow()
            card.onNotNow = { [weak self] in self?.moveCard = nil; self?.beginWithIntro(playIntro) }
            card.show()
            moveCard = card
        } else {
            beginWithIntro(playIntro)
        }
    }

    private func beginWithIntro(_ playIntro: Bool) {
        guard playIntro, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { openPanel(); return }
        Defaults.set(true, forKey: Self.didPlayIntroKey)
        go(.intro)
        effect = IntroEffect.firstLaunch.playFirstLaunch(from: panel.statusAnchor,
                                                        handoff: { [weak self] in self?.openPanel() },
                                                        done: { [weak self] in self?.effect = nil })
        capture("intro", after: 1.0)
        capture("intro-landing", after: 2.1)
    }

    /// The real panel drops from Park's icon (or from beside the notch when the icon is hidden).
    private func openPanel() {
        panel.isPinned = true
        panel.open()
        after(0.45) { [weak self] in
            guard let self else { return }
            if !self.panel.isStatusItemVisible { self.showNotchNote() } else { self.afterNotch() }
        }
    }

    // MARK: - Steps

    private func showNotchNote() {
        go(.notch)
        show(anchor: .panelTop,
             CalloutContent(title: "Your menu bar is full, so Park’s icon is hidden behind the notch.",
                            body: "⌃⌥P always opens Park, from any app.",
                            action: "Got it"),
             action: { [weak self] in self?.afterNotch() })
        autoplay(after: 2.6) { [weak self] in self?.afterNotch() }
    }

    private func afterNotch() {
        guard step == .notch || step == .intro || step == .moveCard || step == .idle else { return }
        if AXIsProcessTrusted() { prepare() } else { askForAccess() }
    }

    private func askForAccess() {
        go(.access)
        model.tourFocus = .permission
        show(anchor: .element(.permissionButton),
             CalloutContent(title: "Park needs permission to see your windows.",
                            body: "Open System Settings and turn on Park under Accessibility. The tour carries on by itself.",
                            action: "Open System Settings", secondary: "Not now"),
             action: { [weak self] in self?.openSettingsForAccess() },
             secondary: { [weak self] in self?.finish(note: "Whenever you’re ready, ⌃⌥P opens Park.") })
    }

    private func openSettingsForAccess() {
        model.requestAccessibility()
        // The switch can already be on and still not count: macOS remembers an older copy of Park (a
        // different build, or one since replaced) under the same name. Say how out of that, rather than wait.
        after(12) { [weak self] in
            guard let self, self.step == .access, !AXIsProcessTrusted() else { return }
            self.show(anchor: .element(.permissionButton),
                      CalloutContent(title: "Already turned on?",
                                     body: "macOS may be remembering an older copy of Park. Select Park in the list and click –, then click below to add it again.",
                                     action: "Open System Settings", secondary: "Not now"),
                      action: { [weak self] in self?.model.requestAccessibility() },
                      secondary: { [weak self] in self?.finish(note: "Whenever you’re ready, ⌃⌥P opens Park.") })
        }
    }

    private func accessGranted() {
        model.tourFocus = nil
        model.refresh()
        show(anchor: .panelTop, CalloutContent(title: "Thanks. Park can see your windows now.", checked: true))
        after(1.1) { [weak self] in self?.prepare() }
    }

    private func prepare() {
        go(.preparing)
        show(anchor: .panelTop, CalloutContent(title: "Opening two practice windows…", body: "Your own windows stay right where they are."))
        practice.open { [weak self] ids in
            guard let self, self.step == .preparing else { return }
            guard let ids, !ids.isEmpty else {
                self.finish(note: "The practice windows didn’t open. Park is ready whenever you are: ⌃⌥P.")
                return
            }
            self.model.tourScope = ids
            self.model.refresh()
            self.after(0.6) { [weak self] in self?.meet() }
        }
    }

    private func meet() {
        go(.meet)
        model.tourFocus = .header
        show(anchor: .element(.header),
             CalloutContent(title: "These are the windows on this desktop.",
                            body: "For the tour, Park only sees the two practice windows it just opened."))
        capture("meet", after: 0.9)
        after(3.4) { [weak self] in
            guard self?.step == .meet else { return }
            self?.askToPark()
        }
    }

    private func askToPark() {
        go(.park)
        model.tourFocus = .parkButton
        show(anchor: .element(.parkButton),
             CalloutContent(title: "Press Park this desktop.",
                            body: "Or press ↩. The practice windows close, and Park remembers them."))
        capture("park", after: 0.9)
        autoplay(after: 2.8) { [weak self] in Task { await self?.model.park() } }
    }

    private func parked(_ spot: Spot) {
        go(.parked)
        model.tourSpotID = spot.id
        model.tourFocus = .row
        show(anchor: .element(.row(spot.id)),
             CalloutContent(title: "Parked.",
                            body: "Both windows are closed. They live in this list now, ready to come back."))
        capture("parked", after: 1.0)
        after(3.0) { [weak self] in
            guard self?.step == .parked else { return }
            self?.askToRestore(spot)
        }
    }

    private func askToRestore(_ spot: Spot) {
        go(.restore)
        model.tourFocus = .restore
        show(anchor: .element(.restore(spot.id)),
             CalloutContent(title: "Restore brings it all back.",
                            body: "Press Restore. The windows reopen right where they were."))
        capture("restore", after: 0.9)
        autoplay(after: 2.8) { [weak self] in
            guard let self, let spot = self.model.store.spots.first(where: { $0.id == self.model.tourSpotID }) else { return }
            Task { await self.model.restore(spot) }
        }
    }

    private func restored() {
        go(.success)
        model.tourFocus = nil
        model.tourSpotID = nil
        practice.refresh()
        show(anchor: .element(.header),
             CalloutContent(title: "That’s Park.",
                            body: "Park any desktop the same way whenever you want the memory back.", checked: true))
        capture("success", after: 1.0)
        after(2.8) { [weak self] in
            guard self?.step == .success else { return }
            self?.askForHotkey()
        }
    }

    private func askForHotkey() {
        go(.hotkey)
        panel.isPinned = false
        panel.close()
        let hidden = !panel.isStatusItemVisible
        after(0.2) { [weak self] in
            guard let self, self.step == .hotkey else { return }
            self.show(anchor: .statusItem,
                      CalloutContent(title: "Press ⌃⌥P to open Park.",
                                     body: hidden ? "From any app, anytime. It works even when the notch hides Park’s icon."
                                                  : "From any app, anytime. Or click Park’s icon up here.",
                                     secondary: "Done"),
                      secondary: { [weak self] in self?.finish() })
            self.capture("hotkey", after: 0.9)
            self.autoplay(after: 2.6) { [weak self] in
                self?.panel.toggle()
                NotificationCenter.default.post(name: .parkPanelHotKey, object: nil)
            }
        }
    }

    private func hotkeyPressed() {
        guard step == .hotkey else { return }
        go(.hotkeyDone)
        after(0.3) { [weak self] in
            self?.show(anchor: .panelTop, CalloutContent(title: "There it is.", body: "Park lives in your menu bar from now on.", checked: true))
            self?.capture("hotkey-done", after: 0.8)
        }
        after(2.4) { [weak self] in self?.finish() }
    }

    // MARK: - Watching for real events

    private func installObservers() {
        ticker = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        observers.append(NotificationCenter.default.addObserver(forName: .parkPanelHotKey, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.hotkeyPressed() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.spaceChanged() }
        })
        // Escape skips the tour from anywhere.
        let esc: (NSEvent) -> Bool = { [weak self] event in
            guard event.keyCode == 53, let self, self.isRunning, self.step != .intro else { return false }
            self.finish()
            return true
        }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { esc($0) ? nil : $0 }) { keyMonitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { _ = esc($0) }) { keyMonitors.append(m) }
    }

    private func tick() {
        guard !paused else { return }
        switch step {
        case .access:
            if AXIsProcessTrusted() { accessGranted() }
        case .park:
            if let spot = model.store.spots.first(where: { practice.owns($0) }) { parked(spot) }
            else if !model.isParking, !practice.anyOpen() {
                // The practice windows were closed by hand: open them again.
                go(.preparing)
                prepare()
            }
        case .restore, .parked:
            if let id = model.tourSpotID, !model.store.spots.contains(where: { $0.id == id }), model.restoringID == nil {
                restored()
            }
        default:
            break
        }
        callout.follow(rect(for: currentAnchor))
    }

    /// Switching desktops mid-tour pauses it; coming back picks up where it left off.
    private func spaceChanged() {
        guard isRunning, [.meet, .park, .parked, .restore, .success].contains(step) else { return }
        let here = practice.isOnCurrentDesktop()
        if !here && !paused {
            paused = true
            callout.hide()
            panel.isPinned = false
            panel.close()
        } else if here && paused {
            paused = false
            panel.isPinned = true
            panel.open()
            after(0.3) { [weak self] in self?.callout.reveal() }
        }
    }

    // MARK: - Finish

    /// Ends the tour (finished or skipped): practice windows and their parked row go away.
    func finish(note: String? = nil) {
        guard isRunning else { return }
        stepTask?.cancel()
        ticker?.invalidate(); ticker = nil
        observers.forEach { NotificationCenter.default.removeObserver($0); NSWorkspace.shared.notificationCenter.removeObserver($0) }
        observers.removeAll()
        keyMonitors.forEach(NSEvent.removeMonitor); keyMonitors.removeAll()
        moveCard?.close(); moveCard = nil

        for spot in model.store.spots where practice.owns(spot) { model.store.remove(spot.id) }
        model.toast = nil   // its "Put back" would bring the practice row back
        model.tourScope = nil
        model.tourFocus = nil
        model.tourSpotID = nil
        model.refresh()
        practice.cleanUp()

        Defaults.set(true, forKey: Self.didCompleteKey)
        Defaults.set(true, forKey: OnboardingController.didFinishKey)
        step = .idle
        paused = false

        if let note {
            panel.isPinned = false
            show(anchor: .panelTop, CalloutContent(title: note, checked: false), skippable: false)
            after(3.2) { [weak self] in self?.callout.hide() }
        } else {
            callout.hide()
            panel.isPinned = false
        }
        if DevMode.autoplay { after(1.5) { NSApp.terminate(nil) } }
    }

    // MARK: - Callout placement

    enum Anchor: Equatable { case element(TourAnchor), panelTop, statusItem }
    private var currentAnchor: Anchor = .panelTop

    private func rect(for anchor: Anchor) -> CalloutTarget? {
        switch anchor {
        case .element(let element):
            guard let rect = panel.screenRect(for: element) else { return nil }
            return CalloutTarget(rect: rect, panel: panel.frame)
        case .panelTop:
            guard panel.isOpen else { return CalloutTarget(rect: panel.statusAnchor, panel: nil) }
            let frame = panel.frame
            return CalloutTarget(rect: NSRect(x: frame.minX, y: frame.maxY - 44, width: frame.width, height: 44), panel: frame)
        case .statusItem:
            return CalloutTarget(rect: panel.statusAnchor, panel: nil)
        }
    }

    private func show(anchor: Anchor, _ content: CalloutContent, skippable: Bool = true,
                      action: (() -> Void)? = nil, secondary: (() -> Void)? = nil) {
        currentAnchor = anchor
        var content = content
        content.skippable = skippable && content.secondary == nil
        callout.present(content, at: rect(for: anchor), action: action, secondary: secondary)
    }

    // MARK: - Helpers

    private func go(_ next: Step) {
        step = next
        Log.write("tour: \(next.rawValue)")
    }

    private func after(_ seconds: Double, _ work: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { MainActor.assumeIsolated { work() } }
    }

    /// Dev only: presses the button for the user, so the tour can be recorded end to end.
    private func autoplay(after seconds: Double, _ work: @escaping @MainActor () -> Void) {
        guard DevMode.autoplay else { return }
        let expected = step
        after(seconds) { [weak self] in
            guard self?.step == expected else { return }
            work()
        }
    }

    /// Dev only: saves each of the tour's windows (and the practice windows) as images, with a manifest
    /// of where they sit, so the step can be recomposed onto a clean desktop for review.
    private func capture(_ name: String, after seconds: Double) {
        guard let directory = DevMode.shotsDirectory else { return }
        after(seconds) { [weak self] in
            guard let self else { return }
            self.shots += 1
            let prefix = String(format: "%02d-%@", self.shots, name)
            TourShots.capture(prefix: prefix, into: directory, extraWindows: self.practice.windowIDs())
        }
    }
}

// MARK: - Practice windows

/// Two harmless real windows the tour parks and restores: a note in TextEdit and a postcard in Preview.
/// Both open documents through NSWorkspace, so no Automation permission is needed.
@MainActor
final class PracticeWindows {
    private let folder: URL = SpotStore.defaultURL.deletingLastPathComponent().appendingPathComponent("Tour", isDirectory: true)
    private var note: URL { folder.appendingPathComponent("Welcome to Park.rtf") }
    private var postcard: URL { folder.appendingPathComponent("Park postcard.png") }
    private var files: [URL] { [note, postcard] }
    private let apps = ["com.apple.TextEdit", "com.apple.Preview"]
    private var launchedByTour: Set<String> = []

    /// Creates the files, opens them, places the windows, and returns their window IDs (nil on failure).
    func open(completion: @escaping (Set<CGWindowID>?) -> Void) {
        do { try writeFiles() } catch { completion(nil); return }
        for id in apps where NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty {
            launchedByTour.insert(id)
        }
        for (file, app) in zip(files, apps) {
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) else { continue }
            NSWorkspace.shared.open([file], withApplicationAt: appURL, configuration: .background, completionHandler: nil)
        }
        // Wait for both windows, then place them side by side, clear of the panel.
        var tries = 0
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] timer in
            MainActor.assumeIsolated {
                guard let self else { timer.invalidate(); return }
                tries += 1
                let found = self.windows()
                if found.count >= self.files.count || tries > 40 {
                    timer.invalidate()
                    guard !found.isEmpty else { completion(nil); return }
                    self.place(found)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        completion(Set(self.windows().map(\.id)))
                    }
                }
            }
        }
    }

    func refresh() {}

    func windowIDs() -> Set<CGWindowID> { Set(windows().map(\.id)) }
    func anyOpen() -> Bool { !windows().isEmpty }
    func isOnCurrentDesktop() -> Bool { !windowIDs().isDisjoint(with: Set(CurrentSpace.windows().map(\.windowID))) }

    /// A parked spot made only of the tour's documents.
    func owns(_ spot: Spot) -> Bool {
        let paths = Set(files.map(\.path))
        return !spot.windows.isEmpty && spot.windows.allSatisfy {
            if case .document(let path) = $0.content { return paths.contains(path) }
            return false
        }
    }

    /// Practice windows currently open, found by the document they show.
    private func windows() -> [(element: AXUIElement, id: CGWindowID, pid: pid_t, file: URL)] {
        var result: [(AXUIElement, CGWindowID, pid_t, URL)] = []
        for app in apps {
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: app) {
                for (element, id) in AX.windows(pid: running.processIdentifier) {
                    guard let doc: String = AX.attr(element, kAXDocumentAttribute),
                          let path = URL(string: doc)?.path,
                          let file = files.first(where: { $0.path == path }) else { continue }
                    result.append((element, id, running.processIdentifier, file))
                }
            }
        }
        return result
    }

    private func place(_ found: [(element: AXUIElement, id: CGWindowID, pid: pid_t, file: URL)]) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let top = screen.frame.maxY - visible.maxY   // menu bar height, in top-left coordinates
        let w = visible.width, h = visible.height
        for window in found {
            let frame = window.file == note
                ? CGRect(x: visible.minX + w * 0.07, y: top + h * 0.30, width: 470, height: 360)
                : CGRect(x: visible.minX + w * 0.22, y: top + h * 0.47, width: 520, height: 370)
            AX.setFrame(window.element, frame)
            AXUIElementPerformAction(window.element, kAXRaiseAction as CFString)
        }
        // Bring them forward now that they're on this desktop (activating earlier could switch desktops).
        for pid in Set(found.map(\.pid)) { NSRunningApplication(processIdentifier: pid)?.activate() }
    }

    /// Closes the practice windows, quits the apps the tour launched (if nothing else is open in them),
    /// and removes the practice files.
    func cleanUp() {
        for window in windows() {
            if let close = AX.element(window.element, kAXCloseButtonAttribute) {
                AXUIElementPerformAction(close, kAXPressAction as CFString)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [self] in
            for id in launchedByTour {
                for app in NSRunningApplication.runningApplications(withBundleIdentifier: id)
                where AX.windows(pid: app.processIdentifier).isEmpty {
                    app.terminate()
                }
            }
            if windows().isEmpty { try? FileManager.default.removeItem(at: folder) }
        }
    }

    private func writeFiles() throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let text = NSMutableAttributedString()
        let title = NSFont.systemFont(ofSize: 26, weight: .semibold)
        let body = NSFont.systemFont(ofSize: 15)
        let gray = NSColor(srgbRed: 0.43, green: 0.43, blue: 0.45, alpha: 1)
        let para = NSMutableParagraphStyle(); para.paragraphSpacing = 10; para.lineSpacing = 3
        text.append(NSAttributedString(string: "Welcome to Park\n", attributes: [.font: title, .paragraphStyle: para]))
        text.append(NSAttributedString(string: "This is a practice window. In a moment, Park will put it away and then bring it right back, exactly where it is now.\n\nNothing here is saved anywhere else. The tour tidies it up when you’re done.",
                                       attributes: [.font: body, .foregroundColor: gray, .paragraphStyle: para]))
        let rtf = try text.data(from: NSRange(location: 0, length: text.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        try rtf.write(to: note)
        try Self.postcardPNG().write(to: postcard)
    }

    /// A small postcard in the website's dawn blues with Park's logo.
    private static func postcardPNG() -> Data {
        let size = NSSize(width: 1200, height: 800)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let hexes: [Int] = [0x0B1B36, 0x163E86, 0x1E50A8, 0x9CC0EA, 0xCFE0F5]
        let colors: [NSColor] = hexes.map { (hex: Int) -> NSColor in
            let r = CGFloat((hex >> 16) & 0xFF) / 255
            let g = CGFloat((hex >> 8) & 0xFF) / 255
            let b = CGFloat(hex & 0xFF) / 255
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        }
        NSGradient(colors: colors, atLocations: [0, 0.35, 0.55, 0.85, 1], colorSpace: .sRGB)?.draw(in: NSRect(origin: .zero, size: size), angle: -90)
        if let logo = Bundle.main.image(forResource: "Logo") {
            logo.draw(in: NSRect(x: size.width / 2 - 110, y: size.height / 2 - 40, width: 220, height: 220))
        }
        let caption = NSAttributedString(string: "Put a desktop away. Pick it up later.", attributes: [
            .font: NSFont.systemFont(ofSize: 40, weight: .semibold), .foregroundColor: NSColor.white])
        let w = caption.size().width
        caption.draw(at: NSPoint(x: (size.width - w) / 2, y: size.height / 2 - 140))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:]) ?? Data()
    }
}

// MARK: - Callout

struct CalloutContent: Equatable {
    var title: String
    var body: String? = nil
    var action: String? = nil
    var secondary: String? = nil
    var checked = false
    var skippable = true
}

/// Where a callout points: an element's frame, plus the panel it belongs to (if open), in screen coordinates.
struct CalloutTarget: Equatable {
    var rect: NSRect
    var panel: NSRect?
}

@MainActor
@Observable
final class CalloutModel {
    var content = CalloutContent(title: "")
    var edge: Edge = .trailing
    /// Tail position along its edge, in points from the leading/top end of the callout.
    var tail: CGFloat = 40
    @ObservationIgnored var onAction: () -> Void = {}
    @ObservationIgnored var onSecondary: () -> Void = {}
    @ObservationIgnored var onSkip: () -> Void = {}
}

final class CalloutPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// A small frosted note with a tail, floating beside the panel element it explains.
@MainActor
final class CalloutWindow {
    static let width: CGFloat = 268
    static let tailSize: CGFloat = 8
    static let gap: CGFloat = 10

    private let window: CalloutPanel
    private let model = CalloutModel()
    private let hosting: NSHostingView<CalloutView>
    private var target: CalloutTarget?
    private var visible = false
    var onSkip: () -> Void = {} { didSet { model.onSkip = onSkip } }

    init() {
        window = CalloutPanel(contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 100),
                              styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        window.isFloatingPanel = true
        window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.hidesOnDeactivate = false
        window.animationBehavior = .none
        window.collectionBehavior = [.fullScreenAuxiliary, .transient]
        hosting = NSHostingView(rootView: CalloutView(model: model))
        hosting.sizingOptions = []
        hosting.safeAreaRegions = []
        window.contentView = hosting
    }

    func present(_ content: CalloutContent, at target: CalloutTarget?, action: (() -> Void)?, secondary: (() -> Void)?) {
        model.onAction = action ?? {}
        model.onSecondary = secondary ?? {}
        model.content = content
        self.target = target
        guard let target else { hide(); return }
        let frame = layout(for: target)
        if !visible {
            // Arrive from the direction of what it points at, settling without overshoot.
            let offset: CGFloat = model.edge == .top ? 6 : (model.edge == .trailing ? 8 : -8)
            var start = frame
            if model.edge == .top { start.origin.y -= offset } else { start.origin.x += offset }
            window.setFrame(start, display: true)
            window.alphaValue = 0
            window.orderFrontRegardless()
            visible = true
            animate(to: frame, alpha: 1)
        } else {
            animate(to: frame, alpha: 1)
        }
        NSAccessibility.post(element: window, notification: .layoutChanged)
    }

    /// Keeps pointing at the element as the panel resizes or moves.
    func follow(_ target: CalloutTarget?) {
        guard visible, let target, target != self.target else { return }
        self.target = target
        let frame = layout(for: target)
        if abs(frame.minY - window.frame.minY) > 40 || abs(frame.minX - window.frame.minX) > 40 {
            animate(to: frame, alpha: 1)
        } else {
            window.setFrame(frame, display: true)
        }
    }

    func reveal() {
        guard let target else { return }
        visible = false
        present(model.content, at: target, action: model.onAction, secondary: model.onSecondary)
    }

    func hide() {
        guard visible else { return }
        visible = false
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.visible else { return }
                self.window.orderOut(nil)
            }
        })
    }

    private func animate(to frame: NSRect, alpha: CGFloat) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.32
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            window.animator().setFrame(frame, display: true)
            window.animator().alphaValue = alpha
        }
    }

    /// Beside the panel (left of it when there's room), tail at the element's centre; below the menu
    /// bar icon when there's no panel.
    private func layout(for target: CalloutTarget) -> NSRect {
        let screen = NSScreen.screens.first(where: { $0.frame.intersects(target.rect) }) ?? NSScreen.main ?? NSScreen.screens[0]
        let visibleFrame = screen.visibleFrame
        let edge: Edge
        if let panel = target.panel {
            edge = panel.minX - Self.width - Self.gap - Self.tailSize > visibleFrame.minX + 8 ? .trailing : .leading
        } else {
            edge = .top
        }
        model.edge = edge
        // Measure the new content before placing the window, so nothing is clipped.
        hosting.layoutSubtreeIfNeeded()
        let fitting = NSHostingController(rootView: CalloutView(model: model)).sizeThatFits(in: NSSize(width: Self.width + Self.tailSize, height: 2000))
        let height = max(fitting.height - (edge == .top ? Self.tailSize : 0), 56)
        let width = Self.width + (edge == .top ? 0 : Self.tailSize)
        var frame = NSRect(x: 0, y: 0, width: width, height: height + (edge == .top ? Self.tailSize : 0))
        switch edge {
        case .trailing, .leading:
            let panel = target.panel ?? target.rect
            frame.origin.x = edge == .trailing ? panel.minX - Self.gap - width : panel.maxX + Self.gap
            frame.origin.y = target.rect.midY - height / 2
            frame.origin.y = min(max(frame.origin.y, visibleFrame.minY + 8), visibleFrame.maxY - height - 8)
            model.tail = min(max(frame.maxY - target.rect.midY, 18), height - 18)
        default:
            frame.origin.x = min(max(target.rect.midX - width / 2, visibleFrame.minX + 8), visibleFrame.maxX - width - 8)
            frame.origin.y = target.rect.minY - 6 - frame.height
            model.tail = min(max(target.rect.midX - frame.minX, 18), width - 18)
        }
        return frame
    }
}

private struct CalloutShape: Shape, Equatable {
    var edge: Edge
    var tail: CGFloat
    let radius: CGFloat = 12
    let size = CalloutWindow.tailSize

    func path(in rect: CGRect) -> Path {
        var body = rect
        switch edge {
        case .trailing: body.size.width -= size
        case .leading: body.origin.x += size; body.size.width -= size
        case .top: body.origin.y += size; body.size.height -= size
        case .bottom: body.size.height -= size
        }
        var path = Path(roundedRect: body, cornerRadius: radius, style: .continuous)
        var t = Path()
        switch edge {
        case .trailing:
            t.move(to: CGPoint(x: body.maxX - 1, y: tail - size)); t.addLine(to: CGPoint(x: rect.maxX, y: tail)); t.addLine(to: CGPoint(x: body.maxX - 1, y: tail + size))
        case .leading:
            t.move(to: CGPoint(x: body.minX + 1, y: tail - size)); t.addLine(to: CGPoint(x: rect.minX, y: tail)); t.addLine(to: CGPoint(x: body.minX + 1, y: tail + size))
        case .top:
            t.move(to: CGPoint(x: tail - size, y: body.minY + 1)); t.addLine(to: CGPoint(x: tail, y: rect.minY)); t.addLine(to: CGPoint(x: tail + size, y: body.minY + 1))
        case .bottom:
            break
        }
        t.closeSubpath()
        path.addPath(t)
        return path
    }
}

/// Frosted material cut to the callout's shape (a SwiftUI clip doesn't reach an NSVisualEffectView).
private struct CalloutBackground: NSViewRepresentable {
    var edge: Edge
    var tail: CGFloat

    final class View: NSVisualEffectView {
        var shape = CalloutShape(edge: .trailing, tail: 40) { didSet { if shape != oldValue { updateMask() } } }
        override func layout() { super.layout(); updateMask() }
        func updateMask() {
            let shape = self.shape
            maskImage = NSImage(size: bounds.size, flipped: true) { rect in
                NSColor.black.setFill()
                NSBezierPath(cgPath: shape.path(in: rect).cgPath).fill()
                return true
            }
        }
    }

    func makeNSView(context: Context) -> View {
        let view = View()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: View, context: Context) {
        view.shape = CalloutShape(edge: edge, tail: tail)
    }
}

struct CalloutView: View {
    @Bindable var model: CalloutModel

    private var insets: EdgeInsets {
        let s = CalloutWindow.tailSize
        switch model.edge {
        case .trailing: return EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: s)
        case .leading: return EdgeInsets(top: 0, leading: s, bottom: 0, trailing: 0)
        case .top: return EdgeInsets(top: s, leading: 0, bottom: 0, trailing: 0)
        case .bottom: return EdgeInsets()
        }
    }

    var body: some View {
        let content = model.content
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                if content.checked {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.brand)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(content.title)
                        .font(.system(size: 13, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    if let body = content.body {
                        Text(body)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineSpacing(1.5)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            if content.action != nil || content.secondary != nil || content.skippable {
                HStack(spacing: 6) {
                    if let action = content.action {
                        Button(action) { model.onAction() }
                            .buttonStyle(PrimaryButtonStyle(fill: Theme.brand))
                            .frame(maxWidth: 190)
                            .keyboardShortcut(.defaultAction)
                    }
                    Spacer(minLength: 0)
                    if let secondary = content.secondary {
                        Button(secondary) { model.onSecondary() }.buttonStyle(QuietButtonStyle())
                    } else if content.skippable {
                        Button("Skip tour") { model.onSkip() }.buttonStyle(QuietButtonStyle())
                    }
                }
            }
        }
        .id(content.title)
        .transition(.opacity)
        .padding(14)
        .padding(insets)
        .frame(width: CalloutWindow.width + (model.edge == .top ? 0 : CalloutWindow.tailSize), alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(CalloutBackground(edge: model.edge, tail: model.tail))
        .overlay(CalloutShape(edge: model.edge, tail: model.tail).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(content.title)
    }
}

// MARK: - Move to Applications

/// Shown before anything else when Park runs from the disk image or Downloads.
@MainActor
final class MoveCardWindow {
    private var window: NSPanel?
    var onNotNow: () -> Void = {}

    func show() {
        let panel = CalloutPanel(contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
                                 styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        let view = MoveCard(onMove: { [weak self] error in self?.move(error) }, onNotNow: { [weak self] in
            self?.close(); self?.onNotNow()
        })
        let hosting = NSHostingView(rootView: view)
        hosting.safeAreaRegions = []
        panel.contentView = hosting
        panel.setContentSize(hosting.fittingSize)
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        window = panel
    }

    private func move(_ message: Binding<String?>) {
        do { try Installer.moveToApplicationsAndRelaunch() }
        catch { message.wrappedValue = error.localizedDescription }
    }

    func close() { window?.orderOut(nil); window = nil }
}

private struct MoveCard: View {
    var onMove: (Binding<String?>) -> Void
    var onNotNow: () -> Void
    @State private var error: String?

    var body: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
            VStack(spacing: 4) {
                Text("Move Park to Applications?")
                    .font(.system(size: 15, weight: .semibold))
                Text("Park works best from your Applications folder, so it can open at login and keep its permissions.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let error {
                Text(error).font(.system(size: 11.5)).foregroundStyle(.red).multilineTextAlignment(.center)
            }
            VStack(spacing: 6) {
                Button("Move to Applications") { onMove($error) }
                    .buttonStyle(PrimaryButtonStyle(fill: Theme.brand))
                    .keyboardShortcut(.defaultAction)
                Button("Not now", action: onNotNow).buttonStyle(QuietButtonStyle())
            }
        }
        .padding(22)
        .frame(width: 340)
        .background(VisualEffect(material: .popover))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

// MARK: - Dev captures

/// Dev only: captures Park's own windows plus the given ones, each without its shadow, with a manifest
/// of their screen frames (top-left coordinates, front to back), for recomposing onto a clean desktop.
enum TourShots {
    static func capture(prefix: String, into directory: URL, extraWindows: Set<CGWindowID>) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let me = ProcessInfo.processInfo.processIdentifier
        let info = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        var manifest: [[String: Any]] = []
        for (index, window) in info.enumerated() {
            guard let id = (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value,
                  let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  pid == me || extraWindows.contains(id),
                  ((window[kCGWindowAlpha as String] as? Double) ?? 1) > 0.01,
                  let bounds = window[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds), frame.width > 20 else { continue }
            let file = directory.appendingPathComponent("\(prefix)-\(id).png")
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-x", "-o", "-l", "\(id)", file.path]
            try? task.run()
            task.waitUntilExit()
            manifest.append(["file": file.lastPathComponent, "x": frame.minX, "y": frame.minY, "w": frame.width, "h": frame.height,
                             "z": index, "own": pid == me])
        }
        if let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted]) {
            try? data.write(to: directory.appendingPathComponent("\(prefix).json"))
        }
    }
}
