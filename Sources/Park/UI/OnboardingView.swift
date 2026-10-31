import AppKit
import ApplicationServices
import SwiftUI

/// The first-launch walkthrough. It teaches by doing: park and restore a practice desktop in Park's
/// own panel, let Park see real windows, then open the real thing with ⌃⌥P. Under a minute.
struct OnboardingView: View {
    enum Step: Int, CaseIterable { case move, practice, access, tryIt }

    @State private var step: Step
    let includesMove: Bool
    var onFinish: () -> Void
    /// Opens Park's panel under its menu bar icon without ending the walkthrough.
    var onShowPanel: () -> Void

    @State private var hasAccess: Bool
    @State private var moveError: String?
    @State private var practice: PracticeDesk.Phase
    @State private var opened: Bool
    @State private var held: NSEvent.ModifierFlags = []
    /// After the first-launch light, the window arrives from it instead of simply appearing.
    @State private var arrived: Bool

    /// `granted`, `practice` and `opened` override live state (for snapshots).
    init(step: Step, includesMove: Bool, granted: Bool? = nil, practice: PracticeDesk.Phase = .ready, opened: Bool = false,
         materialize: Bool = false, onShowPanel: @escaping () -> Void = {}, onFinish: @escaping () -> Void = {}) {
        _arrived = State(initialValue: !materialize)
        _step = State(initialValue: step)
        _hasAccess = State(initialValue: granted ?? AXIsProcessTrusted())
        _practice = State(initialValue: practice)
        _opened = State(initialValue: opened)
        self.includesMove = includesMove
        self.onShowPanel = onShowPanel
        self.onFinish = onFinish
    }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 620, height: 560)
    static func initialStep(includesMove: Bool) -> Step { includesMove ? .move : .practice }

    private var steps: [Step] { Step.allCases.filter { $0 != .move || includesMove } }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                content(for: step)
                    .id(step)
                    .transition(reduceMotion
                                ? .opacity
                                : .asymmetric(insertion: .opacity.combined(with: .offset(x: 18)),
                                              removal: .opacity.combined(with: .offset(x: -18))))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            footer
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .scaleEffect(arrived ? 1 : 0.96)
        .opacity(arrived ? 1 : 0)
        .onAppear {
            guard !arrived else { return }
            withAnimation(.spring(response: 0.55, dampingFraction: 1)) { arrived = true }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : Theme.spring, value: step)
        .task(id: step) { await watchAccessIfNeeded() }
        .onReceive(NotificationCenter.default.publisher(for: .parkPanelHotKey)) { _ in
            guard step == .tryIt else { return }
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
            withAnimation(Theme.spring) { opened = true }
        }
    }

    // MARK: Steps

    @ViewBuilder
    private func content(for step: Step) -> some View {
        switch step {
        case .move:
            StepLayout(title: "First, give Park a parking spot",
                       message: moveError ?? "Park works best from your Applications folder, where it can open at login and keep its permissions.") {
                MoveArt()
            }
        case .practice:
            VStack(spacing: 18) {
                Header(title: practiceTitle, message: practiceMessage, done: practice == .restored)
                PracticeDesk(phase: $practice)
            }
            .padding(.top, 26)
        case .access:
            StepLayout(title: "Now let Park do that for real",
                       message: "To park your real windows, Park needs to see them. In System Settings, turn on Park under Accessibility. This page notices on its own.") {
                AccessArt(granted: hasAccess)
            } footnote: {
                Text("Park only uses this to find, close and reopen windows. Nothing leaves your Mac.")
            }
        case .tryIt:
            StepLayout(title: opened ? "There it is." : "Open Park from anywhere",
                       message: opened ? "That’s where Park lives, under its icon in your menu bar. It opens at login, so it’s always there."
                                       : "Press ⌃⌥P now. Park opens under its icon in your menu bar, from any app.") {
                ShortcutArt(held: held, opened: opened)
            } footnote: {
                Text("Can’t see the icon? A full menu bar can hide icons behind the camera notch. ⌃⌥P always works.")
            }
            .onAppear(perform: watchKeys)
            .onDisappear(perform: stopWatchingKeys)
        }
    }

    private var practiceTitle: String {
        switch practice {
        case .ready: return "Try it: park this desktop"
        case .parked: return "Parked. 2.3 GB back."
        case .restored: return "That’s Park."
        }
    }

    private var practiceMessage: String {
        switch practice {
        case .ready: return "These windows are just for practice. Press Park this desktop in the panel."
        case .parked: return "The windows are saved in your list. Now press Restore to bring them back."
        case .restored: return "Put a desktop away when you’re done with it. Pick it up, exactly as it was, when you’re back."
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack {
            if steps.count > 1 {
                HStack(spacing: 6) {
                    ForEach(steps, id: \.self) { s in
                        Capsule()
                            .fill(s == step ? Theme.brand : Color.primary.opacity(0.15))
                            .frame(width: s == step ? 16 : 6, height: 6)
                    }
                }
                .accessibilityHidden(true)
            }
            Spacer()
            secondaryButton
            primaryButton
        }
        .padding(.horizontal, 24)
        .frame(height: 64)
        .overlay(alignment: .top) { Rectangle().fill(Theme.hairline).frame(height: 1) }
    }

    @ViewBuilder
    private var secondaryButton: some View {
        switch step {
        case .move:
            Button("Not now") { advance() }
                .buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
        case .practice where practice != .restored:
            Button("Skip") { advance() }
                .buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
        case .access where !hasAccess:
            Button("Later") { advance() }
                .buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
        case .tryIt where !opened:
            Button("Show me") { onShowPanel(); withAnimation(Theme.spring) { opened = true } }
                .buttonStyle(QuietButtonStyle())
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        let button = Button(primaryTitle, action: primaryAction)
            .buttonStyle(PrimaryButtonStyle(fill: Theme.brand))
            .frame(width: primaryWidth)
        // In practice, Return belongs to the panel's buttons until the user has tried them.
        if step == .practice && practice != .restored {
            button.disabled(true)
        } else {
            button.keyboardShortcut(.defaultAction)
        }
    }

    private var primaryTitle: String {
        switch step {
        case .move: return "Move to Applications"
        case .practice: return "Continue"
        case .access: return hasAccess ? "Continue" : "Open System Settings"
        case .tryIt: return "Start using Park"
        }
    }

    private var primaryWidth: CGFloat {
        switch step {
        case .move, .access where !hasAccess: return 190
        case .tryIt: return 160
        default: return 120
        }
    }

    private func primaryAction() {
        switch step {
        case .move:
            do { try Installer.moveToApplicationsAndRelaunch() } catch { moveError = error.localizedDescription }
        case .access where !hasAccess:
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            if !AXIsProcessTrustedWithOptions(options) {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            }
        case .tryIt:
            onFinish()
        default:
            advance()
        }
    }

    private func advance() {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { onFinish(); return }
        var next = steps[index + 1]
        // Already granted: there's nothing to ask, so don't show the step.
        if next == .access && AXIsProcessTrusted(), index + 2 < steps.count { next = steps[index + 2] }
        step = next
    }

    /// There's no notification for an Accessibility grant, so poll while that step is showing,
    /// and move on by itself a beat after access arrives.
    private func watchAccessIfNeeded() async {
        guard step == .access, !Snapshot.isRendering else { return }
        while !Task.isCancelled && !hasAccess {
            try? await Task.sleep(for: .milliseconds(600))
            if AXIsProcessTrusted() { withAnimation(Theme.spring) { hasAccess = true } }
        }
        guard !Task.isCancelled, hasAccess else { return }
        try? await Task.sleep(for: .milliseconds(1100))
        if step == .access { advance() }
    }

    // MARK: Keys

    /// Mirrors the modifier keys on the key caps as they're held, so ⌃⌥P feels like a real key press.
    @State private var keyMonitor: Any?

    private func watchKeys() {
        guard keyMonitor == nil, !Snapshot.isRendering else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { event in
            held = event.modifierFlags.intersection([.control, .option])
            return event
        }
    }

    private func stopWatchingKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

extension Notification.Name {
    /// Posted when ⌃⌥P opens the panel, so the walkthrough can tell the user got it.
    static let parkPanelHotKey = Notification.Name("com.spencereverett.park.panelHotKey")
}

// MARK: - Pieces

private struct StepLayout<Art: View, Footnote: View>: View {
    let title: String
    let message: String
    let art: Art
    let footnote: Footnote

    init(title: String, message: String, @ViewBuilder art: () -> Art, @ViewBuilder footnote: () -> Footnote) {
        self.title = title; self.message = message; self.art = art(); self.footnote = footnote()
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            art.frame(height: 150)
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.4)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 22)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            footnote
                .font(.system(size: 11.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 44)
        .padding(.top, 8)
    }
}

extension StepLayout where Footnote == EmptyView {
    init(title: String, message: String, @ViewBuilder art: () -> Art) {
        self.init(title: title, message: message, art: art, footnote: { EmptyView() })
    }
}

/// Park's logo (the coin), bundled in the app as Logo.png.
struct BrandLogo: View {
    var size: CGFloat

    var body: some View {
        Group {
            if let image = Bundle.main.image(forResource: "Logo") {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "parkingsign.circle.fill").resizable().foregroundStyle(Theme.brand)
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color(red: 0.04, green: 0.11, blue: 0.27).opacity(0.28), radius: size * 0.12, y: size * 0.07)
        .accessibilityHidden(true)
    }
}

/// Title and message above the practice desk, with one quiet check when it's done.
private struct Header: View {
    var title: String
    var message: String
    var done: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(Theme.brand)
                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
                Text(title)
                    .font(.system(size: 22, weight: .semibold))
                    .tracking(-0.4)
                    .contentTransition(.opacity)
            }
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)
                .contentTransition(.opacity)
        }
        .animation(Theme.spring, value: title)
        .padding(.horizontal, 40)
    }
}

