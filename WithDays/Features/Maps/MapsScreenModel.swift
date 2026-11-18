import Foundation
import Observation

/// How far the bottom panel is pulled up.
enum PanelDetent {
    /// Only the header: the search word, or the route's summary.
    case collapsed
    case half
    case large
}

/// A route being shown: its ends, the travel mode and Apple's answer.
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
    /// The map view's own center and scale, to put the camera back where it was.
    var cameraCenter: GeoPoint
    var meters: Double
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
    private var hoursTask: Task<Void, Never>?
    private var routeTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: SettingsKey.mapsLastLatitude) != nil,
           defaults.object(forKey: SettingsKey.mapsCameraLatitude) != nil {
            aim = GeoPoint(
                latitude: defaults.double(forKey: SettingsKey.mapsLastLatitude),
                longitude: defaults.double(forKey: SettingsKey.mapsLastLongitude)
            )
            cameraCenter = GeoPoint(
                latitude: defaults.double(forKey: SettingsKey.mapsCameraLatitude),
                longitude: defaults.double(forKey: SettingsKey.mapsCameraLongitude)
            )
            let meters = defaults.double(forKey: SettingsKey.mapsLastSpan)
            self.meters = meters > 0 ? meters : 2000
        } else {
            // Tokyo Station until the current location comes in.
            let tokyo = GeoPoint(latitude: 35.6812, longitude: 139.7671)
            aim = tokyo
            cameraCenter = tokyo
            meters = 2000
        }
    }

    var showingResults: Bool { resultsTitle != nil }

    // MARK: Camera

    func cameraStopped(_ stop: MapCameraStop) {
        aim = stop.aim
        cameraCenter = stop.center
        meters = stop.meters
        let defaults = UserDefaults.standard
        defaults.set(stop.aim.latitude, forKey: SettingsKey.mapsLastLatitude)
        defaults.set(stop.aim.longitude, forKey: SettingsKey.mapsLastLongitude)
        defaults.set(stop.center.latitude, forKey: SettingsKey.mapsCameraLatitude)
        defaults.set(stop.center.longitude, forKey: SettingsKey.mapsCameraLongitude)
        defaults.set(stop.meters, forKey: SettingsKey.mapsLastSpan)
    }

    func userMoved(to point: GeoPoint) {
        userLocation = point
        // The first fix moves the map there once; after that the camera is the user's.
        if !hasCenteredOnUser {
            hasCenteredOnUser = true
            command = MapCameraCommand(kind: .center(point, meters: min(meters, 2000)))
        }
    }

    func backToUser() {
        guard let userLocation else {
            errorMessage = "現在地を取得できていません。iPhoneの設定で位置情報の利用を許可してください"
            return
        }
        command = MapCameraCommand(kind: .center(userLocation, meters: nil))
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
        hoursTask?.cancel()
        searchTask = Task {
            do {
                let found = try await AppleMapsService.search(query, near: near)
                guard !Task.isCancelled else { return }
                results = found
                if found.isEmpty { resultsError = "「\(query)」は見つかりませんでした" }
                loadHours()
            } catch {
                guard !Task.isCancelled else { return }
                resultsError = error.localizedDescription
            }
            searching = false
        }
    }

    /// Shows one place (from history or 「よく使う項目」) as the only result, with its opening hours when it's a place on the map.
    func show(_ place: MapPlace, store: MapsStore) {
        closeRoute()
        resultsTitle = place.name
        results = [place]
        selectedID = place.id
        resultsError = nil
        resultsDetent = .collapsed
        searching = false
        command = MapCameraCommand(kind: .center(place.location, meters: min(meters, 1200)))
        store.recordPlace(place)
        searchTask?.cancel()
        loadHours()
    }

    /// Fills in the results' opening hours from OpenStreetMap, after they show.
    private func loadHours() {
        hoursTask?.cancel()
        let places = results
        guard places.contains(where: { $0.appleID != nil }) else { return }
        hoursTask = Task {
            let hours = await OpenStreetMapHours.hours(for: places)
            guard !Task.isCancelled else { return }
            for index in results.indices where results[index].appleID != nil {
                results[index].hours = hours[results[index].id]
                results[index].hoursChecked = true
            }
        }
    }

    func select(_ place: MapPlace, store: MapsStore) {
        selectedID = place.id
        store.recordPlace(place)
        command = MapCameraCommand(kind: .center(place.location, meters: nil))
    }

    func closeResults() {
        searchTask?.cancel()
        hoursTask?.cancel()
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
                let result = try await AppleMapsService.route(from: origin, to: destination, mode: current.mode)
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
