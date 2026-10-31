import AppKit
import Observation
import SwiftUI

/// A small floating window for choosing Park's first-launch moment by feel: each button plays an effect
/// live over the real screen. Run with `Park --intro-lab`; it runs alongside an installed Park.
@MainActor
@Observable
final class IntroLabModel {
    var speed: Double = 1
    var anchor: IntroAnchor.Source = .parkIcon
    var foundParkIcon = false
    var playing: IntroEffect?

    @ObservationIgnored let player = IntroEffectPlayer()
    @ObservationIgnored var setWindowVisible: (Bool) -> Void = { _ in }
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

    private func start(_ effect: IntroEffect) {
        let origin = IntroAnchor.locate(prefer: anchor).point
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
        .frame(width: 440)
        .onAppear { model.refreshAnchor() }
    }
}

private struct EffectRow: View {
    @Environment(IntroLabModel.self) private var model
    var number: Int
    var effect: IntroEffect
    @State private var hovering = false

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
                Image(systemName: "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(hovering ? .white : Theme.brand)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(hovering ? Theme.brand : Theme.brand.opacity(0.1)))
                    .animation(Theme.quick, value: hovering)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
    static func run() {
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

        let closer = WindowCloser()
        window.delegate = closer
        window.makeKeyAndOrderFront(nil)
        app.activate(ignoringOtherApps: true)
        withExtendedLifetime((closer, model)) { app.run() }
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
}