/// Park's icon heading for a parking bay drawn around the Applications folder, like the disk image.
private struct MoveArt: View {
    var body: some View {
        HStack(spacing: 18) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                .resizable().frame(width: 92, height: 92)
            HStack(spacing: 5) {
                ForEach(0..<5) { _ in Circle().fill(Theme.brand.opacity(0.55)).frame(width: 4, height: 4) }
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.brand.opacity(0.7))
            }
            Image(nsImage: NSWorkspace.shared.icon(forFile: "/Applications"))
                .resizable().frame(width: 84, height: 84)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.brand.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
        }
        .accessibilityHidden(true)
    }
}

/// The exact switch to flip, drawn like System Settings' Accessibility list. It turns on by itself
/// when access is granted, so the user sees the step complete.
private struct AccessArt: View {
    var granted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary)
                Text("Accessibility").font(.system(size: 13, weight: .bold))
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            Text("Allow the applications below to control your computer.")
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                .padding(.horizontal, 14).padding(.bottom, 8)
            VStack(spacing: 0) {
                row(icon: NSWorkspace.shared.icon(forFile: "/System/Applications/Utilities/Terminal.app"), name: "Terminal", on: true, dimmed: true)
                Divider().padding(.leading, 44)
                row(icon: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath), name: "Park", on: granted, dimmed: false)
            }
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.04)))
            .padding(.horizontal, 10).padding(.bottom, 10)
        }
        .frame(width: 320)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.background))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.hairline))
        .shadow(color: .black.opacity(0.1), radius: 14, y: 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(granted ? "Accessibility access is on" : "Waiting for Accessibility access")
    }

    private func row(icon: NSImage, name: String, on: Bool, dimmed: Bool) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: icon).resizable().frame(width: 24, height: 24)
            Text(name).font(.system(size: 12, weight: dimmed ? .regular : .semibold))
            Spacer()
            if !dimmed && !on {
                Text("Turn this on").font(.system(size: 10.5, weight: .medium)).foregroundStyle(Theme.brand)
                    .transition(.opacity)
            }
            Capsule()
                .fill(on ? (dimmed ? Color.primary.opacity(0.25) : Theme.brand) : Color.primary.opacity(0.12))
                .frame(width: 30, height: 17)
                .overlay(alignment: on ? .trailing : .leading) {
                    Circle().fill(.white).frame(width: 14, height: 14).padding(1.5)
                        .shadow(color: .black.opacity(0.15), radius: 1, y: 0.5)
                }
                .animation(Theme.spring, value: on)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .opacity(dimmed ? 0.55 : 1)
    }
}

