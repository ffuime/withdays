import MapKit
import SwiftUI

/// Something for the map to do once: move to a point, or fit a set of points.
struct MapCameraCommand: Equatable {
    enum Kind: Equatable {
        /// `meters` is how much ground the free part of the map shows top to bottom; nil keeps the current scale.
        case center(GeoPoint, meters: Double?)
        case fit([GeoPoint])
    }

    let id = UUID()
    let kind: Kind
}

/// A route drawn on the map.
struct MapRouteOverlay: Equatable {
    var path: [GeoPoint]
    var origin: GeoPoint
    var destination: GeoPoint
}

/// Where the camera stopped: the 「照準地」 (the middle of the part left between the search bar and the panel),
/// the map view's own center (to put the camera back next time) and the scale.
struct MapCameraStop {
    var aim: GeoPoint
    var center: GeoPoint
    var meters: Double
}

/// Apple's map, with the results as pins and the route as a line.
struct AppleMapView: UIViewRepresentable {
    var places: [MapPlace]
    var selectedID: String?
    var route: MapRouteOverlay?
    var userLocation: GeoPoint?
    /// The parts of the map covered by the search bar (top) and the panel (bottom).
    var padding: UIEdgeInsets
    var command: MapCameraCommand?
    var initialCenter: GeoPoint
    var initialMeters: Double

