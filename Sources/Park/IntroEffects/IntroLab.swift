import AppKit
import Observation
import SwiftUI

/// A small floating window for choosing Park's first-launch moment by feel: each button plays an effect
/// live over the real screen. Run with `Park --intro-lab`; it runs alongside an installed Park.
@MainActor
@Observable
final class IntroLabModel {
    var speed: Double = 1 { didSet { player.speed = speed } }
    var anchor: IntroAnchor.Source = .parkIcon
    var foundParkIcon = false
    var playing: IntroEffect?

    // Fireflies tuning.
    var tuning = false
    var looping = false
    var params = FireflyParams() { didSet { player.fireflies = params } }
    var presetNames: [String] = []

    @ObservationIgnored let player = IntroEffectPlayer()
    @ObservationIgnored var setWindowVisible: (Bool) -> Void = { _ in }
    @ObservationIgnored var setTunerVisible: (Bool) -> Void = { _ in }
    @ObservationIgnored private var queue: [IntroEffect] = []

    func refreshAnchor() {
        foundParkIcon = IntroAnchor.runningParkIcon() != nil
    }

    func play(_ effect: IntroEffect) {
        queue = []
        start(effect)
    }

    func playAll() {
        queue = Array(IntroEffect.allCases.dropFirst())
        start(IntroEffect.allCases[0])
    }

    func setTuning(_ on: Bool) {
        tuning = on
        if !on { setLooping(false) }
        setTunerVisible(on)
    }

    /// Replays Fireflies continuously over the screen while the panels stay usable.
    func setLooping(_ on: Bool) {
        if on {
            queue = []
            looping = true
            playing = .fireflies
            player.play(.fireflies, origin: IntroAnchor.locate(prefer: anchor).point, speed: speed,
                        respectReduceMotion: false, skippable: false, loop: true)
        } else if looping {
            looping = false
            playing = nil
            player.stop()
        }
    }

    func playFirefliesOnce() {
        queue = []
        looping = false
        playing = .fireflies
        player.play(.fireflies, origin: IntroAnchor.locate(prefer: anchor).point, speed: speed,
                    respectReduceMotion: false, skippable: false) { [weak self] in self?.playing = nil }
    }

    func resetParams() { params = FireflyParams() }

    func randomize() {
        var next = params
        for dial in FireflyDial.sections.flatMap(\.dials) {
            next[keyPath: dial.key] = Float.random(in: dial.taste)
        }
        next.speed = 1
        params = next
    }

    func copyParams() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(params.json, forType: .string)
    }

    func refreshPresets() { presetNames = FireflyPresets.all().keys.sorted() }

    func savePreset(_ name: String) {
        FireflyPresets.save(params, as: name)
        refreshPresets()
    }

    func loadPreset(_ name: String) {
        if let preset = FireflyPresets.all()[name] { params = preset }
    }

    func deletePreset(_ name: String) {
        FireflyPresets.delete(name)
        refreshPresets()
    }

    private func start(_ effect: IntroEffect) {
        let origin = IntroAnchor.locate(prefer: anchor).point
        looping = false
        playing = effect
        // Step out of the way so the effect has the whole screen.
        setWindowVisible(false)
        player.play(effect, origin: origin, speed: speed, respectReduceMotion: false) { [weak self] in
            guard let self else { return }
            if !self.queue.isEmpty {
                let next = self.queue.removeFirst()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { self.start(next) }
            } else {
                self.playing = nil
                self.setWindowVisible(true)
            }
        }
    }
}

struct IntroLabView: View {
    @Environment(IntroLabModel.self) private var model

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Intro Lab")
                    .font(.system(size: 17, weight: .semibold))
                    .tracking(-0.2)
                Text("Each plays over your real screen and ends on Park’s icon. Click or press any key to skip.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 18)
            .padding(.top, 34)
            .padding(.bottom, 14)

            VStack(spacing: 2) {
                ForEach(Array(IntroEffect.allCases.enumerated()), id: \.element) { index, effect in
                    EffectRow(number: index + 1, effect: effect)
                }
            }
            .padding(.horizontal, 8)

            Divider().padding(.top, 10)

            HStack(spacing: 12) {
                Picker("Speed", selection: $model.speed) {
                    Text("1×").tag(1.0)
                    Text("½×").tag(0.5)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 92)
                .help("Half speed, to study the motion")

                Picker("Start from", selection: $model.anchor) {
                    Text(model.foundParkIcon ? "Park’s icon" : "Park’s icon (hidden)").tag(IntroAnchor.Source.parkIcon)
                    Text("Near the clock").tag(IntroAnchor.Source.nearClock)
                }
                .labelsHidden()
                .fixedSize()
                .help(model.foundParkIcon ? "Starts at Park’s icon in your menu bar"
                                          : "Park’s icon isn’t visible, so effects start near the clock")

                Spacer()

                Button("Play all") { model.playAll() }
                    .buttonStyle(LabButtonStyle(prominent: true))
                    .keyboardShortcut(.return, modifiers: [])
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(width: 460)
        .onAppear { model.refreshAnchor() }
    }
}

private struct EffectRow: View {
    @Environment(IntroLabModel.self) private var model
    var number: Int
    var effect: IntroEffect
    @State private var hovering = false

