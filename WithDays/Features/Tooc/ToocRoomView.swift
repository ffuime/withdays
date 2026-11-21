import SwiftUI

/// A talk room: the messages as bubbles, and the input bar fixed at the bottom. Sending isn't built yet.
/// Drag a bubble left to reply to it; drag right anywhere to go back (the system's back swipe).
struct ToocRoomView: View {
    let roomID: String

    @Environment(ToocStore.self) private var store
    @Environment(\.toocUnimplemented) private var unimplemented
    @State private var draft = ""
    @State private var replyTo: ToocMessage?
    @FocusState private var focused: Bool

    private var room: ToocRoom? { store.rooms.first { $0.id == roomID } }

    var body: some View {
        Group {
            if let room {
                messages(room)
                    .safeAreaInset(edge: .bottom, spacing: 0) { inputBar(room) }
                    .toolbar { toolbar(room) }
            } else {
                ContentUnavailableView("トークが見つかりません", systemImage: "message")
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            draft = room?.draft ?? ""
            store.markRead(roomID)
        }
        .onDisappear {
            // Leaving with something typed keeps it, and the list shows the pencil.
            store.update(roomID) { $0.draft = draft }
        }
    }

    // MARK: Messages

    private func messages(_ room: ToocRoom) -> some View {
        let list = room.messages
        return ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(Array(list.enumerated()), id: \.element.id) { index, message in
                    let first = index == 0 || !Self.sameBurst(list[index - 1], message)
                    let last = index == list.count - 1 || !Self.sameBurst(message, list[index + 1])
                    ToocMessageRow(
                        message: message,
                        room: room,
                        first: first,
                        last: last,
                        onReply: { withAnimation(.snappy) { replyTo = message } }
                    )
                    .padding(.top, first && index > 0 ? 10 : 0)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if list.isEmpty {
                ToocStartTalkText(size: 17)
            }
        }
    }

    /// Sent by the same person in the same minute: drawn as one joined stack.
    static func sameBurst(_ a: ToocMessage, _ b: ToocMessage) -> Bool {
        a.senderID == b.senderID && Calendar.current.isDate(a.date, equalTo: b.date, toGranularity: .minute)
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
            Button(action: unimplemented) { Image(systemName: "magnifyingglass") }
                .accessibilityLabel("トーク内を検索")
            Button(action: unimplemented) { Image(systemName: "ellipsis") }
                .accessibilityLabel("その他")
        }
    }

    private func inputBar(_ room: ToocRoom) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            HStack(spacing: 2) {
                Button(action: unimplemented) {
                    Image(systemName: "plus").frame(width: 40, height: 40)
                }
                .accessibilityLabel("追加")
                Button(action: unimplemented) {
                    Image(systemName: "photo.on.rectangle.angled").frame(width: 40, height: 40)
                }
                .accessibilityLabel("画像")
            }
            .font(.system(size: 18, weight: .medium))
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
                        .padding(.vertical, 10)
                        .padding(.leading, 14)
                    if !draft.isEmpty {
                        // At the bottom, level with the last line, however many lines there are.
                        Button(action: unimplemented) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 30))
                                .foregroundStyle(Color.brand)
                        }
                        .padding(.bottom, 5)
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("送信")
                    }
                }
                .padding(.trailing, draft.isEmpty ? 14 : 5)
                .animation(.snappy(duration: 0.2), value: draft.isEmpty)
            }
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 8)
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
    var onReply: () -> Void

    @Environment(ToocStore.self) private var store
    @State private var dragX: CGFloat = 0
    @State private var armed = false

    private static let replyDistance: CGFloat = 64
    private static let avatarSize: CGFloat = 36

    private var mine: Bool { message.senderID == store.me.id }

    var body: some View {
        Group {
            if mine { myRow } else { theirRow }
        }
        .offset(x: dragX)
        .background(alignment: .trailing) { replyIcon }
        .contentShape(Rectangle())
        .simultaneousGesture(replyDrag)
        .sensoryFeedback(.impact(weight: .medium), trigger: armed) { _, new in new }
    }

    private var theirRow: some View {
        let sender = store.user(message.senderID)
        return HStack(alignment: .top, spacing: 8) {
            if first, let sender {
                ToocAvatar(user: sender, size: Self.avatarSize)
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
                    bubble(tail: first ? .leading : nil)
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
            bubble(tail: first ? .trailing : nil)
        }
    }

    /// Read count (groups) or 既読 (one-to-one, your own messages), above the time.
    private func meta(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            if message.sending {
                ProgressView().controlSize(.mini)
            } else {
                if let read = readLabel { Text(read) }
                Text(ToocTime.clock(message.date)).monospacedDigit()
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private var readLabel: String? {
        guard !room.isMynote, message.readCount > 0 else { return nil }
        if room.isGroup { return "既読\(message.readCount)" }
        return mine ? "既読" : nil
    }

    private func bubble(tail: HorizontalEdge?) -> some View {
        let shape = ToocBubbleShape(mine: mine, tail: tail != nil, joinedAbove: !first, joinedBelow: !last)
        return Group {
            switch message.kind {
            case .text(let text):
                Text(text)
                    .font(.body)
                    .foregroundStyle(mine ? Color.white : Color.primary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
            case .photo:
                ZStack {
                    Color(.tertiarySystemFill)
                    Image(systemName: "photo.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 180, height: 130)
            }
        }
        .padding(mine ? .trailing : .leading, ToocBubbleShape.tail)
        .background(shape.fill(mine ? Color.brand : Color(.secondarySystemBackground)))
        .clipShape(shape)
        .opacity(message.sending ? 0.6 : 1)
    }

    // MARK: Reply swipe

    /// Shown in the space the drag opens on the right: grows with the drag, then pops once letting go would reply.
    private var replyIcon: some View {
        let progress = min(1, -dragX / Self.replyDistance)
        return Image(systemName: "arrowshape.turn.up.left.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.secondary)
            .scaleEffect(armed ? 1.35 : 0.4 + 0.6 * progress)
            .opacity(progress)
            .animation(.spring(response: 0.25, dampingFraction: 0.5), value: armed)
            .padding(.trailing, 14)
            .frame(maxHeight: .infinity, alignment: .center)
    }

    private var replyDrag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let dx = value.translation.width
                // Leftward and mostly sideways only; rightward is left to the back swipe.
                guard dx < 0, abs(dx) > abs(value.translation.height) else {
                    if dragX != 0 { dragX = 0 }
                    return
                }
                // Follows the finger, then resists past the reply point.
                let pull = -dx
                dragX = -(pull < Self.replyDistance ? pull : Self.replyDistance + (pull - Self.replyDistance) * 0.3)
                let nowArmed = pull >= Self.replyDistance
                if nowArmed != armed { armed = nowArmed }
            }
            .onEnded { _ in
                if armed { onReply() }
                armed = false
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
