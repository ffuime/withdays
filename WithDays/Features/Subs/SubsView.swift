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
                Tab(value: SubsTab.list) {
                    SubsListView()
                } label: {
                    Image(systemName: "list.bullet.indent")
                        .accessibilityLabel("リスト")
                }
                Tab(value: SubsTab.renewals) {
                    SubsRenewalsView()
                } label: {
                    Image(systemName: "arrow.trianglehead.clockwise.rotate.90")
                        .accessibilityLabel("更新日")
                }
                Tab(value: SubsTab.simulate) {
                    SubsSimView()
                } label: {
                    Image(systemName: "scissors")
                        .accessibilityLabel("解約シミュ")
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
        ToolbarItem(placement: .topBarLeading) {
            Button(action: onCalendar) {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("カレンダーに戻る")
        }
        if tab == .list {
            ToolbarSpacer(.fixed, placement: .topBarLeading)
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.path.append(.history)
                } label: {
                    Image(systemName: "backward")
                }
                .accessibilityLabel("過去の記録")
            }
        }
    }
}

// MARK: Shared parts

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

/// Delete to the right, edit to the left; both go all the way.
struct SubsSwipes: ViewModifier {
    let sub: Sub
    @Environment(SubsRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                Button {
                    router.deleting = sub
                } label: {
                    Image(systemName: "minus.circle")
                }
                .tint(.red)
                .accessibilityLabel("削除")
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button {
                    router.edit(sub)
                } label: {
                    Image(systemName: "pencil.circle")
                }
                .tint(.blue)
                .accessibilityLabel("編集")
            }
    }
}
