import SwiftUI

/// じぶん: your profile card, ways to add a friend, Mynote, the messages waiting to be sent, and your friends.
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
                HStack(spacing: 12) {
                    mynoteBox
                    scheduledBox
                }
                friendsBox
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
                        .font(.title2.bold())
                        .lineLimit(1)
                    Button {
                        withAnimation(.snappy) { showID.toggle() }
                    } label: {
                        Text(showID ? "@\(me.id)" : "@••••••")
                            .font(.subheadline)
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
                    .font(.subheadline)
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
                .font(.headline)
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
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(theme.accent)
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Mynote, with its latest line.
    private var mynoteBox: some View {
        Button {
            if let room = store.mynote { router.open(room: room.id) }
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ToocAvatar(user: .mynote, size: 28)
                    Text("Mynote")
                        .font(.headline)
                }
                Text(store.mynote?.last.map { $0.preview } ?? "メモを書こう")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// How many messages wait to be sent; tap for all of them.
    private var scheduledBox: some View {
        let waiting = store.scheduledMessages
        return Button { router.path.append(.scheduled) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(theme.accent))
                    Text("送信予約")
                        .font(.headline)
                }
                Text(waiting.first.map { "\(waiting.count)件・次は\(ToocTime.scheduled($0.message.scheduledAt ?? .now))" }
                     ?? "予約はありません")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2, reservesSpace: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    /// The way to the friend list, and the favourites under it (tap one to talk).
    private var friendsBox: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { router.tab = .friends }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("友だち")
                            .font(.headline)
                        Text("\(store.friends.count)人の友だち")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
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
                        .font(.caption.weight(.semibold))
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
                                            .font(.caption2)
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
