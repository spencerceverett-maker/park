import SwiftUI

/// Frames of panel elements the guided tour points at, reported up to the panel's root.
struct TourAnchorsKey: PreferenceKey {
    static var defaultValue: [TourAnchor: CGRect] = [:]
    static func reduce(value: inout [TourAnchor: CGRect], nextValue: () -> [TourAnchor: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

extension View {
    /// Reports this view's frame (in the panel's coordinates) so a tour callout can point at it.
    func tourAnchor(_ anchor: TourAnchor) -> some View {
        background(GeometryReader { proxy in
            Color.clear.preference(key: TourAnchorsKey.self, value: [anchor: proxy.frame(in: .global)])
        })
    }

    /// A soft, slow pulse of brand blue around the element the tour is pointing at.
    func tourGlow(_ active: Bool, cornerRadius: CGFloat = 8) -> some View {
        modifier(TourGlow(active: active, cornerRadius: cornerRadius))
    }
}

private struct TourGlow: ViewModifier {
    var active: Bool
    var cornerRadius: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var breathe = false

    func body(content: Content) -> some View {
        content.overlay(
            RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
                .strokeBorder(Theme.brand.opacity(active ? (breathe ? 0.85 : 0.4) : 0), lineWidth: 1.5)
                .padding(-3)
                .shadow(color: Theme.brand.opacity(active ? (breathe ? 0.45 : 0.2) : 0), radius: breathe ? 9 : 4)
                .allowsHitTesting(false)
        )
        .animation(.easeOut(duration: 0.25), value: active)
        .onChange(of: active, initial: true) { _, isActive in
            guard isActive, !reduceMotion else { breathe = false; return }
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) { breathe = true }
        }
    }
}
