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
                    // The row with the system's long-press menu; its preview shows the talk and opens it on a tap.
                    ToocContextMenuHost(
                        enabled: !router.selecting,
                        items: menuItems(room),
                        onOpen: { router.open(room: room.id) },
                        preview: {
                            ToocRoomPreview(room: room)
                                .environment(store)
                                .environment(router)
                                .environment(\.toocTheme, theme)
                        },
                        content: ToocTalkRow(room: room)
                            .environment(store)
                            .environment(router)
                            .environment(\.toocTheme, theme)
                    )
                    .frame(height: ToocTalkRow.height)
                }
                .tag(room.id)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading, allowsFullSwipe: room.unread > 0) { leadingActions(room) }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) { trailingActions(room) }
            }
        }
        .listStyle(.plain)
        .toocBackground(theme)
        .environment(\.editMode, .constant(router.selecting ? .active : .inactive))
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

    /// One smooth glide to the new place (no bounce), so the row doesn't jump.
    private func pin(_ room: ToocRoom) {
        withAnimation(.smooth(duration: 0.5)) {
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
            // Once the swipe has fully closed, so the row then glides to its place in one move.
            Task {
                try? await Task.sleep(for: .milliseconds(380))
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

    private func menuItems(_ room: ToocRoom) -> [ToocMenuItem] {
        var items = [ToocMenuItem(title: "開く", symbol: "message") { router.open(room: room.id) }]
        if room.unread > 0 {
            items.append(ToocMenuItem(title: "既読にする", symbol: "checkmark.message") { store.markRead(room.id) })
        }
        items.append(ToocMenuItem(title: room.pinned ? "ピン留めを外す" : "ピン留め", symbol: room.pinned ? "pin.slash" : "pin") {
            pin(room)
        })
        if !room.isMynote {
            items.append(ToocMenuItem(title: room.muted ? "通知をオン" : "通知をオフ", symbol: room.muted ? "bell" : "bell.slash") {
                store.update(room.id) { $0.muted.toggle() }
            })
        }
        items.append(ToocMenuItem(title: "非表示", symbol: "eye.slash") { router.confirm = .hideRooms([room.id]) })
        if !room.isMynote {
            items.append(ToocMenuItem(title: "削除", symbol: "trash", destructive: true) { router.confirm = .deleteRooms([room.id]) })
        }
        return items
    }
}

/// One room in the list: icon, name and up to two lines of the last message; the time at the top right and the
/// unread count in the middle. Every row is the same height. The icon opens the profile.
struct ToocTalkRow: View {
    let room: ToocRoom
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme

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
                        .toocFont(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.top, 3)
                        .frame(maxHeight: .infinity, alignment: .top)
                }
                // The count stays where it always is (under the time); あとで sits to its left without moving
                // anything, or alone in the count's place.
                if room.unread > 0 {
                    ToocCountBadge(count: room.unread, prominent: true)
                        .opacity(room.muted ? 0.45 : 1)
                        .overlay(alignment: .leading) {
                            if store.hasLater(room.id) {
                                ToocLaterMark(size: 22)
                                    .fixedSize()
                                    .alignmentGuide(.leading) { $0.width + 4 }
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                } else if store.hasLater(room.id) {
                    ToocLaterMark(size: 22)
                        .transition(.scale.combined(with: .opacity))
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
                .toocFont(.body.bold())
                .lineLimit(1)
            if room.isGroup {
                ToocCountBadge(count: room.memberIDs.count + 1)
            }
            if room.mentioned {
                Image(systemName: "at.circle.fill")
                    .toocFont(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.accent)
                    .accessibilityLabel("メンションがあります")
            }
            Group {
                if !room.draft.isEmpty { Image(systemName: "pencil.circle.fill") }
                if room.muted { Image(systemName: "speaker.slash.fill") }
                if room.scheduled { Image(systemName: "clock.fill") }
            }
            .toocFont(.system(size: 12))
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var preview: some View {
        if let last = room.last {
            HStack(alignment: .top, spacing: 4) {
                if last.failed {
                    Image(systemName: "exclamationmark.circle.fill")
                        .toocFont(.system(size: 12))
                        .foregroundStyle(.red)
                        .frame(height: Self.previewLine)
                } else if last.sending {
                    // Centred on the first line of text.
                    ProgressView()
                        .controlSize(.mini)
                        .frame(height: Self.previewLine)
                }
                previewText(last)
                    .toocFont(.system(size: Self.previewSize))
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

/// 「トークを始めよう」 for a room with no messages: a slow shimmer across the words.
struct ToocStartTalkText: View {
    let size: CGFloat
    @Environment(\.toocTheme) private var theme
    @State private var phase: CGFloat = -1

    var body: some View {
        Text("トークを始めよう")
            .toocFont(.system(size: size, weight: .semibold))
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
                    Text("トークを始めよう").toocFont(.system(size: size, weight: .semibold))
                }
                .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: false)) { phase = 1 }
            }
    }
}
