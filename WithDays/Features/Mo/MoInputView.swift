import SwiftUI

/// Record money in three steps, top to bottom: 支出 / 収入 (and the day), the amount on the keypad, then a category —
/// tapping it records. Every category is in sight in a grid; 編集 opens their list (holding the grid does too).
struct MoInputView: View {
    @Binding var kind: MoKind
    @Environment(\.backToWithDays) private var backToWithDays

    @Environment(MoStore.self) private var mo
    @Environment(ToastCenter.self) private var toasts
    @State private var digits = ""
    @State private var memo = ""
    /// The day it's recorded on; today unless another day is picked.
    @State private var day = CalendarMath.startOfDay(.now)
    @State private var pickingDay = false
    @State private var categorySheet: MoCategorySheet.Target?
    @State private var showCategoryList = false
    @State private var shake = 0
    @State private var saved = 0
    @FocusState private var memoFocused: Bool
    @Namespace private var kindSwitch

    /// Up to 15 digits; long amounts shrink to stay on one line.
    private static let maxDigits = 15
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    private var isToday: Bool { CalendarMath.isSameDay(day, .now) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                kindPicker
                Spacer(minLength: 0)
                dayButton
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            amountCard
                .padding(.horizontal, 16)
                .padding(.top, 12)

            categories
                .padding(.top, 10)

            memoField
                .padding(.horizontal, 16)
                .padding(.top, 6)

            MoKeypad(color: kind.color, onDigit: type, onDelete: deleteLast, onClear: { digits = "" })
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture { memoFocused = false }
        .toolbar { WithDaysBackItem(action: backToWithDays) }
        .sensoryFeedback(.success, trigger: saved)
        .sensoryFeedback(.error, trigger: shake)
        .sensoryFeedback(.impact(weight: .medium), trigger: showCategoryList) { _, new in new }
        .sheet(item: $categorySheet) { target in
            MoCategorySheet(target: target, kind: kind)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showCategoryList) {
            MoCategoryListSheet(kind: kind)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $pickingDay) {
            MoDayPicker(day: $day, color: kind.color)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Top: kind and day

    /// 支出 | 収入 in one capsule; the colour slides to the chosen side.
    private var kindPicker: some View {
        HStack(spacing: 0) {
            ForEach(MoKind.allCases, id: \.self) { item in
                Button {
                    withAnimation(.snappy) { kind = item }
                } label: {
                    Text(item.label)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(kind == item ? Color.white : Color.secondary)
                        .frame(width: 72, height: 36)
                        .background {
                            if kind == item {
                                Capsule()
                                    .fill(item.color)
                                    .matchedGeometryEffect(id: "kind", in: kindSwitch)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
        .accessibilityElement(children: .contain)
    }

    /// 今日, or the picked day (tinted so it isn't missed). Tap to choose.
    private var dayButton: some View {
        Button {
            memoFocused = false
            pickingDay = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "calendar")
                    .font(.system(size: 14, weight: .semibold))
                Text(isToday ? "今日" : MoFormat.shortDay(day))
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
            }
            .foregroundStyle(isToday ? Color.primary : Color.white)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Capsule().fill(isToday ? Color.primary.opacity(0.06) : kind.color))
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isToday)
        .accessibilityLabel("記録する日：\(Fmt.fullDate(day))")
    }

    // MARK: Amount

    private var amountCard: some View {
        let spent = mo.records(on: day).filter { $0.kind == kind }.reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("¥")
                    .font(MoFormat.number(26))
                    .foregroundStyle(kind.color.opacity(0.7))
                Text(digits.isEmpty ? "0" : MoFormat.amount(Int(digits) ?? 0))
                    .font(MoFormat.number(54))
                    .monospacedDigit()
                    .foregroundStyle(digits.isEmpty ? kind.color.opacity(0.3) : kind.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.4)
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.2), value: digits)
                Spacer(minLength: 0)
            }
            .keyframeAnimator(initialValue: 0.0, trigger: shake) { content, x in
                content.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    LinearKeyframe(-10, duration: 0.05)
                    LinearKeyframe(10, duration: 0.05)
                    LinearKeyframe(-6, duration: 0.05)
                    LinearKeyframe(6, duration: 0.05)
                    LinearKeyframe(0, duration: 0.05)
                }
            }
            HStack {
                Text(digits.isEmpty ? "金額を入力してください" : "カテゴリをタップして記録")
                    .contentTransition(.opacity)
                Spacer()
                Text("\(isToday ? "今日" : "この日")の\(kind.label) ¥\(MoFormat.amount(spent))")
                    .monospacedDigit()
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(kind.color.opacity(0.08)))
    }

    // MARK: Categories

