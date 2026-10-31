import AppKit
import SwiftUI

/// Up to three overlapping app icons, with a count for the rest.
struct IconStack: View {
    var bundleIDs: [String]
    var size: CGFloat = 22

    /// Three slots at most: three icons, or two icons and a "+N" badge.
    private var visible: [String] { Array(bundleIDs.prefix(bundleIDs.count > 3 ? 2 : 3)) }
    private var overflow: Int { bundleIDs.count - visible.count }

    var body: some View {
        HStack(spacing: -size * 0.32) {
            ForEach(Array(visible.enumerated()), id: \.element) { index, id in
                Image(nsImage: AppIcons.icon(for: id))
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size, height: size)
                    .shadow(color: .black.opacity(0.12), radius: 1, y: 0.5)
                    .zIndex(Double(visible.count - index))
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 9.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: size, height: size)
                    .background(Circle().fill(.background.secondary))
                    .overlay(Circle().strokeBorder(Theme.hairline))
            }
        }
        .frame(width: stackWidth, alignment: .leading)
        .accessibilityHidden(true)
    }

    /// Fixed width so titles line up across rows regardless of icon count.
    private var stackWidth: CGFloat { size + 2 * size * 0.68 }
}

/// The filled accent button used for the single primary action.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(isEnabled ? 1 : 0.35))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.black.opacity(configuration.isPressed ? 0.14 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Theme.quick, value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

/// A quiet text button that shows a background on hover, for secondary actions.
struct QuietButtonStyle: ButtonStyle {
    var prominent = false
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(prominent ? Color.accentColor : .secondary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed ? Theme.pressed : hovering ? Theme.hover : .clear)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// A keyboard shortcut hint drawn like a key cap.
struct KeyHint: View {
    var text: String
    var onAccent = false

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(onAccent ? .white.opacity(0.7) : Color.secondary)
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 18)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(onAccent ? .white.opacity(0.16) : Theme.hover)
            )
    }
}
