import SwiftUI

/// The month with each day's spending (red) and income (green); the chosen day's records below.
/// Swipe a record left to delete it, right to edit it.
struct MoCalendarView: View {
    @Environment(\.backToWithDays) private var backToWithDays
    @Environment(MoStore.self) private var mo
    @Environment(ToastCenter.self) private var toasts
    @AppStorage(SettingsKey.weekStart, store: AppGroup.defaults) private var weekStart = 1
    @State private var offset = 0
    @State private var selectedDate = CalendarMath.startOfDay(.now)
    @State private var editing: MoRecord?
    private let baseMonth = CalendarMath.startOfMonth(.now)

    private static let range = -600...600
    private static let rowHeight = GridMetrics.rowHeight

    var body: some View {
        VStack(spacing: 0) {
            WeekdayHeader(weekStart: weekStart)

            TabView(selection: $offset) {
                ForEach(Self.range, id: \.self) { index in
                    MoMonthGrid(month: month(index), selectedDate: selectedDate, rowHeight: Self.rowHeight) { day in
                        withAnimation(.snappy) {
                            selectedDate = day
                            offset = CalendarMath.months(from: baseMonth, to: day)
                        }
                    }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: Self.rowHeight * 6)

            monthTotals
                .padding(.horizontal, 16)
                .padding(.top, 8)

            dayList
        }
        .sensoryFeedback(.selection, trigger: selectedDate)
        .toolbar {
            WithDaysBackItem(action: backToWithDays)
            ToolbarItem(placement: .topBarLeading) {
                Text(Fmt.monthTitle(month(offset)))
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(offset)))
                    .animation(.snappy, value: offset)
                    .fixedSize()
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: backToToday) {
                    Image(systemName: "arrow.uturn.left")
                }
            }
        }
        .sheet(item: $editing) { record in
            MoRecordEditor(record: record)
        }
    }

    private func month(_ index: Int) -> Date {
        CalendarMath.addMonths(index, to: baseMonth)
    }

    private func backToToday() {
        withAnimation(.snappy) {
            offset = 0
            selectedDate = CalendarMath.startOfDay(.now)
        }
    }

    /// The shown month's 支出 / 収入 / 収支 in one strip under the grid.
    private var monthTotals: some View {
        let start = month(offset)
        let records = mo.records(from: start, to: CalendarMath.addMonths(1, to: start))
        let expense = records.filter { $0.kind == .expense }.reduce(0) { $0 + $1.amount }
        let income = records.filter { $0.kind == .income }.reduce(0) { $0 + $1.amount }
        let balance = income - expense
        return HStack(spacing: 0) {
            monthTotal("支出", "¥\(MoFormat.amount(expense))", .moExpense)
            monthTotal("収入", "¥\(MoFormat.amount(income))", .moIncome)
            monthTotal("収支", "\(balance > 0 ? "+" : balance < 0 ? "-" : "")¥\(MoFormat.amount(abs(balance)))",
                       balance >= 0 ? .moIncome : .moExpense)
        }
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(.secondarySystemBackground)))
        .animation(.snappy, value: offset)
    }

    private func monthTotal(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(MoFormat.number(15))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
    }

    private var dayList: some View {
        let records = mo.records(on: selectedDate)
        let net = records.reduce(0) { $0 + ($1.kind == .income ? $1.amount : -$1.amount) }
        return VStack(spacing: 0) {
            HStack {
                Text(Fmt.fullDate(selectedDate))
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                if !records.isEmpty {
                    Text(net == 0 ? "¥0" : "\(net > 0 ? "+" : "-")\(MoFormat.amount(abs(net)))")
                        .font(MoFormat.number(18))
                        .monospacedDigit()
                        .foregroundStyle(net > 0 ? Color.moIncome : net < 0 ? Color.moExpense : Color.secondary)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)

            List {
                ForEach(records) { record in
                    row(record)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = record }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { delete(record) } label: {
                                Image(systemName: "trash")
                            }
                            .tint(.red)
                        }
                        .swipeActions(edge: .leading) {
                            Button { editing = record } label: {
                                Image(systemName: "pencil.and.outline")
                            }
                            .tint(.brand)
                        }
                }
            }
            .listStyle(.plain)
            .overlay {
                if records.isEmpty {
                    Text("この日の記録はありません")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func row(_ record: MoRecord) -> some View {
        HStack(spacing: 12) {
            MoIcon(name: record.icon, size: 20)
                .foregroundStyle(record.kind.color)
                .frame(width: 40, height: 40)
                .background(Circle().fill(record.kind.color.opacity(0.1)))
            VStack(alignment: .leading, spacing: 2) {
                Text(record.category)
                    .font(.system(size: 15, weight: .bold))
                if !record.memo.isEmpty {
                    Text(record.memo)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(MoFormat.amount(record.amount))
                .font(MoFormat.number(20))
                .monospacedDigit()
                .foregroundStyle(record.kind.color)
        }
        .padding(.vertical, 2)
    }

    private func delete(_ record: MoRecord) {
        guard let removed = mo.delete(record.id) else { return }
        toasts.show("記録を削除しました") {
            mo.restore(removed.record, at: removed.index)
        }
    }
}

/// Six weeks of one month, laid out like the calendar's grid.
private struct MoMonthGrid: View {
    let month: Date
    let selectedDate: Date
    let rowHeight: CGFloat
    var onSelect: (Date) -> Void

    @Environment(MoStore.self) private var mo
    @Environment(CalendarStore.self) private var store
    @AppStorage(SettingsKey.weekStart, store: AppGroup.defaults) private var weekStart = 1

    var body: some View {
        let days = CalendarMath.gridDays(for: month, weekStart: weekStart)
        let end = CalendarMath.addDays(42, to: days[0])
        let totals = mo.dailyTotals(from: days[0], to: end)
        let holidays = store.holidays(from: days[0], to: end)

        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<6, id: \.self) { row in
                GridRow {
                    ForEach(0..<7, id: \.self) { column in
                        let day = days[row * 7 + column]
                        cell(day, totals: totals[day], isHoliday: holidays.contains(day))
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func cell(_ day: Date, totals: (expense: Int, income: Int)?, isHoliday: Bool) -> some View {
        let isToday = CalendarMath.isSameDay(day, .now)
        let isSelected = CalendarMath.isSameDay(day, selectedDate)
        return ZStack(alignment: .topLeading) {
            if isSelected {
                RoundedRectangle(cornerRadius: GridMetrics.cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .padding(1)
            }
            Rectangle()
                .fill(isSelected ? Color.brand : Color.dayLine)
                .frame(height: 1)
                .padding(.horizontal, 3)
                .offset(y: 20)
            Text("\(CalendarMath.day(day))")
                .font(.system(size: 12, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(isToday ? Color.white : Color.dayNumber(weekday: CalendarMath.weekday(day), isHoliday: isHoliday))
                .frame(minWidth: 18, minHeight: 18)
                .background { if isToday { Circle().fill(Color.brand) } }
                .padding(.leading, 2)
                .padding(.top, 1)
            VStack(alignment: .trailing, spacing: 0) {
                if let totals, totals.expense > 0 {
                    Text(MoFormat.amount(totals.expense))
                        .foregroundStyle(Color.moExpense)
                }
                if let totals, totals.income > 0 {
                    Text(MoFormat.amount(totals.income))
                        .foregroundStyle(Color.moIncome)
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.55)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.horizontal, 3)
            .padding(.top, GridMetrics.laneTop)
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight, alignment: .topLeading)
        .opacity(CalendarMath.isSameMonth(day, month) ? 1 : 0.35)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(day) }
    }
}
