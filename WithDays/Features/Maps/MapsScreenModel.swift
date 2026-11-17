import Foundation
import Observation

/// How far the bottom panel is pulled up.
enum PanelDetent {
    /// Only the header: the search word, or the route's summary.
    case collapsed
    case half
    case large
}

/// A route being shown: its ends, the travel mode and Google's answer.
struct RouteState {
    var origin: RouteEndpoint
    var destination: RouteEndpoint
    var mode: TravelMode
    var originPoint: GeoPoint?
    var destinationPoint: GeoPoint?
    var result: RouteResult?
    var loading = false
    var error: String?
}

/// Maps' screen state: the aim, the results, the route and what the camera should do next.
@MainActor
@Observable
final class MapsScreenModel {
    /// The camera's target when it last stopped: the 「照準地」.
    var aim: GeoPoint
    var zoom: Float
    var userLocation: GeoPoint?
    /// The current location is off the middle of the map, so 「現在地に戻す」 shows.
    var awayFromUser = false
    var command: MapCameraCommand?

    /// The word searched for (or the place opened) that the results panel is showing.
    var resultsTitle: String?
    var results: [MapPlace] = []
    var searching = false
    var resultsError: String?
    var selectedID: String?
    var resultsDetent: PanelDetent = .half

    var route: RouteState?
    var routeDetent: PanelDetent = .half

    var errorMessage: String?

    private var hasCenteredOnUser = false
    private var searchTask: Task<Void, Never>?
    private var routeTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: SettingsKey.mapsLastLatitude) != nil {
            aim = GeoPoint(
                latitude: defaults.double(forKey: SettingsKey.mapsLastLatitude),
                longitude: defaults.double(forKey: SettingsKey.mapsLastLongitude)
            )
            let zoom = defaults.float(forKey: SettingsKey.mapsLastZoom)
            self.zoom = zoom > 0 ? zoom : 15
        } else {
            // Tokyo Station until the current location comes in.
            aim = GeoPoint(latitude: 35.6812, longitude: 139.7671)
            zoom = 15
        }
    }

    var showingResults: Bool { resultsTitle != nil }

    // MARK: Camera

    func cameraStopped(at target: GeoPoint, zoom: Float) {
        aim = target
        self.zoom = zoom
        let defaults = UserDefaults.standard
        defaults.set(target.latitude, forKey: SettingsKey.mapsLastLatitude)
        defaults.set(target.longitude, forKey: SettingsKey.mapsLastLongitude)
        defaults.set(zoom, forKey: SettingsKey.mapsLastZoom)
    }

    func userMoved(to point: GeoPoint) {
        userLocation = point
        // The first fix moves the map there once; after that the camera is the user's.
        if !hasCenteredOnUser {
            hasCenteredOnUser = true
            command = MapCameraCommand(kind: .center(point, zoom: max(zoom, 15)))
        }
    }

    func backToUser() {
        guard let userLocation else {
            errorMessage = "現在地を取得できていません。iPhoneの設定で位置情報の利用を許可してください"
            return
        }
        command = MapCameraCommand(kind: .center(userLocation, zoom: nil))
    }

    // MARK: Search

    func search(_ query: String, store: MapsStore) {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        store.recordQuery(query)
        closeRoute()
        resultsTitle = query
        results = []
        selectedID = nil
        resultsError = nil
        resultsDetent = .half
        searching = true
        let near = aim
        searchTask?.cancel()
        searchTask = Task {
            do {
                let found = try await GoogleMapsAPI.search(query, near: near, key: MapsStore.apiKey)
                guard !Task.isCancelled else { return }
                results = found
                if found.isEmpty { resultsError = "「\(query)」は見つかりませんでした" }
            } catch {
                guard !Task.isCancelled else { return }
                resultsError = error.localizedDescription
            }
            searching = false
        }
    }

    /// Shows one place (from history or 「よく使う項目」) as the only result, with fresh opening hours when it's a Google place.
    func show(_ place: MapPlace, store: MapsStore) {
        closeRoute()
        resultsTitle = place.name
        results = [place]
        selectedID = place.id
        resultsError = nil
        resultsDetent = .collapsed
        searching = false
        command = MapCameraCommand(kind: .center(place.location, zoom: max(zoom, 16)))
        store.recordPlace(place)
        guard let googleID = place.googleID else { return }
        searchTask?.cancel()
        searchTask = Task {
            guard let fresh = try? await GoogleMapsAPI.place(id: googleID, key: MapsStore.apiKey),
                  !Task.isCancelled, results.first?.id == place.id else { return }
            results = [fresh]
        }
    }

    func select(_ place: MapPlace, store: MapsStore) {
        selectedID = place.id
        store.recordPlace(place)
        command = MapCameraCommand(kind: .center(place.location, zoom: nil))
    }

    func closeResults() {
        searchTask?.cancel()
        resultsTitle = nil
        results = []
        selectedID = nil
        resultsError = nil
        searching = false
    }

    // MARK: Route

    func startRoute(from origin: RouteEndpoint, to destination: RouteEndpoint, mode: TravelMode? = nil) {
        route = RouteState(origin: origin, destination: destination, mode: mode ?? route?.mode ?? .walk)
        routeDetent = .half
        loadRoute()
    }

    func changeMode(_ mode: TravelMode) {
        guard route != nil, route?.mode != mode else { return }
        route?.mode = mode
        loadRoute()
    }

    func closeRoute() {
        routeTask?.cancel()
        route = nil
    }

    private func loadRoute() {
        guard let current = route else { return }
        route?.loading = true
        route?.error = nil
        route?.result = nil
        routeTask?.cancel()
        routeTask = Task {
            do {
                let origin = try await point(for: current.origin)
                let destination = try await point(for: current.destination)
                guard !Task.isCancelled else { return }
                route?.originPoint = origin
                route?.destinationPoint = destination
                let result = try await GoogleMapsAPI.route(from: origin, to: destination, mode: current.mode, key: MapsStore.apiKey)
                guard !Task.isCancelled else { return }
                route?.result = result
                route?.loading = false
                command = MapCameraCommand(kind: .fit([origin, destination]))
            } catch {
                guard !Task.isCancelled else { return }
                route?.error = error.localizedDescription
                route?.loading = false
            }
        }
    }

    private func point(for endpoint: RouteEndpoint) async throws -> GeoPoint {
        switch endpoint {
        case .point(_, let location):
            return location
        case .currentLocation:
            if let userLocation { return userLocation }
            let coordinate = try await Locator.current()
            return GeoPoint(coordinate)
        }
    }
}
