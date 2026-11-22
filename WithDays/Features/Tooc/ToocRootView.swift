import SwiftUI

enum ToocTab: Hashable { case talk, friends, me }

enum ToocRoute: Hashable {
    case room(String)
    case search
    case notices
    case scheduled
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

/// Something that needs a yes first: hiding, deleting, blocking.
enum ToocConfirm: Identifiable, Hashable {
    case hideRooms(Set<String>)
    case deleteRooms(Set<String>)
    case hideFriends(Set<String>)
    case blockFriends(Set<String>)

    var id: String { "\(self)" }

    var title: String {
        switch self {
        case .hideRooms(let ids): ids.count > 1 ? "\(ids.count)件のトークを非表示にしますか？" : "トークを非表示にしますか？"
        case .deleteRooms(let ids): ids.count > 1 ? "\(ids.count)件のトークを削除しますか？" : "トークを削除しますか？"
        case .hideFriends(let ids): ids.count > 1 ? "\(ids.count)人を非表示にしますか？" : "友だちを非表示にしますか？"
        case .blockFriends(let ids): ids.count > 1 ? "\(ids.count)人をブロックしますか？" : "ブロックしますか？"
        }
    }

    var message: String {
        switch self {
        case .deleteRooms: "元に戻せません。"
        default: ""
        }
    }

    var button: String {
        switch self {
        case .hideRooms, .hideFriends: "非表示"
        case .deleteRooms: "削除"
        case .blockFriends: "ブロック"
        }
    }

