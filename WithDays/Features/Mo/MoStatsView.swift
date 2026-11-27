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
    @State private var side = MoKind.expense

    var body: some View {
        let records = mo.records(from: period.start, to: period.end)
        let expense = Self.sum(records, .expense)
        let income = Self.sum(records, .income)
        let previous = mo.records(from: CalendarMath.addMonths(-1, to: period.start), to: period.start)

        ScrollView {
            VStack(spacing: 14) {
                summary(expense: expense, income: income, previousExpense: Self.sum(previous, .expense))
                MoDailyChart(period: period, records: records)
                MoBreakdown(side: $side, records: records, total: side == .expense ? expense : income)
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
    }

    private static func sum(_ records: [MoRecord], _ kind: MoKind) -> Int {
        records.filter { $0.kind == kind }.reduce(0) { $0 + $1.amount }
    }

    /// 収支 large, then 支出 and 収入 side by side, then the pace: per day and against last month.
    private func summary(expense: Int, income: Int, previousExpense: Int) -> some View {
        let balance = income - expense
        let today = CalendarMath.startOfDay(.now)
        let running = today >= period.start && today < period.end
        let days = max(1, running
            ? CalendarMath.days(from: period.start, to: today) + 1
            : CalendarMath.days(from: period.start, to: period.end))
        let difference = expense - previousExpense
        let sign = balance > 0 ? "+" : balance < 0 ? "-" : ""
        let differenceText = previousExpense == 0 && expense == 0
            ? "—"
            : "\(difference > 0 ? "+" : difference < 0 ? "-" : "±")¥\(MoFormat.amount(abs(difference)))"
        let differenceColor: Color = difference > 0 ? .moExpense : difference < 0 ? .moIncome : .secondary
        return VStack(spacing: 14) {
            VStack(spacing: 2) {
                Text("収支")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("\(sign)¥\(MoFormat.amount(abs(balance)))")
                    .font(MoFormat.number(44))
                    .monospacedDigit()
                    .foregroundStyle(balance >= 0 ? Color.moIncome : Color.moExpense)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            HStack(spacing: 10) {
                tile(.expense, expense)
                tile(.income, income)
            }
            HStack(spacing: 0) {
                pace("1日あたりの支出", "¥\(MoFormat.amount(expense / days))", color: .primary)
                Divider().frame(height: 30)
                pace("先月の支出と比べて", differenceText, color: differenceColor)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func tile(_ kind: MoKind, _ amount: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(kind.label, systemImage: kind == .expense ? "arrow.up.right" : "arrow.down.left")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(kind.color)
            Text("¥\(MoFormat.amount(amount))")
                .font(MoFormat.number(22))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(kind.color.opacity(0.1)))
    }

    private func pace(_ title: String, _ value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(MoFormat.number(17))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Each day's spending in the month as bars, today's darker.
private struct MoDailyChart: View {
    let period: MoPeriod
    let records: [MoRecord]

    private struct Day: Identifiable {
        let date: Date
        let amount: Int
        var id: Date { date }
    }

    private var days: [Day] {
        let count = max(1, CalendarMath.days(from: period.start, to: period.end))
        var totals: [Date: Int] = [:]
        for record in records where record.kind == .expense {
            totals[CalendarMath.startOfDay(record.date), default: 0] += record.amount
        }
        return (0..<count).map { offset in
            let date = CalendarMath.addDays(offset, to: period.start)
            return Day(date: date, amount: totals[date] ?? 0)
        }
    }

    var body: some View {
        let today = CalendarMath.startOfDay(.now)
        VStack(alignment: .leading, spacing: 10) {
            Text("毎日の支出")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
            Chart(days) { day in
                BarMark(x: .value("日", day.date, unit: .day), y: .value("支出", day.amount))
                    .foregroundStyle(CalendarMath.isSameDay(day.date, today) ? Color.moExpense : Color.moExpense.opacity(0.45))
                    .cornerRadius(2)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.day(), centered: true)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let amount = value.as(Int.self) { Text(MoFormat.compact(amount)) }
                    }
                }
            }
            .frame(height: 140)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemBackground)))
    }
}

/// One side's categories (支出 / 収入, switched at the top): a donut, then each category with its share as a bar.
/// Tapping a category lists its records.
private struct MoBreakdown: View {
    @Binding var side: MoKind
    let records: [MoRecord]
    let total: Int

    @Environment(MoStore.self) private var mo
    @State private var opened: Slice?

    struct Slice: Identifiable {
        let label: String
        let icon: String
        let amount: Int
        let color: Color
        var id: String { label }
    }

    private static let expenseColors: [UInt32] = [0xEF4444, 0xF97316, 0xEAB308, 0x8B5CF6, 0x14B8A6, 0x3B82F6, 0xEC4899]
    private static let incomeColors: [UInt32] = [0x16A34A, 0x65A30D, 0x0EA5E9, 0x22C55E, 0x059669, 0x84CC16]

    /// Grouped by the records' own category names, so deleted categories still count.
    private var slices: [Slice] {
        var amounts: [String: (icon: String, amount: Int)] = [:]
        for record in records where record.kind == side {
            let icon = mo.categories(side).first { $0.label == record.category }?.icon ?? record.icon
            amounts[record.category, default: (icon, 0)].amount += record.amount
        }
        let colors = side == .expense ? Self.expenseColors : Self.incomeColors
        return amounts
            .filter { $0.value.amount > 0 }
            .sorted { $0.value.amount > $1.value.amount }
            .enumerated()
            .map { index, entry in
                Slice(label: entry.key, icon: entry.value.icon, amount: entry.value.amount,
                      color: Color(uiColor: UIColor(hex: colors[index % colors.count])))
            }
    }

    var body: some View {
        let slices = slices
        VStack(spacing: 16) {
            Picker("内訳", selection: $side.animation(.snappy)) {
                ForEach(MoKind.allCases, id: \.self) { kind in
                    Text("\(kind.label)の内訳").tag(kind)
                }
            }
            .pickerStyle(.segmented)

            donut(slices)
                .frame(width: 180, height: 180)

            if slices.isEmpty {
                Text("まだ記録がありません")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
            } else {
                VStack(spacing: 4) {
                    ForEach(slices) { slice in
                        Button { opened = slice } label: { row(slice) }
                            .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Color(.secondarySystemBackground)))
        .sheet(item: $opened) { slice in
            MoCategoryRecords(title: slice.label, color: side.color,
                              records: records.filter { $0.kind == side && $0.category == slice.label })
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func donut(_ slices: [Slice]) -> some View {
        ZStack {
            if slices.isEmpty {
                Circle()
                    .stroke(Color(.systemGray5), lineWidth: 24)
                    .padding(12)
            } else {
                Chart(slices) { slice in
                    SectorMark(angle: .value("金額", slice.amount), innerRadius: .ratio(0.66), angularInset: 1.5)
                        .cornerRadius(3)
                        .foregroundStyle(slice.color)
                }
                .chartLegend(.hidden)
            }
            VStack(spacing: 2) {
                Text(side.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                Text("¥\(MoFormat.amount(total))")
                    .font(MoFormat.number(22))
                    .monospacedDigit()
                    .foregroundStyle(side.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            .frame(width: 110)
        }
    }

    private func row(_ slice: Slice) -> some View {
        let share = Double(slice.amount) / Double(max(total, 1))
        return HStack(spacing: 12) {
            MoIcon(name: slice.icon, size: 18)
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(slice.color))
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(slice.label)
                        .font(.system(size: 15, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text("¥\(MoFormat.amount(slice.amount))")
                        .font(MoFormat.number(16))
                        .monospacedDigit()
                }
                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.primary.opacity(0.07))
                            Capsule().fill(slice.color).frame(width: max(4, geo.size.width * share))
                        }
                    }
                    .frame(height: 6)
                    Text("\(Int((share * 100).rounded()))%")
                        .font(MoFormat.number(12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// A category's records in the month, newest first.
private struct MoCategoryRecords: View {
    let title: String
    let color: Color
    let records: [MoRecord]

    var body: some View {
        NavigationStack {
            List(records.sorted { $0.date > $1.date }) { record in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(MoFormat.shortDay(record.date))
                            .font(.system(size: 15, weight: .bold))
                            .monospacedDigit()
                        if !record.memo.isEmpty {
                            Text(record.memo)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 8)
                    Text("¥\(MoFormat.amount(record.amount))")
                        .font(MoFormat.number(18))
                        .monospacedDigit()
                        .foregroundStyle(color)
                }
            }
            .listStyle(.plain)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
