import GoogleMaps
import SwiftUI

/// Something for the map to do once: move to a point, or fit a set of points.
struct MapCameraCommand: Equatable {
    enum Kind: Equatable {
        /// A nil zoom keeps the current one.
        case center(GeoPoint, zoom: Float?)
        case fit([GeoPoint])
    }

    let id = UUID()
    let kind: Kind
}

/// A route drawn on the map.
struct MapRouteOverlay: Equatable {
    var encodedPolyline: String?
    var origin: GeoPoint
    var destination: GeoPoint
}

/// Google's map, with the results as markers and the route as a line.
/// The camera's target (the middle of the area left between the search bar and the panel) is the 「照準地」.
struct GoogleMapView: UIViewRepresentable {
    var places: [MapPlace]
    var selectedID: String?
    var route: MapRouteOverlay?
    var userLocation: GeoPoint?
    var padding: UIEdgeInsets
    var command: MapCameraCommand?
    var initialCamera: GeoPoint
    var initialZoom: Float

    /// The camera moved: its target, and whether the current location is off the middle.
    var onCameraChange: (GeoPoint, Bool) -> Void
    var onCameraIdle: (GeoPoint, Float) -> Void
    var onLongPress: (GeoPoint) -> Void
    var onMarkerTap: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(target: initialCamera.coordinate, zoom: initialZoom)
        let map = GMSMapView(options: options)
        map.delegate = context.coordinator
        map.isMyLocationEnabled = true
        map.settings.myLocationButton = false
        map.settings.compassButton = true
        map.settings.indoorPicker = false
        map.padding = padding
        return map
    }

    func updateUIView(_ map: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        if map.padding != padding { map.padding = padding }
        coordinator.syncMarkers(on: map)
        coordinator.syncRoute(on: map)
        if let command, command.id != coordinator.lastCommandID {
            coordinator.lastCommandID = command.id
            coordinator.perform(command, on: map)
        }
        // The blue dot may have moved under a still camera; reported after this update, not during it.
        if userLocation != coordinator.reportedUser {
            coordinator.reportedUser = userLocation
            Task { @MainActor [weak map] in
                guard let map else { return }
                coordinator.reportCamera(of: map)
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapView
        var lastCommandID: UUID?
        private var markers: [String: GMSMarker] = [:]
        private var markerSelection: String?
        private var drawnRoute: MapRouteOverlay?
        private var routeShapes: [GMSOverlay] = []
        var reportedUser: GeoPoint?

        init(parent: GoogleMapView) {
            self.parent = parent
        }

        // MARK: Markers

        func syncMarkers(on map: GMSMapView) {
            let wanted = Dictionary(parent.places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (id, marker) in markers where wanted[id] == nil {
                marker.map = nil
                markers[id] = nil
            }
            for (id, place) in wanted {
                let marker: GMSMarker
                if let existing = markers[id] {
                    marker = existing
                } else {
                    marker = GMSMarker(position: place.location.coordinate)
                    marker.userData = id
                    marker.map = map
                    markers[id] = marker
                }
                marker.position = place.location.coordinate
                marker.title = place.name
                if marker.icon == nil || markerSelection != parent.selectedID {
                    let selected = id == parent.selectedID
                    marker.icon = GMSMarker.markerImage(with: selected ? UIColor(Color.brand) : UIColor.systemRed)
                    marker.zIndex = selected ? 1 : 0
                }
            }
            markerSelection = parent.selectedID
        }

        // MARK: Route

        func syncRoute(on map: GMSMapView) {
            guard parent.route != drawnRoute else { return }
            drawnRoute = parent.route
            for shape in routeShapes { shape.map = nil }
            routeShapes = []
            guard let route = parent.route else { return }
            if let encoded = route.encodedPolyline, let path = GMSPath(fromEncodedPath: encoded) {
                let outline = GMSPolyline(path: path)
                outline.strokeWidth = 9
                outline.strokeColor = UIColor.white.withAlphaComponent(0.9)
                outline.map = map
                let line = GMSPolyline(path: path)
                line.strokeWidth = 6
                line.strokeColor = UIColor(Color.brand)
                line.zIndex = 1
                line.map = map
                routeShapes += [outline, line]
            }
            let start = GMSMarker(position: route.origin.coordinate)
            start.icon = GMSMarker.markerImage(with: .systemGreen)
            start.map = map
            let end = GMSMarker(position: route.destination.coordinate)
            end.icon = GMSMarker.markerImage(with: .systemRed)
            end.zIndex = 2
            end.map = map
            routeShapes += [start, end]
        }

        // MARK: Camera

        func perform(_ command: MapCameraCommand, on map: GMSMapView) {
            switch command.kind {
            case .center(let point, let zoom):
                map.animate(with: GMSCameraUpdate.setTarget(point.coordinate, zoom: zoom ?? map.camera.zoom))
            case .fit(let points):
                guard let first = points.first else { return }
                if points.count == 1 {
                    map.animate(with: GMSCameraUpdate.setTarget(first.coordinate, zoom: max(map.camera.zoom, 15)))
                    return
                }
                var bounds = GMSCoordinateBounds(coordinate: first.coordinate, coordinate: first.coordinate)
                for point in points.dropFirst() { bounds = bounds.includingCoordinate(point.coordinate) }
                map.animate(with: GMSCameraUpdate.fit(bounds, withPadding: 48))
            }
        }

        /// Reports the target, and whether the blue dot is more than a few points off the middle.
        func reportCamera(of map: GMSMapView) {
            let target = GeoPoint(map.camera.target)
            var away = false
            if let user = parent.userLocation {
                let dot = map.projection.point(for: user.coordinate)
                let padding = map.padding
                let middle = CGPoint(
                    x: (padding.left + map.bounds.width - padding.right) / 2,
                    y: (padding.top + map.bounds.height - padding.bottom) / 2
                )
                away = hypot(dot.x - middle.x, dot.y - middle.y) > 40
            }
            parent.onCameraChange(target, away)
        }

        // MARK: GMSMapViewDelegate

        nonisolated func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
            MainActor.assumeIsolated { reportCamera(of: mapView) }
        }

        nonisolated func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            MainActor.assumeIsolated {
                reportCamera(of: mapView)
                parent.onCameraIdle(GeoPoint(position.target), position.zoom)
            }
        }

        nonisolated func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
            MainActor.assumeIsolated { parent.onLongPress(GeoPoint(coordinate)) }
        }

        nonisolated func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            MainActor.assumeIsolated {
                if let id = marker.userData as? String { parent.onMarkerTap(id) }
            }
            // Keep Google's info window closed; the panel shows the place.
            return true
        }
    }
}
