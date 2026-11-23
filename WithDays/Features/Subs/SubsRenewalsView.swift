import SwiftUI

/// 更新日: the month like the calendar, each renewal's icon on its day, and the month's renewals below with their total.
struct SubsRenewalsView: View {
    @Environment(SubsStore.self) private var store
    @Environment(SubsRouter.self) private var router
    @AppStorage(SettingsKey.weekStart, store: AppGroup.defaults) private var weekStart = 1
    @State private var offset = 0
    private let baseMonth = CalendarMath.startOfMonth(.now)

    private static let range = -240...240
    private static let rowHeight: CGFloat = 54

    private var month: Date { CalendarMath.addMonths(offset, to: baseMonth) }

    var body: some View {
        let charges = store.charges(in: month)
        VStack(spacing: 0) {
            HStack {
                Text(Fmt.monthTitle(month))
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(offset)))
                    .animation(.snappy, value: offset)
                Spacer()
                if offset != 0 {
                    Button {
                        withAnimation(.snappy) { offset = 0 }
                    } label: {
                        Image(systemName: "arrow.uturn.left")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .frame(height: 40)
            .padding(.horizontal, 16)

            WeekdayHeader(weekStart: weekStart)

            TabView(selection: $offset) {
                ForEach(Self.range, id: \.self) { index in
                    SubsMonthGrid(month: CalendarMath.addMonths(index, to: baseMonth), rowHeight: Self.rowHeight)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: Self.rowHeight * 6)

            List {
                ForEach(charges) { charge in
                    row(charge)
                        .listRowSeparator(.hidden)
                }
                HStack {
                    Spacer()
                    Text("合計")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Text(SubsFormat.yen(charges.reduce(0) { $0 + $1.amount }))
                        .font(SubsFormat.number(20, .bold))
                        .monospacedDigit()
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .overlay {
                if charges.isEmpty {
                    Text("この月の更新はありません")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: offset)
    }

    @ViewBuilder
    private func row(_ charge: SubsStore.Charge) -> some View {
        let sub = store.sub(charge.subID)
        let content = HStack(spacing: 12) {
            if let sub {
                SubsIconView(sub: sub, size: 32)
            } else {
                SubsSymbolIcon(symbol: charge.symbol, tint: charge.tint, size: 32)
            }
            Text(charge.name)
                .font(.system(size: 15, weight: .bold))
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(SubsFormat.day(charge.date))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            SubsPriceText(price: charge.amount, size: 16)
        }
        .contentShape(Rectangle())
        if let sub {
            content
                .onTapGesture { router.open(sub) }
                .modifier(SubsSwipes(sub: sub))
        } else {
            content
        }
    }
}

/// Six weeks of a month, laid out like the calendar's grid, with each renewal's icon.
private struct SubsMonthGrid: View {
    let month: Date
    let rowHeight: CGFloat

    @Environment(SubsStore.self) private var store
    @Environment(CalendarStore.self) private var calendar
    @AppStorage(SettingsKey.weekStart, store: AppGroup.defaults) private var weekStart = 1

    var body: some View {
        let days = CalendarMath.gridDays(for: month, weekStart: weekStart)
        let end = CalendarMath.addDays(42, to: days[0])
        let holidays = calendar.holidays(from: days[0], to: end)
        let byDay = Dictionary(grouping: store.charges(in: month)) { CalendarMath.startOfDay($0.date) }

        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
            ForEach(0..<6, id: \.self) { row in
                GridRow {
                    ForEach(0..<7, id: \.self) { column in
                        let day = days[row * 7 + column]
                        cell(day, charges: CalendarMath.isSameMonth(day, month) ? byDay[day] ?? [] : [], isHoliday: holidays.contains(day))
                    }
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func cell(_ day: Date, charges: [SubsStore.Charge], isHoliday: Bool) -> some View {
        let isToday = CalendarMath.isSameDay(day, .now)
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color.dayLine)
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
            HStack(spacing: -6) {
                ForEach(charges.prefix(2)) { charge in
                    icon(charge)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).stroke(Color(.systemBackground), lineWidth: 1.5))
                }
                if charges.count > 2 {
                    Text("+\(charges.count - 2)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, GridMetrics.laneTop + 2)
        }
        .frame(maxWidth: .infinity)
        .frame(height: rowHeight, alignment: .topLeading)
        .opacity(CalendarMath.isSameMonth(day, month) ? 1 : 0.35)
    }

    @ViewBuilder
    private func icon(_ charge: SubsStore.Charge) -> some View {
        if let sub = store.sub(charge.subID) {
            SubsIconView(sub: sub, size: 24)
        } else {
            SubsSymbolIcon(symbol: charge.symbol, tint: charge.tint, size: 24)
        }
    }
}
