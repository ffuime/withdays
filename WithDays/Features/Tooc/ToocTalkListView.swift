import SwiftUI
import UIKit

/// トーク: the rooms, pinned ones first, then by the chosen order. すべて・友だち・グループ at the top right.
struct ToocTalkListView: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme

    var body: some View {
        @Bindable var router = router
        List(selection: $router.selection) {
            ForEach(store.rooms(router.filter)) { room in
                ZStack {
                    // Hidden, so the row opens the room without a chevron.
                    NavigationLink(value: ToocRoute.room(room.id)) { EmptyView() }
                        .opacity(0)
                    ToocTalkRow(room: room)
                }
                .tag(room.id)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .swipeActions(edge: .leading, allowsFullSwipe: room.unread > 0) { leadingActions(room) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingActions(room) }
                .contextMenu {
                    menu(room)
                } preview: {
                    ToocRoomPreview(room: room)
                        .environment(store)
                        .environment(\.toocTheme, theme)
                }
            }
        }
        .listStyle(.plain)
        .toocBackground(theme)
        .environment(\.editMode, .constant(router.selecting ? .active : .inactive))
        .animation(.spring(response: 0.45, dampingFraction: 0.86), value: store.rooms(router.filter).map(\.id))
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack {
                Spacer()
                Picker("表示", selection: $router.filter.animation(.snappy)) {
                    ForEach(ToocTalkFilter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .overlay {
            if store.rooms(router.filter).isEmpty {
                ContentUnavailableView(router.filter == .groups ? "グループはまだありません" : "トークはまだありません",
                                       systemImage: "message")
            }
        }
    }

    private func pin(_ room: ToocRoom) {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.86)) {
            store.update(room.id) { $0.pinned.toggle() }
        }
    }

    /// Left to right: read (only while anything is unread; a full swipe), pin, mute.
    @ViewBuilder
    private func leadingActions(_ room: ToocRoom) -> some View {
        if room.unread > 0 {
            Button {
                withAnimation(.snappy) { store.markRead(room.id) }
            } label: {
                Image(systemName: "checkmark.message.fill")
            }
            .tint(.blue)
            .accessibilityLabel("既読にする")
        }
        Button {
            // After the swipe closes, so the row then glides to its place.
            Task {
                try? await Task.sleep(for: .milliseconds(250))
                pin(room)
            }
        } label: {
            Image(systemName: room.pinned ? "pin.slash.fill" : "pin.fill")
        }
        .tint(.orange)
        .accessibilityLabel(room.pinned ? "ピン留めを外す" : "ピン留め")
        if !room.isMynote {
            Button {
                store.update(room.id) { $0.muted.toggle() }
            } label: {
                Image(systemName: room.muted ? "speaker.2.fill" : "speaker.slash.fill")
            }
            .tint(.indigo)
            .accessibilityLabel(room.muted ? "通知をオン" : "ミュート")
        }
    }

    /// Left to right: hide, delete (Mynote can only be hidden). Never a full swipe; both ask first.
    @ViewBuilder
    private func trailingActions(_ room: ToocRoom) -> some View {
        // A trailing swipe lists its buttons from the edge inwards.
        if !room.isMynote {
            Button {
                router.confirm = .deleteRooms([room.id])
            } label: {
                Image(systemName: "minus.circle")
            }
            .tint(.red)
            .accessibilityLabel("削除")
        }
        Button {
            router.confirm = .hideRooms([room.id])
        } label: {
            Image(systemName: "eye.slash.fill")
        }
        .tint(.gray)
        .accessibilityLabel("非表示")
    }

    @ViewBuilder
    private func menu(_ room: ToocRoom) -> some View {
        Button("開く", systemImage: "message") { router.open(room: room.id) }
        if room.unread > 0 {
            Button("既読にする", systemImage: "checkmark.message") { withAnimation(.snappy) { store.markRead(room.id) } }
        }
        Button(room.pinned ? "ピン留めを外す" : "ピン留め", systemImage: room.pinned ? "pin.slash" : "pin") { pin(room) }
        if !room.isMynote {
            Button(room.muted ? "通知をオン" : "通知をオフ", systemImage: room.muted ? "bell" : "bell.slash") {
                store.update(room.id) { $0.muted.toggle() }
            }
        }
        Divider()
        Button("非表示", systemImage: "eye.slash") { router.confirm = .hideRooms([room.id]) }
        if !room.isMynote {
            Button("削除", systemImage: "trash", role: .destructive) { router.confirm = .deleteRooms([room.id]) }
        }
    }
}

