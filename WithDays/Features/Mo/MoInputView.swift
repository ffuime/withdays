import SwiftUI

/// Enter an amount on the keypad, then tap a category to record it (now).
/// Holding the categories opens their list to edit, delete and reorder them.
struct MoInputView: View {
    @Binding var kind: MoKind
    @Environment(\.backToWithDays) private var backToWithDays

    @Environment(MoStore.self) private var mo
    @Environment(ToastCenter.self) private var toasts
    @State private var digits = ""
    @State private var memo = ""
    @State private var categorySheet: MoCategorySheet.Target?
    @State private var showCategoryList = false
    @State private var shake = 0
    @State private var saved = 0
    @FocusState private var memoFocused: Bool
    @State private var amountWidth: CGFloat = 0

    /// Up to 15 digits; past 8 the amount shrinks to stay on one line.
    private static let maxDigits = 15

    var body: some View {
        VStack(spacing: 0) {
            kindPicker
                .padding(.top, 12)

            amountView
                .padding(.top, 21)

            categoryStrip
                .padding(.top, 18)

            memoField
                .padding(.horizontal, 20)
                .padding(.top, 10)

            MoKeypad(onDigit: type, onDelete: deleteLast, onClear: { digits = "" })
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 18)
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
    }

    // MARK: Parts

    private var kindPicker: some View {
        HStack(spacing: 10) {
            ForEach(MoKind.allCases, id: \.self) { item in
                Button {
                    withAnimation(.snappy) { kind = item }
                } label: {
                    Label(item.label, systemImage: item == .expense ? "arrow.up" : "arrow.down")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(kind == item ? Color.white : item.color)
                        .padding(.horizontal, 18)
                        .frame(height: 38)
                        .background(Capsule().fill(kind == item ? item.color : item.color.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Sized so eight digits (with their commas) just fill the width; longer amounts shrink.
    private var amountView: some View {
        let size = Self.amountFontSize(width: amountWidth)
        return VStack(spacing: 0) {
            Text(digits.isEmpty ? "-" : MoFormat.amount(Int(digits) ?? 0))
                .font(MoFormat.number(size))
                .monospacedDigit()
                .foregroundStyle(kind.color)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.2), value: digits)
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
                .frame(maxWidth: .infinity)
                .frame(height: size * 1.15)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { amountWidth = $0 }
            Text(digits.isEmpty ? "金額を入力" : "カテゴリを選択")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, 16)
    }

    private static func amountFontSize(width: CGFloat) -> CGFloat {
        guard width > 0 else { return 80 }
        let base: CGFloat = 100
        let plain = UIFont.systemFont(ofSize: base, weight: .semibold)
        let font = UIFont(descriptor: plain.fontDescriptor.withDesign(.rounded) ?? plain.fontDescriptor, size: base)
        let measured = ("88,888,888" as NSString).size(withAttributes: [.font: font]).width
        return floor(base * width / measured)
    }

    private var categoryStrip: some View {
        let categories = mo.categories(kind)
        let enabled = !digits.isEmpty
        return ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(categories) { category in
                    MoCategoryTile(category: category, kind: kind, enabled: enabled) { tap(category) }
                        .containerRelativeFrame(.horizontal, count: 21, span: 5, spacing: 12)
                }
                Button { categorySheet = .new } label: {
                    VStack(spacing: 6) {
                        Circle()
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 5]))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                Image(systemName: "plus")
                                    .font(.system(size: 28, weight: .semibold))
                            }
                        Text("カテゴリ追加")
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .containerRelativeFrame(.horizontal, count: 21, span: 5, spacing: 12)
            }
            .padding(.vertical, 6)
            .scrollTargetLayout()
        }
        // About 4.2 circles across, so it shows there are more to the side.
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .animation(.snappy, value: categories)
        // Holding anywhere on the categories opens their list (edit, delete, reorder).
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                memoFocused = false
                showCategoryList = true
            }
        )
    }

    private var memoField: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .foregroundStyle(.secondary)
            TextField("任意のメモを入力…", text: $memo)
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
        .frame(height: 44)
        .background(Capsule().fill(Color.primary.opacity(0.035)))
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
        guard let amount = Int(digits), amount > 0 else { return }
        let record = mo.add(amount: amount, kind: kind, category: category, memo: memo.trimmingCharacters(in: .whitespacesAndNewlines))
        digits = ""
        memo = ""
        memoFocused = false
        saved += 1
        toasts.show("\(category.label)：¥\(MoFormat.amount(amount))") {
            _ = mo.delete(record.id)
        }
    }
}

/// One category: a circle filling the tile's width, and its name. Disabled until an amount is entered.
private struct MoCategoryTile: View {
    let category: MoCategory
    let kind: MoKind
    let enabled: Bool
    var onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Circle()
                    .fill(kind.color.opacity(0.1))
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        MoIcon(name: category.icon, size: 36)
                            .foregroundStyle(kind.color)
                    }
                Text(category.label)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(MoTileStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
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

/// 1–9, 00, 0 and delete in a grid. Holding delete clears everything.
private struct MoKeypad: View {
    var onDigit: (String) -> Void
    var onDelete: () -> Void
    var onClear: () -> Void

    @State private var tick = 0

    private let keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "00", "0", "delete"]

    var body: some View {
        Grid(horizontalSpacing: 0, verticalSpacing: 0) {
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
                        .font(.system(size: 26, weight: .medium))
                        .foregroundStyle(Color.moExpense.opacity(0.75))
                } else {
                    Text(key)
                        .font(MoFormat.number(34))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }
}

/// Keys grow while pressed, as on the web app.
private struct MoKeyStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 1.45 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