/// ⌃ ⌥ P as real key caps that press down as they're held, over a slice of the menu bar.
private struct ShortcutArt: View {
    var held: NSEvent.ModifierFlags
    var opened: Bool

    var body: some View {
        VStack(spacing: 22) {
            HStack(spacing: 8) {
                KeyCap(symbol: "⌃", name: "control", down: held.contains(.control), done: opened)
                KeyCap(symbol: "⌥", name: "option", down: held.contains(.option), done: opened)
                KeyCap(symbol: "P", name: nil, down: false, done: opened)
            }
            HStack(spacing: 13) {
                Spacer()
                Image(nsImage: StatusIcon.image).renderingMode(.template)
                    .frame(width: 30, height: 22)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(opened ? Theme.brand.opacity(0.18) : Color.primary.opacity(0.1)))
                Image(systemName: "wifi").font(.system(size: 13, weight: .medium))
                Image(systemName: "battery.75percent").font(.system(size: 14))
                TimelineView(.everyMinute) { context in
                    Text(context.date.formatted(.dateTime.hour().minute())).font(.system(size: 13, weight: .medium)).monospacedDigit()
                }
            }
            .foregroundStyle(.primary.opacity(0.85))
            .padding(.horizontal, 14)
            .frame(width: 300, height: 30)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(.background.secondary))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Theme.hairline))
        }
        .accessibilityHidden(true)
    }
}

