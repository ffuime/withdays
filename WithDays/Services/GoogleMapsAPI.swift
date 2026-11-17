import Foundation

/// Places API (New) and Routes API, called with the key entered in Settings.
enum GoogleMapsAPI {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let placeFields = [
        "id", "displayName", "shortFormattedAddress", "location", "primaryTypeDisplayName",
        "businessStatus", "currentOpeningHours.openNow", "currentOpeningHours.nextOpenTime",
        "currentOpeningHours.nextCloseTime",
    ]

    // MARK: Places

    /// Text search ranked by distance from `near`, so 「ラーメン屋」 gives the nearest ones first.
    static func search(_ query: String, near: GeoPoint, key: String) async throws -> [MapPlace] {
        var request = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(placeFields.map { "places.\($0)" }.joined(separator: ","), forHTTPHeaderField: "X-Goog-FieldMask")
        let body: [String: Any] = [
            "textQuery": query,
            "languageCode": "ja",
            "regionCode": "JP",
            "pageSize": 20,
            "rankPreference": "DISTANCE",
            "locationBias": [
                "circle": [
                    "center": ["latitude": near.latitude, "longitude": near.longitude],
                    "radius": 50000.0,
                ],
            ],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let response: SearchResponse = try await send(request)
        return (response.places ?? []).map(\.place)
            .sorted { $0.location.distance(to: near) < $1.location.distance(to: near) }
    }

    /// One place's details, for a place opened again from history or 「よく使う項目」.
    static func place(id: String, key: String) async throws -> MapPlace {
        var components = URLComponents(string: "https://places.googleapis.com/v1/places/")!
        components.path += id
        components.queryItems = [URLQueryItem(name: "languageCode", value: "ja"), URLQueryItem(name: "regionCode", value: "JP")]
        var request = URLRequest(url: components.url!)
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(placeFields.joined(separator: ","), forHTTPHeaderField: "X-Goog-FieldMask")
        let place: PlaceDTO = try await send(request)
        return place.place
    }

    // MARK: Routes

    static func route(from origin: GeoPoint, to destination: GeoPoint, mode: TravelMode, key: String) async throws -> RouteResult {
        var request = URLRequest(url: URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue([
            "routes.duration", "routes.distanceMeters", "routes.polyline.encodedPolyline",
            "routes.legs.steps.distanceMeters", "routes.legs.steps.staticDuration", "routes.legs.steps.travelMode",
            "routes.legs.steps.navigationInstruction", "routes.legs.steps.transitDetails",
        ].joined(separator: ","), forHTTPHeaderField: "X-Goog-FieldMask")
        func waypoint(_ point: GeoPoint) -> [String: Any] {
            ["location": ["latLng": ["latitude": point.latitude, "longitude": point.longitude]]]
        }
        var body: [String: Any] = [
            "origin": waypoint(origin),
            "destination": waypoint(destination),
            "travelMode": mode.apiValue,
            "languageCode": "ja",
            "regionCode": "JP",
            "units": "METRIC",
        ]
        if mode == .drive { body["routingPreference"] = "TRAFFIC_AWARE" }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let response: RoutesResponse = try await send(request)
        guard let route = response.routes?.first else {
            throw Failure(message: "\(mode.label)の経路が見つかりませんでした")
        }
        var steps: [RouteStep] = []
        for step in (route.legs ?? []).flatMap({ $0.steps ?? [] }) {
            steps.append(step.step(id: steps.count))
        }
        return RouteResult(
            durationSeconds: seconds(route.duration) ?? 0,
            distanceMeters: route.distanceMeters ?? 0,
            encodedPolyline: route.polyline?.encodedPolyline,
            steps: steps
        )
    }

    // MARK: Plumbing

    private static func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error?.message
            throw Failure(message: message.map { "Google: \($0)" } ?? "Googleに接続できませんでした（\(status)）")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    /// "123s" → 123.
    fileprivate static func seconds(_ text: String?) -> Int? {
        guard let text else { return nil }
        return Double(text.replacingOccurrences(of: "s", with: "")).map { Int($0.rounded()) }
    }

    fileprivate static func date(_ text: String?) -> Date? {
        guard let text else { return nil }
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text)
    }
}

// MARK: Response shapes

private struct ErrorResponse: Decodable {
    struct Body: Decodable { let message: String? }
    let error: Body?
}

private struct LocalizedText: Decodable {
    let text: String?
}

private struct LatLng: Decodable {
    let latitude: Double?
    let longitude: Double?
}

private struct SearchResponse: Decodable {
    let places: [PlaceDTO]?
}

private struct PlaceDTO: Decodable {
    struct Hours: Decodable {
        let openNow: Bool?
        let nextOpenTime: String?
        let nextCloseTime: String?
    }

