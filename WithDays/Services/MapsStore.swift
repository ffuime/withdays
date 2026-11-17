import Foundation
import GoogleMaps
import Observation

/// Maps' 「よく使う項目」 and search history, kept in UserDefaults.
@Observable
final class MapsStore {
    static let historyLimit = 30

    private(set) var saved: [SavedPlace] = []
    private(set) var history: [MapsHistoryEntry] = []

    init() {
        saved = Self.load([SavedPlace].self, key: SettingsKey.mapsSaved) ?? []
        history = Self.load([MapsHistoryEntry].self, key: SettingsKey.mapsHistory) ?? []
    }

    /// The key entered in Settings, trimmed; empty when there's none.
    static var apiKey: String {
        (UserDefaults.standard.string(forKey: SettingsKey.mapsAPIKey) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Saved places

    func save(_ place: SavedPlace) {
        saved.append(place)
        persistSaved()
    }

    func rename(_ id: SavedPlace.ID, to name: String) {
        guard let index = saved.firstIndex(where: { $0.id == id }), !name.isEmpty else { return }
        saved[index].name = name
        persistSaved()
    }

    func deleteSaved(_ id: SavedPlace.ID) {
        saved.removeAll { $0.id == id }
        persistSaved()
    }

    func isSaved(_ place: MapPlace) -> Bool {
        saved.contains { saved in
            if let googleID = place.googleID { return saved.placeID == googleID }
            return saved.asPlace.id == place.id
        }
    }

    // MARK: History

    func recordQuery(_ query: String) {
        record(MapsHistoryEntry(kind: .query, text: query)) { $0.kind == .query && $0.text == query }
    }

    func recordPlace(_ place: MapPlace) {
        let entry = MapsHistoryEntry(
            kind: .place, text: place.name, placeID: place.googleID, address: place.address, location: place.location
        )
        record(entry) { $0.kind == .place && ($0.placeID != nil ? $0.placeID == place.googleID : $0.text == place.name) }
    }

    func deleteHistory(_ id: MapsHistoryEntry.ID) {
        history.removeAll { $0.id == id }
        persistHistory()
    }

    func clearHistory() {
        history.removeAll()
        persistHistory()
    }

    /// Newest first; an entry already there moves to the top.
    private func record(_ entry: MapsHistoryEntry, sameAs: (MapsHistoryEntry) -> Bool) {
        history.removeAll(where: sameAs)
        history.insert(entry, at: 0)
        if history.count > Self.historyLimit { history.removeLast(history.count - Self.historyLimit) }
        persistHistory()
    }

    // MARK: Storage

    private func persistSaved() {
        UserDefaults.standard.set(try? JSONEncoder().encode(saved), forKey: SettingsKey.mapsSaved)
    }

    private func persistHistory() {
        UserDefaults.standard.set(try? JSONEncoder().encode(history), forKey: SettingsKey.mapsHistory)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// The Maps SDK takes its key once per launch, before the first map.
enum GoogleMapsSetup {
    @MainActor private static var providedKey: String?

    enum State {
        /// No key in Settings yet.
        case missing
        case ready
        /// The key was changed after the map started; the map keeps the old one until the next launch.
        case needsRelaunch
    }

    @MainActor
    static func prepare() -> State {
        let key = MapsStore.apiKey
        guard !key.isEmpty else { return providedKey == nil ? .missing : .needsRelaunch }
        if let providedKey { return providedKey == key ? .ready : .needsRelaunch }
        GMSServices.provideAPIKey(key)
        providedKey = key
        return .ready
    }
}
