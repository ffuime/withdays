import CoreLocation
import SwiftUI

/// A latitude / longitude pair that can be saved.
struct GeoPoint: Codable, Hashable {
    var latitude: Double
    var longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Meters along the ground.
    func distance(to other: GeoPoint) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }
}

/// When a place opens and closes next, worked out from OpenStreetMap's opening_hours.
struct PlaceHours: Hashable {
    var openNow: Bool
    var nextOpen: Date?
    /// Nil while open around the clock.
    var nextClose: Date?
}

/// A place found with Apple's map search, or a saved point shown like one.
struct MapPlace: Identifiable, Hashable {
    /// Apple's place identifier, or "saved-<uuid>" / "point-<uuid>" for a point that isn't a place on the map.
    let id: String
    var name: String
    var address: String?
    var location: GeoPoint
    var category: String?
    var hours: PlaceHours?
    /// OpenStreetMap was asked about this place's hours (whether or not it knew them).
    var hoursChecked = false

    /// Apple's place identifier, when this is a place on the map.
    var appleID: String? {
        id.hasPrefix("saved-") || id.hasPrefix("point-") ? nil : id
    }
}

// MARK: Open / closed

extension MapPlace {
    /// 「営業中」 and so on, with its color, and the time it closes or opens again.
    struct OpenStatus {
        let label: String
        let color: Color
        let detail: String?
    }

    /// Nil for a point that isn't a place on the map.
    var openStatus: OpenStatus? {
        guard appleID != nil else { return nil }
        guard let hours else {
            return hoursChecked
                ? OpenStatus(label: "営業時間の情報なし", color: .secondary, detail: nil)
                : OpenStatus(label: "営業時間を確認中…", color: .secondary, detail: nil)
        }
        if hours.openNow {
            guard let close = hours.nextClose else {
                return OpenStatus(label: "営業中", color: .green, detail: "24時間営業")
            }
            return OpenStatus(label: "営業中", color: .green, detail: "\(MapsFormat.time(close)) に閉店")
        }
        guard let open = hours.nextOpen else {
            return OpenStatus(label: "営業時間外", color: .red, detail: nil)
        }
        return OpenStatus(label: "営業時間外", color: .red, detail: "\(MapsFormat.time(open)) に営業開始")
    }
}

// MARK: Saved places and history

/// A place in 「よく使う項目」: from a search result or a long press on the map.
struct SavedPlace: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var location: GeoPoint
    var placeID: String?
    var address: String?

    var asPlace: MapPlace {
        MapPlace(id: placeID ?? "saved-\(id.uuidString)", name: name, address: address, location: location)
    }
}

/// A search word, or a place opened from the results.
struct MapsHistoryEntry: Codable, Identifiable, Hashable {
    enum Kind: String, Codable {
        case query, place
    }

    var id = UUID()
    var kind: Kind
    /// The search word, or the place's name.
    var text: String
    var placeID: String?
    var address: String?
    var location: GeoPoint?
    var date = Date()
}

// MARK: Routes

enum TravelMode: String, CaseIterable, Identifiable, Codable {
    case walk, drive, transit, bicycle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .walk: "徒歩"
        case .drive: "車"
        case .transit: "電車・バス"
        case .bicycle: "自転車"
        }
    }

    var symbol: String {
        switch self {
        case .walk: "figure.walk"
        case .drive: "car.fill"
        case .transit: "tram.fill"
        case .bicycle: "bicycle"
        }
    }
}

/// Where a route starts or ends.
enum RouteEndpoint: Hashable {
    case currentLocation
    case point(name: String, location: GeoPoint)

    var name: String {
        switch self {
        case .currentLocation: "現在地"
        case .point(let name, _): name
        }
    }

    var isCurrentLocation: Bool {
        if case .currentLocation = self { return true }
        return false
    }
}

struct RouteResult: Hashable {
    var durationSeconds: Int
    var distanceMeters: Int
    /// The line to draw; empty for 電車・バス, which Apple only answers with a time.
    var path: [GeoPoint]
    var steps: [RouteStep]
    var arrival: Date?
}

struct RouteStep: Identifiable, Hashable {
    let id: Int
    var instruction: String
    var distanceMeters: Int?
}

// MARK: Formatting

enum MapsFormat {
    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "H:mm"
        return formatter
    }()

    private static let day: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d(E)"
        return formatter
    }()

    /// 「22:00」, 「明日 11:00」 or 「11/20(木) 11:00」.
    static func time(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return clock.string(from: date) }
        if calendar.isDateInTomorrow(date) { return "明日 " + clock.string(from: date) }
        return day.string(from: date) + " " + clock.string(from: date)
    }

    static func clockTime(_ date: Date) -> String {
        clock.string(from: date)
    }

    /// 「350 m」 or 「1.2 km」.
    static func distance(_ meters: Double) -> String {
        if meters < 1000 { return "\(Int((meters / 10).rounded()) * 10) m" }
        if meters < 10000 { return String(format: "%.1f km", meters / 1000) }
        return "\(Int((meters / 1000).rounded())) km"
    }

    /// 「8分」 or 「1時間5分」.
    static func duration(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60).rounded()))
        if minutes < 60 { return "\(minutes)分" }
        let rest = minutes % 60
        return rest == 0 ? "\(minutes / 60)時間" : "\(minutes / 60)時間\(rest)分"
    }
}