/// One room in the list: icon, name and up to two lines of the last message; the time at the top right and the
/// unread count in the middle. Every row is the same height. The icon opens the profile.
struct ToocTalkRow: View {
    let room: ToocRoom
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router

    static let previewSize: CGFloat = 14
    private static let previewLine = UIFont.systemFont(ofSize: previewSize).lineHeight
    static let height: CGFloat = 60

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ToocAvatar(user: store.iconUser(of: room), badge: room.pinned ? "pin.fill" : nil)
                .contentShape(Circle())
                .onTapGesture(perform: openProfile)
            VStack(alignment: .leading, spacing: 3) {
                nameLine
                preview
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            ZStack {
                if let last = room.last {
                    Text(ToocTime.listLabel(last.date))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                if room.unread > 0 {
                    ToocCountBadge(count: room.unread, prominent: true)
                        .opacity(room.muted ? 0.45 : 1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .frame(height: Self.height)
        .contentShape(Rectangle())
    }

    private func openProfile() {
        if room.isMynote {
            router.sheet = .profile(store.me.id)
        } else if !room.isGroup, let other = room.memberIDs.first {
            router.sheet = .profile(other)
        } else {
            router.open(room: room.id)
        }
    }

    private var nameLine: some View {
        HStack(spacing: 5) {
            Text(store.name(of: room))
                .font(.body.bold())
                .lineLimit(1)
            if room.isGroup {
                ToocCountBadge(count: room.memberIDs.count + 1)
            }
            Group {
                if !room.draft.isEmpty { Image(systemName: "pencil.circle.fill") }
                if room.muted { Image(systemName: "speaker.slash.fill") }
                if room.scheduled { Image(systemName: "clock.fill") }
            }
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let last = room.last {
            HStack(alignment: .top, spacing: 4) {
                if last.sending {
                    // Centred on the first line of text.
                    ProgressView()
                        .controlSize(.mini)
                        .frame(height: Self.previewLine)
                }
                previewText(last)
                    .font(.system(size: Self.previewSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        } else {
            ToocStartTalkText(size: Self.previewSize)
                .onTapGesture {
                    store.update(room.id) { $0.draft = "よろしく！" }
                    router.open(room: room.id, focus: true)
                }
        }
    }

    /// The sender's icon at the text's size, then the message (its own line breaks kept).
    private func previewText(_ message: ToocMessage) -> Text {
        let sender = store.user(message.senderID) ?? store.me
        let icon = Text(Image(uiImage: ToocIconImage.inline(sender, size: Self.previewSize))).baselineOffset(-2)
        if let symbol = message.symbol {
            return Text("\(icon) \(Image(systemName: symbol))\(message.preview)")
        }
        return Text("\(icon) \(message.preview)")
    }
}

/// A peek at a room's latest messages (from a long press), without marking them read.
struct ToocRoomPreview: View {
    let room: ToocRoom
    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ToocAvatar(user: store.iconUser(of: room), size: 32)
                Text(store.name(of: room))
                    .font(.headline)
                    .lineLimit(1)
            }
            .padding(14)
            Divider()
            VStack(spacing: 6) {
                if room.sent.isEmpty {
                    Text("メッセージはまだありません")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                Spacer(minLength: 0)
                ForEach(room.sent.suffix(8)) { message in
                    let mine = message.senderID == store.me.id
                    HStack {
                        if mine { Spacer(minLength: 40) }
                        Text(message.preview)
                            .font(.subheadline)
                            .lineLimit(3)
                            .foregroundStyle(mine ? Color.white : Color.primary)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(mine ? theme.myBubble : theme.theirBubble,
                                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        if !mine { Spacer(minLength: 40) }
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 320, height: 420)
        .background(theme.fill)
    }
}

/// 「トークを始めよう」 for a room with no messages: a slow shimmer across the words.
struct ToocStartTalkText: View {
    let size: CGFloat
    @Environment(\.toocTheme) private var theme
    @State private var phase: CGFloat = -1

    var body: some View {
        Text("トークを始めよう")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(theme.accent)
            .overlay {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .white.opacity(0.9), location: 0.5),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 60)
                .offset(x: phase * 120)
                .blendMode(.plusLighter)
                .mask {
                    Text("トークを始めよう").font(.system(size: size, weight: .semibold))
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}
