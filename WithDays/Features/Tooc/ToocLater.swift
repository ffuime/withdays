import SwiftUI

// MARK: - あとで返信

/// The red あとで返信 mark beside a message (and on its talk in the list): a clock on a red circle.
struct ToocLaterMark: View {
    var size: CGFloat = 26

    var body: some View {
        Image(systemName: "clock.fill")
            .font(.system(size: size * 0.52, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.red))
            .accessibilityLabel("あとで返信")
    }
}

/// じぶん › あとで返信: every message put off, newest mark first. Tap one to open it in its talk.
struct ToocLaterView: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme

    var body: some View {
        let items = store.laterItems
        List {
            ForEach(items) { item in
                Button {
                    router.highlightMessage = item.message.id
                    router.path.append(.room(item.room.id))
                } label: {
                    row(item.message, in: item.room)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .trailing) {
                    Button("解除", systemImage: "clock.badge.xmark") {
                        withAnimation(.snappy) { store.toggleLater(item.message, in: item.room.id) }
                    }
                    .tint(.red)
                }
            }
        }
        .listStyle(.plain)
        .toocBackground(theme)
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("あとで返信はありません", systemImage: "clock.badge",
                                       description: Text("メッセージをダブルタップするか、長押しメニューの「あとで返信」で印を付けられます。"))
            }
        }
        .navigationTitle("あとで返信")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ message: ToocMessage, in room: ToocRoom) -> some View {
        let sender = store.user(message.senderID)
        return HStack(alignment: .top, spacing: 12) {
            if let sender {
                ToocAvatar(user: sender, size: 44)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(store.name(of: room))
                        .toocFont(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(ToocTime.listLabel(message.date))
                        .toocFont(.caption)
                        .foregroundStyle(.secondary)
                }
                if room.isGroup, let sender {
                    Text(sender.displayName)
                        .toocFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(message.preview)
                    .toocFont(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            ToocLaterMark(size: 22)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

// MARK: - Who reacted

/// Who reacted with what: a row of emoji filters on top, then the people. Your own can be taken back from here.
struct ToocReactionsSheet: View {
    let messageID: UUID
    let roomID: String

    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var filter: String?

    private var reactions: [String: String] {
        store.room(roomID)?.messages.first { $0.id == messageID }?.reactions ?? [:]
    }

    var body: some View {
        let all = reactions
        let counts = Dictionary(grouping: all.values, by: { $0 }).mapValues(\.count)
        let order = ToocStore.emojis.filter { counts[$0] != nil } + counts.keys.filter { !ToocStore.emojis.contains($0) }.sorted()
        let people = all.filter { filter == nil || $0.value == filter }
            .sorted { $0.key == store.me.id ? true : $1.key == store.me.id ? false : $0.key < $1.key }
        NavigationStack {
            List {
                ForEach(people, id: \.key) { entry in
                    row(id: entry.key, emoji: entry.value)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .top, spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        chip(label: "すべて", count: all.count, value: nil)
                        ForEach(order, id: \.self) { emoji in
                            chip(label: emoji, count: counts[emoji] ?? 0, value: emoji)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            }
            .overlay {
                if all.isEmpty {
                    ContentUnavailableView("リアクションはありません", systemImage: "face.smiling")
                }
            }
            .navigationTitle("リアクション")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.selection, trigger: filter)
    }

    private func chip(label: String, count: Int, value: String?) -> some View {
        let on = filter == value
        return Button {
            withAnimation(.snappy) { filter = value }
        } label: {
            HStack(spacing: 5) {
                Text(label).toocFont(.subheadline.weight(.semibold))
                Text("\(count)")
                    .toocFont(.footnote.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(on ? Color.white.opacity(0.85) : Color.secondary)
            }
            .foregroundStyle(on ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(Capsule().fill(on ? theme.accent : Color(.tertiarySystemFill)))
        }
        .buttonStyle(.plain)
    }

    private func row(id: String, emoji: String) -> some View {
        let isMe = id == store.me.id
        let user = isMe ? store.me : store.user(id)
        return HStack(spacing: 12) {
            if let user {
                ToocAvatar(user: user, size: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(isMe ? "\(user?.displayName ?? id)（じぶん）" : user?.displayName ?? id)
                    .toocFont(.body.weight(.semibold))
                    .lineLimit(1)
                if isMe {
                    Button("取り消す") {
                        withAnimation(.snappy) { store.react(nil, to: messageID, in: roomID) }
                    }
                    .toocFont(.footnote)
                    .foregroundStyle(theme.accent)
                    .buttonStyle(.plain)
                }
            }
            Spacer()
            Text(emoji).font(.system(size: 28))
        }
        .padding(.vertical, 2)
    }
}
