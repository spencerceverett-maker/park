import AppKit
import SwiftUI

/// A miniature Mac for the walkthrough: three practice windows and Park's panel, built from the same
/// pieces as the real one. Parking and restoring here only moves these drawings; nothing on the
/// user's Mac is touched.
struct PracticeDesk: View {
    enum Phase: Equatable { case ready, parked, restored }

    @Binding var phase: Phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Windows are folded into the panel's list while parked.
    @State private var folded = false
    @State private var rowShown = false
    @State private var memory: Double = 13.1

    static let size = CGSize(width: 540, height: 300)

    var body: some View {
        ZStack(alignment: .topLeading) {
            DawnWallpaper()
            ForEach(Array(PracticeWindow.all.enumerated()), id: \.element.id) { index, window in
                MockWindow(window: window)
                    .frame(width: window.frame.width, height: window.frame.height)
                    .scaleEffect(folded ? 0.1 : 1, anchor: .center)
                    .offset(foldOffset(for: window))
                    .opacity(folded ? 0 : 1)
                    .position(x: window.frame.midX, y: window.frame.midY)
                    .animation(windowAnimation(index: index), value: folded)
            }
            MiniMenuBar()
            PracticePanel(phase: phase, rowShown: rowShown, memory: memory, park: park, restore: restore)
                .frame(width: PracticePanel.width)
                .offset(x: Self.size.width - PracticePanel.width - 12, y: 28)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
        .shadow(color: Color(red: 0.04, green: 0.11, blue: 0.27).opacity(0.22), radius: 18, y: 10)
        .onAppear(perform: syncToPhase)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Practice desktop with three windows and Park's panel")
    }

    /// Snapshots and reopened walkthroughs start in whatever state `phase` says.
    private func syncToPhase() {
        let parked = phase == .parked
        folded = parked
        rowShown = parked
        memory = parked ? 10.8 : 13.1
    }

    // MARK: Actions

    private func park() {
        guard phase != .parked else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        folded = true
        // The row lands as the windows arrive, so they read as going into it.
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Theme.spring.delay(0.22)) { rowShown = true }
        withAnimation(.easeOut(duration: 0.9).delay(0.25)) { memory = 10.8 }
        withAnimation(Theme.spring.delay(0.35)) { phase = .parked }
    }

    private func restore() {
        guard phase == .parked else { return }
        withAnimation(reduceMotion ? .easeOut(duration: 0.15) : Theme.spring) { rowShown = false }
        folded = false
        withAnimation(.easeOut(duration: 0.7)) { memory = 13.1 }
        withAnimation(Theme.spring.delay(0.45)) { phase = .restored }
    }

    // MARK: Motion

    /// Where the new row's icons sit, in desk coordinates; windows fold toward it.
    private static let rowTarget = CGPoint(x: size.width - PracticePanel.width - 12 + 38, y: 28 + 140)

    private func foldOffset(for window: PracticeWindow) -> CGSize {
        guard folded, !reduceMotion else { return .zero }
        return CGSize(width: Self.rowTarget.x - window.frame.midX, height: Self.rowTarget.y - window.frame.midY)
    }

    private func windowAnimation(index: Int) -> Animation {
        if reduceMotion { return .easeOut(duration: 0.18) }
        // Critically damped; front windows leave first and come back last.
        let order = folded ? Double(PracticeWindow.all.count - 1 - index) : Double(index)
        return .spring(response: 0.5, dampingFraction: 1).delay(order * 0.05)
    }
}

// MARK: - Panel

/// Park's panel, scaled for the practice desk, using the real panel's components and metrics.
private struct PracticePanel: View {
    static let width: CGFloat = 236

    var phase: PracticeDesk.Phase
    var rowShown: Bool
    var memory: Double
    var park: () -> Void
    var restore: () -> Void

