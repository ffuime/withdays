import SwiftUI

/// 友だち: the friends, newest first by default. Tap one for their profile; the button on the right opens a talk.
struct ToocFriendListView: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme

    var body: some View {
        @Bindable var router = router
        List(selection: $router.selection) {
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
            if store.friends.isEmpty {
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
                            .font(.body.bold())
                            .lineLimit(1)
                        if !friend.bio.isEmpty {
                            Text(friend.bio)
                                .font(.system(size: ToocTalkRow.previewSize))
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
                    .font(.system(size: 20, weight: .medium))
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
