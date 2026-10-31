import Foundation

/// Every tunable value of the Fireflies intro. Passed to the shaders as-is, so the fields must stay
/// all `Float` and in the same order as `struct Fireflies` in `IntroShaders`.
struct FireflyParams: Codable, Equatable {
    var count: Float = 420
    var size: Float = 1.15             // points, for the smallest motes
    var sizeVariation: Float = 0.6     // power-law spread: most stay small, a few grow
    var softness: Float = 0.55         // crisp point → soft bokeh falloff
    var opacity: Float = 0.8
    var opacityVariation: Float = 0.5
    var twinkle: Float = 0.3
    var twinkleSpeed: Float = 2.2
    var depth: Float = 0.12            // share of large, out-of-focus motes
    var scatter: Float = 1.0           // how much of the screen they start across
    var driftSpeed: Float = 34
    var swirl: Float = 1.2
    var turbulence: Float = 0.45
    var gatherTime: Float = 1.1
    var stagger: Float = 0.6
    var colorMix: Float = 0.45         // deep sign blue → pale horizon
    var whiteCore: Float = 1           // 0 or 1
    var glow: Float = 0.25
    var ringSize: Float = 15
    var ringSoftness: Float = 0.4
    var speed: Float = 1

    /// Seconds of the effect at speed 1: the last motes arrive, the ring settles and fades.
    var duration: Double { Double(0.35 + stagger + gatherTime * 1.2 + 0.75) }

    static let maxCount = 1200
    var instanceCount: Int { min(max(Int(count), 0), Self.maxCount) }

    /// The values as JSON, for pasting back into code or a conversation.
    var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}

/// One control in the tuning panel.
struct FireflyDial: Identifiable {
    let label: String
    let key: WritableKeyPath<FireflyParams, Float>
    let range: ClosedRange<Float>
    /// Where Randomize picks from: the part of the range that still looks good.
    let taste: ClosedRange<Float>
    var decimals = 2
    var id: String { label }

    static let sections: [(title: String, dials: [FireflyDial])] = [
        ("Motes", [
            FireflyDial(label: "Count", key: \.count, range: 40...1200, taste: 220...700, decimals: 0),
            FireflyDial(label: "Size", key: \.size, range: 0.4...4, taste: 0.7...1.6),
            FireflyDial(label: "Size variation", key: \.sizeVariation, range: 0...1, taste: 0.35...0.8),
            FireflyDial(label: "Softness", key: \.softness, range: 0...1, taste: 0.3...0.85),
        ]),
        ("Light", [
            FireflyDial(label: "Opacity", key: \.opacity, range: 0.05...1, taste: 0.55...0.95),
            FireflyDial(label: "Opacity variation", key: \.opacityVariation, range: 0...1, taste: 0.2...0.7),
            FireflyDial(label: "Glow", key: \.glow, range: 0...1, taste: 0.15...0.6),
            FireflyDial(label: "Color", key: \.colorMix, range: 0...1, taste: 0.25...0.7),
        ]),
        ("Twinkle", [
            FireflyDial(label: "Amount", key: \.twinkle, range: 0...1, taste: 0.1...0.5),
            FireflyDial(label: "Speed", key: \.twinkleSpeed, range: 0...8, taste: 1...4),
        ]),
        ("Depth & motion", [
            FireflyDial(label: "Depth", key: \.depth, range: 0...0.6, taste: 0.05...0.25),
            FireflyDial(label: "Scatter", key: \.scatter, range: 0.2...1.2, taste: 0.7...1.1),
            FireflyDial(label: "Drift speed", key: \.driftSpeed, range: 0...120, taste: 15...60, decimals: 0),
            FireflyDial(label: "Swirl", key: \.swirl, range: 0...4, taste: 0.4...2),
            FireflyDial(label: "Turbulence", key: \.turbulence, range: 0...1, taste: 0.2...0.7),
        ]),
        ("Gather", [
            FireflyDial(label: "Gather time", key: \.gatherTime, range: 0.3...3, taste: 0.8...1.5),
            FireflyDial(label: "Stagger", key: \.stagger, range: 0...1.5, taste: 0.3...0.9),
            FireflyDial(label: "Ring size", key: \.ringSize, range: 8...40, taste: 13...20, decimals: 1),
            FireflyDial(label: "Ring softness", key: \.ringSoftness, range: 0...1, taste: 0.2...0.7),
            FireflyDial(label: "Overall speed", key: \.speed, range: 0.25...2, taste: 0.8...1.2),
        ]),
    ]
}

/// Named presets, kept in the lab's defaults.
enum FireflyPresets {
    private static let key = "IntroLab.fireflyPresets"

    static func all() -> [String: FireflyParams] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let presets = try? JSONDecoder().decode([String: FireflyParams].self, from: data) else { return [:] }
        return presets
    }

    static func save(_ params: FireflyParams, as name: String) {
        var presets = all()
        presets[name] = params
        write(presets)
    }

    static func delete(_ name: String) {
        var presets = all()
        presets[name] = nil
        write(presets)
    }

    private static func write(_ presets: [String: FireflyParams]) {
        if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: key) }
    }
}
