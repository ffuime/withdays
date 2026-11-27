import Charts
import SwiftUI

/// A month's balance and where the money went / came from. Swipe sideways (or use the arrows) for other months.
/// A month runs from the start day set in Settings (every month on day x) to the day before it next month.
struct MoStatsView: View {
    @Environment(\.backToWithDays) private var backToWithDays
    @AppStorage(SettingsKey.moMonthStart) private var startDay = 1
    @State private var offset = 0

    private static let range = -600...600

    var body: some View {
        TabView(selection: $offset) {
            ForEach(Self.range, id: \.self) { index in
                MoStatsPage(period: period(index))
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .sensoryFeedback(.selection, trigger: offset)
        // The same bar as the calendar's: month on the left, arrows on the right.
        .toolbar {
            WithDaysBackItem(action: backToWithDays)
            ToolbarItem(placement: .topBarLeading) {
                Text(title(period(offset)))
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(offset)))
                    .animation(.snappy, value: offset)
                    .fixedSize()
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItemGroup(placement: .topBarTrailing) {
                arrow("chevron.left", step: -1)
                arrow("chevron.right", step: 1)
            }
        }
    }

    /// The period `index` months from the one holding today.
    private func period(_ index: Int) -> MoPeriod {
        let day = min(max(startDay, 1), 28)
        let today = CalendarMath.startOfDay(.now)
        var start = CalendarMath.addDays(day - 1, to: CalendarMath.startOfMonth(today))
        if start > today { start = CalendarMath.addMonths(-1, to: start) }
        start = CalendarMath.addMonths(index, to: start)
        return MoPeriod(start: start, end: CalendarMath.addMonths(1, to: start))
    }

    /// 2026年11月, or 10/25〜11/24 when months start on another day.
    private func title(_ period: MoPeriod) -> String {
        guard CalendarMath.day(period.start) != 1 else { return Fmt.monthTitle(period.start) }
        let last = CalendarMath.addDays(-1, to: period.end)
        let calendar = CalendarMath.calendar
        let short: (Date) -> String = { "\(calendar.component(.month, from: $0))/\(calendar.component(.day, from: $0))" }
        return "\(short(period.start))〜\(short(last))"
    }

    private func arrow(_ icon: String, step: Int) -> some View {
        Button {
            withAnimation(.snappy) { offset = min(Self.range.upperBound, max(Self.range.lowerBound, offset + step)) }
        } label: {
            Image(systemName: icon)
        }
    }
}

struct MoPeriod: Hashable {
    let start: Date
    let end: Date
}

private struct MoStatsPage: View {
    let period: MoPeriod

    @Environment(MoStore.self) private var mo

    var body: some View {
        let records = mo.records(from: period.start, to: period.end)
        let expense = records.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
        let income = records.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
        let balance = income - expense

        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 10) {
                    Text("今月の収支")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("\(balance < 0 ? "-" : "")\(MoFormat.amount(abs(balance)))")
                        .font(MoFormat.number(48))
                        .monospacedDigit()
                        .foregroundStyle(balance >= 0 ? Color.moIncome : Color.moExpense)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    HStack(spacing: 24) {
                        total(.expense, expense)
                        total(.income, income)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemBackground)))

                MoBreakdown(kind: .expense, records: records, total: expense)
                MoBreakdown(kind: .income, records: records, total: income)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
    }

    private func total(_ kind: MoKind, _ amount: Int) -> some View {
        HStack(spacing: 4) {
            Image(systemName: kind == .expense ? "arrow.up" : "arrow.down")
                .font(.system(size: 12, weight: .bold))
            Text(MoFormat.amount(amount))
                .font(MoFormat.number(20))
                .monospacedDigit()
        }
        .foregroundStyle(kind.color)
    }
}

/// A donut of one side's categories with the list under it, largest first.
private struct MoBreakdown: View {
    let kind: MoKind
    let records: [MoRecord]
    let total: Int

    @Environment(MoStore.self) private var mo

    private struct Slice: Identifiable {
        let label: String
        let icon: String
        let amount: Int
        let color: Color
        var id: String { label }
    }

    private static let expenseColors: [UInt32] = [0xEF4444, 0xF97316, 0xEAB308, 0x8B5CF6, 0x14B8A6]
    private static let incomeColors: [UInt32] = [0x16A34A, 0x65A30D, 0x15803D, 0x22C55E, 0x059669]

    /// Grouped by the records' own category names, so deleted categories still count.
    private var slices: [Slice] {
        var amounts: [String: (icon: String, amount: Int)] = [:]
        for record in records where record.kind == kind {
            let icon = mo.categories(kind).first { $0.label == record.category }?.icon ?? record.icon
            amounts[record.category, default: (icon, 0)].amount += record.amount
        }
        let colors = kind == .expense ? Self.expenseColors : Self.incomeColors
        return amounts
            .filter { $0.value.amount > 0 }
            .sorted { $0.value.amount > $1.value.amount }
            .enumerated()
            .map { index, entry in
                Slice(label: entry.key, icon: entry.value.icon, amount: entry.value.amount, color: Color(uiColor: UIColor(hex: colors[index % colors.count])))
            }
    }

    var body: some View {
        let slices = slices
        VStack(spacing: 14) {
            ZStack {
                if slices.isEmpty {
                    Circle()
                        .stroke(Color(.systemGray5), lineWidth: 26)
                        .padding(13)
                } else {
                    Chart(slices) { slice in
                        SectorMark(angle: .value("金額", slice.amount), innerRadius: .ratio(0.64), angularInset: 1.5)
                            .cornerRadius(3)
                            .foregroundStyle(slice.color)
                    }
                    .chartLegend(.hidden)
                }
                VStack(spacing: 2) {
                    Text(kind.label)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                    Text("¥\(MoFormat.amount(total))")
                        .font(MoFormat.number(22))
                        .monospacedDigit()
                        .foregroundStyle(kind.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .frame(width: 110)
            }
            .frame(width: 200, height: 200)

            if slices.isEmpty {
                Text("まだ記録がありません")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(slices) { slice in
                        HStack(spacing: 12) {
                            MoIcon(name: slice.icon, size: 20)
                                .foregroundStyle(.white)
                                .frame(width: 38, height: 38)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(slice.color))
                            Text(slice.label)
                                .font(.system(size: 15, weight: .bold))
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text("\(Int((Double(slice.amount) / Double(max(total, 1)) * 100).rounded()))%")
                                .font(MoFormat.number(15))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(MoFormat.amount(slice.amount))
                                .font(MoFormat.number(18))
                                .monospacedDigit()
                                .frame(minWidth: 80, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}
