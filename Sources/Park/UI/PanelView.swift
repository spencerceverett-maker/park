import SwiftUI

struct PanelView: View {
    @Environment(AppModel.self) private var model
    var onHeightChange: (CGFloat) -> Void = { _ in }

    @State private var selection: Spot.ID?
    @State private var renamingID: Spot.ID?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if model.hasAccessibility {
                DesktopSection()
                Divider().overlay(Theme.hairline)
                SpotList(selection: $selection, renamingID: $renamingID)
            } else {
                PermissionSection()
            }
            Divider().overlay(Theme.hairline)
            FooterBar()
        }
        .frame(width: PanelController.width)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { onHeightChange(proxy.size.height) }
                    .onChange(of: proxy.size.height) { _, height in onHeightChange(height) }
            }
        )
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { moveSelection(by: 1) }
        .onKeyPress(.upArrow) { moveSelection(by: -1) }
        .onKeyPress(.return) { activate() }
        .onKeyPress(.delete) { deleteSelection() }
        .onKeyPress(.deleteForward) { deleteSelection() }
        .onChange(of: model.store.spots) { _, spots in
            if let selection, !spots.contains(where: { $0.id == selection }) { self.selection = nil }
        }
    }

    // MARK: - Keyboard

    private func moveSelection(by delta: Int) -> KeyPress.Result {
        guard renamingID == nil else { return .ignored }
        let spots = model.store.spots
        guard !spots.isEmpty else { return .handled }
        let current = selection.flatMap { id in spots.firstIndex { $0.id == id } }
        let next: Int? = switch current {
        case nil: delta > 0 ? 0 : nil
        case let index?: index + delta < 0 ? nil : min(index + delta, spots.count - 1)
        }
        withAnimation(Theme.quick) { selection = next.map { spots[$0].id } }
        return .handled
    }

    private func activate() -> KeyPress.Result {
        guard renamingID == nil else { return .ignored }
        if let id = selection, let spot = model.store.spots.first(where: { $0.id == id }) {
            Task { await model.restore(spot) }
        } else if model.hasAccessibility {
            Task { await model.park() }
        }
        return .handled
    }

    private func deleteSelection() -> KeyPress.Result {
        guard renamingID == nil, let id = selection,
              let spot = model.store.spots.first(where: { $0.id == id }) else { return .ignored }
        withAnimation(Theme.spring) { model.delete(spot) }
        return .handled
    }
}

// MARK: - This desktop

