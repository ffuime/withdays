import SwiftUI

/// じぶん: your profile card, ways to add a friend, and a way to the friend list.
struct ToocMeView: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @State private var showID = true

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                card
                addFriend
                friendsBox
            }
            .padding(16)
        }
    }

    /// Icon, name and toocID, with the bio underneath; on the icon spread out, blurred and whitened. Tap: the profile.
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
                Color(.systemBackground).opacity(0.72)
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
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
    }

    private func addButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(Color.brand)
                Text(title)
                    .font(.footnote.weight(.semibold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var friendsBox: some View {
        Button {
            withAnimation(.snappy) { router.tab = .friends }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Color.brand)
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
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
