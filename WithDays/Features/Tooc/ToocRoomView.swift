import PhotosUI
import SwiftUI
import UIKit

struct ToocPhotoFile: Identifiable, Hashable {
    let id: String
}

/// A talk room: the messages as bubbles, and the input bar fixed at the bottom.
/// Drag a bubble left to reply to it; drag it right (or from the edge) to go back.
struct ToocRoomView: View {
    let roomID: String

    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var draft = ""
    @State private var replyTo: ToocMessage?
    @FocusState private var focused: Bool

    @State private var scheduling = false
    @State private var scheduleDate = Date.now.addingTimeInterval(60 * 60)
    @State private var pickingPhoto = false
    @State private var photoItem: PhotosPickerItem?
    @State private var usingCamera = false
    @State private var viewing: ToocPhotoFile?
    @State private var searching = false
    @State private var highlight: UUID?
    @State private var showMembers = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmClear = false
    @State private var confirmLeave = false

    private var room: ToocRoom? { store.room(roomID) }

    var body: some View {
        Group {
            if let room {
                messages(room)
                    .safeAreaInset(edge: .bottom, spacing: 0) { inputBar(room) }
                    .toolbar { toolbar(room) }
                    .background((store.settings.background.color ?? Color(.systemBackground)).ignoresSafeArea())
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
        }
        .onDisappear {
            if store.openRoomID == roomID { store.openRoomID = nil }
            // Leaving with something typed keeps it, and the list shows the pencil.
            store.update(roomID) { $0.draft = draft }
        }
        .sheet(isPresented: $scheduling) { scheduleSheet }
        .sheet(isPresented: $searching) {
            ToocRoomSearchView(roomID: roomID) { id in
                searching = false
                highlight = id
            }
        }
        .sheet(isPresented: $showMembers) { ToocMembersView(roomID: roomID) }
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
        .fullScreenCover(isPresented: $usingCamera) {
            ToocCameraPicker { image in sendPhoto(image) }
                .ignoresSafeArea()
        }
        .fullScreenCover(item: $viewing) { ToocPhotoViewer(file: $0.id) }
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
            Text("このトークのメッセージと写真がすべて消えます。")
        }
        .confirmationDialog("グループを退会しますか？", isPresented: $confirmLeave, titleVisibility: .visible) {
            Button("退会", role: .destructive) {
                dismiss()
                store.leave(roomID)
            }
        }
    }

    // MARK: Messages

