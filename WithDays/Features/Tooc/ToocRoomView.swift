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
    /// How far the input field is being pulled (up or down), for its give under the finger.
    @State private var pull: CGFloat = 0
    /// Counts つなげて送信, for its tap.
    @State private var continued = 0
    /// The message whose 返信ツリー is open.
    @State private var threadOf: ToocMessage?

    @State private var scheduling = false
    @State private var scheduleDate = Date.now.addingTimeInterval(60 * 60)
    @State private var pickingPhoto = false
    @State private var photoItems: [PhotosPickerItem] = []
    /// Photos picked or taken, joined to the input until sent.
    @State private var attachments: [ToocPendingPhoto] = []
    @State private var usingCamera = false
    @State private var pickingFile = false
    @State private var quickLook: URL?
    @State private var viewing: ToocPhotoViewerItem?
    /// The text just sent, flying from the input field into its bubble.
    @State private var flight: ToocFlight?
    @State private var flightProgress: CGFloat = 0
    @State private var inputFrame: CGRect = .zero
    @State private var choosingUrgency = false
    @State private var managingRoles = false
    @State private var confirmDeleteGroup = false
    @State private var composer: ToocComposer?
    @State private var selecting: String?
    @State private var searching = false
    @State private var highlight: UUID?
    @State private var showMembers = false
    @State private var editingGroup = false
    @State private var confirmClear = false
    @State private var confirmLeave = false
    @State private var confirmHide = false
    @State private var reactingTo: ToocMessage?
    @State private var forwarding: ToocMessage?
    @State private var addingToAlbum: ToocMessage?
    @State private var showStickers = false
    /// People called with @ while typing (their name as typed → toocID).
    @State private var mentionPicks: [String: String] = [:]

    private var room: ToocRoom? { store.room(roomID) }

    /// The messages with the pins above, the input below, and the room's top bar.
    private func talk(_ room: ToocRoom) -> some View {
        messages(room)
            .safeAreaInset(edge: .top, spacing: 0) {
                if !room.pinnedMessages.isEmpty {
                    ToocPinBar(room: room) { id in jump(to: id) }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: room.pinnedMessages)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let stranger = notFriend(room) {
                    notFriendBar(stranger)
                } else {
                    VStack(spacing: 0) {
                        let candidates = mentionCandidates(room)
                        if !candidates.isEmpty {
                            ToocMentionStrip(candidates: candidates, onPick: pickMention)
                                .padding(.top, 6)
                        }
                        inputBar(room)
                        if showStickers {
                            ToocStickerPanel { url in
                                withAnimation(.snappy) {
                                    store.send(.sticker(url: url), in: roomID, replyTo: replyTo?.id)
                                    replyTo = nil
                                }
                            }
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                    }
                    .animation(.snappy, value: showStickers)
                    .animation(.snappy, value: mentionCandidates(room).map(\.id))
                }
            }
            .toolbar { toolbar(room) }
            .background(theme.fill.ignoresSafeArea())
            .sheet(isPresented: $managingRoles) { ToocGroupRolesView(roomID: roomID) }
            .alert("グループを削除しますか？", isPresented: $confirmDeleteGroup) {
                Button("キャンセル", role: .cancel) {}
                Button("削除", role: .destructive) {
                    dismiss()
                    store.deleteGroup(roomID)
                }
            } message: {
                Text("メンバー全員のトーク一覧から消え、元に戻せません。")
            }
    }

    /// The talk with its bars, title and arrival; the sheets and covers are added in `body`.
    private var screen: some View {
        Group {
            if let room {
                talk(room)
            } else {
                ContentUnavailableView("トークが見つかりません", systemImage: "message")
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .overlay { flightLayer }
        .sheet(isPresented: $choosingUrgency) {
            ToocUrgencySheet(text: trimmed.isEmpty ? "写真\(attachments.count)枚" : trimmed) { urgency in
                choosingUrgency = false
                send(urgency: urgency)
            }
        }
        .onAppear {
            draft = room?.draft ?? ""
            store.openRoomID = roomID
            store.markRead(roomID)
            if store.banner?.roomID == roomID { store.banner = nil }
            if router.focusRoomID == roomID {
                router.focusRoomID = nil
                focused = true
            }
            if let id = router.highlightMessage {
                router.highlightMessage = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    highlight = id
                }
            }
        }
        .onDisappear {
            if store.openRoomID == roomID { store.openRoomID = nil }
            // Leaving with something typed keeps it, and the list shows the pencil.
            if editing == nil { store.update(roomID) { $0.draft = draft } }
        }
    }

    var body: some View {
        screen
        .sheet(isPresented: $scheduling) { scheduleSheet }
        .sheet(isPresented: $searching) {
            ToocRoomSearchView(roomID: roomID) { id in
                searching = false
                highlight = id
            }
        }
        .sheet(isPresented: $showMembers) { ToocMembersView(roomID: roomID) }
        .sheet(item: $forwarding) { message in ToocForwardView(message: message) }
        .sheet(item: $addingToAlbum) { message in ToocAddToAlbumSheet(roomID: roomID, message: message) }
        .sheet(item: $threadOf) { message in ToocThreadView(roomID: roomID, messageID: message.id) }
        .onChange(of: focused) { _, focused in
            if focused { withAnimation(.snappy) { showStickers = false } }
        }
        .sheet(item: $reactingTo) { message in
            ToocEmojiPicker { emoji in
                withAnimation(.snappy) { store.react(emoji, to: message.id, in: roomID) }
            }
        }
        .sheet(item: $composer) { kind in
            ToocComposerView(kind: kind, roomID: roomID) { message in
                withAnimation(.snappy) { _ = store.send(message, in: roomID) }
            }
        }
        .sheet(item: Binding(get: { selecting.map { ToocSelectText(text: $0) } }, set: { selecting = $0?.text })) { item in
            ToocSelectTextView(text: item.text)
        }
        .photosPicker(isPresented: $pickingPhoto, selection: $photoItems, maxSelectionCount: 10, matching: .images)
        .onChange(of: photoItems) { _, items in
            guard !items.isEmpty else { return }
            photoItems = []
            Task {
                for item in items {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        withAnimation(.snappy) { attachments.append(ToocPendingPhoto(image: image)) }
                    }
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
            ToocCameraPicker { image in
                withAnimation(.snappy) { attachments.append(ToocPendingPhoto(image: image)) }
            }
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewing) { item in
            ToocPhotoViewer(item: item) { viewing = nil }
        }
        .sheet(isPresented: $editingGroup) { ToocGroupEditView(roomID: roomID) }
        .alert("トーク履歴を削除しますか？", isPresented: $confirmClear) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) { store.clearHistory(roomID) }
        } message: {
            Text("元に戻せません。")
        }
        .alert("グループを退会しますか？", isPresented: $confirmLeave) {
            Button("キャンセル", role: .cancel) {}
            Button("退会", role: .destructive) {
                dismiss()
                store.leave(roomID)
            }
        }
        .alert("トークを非表示にしますか？", isPresented: $confirmHide) {
            Button("キャンセル", role: .cancel) {}
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
        /// A つづき whose message isn't right above it (someone else wrote in between).
        let followsFar: Bool
        /// A つづき of someone else's message right above: a thin line links them. True when that one is yours.
        let linkedFromMine: Bool?
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
            let first = previous.map { !Self.joins($0, message) } ?? true
            let last = next.map { !Self.joins(message, $0) } ?? true
            let item = Item(
                message: message, first: first, last: last,
                joinedAbove: !first && message.isText && (previous?.isText ?? false),
                joinedBelow: !last && message.isText && (next?.isText ?? false),
                followsFar: message.follows != nil && previous?.id != message.follows,
                linkedFromMine: previous.flatMap { previous in
                    message.follows == previous.id && previous.senderID != message.senderID
                        ? previous.senderID == store.me.id : nil
                }
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
        let size = CGFloat(store.settings.textPoints)
        let typer = store.typing[roomID].flatMap { store.user($0) }
        return ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 2, pinnedViews: [.sectionHeaders]) {
                    ForEach(days(list)) { day in
                        // Each day's label stays at the top while its messages scroll under it; the next day's pushes it up.
                        Section {
                            ForEach(day.items) { item in
                                VStack(alignment: item.message.senderID == store.me.id ? .trailing : .leading, spacing: 3) {
                                if item.followsFar, let up = item.message.follows {
                                    followLink(up, mine: item.message.senderID == store.me.id)
                                }
                                if let fromMine = item.linkedFromMine {
                                    ToocFollowLine(fromMine: fromMine)
                                }
                                ToocMessageRow(
                                    message: item.message,
                                    room: room,
                                    first: item.first,
                                    last: item.last,
                                    joinedAbove: item.joinedAbove,
                                    joinedBelow: item.joinedBelow,
                                    textSize: size,
                                    highlighted: highlight == item.message.id,
                                    arriving: flight?.id == item.message.id,
                                    onArrivingFrame: { frame in landFlight(item.message.id, at: frame) },
                                    actions: actions(for: item.message)
                                )
                                }
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
                .scrollTargetLayout()
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

    private static let dayLabelHeight: CGFloat = 40

    /// The day: plain text, no background.
    private func dayLabel(_ date: Date) -> some View {
        Text(ToocTime.day(date))
            .toocFont(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .frame(height: Self.dayLabelHeight)
    }

    private func actions(for message: ToocMessage) -> ToocMessageActions {
        ToocMessageActions(
            moreReactions: { reactingTo = message },
            forward: { forwarding = message },
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
                // Every photo in the talk, oldest first, so a swipe goes to the one before or after.
                let photos = (room?.messages ?? []).filter { photo in
                    switch photo.kind {
                    case .photo(let file): file != nil
                    case .remotePhoto: true
                    default: false
                    }
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    viewing = ToocPhotoViewerItem(photos: photos.isEmpty ? [message] : photos, start: message.id,
                                                  image: image, source: frame, roomID: roomID)
                }
            },
            openFile: { file in
                guard file.hasPrefix("http"), let url = URL(string: file) else {
                    quickLook = ToocFiles.url(file)
                    return
                }
                // A file on the server: fetched into a temporary folder, then previewed.
                Task {
                    guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
                    let name = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
                    let target = FileManager.default.temporaryDirectory.appending(path: name)
                    try? data.write(to: target, options: .atomic)
                    quickLook = target
                }
            },
            showOriginal: { id in jump(to: id) },
            addToAlbum: { addingToAlbum = message },
            openThread: { threadOf = message }
        )
    }

    /// Scrolls to a message and has it jump, so it's easy to spot.
    /// Over a つづき that isn't next to its message: where it continues from (tap to go there).
    private func followLink(_ id: UUID, mine: Bool) -> some View {
        let from = room?.messages.first { $0.id == id }.map(\.senderID)
        let title = from == nil || from == store.me.id ? "つづき" : "\(store.displayName(from ?? ""))へのつづき"
        return Button { jump(to: id) } label: {
            Label(title, systemImage: "arrow.turn.left.up")
                .toocFont(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.vertical, 2)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(mine ? .trailing : .leading, mine ? 18 : 52)
        .padding(.top, 6)
        .accessibilityHint("つながる前のメッセージへ移動")
    }

    private func jump(to id: UUID) {
        highlight = nil
        Task { @MainActor in highlight = id }
    }

    /// Messages waiting for their time, under the talk: dimmed, with when they'll go.
    private func scheduledSection(_ waiting: [ToocMessage], size: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack {
                Rectangle().fill(.quaternary).frame(height: 1)
                Label("送信予約", systemImage: "clock")
                    .toocFont(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize()
                Rectangle().fill(.quaternary).frame(height: 1)
            }
            .padding(.vertical, 8)
            ForEach(waiting) { message in
                HStack(alignment: .bottom, spacing: 5) {
                    Spacer(minLength: 40)
                    Text(ToocTime.scheduled(message.scheduledAt ?? .now))
                        .toocFont(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text(message.preview)
                        .toocFont(.system(size: size))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(theme.accent.opacity(0.5), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .contextMenu {
                            ToocMenuButton("今すぐ送信", systemImage: "paperplane") {
                                withAnimation(.snappy) { store.sendNow(message.id, in: roomID) }
                            }
                            ToocDestructiveButton("送信予約を取り消す", systemImage: "xmark.circle") {
                                withAnimation(.snappy) { store.deleteMessage(message.id, in: roomID) }
                            }
                        }
                }
            }
        }
    }

    /// Drawn as one stack: the same burst, or `b` sent as the つづき of `a` (any time later).
    static func joins(_ a: ToocMessage, _ b: ToocMessage) -> Bool {
        if sameBurst(a, b) { return true }
        return b.follows == a.id && a.senderID == b.senderID && !a.isUnsent && !b.isUnsent
    }

    /// Sent by the same person in the same minute: drawn as one stack.
    static func sameBurst(_ a: ToocMessage, _ b: ToocMessage) -> Bool {
        a.senderID == b.senderID && !a.isUnsent && !b.isUnsent
            && Calendar.current.isDate(a.date, equalTo: b.date, toGranularity: .minute)
    }

    // MARK: Sending

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Something to send: text, or photos (text is optional with photos).
    private var canSend: Bool { !trimmed.isEmpty || (!attachments.isEmpty && editing == nil) }

    /// `follows`: sent as the つづき of that earlier message of yours (not a quote).
    private func send(silent: Bool = false, urgency: ToocUrgency? = nil, follows: UUID? = nil) {
        let text = trimmed
        guard canSend else { return }
        var flying: UUID?
        withAnimation(.snappy) {
            if let editing {
                if !text.isEmpty { store.edit(editing.id, in: roomID, text: text) }
                self.editing = nil
            } else {
                // The photos first, then the words, as one burst.
                for (index, photo) in attachments.enumerated() {
                    // With no words, the 温度感 rides on the last photo.
                    let carries = text.isEmpty && index == attachments.count - 1
                    if let file = ToocFiles.save(photo.image) {
                        store.send(.photo(file), in: roomID, replyTo: follows == nil ? replyTo?.id : nil, silent: silent,
                                   urgency: carries ? urgency : nil, follows: index == 0 ? follows : nil)
                    }
                }
                if !text.isEmpty {
                    flying = store.send(.text(text), in: roomID,
                                        replyTo: attachments.isEmpty && follows == nil ? replyTo?.id : nil,
                                        silent: silent, mentions: mentions(in: text), urgency: urgency,
                                        follows: attachments.isEmpty ? follows : nil)
                }
                attachments = []
                replyTo = nil
                mentionPicks = [:]
            }
            draft = ""
        }
        if let flying, inputFrame != .zero {
            flightProgress = 0
            flight = ToocFlight(id: flying, text: text, from: inputFrame)
            // If its bubble never shows up (scrolled away), give up.
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                if flight?.id == flying { flight = nil }
            }
        }
    }

    /// Pulled up while typing: sent as the つづき of the talk's last message (linked to it however long ago).
    private func sendContinuing() {
        continued += 1
        send(follows: store.lastMessage(in: roomID)?.id)
    }

    /// The input field follows the finger up or down: down closes the keyboard; up opens it, or — while typing —
    /// sends as a つづき.
    private var inputSwipe: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                let dy = value.translation.height
                guard abs(dy) > abs(value.translation.width) else { return }
                // A little give, stiffer the further it goes.
                pull = dy > 0 ? min(14, dy * 0.22) : max(-24, dy * 0.28)
            }
            .onEnded { value in
                let dy = value.translation.height
                let projected = value.predictedEndTranslation.height
                let vertical = abs(dy) > abs(value.translation.width) * 1.3
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) { pull = 0 }
                guard vertical else { return }
                if dy > 36 || projected > 140 {
                    if focused { focused = false }
                } else if dy < -36 || projected < -140 {
                    if !focused {
                        focused = true
                    } else if canSend, editing == nil {
                        sendContinuing()
                    }
                }
            }
    }

    /// Shown over the field while it's pulled up with something typed.
    private var continueHint: some View {
        Label(store.lastMessage(in: roomID) == nil ? "送信" : "つなげて送信", systemImage: "arrow.up")
            .toocFont(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 11)
            .padding(.vertical, 5)
            .background(theme.accent, in: Capsule())
            .fixedSize()
    }

    /// The new bubble has its place: fly there with a soft, stretchy spring, then show the real one.
    private func landFlight(_ id: UUID, at frame: CGRect) {
        guard var current = flight, current.id == id else { return }
        let first = current.to == nil
        current.to = frame
        flight = current
        guard first else { return }
        withAnimation(.spring(response: 0.48, dampingFraction: 0.66)) {
            flightProgress = 1
        } completion: {
            if flight?.id == id { flight = nil }
            flightProgress = 0
        }
    }

    @ViewBuilder
    private var flightLayer: some View {
        if let flight, let to = flight.to {
            GeometryReader { proxy in
                ToocFlyingBubble(text: flight.text, from: flight.from, to: to,
                                 origin: proxy.frame(in: .global).origin, size: CGFloat(store.settings.textPoints),
                                 fill: theme.myBubble, progress: flightProgress)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
    }

    /// The people still called in the text (a deleted @name no longer counts).
    private func mentions(in text: String) -> [String] {
        Array(Set(mentionPicks.filter { text.contains("@\($0.key)") }.map(\.value)))
    }

    /// The word being typed after @ in a group (nil when not typing a name).
    private var mentionQuery: String? {
        guard room?.isGroup == true, let at = draft.lastIndex(of: "@") else { return nil }
        if at != draft.startIndex, !draft[draft.index(before: at)].isWhitespace { return nil }
        let typed = draft[draft.index(after: at)...]
        guard !typed.contains(where: \.isWhitespace), typed.count <= 20 else { return nil }
        return String(typed)
    }

    private func mentionCandidates(_ room: ToocRoom) -> [ToocUser] {
        guard let query = mentionQuery else { return [] }
        return room.memberIDs.compactMap { store.user($0) }.filter { user in
            query.isEmpty || user.name.localizedCaseInsensitiveContains(query)
                || user.displayName.localizedCaseInsensitiveContains(query) || user.id.contains(query.lowercased())
        }
    }

    private func pickMention(_ user: ToocUser) {
        guard let at = draft.lastIndex(of: "@") else { return }
        withAnimation(.snappy) {
            draft = String(draft[..<at]) + "@\(user.name) "
            mentionPicks[user.name] = user.id
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

    /// The photos waiting to go, joined to the top of the input like a reply.
    private var attachmentBar: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(attachments) { photo in
                    Image(uiImage: photo.image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topTrailing) {
                            Button {
                                withAnimation(.snappy) { attachments.removeAll { $0.id == photo.id } }
                            } label: {
                                Image(systemName: "xmark")
                                    .toocFont(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Circle().fill(.black.opacity(0.6)))
                            }
                            .padding(3)
                            .accessibilityLabel("添付を外す")
                        }
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        .transition(.move(edge: .bottom).combined(with: .opacity))
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
                    Button { scheduling = false } label: { Image(systemName: "xmark").foregroundStyle(Color.primary) }
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
                    .toocFont(.headline)
                    .lineLimit(1)
                if room.isGroup {
                    ToocCountBadge(count: room.memberIDs.count + 1, large: true)
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
                    // Only for those allowed to change something there (管理人, or an オペレーター handed it).
                    if ToocGroupPermission.allCases.contains(where: { store.can($0, in: room) }) {
                        Button("グループプロフィールを編集", systemImage: "pencil") { editingGroup = true }
                    }
                    Button(store.isAdmin(room) ? "管理人・権限" : "管理人", systemImage: "person.badge.key") {
                        managingRoles = true
                    }
                } else if !room.isMynote, let other = room.memberIDs.first {
                    Button("プロフィール", systemImage: "person.crop.circle") { router.sheet = .profile(other) }
                }
            }
            Section {
                Button("ノート", systemImage: "note.text") { router.sheet = .notes(roomID, nil) }
                Button("アルバム", systemImage: "photo.stack") { router.sheet = .albums(roomID, nil) }
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
                ToocDestructiveButton("トーク履歴を削除", systemImage: "trash") { confirmClear = true }
                if room.isGroup {
                    ToocDestructiveButton("グループを退会", systemImage: "rectangle.portrait.and.arrow.right") {
                        confirmLeave = true
                    }
                    if store.isAdmin(room) {
                        ToocDestructiveButton("グループを削除", systemImage: "trash.fill") { confirmDeleteGroup = true }
                    }
                }
            }
        } label: {
            ToocBarIcon("ellipsis")
        }
        .tint(Color.primary)
        .accessibilityLabel("その他")
    }

    private static let barHeight: CGFloat = 48

    /// In a one-to-one talk, the other person if you haven't added them: until then you can't write.
    private func notFriend(_ room: ToocRoom) -> ToocUser? {
        guard !room.isGroup, !room.isMynote, let other = room.memberIDs.first else { return nil }
        let user = store.lookUp(other)
        return user.isFriend ? nil : user
    }

    private func notFriendBar(_ user: ToocUser) -> some View {
        HStack(spacing: 12) {
            Text("友だちになるまでメッセージは送れません")
                .toocFont(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("友だちになる") {
                withAnimation(.snappy) { store.addFriend(user) }
            }
            .toocFont(.subheadline.weight(.semibold))
            .buttonStyle(.glassProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Self.barHeight / 2, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

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
                        .disabled(trimmed.isEmpty || editing != nil || !attachments.isEmpty)
                } label: {
                    Image(systemName: "plus").frame(width: 44, height: Self.barHeight)
                }
                .tint(Color.primary)
                .accessibilityLabel("追加")
                Button { pickingPhoto = true } label: {
                    Image(systemName: "photo.on.rectangle.angled").frame(width: 44, height: Self.barHeight)
                }
                .accessibilityLabel("写真")
            }
            .toocFont(.system(size: 19, weight: .medium))
            .foregroundStyle(Color.primary)
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
                if !attachments.isEmpty {
                    attachmentBar
                    Divider().padding(.horizontal, 12)
                }
                HStack(alignment: .bottom, spacing: 6) {
                    TextField("\(store.name(of: room))へ送信", text: $draft, axis: .vertical)
                        .lineLimit(1...6)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { inputFrame = $0 }
                        .focused($focused)
                        .submitLabel(store.settings.returnSends ? .send : .return)
                        .padding(.vertical, 13)
                        .padding(.leading, 16)
                        .frame(minHeight: Self.barHeight)
                        .onChange(of: draft) { old, new in
                            if !new.isEmpty { store.typed(in: roomID) }
                            // 「改行キーで送信」: Return sends instead of breaking the line.
                            if store.settings.returnSends, new.hasSuffix("\n"), new.count == old.count + 1 {
                                draft = String(new.dropLast())
                                send()
                            }
                        }
                    if canSend {
                        sendButton(room)
                            .padding(.bottom, 6)
                            .transition(.scale.combined(with: .opacity))
                    } else {
                        Button {
                            withAnimation(.snappy) {
                                showStickers.toggle()
                                if showStickers { focused = false }
                            }
                        } label: {
                            Image(systemName: showStickers ? "keyboard" : "face.smiling")
                                .toocFont(.system(size: 21, weight: .medium))
                                .foregroundStyle(showStickers ? Color.primary : Color.secondary)
                                .contentTransition(.symbolEffect(.replace))
                                .frame(width: 36, height: Self.barHeight)
                        }
                        .accessibilityLabel(showStickers ? "キーボード" : "スタンプ")
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.trailing, 6)
                .animation(.snappy(duration: 0.2), value: canSend)
            }
            // The whole field is glass that stretches under the finger.
            .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: Self.barHeight / 2, style: .continuous))
            .overlay(alignment: .top) {
                if pull < -12, focused, canSend, editing == nil {
                    continueHint
                        .offset(y: -34)
                        .transition(.scale(scale: 0.8, anchor: .bottom).combined(with: .opacity))
                }
            }
            .offset(y: pull)
            .animation(.snappy(duration: 0.2), value: pull < -12)
            .simultaneousGesture(inputSwipe)
            .sensoryFeedback(.impact(weight: .medium), trigger: continued)
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    /// Tap: send. Hold: ふつうに送信 / ミュートメッセージで送信 / 時刻指定して送信. While editing, just saves.
    @ViewBuilder
    private func sendButton(_ room: ToocRoom) -> some View {
        let icon = Image(systemName: editing == nil ? "arrow.up.circle.fill" : "checkmark.circle.fill")
            .toocFont(.system(size: 32))
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
                if attachments.isEmpty {
                    Button("時刻指定して送信", systemImage: "clock") { openSchedule() }
                }
                if !room.isMynote {
                    Divider()
                    Button("温度感を伝える", systemImage: "thermometer.medium") { choosingUrgency = true }
                }
            } label: {
                icon
            } primaryAction: {
                send()
            }
            .tint(Color.primary)
            .menuIndicator(.hidden)
            .accessibilityLabel("送信")
        }
    }

    private var editBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "pencil")
                .foregroundStyle(theme.accent)
            Text("メッセージを編集")
                .toocFont(.caption.bold())
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                withAnimation(.snappy) {
                    editing = nil
                    draft = ""
                }
            } label: {
                Image(systemName: "xmark")
                    .toocFont(.system(size: 13, weight: .semibold))
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
                    .toocFont(.caption.bold())
                Text(message.preview)
                    .toocFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                withAnimation(.snappy) { replyTo = nil }
            } label: {
                Image(systemName: "xmark")
                    .toocFont(.system(size: 13, weight: .semibold))
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
    /// Nothing happens (a preview).
    static let none = ToocMessageActions(moreReactions: {}, forward: {}, reply: {}, edit: {}, select: {},
                                         openPhoto: { _, _ in }, openFile: { _ in }, showOriginal: { _ in })

    var moreReactions: () -> Void
    var forward: () -> Void
    var reply: () -> Void
    var edit: () -> Void
    var select: () -> Void
    var openPhoto: (UIImage, CGRect) -> Void
    var openFile: (String) -> Void
    /// A reply's quote was tapped: go to the message it answers.
    var showOriginal: (UUID) -> Void
    var addToAlbum: () -> Void = {}
    /// 返信ツリー: the conversation this message is part of.
    var openThread: () -> Void = {}
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
    /// Waiting for the bubble flying in from the input field: hidden, reporting where it is.
    var arriving = false
    var onArrivingFrame: ((CGRect) -> Void)? = nil
    let actions: ToocMessageActions
    /// Where the reply quote is (a double tap there opens the tree instead).
    @State private var quoteFrame: CGRect = .zero

    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme
    @State private var dragX: CGFloat = 0
    @State private var armed = false
    @State private var showFull = false
    @State private var shownHeight: CGFloat = 0
    @State private var fullHeight: CGFloat = 0
    @State private var showReactions = false
    @State private var showLaters = false
    @State private var nudge = 0

    private static let replyDistance: CGFloat = 64
    private static let maxPull: CGFloat = 96
    private static let avatarSize: CGFloat = 36

    private var mine: Bool { message.senderID == store.me.id }
    /// You put it off (here or on another device).
    private var later: Bool { store.isLater(message.id) || message.laterBy.contains(store.me.id) }

    var body: some View {
        if message.system, case .text(let text) = message.kind {
            // Written by tooc for the group (someone added or left).
            Text(text)
                .toocFont(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(theme.theirBubble, in: Capsule())
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        } else if message.isUnsent {
            Text(mine ? "送信を取り消しました" : "\(store.displayName(message.senderID))が送信を取り消しました")
                .toocFont(.caption)
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
                    sender.nameText
                        .toocFont(.caption2)
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
            if message.failed {
                failedMark
            } else if last || message.sending {
                meta(alignment: .trailing)
            }
            bubbleWithReactions
        }
    }

    /// Couldn't be sent: tap to send again or give up.
    private var failedMark: some View {
        Menu {
            Button("再送", systemImage: "arrow.clockwise") {
                withAnimation(.snappy) { store.resend(message.id, in: room.id) }
            }
            ToocDestructiveButton("削除", systemImage: "trash") {
                withAnimation(.snappy) { store.discardFailed(message.id, in: room.id) }
            }
        } label: {
            Image(systemName: "exclamationmark.circle.fill")
                .toocFont(.system(size: 20))
                .foregroundStyle(.red)
                .frame(width: 28, height: 28)
        }
        .tint(Color.primary)
        .accessibilityLabel("送信できませんでした")
        .transition(.scale.combined(with: .opacity))
    }

    /// 既読 (with the mute mark beside it) above the time.
    private func meta(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
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
        .toocFont(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private var readLabel: String? {
        guard !room.isMynote, mine, message.readCount > 0 else { return nil }
        if room.isGroup { return "既読\(message.readCount)" }
        return "既読"
    }

    private var bubbleWithReactions: some View {
        VStack(alignment: mine ? .trailing : .leading, spacing: -6) {
            if let urgency = message.urgency {
                ToocUrgencyChip(urgency: urgency)
                    .padding(mine ? .trailing : .leading, ToocBubbleShape.tail + 2)
                    .padding(.bottom, 10)
            }
            bubble
                // あとで返信, for everyone to see: stuck to the bubble's outer top corner.
                .overlay(alignment: mine ? .topLeading : .topTrailing) {
                    if !message.laterBy.isEmpty {
                        Button { showLaters = true } label: {
                            ToocLaterMark(size: 28, count: message.laterBy.count)
                        }
                        .buttonStyle(.plain)
                        .offset(x: mine ? -12 : 12, y: -12)
                        .transition(.scale(scale: 0.1).combined(with: .opacity))
                        .accessibilityLabel("あとで返信 \(message.laterBy.count)人")
                    }
                }
                // Put on with a pop: it springs out of the corner and the hourglass flips.
                .animation(.spring(response: 0.38, dampingFraction: 0.52), value: message.laterBy)
                .sheet(isPresented: $showLaters) {
                    ToocLaterSheet(messageID: message.id, roomID: room.id)
                }
            if !message.reactions.isEmpty {
                reactions
                    .padding(mine ? .trailing : .leading, ToocBubbleShape.tail + 8)
                    .zIndex(1)
            }
        }
        // Shown from a reply: a little jump, so it stands out.
        .keyframeAnimator(initialValue: ToocNudge(), trigger: nudge) { content, value in
            content
                .scaleEffect(value.scale, anchor: mine ? .trailing : .leading)
                .rotationEffect(.degrees(value.angle))
        } keyframes: { _ in
            KeyframeTrack(\.scale) {
                SpringKeyframe(1.12, duration: 0.18)
                SpringKeyframe(0.96, duration: 0.16)
                SpringKeyframe(1.0, duration: 0.3)
            }
            KeyframeTrack(\.angle) {
                CubicKeyframe(-3, duration: 0.09)
                CubicKeyframe(3, duration: 0.12)
                CubicKeyframe(-2, duration: 0.12)
                CubicKeyframe(0, duration: 0.14)
            }
        }
        .onChange(of: highlighted) { _, on in if on { nudge += 1 } }
    }

    /// The reactions under the bubble: each emoji with its count, and the faces of who reacted. Tap for who did what.
    private var reactions: some View {
        let counts = Dictionary(grouping: message.reactions.values, by: { $0 }).mapValues(\.count)
        let order = ToocStore.emojis.filter { counts[$0] != nil } + counts.keys.filter { !ToocStore.emojis.contains($0) }.sorted()
        let people = message.reactions.keys.sorted().compactMap { $0 == store.me.id ? store.me : store.user($0) }
        let reacted = message.reactions[store.me.id] != nil
        return Button {
            showReactions = true
        } label: {
            HStack(spacing: 6) {
                HStack(spacing: 2) {
                    ForEach(order.prefix(4), id: \.self) { emoji in
                        Text(emoji).font(.system(size: 15))
                        if let count = counts[emoji], count > 1 {
                            Text("\(count)")
                                .toocFont(.system(size: 11, weight: .bold))
                                .foregroundStyle(.secondary)
                                .padding(.trailing, 2)
                        }
                    }
                }
                if room.isGroup || people.count > 1 {
                    HStack(spacing: -6) {
                        ForEach(people.prefix(3)) { person in
                            ToocAvatar(user: person, size: 18)
                                .overlay(Circle().strokeBorder(theme.card, lineWidth: 1.5))
                        }
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(reacted ? theme.accent.opacity(0.7) : Color.primary.opacity(0.08), lineWidth: reacted ? 1.5 : 1))
            .shadow(color: .black.opacity(0.12), radius: 4, y: 1.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("リアクション\(message.reactions.count)件")
        .sheet(isPresented: $showReactions) {
            ToocReactionsSheet(messageID: message.id, roomID: room.id)
        }
    }

    @ViewBuilder
    private var bubble: some View {
        Group {
            switch message.kind {
            case .text(let text):
                let shape = ToocBubbleShape(mine: mine, tail: first, joinedAbove: joinedAbove, joinedBelow: joinedBelow)
                VStack(alignment: .leading, spacing: 6) {
                    if let quotedMessage = quoted {
                        quote(quotedMessage)
                            .contentShape(Rectangle())
                            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { quoteFrame = $0 }
                            // Twice: the 返信ツリー. Once: go to the message it answers.
                            .onTapGesture(count: 2) { actions.openThread() }
                            .onTapGesture { actions.showOriginal(quotedMessage.id) }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityHint("返信元へ移動。ダブルタップで返信ツリー")
                            .accessibilityAction(named: "返信ツリー") { actions.openThread() }
                    }
                    longText(text)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
                .background(shape.fill(mine ? theme.myBubble : theme.theirBubble))
                .clipShape(shape)
                .background {
                    if !mine {
                        shape.fill(theme.theirBubble)
                            .shadow(color: .black.opacity(0.09), radius: 3, x: 0, y: 1.5)
                    }
                }
            case .photo(let file):
                // A photo has no tail and never joins: just the picture with rounded corners.
                ToocPhotoBubble(file: file, address: nil, open: actions.openPhoto)
                    .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
            case .remotePhoto(let address):
                ToocPhotoBubble(file: nil, address: address, open: actions.openPhoto)
                    .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
            case .sticker(let url):
                ToocStickerImage(url: url)
                    .frame(width: 136, height: 136)
                    .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
            case .note, .album:
                ToocBoardCard(message: message, roomID: room.id, mine: mine)
                    .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
            default:
                ToocCardBubble(message: message, room: room, mine: mine, openFile: actions.openFile)
                    .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
            }
        }
        .tint(theme.accent)
        .opacity(message.sending || message.failed ? 0.6 : 1)
        .opacity(arriving ? 0 : 1)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            if arriving { onArrivingFrame?(frame) }
        }
        .simultaneousGesture(SpatialTapGesture(count: 2, coordinateSpace: .global).onEnded { tap in
            guard quoted == nil || !quoteFrame.contains(tap.location) else { return }
            toggleLater()
        }, isEnabled: canMarkLater && !isPhoto)
        .sensoryFeedback(.impact(weight: .medium), trigger: later)
        .tint(Color.primary)
        .contextMenu {
            if !message.sending && !message.failed { menu }
        }
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
            ToocMenuButton("その他の絵文字", systemImage: "ellipsis", action: actions.moreReactions)
        }
        .controlGroupStyle(.palette)
        .menuActionDismissBehavior(.enabled)
        if !canMarkLater && !inThread {
            ToocMenuButton("返信", systemImage: "arrowshape.turn.up.left.fill", action: actions.reply)
        } else {
        Menu {
            ToocMenuButton("返信する", systemImage: "arrowshape.turn.up.left.fill", action: actions.reply)
            if canMarkLater {
                ToocMenuButton(later ? "あとで返信を解除" : "あとで返信をマーク", systemImage: later ? "xmark.circle" : "hourglass") {
                    toggleLater()
                }
            }
            if inThread {
                ToocMenuButton("返信ツリー", systemImage: "arrow.triangle.branch", action: actions.openThread)
            }
        } label: {
            Label("返信", systemImage: "arrowshape.turn.up.left.fill")
        }
        .tint(Color.primary)
        }
        if message.forwardable {
            ToocMenuButton("転送", systemImage: "arrowshape.turn.up.right", action: actions.forward)
        }
        if isPhoto, !message.sending, !message.failed, !room.isMynote {
            ToocMenuButton("アルバムに追加", systemImage: "photo.badge.plus", action: actions.addToAlbum)
        }
        if pinned {
            ToocMenuButton("ピン留めを解除", systemImage: "pin.slash") {
                withAnimation(.snappy) { store.unpin(message.id, in: room.id) }
            }
        } else {
            ToocMenuButton("ピン留め", systemImage: "pin") {
                withAnimation(.snappy) { store.pin(message, in: room.id) }
            }
        }
        if case .sticker(let url) = message.kind, !store.stickers.contains(where: { $0.url == url }) {
            ToocMenuButton("スタンプに追加", systemImage: "face.smiling") { store.saveSticker(url) }
        }
        if case .text(let text) = message.kind {
            ToocMenuButton("コピー", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
            ToocMenuButton("選択", systemImage: "selection.pin.in.out", action: actions.select)
            if mine {
                ToocMenuButton("編集", systemImage: "pencil", action: actions.edit)
            }
        }
        Divider()
        if mine {
            Button(role: .destructive) {
                withAnimation(.snappy) { store.unsend(message.id, in: room.id) }
            } label: {
                Label { Text("送信取消") } icon: { Self.red("arrow.uturn.backward") }
            }
        }
        Button(role: .destructive) {
            withAnimation(.snappy) { store.deleteMessage(message.id, in: room.id) }
        } label: {
            Label { Text("削除") } icon: { Self.red("trash") }
        }
    }

    /// A red symbol that stays red in the system's menu (which otherwise draws symbols in the text colour).
    private static func red(_ symbol: String) -> Image {
        let image = UIImage(systemName: symbol)?.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
        return image.map { Image(uiImage: $0) } ?? Image(systemName: symbol)
    }

    private var pinned: Bool { room.pinnedMessages.contains { $0.messageID == message.id } }

    /// Part of a conversation: it answers or continues something, or something answers or continues it.
    private var inThread: Bool {
        message.replyTo != nil || message.follows != nil
            || room.messages.contains { $0.replyTo == message.id || $0.follows == message.id }
    }

    /// Someone else's message can be put off to answer later.
    private var canMarkLater: Bool { !mine && !message.sending && !message.failed && !room.isMynote }

    private var isPhoto: Bool {
        switch message.kind {
        case .photo, .remotePhoto: true
        default: false
        }
    }

    private func toggleLater() {
        withAnimation(.snappy) { store.toggleLater(message, in: room.id) }
    }

    /// Long text stops at 14 lines, with すべてを表示 for the rest in a sheet. Short text is just itself.
    private func longText(_ text: String) -> some View {
        let color = mine ? Color.white : Color.primary
        return VStack(alignment: .leading, spacing: 6) {
            Text(ToocLinks.attributed(text, mentions: mentionNames, color: mine ? nil : theme.accent))
                .toocFont(.system(size: textSize))
                .foregroundStyle(color)
                .tint(mine ? Color.white : theme.accent)
                .lineLimit(14)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { shownHeight = $0 }
                // The whole text at the same width, unseen, to tell whether anything was cut.
                .background(alignment: .topLeading) {
                    Text(text)
                        .toocFont(.system(size: textSize))
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
            if fullHeight > shownHeight + 1 {
                Button("すべてを表示") { showFull = true }
                    .toocFont(.system(size: textSize * 0.88, weight: .semibold))
                    .foregroundStyle(mine ? Color.white : theme.accent)
                    .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $showFull) {
            NavigationStack {
                ScrollView {
                    Text(text)
                        .toocFont(.system(size: textSize))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                }
                .navigationTitle(store.displayName(message.senderID))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { showFull = false } label: { Image(systemName: "xmark").foregroundStyle(Color.primary) }
                            .accessibilityLabel("閉じる")
                    }
                }
            }
        }
    }

    /// The names the people called go by, as they may have been typed.
    private var mentionNames: [String] {
        message.mentions.flatMap { id -> [String] in
            guard let user = store.user(id) else { return [] }
            return [user.name, user.displayName]
        }
    }

    private var quoted: ToocMessage? {
        guard let id = message.replyTo else { return nil }
        return room.messages.first { $0.id == id }
    }

    private func quote(_ quoted: ToocMessage) -> some View {
        let name = store.displayName(quoted.senderID)
        return HStack(spacing: 6) {
            Capsule()
                .fill(mine ? Color.white.opacity(0.7) : theme.accent)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).toocFont(.caption.bold())
                Text(quoted.preview).toocFont(.caption).lineLimit(1)
            }
            .foregroundStyle(mine ? Color.white.opacity(0.85) : Color.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Reply swipe

    /// Shown in the space the drag opens on the right: grows with the drag, and is full once letting go would reply.
    private var replyIcon: some View {
        let progress = min(1, max(0, -dragX / Self.replyDistance))
        return Image(systemName: "arrowshape.turn.up.left.fill")
            .toocFont(.system(size: 18, weight: .semibold))
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
    static let tail: CGFloat = 6
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
            // Small, and out of the bubble's side a little below its top, so it reads as part of the bubble.
            horn.move(to: CGPoint(x: edge - out * 8, y: top + 6))
            // Upper edge: dips gently out to the tip, which stays below the bubble's top.
            horn.addQuadCurve(to: CGPoint(x: edge + out * Self.tail, y: top + 3),
                              control: CGPoint(x: edge + out * 2, y: top + 7.5))
            // Lower edge: swells back into the side.
            horn.addQuadCurve(to: CGPoint(x: edge - out * 0.5, y: top + 16),
                              control: CGPoint(x: edge + out * 4, y: top + 11))
            horn.addLine(to: CGPoint(x: edge - out * 8, y: top + 16))
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
                            .toocFont(.system(size: 30))
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
                    .toocFont(.headline)
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
                        Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Color.primary) }
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

/// The little jump of a message shown from a reply.
struct ToocNudge {
    var scale = 1.0
    var angle = 0.0
}

/// Text on its way from the input field into its new bubble.
struct ToocFlight: Identifiable {
    let id: UUID
    let text: String
    let from: CGRect
    var to: CGRect?
}

/// The flying text: it starts as the input field's line and ends as the bubble, filling with the bubble's colour,
/// stretching a little on the way.
struct ToocFlyingBubble: View, Animatable {
    let text: String
    let from: CGRect
    let to: CGRect
    let origin: CGPoint
    let size: CGFloat
    let fill: Color
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        let p = progress
        let rect = CGRect(x: from.minX + (to.minX - from.minX) * p,
                          y: from.minY + (to.minY - from.minY) * p,
                          width: max(1, from.width + (to.width - from.width) * p),
                          height: max(1, from.height + (to.height - from.height) * p))
        // Squeezed sideways and stretched upward mid-flight, like something soft being pulled.
        let pull = sin(min(max(p, 0), 1) * .pi)
        let fade = min(1, max(0, p * 1.6))
        return ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 18 + 4 * (1 - p), style: .continuous)
                .fill(fill.opacity(fade))
            // Laid out at the landing bubble's width the whole way, so it never shortens to …
            Text(text)
                .toocFont(.system(size: size))
                .foregroundStyle(Color.primary.opacity(1 - fade))
                .overlay(alignment: .leading) {
                    Text(text)
                        .toocFont(.system(size: size))
                        .foregroundStyle(Color.white.opacity(fade))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: max(1, to.width - 26 - ToocBubbleShape.tail), alignment: .leading)
                .padding(.horizontal, 13 + 3 * (1 - p))
        }
        .frame(width: rect.width, height: rect.height)
        .scaleEffect(x: 1 - 0.08 * pull, y: 1 + 0.1 * pull, anchor: .bottomTrailing)
        .position(x: rect.midX - origin.x, y: rect.midY - origin.y)
    }
}

// MARK: - 返信ツリー

/// A conversation on its own: where it began, every reply and つづき, oldest first. Writing here answers the last
/// message of the tree — or, when that one is yours, continues it (two in a row join up, as in the talk).
struct ToocThreadView: View {
    let roomID: String
    let messageID: UUID

    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if let room = store.room(roomID) {
                    content(room)
                } else {
                    ContentUnavailableView("トークが見つかりません", systemImage: "bubble.left.and.bubble.right")
                }
            }
            .navigationTitle("返信ツリー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Color.primary) }
                        .accessibilityLabel("閉じる")
                }
            }
            .background(theme.fill.ignoresSafeArea())
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func content(_ room: ToocRoom) -> some View {
        let thread = store.thread(messageID, in: roomID)
        let size = CGFloat(store.settings.textPoints)
        return ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(thread.enumerated()), id: \.element.id) { index, message in
                        let previous = index > 0 ? thread[index - 1] : nil
                        let next = index < thread.count - 1 ? thread[index + 1] : nil
                        let first = previous.map { !ToocRoomView.joins($0, message) } ?? true
                        let last = next.map { !ToocRoomView.joins(message, $0) } ?? true
                        ToocMessageRow(
                            message: message,
                            room: room,
                            first: first,
                            last: last,
                            joinedAbove: !first && message.isText && (previous?.isText ?? false),
                            joinedBelow: !last && message.isText && (next?.isText ?? false),
                            textSize: size,
                            actions: .none
                        )
                        .padding(.top, first && index > 0 ? 10 : 0)
                        .id(message.id)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .animation(.smooth(duration: 0.3), value: thread.map(\.id))
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: thread.count) {
                withAnimation(.smooth) { reader.scrollTo(thread.last?.id, anchor: .bottom) }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { input(thread) }
        }
    }

    private var trimmed: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func input(_ thread: [ToocMessage]) -> some View {
        let continuing = thread.last?.senderID == store.me.id
        return HStack(alignment: .bottom, spacing: 6) {
            TextField(continuing ? "続けて送信" : "ツリーに返信", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.vertical, 13)
                .padding(.leading, 16)
            if !trimmed.isEmpty {
                Button { send(thread) } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .toocFont(.system(size: 32))
                        .foregroundStyle(theme.accent)
                }
                .padding(.bottom, 6)
                .accessibilityLabel("送信")
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.trailing, 6)
        .animation(.snappy(duration: 0.2), value: trimmed.isEmpty)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 25, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    /// Answers the tree's last message; yours already, it continues it instead.
    private func send(_ thread: [ToocMessage]) {
        let text = trimmed
        guard !text.isEmpty, let last = thread.last else { return }
        withAnimation(.snappy) {
            if last.senderID == store.me.id {
                _ = store.send(.text(text), in: roomID, follows: last.id)
            } else {
                _ = store.send(.text(text), in: roomID, replyTo: last.id)
            }
            draft = ""
        }
    }
}

/// A thin line from someone's message down to the つづき sent to it from the other side.
struct ToocFollowLine: View {
    /// The message above is yours (the line runs from the right to the left).
    let fromMine: Bool

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            let left: CGFloat = 72
            let right = width - 36
            let start = fromMine ? right : left
            let end = fromMine ? left : right
            let turn: CGFloat = end > start ? 8 : -8
            Path { path in
                path.move(to: CGPoint(x: start, y: 0))
                path.addQuadCurve(to: CGPoint(x: start + turn, y: height / 2), control: CGPoint(x: start, y: height / 2))
                path.addLine(to: CGPoint(x: end - turn, y: height / 2))
                path.addQuadCurve(to: CGPoint(x: end, y: height), control: CGPoint(x: end, y: height / 2))
            }
            .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
        }
        .frame(height: 16)
        .accessibilityHidden(true)
    }
}