    let id: String
    let displayName: LocalizedText?
    let shortFormattedAddress: String?
    let location: LatLng?
    let primaryTypeDisplayName: LocalizedText?
    let businessStatus: String?
    let currentOpeningHours: Hours?

    var place: MapPlace {
        MapPlace(
            id: id,
            name: displayName?.text ?? "名称不明",
            address: shortFormattedAddress,
            location: GeoPoint(latitude: location?.latitude ?? 0, longitude: location?.longitude ?? 0),
            category: primaryTypeDisplayName?.text,
            hours: currentOpeningHours.map {
                PlaceHours(
                    openNow: $0.openNow,
                    nextOpen: GoogleMapsAPI.date($0.nextOpenTime),
                    nextClose: GoogleMapsAPI.date($0.nextCloseTime)
                )
            },
            businessStatus: businessStatus
        )
    }
}

private struct RoutesResponse: Decodable {
    let routes: [RouteDTO]?
}

private struct RouteDTO: Decodable {
    struct Polyline: Decodable { let encodedPolyline: String? }
    struct Leg: Decodable { let steps: [StepDTO]? }

    let duration: String?
    let distanceMeters: Int?
    let polyline: Polyline?
    let legs: [Leg]?
}

private struct StepDTO: Decodable {
    struct Instruction: Decodable { let instructions: String? }

    struct Transit: Decodable {
        struct Stop: Decodable { let name: String? }
        struct StopDetails: Decodable {
            let arrivalStop: Stop?
            let departureStop: Stop?
            let arrivalTime: String?
            let departureTime: String?
        }
        struct Vehicle: Decodable { let name: LocalizedText? }
        struct Line: Decodable {
            let name: String?
            let nameShort: String?
            let color: String?
            let vehicle: Vehicle?
        }

        let stopDetails: StopDetails?
        let headsign: String?
        let transitLine: Line?
        let stopCount: Int?
    }

    let distanceMeters: Int?
    let staticDuration: String?
    let travelMode: String?
    let navigationInstruction: Instruction?
    let transitDetails: Transit?

    func step(id: Int) -> RouteStep {
        RouteStep(
            id: id,
            travelMode: travelMode ?? "",
            instruction: navigationInstruction?.instructions,
            distanceMeters: distanceMeters,
            durationSeconds: GoogleMapsAPI.seconds(staticDuration),
            transit: transitDetails.map { details in
                TransitStep(
                    lineName: details.transitLine?.name ?? details.transitLine?.nameShort ?? "路線",
                    vehicle: details.transitLine?.vehicle?.name?.text,
                    headsign: details.headsign,
                    departureStop: details.stopDetails?.departureStop?.name,
                    arrivalStop: details.stopDetails?.arrivalStop?.name,
                    departureTime: GoogleMapsAPI.date(details.stopDetails?.departureTime),
                    arrivalTime: GoogleMapsAPI.date(details.stopDetails?.arrivalTime),
                    stopCount: details.stopCount,
                    color: details.transitLine?.color
                )
            }
        )
    }
}