    /// The effect being tuned stays highlighted.
    private var selected: Bool { model.tuning && effect == .fireflies }

    var body: some View {
        Button { model.play(effect) } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(number)")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(Theme.hover))
                VStack(alignment: .leading, spacing: 2) {
                    Text(effect.title)
                        .font(.system(size: 13, weight: .semibold))
                    Text(effect.intent)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                // Room for the tune button, which sits on top so it gets its own clicks.
                if effect == .fireflies { Color.clear.frame(width: 28, height: 28) }
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? .white : Theme.brand)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(hovering ? Theme.brand : Theme.brand.opacity(0.1)))
                    .animation(Theme.quick, value: hovering)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering || selected ? Theme.hover : .clear))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Theme.brand.opacity(selected ? 0.35 : 0), lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if effect == .fireflies {
                Button { model.setTuning(!model.tuning) } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(model.tuning ? .white : Theme.brand)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(model.tuning ? Theme.brand : Theme.brand.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 10 + 28 + 12)
                .padding(.top, 7)
                .help(model.tuning ? "Close the tuning panel" : "Tune Fireflies live")
            }
        }
        .onHover { hovering = $0 }
        .keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: [])
        .help("Play \(effect.title) (\(number))")
    }
}

private struct LabButtonStyle: ButtonStyle {
    var prominent = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(prominent ? .white : .primary)
            .padding(.horizontal, 14)
            .frame(height: 28)
            .background(Capsule().fill(prominent ? Theme.brand : Theme.hover))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

enum IntroLab {
    @MainActor
    /// - Parameters:
    ///   - tuning: open with Fireflies' tuning panel showing.
    ///   - looping: and start Fireflies replaying.
    static func run(tuning: Bool = false, looping: Bool = false) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let model = IntroLabModel()

        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.level = .floating
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: IntroLabView().environment(model))
        window.contentView = hosting
        window.setContentSize(hosting.fittingSize)
        if let screen = NSScreen.main {
            let v = screen.visibleFrame
            window.setFrameOrigin(NSPoint(x: v.minX + 40, y: v.minY + 40))
        }
        model.setWindowVisible = { [weak window] visible in
            guard let window else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = visible ? 0.2 : 0.12
                window.animator().alphaValue = visible ? 1 : 0
            }
            if visible { window.makeKeyAndOrderFront(nil) }
        }

        // Fireflies' tuning panel floats beside the lab and stays usable while the effect loops.
        let tuner = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 600),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        tuner.titleVisibility = .hidden
        tuner.titlebarAppearsTransparent = true
        tuner.isMovableByWindowBackground = true
        tuner.level = .floating
        tuner.isReleasedWhenClosed = false
        let tunerHosting = NSHostingView(rootView: FireflyTunerView().environment(model))
        tuner.contentView = tunerHosting
        tuner.setContentSize(tunerHosting.fittingSize)
        tuner.setFrameOrigin(NSPoint(x: window.frame.maxX + 12, y: window.frame.minY))
        let tunerCloser = TunerCloser { model.setTuning(false) }
        tuner.delegate = tunerCloser
        model.setTunerVisible = { [weak tuner] visible in
            guard let tuner else { return }
            if visible { tuner.orderFront(nil) } else { tuner.orderOut(nil) }
        }

        let closer = WindowCloser()
        window.delegate = closer
        window.makeKeyAndOrderFront(nil)
        if tuning {
            model.setTuning(true)
            if looping { DispatchQueue.main.async { model.setLooping(true) } }
        }
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime((closer, tunerCloser, tuner, model)) { app.run() }
    }

    /// Plays one effect once from the command line, then quits: `Park --intro=ripple [--speed=0.5]`.
    @MainActor
    static func playOnce(_ effect: IntroEffect, speed: Double, anchor: IntroAnchor.Source) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let player = IntroEffectPlayer()
        let origin = IntroAnchor.locate(prefer: anchor).point
        DispatchQueue.main.async {
            player.play(effect, origin: origin, speed: speed, respectReduceMotion: false) {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { app.terminate(nil) }
            }
        }
        withExtendedLifetime(player) { app.run() }
    }

    private final class WindowCloser: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }
    }

    /// Closing the tuning panel just hides it (and stops the loop).
    private final class TunerCloser: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowShouldClose(_ sender: NSWindow) -> Bool { onClose(); return false }
    }
}
