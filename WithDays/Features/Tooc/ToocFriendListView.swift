import SwiftUI

/// 友だち: the friends, newest first by default. Tap one for their profile; the button on the right opens a talk.
struct ToocFriendListView: View {
    var onCalendar: () -> Void

    @Environment(ToocStore.self) private var store
    @Environment(\.toocUnimplemented) private var unimplemented
    @State private var path: [String] = []
    @State private var qr: ToocQRSheet?
    @State private var profile: ToocUser?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(store.friends) { friend in
                    ToocFriendRow(friend: friend, onOpen: { profile = friend }, onTalk: { openTalk(friend) })
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        // A full swipe left adds / removes the favourite.
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                withAnimation { store.toggleFavorite(friend.id) }
                            } label: {
                                Label(friend.isFavorite ? "お気に入り解除" : "お気に入り",
                                      systemImage: friend.isFavorite ? "star.slash.fill" : "star.fill")
                            }
                            .tint(.yellow)
                        }
                        // Right to left: hide, block. Never a full swipe.
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                withAnimation { store.block(friend.id) }
                            } label: {
                                Label("ブロック", systemImage: "nosign")
                            }
                            .tint(.red)
                            Button {
                                withAnimation { store.hideFriend(friend.id) }
                            } label: {
                                Label("非表示", systemImage: "eye.slash.fill")
                            }
                            .tint(.gray)
                        }
                }
            }
            .listStyle(.plain)
            .overlay {
                if store.friends.isEmpty {
                    ContentUnavailableView("友だちはまだいません", systemImage: "person.2")
                }
            }
            .navigationTitle("友だち")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToocBackToolbar(onCalendar: onCalendar) { sortMenu }
                ToocListToolbar(qr: $qr, store: store, unimplemented: unimplemented)
            }
            .navigationDestination(for: String.self) { id in
                ToocRoomView(roomID: id)
            }
        }
        .sheet(item: $qr) { ToocQRView(start: $0) }
        .sheet(item: $profile) { user in
            ToocProfileSheet(user: user) {
                profile = nil
                openTalk(user)
            }
        }
    }

    private func openTalk(_ friend: ToocUser) {
        path = [store.room(with: friend.id).id]
    }

    private var sortMenu: some View {
        @Bindable var store = store
        return Menu {
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

struct ToocFriendRow: View {
    let friend: ToocUser
    var onOpen: () -> Void
    var onTalk: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onOpen) {
                HStack(spacing: 12) {
                    ToocAvatar(user: friend, badge: friend.isFavorite ? "star.fill" : nil)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(friend.name)
                            .font(.body.bold())
                            .lineLimit(1)
                        if !friend.bio.isEmpty {
                            Text(friend.bio)
                                .font(.system(size: 17 * 0.88))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button(action: onTalk) {
                Image(systemName: "plus.message")
                    .font(.system(size: 18, weight: .medium))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("トークを始める")
        }
    }
}