    private var categories: some View {
        let list = mo.categories(kind)
        let ready = !digits.isEmpty
        return VStack(spacing: 6) {
            HStack {
                Text("カテゴリ")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("編集") {
                    memoFocused = false
                    showCategoryList = true
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(kind.color)
            }
            .padding(.horizontal, 20)

            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 10) {
                    ForEach(list) { category in
                        MoCategoryTile(category: category, color: kind.color, ready: ready) { tap(category) }
                    }
                    Button { categorySheet = .new } label: {
                        VStack(spacing: 5) {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                                .frame(height: 50)
                                .overlay {
                                    Image(systemName: "plus")
                                        .font(.system(size: 20, weight: .semibold))
                                }
                            Text("追加")
                                .font(.system(size: 11, weight: .bold))
                                .lineLimit(1)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("カテゴリを追加")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
            .animation(.snappy, value: list)
            // Holding the categories opens their list too (edit, delete, reorder).
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                    memoFocused = false
                    showCategoryList = true
                }
            )
        }
        .frame(maxHeight: .infinity)
    }

    private var memoField: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.bubble")
                .foregroundStyle(.secondary)
            TextField("メモ（任意）", text: $memo)
                .font(.system(size: 15))
                .focused($memoFocused)
                .submitLabel(.done)
            if !memo.isEmpty {
                Button { memo = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 42)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .animation(.snappy, value: memo.isEmpty)
    }

    // MARK: Actions

    private func type(_ key: String) {
        let next = digits + key
        guard next.count <= Self.maxDigits else {
            shake += 1
            return
        }
        // No leading zeros: "0" then "5" is just 5.
        digits = Int(next).map { $0 == 0 ? "" : String($0) } ?? digits
    }

    private func deleteLast() {
        guard !digits.isEmpty else { return }
        digits.removeLast()
    }

    private func tap(_ category: MoCategory) {
        // A category before an amount: the amount shakes to say what's missing.
        guard let amount = Int(digits), amount > 0 else {
            shake += 1
            return
        }
        let record = mo.add(amount: amount, kind: kind, category: category,
                            memo: memo.trimmingCharacters(in: .whitespacesAndNewlines), date: recordDate)
        digits = ""
        memo = ""
        memoFocused = false
        saved += 1
        let when = isToday ? "" : "（\(MoFormat.shortDay(day))）"
        toasts.show("\(category.label)：¥\(MoFormat.amount(amount))\(when)") {
            _ = mo.delete(record.id)
        }
    }

    /// Now, or the picked day at this time of day (so its records keep an order).
    private var recordDate: Date {
        guard !isToday else { return .now }
        let calendar = CalendarMath.calendar
        let time = calendar.dateComponents([.hour, .minute, .second], from: .now)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: time.second ?? 0, of: day) ?? day
    }
}

/// Choosing the day to record on: today and yesterday at a tap, or any day on the calendar.
private struct MoDayPicker: View {
    @Binding var day: Date
    let color: Color

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    quick("今日", CalendarMath.startOfDay(.now))
                    quick("昨日", CalendarMath.addDays(-1, to: CalendarMath.startOfDay(.now)))
                }
                .padding(.horizontal, 16)
                DatePicker("日付", selection: Binding(get: { day }, set: { day = CalendarMath.startOfDay($0) }),
                           in: ...Date.now, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .tint(color)
                    .padding(.horizontal, 8)
            }
            .navigationTitle("記録する日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }
                        .buttonStyle(.glassProminent)
                        .tint(color)
                }
            }
        }
    }

    private func quick(_ title: String, _ target: Date) -> some View {
        let chosen = CalendarMath.isSameDay(day, target)
        return Button {
            day = target
            dismiss()
        } label: {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(chosen ? Color.white : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Capsule().fill(chosen ? color : Color.primary.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

/// One category: its icon on a tinted rounded square, and its name. Dimmed until there's an amount.
private struct MoCategoryTile: View {
    let category: MoCategory
    let color: Color
    let ready: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 5) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(ready ? color.opacity(0.14) : Color.primary.opacity(0.05))
                    .frame(height: 50)
                    .overlay {
                        MoIcon(name: category.icon, size: 24)
                            .foregroundStyle(ready ? color : Color.secondary)
                    }
                Text(category.label)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(ready ? Color.primary : Color.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MoTileStyle())
        .animation(.snappy(duration: 0.2), value: ready)
        .accessibilityLabel(category.label)
    }
}

/// A tile sinks a little while pressed.
private struct MoTileStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

/// 1–9, 00, 0 and delete on rounded keys. Holding delete clears everything.
private struct MoKeypad: View {
    let color: Color
    var onDigit: (String) -> Void
    var onDelete: () -> Void
    var onClear: () -> Void

    @State private var tick = 0

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "00", "0", "delete"]

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(0..<4, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        key(keys[row * 3 + column])
                    }
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tick)
    }

    @ViewBuilder
    private func key(_ key: String) -> some View {
        Button {
            tick += 1
            if key == "delete" { onDelete() } else { onDigit(key) }
        } label: {
            Group {
                if key == "delete" {
                    Image(systemName: "delete.left")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(color)
                } else {
                    Text(key)
                        .font(MoFormat.number(28))
                        .foregroundStyle(.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(key == "delete" ? color.opacity(0.1) : Color.primary.opacity(0.05)))
            .contentShape(Rectangle())
        }
        .buttonStyle(MoKeyStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.55).onEnded { _ in
                guard key == "delete" else { return }
                tick += 1
                onClear()
            }
        )
        .accessibilityLabel(key == "delete" ? "1文字消す" : key)
    }
}

/// Keys dip while pressed.
private struct MoKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
    }
}
