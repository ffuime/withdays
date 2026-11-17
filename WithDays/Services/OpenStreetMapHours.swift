import Foundation

/// Opening hours from OpenStreetMap (free, through the public Overpass API), matched to Apple's places by name and position.
enum OpenStreetMapHours {
    /// How far an OpenStreetMap entry may be from Apple's pin and still be the same place.
    private static let matchRadius = 90.0

    /// The hours of each place OpenStreetMap knows, by place ID. Places it doesn't know are left out.
    static func hours(for places: [MapPlace], at now: Date = Date()) async -> [String: PlaceHours] {
        let wanted = places.filter { $0.appleID != nil }.prefix(25)
        guard !wanted.isEmpty else { return [:] }
        let arounds = wanted.map { place in
            String(format: "nwr(around:%.0f,%.6f,%.6f)[\"opening_hours\"];", matchRadius, place.location.latitude, place.location.longitude)
        }.joined()
        let query = "[out:json][timeout:20];(\(arounds));out tags center;"
        guard let elements = await fetch(query) else { return [:] }

        var found: [String: PlaceHours] = [:]
        for place in wanted {
            let match = elements
                .filter { $0.point.distance(to: place.location) <= matchRadius && $0.matches(place.name) }
                .min { $0.point.distance(to: place.location) < $1.point.distance(to: place.location) }
            guard let match, let schedule = OpeningHours(match.openingHours) else { continue }
            found[place.id] = schedule.status(at: now)
        }
        return found
    }

    // MARK: Overpass

    private struct Element {
        let point: GeoPoint
        let names: [String]
        let openingHours: String

        func matches(_ name: String) -> Bool {
            let target = Self.normalize(name)
            guard target.count >= 2 else { return false }
            return names.contains { other in
                let other = Self.normalize(other)
                return other.count >= 2 && (target.contains(other) || other.contains(target))
            }
        }

        /// 「セブン-イレブン 新宿店」 → 「セブンイレブン新宿店」, lowercased, for comparing names.
        static func normalize(_ text: String) -> String {
            let dropped: Set<Character> = [" ", "　", "-", "‐", "－", "・", "･", "'", "’", ".", "．"]
            return String(text.applyingTransform(.fullwidthToHalfwidth, reverse: false) ?? text)
                .lowercased()
                .filter { !dropped.contains($0) }
        }
    }

    private struct Response: Decodable {
        struct Item: Decodable {
            struct Center: Decodable {
                let lat: Double
                let lon: Double
            }

            let lat: Double?
            let lon: Double?
            let center: Center?
            let tags: [String: String]?
        }

        let elements: [Item]
    }