    private func messages(_ room: ToocRoom) -> some View {
        let list = room.sent
        let waiting = room.waiting
        let size = store.settings.textSize.points
        return ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, message in
                        let first = index == 0 || !Self.sameBurst(list[index - 1], message)
                        let last = index == list.count - 1 || !Self.sameBurst(message, list[index + 1])
                        ToocMessageRow(
                            message: message,
                            room: room,
                            first: first,
                            last: last,
                            textSize: size,
                            highlighted: highlight == message.id,
                            onReply: {
                                withAnimation(.snappy) { replyTo = message }
                                focused = true
                            },
                            onBack: { dismiss() },
                            onPhoto: { viewing = ToocPhotoFile(id: $0) }
                        )
                        .padding(.top, first && index > 0 ? 10 : 0)
                        .id(message.id)
                    }
                    if !waiting.isEmpty {
                        scheduledSection(waiting, size: size)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if list.isEmpty && waiting.isEmpty {
                    ToocStartTalkText(size: 17)
                }
            }
            .onChange(of: room.messages.count) {
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
                        .background(Color.brand.opacity(0.55), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
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

    /// Sent by the same person in the same minute: drawn as one joined stack.
    static func sameBurst(_ a: ToocMessage, _ b: ToocMessage) -> Bool {
        a.senderID == b.senderID && Calendar.current.isDate(a.date, equalTo: b.date, toGranularity: .minute)
    }

    // MARK: Sending

    private func send(silent: Bool = false) {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(.snappy) {
            store.send(.text(text), in: roomID, replyTo: replyTo?.id, silent: silent)
            draft = ""
            replyTo = nil
        }
    }

    private func schedule() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        withAnimation(.snappy) {
            store.send(.text(text), in: roomID, replyTo: replyTo?.id, at: scheduleDate)
            draft = ""
            replyTo = nil
        }
        scheduling = false
    }

    private func sendPhoto(_ image: UIImage) {
        guard let file = ToocPhotos.save(image) else { return }
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
            Button { searching = true } label: { Image(systemName: "magnifyingglass") }
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
                    Button("非表示", systemImage: "eye.slash") {
                        dismiss()
                        store.update(roomID) { $0.hidden = true }
                    }
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
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("その他")
    }

    private func inputBar(_ room: ToocRoom) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 2) {
                Menu {
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button("カメラ", systemImage: "camera") { usingCamera = true }
                    }
                    Button("写真を選ぶ", systemImage: "photo.on.rectangle") { pickingPhoto = true }
                    Button("時刻指定して送信", systemImage: "clock") { openSchedule() }
                        .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            .foregroundStyle(.primary)
            .padding(.horizontal, 2)
            .glassEffect(.regular.interactive(), in: .capsule)

            VStack(spacing: 0) {
                if let replyTo {
                    replyBar(replyTo)
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
                    if !draft.isEmpty {
                        sendButton(room)
                            .padding(.bottom, 6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.trailing, draft.isEmpty ? 16 : 6)
                .animation(.snappy(duration: 0.2), value: draft.isEmpty)
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: Self.barHeight / 2, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private static let barHeight: CGFloat = 48

    /// Tap: send. Hold: ふつうに送信 / ミュートメッセージで送信 / 時刻指定して送信.
    private func sendButton(_ room: ToocRoom) -> some View {
        Menu {
            Button("ふつうに送信", systemImage: "paperplane") { send() }
            if !room.isMynote {
                Button("ミュートメッセージで送信", systemImage: "bell.slash") { send(silent: true) }
            }
            Button("時刻指定して送信", systemImage: "clock") { openSchedule() }
        } label: {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 32))
                .foregroundStyle(Color.brand)
        } primaryAction: {
            send()
        }
        .menuIndicator(.hidden)
        .accessibilityLabel("送信")
    }

    private func openSchedule() {
        scheduleDate = Calendar.current.date(byAdding: .hour, value: 1, to: .now) ?? .now
        scheduling = true
    }

    /// [icon] ○○へ返信 over one line of the message, joined to the top of the input field.
    private func replyBar(_ message: ToocMessage) -> some View {
        let sender = store.user(message.senderID) ?? store.me
        return HStack(spacing: 8) {
            ToocAvatar(user: sender, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(sender.name)へ返信")
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

struct ToocMessageRow: View {
    let message: ToocMessage
    let room: ToocRoom
    /// The first and last of a burst (same person, same minute): only the first has the tail, icon and name.
    let first: Bool
    let last: Bool
    var textSize: CGFloat = 17
    var highlighted = false
    var onReply: () -> Void
    var onBack: () -> Void
    var onPhoto: (String) -> Void

    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @State private var dragX: CGFloat = 0
    @State private var armed = false
    @State private var backArmed = false

    private static let replyDistance: CGFloat = 64
    private static let backDistance: CGFloat = 90
    private static let avatarSize: CGFloat = 36

    private var mine: Bool { message.senderID == store.me.id }

    var body: some View {
        Group {
            if mine { myRow } else { theirRow }
        }
        .offset(x: dragX)
        .background(alignment: .trailing) { replyIcon }
        .contentShape(Rectangle())
        .simultaneousGesture(swipe)
        .sensoryFeedback(.impact(weight: .medium), trigger: armed) { _, new in new }
        .sensoryFeedback(.impact(weight: .light), trigger: backArmed) { _, new in new }
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
                    Text(sender.name)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.leading, 6)
                }
                HStack(alignment: .bottom, spacing: 5) {
                    bubble
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
            bubble
        }
    }

    /// Read count (groups) or 既読 (one-to-one, your own messages), above the time.
    private func meta(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            if message.sending {
                ProgressView().controlSize(.mini)
            } else {
                if message.silent {
                    Image(systemName: "bell.slash.fill")
                        .accessibilityLabel("ミュートメッセージ")
                }
                if let read = readLabel { Text(read) }
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

    @ViewBuilder
    private var bubble: some View {
        Group {
            switch message.kind {
            case .text(let text):
                let shape = ToocBubbleShape(mine: mine, tail: first, joinedAbove: !first, joinedBelow: !last)
                VStack(alignment: .leading, spacing: 6) {
                    if let quotedMessage = quoted { quote(quotedMessage) }
                    Text(text)
                        .font(.system(size: textSize))
                        .foregroundStyle(mine ? Color.white : Color.primary)
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 8)
                .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
                .background(shape.fill(mine ? Color.brand : Color(.secondarySystemBackground)))
                .clipShape(shape)
            case .photo(let file):
                // A photo has no tail: just the picture with rounded corners.
                photo(file)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
                    .onTapGesture { if let file { onPhoto(file) } }
            }
        }
        .overlay {
            if highlighted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.brand, lineWidth: 3)
                    .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
            }
        }
        .opacity(message.sending ? 0.6 : 1)
        .contextMenu { menu }
    }

    @ViewBuilder
    private func photo(_ file: String?) -> some View {
        if let file, let image = ToocPhotos.image(file) {
            let ratio = image.size.height / max(1, image.size.width)
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 200, height: min(280, max(120, 200 * ratio)))
                .clipped()
        } else {
            ZStack {
                Color(.tertiarySystemFill)
                Image(systemName: "photo.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(.secondary)
            }
            .frame(width: 180, height: 130)
        }
    }

    private var quoted: ToocMessage? {
        guard let id = message.replyTo else { return nil }
        return room.messages.first { $0.id == id }
    }

    private func quote(_ quoted: ToocMessage) -> some View {
        let name = store.user(quoted.senderID)?.name ?? ""
        return HStack(spacing: 6) {
            Capsule()
                .fill(mine ? Color.white.opacity(0.7) : Color.brand)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.caption.bold())
                Text(quoted.preview).font(.caption).lineLimit(1)
            }
            .foregroundStyle(mine ? Color.white.opacity(0.85) : Color.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var menu: some View {
        Button("返信", systemImage: "arrowshape.turn.up.left", action: onReply)
        if case .text(let text) = message.kind {
            Button("コピー", systemImage: "doc.on.doc") { UIPasteboard.general.string = text }
        }
        if mine {
            Button("送信取消", systemImage: "arrow.uturn.backward", role: .destructive) {
                withAnimation(.snappy) { store.deleteMessage(message.id, in: room.id) }
            }
        } else {
            Button("削除", systemImage: "trash", role: .destructive) {
                withAnimation(.snappy) { store.deleteMessage(message.id, in: room.id) }
            }
        }
    }

    // MARK: Swipes

    /// Shown in the space the drag opens on the right: grows with the drag, then pops once letting go would reply.
    private var replyIcon: some View {
        let progress = min(1, max(0, -dragX / Self.replyDistance))
        return Image(systemName: "arrowshape.turn.up.left.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.secondary)
            .scaleEffect(armed ? 1.35 : 0.4 + 0.6 * progress)
            .opacity(progress)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: armed)
            .padding(.trailing, 14)
            .frame(maxHeight: .infinity, alignment: .center)
    }

    /// Left: reply (follows the finger, then resists past the reply point). Right: back to the list.
    private var swipe: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let dx = value.translation.width
                guard abs(dx) > abs(value.translation.height) else {
                    if dragX != 0 { dragX = 0 }
                    return
                }
                if dx < 0 {
                    let pull = -dx
                    dragX = -(pull < Self.replyDistance ? pull : Self.replyDistance + (pull - Self.replyDistance) * 0.3)
                    let nowArmed = pull >= Self.replyDistance
                    if nowArmed != armed { armed = nowArmed }
                    if backArmed { backArmed = false }
                } else {
                    dragX = dx * 0.5
                    let nowArmed = dx >= Self.backDistance
                    if nowArmed != backArmed { backArmed = nowArmed }
                    if armed { armed = false }
                }
            }
            .onEnded { _ in
                if armed { onReply() }
                if backArmed { onBack() }
                armed = false
                backArmed = false
                withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) { dragX = 0 }
            }
    }
}

/// A bubble: fully rounded, with a small tail at the top outer corner on the first of a burst. Bubbles of one burst
/// keep their gaps but tighten the corners they share, so they read as one joined stack.
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
        let outerTop = tail ? 4 : (joinedAbove ? Self.joined : Self.radius)
        let outerBottom = joinedBelow ? Self.joined : Self.radius
        let radii = mine
            ? RectangleCornerRadii(topLeading: Self.radius, bottomLeading: Self.radius,
                                   bottomTrailing: outerBottom, topTrailing: outerTop)
            : RectangleCornerRadii(topLeading: outerTop, bottomLeading: outerBottom,
                                   bottomTrailing: Self.radius, topTrailing: Self.radius)
        var path = UnevenRoundedRectangle(cornerRadii: radii, style: .continuous).path(in: body)
        if tail {
            var point = Path()
            if mine {
                point.move(to: CGPoint(x: body.maxX - 10, y: body.minY))
                point.addLine(to: CGPoint(x: body.maxX + Self.tail - 1, y: body.minY))
                point.addQuadCurve(to: CGPoint(x: body.maxX, y: body.minY + 14),
                                   control: CGPoint(x: body.maxX + 1, y: body.minY + 3))
                point.addLine(to: CGPoint(x: body.maxX - 10, y: body.minY + 14))
            } else {
                point.move(to: CGPoint(x: body.minX + 10, y: body.minY))
                point.addLine(to: CGPoint(x: body.minX - Self.tail + 1, y: body.minY))
                point.addQuadCurve(to: CGPoint(x: body.minX, y: body.minY + 14),
                                   control: CGPoint(x: body.minX - 1, y: body.minY + 3))
                point.addLine(to: CGPoint(x: body.minX + 10, y: body.minY + 14))
            }
            point.closeSubpath()
            // A union, so the overlap never cancels out whichever way each part winds.
            path = path.union(point)
        }
        return path
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

/// A sent photo on black, to look at or share.
struct ToocPhotoViewer: View {
    let file: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = ToocPhotos.image(file) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
                if let image = ToocPhotos.image(file) {
                    ToolbarItem(placement: .topBarTrailing) {
                        ShareLink(item: Image(uiImage: image), preview: SharePreview("写真", image: Image(uiImage: image))) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }
}