    private var parked: Bool { phase == .parked }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // This desktop
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    if parked {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                            .foregroundStyle(.tertiary)
                            .frame(width: 17, height: 17)
                            .frame(width: 17 + 2 * 17 * 0.68, alignment: .leading)
                    } else {
                        IconStack(bundleIDs: PracticeWindow.bundleIDs, size: 17)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(parked ? "Nothing open here" : "Safari, Freeform and Terminal")
                            .font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Text(parked ? "Switch to a desktop with windows to park it" : "3 windows on this desktop")
                            .font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .contentTransition(.opacity)
                }
                ParkButton(enabled: !parked, action: park)
            }
            .padding(12)

            Divider().overlay(Theme.hairline)

            // Parked
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Parked").font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(rowShown ? 3 : 2)").font(.system(size: 9.5).monospacedDigit()).foregroundStyle(.tertiary)
                        .contentTransition(.numericText())
                }
                .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 2)

                VStack(spacing: 0) {
                    if rowShown {
                        PracticeRow(name: "Practice", detail: "3 windows · Just now", freed: "2.3 GB",
                                    bundleIDs: PracticeWindow.bundleIDs, highlighted: true, restore: restore)
                            .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity),
                                                    removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))))
                    }
                    PracticeRow(name: "Q4 launch plan", detail: "5 windows · Yesterday", freed: "1.0 GB",
                                bundleIDs: ["com.apple.Safari", "com.apple.iWork.Keynote", "com.apple.Notes"])
                    PracticeRow(name: "api-server", detail: "2 windows · Tuesday", freed: nil,
                                bundleIDs: ["com.apple.Terminal", "com.apple.Safari"])
                }
                .padding(.horizontal, 6).padding(.bottom, 6)
            }

            Divider().overlay(Theme.hairline)

            // Memory
            HStack(spacing: 6) {
                Capsule().fill(Theme.hover).frame(width: 32, height: 3)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Theme.brand).frame(width: 32 * memory / 16, height: 3)
                    }
                Text("\(String(format: "%.1f", memory)) of 16 GB memory used")
                    .font(.system(size: 9.5).monospacedDigit()).foregroundStyle(.secondary)
                    .contentTransition(.numericText(value: memory))
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
        }
        .background(PanelMaterial())
        .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 11, style: .continuous).strokeBorder(Color.white.opacity(0.5), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
        .environment(\.colorScheme, .light)
    }
}

/// The panel's primary button, with one quiet invitation to press it.
private struct ParkButton: View {
    var enabled: Bool
    var action: () -> Void
    @State private var invite = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text("Park this desktop")
                KeyHint(text: "↩", onAccent: true).scaleEffect(0.8)
            }
        }
        .buttonStyle(MiniPrimaryButtonStyle())
        .disabled(!enabled)
        .keyboardShortcut(enabled ? .defaultAction : nil)
        .background(
            // A soft ring that breathes until the first press. First-run only, so it can afford to.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.brand.opacity(invite && enabled ? 0 : 0.45), lineWidth: 2)
                .scaleEffect(invite && enabled ? 1.08 : 1)
                .opacity(enabled ? 1 : 0)
        )
        .onAppear {
            guard !reduceMotion, !Snapshot.isRendering else { return }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false).delay(0.8)) { invite = true }
        }
    }
}

private struct MiniPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Theme.brand.opacity(isEnabled ? 1 : 0.35)))
            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(.black.opacity(configuration.isPressed ? 0.14 : 0)))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

private struct PracticeRow: View {
    var name: String
    var detail: String
    var freed: String?
    var bundleIDs: [String]
    var highlighted = false
    var restore: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            IconStack(bundleIDs: bundleIDs, size: 17)
            VStack(alignment: .leading, spacing: 0) {
                Text(name).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(detail).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if let restore {
                Button("Restore", action: restore)
                    .buttonStyle(MiniQuietButtonStyle())
                    .keyboardShortcut(.defaultAction)
            } else if let freed {
                Text(freed).font(.system(size: 9.5).monospacedDigit()).foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(highlighted ? Theme.brand.opacity(0.12) : .clear))
    }
}

private struct MiniQuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .frame(height: 21)
            .background(Capsule().fill(Theme.brand))
            .overlay(Capsule().fill(.black.opacity(configuration.isPressed ? 0.14 : 0)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Popover material over the wallpaper; image snapshots can't render materials, so they get a flat stand-in.
private struct PanelMaterial: View {
    var body: some View {
        if Snapshot.isRendering {
            Color(white: 0.965).opacity(0.94)
        } else {
            Rectangle().fill(.regularMaterial)
        }
    }
}

// MARK: - Desk

/// The website's pre-sunrise blues, so the practice Mac matches the one people saw on parkformac.com.
struct DawnWallpaper: View {
    var body: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Color(red: 0x16 / 255, green: 0x3E / 255, blue: 0x86 / 255), location: 0),
                .init(color: Color(red: 0x1E / 255, green: 0x50 / 255, blue: 0xA8 / 255), location: 0.42),
                .init(color: Color(red: 0x9C / 255, green: 0xC0 / 255, blue: 0xEA / 255), location: 0.82),
                .init(color: Color(red: 0xCF / 255, green: 0xE0 / 255, blue: 0xF5 / 255), location: 1),
            ], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(red: 0xE3 / 255, green: 0xEE / 255, blue: 0xFA / 255).opacity(0.9), .clear],
                           center: UnitPoint(x: 0.72, y: 1.05), startRadius: 0, endRadius: 260)
        }
    }
}

