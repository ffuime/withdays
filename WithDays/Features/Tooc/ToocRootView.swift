import SwiftUI

enum ToocTab: Hashable { case talk, friends, me }

/// tooc's frame: sign-in, then three tabs (トーク・友だち・じぶん). Each tab's top-left back button returns to the calendar.
struct ToocRootView: View {
    var onCalendar: () -> Void

    @State private var store = ToocStore()
    @State private var tab = ToocTab.talk

    var body: some View {
        Group {
            if store.signedIn {
                tabs
            } else {
                ToocLoginView(onCalendar: onCalendar)
            }
        }
        .environment(store)
        .toocUnimplementedHost()
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            Tab(value: ToocTab.talk) {
                ToocTalkListView(onCalendar: onCalendar)
            } label: {
                tabLabel("トーク", "message", selected: tab == .talk)
            }
            .badge(store.unreadTotal)

            Tab(value: ToocTab.friends) {
                ToocFriendListView(onCalendar: onCalendar)
            } label: {
                tabLabel("友だち", "person.2", selected: tab == .friends)
            }

            Tab(value: ToocTab.me) {
                ToocMeView(onCalendar: onCalendar) { tab = .friends }
            } label: {
                tabLabel("じぶん", "face.smiling", selected: tab == .me)
            }
        }
    }

    /// Outlined, except the selected tab (the one under the glass) which is filled.
    private func tabLabel(_ title: String, _ symbol: String, selected: Bool) -> some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: selected ? "\(symbol).fill" : symbol)
                .environment(\.symbolVariants, .none)
        }
        .environment(\.symbolVariants, .none)
    }
}

/// The top-left pill on tooc's tab screens: back to the calendar, then (optionally) the sort menu.
struct ToocBackToolbar<SortMenu: View>: ToolbarContent {
    var onCalendar: () -> Void
    @ViewBuilder var sortMenu: SortMenu

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarLeading) {
            Button(action: onCalendar) {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("カレンダーに戻る")
            sortMenu
        }
    }
}

/// The ＋ menu: start a talk or a group, and the ways to add a friend.
struct ToocPlusMenu: View {
    @Binding var qr: ToocQRSheet?
    @Environment(\.toocUnimplemented) private var unimplemented

    var body: some View {
        Menu {
            ControlGroup {
                Button("トークルームを作成", systemImage: "plus.message", action: unimplemented)
                Button("グループを作成", systemImage: "person.2.badge.plus", action: unimplemented)
            }
            ToocAddFriendSection(qr: $qr)
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("追加")
    }
}

struct ToocAddFriendSection: View {
    @Binding var qr: ToocQRSheet?
    @Environment(\.toocUnimplemented) private var unimplemented

    var body: some View {
        Section("友だち追加") {
            Button("MyQRを表示", systemImage: "qrcode") { qr = .show }
            Button("MyQRをスキャン", systemImage: "qrcode.viewfinder") { qr = .scan }
            Button("toocIDで検索", systemImage: "at", action: unimplemented)
        }
    }
}

/// The search / ＋ / ⋯ pill shared by the トーク and 友だち tabs.
struct ToocListToolbar: ToolbarContent {
    @Binding var qr: ToocQRSheet?
    let store: ToocStore
    let unimplemented: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button(action: unimplemented) {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("検索")
            ToocPlusMenu(qr: $qr)
            Menu {
                Button("toocを選択", systemImage: "checkmark.circle", action: unimplemented)
                Button("すべて既読にする", systemImage: "checkmark.message") { store.markAllRead() }
                Button("設定", systemImage: "gearshape", action: unimplemented)
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel("その他")
        }
    }
}
