import AppKit
import SwiftUI

/// A compact panel of dials for tuning Fireflies live, in the spirit of DialKit: each row is the slider,
/// its label on the left and its value on the right. Changes apply to the running effect immediately.
struct FireflyTunerView: View {
    @Environment(IntroLabModel.self) private var model
    @State private var presetName = ""
    @State private var copied = false

    var body: some View {
        @Bindable var model = model
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("Fireflies")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Toggle("Loop", isOn: Binding(get: { model.looping }, set: { model.setLooping($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11.5))
                    .help("Replay continuously while you tune")
                Button { model.playFirefliesOnce() } label: {
                    Image(systemName: "play.fill").font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(DialIconButtonStyle(prominent: true))
                .help("Play once")
            }
            .padding(.horizontal, 14)
            .padding(.top, 30)
            .padding(.bottom, 10)

            Divider().overlay(Theme.hairline)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(FireflyDial.sections, id: \.title) { section in
                        DialSectionHeader(title: section.title)
                        ForEach(section.dials) { dial in
                            DialRow(dial: dial, value: $model.params[dynamicMember: dial.key],
                                    defaultValue: FireflyParams()[keyPath: dial.key])
                        }
                        if section.title == "Light" {
                            DialToggleRow(label: "White-hot core",
                                          isOn: Binding(get: { model.params.whiteCore > 0.5 },
                                                        set: { model.params.whiteCore = $0 ? 1 : 0 }))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
            }
            .frame(maxHeight: 560)

            Divider().overlay(Theme.hairline)

            VStack(spacing: 8) {
                HStack(spacing: 6) {
                    Menu {
                        if model.presetNames.isEmpty { Text("No presets yet") }
                        ForEach(model.presetNames, id: \.self) { name in
                            Button(name) { model.loadPreset(name) }
                        }
                        if !model.presetNames.isEmpty {
                            Divider()
                            Menu("Delete") {
                                ForEach(model.presetNames, id: \.self) { name in
                                    Button(name, role: .destructive) { model.deletePreset(name) }
                                }
                            }
                        }
                    } label: {
                        Text("Presets").font(.system(size: 11.5, weight: .medium))
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    Spacer()
                    Button { model.randomize() } label: { Image(systemName: "dice") }
                        .buttonStyle(DialIconButtonStyle())
                        .help("Randomize within tasteful ranges")
                    Button { model.resetParams() } label: { Image(systemName: "arrow.counterclockwise") }
                        .buttonStyle(DialIconButtonStyle())
                        .help("Reset to defaults")
                    Button {
                        model.copyParams()
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .buttonStyle(DialIconButtonStyle(wide: true))
                    .help("Copy the values as JSON")
                }
                HStack(spacing: 6) {
                    TextField("Preset name", text: $presetName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                        .onSubmit(save)
                    Button("Save", action: save)
                        .buttonStyle(DialIconButtonStyle(wide: true))
                        .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 300)
        .onAppear { model.refreshPresets() }
    }

    private func save() {
        let name = presetName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.savePreset(name)
        presetName = ""
    }
}

private struct DialSectionHeader: View {
    var title: String
    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(.tertiary)
            .padding(.top, 12)
            .padding(.bottom, 2)
            .padding(.leading, 2)
    }
}

/// One dial: drag anywhere on the row to set it; the fill shows where it sits in its range.
/// The value turns brand blue when it differs from the default; double-click resets it.
private struct DialRow: View {
    let dial: FireflyDial
    @Binding var value: Float
    let defaultValue: Float
    @State private var dragging = false
    @State private var hovering = false

    private var fraction: CGFloat {
        CGFloat((value - dial.range.lowerBound) / (dial.range.upperBound - dial.range.lowerBound)).clamped
    }
    private var changed: Bool { abs(value - defaultValue) > 0.0001 }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(hovering || dragging ? Theme.pressed : Theme.hover)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.brand.opacity(dragging ? 0.3 : 0.2))
                    .frame(width: max(6, fraction * geo.size.width))
                HStack {
                    Text(dial.label).foregroundStyle(.primary.opacity(0.85))
                    Spacer()
                    Text(String(format: "%.\(dial.decimals)f", value))
                        .monospacedDigit()
                        .foregroundStyle(changed ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(.secondary))
                }
                .font(.system(size: 11.5))
                .padding(.horizontal, 8)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    dragging = true
                    let f = Float((drag.location.x / max(geo.size.width, 1)).clamped)
                    value = dial.range.lowerBound + f * (dial.range.upperBound - dial.range.lowerBound)
                }
                .onEnded { _ in dragging = false })
            .simultaneousGesture(TapGesture(count: 2).onEnded { value = defaultValue })
        }
        .frame(height: 24)
        .onHover { hovering = $0 }
        .animation(Theme.quick, value: dragging)
        .help("Double-click to reset to \(String(format: "%.\(dial.decimals)f", defaultValue))")
    }
}

private struct DialToggleRow: View {
    var label: String
    @Binding var isOn: Bool
    var body: some View {
        HStack {
            Text(label).font(.system(size: 11.5)).foregroundStyle(.primary.opacity(0.85))
            Spacer()
            Toggle(label, isOn: $isOn).toggleStyle(.switch).controlSize(.mini).labelsHidden()
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.hover))
    }
}

private struct DialIconButtonStyle: ButtonStyle {
    var prominent = false
    var wide = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11.5, weight: .medium))
            .foregroundStyle(prominent ? .white : .primary)
            .padding(.horizontal, wide ? 10 : 0)
            .frame(minWidth: 26, minHeight: 24)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(prominent ? Theme.brand : (configuration.isPressed ? Theme.pressed : Theme.hover)))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
    }
}

private extension CGFloat {
    var clamped: CGFloat { Swift.min(Swift.max(self, 0), 1) }
}
