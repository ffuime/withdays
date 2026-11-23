import SwiftUI

/// リスト: this month's total on a card stuck to the top, then the subscriptions. ＋ adds one.
struct SubsListView: View {
    @Environment(SubsStore.self) private var store
    @Environment(SubsRouter.self) private var router

    /// The card's color is drawn behind the list, from the screen's top to the card's bottom,
    /// so it reaches under the bar and stretches when pulled down.
    @State private var offset: CGFloat = 0
    @State private var cardHeight: CGFloat = 0

    static let cardColors = [Color(uiColor: UIColor(hex: 0x0B3A5C)), Color(uiColor: UIColor(hex: 0x14679A))]

    var body: some View {
        List {
            card
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { cardHeight = $0 }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)

            sortBar
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            ForEach(store.sorted) { sub in
                SubsRow(sub: sub)
                    .onTapGesture { router.open(sub) }
                    .modifier(SubsSwipes(sub: sub))
                    .listRowSeparator(.hidden)
            }

            if store.subs.isEmpty {
                Text("右下の＋からサブスクを追加しましょう")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            Color.clear.frame(height: 72)
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in offset = y }
        .background(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32, style: .continuous)
                .fill(LinearGradient(colors: Self.cardColors, startPoint: .top, endPoint: .bottom))
                .frame(height: max(cardHeight - offset, 0))
                .frame(maxWidth: .infinity)
                .ignoresSafeArea()
        }
        .overlay(alignment: .bottomTrailing) {
            Button(action: router.add) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.circle)
            .accessibilityLabel("サブスクを追加")
            .padding(20)
        }
        .animation(.snappy, value: store.sorted.map(\.id))
    }

    private var card: some View {
        let total = store.monthlyTotal
        return VStack(spacing: 4) {
            Text("今月の合計支出")
                .font(.system(size: 15, weight: .medium))
                .opacity(0.9)
            Text(SubsFormat.yen(total))
                .font(SubsFormat.number(64, .regular))
                .monospacedDigit()
                .contentTransition(.numericText(value: total))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(SubsFormat.yen(total * 12))
                    .font(SubsFormat.number(19, .medium))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: total * 12))
                Text("/年")
                    .font(.system(size: 14, weight: .medium))
            }
            .opacity(0.9)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.top, 16)
        .padding(.bottom, 30)
        .animation(.snappy, value: total)
    }

    private var sortBar: some View {
        @Bindable var store = store
        return HStack {
            Text("\(store.subs.count)件")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Menu {
                Picker("並び順", selection: $store.sort) {
                    ForEach(SubsSort.allCases) { Text($0.label).tag($0) }
                }
                Divider()
                Toggle("逆順", isOn: $store.reversed)
            } label: {
                HStack(spacing: 4) {
                    Text(store.sort.label)
                    Image(systemName: "arrow.up.arrow.down")
                }
                .font(.system(size: 13, weight: .semibold))
            }
        }
        .padding(.top, 6)
    }
}
