import SwiftUI

enum ToocTab: Hashable { case talk, friends, me }

enum ToocRoute: Hashable {
    case room(String)
    case search
    case notices
    case settings
    case settingsAccount
    case settingsPassword
    case settingsNotifications
    case settingsHidden
    case settingsTalk
}

enum ToocSheet: Identifiable, Hashable {
    case qr(ToocQRSheet)
    case newTalk
    case newGroup
    case find(String)
    case profile(String)
    case editProfile

    var id: String {
        switch self {
        case .qr(let start): "qr-\(start.rawValue)"
        case .newTalk: "newTalk"
        case .newGroup: "newGroup"
        case .find(let id): "find-\(id)"
        case .profile(let id): "profile-\(id)"
        case .editProfile: "editProfile"
        }
    }
}

/// Where tooc is: the pushed screens over the tabs, the tab, selection, and the sheet on top.
@MainActor
@Observable
final class ToocRouter {
    var path: [ToocRoute] = []
    var tab = ToocTab.talk {
        didSet { if oldValue != tab { endSelecting() } }
    }
    var selecting = false
    var selection: Set<String> = []
    var sheet: ToocSheet? = nil

    func open(room id: String) {
        sheet = nil
        path = [.room(id)]
    }

    func startSelecting() {
        selection = []
        selecting = true
    }

    func endSelecting() {
        selecting = false
        selection = []
    }

    func reset() {
        path = []
        sheet = nil
        tab = .talk
        endSelecting()
    }
}

/// tooc: sign-in, then three tabs (トーク・友だち・じぶん) inside one navigation stack, so the top pills morph
/// as the tab changes. The top-left back button returns to the calendar.
struct ToocRootView: View {
    var onCalendar: () -> Void

    @State private var store = ToocStore()
    @State private var router = ToocRouter()

