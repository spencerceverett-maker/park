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

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        spots = (try? decoder.decode([Spot].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(spots).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Park: failed to save spots: \(error)")
        }
    }
}
