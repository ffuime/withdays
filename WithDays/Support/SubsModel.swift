import Foundation
import SwiftUI

// MARK: Billing cycle

enum SubsUnit: String, Codable, CaseIterable {
    case week, month, year
}

struct SubsCycle: Codable, Hashable {
    var unit: SubsUnit
    var count = 1

    static let monthly = SubsCycle(unit: .month)

    /// 「月間」「3か月」: the cycle's name.
    var label: String {
        switch unit {
        case .week: count == 1 ? "週間" : "\(count)週間"
        case .month: count == 1 ? "月間" : "\(count)か月"
        case .year: count == 1 ? "年間" : "\(count)年"
        }
    }

    /// 「/月」「/2ヶ月」: after a price.
    var suffix: String {
        switch unit {
        case .week: count == 1 ? "/週" : "/\(count)週間"
        case .month: count == 1 ? "/月" : "/\(count)ヶ月"
        case .year: count == 1 ? "/年" : "/\(count)年"
        }
    }

    /// What one month of it costs on average.
    func monthly(_ price: Int) -> Double {
        let each = Double(price) / Double(max(count, 1))
        switch unit {
        case .week: return each * 52 / 12
        case .month: return each
        case .year: return each / 12
        }
    }

    /// `times` cycles from `date` (negative goes back). Always counted from the same date, so 31st stays 31st where it can.
    func advance(_ date: Date, times: Int = 1) -> Date {
        let calendar = CalendarMath.calendar
        switch unit {
        case .week: return calendar.date(byAdding: .day, value: 7 * count * times, to: date) ?? date
        case .month: return calendar.date(byAdding: .month, value: count * times, to: date) ?? date
        case .year: return calendar.date(byAdding: .year, value: count * times, to: date) ?? date
        }
    }
}

// MARK: Subscription

struct Sub: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name = ""
    var price = 0
    var cycle = SubsCycle.monthly
    var category = "動画"
    /// 登録日.
    var startDate = CalendarMath.startOfDay(.now)
    /// The 次回更新日 as entered; every renewal is this date plus whole cycles.
    var anchor = CalendarMath.addMonths(1, to: CalendarMath.startOfDay(.now))
    var trial = false
    var trialEnd = CalendarMath.addDays(7, to: CalendarMath.startOfDay(.now))
    var memo = ""
    var symbol = "play.rectangle.fill"
    var tint: UInt32 = 0x065A8C
    /// A picture of its own (also the App Store icon), small PNG / JPEG.
    var image: Data?
    /// The app chosen in Screen Time (an encoded ApplicationToken).
    var appToken: Data?
    var createdAt = Date.now
    /// Payments are written down up to this day.
    var paidThrough: Date?

    var monthly: Double { cycle.monthly(price) }

    /// Still free today.
    var inTrial: Bool { trial && trialEnd >= CalendarMath.startOfDay(.now) }

    /// A renewal on `date` costs money (not inside the free trial, not before signing up).
    func charges(on date: Date) -> Bool {
        date >= CalendarMath.startOfDay(startDate) && !(trial && date < trialEnd)
    }

    /// Renewals in (after, through], oldest first.
    func renewals(after: Date, through: Date) -> [Date] {
        guard through > after else { return [] }
        var k = 0
        // Back to the first renewal after `after`, or forward to it.
        while cycle.advance(anchor, times: k) > after { k -= 1 }
        while cycle.advance(anchor, times: k) <= after { k += 1 }
        var dates: [Date] = []
        var date = cycle.advance(anchor, times: k)
        while date <= through, dates.count < 2000 {
            dates.append(date)
            k += 1
            date = cycle.advance(anchor, times: k)
        }
        return dates
    }

    /// The first renewal today or later.
    var nextRenewal: Date {
        let today = CalendarMath.startOfDay(.now)
        return renewals(after: CalendarMath.addDays(-1, to: today), through: cycle.advance(today, times: 2)).first ?? anchor
    }

    /// The first renewal after `start` (sign-up), at or after today: the default 次回更新日.
    static func firstRenewal(from start: Date, cycle: SubsCycle) -> Date {
        let today = CalendarMath.startOfDay(.now)
        var k = 1
        var date = cycle.advance(start, times: k)
        while date < today, k < 5000 {
            k += 1
            date = cycle.advance(start, times: k)
        }
        return date
    }
}

/// One renewal that was paid. Keeps the name and look, so it stays after the subscription is deleted.
struct SubsPayment: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var subID: String
    var name: String
    var symbol: String
    var tint: UInt32
    var amount: Int
    var date: Date
}

enum SubsSort: String, Codable, CaseIterable, Identifiable {
    case added, price, renewal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .added: "追加が新しい順"
        case .price: "値段が高い順"
        case .renewal: "更新が近い順"
        }
    }
}

struct SubsState: Codable {
    var subs: [Sub] = []
    var payments: [SubsPayment] = []
    var customCategories: [String] = []
    var sort = SubsSort.added
    var reversed = false
}

enum SubsData {
    static let defaultCategories = ["動画", "音楽", "ファンクラブ", "ゲーム", "ツール", "クラウド", "ニュース", "ヘルスケア", "教育", "その他"]

    private static var url: URL {
        let base = AppGroup.identifier.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appending(path: "subscribes.json")
    }

    static func load() -> SubsState {
        guard let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(SubsState.self, from: data) else {
            return SubsState()
        }
        return state
    }

    static func save(_ state: SubsState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

// MARK: Formatting

enum SubsFormat {
    private static let grouping: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.usesGroupingSeparator = true
        return formatter
    }()

    /// ¥3,000
    static func yen(_ amount: Int) -> String {
        "¥" + (grouping.string(from: NSNumber(value: amount)) ?? "\(amount)")
    }

    static func yen(_ amount: Double) -> String {
        yen(Int(amount.rounded()))
    }

    private static let dotted: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = CalendarMath.calendar
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy.MM.dd"
        return formatter
    }()

    private static let short: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = CalendarMath.calendar
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "M/d"
        return formatter
    }()

    /// 2026.01.05
    static func date(_ date: Date) -> String { dotted.string(from: date) }

    /// 1/5
    static func day(_ date: Date) -> String { short.string(from: date) }

    /// Big numbers: rounded.
    static func number(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