private struct MiniMenuBar: View {
    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: "apple.logo").font(.system(size: 10, weight: .semibold))
            Text("Finder").font(.system(size: 10, weight: .bold))
            ForEach(["File", "Edit", "View", "Window"], id: \.self) { Text($0).font(.system(size: 10)) }
            Spacer()
            Image(nsImage: StatusIcon.image).renderingMode(.template)
                .resizable().frame(width: 12, height: 12)
                .frame(width: 22, height: 16)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(.white.opacity(0.28)))
            Image(systemName: "wifi").font(.system(size: 9.5, weight: .semibold))
            TimelineView(.everyMinute) { context in
                Text(context.date.formatted(.dateTime.weekday(.abbreviated).hour().minute()))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(.white.opacity(0.16))
        .accessibilityHidden(true)
    }
}

struct PracticeWindow: Identifiable {
    enum Kind { case browser, board, terminal }
    let id: Kind
    let title: String
    let frame: CGRect

    static let all: [PracticeWindow] = [
        PracticeWindow(id: .browser, title: "Onboarding research", frame: CGRect(x: 22, y: 42, width: 248, height: 150)),
        PracticeWindow(id: .board, title: "Onboarding redesign", frame: CGRect(x: 128, y: 92, width: 214, height: 140)),
        PracticeWindow(id: .terminal, title: "api-server", frame: CGRect(x: 40, y: 168, width: 214, height: 108)),
    ]
    /// System apps, so the icons are on every Mac.
    static let bundleIDs = ["com.apple.Safari", "com.apple.freeform", "com.apple.Terminal"]
}

private struct MockWindow: View {
    let window: PracticeWindow

    private var dark: Bool { window.id != .browser }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach([Color(red: 1, green: 0.37, blue: 0.34), Color(red: 1, green: 0.74, blue: 0.18), Color(red: 0.16, green: 0.78, blue: 0.25)], id: \.self) {
                    Circle().fill($0).frame(width: 6, height: 6)
                }
                Text(window.title).font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(dark ? Color.white.opacity(0.6) : Color.black.opacity(0.5))
                    .padding(.leading, 6)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 18)
            .background(dark ? Color(white: 0.17) : Color(white: 0.93))
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(dark ? Color(white: 0.12) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.black.opacity(0.18), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 6)
    }

    @ViewBuilder
    private var content: some View {
        switch window.id {
        case .browser:
            VStack(alignment: .leading, spacing: 5) {
                Text("RESEARCH · WEEK 3").font(.system(size: 6, weight: .semibold)).foregroundStyle(.secondary)
                Text("Onboarding research").font(.system(size: 12, weight: .bold)).foregroundStyle(.black)
                ForEach([0.9, 0.75, 0.82], id: \.self) { width in
                    Capsule().fill(Color(white: 0.88)).frame(width: 200 * width, height: 4)
                }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(Color(red: 0.91, green: 0.94, blue: 0.98)).frame(height: 30)
                    RoundedRectangle(cornerRadius: 4).fill(Color(white: 0.94)).frame(height: 30)
                }
            }
            .padding(10)
        case .board:
            HStack(spacing: 8) {
                ForEach([Theme.brand, Color(red: 0x9C / 255, green: 0xC0 / 255, blue: 0xEA / 255), Color(white: 0.85)], id: \.self) { tint in
                    VStack(alignment: .leading, spacing: 4) {
                        RoundedRectangle(cornerRadius: 3).fill(tint).frame(width: 14, height: 14)
                        Capsule().fill(Color(white: 0.8)).frame(width: 36, height: 3)
                        Capsule().fill(Color(white: 0.85)).frame(width: 26, height: 3)
                        Spacer()
                        RoundedRectangle(cornerRadius: 3).fill(Color(white: 0.15)).frame(height: 10)
                    }
                    .padding(6)
                    .frame(width: 56, height: 86)
                    .background(RoundedRectangle(cornerRadius: 5).fill(.white))
                }
            }
            .padding(12)
        case .terminal:
            VStack(alignment: .leading, spacing: 3) {
                Text("~/Developer/api-server").foregroundStyle(Color(red: 0x9C / 255, green: 0xC0 / 255, blue: 0xEA / 255))
                Text("❯ npm run dev").foregroundStyle(.white.opacity(0.85))
                Text("  ▲ Ready on localhost:3000").foregroundStyle(Color(red: 0.4, green: 0.85, blue: 0.5))
                Text("  GET /api/plans 200 in 18 ms").foregroundStyle(.white.opacity(0.55))
            }
            .font(.system(size: 7.5, design: .monospaced))
            .padding(9)
        }
    }
}
