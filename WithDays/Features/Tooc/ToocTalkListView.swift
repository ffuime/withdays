import SwiftUI

/// トーク: the rooms, pinned ones first, then by the chosen order.
struct ToocTalkListView: View {
    var onCalendar: () -> Void

    @Environment(ToocStore.self) private var store
    @Environment(\.toocUnimplemented) private var unimplemented
    @State private var path: [String] = []
    @State private var qr: ToocQRSheet?

    var body: some View {
        NavigationStack(path: $path) {
            List {
                ForEach(store.visibleRooms) { room in
                    NavigationLink(value: room.id) {
                        ToocTalkRow(room: room)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    .swipeActions(edge: .leading, allowsFullSwipe: room.unread > 0) { leadingActions(room) }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingActions(room) }
                }
            }
            .listStyle(.plain)
            .navigationTitle("トーク")
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
    }

    /// Left to right: read (a full swipe, while anything is unread), pin, mute.
    @ViewBuilder
    private func leadingActions(_ room: ToocRoom) -> some View {
        Button {
            store.markRead(room.id)
        } label: {
            Label("既読", systemImage: "checkmark.message.fill")
        }
        .tint(.blue)
        Button {
            store.update(room.id) { $0.pinned.toggle() }
        } label: {
            Label(room.pinned ? "ピン留め解除" : "ピン留め", systemImage: room.pinned ? "pin.slash.fill" : "pin.fill")
        }
        .tint(.orange)
        Button {
            store.update(room.id) { $0.muted.toggle() }
        } label: {
            Label(room.muted ? "通知オン" : "ミュート", systemImage: room.muted ? "speaker.2.fill" : "speaker.slash.fill")
        }
        .tint(.indigo)
    }

    /// Left to right: hide, delete (Mynote can only be hidden). Never a full swipe.
    @ViewBuilder
    private func trailingActions(_ room: ToocRoom) -> some View {
        // A trailing swipe lists its buttons from the edge inwards.
        if !room.isMynote {
            Button(role: .destructive) {
                withAnimation { store.delete(room.id) }
            } label: {
                Label("削除", systemImage: "minus.circle")
            }
            .tint(.red)
        }
        Button {
            withAnimation { store.update(room.id) { $0.hidden = true } }
        } label: {
            Label("非表示", systemImage: "eye.slash.fill")
        }
        .tint(.gray)
    }

    private var sortMenu: some View {
        @Bindable var store = store
        return Menu {
            Section {
                Toggle("お気に入りを優先", isOn: $store.favoritesFirst)
                Toggle("未読メッセージを優先", isOn: $store.unreadFirst)
            }
            Section {
                Picker("並び替え", selection: $store.talkSort) {
                    ForEach([ToocTalkSort.added, .conversation, .profile]) { Text($0.label).tag($0) }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .accessibilityLabel("並び替え")
    }
}

/// One room in the list: icon, name and last message, time and unread count.
struct ToocTalkRow: View {
    let room: ToocRoom
    @Environment(ToocStore.self) private var store

    private static let previewSize: CGFloat = 17 * 0.88

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ToocAvatar(user: store.iconUser(of: room), badge: room.pinned ? "pin.fill" : nil)
            VStack(alignment: .leading, spacing: 3) {
                nameLine
                preview
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 6) {
                if let last = room.last {
                    Text(ToocTime.listLabel(last.date))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                if room.unread > 0 {
                    ToocCountBadge(count: room.unread, prominent: true)
                        .opacity(room.muted ? 0.45 : 1)
                }
            }
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
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                if last.sending {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(previewText(last))
                    .font(.system(size: Self.previewSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
        } else {
            ToocStartTalkText(size: Self.previewSize)
        }
    }

    /// The sender's icon at the text's size, then the message (its own line breaks kept).
    private func previewText(_ message: ToocMessage) -> Text {
        let sender = store.user(message.senderID) ?? store.me
        let icon = Image(uiImage: ToocIconImage.inline(sender, size: Self.previewSize))
        switch message.kind {
        case .text(let text):
            return Text("\(Text(icon).baselineOffset(-2)) \(text)")
        case .photo:
            return Text("\(Text(icon).baselineOffset(-2)) \(Image(systemName: "photo.fill"))写真")
        }
    }
}

/// 「トークを始めよう」 for a room with no messages: a slow shimmer across the words.
struct ToocStartTalkText: View {
    let size: CGFloat
    @State private var phase: CGFloat = -1

    var body: some View {
        Text("トークを始めよう")
            .font(.system(size: size, weight: .semibold))
            .foregroundStyle(Color.brand)
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
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}
