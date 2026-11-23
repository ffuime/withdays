import SwiftUI

/// Subscribes' subscriptions and payment history, saved through `SubsData` after every change.
@MainActor
@Observable
final class SubsStore {
    private(set) var state = SubsData.load()

    init() {
        catchUp()
    }

    var subs: [Sub] { state.subs }
    var payments: [SubsPayment] { state.payments }

    func sub(_ id: String) -> Sub? {
        state.subs.first { $0.id == id }
    }

    var categories: [String] {
        let custom = state.customCategories.filter { !SubsData.defaultCategories.contains($0) }
        // New ones go before その他.
        return Array(SubsData.defaultCategories.dropLast()) + custom + ["その他"]
    }

    func addCategory(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !categories.contains(name) else { return }
        state.customCategories.append(name)
        persist()
    }

    // MARK: Changes

    func save(_ sub: Sub) {
        if let index = state.subs.firstIndex(where: { $0.id == sub.id }) {
            state.subs[index] = sub
        } else {
            state.subs.append(sub)
        }
        catchUp()
        persist()
    }

    /// Past payments stay in the history.
    func delete(_ id: String) {
        state.subs.removeAll { $0.id == id }
        persist()
    }

    var sort: SubsSort {
        get { state.sort }
        set { state.sort = newValue; persist() }
    }

    var reversed: Bool {
        get { state.reversed }
        set { state.reversed = newValue; persist() }
    }

    /// Writes down every renewal that has passed since last time.
    func catchUp() {
        let today = CalendarMath.startOfDay(.now)
        var changed = false
        for index in state.subs.indices {
            let sub = state.subs[index]
            let from = sub.paidThrough ?? CalendarMath.addDays(-1, to: CalendarMath.startOfDay(sub.startDate))
            guard from < CalendarMath.addDays(-1, to: today) else { continue }
            for date in sub.renewals(after: from, through: today) where date < today && sub.charges(on: date) {
                state.payments.append(SubsPayment(subID: sub.id, name: sub.name, symbol: sub.symbol, tint: sub.tint, amount: sub.price, date: date))
            }
            // Today's renewal is still "next" today; it's written down tomorrow.
            state.subs[index].paidThrough = CalendarMath.addDays(-1, to: today)
            changed = true
        }
        if changed { persist() }
    }

    // MARK: Reading

    /// The list's order.
    var sorted: [Sub] {
        let list: [Sub]
        switch state.sort {
        case .added: list = state.subs.sorted { $0.createdAt > $1.createdAt }
        case .price: list = state.subs.sorted { $0.monthly > $1.monthly }
        case .renewal: list = state.subs.sorted { $0.nextRenewal < $1.nextRenewal }
        }
        return state.reversed ? list.reversed() : list
    }

    /// 今月の合計支出: each subscription's monthly share, leaving out free trials.
    var monthlyTotal: Double {
        state.subs.filter { !$0.inTrial }.reduce(0) { $0 + $1.monthly }
    }

    struct Charge: Identifiable, Hashable {
        let id: String
        let subID: String
        let name: String
        let symbol: String
        let tint: UInt32
        let amount: Int
        let date: Date
    }

    /// What's paid in a month: what was (from the history) and what will be (from the renewals).
    func charges(in month: Date) -> [Charge] {
        let start = CalendarMath.startOfMonth(month)
        let end = CalendarMath.addMonths(1, to: start)
        let today = CalendarMath.startOfDay(.now)
        var list = state.payments.filter { $0.date >= start && $0.date < end && $0.date < today }.map {
            Charge(id: $0.id, subID: $0.subID, name: $0.name, symbol: $0.symbol, tint: $0.tint, amount: $0.amount, date: $0.date)
        }
        if end > today {
            let from = CalendarMath.addDays(-1, to: max(start, today))
            for sub in state.subs {
                for date in sub.renewals(after: from, through: CalendarMath.addDays(-1, to: end)) where sub.charges(on: date) {
                    list.append(Charge(id: "\(sub.id)-\(date.timeIntervalSince1970)", subID: sub.id, name: sub.name,
                                       symbol: sub.symbol, tint: sub.tint, amount: sub.price, date: date))
                }
            }
        }
        return list.sorted { ($0.date, $0.name) < ($1.date, $1.name) }
    }

    /// Payments so far for one subscription.
    func paid(_ id: String) -> (count: Int, total: Int) {
        let mine = state.payments.filter { $0.subID == id }
        return (mine.count, mine.reduce(0) { $0 + $1.amount })
    }

    // MARK: Saving

    private func persist() {
        SubsData.save(state)
        SubsUsageShare.publish(state.subs)
    }
}