    private static func fetch(_ query: String) async -> [Element]? {
        var request = URLRequest(url: URL(string: "https://overpass-api.de/api/interpreter")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("WithDays-iOS", forHTTPHeaderField: "User-Agent")
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = Data(("data=" + (query.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")).utf8)
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let decoded = try? JSONDecoder().decode(Response.self, from: data) else { return nil }
        return decoded.elements.compactMap { item in
            guard let tags = item.tags, let hours = tags["opening_hours"],
                  let lat = item.lat ?? item.center?.lat, let lon = item.lon ?? item.center?.lon else { return nil }
            let names = ["name", "name:ja", "name:en", "brand", "brand:ja", "official_name"].compactMap { tags[$0] }
            return Element(point: GeoPoint(latitude: lat, longitude: lon), names: names, openingHours: hours)
        }
    }
}

// MARK: - opening_hours

/// The common part of OpenStreetMap's opening_hours: 「24/7」, 「Mo-Fr 09:00-18:00; Sa,Su 10:00-17:00」,
/// 「Mo-Sa 11:00-14:00,17:00-23:00; Su off」, times past midnight (「18:00-02:00」). Rules for holidays,
/// months or dates are skipped.
struct OpeningHours {
    /// Minutes from the start of the day, Monday = 0; an end past 1440 runs into the next day.
    private var week: [[(start: Int, end: Int)]?] = Array(repeating: nil, count: 7)
    private var always = false

    init?(_ text: String) {
        let cleaned = text.replacingOccurrences(of: "\"[^\"]*\"", with: "", options: .regularExpression)
            .replacingOccurrences(of: "||", with: ";")
        if cleaned.trimmingCharacters(in: .whitespaces) == "24/7" {
            always = true
            return
        }
        var understood = false
        for rule in cleaned.split(separator: ";") {
            if apply(String(rule)) { understood = true }
        }
        guard understood else { return nil }
        // Days no rule mentions are closed.
        week = week.map { $0 ?? [] }
    }

    private static let dayNames = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

    /// Applies one rule; false when it couldn't be read.
    private mutating func apply(_ rule: String) -> Bool {
        let tokens = rule.replacingOccurrences(of: ",", with: " ").split(separator: " ").map(String.init)
        var days = Set<Int>()
        var times: [(start: Int, end: Int)] = []
        var off = false
        var holiday = false
        var applied = false
        var unreadable = false

        func flush() {
            defer {
                days = []
                times = []
                off = false
                holiday = false
            }
            guard !unreadable, off || !times.isEmpty else { return }
            if days.isEmpty {
                if holiday { return }
                days = Set(0..<7)
            }
            for day in days { week[day] = off ? [] : times }
            applied = true
        }

        for token in tokens {
            if let range = Self.days(token) {
                if off || !times.isEmpty { flush() }
                days.formUnion(range)
            } else if token == "PH" || token == "SH" {
                holiday = true
            } else if let span = Self.time(token) {
                times.append(span)
            } else if token == "off" || token == "closed" {
                off = true
            } else if token == "open" {
                times.append((0, 1440))
            } else {
                unreadable = true
            }
        }
        flush()
        return applied && !unreadable
    }

    /// 「Mo」, 「Mo-Fr」, 「Fr-Mo」 → day numbers.
    private static func days(_ token: String) -> Set<Int>? {
        let parts = token.split(separator: "-").map(String.init)
        guard (1...2).contains(parts.count), let first = dayNames.firstIndex(of: parts[0]) else { return nil }
        guard parts.count == 2 else { return [first] }
        guard let last = dayNames.firstIndex(of: parts[1]) else { return nil }
        var result = Set<Int>()
        var day = first
        while true {
            result.insert(day)
            if day == last { break }
            day = (day + 1) % 7
        }
        return result
    }

    /// 「09:00-18:00」, 「18:00-02:00」, 「11:00+」 → minutes.
    private static func time(_ token: String) -> (start: Int, end: Int)? {
        if token.hasSuffix("+"), let start = minutes(String(token.dropLast())) {
            return (start, max(start + 60, 1440))
        }
        let parts = token.split(separator: "-").map(String.init)
        guard parts.count == 2, let start = minutes(parts[0]), var end = minutes(parts[1]) else { return nil }
        if end <= start { end += 1440 }
        return (start, end)
    }

    private static func minutes(_ text: String) -> Int? {
        let parts = text.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...48).contains(hour), (0..<60).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// Open now or not, and when that changes.
    func status(at now: Date, calendar: Calendar = .current) -> PlaceHours {
        if always { return PlaceHours(openNow: true, nextOpen: nil, nextClose: nil) }
        let today = calendar.startOfDay(for: now)
        var spans: [(start: Date, end: Date)] = []
        for offset in -1...8 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { continue }
            // Calendar's weekday is 1 = Sunday; here 0 = Monday.
            let weekday = (calendar.component(.weekday, from: day) + 5) % 7
            for span in week[weekday] ?? [] {
                spans.append((day.addingTimeInterval(TimeInterval(span.start * 60)), day.addingTimeInterval(TimeInterval(span.end * 60))))
            }
        }
        spans.sort { $0.start < $1.start }
        // Join spans that touch, so 「Mo-Su 00:00-24:00」 reads as one long opening.
        var merged: [(start: Date, end: Date)] = []
        for span in spans {
            if let last = merged.last, span.start <= last.end {
                merged[merged.count - 1].end = max(last.end, span.end)
            } else {
                merged.append(span)
            }
        }
        if let current = merged.first(where: { $0.start <= now && now < $0.end }) {
            let roundTheClock = current.end.timeIntervalSince(now) > 6 * 24 * 3600
            return PlaceHours(openNow: true, nextOpen: nil, nextClose: roundTheClock ? nil : current.end)
        }
        return PlaceHours(openNow: false, nextOpen: merged.first { $0.start > now }?.start, nextClose: nil)
    }
}
