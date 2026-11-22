import PhotosUI
import QuickLook
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// A talk room: the messages as bubbles under a date that stays at the top, and the input bar at the bottom.
/// Drag a bubble left to reply to it; drag right anywhere to go back (the system's back swipe).
struct ToocRoomView: View {
    let roomID: String

    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var replyTo: ToocMessage?
    @State private var editing: ToocMessage?
    @FocusState private var focused: Bool

    @State private var scheduling = false
    @State private var scheduleDate = Date.now.addingTimeInterval(60 * 60)
    @State private var pickingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var usingCamera = false
    @State private var pickingFile = false
    @State private var quickLook: URL?
    @State private var zoom: ToocPhotoZoomItem?
    @State private var composer: ToocComposer?
    @State private var selecting: String?
    @State private var searching = false
    @State private var highlight: UUID?
    @State private var showMembers = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmClear = false
    @State private var confirmLeave = false
    @State private var confirmHide = false
    @State private var reactingTo: ToocMessage?

    private var room: ToocRoom? { store.room(roomID) }

    var body: some View {
        Group {
            if let room {
                messages(room)
                    .safeAreaInset(edge: .bottom, spacing: 0) { inputBar(room) }
                    .toolbar { toolbar(room) }
                    .background(theme.fill.ignoresSafeArea())
            } else {
                ContentUnavailableView("トークが見つかりません", systemImage: "message")
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            draft = room?.draft ?? ""
            store.openRoomID = roomID
            store.markRead(roomID)
            if store.banner?.roomID == roomID { store.banner = nil }
            if router.focusRoomID == roomID {
                router.focusRoomID = nil
                focused = true
            }
        }
        .onDisappear {
            if store.openRoomID == roomID { store.openRoomID = nil }
            // Leaving with something typed keeps it, and the list shows the pencil.
            if editing == nil { store.update(roomID) { $0.draft = draft } }
        }
        .sheet(isPresented: $scheduling) { scheduleSheet }
        .sheet(isPresented: $searching) {
            ToocRoomSearchView(roomID: roomID) { id in
                searching = false
                highlight = id
            }
        }
        .sheet(isPresented: $showMembers) { ToocMembersView(roomID: roomID) }
        .sheet(item: $reactingTo) { message in
            ToocEmojiPicker { emoji in
                withAnimation(.snappy) { store.react(emoji, to: message.id, in: roomID) }
            }
        }
        .sheet(item: $composer) { kind in
            ToocComposerView(kind: kind, roomID: roomID) { message in
                withAnimation(.snappy) { store.send(message, in: roomID) }
            }
        }
        .sheet(item: Binding(get: { selecting.map { ToocSelectText(text: $0) } }, set: { selecting = $0?.text })) { item in
            ToocSelectTextView(text: item.text)
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photoItem, matching: .images)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            photoItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    sendPhoto(image)
                }
            }
        }
        .fileImporter(isPresented: $pickingFile, allowedContentTypes: [.item]) { result in
            guard case .success(let url) = result, let copied = ToocFiles.copy(url) else { return }
            withAnimation(.snappy) {
                store.send(.file(name: copied.name, file: copied.file, size: copied.size), in: roomID, replyTo: replyTo?.id)
                replyTo = nil
            }
        }
        .quickLookPreview($quickLook)
        .fullScreenCover(isPresented: $usingCamera) {
            ToocCameraPicker { image in sendPhoto(image) }
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $zoom) { item in
            ToocPhotoZoom(item: item) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { zoom = nil }
            }
        }
        .alert("グループ名を変更", isPresented: $renaming) {
            TextField("グループ名", text: $newName)
            Button("キャンセル", role: .cancel) {}
            Button("変更") {
                let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !name.isEmpty { store.update(roomID) { $0.title = name } }
            }
        }
        .confirmationDialog("トーク履歴を削除しますか？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("トーク履歴を削除", role: .destructive) { store.clearHistory(roomID) }
        } message: {
            Text("元に戻せません。")
        }
        .confirmationDialog("グループを退会しますか？", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("退会", role: .destructive) {
                dismiss()
                store.leave(roomID)
            }
        }
        .confirmationDialog("トークを非表示にしますか？", isPresented: $confirmHide, titleVisibility: .visible) {
            Button("非表示", role: .destructive) {
                dismiss()
                store.update(roomID) { $0.hidden = true }
            }
        }
    }

    // MARK: Messages

    private struct Item: Identifiable {
        let message: ToocMessage
        let first: Bool
        let last: Bool
        let joinedAbove: Bool
        let joinedBelow: Bool
        var id: UUID { message.id }
    }

    private struct Day: Identifiable {
        let date: Date
        var items: [Item]
        var id: Date { date }
    }

    /// The messages by day; within a day, bursts (same person, same minute) know their first and last, and text
    /// bubbles next to each other in a burst join corners (photos and cards never do).
    private func days(_ list: [ToocMessage]) -> [Day] {
        var days: [Day] = []
        let calendar = Calendar.current
        for (index, message) in list.enumerated() {
            let previous = index > 0 ? list[index - 1] : nil
            let next = index < list.count - 1 ? list[index + 1] : nil
            let first = previous.map { !Self.sameBurst($0, message) } ?? true
            let last = next.map { !Self.sameBurst(message, $0) } ?? true
            let item = Item(
                message: message, first: first, last: last,
                joinedAbove: !first && message.isText && (previous?.isText ?? false),
                joinedBelow: !last && message.isText && (next?.isText ?? false)
            )
            let day = calendar.startOfDay(for: message.date)
            if days.last?.date == day {
                days[days.count - 1].items.append(item)
            } else {
                days.append(Day(date: day, items: [item]))
            }
        }
        return days
    }

    private func messages(_ room: ToocRoom) -> some View {
        let list = room.sent
        let waiting = room.waiting
        let size = store.settings.textSize.points
        let typer = store.typing[roomID].flatMap { store.user($0) }
        return ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(days(list)) { day in
                        Section {
                            ForEach(day.items) { item in
                                ToocMessageRow(
                                    message: item.message,
                                    room: room,
                                    first: item.first,
                                    last: item.last,
                                    joinedAbove: item.joinedAbove,
                                    joinedBelow: item.joinedBelow,
                                    textSize: size,
                                    highlighted: highlight == item.message.id,
                                    actions: actions(for: item.message)
                                )
                                .padding(.top, item.first && item.message.id != day.items.first?.message.id ? 10 : 0)
                                .id(item.message.id)
                            }
                        } header: {
                            dayLabel(day.date)
                        }
                    }
                    if let typer {
                        ToocTypingRow(user: typer)
                            .padding(.top, 10)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                    if !waiting.isEmpty {
                        scheduledSection(waiting, size: size)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 12)
                .animation(.snappy, value: typer?.id)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if list.isEmpty && waiting.isEmpty {
                    Button {
                        draft = "よろしく！"
                        focused = true
                    } label: {
                        ToocStartTalkText(size: 17)
                    }
                    .buttonStyle(.plain)
                }
            }
            .onChange(of: room.messages.count) {
                withAnimation(.snappy) { reader.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: typer?.id) {
                withAnimation(.snappy) { reader.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: highlight) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { reader.scrollTo(id, anchor: .center) }
                Task {
                    try? await Task.sleep(for: .seconds(1.6))
                    withAnimation { if highlight == id { highlight = nil } }
                }
            }
        }
    }

    /// The day, in a small glass capsule; the current day's stays at the top while scrolling.
    private func dayLabel(_ date: Date) -> some View {
        Text(ToocTime.day(date))
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
    }

    private func actions(for message: ToocMessage) -> ToocMessageActions {
        ToocMessageActions(
            moreReactions: { reactingTo = message },
            reply: {
                withAnimation(.snappy) {
                    editing = nil
                    replyTo = message
                }
                focused = true
            },
            edit: {
                if case .text(let text) = message.kind {
                    withAnimation(.snappy) {
                        replyTo = nil
                        editing = message
                        draft = text
                    }
                    focused = true
                }
            },
            select: { if case .text(let text) = message.kind { selecting = text } },
            openPhoto: { image, frame in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { zoom = ToocPhotoZoomItem(image: image, source: frame) }
            },
            openFile: { quickLook = ToocFiles.url($0) }
        )
    }

    /// Messages waiting for their time, under the talk: dimmed, with when they'll go.
    private func scheduledSection(_ waiting: [ToocMessage], size: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Rectangle().fill(.quaternary).frame(height: 1)
                Label("送信予約", systemImage: "clock")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Rectangle().fill(.quaternary).frame(height: 1)
            }
            .padding(.vertical, 8)
            ForEach(waiting) { message in
                HStack(alignment: .bottom, spacing: 5) {
                    Spacer(minLength: 40)
                    Text(ToocTime.scheduled(message.scheduledAt ?? .now))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(message.preview)
                        .font(.system(size: size))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(theme.accent.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contextMenu {
                            Button("今すぐ送信", systemImage: "paperplane") {
                                withAnimation(.snappy) { store.sendNow(message.id, in: roomID) }
                            }
                            Button("送信予約を取り消す", systemImage: "xmark.circle", role: .destructive) {
                                withAnimation(.snappy) { store.deleteMessage(message.id, in: roomID) }
                            }
                        }
                }
            }
        }
    }

    /// Sent by the same person in the same minute: drawn as one stack.
    static func sameBurst(_ a: ToocMessage, _ b: ToocMessage) -> Bool {
        a.senderID == b.senderID && !a.isUnsent && !b.isUnsent
            && Calendar.current.isDate(a.date, equalTo: b.date, toGranularity: .minute)
    }

    // MARK: Sending

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func send(silent: Bool = false) {
        let text = trimmed
        guard !text.isEmpty else { return }
        withAnimation(.snappy) {
            if let editing {
                store.edit(editing.id, in: roomID, text: text)
                self.editing = nil
            } else {
                store.send(.text(text), in: roomID, replyTo: replyTo?.id, silent: silent)
                replyTo = nil
            }
            draft = ""
        }
    }

    private func schedule() {
        let text = trimmed
        guard !text.isEmpty else { return }
        withAnimation(.snappy) {
            store.send(.text(text), in: roomID, replyTo: replyTo?.id, at: scheduleDate)
            draft = ""
            replyTo = nil
        }
        scheduling = false
    }

    private func sendPhoto(_ image: UIImage) {
        guard let file = ToocFiles.save(image) else { return }
        withAnimation(.snappy) {
            store.send(.photo(file), in: roomID, replyTo: replyTo?.id)
            replyTo = nil
        }
    }

    private var scheduleSheet: some View {
        NavigationStack {
            ScrollView {
                DatePicker("送信日時", selection: $scheduleDate, in: Date.now.addingTimeInterval(60)...,
                           displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding(.horizontal)
            }
            .navigationTitle("時刻指定して送信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { scheduling = false } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("キャンセル")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: schedule) { Image(systemName: "checkmark") }
                        .buttonStyle(.glassProminent)
                        .accessibilityLabel("予約する")
                }
            }
        }
        .presentationDetents([.large])
    }

    private func openSchedule() {
        scheduleDate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        scheduling = true
    }

    // MARK: Bars

    @ToolbarContentBuilder
    private func toolbar(_ room: ToocRoom) -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            HStack(spacing: 4) {
                Text(store.name(of: room))
                    .font(.headline)
                    .lineLimit(1)
                if room.isGroup {
                    Text("(\(room.memberIDs.count + 1))")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            }
            .fixedSize()
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button { searching = true } label: { ToocBarIcon("magnifyingglass") }
                .accessibilityLabel("トーク内を検索")
            roomMenu(room)
        }
    }

    private func roomMenu(_ room: ToocRoom) -> some View {
        Menu {
            Section {
                if room.isGroup {
                    Button("メンバー", systemImage: "person.2") { showMembers = true }
                    Button("グループ名を変更", systemImage: "pencil") {
                        newName = room.title ?? ""
                        renaming = true
                    }
                } else if !room.isMynote, let other = room.memberIDs.first {
                    Button("プロフィール", systemImage: "person.crop.circle") { router.sheet = .profile(other) }
                }
            }
            Section {
                Button(room.pinned ? "ピン留めを外す" : "ピン留め", systemImage: room.pinned ? "pin.slash" : "pin") {
                    store.update(roomID) { $0.pinned.toggle() }
                }
                if !room.isMynote {
                    Button(room.muted ? "通知をオン" : "通知をオフ", systemImage: room.muted ? "bell" : "bell.slash") {
                        store.update(roomID) { $0.muted.toggle() }
                    }
                    Button("非表示", systemImage: "eye.slash") { confirmHide = true }
                }
            }
            Section {
                Button("トーク履歴を削除", systemImage: "trash", role: .destructive) { confirmClear = true }
                if room.isGroup {
                    Button("グループを退会", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                        confirmLeave = true
                    }
                }
            }
        } label: {
            ToocBarIcon("ellipsis")
        }
        .accessibilityLabel("その他")
    }

    private static let barHeight: CGFloat = 48

    private func inputBar(_ room: ToocRoom) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 2) {
                Menu {
                    Section {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button("カメラ", systemImage: "camera") { usingCamera = true }
                        }
                        Button("写真", systemImage: "photo.on.rectangle") { pickingPhoto = true }
                        Button("ファイル", systemImage: "doc") { pickingFile = true }
                        Button("位置情報", systemImage: "mappin.and.ellipse") { composer = .location }
                    }
                    Section {
                        Button("投票", systemImage: "chart.bar") { composer = .poll }
                        Button("日程調整", systemImage: "calendar") { composer = .datePoll }
                        Button("あみだくじ", systemImage: "line.3.horizontal") { composer = .amida }
                    }
                    Button("時刻指定して送信", systemImage: "clock") { openSchedule() }
                        .disabled(trimmed.isEmpty || editing != nil)
                } label: {
                    Image(systemName: "plus").frame(width: 44, height: Self.barHeight)
                }
                .accessibilityLabel("追加")
                Button { pickingPhoto = true } label: {
                    Image(systemName: "photo.on.rectangle.angled").frame(width: 44, height: Self.barHeight)
                }
                .accessibilityLabel("写真")
            }
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 2)
            .glassEffect(.regular.interactive(), in: .capsule)

            VStack(spacing: 0) {
                if let replyTo {
                    replyBar(replyTo)
                    Divider().padding(.horizontal, 12)
                }
                if editing != nil {
                    editBar
                    Divider().padding(.horizontal, 12)
                }
                HStack(alignment: .bottom, spacing: 6) {
                    TextField("\(store.name(of: room))へ送信", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .focused($focused)
                        .submitLabel(store.settings.returnSends ? .send : .return)
                        .padding(.vertical, 13)
                        .padding(.leading, 16)
                        .frame(minHeight: Self.barHeight)
                        .onChange(of: draft) { old, new in
                            // 「改行キーで送信」: Return sends instead of breaking the line.
                            if store.settings.returnSends, new.hasSuffix("\n"), new.count == old.count + 1 {
                                draft = String(new.dropLast())
                                send()
                            }
                        }
                    if !trimmed.isEmpty {
                        sendButton(room)
                            .padding(.bottom, 6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.trailing, trimmed.isEmpty ? 16 : 6)
                .animation(.snappy(duration: 0.2), value: trimmed.isEmpty)
            }
            // The whole field is glass that stretches under the finger.
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: Self.barHeight / 2, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    /// Tap: send. Hold: ふつうに送信 / ミュートメッセージで送信 / 時刻指定して送信. While editing, just saves.
    @ViewBuilder
    private func sendButton(_ room: ToocRoom) -> some View {
        let icon = Image(systemName: editing == nil ? "arrow.up.circle.fill" : "checkmark.circle.fill")
            .font(.system(size: 32))
            .foregroundStyle(theme.accent)
        if editing != nil {
            Button { send() } label: { icon }
                .accessibilityLabel("編集を保存")
        } else {
            Menu {
                Button("ふつうに送信", systemImage: "paperplane") { send() }
                if !room.isMynote {
                    Button("ミュートメッセージで送信", systemImage: "bell.slash") { send(silent: true) }
                }
                Button("時刻指定して送信", systemImage: "clock") { openSchedule() }
            } label: {
                icon
            } primaryAction: {
                send()
            }
            .menuIndicator(.hidden)
            .accessibilityLabel("送信")
        }
    }

    private var editBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .foregroundStyle(theme.accent)
            Text("メッセージを編集")
                .font(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                withAnimation(.snappy) {
                    editing = nil
                    draft = ""
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("編集をやめる")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// [icon] ○○へ返信 over one line of the message, joined to the top of the input field.
    private func replyBar(_ message: ToocMessage) -> some View {
        let sender = store.user(message.senderID) ?? store.me
        return HStack(spacing: 8) {
            ToocAvatar(user: sender, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(sender.displayName)へ返信")
                    .font(.caption.bold())
                Text(message.preview)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                withAnimation(.snappy) { replyTo = nil }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .accessibilityLabel("返信をやめる")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - A message

struct ToocMessageActions {
    var moreReactions: () -> Void
    var reply: () -> Void
    var edit: () -> Void
    var select: () -> Void
    var openPhoto: (UIImage, CGRect) -> Void
    var openFile: (String) -> Void
}

struct ToocMessageRow: View {
    let message: ToocMessage
    let room: ToocRoom
    /// The first and last of a burst (same person, same minute): only the first has the tail, icon and name.
    let first: Bool
    let last: Bool
    let joinedAbove: Bool
    let joinedBelow: Bool
    var textSize: CGFloat = 17
    var highlighted = false
    let actions: ToocMessageActions

    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme
    @State private var dragX: CGFloat = 0
    @State private var armed = false

    private static let replyDistance: CGFloat = 64
    private static let maxPull: CGFloat = 96
    private static let avatarSize: CGFloat = 36

    private var mine: Bool { message.senderID == store.me.id }

    var body: some View {
        if message.isUnsent {
            Text(mine ? "送信を取り消しました" : "\(store.displayName(message.senderID))が送信を取り消しました")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(theme.theirBubble, in: Capsule())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        } else {
            Group {
                if mine { myRow } else { theirRow }
            }
            .offset(x: dragX)
            .background(alignment: .trailing) { replyIcon }
            .contentShape(Rectangle())
            // Only a leftward drag is taken; a rightward one is left to the back swipe.
            .gesture(ToocLeftPan(onChange: pull, onEnd: release))
            // One tick when letting go would reply.
            .sensoryFeedback(.impact(weight: .light), trigger: armed) { _, new in new }
        }
    }

    private var theirRow: some View {
        let sender = store.user(message.senderID)
        return HStack(alignment: .top, spacing: 8) {
            if first, let sender {
                ToocAvatar(user: sender, size: Self.avatarSize)
                    .onTapGesture { router.sheet = .profile(sender.id) }
            } else {
                Color.clear.frame(width: Self.avatarSize, height: 1)
            }
            VStack(alignment: .leading, spacing: 3) {
                if first, room.isGroup, let sender {
                    Text(sender.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, ToocBubbleShape.tail + 4)
                }
                HStack(alignment: .bottom, spacing: 5) {
                    bubbleWithReactions
                    if last { meta(alignment: .leading) }
                }
            }
            Spacer(minLength: 40)
        }
    }

    private var myRow: some View {
        HStack(alignment: .bottom, spacing: 5) {
            Spacer(minLength: 40)
            if last || message.sending { meta(alignment: .trailing) }
            bubbleWithReactions
        }
    }

    /// 既読 (with the mute mark beside it) above the time.
    private func meta(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            if message.sending {
                ProgressView().controlSize(.mini)
            } else {
                if readLabel != nil || message.silent || message.edited {
                    HStack(spacing: 3) {
                        if message.edited { Text("編集済み") }
                        if message.silent {
                            Image(systemName: "bell.slash.fill")
                                .accessibilityLabel("ミュートメッセージ")
                        }
                        if let read = readLabel { Text(read) }
                    }
                }
                Text(ToocTime.clock(message.date)).monospacedDigit()
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private var readLabel: String? {
        guard !room.isMynote, mine, message.readCount > 0 else { return nil }
        if room.isGroup { return "既読\(message.readCount)" }
        return "既読"
    }

    private var bubbleWithReactions: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: -6) {
            bubble
            if !message.reactions.isEmpty {
                reactions
                    .padding(mine ? .trailing : .leading, ToocBubbleShape.tail + 8)
                    .zIndex(1)
            }
        }
    }

    private var reactions: some View {
        let counts = Dictionary(grouping: message.reactions.values, by: { $0 }).mapValues(\.count)
        let order = ToocStore.emojis.filter { counts[$0] != nil } + counts.keys.filter { !ToocStore.emojis.contains($0) }.sorted()
        return Button {
            if message.reactions[store.me.id] != nil {
                withAnimation(.snappy) { store.react(nil, to: message.id, in: room.id) }
            }
        } label: {
            HStack(spacing: 3) {
                ForEach(order, id: \.self) { emoji in
                    Text(emoji).font(.system(size: 13))
                    if let count = counts[emoji], count > 1 {
                        Text("\(count)").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(theme.fill, in: Capsule())
            .overlay(Capsule().strokeBorder(message.reactions[store.me.id] != nil ? theme.accent : Color.secondary.opacity(0.25)))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var bubble: some View {
        Group {
            switch message.kind {
            case .text(let text):
                let shape = ToocBubbleShape(mine: mine, tail: first, joinedAbove: joinedAbove, joinedBelow: joinedBelow)
                VStack(alignment: .leading, spacing: 6) {
                    if let quotedMessage = quoted { quote(quotedMessage) }
                    Text(text)
                        .font(.system(size: textSize))
                        .foregroundStyle(mine ? Color.white : Color.primary)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
                .background(shape.fill(mine ? theme.myBubble : theme.theirBubble))
                .clipShape(shape)
            case .photo(let file):
                // A photo has no tail and never joins: just the picture with rounded corners.
                ToocPhotoBubble(file: file, address: nil, open: actions.openPhoto)
                    .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
            case .remotePhoto(let address):
                ToocPhotoBubble(file: nil, address: address, open: actions.openPhoto)
                    .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
            default:
                ToocCardBubble(message: message, room: room, mine: mine, openFile: actions.openFile)
                    .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
            }
        }
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(theme.accent, lineWidth: 3)
                    .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
            }
        }
        .opacity(message.sending ? 0.6 : 1)
        .contextMenu { menu }
    }

    /// The system's long-press menu: the five favourite reactions (and ⋯ for every emoji) on top, then the actions.
    @ViewBuilder
    private var menu: some View {
        ControlGroup {
            ForEach(store.settings.favoriteReactions, id: \.self) { emoji in
                Button(emoji) {
                    let current = message.reactions[store.me.id]
                    withAnimation(.snappy) { store.react(current == emoji ? nil : emoji, to: message.id, in: room.id) }
                }
            }
            Button("その他の絵文字", systemImage: "ellipsis", action: actions.moreReactions)
        }
        .controlGroupStyle(.palette)
        Button("返信", systemImage: "arrowshape.turn.up.left", action: actions.reply)
        if case .text(let text) = message.kind {
            Button("コピー", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
            Button("選択", systemImage: "selection.pin.in.out", action: actions.select)
            if mine {
                Button("編集", systemImage: "pencil", action: actions.edit)
            }
        }
        Divider()
        if mine {
            Button("送信取消", systemImage: "arrow.uturn.backward", role: .destructive) {
                withAnimation(.snappy) { store.unsend(message.id, in: room.id) }
            }
        }
        Button("削除", systemImage: "trash", role: .destructive) {
            withAnimation(.snappy) { store.deleteMessage(message.id, in: room.id) }
        }
    }

    // MARK: Reply swipe

    /// Shown in the space the drag opens on the right: grows with the drag, and is full once letting go would reply.
    private var replyIcon: some View {
        let progress = min(1, max(0, -dragX / Self.replyDistance))
        return Image(systemName: "arrowshape.turn.up.left.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(progress >= 1 ? theme.accent : Color.secondary)
            .scaleEffect(0.4 + 0.6 * progress)
            .opacity(progress)
            .padding(.trailing, 14)
            .frame(maxHeight: .infinity, alignment: .center)
    }

    /// Follows the finger smoothly and eases off the further it goes (no catch, no click).
    private func pull(_ x: CGFloat) {
        let distance = max(0, -x)
        dragX = -Self.maxPull * (1 - exp(-distance / Self.maxPull))
        let nowArmed = -dragX >= Self.replyDistance
        if nowArmed != armed { armed = nowArmed }
    }

    private func release(_ x: CGFloat) {
        if -dragX >= Self.replyDistance { actions.reply() }
        armed = false
        withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) { dragX = 0 }
    }
}

/// A pan that only starts for a leftward, mostly sideways drag, so scrolling and the back swipe still work.
struct ToocLeftPan: UIGestureRecognizerRepresentable {
    var onChange: (CGFloat) -> Void
    var onEnd: (CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }

    func handleUIGestureRecognizerAction(_ pan: UIPanGestureRecognizer, context: Context) {
        let x = pan.translation(in: pan.view).x
        switch pan.state {
        case .began, .changed: onChange(x)
        case .ended, .cancelled, .failed: onEnd(x)
        default: break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            let translation = pan.translation(in: pan.view)
            let x = abs(velocity.x) > 1 ? velocity.x : translation.x
            let y = abs(velocity.x) > 1 ? velocity.y : translation.y
            return x < 0 && abs(x) > abs(y)
        }

        /// The talk's scrolling waits for this pan to start or give up, so a sideways drag is never taken by it.
        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            other.view is UIScrollView && other is UIPanGestureRecognizer
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            false
        }
    }
}

/// A bubble: fully rounded, with LINE's tail on the first of a burst — a small horn on the upper outer side, its tip
/// pointing up and out. Its upper edge dips in a soft curve from the bubble's rounded corner to the tip; its lower edge
/// swells back down into the bubble's side. Text bubbles in a burst keep their gaps but tighten the corners they share.
struct ToocBubbleShape: Shape {
    let mine: Bool
    let tail: Bool
    let joinedAbove: Bool
    let joinedBelow: Bool

    /// The room kept beside the bubble for the tail.
    static let tail: CGFloat = 9
    private static let radius: CGFloat = 18
    private static let joined: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        let body = CGRect(
            x: mine ? rect.minX : rect.minX + Self.tail,
            y: rect.minY,
            width: rect.width - Self.tail,
            height: rect.height
        )
        let outerTop = joinedAbove && !tail ? Self.joined : Self.radius
        let outerBottom = joinedBelow ? Self.joined : Self.radius
        let radii = mine
            ? RectangleCornerRadii(topLeading: Self.radius, bottomLeading: Self.radius,
                                   bottomTrailing: outerBottom, topTrailing: outerTop)
            : RectangleCornerRadii(topLeading: outerTop, bottomLeading: outerBottom,
                                   bottomTrailing: Self.radius, topTrailing: Self.radius)
        var path = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: body)
        if tail {
            let edge = mine ? body.maxX : body.minX
            let out: CGFloat = mine ? 1 : -1
            let top = body.minY
            var horn = Path()
            // Starts on the rounded corner, inside the bubble's outline.
            horn.move(to: CGPoint(x: edge - out * 11, y: top + 3))
            // Upper edge: dips softly out to the tip, which sits a little below the bubble's top.
            horn.addQuadCurve(to: CGPoint(x: edge + out * Self.tail, y: top + 4),
                              control: CGPoint(x: edge + out * 1, y: top + 7))
            // Lower edge: swells back down into the bubble's side.
            horn.addQuadCurve(to: CGPoint(x: edge + out * 0.5, y: top + 21),
                              control: CGPoint(x: edge + out * 6, y: top + 15))
            horn.addLine(to: CGPoint(x: edge - out * 11, y: top + 21))
            horn.closeSubpath()
            // A union, so the overlap never cancels out whichever way each part winds.
            path = path.union(horn)
        }
        return path
    }
}

/// The other person typing: their icon and a bubble of three dots rising in turn.
struct ToocTypingRow: View {
    let user: ToocUser
    @Environment(\.toocTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ToocAvatar(user: user, size: 36)
            TimelineView(.animation) { context in
                let time = context.date.timeIntervalSinceReferenceDate
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        let phase = (time * 2.4 - Double(index) * 0.35).truncatingRemainder(dividingBy: 2 * .pi)
                        Circle()
                            .fill(Color.secondary)
                            .frame(width: 7, height: 7)
                            .offset(y: -3 * max(0, sin(phase * 2)))
                            .opacity(0.45 + 0.55 * max(0, sin(phase * 2)))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .padding(.leading, ToocBubbleShape.tail)
                .background(ToocBubbleShape(mine: false, tail: true, joinedAbove: false, joinedBelow: false)
                    .fill(theme.theirBubble))
            }
            Spacer()
        }
        .accessibilityLabel("\(user.displayName)が入力中")
    }
}

/// A photo in a talk, from a file or the web. Tap to open it full screen, grown from here.
struct ToocPhotoBubble: View {
    let file: String?
    let address: String?
    var open: (UIImage, CGRect) -> Void

    @State private var image: UIImage?
    @State private var frame: CGRect = .zero

    var body: some View {
        Group {
            if let image {
                let ratio = image.size.height / max(1, image.size.width)
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 200, height: min(280, max(120, 200 * ratio)))
                    .clipped()
            } else {
                ZStack {
                    Color(.tertiarySystemFill)
                    if address != nil {
                        ProgressView()
                    } else {
                        Image(systemName: "photo.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 200, height: 150)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
        .onTapGesture { if let image { open(image, frame) } }
        .task(id: (file ?? "") + (address ?? "")) {
            if let file {
                image = ToocFiles.image(file)
            } else if let address {
                image = await ToocFiles.remoteImage(address)
            }
        }
    }
}

struct ToocPhotoZoomItem: Identifiable {
    let id = UUID()
    let image: UIImage
    let source: CGRect
}

/// A photo grown out of its bubble to the full width, with 保存 at the bottom centre. Drag or pinch it to put it back.
struct ToocPhotoZoom: View {
    let item: ToocPhotoZoomItem
    var onClose: () -> Void

    @State private var progress: CGFloat = 0
    @State private var saved = false

    var body: some View {
        ToocZoomLayer(
            source: item.source,
            aspect: item.image.size.height / max(1, item.image.size.width),
            sourceRadius: 16,
            zoomable: true,
            progress: $progress,
            onClosed: onClose
        ) {
            Image(uiImage: item.image)
                .resizable()
                .scaledToFill()
        } backdrop: {
            Color.black
        } accessory: {
            Button {
                UIImageWriteToSavedPhotosAlbum(item.image, nil, nil, nil)
                withAnimation(.snappy) { saved = true }
            } label: {
                Label(saved ? "保存しました" : "保存", systemImage: saved ? "checkmark" : "square.and.arrow.down")
                    .font(.headline)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.glass)
            .disabled(saved)
            .environment(\.colorScheme, .dark)
        }
        .presentationBackground(.clear)
        .sensoryFeedback(.success, trigger: saved)
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { progress = 1 }
        }
    }
}

/// The camera, for sending a photo straight away.
struct ToocCameraPicker: UIViewControllerRepresentable {
    var onPick: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: ToocCameraPicker
        init(_ parent: ToocCameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onPick(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Part of a message's text, picked with the system's selection handles.
struct ToocSelectText: Identifiable {
    let text: String
    var id: String { text }
}

struct ToocSelectTextView: View {
    let text: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ToocSelectableText(text: text)
                .padding(.horizontal, 12)
                .navigationTitle("テキストを選択")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { dismiss() } label: { Image(systemName: "xmark") }
                            .accessibilityLabel("閉じる")
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ToocSelectableText: UIViewRepresentable {
    let text: String

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.isEditable = false
        view.isSelectable = true
        view.backgroundColor = .clear
        view.font = .preferredFont(forTextStyle: .body)
        view.adjustsFontForContentSizeCategory = true
        view.text = text
        DispatchQueue.main.async {
            view.becomeFirstResponder()
            view.selectedRange = NSRange(location: 0, length: (text as NSString).length)
        }
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.text != text { view.text = text }
    }
}
