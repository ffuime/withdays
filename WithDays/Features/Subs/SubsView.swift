import SwiftUI

enum SubsTab: Hashable {
    case list, renewals, simulate
}

enum SubsRoute: Hashable {
    case detail(String)
    case history
}

struct SubsEditing: Identifiable {
    let id = UUID()
    var sub: Sub
    var isNew: Bool
}

/// Where Subscribes is: the pushed screens, the editor and the delete question.
@MainActor
@Observable
final class SubsRouter {
    var path: [SubsRoute] = []
    var editing: SubsEditing?
    var deleting: Sub?

    func open(_ sub: Sub) { path.append(.detail(sub.id)) }
    func add() { editing = SubsEditing(sub: Sub(), isNew: true) }
    func edit(_ sub: Sub) { editing = SubsEditing(sub: sub, isNew: false) }
}

/// Subscribes: the subscriptions list, their renewal calendar and a cancellation simulator.
struct SubsView: View {
    var onCalendar: () -> Void

    @State private var store = SubsStore()
    @State private var router = SubsRouter()
    @State private var tab = SubsTab.list
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        return NavigationStack(path: $router.path) {
            TabView(selection: $tab) {
                Tab("リスト", systemImage: "list.bullet.indent", value: SubsTab.list) {
                    SubsListView()
                }
                Tab("更新日", systemImage: "arrow.trianglehead.clockwise.rotate.90", value: SubsTab.renewals) {
                    SubsRenewalsView()
                }
                Tab("解約シミュ", systemImage: "scissors", value: SubsTab.simulate) {
                    SubsSimView()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .navigationDestination(for: SubsRoute.self) { route in
                switch route {
                case .detail(let id): SubsDetailView(id: id)
                case .history: SubsHistoryView()
                }
            }
        }
        .environment(store)
        .environment(router)
        .sheet(item: $router.editing) { editing in
            SubsEditor(sub: editing.sub, isNew: editing.isNew) { store.save($0) }
                .environment(store)
        }
        .alert(
            "「\(router.deleting?.name ?? "")」を削除しますか？",
            isPresented: Binding(get: { router.deleting != nil }, set: { if !$0 { router.deleting = nil } }),
            presenting: router.deleting
        ) { sub in
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                withAnimation(.snappy) {
                    router.path.removeAll { $0 == .detail(sub.id) }
                    store.delete(sub.id)
                }
            }
        } message: { _ in
            Text("これまでの支払いの記録は残ります。")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { store.catchUp() }
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        // On the dark cards of リスト and 解約シミュ the pills are tinted and their symbols white.
        ToolbarItem(placement: .topBarLeading) {
            SubsPill(symbol: "chevron.left", onCard: tab != .renewals, action: onCalendar)
                .accessibilityLabel("カレンダーに戻る")
        }
        .sharedBackgroundVisibility(.hidden)
        if tab == .list {
            ToolbarItem(placement: .topBarLeading) {
                SubsPill(symbol: "backward", onCard: true) { router.path.append(.history) }
                    .accessibilityLabel("過去の記録")
            }
            .sharedBackgroundVisibility(.hidden)
        }
    }
}

// MARK: Shared parts

/// A round glass button in the top bar, the size of the system's.
struct SubsPill: View {
    let symbol: String
    var onCard = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(onCard ? Color.white : Color.primary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(onCard ? .regular.tint(SubsListView.cardColors[0].opacity(0.55)).interactive() : .regular.interactive(), in: .circle)
        .animation(.snappy, value: onCard)
    }
}

/// The dark card stuck to the top of a list (今月の合計支出, 解約シミュ): its color is drawn behind the list,
/// from the screen's top to the card's bottom, so it reaches under the bar and stretches when pulled down.
struct SubsTopCard: ViewModifier {
    let cardHeight: CGFloat
    @State private var offset: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, y in offset = y }
            .background(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: 32, bottomTrailingRadius: 32, style: .continuous)
                    .fill(LinearGradient(colors: SubsListView.cardColors, startPoint: .top, endPoint: .bottom))
                    .frame(height: max(cardHeight - offset, 0))
                    .frame(maxWidth: .infinity)
                    .ignoresSafeArea()
            }
    }
}

/// A subscription's icon: the app's (Screen Time), its own picture, or a symbol on its color.
struct SubsIconView: View {
    let sub: Sub
    var size: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        Group {
            if let token = SubsScreenTime.token(sub.appToken), SubsScreenTime.approved {
                SubsAppIcon(token: token, size: size)
            } else if let data = sub.image, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(shape)
            } else {
                SubsSymbolIcon(symbol: sub.symbol, tint: sub.tint, size: size)
            }
        }
        .frame(width: size, height: size)
    }
}

struct SubsSymbolIcon: View {
    let symbol: String
    let tint: UInt32
    var size: CGFloat = 40

    var body: some View {
        let color = Color(uiColor: UIColor(hex: tint))
        Image(systemName: symbol)
            .font(.system(size: size * 0.46, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .fill(LinearGradient(colors: [color.opacity(0.85), color], startPoint: .top, endPoint: .bottom))
            )
    }
}

/// ¥3,000/月: the price bold, the cycle light.
struct SubsPriceText: View {
    let price: Int
    var suffix = ""
    var size: CGFloat = 17

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
            Text(SubsFormat.yen(price))
                .font(SubsFormat.number(size, .bold))
                .monospacedDigit()
                .foregroundStyle(.primary)
            if !suffix.isEmpty {
                Text(suffix)
                    .font(.system(size: size * 0.72, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// One subscription in the list.
struct SubsRow: View {
    let sub: Sub

    var body: some View {
        HStack(spacing: 12) {
            SubsIconView(sub: sub, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(sub.name)
                    .font(.system(size: 16, weight: .bold))
                    .lineLimit(1)
                if sub.inTrial {
                    Text("無料トライアル 〜\(SubsFormat.day(sub.trialEnd))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
            Spacer(minLength: 8)
            SubsPriceText(price: sub.price, suffix: sub.cycle.suffix)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Swipe right to edit, left to delete (asks first).
struct SubsSwipes: ViewModifier {
    let sub: Sub
    @Environment(SubsRouter.self) private var router

    func body(content: Content) -> some View {
        content
            // Swiped all the way, the symbol follows the finger (the system's full swipe).
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    router.edit(sub)
                } label: {
                    Label("編集", systemImage: "pencil.circle")
                        .labelStyle(.iconOnly)
                }
                .tint(.blue)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) {
                    router.deleting = sub
                } label: {
                    Label("削除", systemImage: "minus.circle")
                        .labelStyle(.iconOnly)
                }
                .tint(.red)
            }
    }
}
