import SwiftUI

// MARK: - あとで返信

/// The red あとで返信 mark: an hourglass on a red circle (with how many, when more than one put it off).
struct ToocLaterMark: View {
    var size: CGFloat = 26
    var count = 1

    var body: some View {
        Image(systemName: "hourglass")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .symbolEffect(.rotate, value: count)
            .frame(width: size, height: size)
            .background(Circle().fill(Color.red))
            .overlay(alignment: .topTrailing) {
                if count > 1 {
                    Text("\(count)")
                        .font(.system(size: size * 0.38, weight: .heavy))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(.white))
                        .offset(x: size * 0.22, y: -size * 0.18)
                }
            }
            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
            .accessibilityLabel("あとで返信")
    }
}

/// Who put a message off with あとで返信; and a button to put it off yourself (not on your own messages).
struct ToocLaterSheet: View {
    let messageID: UUID
    let roomID: String

    @Environment(ToocStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    private var message: ToocMessage? { store.room(roomID)?.messages.first { $0.id == messageID } }

    var body: some View {
        let people = (message?.laterBy ?? []).compactMap { $0 == store.me.id ? store.me : store.user($0) }
        let mineMessage = message?.senderID == store.me.id
        let marked = message.map { $0.laterBy.contains(store.me.id) || store.isLater($0.id) } ?? false
        NavigationStack {
            List {
                Section {
                    ForEach(people) { person in
                        HStack(spacing: 12) {
                            ToocAvatar(user: person, size: 40)
                            Text(person.id == store.me.id ? "\(person.displayName)（じぶん）" : person.displayName)
                                .toocFont(.body.weight(.semibold))
                                .lineLimit(1)
                            Spacer()
                            ToocLaterMark(size: 24)
                        }
                        .listRowBackground(Color.clear)
                    }
                } footer: {
                    Text("あとで返信した人がそのトークで何か送ると、印は消えます。")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                if !mineMessage, let message {
                    Button {
                        withAnimation(.snappy) { store.toggleLater(message, in: roomID) }
                    } label: {
                        Label(marked ? "あとで返信を解除" : "じぶんもあとで返信", systemImage: marked ? "xmark" : "hourglass")
                            .toocFont(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(marked ? Color.gray : Color.red)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                }
            }
            .navigationTitle("あとで返信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.primary) }
                        .accessibilityLabel("閉じる")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.impact(weight: .medium), trigger: marked)
    }
}

/// 温度感 on a message: how soon the sender hopes for an answer.
struct ToocUrgencyChip: View {
    let urgency: ToocUrgency

    var body: some View {
        Label(urgency.label, systemImage: urgency.symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(urgency.color))
            .accessibilityLabel("温度感：\(urgency.label)")
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
                ContentUnavailableView("あとで返信はありません", systemImage: "hourglass",
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
                    sender.nameText
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
    @State private var picking = false

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
                HStack(spacing: 0) {
                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            chip(label: "すべて", count: all.count, value: nil)
                            ForEach(order, id: \.self) { emoji in
                                chip(label: emoji, count: counts[emoji] ?? 0, value: emoji)
                            }
                        }
                        .padding(.leading, 16)
                        .padding(.trailing, 8)
                        .padding(.vertical, 8)
                    }
                    .scrollIndicators(.hidden)
                    // ＋ at the right end: react (or change yours) from here.
                    Button { picking = true } label: {
                        Image(systemName: "plus")
                            .toocFont(.system(size: 16, weight: .bold))
                            .foregroundStyle(theme.accent)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Color(.tertiarySystemFill)))
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("リアクションを追加")
                    .padding(.trailing, 16)
                }
            }
            .sheet(isPresented: $picking) {
                ToocEmojiPicker { emoji in
                    withAnimation(.snappy) { store.react(emoji, to: messageID, in: roomID) }
                }
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
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.primary) }
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