private struct KeyCap: View {
    var symbol: String
    var name: String?
    var down: Bool
    var done: Bool

    var body: some View {
        // Like a Mac keyboard: modifier symbol top-right, its name bottom-right; letters centered.
        Group {
            if let name {
                VStack(alignment: .trailing, spacing: 0) {
                    Text(symbol).font(.system(size: 15, weight: .medium))
                    Spacer(minLength: 0)
                    Text(name).font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(done ? Color.white.opacity(0.8) : Color.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                .padding(.horizontal, 8).padding(.vertical, 7)
            } else {
                Text(symbol).font(.system(size: 22, weight: .medium))
            }
        }
        .foregroundStyle(done ? .white : .primary)
        .frame(width: name == nil ? 58 : 70, height: 56)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(done ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(.background))
                .shadow(color: .black.opacity(down ? 0.08 : 0.18), radius: 0, y: down ? 1 : 3)
        )
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(done ? 0 : 0.12)))
        .offset(y: down ? 2 : 0)
        .animation(.easeOut(duration: 0.08), value: down)
        .animation(Theme.spring, value: done)
    }
}

// MARK: - Window

/// Hosts the walkthrough in a small, centered window.
@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    var onFinish: () -> Void = {}
    var onShowPanel: () -> Void = {}

    static let didFinishKey = "didFinishOnboarding"

    func show(materialize: Bool = false) {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let includesMove = !Installer.isInApplicationsFolder
        let view = OnboardingView(step: OnboardingView.initialStep(includesMove: includesMove), includesMove: includesMove,
                                  materialize: materialize,
                                  onShowPanel: { [weak self] in self?.onShowPanel() },
                                  onFinish: { [weak self] in self?.finish() })
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: OnboardingView.size),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        // Arriving out of the light: no system zoom, and a clear background while the content fades in.
        if materialize { window.animationBehavior = .none }
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.delegate = self
        window.center()
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func finish() {
        UserDefaults.standard.set(true, forKey: Self.didFinishKey)
        window?.close()
        onFinish()
    }

    func windowWillClose(_ notification: Notification) {
        // Closing early still counts as seen; the guide stays one click away in the ··· menu.
        UserDefaults.standard.set(true, forKey: Self.didFinishKey)
        window = nil
    }
}
