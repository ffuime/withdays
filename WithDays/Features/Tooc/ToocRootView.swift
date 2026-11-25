import SwiftUI

enum ToocTab: Hashable { case talk, me }

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
    case settingsEmail
    case settingsPhone
    case settingsFont
    case settingsAbout
    case settingsChangelog
    case settingsCredits
    case friends
    case later
}

enum ToocSheet: Identifiable, Hashable {
    case qr(ToocQRSheet)
    case newTalk
    case newGroup
    case find(String)
    case profile(String)
    case editProfile
    case accounts
    case notes(String, String?)
    case albums(String, String?)

    var id: String {
        switch self {
        case .qr(let start): "qr-\(start.rawValue)"
        case .newTalk: "newTalk"
        case .newGroup: "newGroup"
        case .find(let id): "find-\(id)"
        case .profile(let id): "profile-\(id)"
        case .editProfile: "editProfile"
        case .accounts: "accounts"
        case .notes(let room, let note): "notes-\(room)-\(note ?? "")"
        case .albums(let room, let album): "albums-\(room)-\(album ?? "")"
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
    /// A message to show (scrolled to and lit up) when its room opens.
    var highlightMessage: UUID? = nil

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
    /// Back to WithDays' calendar; nil in the tooc app (nothing to go back to).
    var onCalendar: (() -> Void)? = nil

    @State private var store = ToocStore()
    @State private var router = ToocRouter()
    @State private var welcome = false
    /// The iPhone's own light / dark (for 自動).
    @State private var systemDark = ToocRootView.deviceDark

    static var deviceDark: Bool { UIScreen.main.traitCollection.userInterfaceStyle == .dark }

    private var scheme: ColorScheme {
        // Signed in, the theme decides; before that, the iPhone's own.
        if store.signedIn { return store.settings.theme.colorScheme }
        return systemDark ? .dark : .light
    }
    /// Who you were when a switch began, for the overlay's first face.
    @State private var switchFrom: ToocUser?

    var body: some View {
        let theme = store.theme
        // Signing out (or deleting the account) fades and settles into the sign-in form, and back.
        Group {
            if store.signedIn {
                main
                    .transition(.asymmetric(insertion: .opacity,
                                            removal: .opacity.combined(with: .scale(scale: 0.94))))
            } else if store.starting {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ToocLoginView(onCalendar: onCalendar)
                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.04)), removal: .opacity))
            }
        }
        .id(scheme)
        .animation(.smooth(duration: 0.5), value: store.signedIn)
        .environment(store)
        .environment(router)
        .environment(\.toocTheme, theme)
        .toocFont(.body)
        .environment(\.toocFontFamily, ToocFontLibrary.shared.family(store.settings.font))
        .tint(theme.accent)
        // ライト・ダーク・自動 decided here (自動 = the iPhone's own setting, read from the screen so nothing around
        // tooc can change it), then given to SwiftUI and set on the window alike, so text, lists, bars and sheets agree.
        .environment(\.colorScheme, scheme)
        .background(ToocInterfaceStyle(scheme: scheme))
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            systemDark = Self.deviceDark
        }
        // No scaling or blurring of the screen itself while switching: done to the whole TabView, it left the
        // tab bar and top bar laid out shrunk toward the middle. The overlay's own frosted layer covers it instead.
        .overlay {
            if welcome {
                ToocWelcomeView(name: greetingName) { welcome = false }
                    .environment(\.toocTheme, store.theme)
            }
        }
        .overlay {
            if let user = store.farewell {
                ToocGoodbyeView(user: user) { store.farewell = nil }
                    .environment(store)
                    .environment(\.toocTheme, store.theme)
            }
        }
        .overlay {
            if let to = store.switchingTo, let from = switchFrom {
                ToocSwitchOverlay(
                    from: from, to: to, ready: store.account == to.id,
                    onMidway: { router.reset() },
                    onDone: {
                        store.switchingTo = nil
                        switchFrom = nil
                    }
                )
                .environment(\.toocTheme, store.theme)
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.switchingTo?.id)
        .onChange(of: store.switchingTo?.id) { _, id in
            if id != nil, switchFrom == nil { switchFrom = store.me }
            if id == nil { switchFrom = nil }
        }
        .alert("切り替えられませんでした", isPresented: Binding(get: { store.switchError != nil },
                                                        set: { if !$0 { store.switchError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.switchError ?? "")
        }
        .onChange(of: store.signedIn) { _, signedIn in
            router.reset()
            if signedIn { welcome = true }
        }
        .onAppear {
            // Opening tooc already signed in says hello too (as signing in does).
            if store.signedIn { welcome = true }
            if store.settings.notifications { ToocNotifications.requestAuthorization() }
            if let room = ToocNotifications.takePendingRoom(), store.signedIn { router.open(room: room) }
            if let id = ToocNotifications.takePendingFriend(), store.signedIn { router.sheet = .find(id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: ToocNotifications.openRoom)) { _ in
            if let room = ToocNotifications.takePendingRoom(), store.signedIn { router.open(room: room) }
            if let id = ToocNotifications.takePendingFriend(), store.signedIn { router.sheet = .find(id) }
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

    /// The name to greet: the profile's once it has arrived, the one this device remembers before that.
    private var greetingName: String {
        if store.me.name != store.me.id { return store.me.name }
        return ToocAccounts.saved.first { $0.id == store.me.id }?.name ?? store.me.name
    }


    private var main: some View {
        @Bindable var router = router
        return NavigationStack(path: $router.path) {
            tabs
                .tint(store.theme.accent)
                .background(ToocNavigationBarTint().frame(width: 0, height: 0))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .navigationDestination(for: ToocRoute.self) { route in
                    ToocDestination(route: route)
                        .tint(store.theme.accent)
                        .background(ToocNavigationBarTint().frame(width: 0, height: 0))
                }
        }
        // The bar's own buttons (‹ back) in the text colour; the screens keep the theme's.
        .tint(Color.primary)
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

    /// じぶん's place in the tab bar (トーク, じぶん).
    private static let meTabIndex = 1
    /// The tabs' symbols in order (the chosen one shows its filled version).
    private static let tabSymbols = ["message", "face.smiling"]

    private var tabs: some View {
        let selection = Binding(get: { router.tab }, set: { tab in withAnimation(.snappy) { router.tab = tab } })
        return TabView(selection: selection) {
            Tab(value: ToocTab.talk) {
                ToocTalkListView()
                    // じぶん: hold for the accounts, double-tap for the one used before.
                    .background(
                        ToocTabBarHook(
                            onLongPress: { index in if index == Self.meTabIndex { router.sheet = .accounts } },
                            onDoubleTap: { index in if index == Self.meTabIndex { switchBack() } },
                            symbols: Self.tabSymbols,
                            selected: router.tab == .talk ? 0 : 1
                        )
                        .frame(width: 0, height: 0)
                    )
            } label: {
                tabLabel("トーク", "message", .talk)
            }
            .badge(store.unreadTotal)

            Tab(value: ToocTab.me) {
                ToocMeView()
                    .background(
                        ToocTabBarHook(onLongPress: { _ in }, onDoubleTap: { _ in }, symbols: Self.tabSymbols,
                                       selected: router.tab == .talk ? 0 : 1, gestures: false)
                        .frame(width: 0, height: 0)
                    )
            } label: {
                tabLabel("じぶん", "face.smiling", .me)
            }
        }
        // Outlined everywhere; only the chosen tab names its filled symbol.
        .environment(\.symbolVariants, .none)
    }

    private func switchBack() {
        Task {
            do {
                try await store.switchToPrevious()
            } catch {
                store.switchError = error.localizedDescription
            }
        }
    }

    private func tabLabel(_ title: String, _ symbol: String, _ tab: ToocTab) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(uiImage: ToocTabBarHook.tabImage("\(symbol).fill"))
                .renderingMode(.template)
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
                    .foregroundStyle(Color.primary)
            } else {
                if let onCalendar {
                    Button(action: onCalendar) { ToocBarIcon("chevron.left") }
                        .accessibilityLabel("カレンダーに戻る")
                }
                if router.tab == .talk { ToocTalkSortMenu() }
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
                .tint(Color.primary)
                .accessibilityLabel("友だち追加")
                Button { router.path.append(.notices) } label: {
                    ToocBarIcon(store.unseenNotices > 0 ? "bell.badge" : "bell")
                }
                .accessibilityLabel("お知らせ")
                Button { router.path.append(.settings) } label: { ToocBarIcon("gearshape") }
                    .accessibilityLabel("設定")
            } else {
                // ＋, 検索, 設定 (left to right); すべて既読 and 選択 live at the bottom of ＋.
                ToocPlusMenu()
                Button { router.path.append(.search) } label: { ToocBarIcon("magnifyingglass") }
                    .accessibilityLabel("検索")
                Button { router.path.append(.settings) } label: { ToocBarIcon("gearshape") }
                    .accessibilityLabel("設定")
            }
        }
    }

    /// What can be done to the chosen talks or friends. Hiding, deleting and blocking ask first.
    @ViewBuilder
    private var selectionActions: some View {
        let chosen = router.selection
        Group {
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

/// A top-bar symbol: a little smaller than the system's, in the text colour (whatever the theme).
struct ToocBarIcon: View {
    let name: String

    init(_ name: String) { self.name = name }

    var body: some View {
        Image(systemName: name)
            .toocFont(.system(size: 15, weight: .semibold))
            .foregroundStyle(Color.primary)
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
        case .settingsEmail: ToocEmailSettingsView()
        case .settingsPhone: ToocPhoneSettingsView()
        case .settingsFont: ToocFontSettingsView()
        case .settingsAbout: ToocAboutView()
        case .settingsChangelog: ToocChangelogView()
        case .settingsCredits: ToocCreditsView()
        case .friends: ToocFriendsScreen()
        case .later: ToocLaterView()
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
        case .accounts: ToocAccountsView()
        case .notes(let room, let note): ToocNotesView(roomID: room, openID: note)
        case .albums(let room, let album): ToocAlbumsView(roomID: room, openID: album)
        }
    }
}

/// The ＋ menu: start a talk or a group, and the ways to add a friend.
struct ToocPlusMenu: View {
    @Environment(ToocRouter.self) private var router
    @Environment(ToocStore.self) private var store

    var body: some View {
        Menu {
            ControlGroup {
                Button("トークルームを作成", systemImage: "plus.message") { router.sheet = .newTalk }
                Button("グループを作成", systemImage: "person.2.badge.plus") { router.sheet = .newGroup }
            }
            ToocAddFriendSection()
            Divider()
            Button("すべて既読にする", systemImage: "checkmark.message") { store.markAllRead() }
            Button("toocを選択", systemImage: "checkmark.circle") {
                withAnimation(.snappy) { router.startSelecting() }
            }
        } label: {
            ToocBarIcon("plus")
        }
        .tint(Color.primary)
        .accessibilityLabel("追加")
    }
}

struct ToocAddFriendSection: View {
    @Environment(ToocRouter.self) private var router

    var body: some View {
        Section {
            Button("MyQRを表示", systemImage: "qrcode") { router.sheet = .qr(.show) }
            Button("MyQRをスキャン", systemImage: "qrcode.viewfinder") { router.sheet = .qr(.scan) }
            Button("toocIDで検索", systemImage: "at") { router.sheet = .find("") }
        } header: {
            Text("友だち追加").toocFont(.footnote)
        }
    }
}

struct ToocTalkSortMenu: View {
    @Environment(ToocStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Menu {
            Section {
                Toggle("あとで返信を優先", isOn: $store.laterFirst.animation(.snappy))
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
        .tint(Color.primary)
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
        .tint(Color.primary)
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
                                .toocFont(.subheadline.bold())
                                .lineLimit(1)
                            Text(store.settings.showContent ? notice.body : "新しいお知らせがあります")
                                .toocFont(.subheadline)
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

/// Draws the navigation bar's own ‹ back button in the text colour, like the other bar symbols.
struct ToocNavigationBarTint: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller { Controller() }
    func updateUIViewController(_ controller: Controller, context: Context) { controller.apply() }

    final class Controller: UIViewController {
        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            apply()
        }

        func apply() {
            navigationController?.navigationBar.tintColor = .label
        }
    }
}

/// After logging out: your icon on tooc's colour says goodbye, shrinks away, and the sign-in form shows through.
struct ToocGoodbyeView: View {
    let user: ToocUser
    var onDone: () -> Void

    @Environment(\.toocTheme) private var theme
    @State private var stage = 0

    var body: some View {
        ZStack {
            theme.accent
                .ignoresSafeArea()
                .opacity(stage >= 1 ? 1 : 0)
            VStack(spacing: 14) {
                ToocAvatar(user: user, size: 96)
                    .overlay { Circle().stroke(.white.opacity(0.9), lineWidth: 3) }
                    .scaleEffect(stage >= 2 ? 0.15 : (stage >= 1 ? 1 : 0.7))
                    .blur(radius: stage >= 2 ? 8 : 0)
                    .opacity(stage == 1 ? 1 : 0)
                Text("またね、\(user.name)")
                    .toocFont(.headline)
                    .foregroundStyle(.white)
                    .opacity(stage == 1 ? 1 : 0)
                    .offset(y: stage >= 1 ? 0 : 10)
            }
        }
        .opacity(stage >= 3 ? 0 : 1)
        .sensoryFeedback(.impact(weight: .light), trigger: stage) { _, new in new == 2 }
        .task {
            withAnimation(.easeOut(duration: 0.35)) { stage = 1 }
            try? await Task.sleep(for: .milliseconds(1100))
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { stage = 2 }
            try? await Task.sleep(for: .milliseconds(380))
            withAnimation(.easeIn(duration: 0.4)) { stage = 3 }
            try? await Task.sleep(for: .milliseconds(420))
            onDone()
        }
        .allowsHitTesting(stage < 3)
    }
}

/// ライト・ダーク・自動 for the window tooc is in (what it was before comes back when tooc closes).
struct ToocInterfaceStyle: UIViewRepresentable {
    let scheme: ColorScheme?

    func makeUIView(context: Context) -> Probe { Probe() }

    func updateUIView(_ view: Probe, context: Context) {
        view.style = switch scheme {
        case .dark?: .dark
        case .light?: .light
        default: .unspecified
        }
        view.apply()
    }

    static func dismantleUIView(_ view: Probe, coordinator: ()) { view.restore() }

    final class Probe: UIView {
        var style: UIUserInterfaceStyle = .unspecified
        private weak var held: UIWindow?
        private var original: UIUserInterfaceStyle = .unspecified
        private var originalRoot: UIUserInterfaceStyle = .unspecified

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            if held !== window {
                held = window
                original = window.overrideUserInterfaceStyle
                originalRoot = window.rootViewController?.overrideUserInterfaceStyle ?? .unspecified
            }
            let root = window.rootViewController
            guard window.overrideUserInterfaceStyle != style || root?.overrideUserInterfaceStyle != style else { return }
            let next = style
            UIView.transition(with: window, duration: 0.3, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                window.overrideUserInterfaceStyle = next
                root?.overrideUserInterfaceStyle = next
            }
        }

        func restore() {
            held?.overrideUserInterfaceStyle = original
            held?.rootViewController?.overrideUserInterfaceStyle = originalRoot
        }
    }
}
