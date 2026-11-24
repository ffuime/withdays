import SwiftUI

/// じぶん: your profile card, ways to add a friend, your friends, then Mynote, あとで返信 and the messages waiting to be sent.
struct ToocMeView: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme
    @State private var showID = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                card
                addFriend
                friendsBox
                shortcuts
            }
            .padding(16)
        }
        .background(theme.fill.ignoresSafeArea())
    }

    /// Icon, name and toocID, with the bio underneath; on the profile background, blurred and whitened. Tap: the profile.
    private var card: some View {
        let me = store.me
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 16) {
                ToocAvatar(user: me, size: 76)
                VStack(alignment: .leading, spacing: 4) {
                    Text(me.name)
                        .toocFont(.title2.bold())
                        .lineLimit(1)
                    Button {
                        withAnimation(.snappy) { showID.toggle() }
                    } label: {
                        Text(showID ? "@\(me.id)" : "@••••••")
                            .toocFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .contentTransition(.opacity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("タップでtoocIDの表示・非表示")
                }
                Spacer(minLength: 0)
            }
            if !me.bio.isEmpty {
                Text(me.bio)
                    .toocFont(.subheadline)
                    .foregroundStyle(Color.primary.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                ToocIconBackdrop(user: me)
                theme.fill.opacity(0.72)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { router.sheet = .profile(me.id) }
        .accessibilityAddTraits(.isButton)
    }

    /// Two plain halves: your QR code, and a search by toocID.
    private var addFriend: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("友だち追加")
                .toocFont(.headline)
                .padding(.leading, 4)
            HStack(spacing: 0) {
                addButton("QRコード", "qrcode") { router.sheet = .qr(.show) }
                Divider()
                    .frame(height: 44)
                addButton("toocID", "at") { router.sheet = .find("") }
            }
            .background(theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func addButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .toocFont(.system(size: 22, weight: .medium))
                    .foregroundStyle(theme.accent)
                Text(title)
                    .toocFont(.footnote.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Mynote, あとで返信 and the messages waiting to be sent, as plain rows with a hairline between.
    private var shortcuts: some View {
        let waiting = store.scheduledMessages
        return VStack(spacing: 0) {
            shortcut(
                icon: AnyView(ToocAvatar(user: .mynote, size: 40)),
                title: "Mynote",
                detail: store.mynote?.last.map { $0.preview } ?? "メモを書こう"
            ) {
                if let room = store.mynote { router.open(room: room.id) }
            }
            Divider().padding(.leading, 56)
            shortcut(
                icon: AnyView(ToocLaterMark(size: 40)),
                title: "あとで返信",
                detail: store.laterItems.isEmpty ? "ありません" : "\(store.laterItems.count)件"
            ) {
                router.path.append(.later)
            }
            Divider().padding(.leading, 56)
            shortcut(
                icon: AnyView(
                    Image(systemName: "clock.fill")
                        .toocFont(.system(size: 17))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(theme.accent))
                ),
                title: "送信予約",
                detail: waiting.first.map { "\(waiting.count)件・次は\(ToocTime.scheduled($0.message.scheduledAt ?? .now))" }
                    ?? "予約はありません"
            ) {
                router.path.append(.scheduled)
            }
        }
        .padding(.horizontal, 4)
    }

    private func shortcut(icon: AnyView, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                icon
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .toocFont(.body.weight(.semibold))
                    Text(detail)
                        .toocFont(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .toocFont(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// The way to the friend list, and the favourites under it (tap one to talk).
    private var friendsBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                router.path.append(.friends)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .toocFont(.system(size: 20))
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("友だち")
                            .toocFont(.headline)
                        Text("\(store.friends.count)人の友だち")
                            .toocFont(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .toocFont(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !store.favorites.isEmpty {
                Divider().padding(.leading, 16)
                VStack(alignment: .leading, spacing: 10) {
                    Label("お気に入り", systemImage: "star.fill")
                        .toocFont(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ScrollView(.horizontal) {
                        HStack(spacing: 14) {
                            ForEach(store.favorites) { friend in
                                Button {
                                    router.open(room: store.room(with: friend.id).id)
                                } label: {
                                    VStack(spacing: 5) {
                                        ToocAvatar(user: friend, size: 52)
                                        Text(friend.displayName)
                                            .toocFont(.caption2)
                                            .lineLimit(1)
                                            .frame(width: 60)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(16)
            }
        }
        .background(theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}