    @MainActor
    func perform(_ store: ToocStore) {
        switch self {
        case .hideRooms(let ids): ids.forEach { id in store.update(id) { $0.hidden = true } }
        case .deleteRooms(let ids): ids.forEach(store.delete)
        case .hideFriends(let ids): ids.forEach(store.hideFriend)
        case .blockFriends(let ids): ids.forEach(store.block)
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
    var filter = ToocTalkFilter.all
    var selecting = false
    var selection: Set<String> = []
    var sheet: ToocSheet? = nil
    var confirm: ToocConfirm? = nil
    /// A room to open with the keyboard up.
    var focusRoomID: String? = nil

    func open(room id: String, focus: Bool = false) {
        sheet = nil
        focusRoomID = focus ? id : nil
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
        confirm = nil
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
    @State private var welcome = false

    var body: some View {
        let theme = store.theme
        Group {
            if store.signedIn {
                main
            } else {
                ToocLoginView(onCalendar: onCalendar)
            }
        }
        .environment(store)
        .environment(router)
        .environment(\.toocTheme, theme)
        .tint(theme.accent)
        .environment(\.colorScheme, theme.dark ? .dark : colorScheme)
        .overlay {
            if welcome {
                ToocWelcomeView(name: store.me.name) { welcome = false }
                    .environment(\.toocTheme, store.theme)
            }
        }
        .onChange(of: store.signedIn) { _, signedIn in
            router.reset()
            if signedIn { welcome = true }
        }
        .onAppear {
            if store.settings.notifications { ToocNotifications.requestAuthorization() }
            if let room = ToocNotifications.takePendingRoom(), store.signedIn { router.open(room: room) }
        }
        .onReceive(NotificationCenter.default.publisher(for: ToocNotifications.openRoom)) { _ in
            if let room = ToocNotifications.takePendingRoom(), store.signedIn { router.open(room: room) }
        }
        .task {
            // Scheduled messages go out when their time comes.
            while !Task.isCancelled {
                store.deliverDue()
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onDisappear { store.flush() }
    }

    @Environment(\.colorScheme) private var colorScheme

    private var main: some View {
        @Bindable var router = router
        return NavigationStack(path: $router.path) {
            tabs
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .navigationDestination(for: ToocRoute.self) { ToocDestination(route: $0) }
        }
        .sheet(item: $router.sheet) { ToocSheetView(sheet: $0) }
        .alert(router.confirm?.title ?? "", isPresented: Binding(
            get: { router.confirm != nil }, set: { if !$0 { router.confirm = nil } }
        ), presenting: router.confirm) { confirm in
            Button("キャンセル", role: .cancel) {}
            Button(confirm.button, role: .destructive) {
                withAnimation(.snappy) {
                    confirm.perform(store)
                    router.endSelecting()
                }
            }
        } message: { confirm in
            if !confirm.message.isEmpty { Text(confirm.message) }
        }
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
        // Outlined everywhere; only the chosen tab names its filled symbol.
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
                    .foregroundStyle(store.theme.accent)
            } else {
                Button(action: onCalendar) { ToocBarIcon("chevron.left") }
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
                    ToocBarIcon("plus")
                }
                .accessibilityLabel("友だち追加")
                Button { router.path.append(.notices) } label: {
                    ToocBarIcon(store.unseenNotices > 0 ? "bell.badge" : "bell")
                }
                .accessibilityLabel("お知らせ")
                Button { router.path.append(.settings) } label: { ToocBarIcon("gearshape") }
                    .accessibilityLabel("設定")
            } else {
                Button { router.path.append(.search) } label: { ToocBarIcon("magnifyingglass") }
                    .accessibilityLabel("検索")
                ToocPlusMenu()
                Menu {
                    Button("toocを選択", systemImage: "checkmark.circle") {
                        withAnimation(.snappy) { router.startSelecting() }
                    }
                    Button("すべて既読にする", systemImage: "checkmark.message") { store.markAllRead() }
                    Button("設定", systemImage: "gearshape") { router.path.append(.settings) }
                } label: {
                    ToocBarIcon("ellipsis")
                }
                .accessibilityLabel("その他")
            }
        }
    }

    /// What can be done to the chosen talks or friends. Hiding, deleting and blocking ask first.
    @ViewBuilder
    private var selectionActions: some View {
        let chosen = router.selection
        if router.tab == .friends {
            Button {
                withAnimation(.snappy) {
                    chosen.forEach(store.toggleFavorite)
                    router.endSelecting()
                }
            } label: { ToocBarIcon("star") }
                .accessibilityLabel("お気に入り")
                .disabled(chosen.isEmpty)
            Button { router.confirm = .hideFriends(chosen) } label: { ToocBarIcon("eye.slash") }
                .accessibilityLabel("非表示")
                .disabled(chosen.isEmpty)
            Button { router.confirm = .blockFriends(chosen) } label: { ToocBarIcon("nosign") }
                .accessibilityLabel("ブロック")
                .disabled(chosen.isEmpty)
        } else {
            Button {
                withAnimation(.snappy) {
                    chosen.forEach(store.markRead)
                    router.endSelecting()
                }
            } label: { ToocBarIcon("checkmark.message") }
                .accessibilityLabel("既読にする")
                .disabled(chosen.isEmpty)
            Button { router.confirm = .hideRooms(chosen) } label: { ToocBarIcon("eye.slash") }
                .accessibilityLabel("非表示")
                .disabled(chosen.isEmpty)
            Button { router.confirm = .deleteRooms(chosen) } label: { ToocBarIcon("trash") }
                .accessibilityLabel("削除")
                .disabled(chosen.isEmpty)
        }
    }
}

/// A top-bar symbol: a little smaller than the system's, in the theme's colour.
struct ToocBarIcon: View {
    let name: String
    @Environment(\.toocTheme) private var theme

    init(_ name: String) { self.name = name }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(theme.accent)
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
        case .scheduled: ToocScheduledView()
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
            ToocBarIcon("plus")
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
                Toggle("お気に入りを優先", isOn: $store.favoritesFirst.animation(.snappy))
                Toggle("未読メッセージを優先", isOn: $store.unreadFirst.animation(.snappy))
            }
            Section {
                Picker("並び替え", selection: $store.talkSort.animation(.snappy)) {
                    ForEach([ToocTalkSort.added, .conversation, .profile]) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            }
        } label: {
            ToocBarIcon("arrow.up.arrow.down")
        }
        .accessibilityLabel("並び替え")
    }
}

struct ToocFriendSortMenu: View {
    @Environment(ToocStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Menu {
            Picker("並び替え", selection: $store.friendSort.animation(.snappy)) {
                ForEach(ToocTalkSort.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            ToocBarIcon("arrow.up.arrow.down")
        }
        .accessibilityLabel("並び替え")
    }
}

/// A message or event arriving while you're elsewhere: a glass banner at the top for a few seconds.
private struct ToocBanner: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme

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
                                .foregroundStyle(theme.accent)
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
