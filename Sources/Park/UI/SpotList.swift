import SwiftUI

struct SpotList: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: Spot.ID?
    @Binding var renamingID: Spot.ID?

    var body: some View {
        let spots = model.store.spots
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Parked")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                if !spots.isEmpty {
                    Text("\(spots.count)")
                        .font(.system(size: 11.5).monospacedDigit())
                        .foregroundStyle(.tertiary)
                        .contentTransition(.numericText())
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 4)

            if spots.isEmpty {
                EmptyParked()
            } else if spots.count > Theme.maxVisibleRows {
                ScrollViewReader { proxy in
                    ScrollView {
                        rows(spots)
                    }
                    .onChange(of: selection) { _, id in
                        guard let id else { return }
                        withAnimation(Theme.quick) { proxy.scrollTo(id) }
                    }
                }
                .scrollIndicators(.never)
                .frame(height: CGFloat(Theme.maxVisibleRows) * Theme.rowHeight + Theme.rowHeight / 2)
            } else {
                rows(spots)
            }
        }
        .animation(Theme.spring, value: spots)
    }

    private func rows(_ spots: [Spot]) -> some View {
        VStack(spacing: 0) {
            ForEach(spots) { spot in
                SpotRow(
                    spot: spot,
                    isSelected: selection == spot.id,
                    isRenaming: Binding(
                        get: { renamingID == spot.id },
                        set: { renamingID = $0 ? spot.id : nil }
                    )
                )
                .id(spot.id)
                .transition(.asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity),
                    removal: .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
                ))
            }
        }
        .padding(.horizontal, Theme.outerPadding)
        .padding(.bottom, Theme.outerPadding)
    }
}

private struct EmptyParked: View {
    var body: some View {
        Text("Nothing parked yet. Park a desktop to close its windows and free up memory. They’ll come back exactly as you left them.")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .lineSpacing(1.5)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 16)
            .padding(.top, 2)
            .padding(.bottom, 14)
    }
}

struct SpotRow: View {
    @Environment(AppModel.self) private var model
    var spot: Spot
    var isSelected: Bool
    @Binding var isRenaming: Bool

    @State private var hovering = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    private var isRestoring: Bool { model.restoringID == spot.id }
    private var justParked: Bool { model.justParkedID == spot.id }
    private var showsActions: Bool { (hovering || isSelected) && !isRenaming }

    var body: some View {
        HStack(spacing: 10) {
            IconStack(bundleIDs: spot.bundleIDs)

            VStack(alignment: .leading, spacing: 1) {
                if isRenaming {
                    TextField("Name", text: $draftName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, weight: .medium))
                        .focused($nameFocused)
                        .onSubmit(commitRename)
                        .onExitCommand { isRenaming = false }
                        .onAppear {
                            draftName = spot.name
                            nameFocused = true
                        }
                } else {
                    Text(spot.name)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(subtitle)
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isRestoring {
                ProgressView().controlSize(.small)
                    .padding(.trailing, 6)
            } else if !showsActions, let freed = spot.freedBytes, freed > 50_000_000 {
                Text(ByteText.short(freed))
                    .font(.system(size: 11.5).monospacedDigit())
                    .foregroundStyle(.tertiary)
                    .padding(.trailing, 4)
                    .help("Memory freed when this desktop was parked")
                    .transition(.opacity)
            } else if showsActions {
                HStack(spacing: 2) {
                    Button("Restore") { Task { await model.restore(spot) } }
                        .buttonStyle(QuietButtonStyle(prominent: true))
                    RowMenu(spot: spot, rename: startRename)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, Theme.rowPadding)
        .frame(height: Theme.rowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.rowRadius, style: .continuous)
                .fill(background)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(count: 2) { startRename() }
        .contextMenu {
            Button("Restore") { Task { await model.restore(spot) } }
            Button("Rename…", action: startRename)
            Divider()
            Button("Delete", role: .destructive) { withAnimation(Theme.spring) { model.delete(spot) } }
        }
        .animation(Theme.quick, value: showsActions)
        .animation(.easeOut(duration: 0.6), value: justParked)
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Reopens these windows on this desktop")
        .accessibilityAction { Task { await model.restore(spot) } }
        .accessibilityAction(named: "Rename", startRename)
        .accessibilityAction(named: "Delete") { model.delete(spot) }
    }

    private var background: Color {
        if justParked { return Color.accentColor.opacity(0.14) }
        if isSelected || hovering || isRenaming { return Theme.hover }
        return .clear
    }

    private var subtitle: String {
        "\(spot.summary) · \(RelativeTime.string(for: spot.createdAt))"
    }

    /// Lists what's inside so you can check before restoring.
    private var helpText: String {
        spot.windows.prefix(12).map { window in
            if let title = window.title, !title.isEmpty { return "\(window.appName) — \(title)" }
            return window.appName
        }.joined(separator: "\n")
    }

    private func startRename() {
        draftName = spot.name
        isRenaming = true
    }

    private func commitRename() {
        model.store.rename(spot.id, to: draftName)
        isRenaming = false
    }
}

private struct RowMenu: View {
    @Environment(AppModel.self) private var model
    var spot: Spot
    var rename: () -> Void

    var body: some View {
        Menu {
            Button("Rename…", action: rename)
            Divider()
            Button("Delete", role: .destructive) { withAnimation(Theme.spring) { model.delete(spot) } }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
