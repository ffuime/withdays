import SwiftUI

/// 友だち: the friends, newest first by default. Tap one for their profile; the button on the right opens a talk.
struct ToocFriendListView: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme

    var body: some View {
        @Bindable var router = router
        List(selection: $router.selection) {
            if !store.requests.isEmpty {
                Section {
                    ForEach(store.requests) { user in
                        ToocRequestRow(user: user)
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .selectionDisabled()
                    }
                } header: {
                    Text("友だち申請")
                }
            }
            ForEach(store.friends) { friend in
                ToocFriendRow(
                    friend: friend,
                    onOpen: { router.sheet = .profile(friend.id) },
                    onTalk: { router.open(room: store.room(with: friend.id).id) }
                )
                .allowsHitTesting(!router.selecting)
                .tag(friend.id)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                // A swipe right (a full one too) adds / removes the favourite.
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        withAnimation { store.toggleFavorite(friend.id) }
                    } label: {
                        Image(systemName: friend.isFavorite ? "star.slash.fill" : "star.fill")
                    }
                    .tint(.yellow)
                    .accessibilityLabel(friend.isFavorite ? "お気に入りから外す" : "お気に入り")
                }
                // A swipe left: hide, block. Never a full swipe; both ask first.
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        router.confirm = .blockFriends([friend.id])
                    } label: {
                        Image(systemName: "nosign")
                    }
                    .tint(.red)
                    .accessibilityLabel("ブロック")
                    Button {
                        router.confirm = .hideFriends([friend.id])
                    } label: {
                        Image(systemName: "eye.slash.fill")
                    }
                    .tint(.gray)
                    .accessibilityLabel("非表示")
                }
            }
        }
        .listStyle(.plain)
        .toocBackground(theme)
        .environment(\.editMode, .constant(router.selecting ? .active : .inactive))
        .overlay {
            if store.friends.isEmpty && store.requests.isEmpty {
                ContentUnavailableView("友だちはまだいません", systemImage: "person.2")
            }
        }
    }
}

struct ToocFriendRow: View {
    let friend: ToocUser
    var onOpen: () -> Void
    var onTalk: () -> Void
    @Environment(\.toocTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    ToocAvatar(user: friend, badge: friend.isFavorite ? "star.fill" : nil)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(friend.displayName)
                            .toocFont(.body.bold())
                            .lineLimit(1)
                        if !friend.bio.isEmpty {
                            Text(friend.bio)
                                .toocFont(.system(size: ToocTalkRow.previewSize))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onTalk) {
                Image(systemName: "plus.message")
                    .toocFont(.system(size: 20, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("トークを始める")
        }
        .frame(height: ToocTalkRow.height)
    }
}

/// Someone who added you: their icon and name (tap for the profile), 友だちになる, and ✕ to turn it down.
struct ToocRequestRow: View {
    let user: ToocUser
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Button { router.sheet = .profile(user.id) } label: {
                HStack(spacing: 12) {
                    ToocAvatar(user: user)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.displayName)
                            .toocFont(.body.bold())
                            .lineLimit(1)
                        Text("@\(user.id)")
                            .toocFont(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button("友だちになる") {
                withAnimation(.snappy) { store.addFriend(user) }
            }
            .toocFont(.subheadline.weight(.semibold))
            .buttonStyle(.glassProminent)
            Button {
                withAnimation(.snappy) { store.decline(user.id) }
            } label: {
                Image(systemName: "xmark")
                    .toocFont(.system(size: 13, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("申請を削除")
        }
        .frame(height: ToocTalkRow.height)
    }
}

/// 友だち, pushed from じぶん: the list, with the friend tab's top bar (並び替え, choosing and what to do with the chosen).
struct ToocFriendsScreen: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router

    var body: some View {
        ToocFriendListView()
            .navigationTitle("友だち")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(router.selecting)
            .toolbar {
                if router.selecting {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("完了") { withAnimation(.snappy) { router.endSelecting() } }
                            .fontWeight(.semibold)
                            .foregroundStyle(store.theme.accent)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) { selectionActions }
                } else {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        ToocFriendSortMenu()
                        Menu {
                            ToocAddFriendSection()
                        } label: {
                            ToocBarIcon("plus")
                        }
                        .accessibilityLabel("友だち追加")
                        Button {
                            withAnimation(.snappy) { router.startSelecting() }
                        } label: {
                            ToocBarIcon("checkmark.circle")
                        }
                        .accessibilityLabel("友だちを選択")
                    }
                }
            }
            .onDisappear { router.endSelecting() }
    }

    @ViewBuilder
    private var selectionActions: some View {
        let chosen = router.selection
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
    }
}
