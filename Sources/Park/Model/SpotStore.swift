import Foundation
import Observation

/// Parked spots, newest first, persisted as JSON in Application Support.
@Observable
final class SpotStore {
    private(set) var spots: [Spot] = []

    private let fileURL: URL

    init(fileURL: URL = SpotStore.defaultURL) {
        self.fileURL = fileURL
        load()
    }

    static var defaultURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Park", isDirectory: true).appendingPathComponent("spots.json")
    }

    func insert(_ spot: Spot) {
        spots.insert(spot, at: 0)
        save()
    }

    func remove(_ id: Spot.ID) {
        spots.removeAll { $0.id == id }
        save()
    }

    func rename(_ id: Spot.ID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = spots.firstIndex(where: { $0.id == id }) else { return }
        spots[index].name = trimmed
        save()
    }

    func update(_ spot: Spot) {
        guard let index = spots.firstIndex(where: { $0.id == spot.id }) else { return }
        spots[index] = spot
        save()
    }

    /// Puts a spot back at its original position (used by undo).
    func restore(_ spot: Spot, at index: Int) {
        spots.insert(spot, at: min(index, spots.count))
        save()
    }

    /// Decodes spots one by one, so a single unreadable entry (say, from a newer version of Park)
    /// doesn't take the rest with it. Anything unreadable is backed up before the file is rewritten.
    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = Self.decoder
        guard let entries = try? decoder.decode([Lenient<Spot>].self, from: data) else {
            backUpUnreadableFile()
            return
        }
        spots = entries.compactMap(\.value)
        if spots.count < entries.count {
            backUpUnreadableFile()
            Log.write("skipped \(entries.count - spots.count) unreadable parked desktops; original backed up")
        }
    }

    private func backUpUnreadableFile() {
        let stamp = Date().formatted(.iso8601).replacingOccurrences(of: ":", with: "-")
        let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable-\(stamp).json")
        try? FileManager.default.copyItem(at: fileURL, to: backup)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Self.encoder.encode(spots).write(to: fileURL, options: .atomic)
        } catch {
            Log.write("failed to save parked desktops: \(error)")
        }
    }

    // MARK: - Crash safety

    /// Parking writes what it's about to close here first, so a crash between closing windows and saving
    /// the spot can't lose them. The next launch folds anything left here back into the list.
    static var pendingURL: URL { defaultURL.deletingLastPathComponent().appendingPathComponent("parking.json") }

    static func writePending(_ spot: Spot) {
        try? FileManager.default.createDirectory(at: pendingURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoder.encode(spot).write(to: pendingURL, options: .atomic)
    }

    static func clearPending() {
        try? FileManager.default.removeItem(at: pendingURL)
    }

    /// Returns true if an interrupted park was recovered.
    @discardableResult
    func recoverPending() -> Bool {
        guard let data = try? Data(contentsOf: Self.pendingURL),
              var spot = try? Self.decoder.decode(Spot.self, from: data) else { return false }
        Self.clearPending()
        guard !spots.contains(where: { $0.id == spot.id }) else { return false }
        spot.name += " (recovered)"
        insert(spot)
        Log.write("recovered an interrupted park: \(spot.name)")
        return true
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Decodes a value if it can, and nil instead of throwing.
struct Lenient<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        value = try? T(from: decoder)
    }
}
