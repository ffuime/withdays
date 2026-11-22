import SwiftUI
import UIKit

/// トーク: the rooms, pinned ones first, then by the chosen order.
struct ToocTalkListView: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        List(selection: $router.selection) {
            ForEach(store.visibleRooms) { room in
                ZStack {
                    // Hidden, so the row opens the room without a chevron.
                    NavigationLink(value: ToocRoute.room(room.id)) { EmptyView() }
                        .opacity(0)
                    ToocTalkRow(room: room)
                }
                .tag(room.id)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .swipeActions(edge: .leading, allowsFullSwipe: room.unread > 0) { leadingActions(room) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingActions(room) }
            }
        }
        .listStyle(.plain)
        .environment(\.editMode, .constant(router.selecting ? .active : .inactive))
    }

    /// Left to right: read (only while anything is unread; a full swipe), pin, mute.
    @ViewBuilder
    private func leadingActions(_ room: ToocRoom) -> some View {
        if room.unread > 0 {
            Button {
                store.markRead(room.id)
            } label: {
                Image(systemName: "checkmark.message.fill")
            }
            .tint(.blue)
            .accessibilityLabel("既読にする")
        }
        Button {
            store.update(room.id) { $0.pinned.toggle() }
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

    /// Left to right: hide, delete (Mynote can only be hidden). Never a full swipe.
    @ViewBuilder
    private func trailingActions(_ room: ToocRoom) -> some View {
        // A trailing swipe lists its buttons from the edge inwards.
        if !room.isMynote {
            Button(role: .destructive) {
                withAnimation { store.delete(room.id) }
            } label: {
                Image(systemName: "minus.circle")
            }
            .tint(.red)
            .accessibilityLabel("削除")
        }
        Button {
            withAnimation { store.update(room.id) { $0.hidden = true } }
        } label: {
            Image(systemName: "eye.slash.fill")
        }
        .tint(.gray)
        .accessibilityLabel("非表示")
    }
}

/// One room in the list: icon, name and up to two lines of the last message; the time at the top right and the
/// unread count in the middle. Every row is the same height.
struct ToocTalkRow: View {
    let room: ToocRoom
    @Environment(ToocStore.self) private var store

    static let previewSize: CGFloat = 14
    private static let previewLine = UIFont.systemFont(ofSize: previewSize).lineHeight
    static let height: CGFloat = 60

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ToocAvatar(user: store.iconUser(of: room), badge: room.pinned ? "pin.fill" : nil)
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