    var body: some View {
        Group {
            if store.signedIn {
                main
            } else {
                ToocLoginView(onCalendar: onCalendar)
            }
        }
        .environment(store)
        .environment(router)
        .onChange(of: store.signedIn) { router.reset() }
        .task {
            // Scheduled messages go out when their time comes.
            while !Task.isCancelled {
                store.deliverDue()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onDisappear { store.flush() }
    }

    private var main: some View {
        @Bindable var router = router
        return NavigationStack(path: $router.path) {
            tabs
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .navigationDestination(for: ToocRoute.self) { ToocDestination(route: $0) }
        }
        .sheet(item: $router.sheet) { ToocSheetView(sheet: $0) }
        .overlay(alignment: .top) { ToocBanner() }
    }

    private var tabs: some View {
        let selection = Binding(get: { router.tab }, set: { tab in withAnimation(.snappy) { router.tab = tab } })
        return TabView(selection: selection) {
            Tab(value: ToocTab.talk) {
                ToocTalkListView()
            } label: {
                tabLabel("トーク", "message", .talk)
            }
            .badge(store.unreadTotal)

            Tab(value: ToocTab.friends) {
                ToocFriendListView()
            } label: {
                tabLabel("友だち", "person.2", .friends)
            }

            Tab(value: ToocTab.me) {
                ToocMeView()
            } label: {
                tabLabel("じぶん", "face.smiling", .me)
            }
        }
        // Outlined everywhere; only the tab under the glass names its filled symbol.
        .environment(\.symbolVariants, .none)
    }

    private func tabLabel(_ title: String, _ symbol: String, _ tab: ToocTab) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: router.tab == tab ? "\(symbol).fill" : symbol)
                .environment(\.symbolVariants, .none)
        }
        .environment(\.symbolVariants, .none)
    }

    // MARK: Top bar, shared by the tabs so its pills morph between them

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            if router.selecting {
                Button("完了") { withAnimation(.snappy) { router.endSelecting() } }
                    .fontWeight(.semibold)
            } else {
                Button(action: onCalendar) {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("カレンダーに戻る")
                switch router.tab {
                case .talk: ToocTalkSortMenu()
                case .friends: ToocFriendSortMenu()
                case .me: EmptyView()
                }
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if router.selecting {
                selectionActions
            } else if router.tab == .me {
                Menu {
                    ToocAddFriendSection()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("友だち追加")
                Button { router.path.append(.notices) } label: {
                    Image(systemName: store.unseenNotices > 0 ? "bell.badge" : "bell")
                }
                .accessibilityLabel("お知らせ")
                Button { router.path.append(.settings) } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("設定")
            } else {
                Button { router.path.append(.search) } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel("検索")
                ToocPlusMenu()
                Menu {
                    Button("toocを選択", systemImage: "checkmark.circle") {
                        withAnimation(.snappy) { router.startSelecting() }
                    }
                    Button("すべて既読にする", systemImage: "checkmark.message") { store.markAllRead() }
                    Button("設定", systemImage: "gearshape") { router.path.append(.settings) }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("その他")
            }
        }
    }

    /// What can be done to the chosen talks or friends.
    @ViewBuilder
    private var selectionActions: some View {
        let chosen = router.selection
        if router.tab == .friends {
            Button { act { chosen.forEach(store.toggleFavorite) } } label: { Image(systemName: "star") }
                .accessibilityLabel("お気に入り")
            Button { act { chosen.forEach(store.hideFriend) } } label: { Image(systemName: "eye.slash") }
                .accessibilityLabel("非表示")
            Button { act { chosen.forEach(store.block) } } label: { Image(systemName: "nosign") }
                .accessibilityLabel("ブロック")
        } else {
            Button { act { chosen.forEach(store.markRead) } } label: { Image(systemName: "checkmark.message") }
                .accessibilityLabel("既読にする")
            Button { act { chosen.forEach { id in store.update(id) { $0.hidden = true } } } } label: { Image(systemName: "eye.slash") }
                .accessibilityLabel("非表示")
            Button(role: .destructive) { act { chosen.forEach(store.delete) } } label: { Image(systemName: "trash") }
                .accessibilityLabel("削除")
        }
    }

    private func act(_ change: () -> Void) {
        withAnimation(.snappy) {
            change()
            router.endSelecting()
        }
    }
}

/// The screens pushed over the tabs.
private struct ToocDestination: View {
    let route: ToocRoute

    var body: some View {
        switch route {
        case .room(let id): ToocRoomView(roomID: id)
        case .search: ToocSearchView()
        case .notices: ToocNoticesView()
        case .settings: ToocSettingsView()
        case .settingsAccount: ToocAccountSettingsView()
        case .settingsPassword: ToocPasswordView()
        case .settingsNotifications: ToocNotificationSettingsView()
        case .settingsHidden: ToocHiddenSettingsView()
        case .settingsTalk: ToocTalkSettingsView()
        }
    }
}

private struct ToocSheetView: View {
    let sheet: ToocSheet
    @Environment(ToocStore.self) private var store

    var body: some View {
        switch sheet {
        case .qr(let start): ToocQRView(start: start)
        case .newTalk: ToocNewTalkView(group: false)
        case .newGroup: ToocNewTalkView(group: true)
        case .find(let id): ToocFindView(initialID: id)
        case .profile(let id): ToocProfileSheet(userID: id)
        case .editProfile: ToocEditProfileView()
        }
    }
}

/// The ＋ menu: start a talk or a group, and the ways to add a friend.
struct ToocPlusMenu: View {
    @Environment(ToocRouter.self) private var router

    var body: some View {
        Menu {
            ControlGroup {
                Button("トークルームを作成", systemImage: "plus.message") { router.sheet = .newTalk }
                Button("グループを作成", systemImage: "person.2.badge.plus") { router.sheet = .newGroup }
            }
            ToocAddFriendSection()
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("追加")
    }
}

struct ToocAddFriendSection: View {
    @Environment(ToocRouter.self) private var router

    var body: some View {
        Section("友だち追加") {
            Button("MyQRを表示", systemImage: "qrcode") { router.sheet = .qr(.show) }
            Button("MyQRをスキャン", systemImage: "qrcode.viewfinder") { router.sheet = .qr(.scan) }
            Button("toocIDで検索", systemImage: "at") { router.sheet = .find("") }
        }
    }
}

struct ToocTalkSortMenu: View {
    @Environment(ToocStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Menu {
            Section {
                Toggle("お気に入りを優先", isOn: $store.favoritesFirst)
                Toggle("未読メッセージを優先", isOn: $store.unreadFirst)
            }
            Section {
                Picker("並び替え", selection: $store.talkSort) {
                    ForEach([ToocTalkSort.added, .conversation, .profile]) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("並び替え")
    }
}

struct ToocFriendSortMenu: View {
    @Environment(ToocStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Menu {
            Picker("並び替え", selection: $store.friendSort) {
                ForEach(ToocTalkSort.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("並び替え")
    }
}

/// A message or event arriving while you're elsewhere: a glass banner at the top for a few seconds.
private struct ToocBanner: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router

    var body: some View {
        ZStack {
            if let notice = store.banner {
                Button {
                    store.banner = nil
                    if let room = notice.roomID {
                        router.open(room: room)
                    } else if let user = notice.userID {
                        router.sheet = .profile(user)
                    }
                } label: {
                    HStack(spacing: 10) {
                        if let id = notice.userID, let user = store.user(id) {
                            ToocAvatar(user: user, size: 36)
                        } else {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(Color.brand)
                                .frame(width: 36, height: 36)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(notice.title)
                                .font(.subheadline.bold())
                                .lineLimit(1)
                            Text(store.settings.showContent ? notice.body : "新しいお知らせがあります")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                .padding(.horizontal, 12)
                .gesture(DragGesture(minimumDistance: 10).onEnded { value in
                    if value.translation.height < 0 { withAnimation(.snappy) { store.banner = nil } }
                })
                .transition(.move(edge: .top).combined(with: .opacity))
                .task(id: notice.id) {
                    try? await Task.sleep(for: .seconds(3.5))
                    withAnimation(.snappy) { if store.banner?.id == notice.id { store.banner = nil } }
                }
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: store.banner?.id)
    }
}