private struct DesktopSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let loading = model.preview == nil
        let preview = model.preview ?? .empty
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                if loading {
                    ProgressView().controlSize(.small)
                        .frame(width: 22 + 2 * 22 * 0.68, alignment: .leading)
                } else if preview.windowCount > 0 {
                    IconStack(bundleIDs: preview.bundleIDs)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))
                        .foregroundStyle(.tertiary)
                        .frame(width: 22, height: 22)
                        .frame(width: 22 + 2 * 22 * 0.68, alignment: .leading)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(loading ? "This desktop" : preview.windowCount > 0 ? NameList.string(preview.appNames) : "Nothing open here")
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(loading ? "Looking for windows…" : subtitle(preview))
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if !preview.runningCommands.isEmpty {
                RunningWarning(commands: preview.runningCommands)
                    .transition(.opacity)
            }

            Button {
                Task { await model.park() }
            } label: {
                HStack(spacing: 8) {
                    if model.isParking {
                        ProgressView().controlSize(.small).tint(.white)
                        Text("Parking…")
                    } else {
                        Text("Park this desktop")
                        KeyHint(text: "↩", onAccent: true)
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled((!loading && preview.windowCount == 0) || model.isParking)

            if let error = model.errorMessage {
                Text(error)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(16)
        .animation(Theme.spring, value: model.errorMessage)
    }

    private func subtitle(_ preview: DesktopPreview) -> String {
        switch preview.windowCount {
        case 0: return "Switch to a desktop with windows to park it"
        case 1: return "1 window on this desktop"
        default: return "\(preview.windowCount) windows on this desktop"
        }
    }
}

/// Parking closes terminal windows, and the terminal stops what was running in them shortly after.
private struct RunningWarning: View {
    var commands: [String]

    private var text: String {
        let shown = commands.prefix(2).map { "“\(Self.short($0))”" }
        let rest = commands.count > 2 ? " and \(commands.count - 2) more" : ""
        let list = shown.joined(separator: " and ") + rest
        return commands.count == 1
            ? "\(list) is running. It stops about a minute after parking and won’t restart on its own."
            : "\(list) are running. They stop about a minute after parking and won’t restart on their own."
    }

    private static func short(_ command: String) -> String {
        command.count > 28 ? String(command.prefix(27)) + "…" : command
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(text)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .help(commands.joined(separator: "\n"))
    }
}

// MARK: - Permission

private struct PermissionSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "macwindow.on.rectangle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.accentColor)
                .frame(width: 40, height: 40)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.12)))

            VStack(alignment: .leading, spacing: 4) {
                Text("Let Park see your windows")
                    .font(.system(size: 15, weight: .semibold))
                Text("Park needs Accessibility access to find the windows on a desktop, close them, and put them back later. Everything stays on your Mac.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(1.5)
            }

            Button("Open System Settings") { model.requestAccessibility() }
                .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: 6) {
                ProgressView().controlSize(.mini)
                Text("Turn on Park in Privacy & Security → Accessibility. This updates on its own.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .task {
            // Poll until access is granted; there is no notification for it.
            while !Task.isCancelled && !model.hasAccessibility {
                try? await Task.sleep(for: .milliseconds(800))
                if AXIsProcessTrusted() {
                    withAnimation(Theme.spring) { model.refresh() }
                }
            }
        }
    }
}

// MARK: - Footer

private struct FooterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                if let toast = model.toast {
                    ToastView(toast: toast)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                        .id(toast.id)
                } else {
                    MemoryMeter(stats: model.memory)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()

            SettingsMenu()
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .frame(height: 40)
        .animation(Theme.spring, value: model.toast)
    }
}

private struct MemoryMeter: View {
    var stats: MemoryStats

    private var tint: Color {
        switch stats.fraction {
        case ..<0.75: return .secondary
        case ..<0.9: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Theme.hover)
                .frame(width: 44, height: 4)
                .overlay(alignment: .leading) {
                    Capsule().fill(tint).frame(width: max(4, 44 * stats.fraction), height: 4)
                }
            Text("\(ByteText.gigabytes(stats.used)) of \(ByteText.short(stats.total)) memory used")
                .font(.system(size: 11.5).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .help("Memory in use across your Mac, as Activity Monitor reports it")
    }
}

private struct ToastView: View {
    var toast: Toast
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
            Text(toast.message)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(1)
            if let undo = toast.undo {
                Button("Undo") {
                    withAnimation(Theme.spring) {
                        undo()
                        model.toast = nil
                    }
                }
                .buttonStyle(QuietButtonStyle(prominent: true))
            }
        }
    }
}

private struct SettingsMenu: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LoginItem.isEnabled

    var body: some View {
        if Snapshot.isRendering {
            // ImageRenderer can't draw menus; show the button's face instead.
            label
        } else {
            menu
        }
    }

    private var label: some View {
        Image(systemName: "ellipsis")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 24)
            .contentShape(Rectangle())
    }

    private var menu: some View {
        @Bindable var model = model
        return Menu {
            Toggle("Quit Apps Not Used on Other Desktops", isOn: $model.quitApps)
            Toggle("Open at Login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in LoginItem.set(enabled) }
            Divider()
            Text("Open Park: ⌃⌥P")
            Text("Park this desktop: ⌃⌥⌘P")
            Divider()
            Button("Quit Park") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            label
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Settings")
    }
}