    /// The camera moved: its aim, and whether the current location is off the middle.
    var onCameraChange: (GeoPoint, Bool) -> Void
    var onCameraIdle: (MapCameraStop) -> Void
    var onLongPress: (GeoPoint) -> Void
    var onMarkerTap: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> MKMapView {
        let map = MKMapView()
        map.delegate = context.coordinator
        map.showsUserLocation = true
        map.showsCompass = false
        map.pointOfInterestFilter = .includingAll
        map.setRegion(
            MKCoordinateRegion(center: initialCenter.coordinate, latitudinalMeters: initialMeters, longitudinalMeters: initialMeters),
            animated: false
        )
        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPressed(_:)))
        press.minimumPressDuration = 0.5
        map.addGestureRecognizer(press)
        return map
    }

    func updateUIView(_ map: MKMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        coordinator.syncMarkers(on: map)
        coordinator.syncRoute(on: map)
        if let command, command.id != coordinator.lastCommandID {
            coordinator.lastCommandID = command.id
            // After this update, once the map has its size.
            Task { @MainActor [weak map] in
                guard let map else { return }
                coordinator.perform(command, on: map)
            }
        }
        // The blue dot may have moved under a still camera; reported after this update, not during it.
        // So does the middle when the panel's height changes.
        if userLocation != coordinator.reportedUser || padding != coordinator.reportedPadding {
            let paddingChanged = padding != coordinator.reportedPadding
            coordinator.reportedUser = userLocation
            coordinator.reportedPadding = padding
            Task { @MainActor [weak map] in
                guard let map else { return }
                coordinator.reportCamera(of: map)
                if paddingChanged { coordinator.reportStop(of: map) }
            }
        }
    }

    final class PinAnnotation: NSObject, MKAnnotation {
        enum Kind {
            case place, origin, destination
        }

        let id: String
        let kind: Kind
        @objc dynamic var coordinate: CLLocationCoordinate2D
        var title: String?
        var selected = false

        init(id: String, kind: Kind, coordinate: CLLocationCoordinate2D, title: String?) {
            self.id = id
            self.kind = kind
            self.coordinate = coordinate
            self.title = title
        }
    }

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: AppleMapView
        var lastCommandID: UUID?
        var reportedUser: GeoPoint?
        var reportedPadding: UIEdgeInsets?
        private var pins: [String: PinAnnotation] = [:]
        private var drawnRoute: MapRouteOverlay?
        private var routeShapes: [MKAnnotation] = []
        private var routeLine: MKPolyline?

        init(parent: AppleMapView) {
            self.parent = parent
        }

        // MARK: Pins

        func syncMarkers(on map: MKMapView) {
            let wanted = Dictionary(parent.places.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for (id, pin) in pins where wanted[id] == nil {
                map.removeAnnotation(pin)
                pins[id] = nil
            }
            for (id, place) in wanted {
                let selected = id == parent.selectedID
                if let pin = pins[id] {
                    pin.coordinate = place.location.coordinate
                    if pin.selected != selected {
                        pin.selected = selected
                        if let view = map.view(for: pin) as? MKMarkerAnnotationView { style(view, for: pin) }
                    }
                } else {
                    let pin = PinAnnotation(id: id, kind: .place, coordinate: place.location.coordinate, title: place.name)
                    pin.selected = selected
                    pins[id] = pin
                    map.addAnnotation(pin)
                }
            }
        }

        private func style(_ view: MKMarkerAnnotationView, for pin: PinAnnotation) {
            switch pin.kind {
            case .place:
                view.markerTintColor = pin.selected ? UIColor(Color.brand) : .systemRed
                view.glyphImage = nil
                view.zPriority = pin.selected ? .max : .defaultUnselected
            case .origin:
                view.markerTintColor = .systemGreen
                view.glyphImage = UIImage(systemName: "figure.walk")
                view.zPriority = .max
            case .destination:
                view.markerTintColor = .systemRed
                view.glyphImage = UIImage(systemName: "flag.fill")
                view.zPriority = .max
            }
            view.displayPriority = .required
            view.titleVisibility = pin.selected || pin.kind != .place ? .visible : .adaptive
        }

        // MARK: Route

        func syncRoute(on map: MKMapView) {
            guard parent.route != drawnRoute else { return }
            drawnRoute = parent.route
            map.removeAnnotations(routeShapes)
            routeShapes = []
            if let routeLine { map.removeOverlay(routeLine) }
            routeLine = nil
            guard let route = parent.route else { return }
            if route.path.count > 1 {
                let coordinates = route.path.map(\.coordinate)
                let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
                map.addOverlay(line, level: .aboveRoads)
                routeLine = line
            }
            let start = PinAnnotation(id: "route-origin", kind: .origin, coordinate: route.origin.coordinate, title: nil)
            let end = PinAnnotation(id: "route-destination", kind: .destination, coordinate: route.destination.coordinate, title: nil)
            routeShapes = [start, end]
            map.addAnnotations(routeShapes)
        }

        // MARK: Camera

        /// The middle of the part of the map that isn't covered.
        private func middle(of map: MKMapView) -> CGPoint {
            let padding = parent.padding
            return CGPoint(x: map.bounds.midX, y: (padding.top + map.bounds.height - padding.bottom) / 2)
        }

        func perform(_ command: MapCameraCommand, on map: MKMapView) {
            guard map.bounds.width > 0, map.bounds.height > 0 else { return }
            let padding = parent.padding
            switch command.kind {
            case .center(let point, let meters):
                let freeHeight = max(map.bounds.height - padding.top - padding.bottom, 1)
                // Map points per screen point, now or at the asked scale.
                var scale = map.visibleMapRect.size.width / Double(map.bounds.width)
                if let meters {
                    scale = meters * MKMapPointsPerMeterAtLatitude(point.latitude) / Double(freeHeight)
                }
                let size = MKMapSize(width: Double(map.bounds.width) * scale, height: Double(freeHeight) * scale)
                let mid = MKMapPoint(point.coordinate)
                let rect = MKMapRect(x: mid.x - size.width / 2, y: mid.y - size.height / 2, width: size.width, height: size.height)
                map.setVisibleMapRect(rect, edgePadding: UIEdgeInsets(top: padding.top, left: 0, bottom: padding.bottom, right: 0), animated: true)
            case .fit(let points):
                guard let first = points.first else { return }
                var rect = MKMapRect(origin: MKMapPoint(first.coordinate), size: MKMapSize(width: 0, height: 0))
                for point in points.dropFirst() {
                    rect = rect.union(MKMapRect(origin: MKMapPoint(point.coordinate), size: MKMapSize(width: 0, height: 0)))
                }
                if let routeLine { rect = rect.union(routeLine.boundingMapRect) }
                if rect.size.width < 1, rect.size.height < 1 {
                    perform(MapCameraCommand(kind: .center(first, meters: 1200)), on: map)
                    return
                }
                map.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(top: padding.top + 48, left: 48, bottom: padding.bottom + 48, right: 48),
                    animated: true
                )
            }
        }

        /// Reports the aim, and whether the blue dot is more than a few points off the middle.
        func reportCamera(of map: MKMapView) {
            guard map.bounds.height > 0 else { return }
            let mid = middle(of: map)
            let aim = GeoPoint(map.convert(mid, toCoordinateFrom: map))
            var away = false
            if let user = parent.userLocation {
                let dot = map.convert(user.coordinate, toPointTo: map)
                away = hypot(dot.x - mid.x, dot.y - mid.y) > 40
            }
            parent.onCameraChange(aim, away)
        }

        func reportStop(of map: MKMapView) {
            guard map.bounds.height > 0 else { return }
            let padding = parent.padding
            let mid = middle(of: map)
            let freeHeight = max(map.bounds.height - padding.top - padding.bottom, 1)
            let scale = map.visibleMapRect.size.width / Double(map.bounds.width)
            let aim = map.convert(mid, toCoordinateFrom: map)
            let meters = Double(freeHeight) * scale / MKMapPointsPerMeterAtLatitude(aim.latitude)
            parent.onCameraIdle(MapCameraStop(aim: GeoPoint(aim), center: GeoPoint(map.centerCoordinate), meters: meters))
        }

        @objc func longPressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, let map = recognizer.view as? MKMapView else { return }
            let coordinate = map.convert(recognizer.location(in: map), toCoordinateFrom: map)
            parent.onLongPress(GeoPoint(coordinate))
        }

        // MARK: MKMapViewDelegate

        func mapViewDidChangeVisibleRegion(_ mapView: MKMapView) {
            reportCamera(of: mapView)
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            reportCamera(of: mapView)
            reportStop(of: mapView)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let pin = annotation as? PinAnnotation else { return nil }
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "pin") as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: pin, reuseIdentifier: "pin")
            view.annotation = pin
            view.canShowCallout = false
            style(view, for: pin)
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let pin = view.annotation as? PinAnnotation else { return }
            // The panel shows the place; the map keeps no selection of its own.
            mapView.deselectAnnotation(pin, animated: false)
            if pin.kind == .place { parent.onMarkerTap(pin.id) }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let line = overlay as? MKPolyline else { return MKOverlayRenderer(overlay: overlay) }
            let renderer = MKPolylineRenderer(polyline: line)
            renderer.strokeColor = UIColor(Color.brand)
            renderer.lineWidth = 6
            renderer.lineCap = .round
            renderer.lineJoin = .round
            return renderer
        }
    }
}
