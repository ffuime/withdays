import SwiftUI
import UIKit

/// The long-press menu on a message: which message, where its bubble is, where each choice is on screen, and the one
/// under the finger. The finger that opened it can slide straight onto a reaction or an action and let go.
@MainActor
@Observable
final class ToocMessageMenu {
    var message: ToocMessage?
    var bubble: CGRect = .zero
    var hovered: String?
    /// What the finger let go on; the room carries it out.
    var chosen: String?
    @ObservationIgnored var frames: [String: CGRect] = [:]

    func open(_ message: ToocMessage, bubble: CGRect) {
        frames = [:]
        hovered = nil
        self.bubble = bubble
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) { self.message = message }
    }

    func track(_ point: CGPoint) {
        let hit = frames.first { $0.value.contains(point) }?.key
        if hit != hovered { hovered = hit }
    }

    func close() {
        withAnimation(.snappy(duration: 0.2)) {
            message = nil
            hovered = nil
        }
    }
}

enum ToocMenuAction: String {
    case more, reply, copy, select, edit, unsend, delete

    var title: String {
        switch self {
        case .more: "その他の絵文字"
        case .reply: "返信"
        case .copy: "コピー"
        case .select: "選択"
        case .edit: "編集"
        case .unsend: "送信取消"
        case .delete: "削除"
        }
    }

    var symbol: String {
        switch self {
        case .more: "ellipsis"
        case .reply: "arrowshape.turn.up.left"
        case .copy: "doc.on.doc"
        case .select: "selection.pin.in.out"
        case .edit: "pencil"
        case .unsend: "arrow.uturn.backward"
        case .delete: "trash"
        }
    }

    var destructive: Bool { self == .unsend || self == .delete }
}

/// Dims the talk except the pressed bubble, with big reactions just above it and the actions just below.
struct ToocMessageMenuOverlay: View {
    let menu: ToocMessageMenu
    let message: ToocMessage
    let mine: Bool
    let favorites: [String]
    var perform: (String) -> Void

    @Environment(\.toocTheme) private var theme

    private static let barHeight: CGFloat = 56
    private static let rowHeight: CGFloat = 46
    private static let menuWidth: CGFloat = 230

    private var actions: [ToocMenuAction] {
        var list: [ToocMenuAction] = [.reply]
        if message.isText {
            list += [.copy, .select]
            if mine { list.append(.edit) }
        }
        if mine { list.append(.unsend) }
        list.append(.delete)
        return list
    }

    var body: some View {
        GeometryReader { proxy in
            let origin = proxy.frame(in: .global).origin
            let bubble = menu.bubble.offsetBy(dx: -origin.x, dy: -origin.y)
            let menuHeight = CGFloat(actions.count) * Self.rowHeight
            let barWidth = CGFloat(favorites.count + 1) * 48 + 12
            // Below the bubble if there's room, otherwise everything goes above it.
            let below = bubble.maxY + 10 + menuHeight + 20 < proxy.size.height
            let barY = max(Self.barHeight / 2 + 60, bubble.minY - 10 - Self.barHeight / 2
                           - (below ? 0 : menuHeight + 10))
            let menuY = below ? bubble.maxY + 10 + menuHeight / 2 : bubble.minY - 10 - menuHeight / 2
            ZStack {
                // Everything but the bubble darkens; a tap there closes.
                Rectangle()
                    .fill(.black.opacity(0.28))
                    .mask {
                        ZStack {
                            Rectangle()
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .frame(width: bubble.width + 6, height: bubble.height + 6)
                                .position(x: bubble.midX, y: bubble.midY)
                                .blendMode(.destinationOut)
                        }
                        .compositingGroup()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { menu.close() }
                reactions
                    .frame(width: barWidth, height: Self.barHeight)
                    .position(x: horizontal(bubble, width: barWidth, in: proxy.size.width), y: barY)
                    .transition(.scale(scale: 0.6, anchor: mine ? .bottomTrailing : .bottomLeading).combined(with: .opacity))
                actionList
                    .frame(width: Self.menuWidth, height: menuHeight)
                    .position(x: horizontal(bubble, width: Self.menuWidth, in: proxy.size.width), y: menuY)
                    .transition(.scale(scale: 0.8, anchor: mine ? .topTrailing : .topLeading).combined(with: .opacity))
            }
        }
        .ignoresSafeArea()
        .sensoryFeedback(.selection, trigger: menu.hovered) { _, new in new != nil }
    }

    /// Lined up with the bubble's outer edge, kept on screen.
    private func horizontal(_ bubble: CGRect, width: CGFloat, in total: CGFloat) -> CGFloat {
        let x = mine ? bubble.maxX - width / 2 : bubble.minX + width / 2
        return min(max(x, width / 2 + 12), total - width / 2 - 12)
    }

    private var reactions: some View {
        HStack(spacing: 0) {
            ForEach(favorites, id: \.self) { emoji in
                let id = "emoji:\(emoji)"
                Button { perform(id) } label: {
                    Text(emoji)
                        .font(.system(size: 30))
                        .frame(width: 48, height: 48)
                        .scaleEffect(menu.hovered == id ? 1.35 : 1)
                        .offset(y: menu.hovered == id ? -6 : 0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: menu.hovered)
                }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { menu.frames[id] = $0 }
            }
            Button { perform(ToocMenuAction.more.rawValue) } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.primary.opacity(menu.hovered == ToocMenuAction.more.rawValue ? 0.18 : 0.08)))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("その他の絵文字")
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                menu.frames[ToocMenuAction.more.rawValue] = $0
            }
        }
        .padding(.horizontal, 6)
        .glassEffect(.regular, in: .capsule)
    }

    private var actionList: some View {
        VStack(spacing: 0) {
            ForEach(actions, id: \.self) { action in
                Button { perform(action.rawValue) } label: {
                    HStack {
                        Text(action.title)
                        Spacer()
                        Image(systemName: action.symbol)
                    }
                    .font(.body)
                    .foregroundStyle(action.destructive ? Color.red : Color.primary)
                    .padding(.horizontal, 16)
                    .frame(height: Self.rowHeight)
                    .background(Color.primary.opacity(menu.hovered == action.rawValue ? 0.1 : 0))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { menu.frames[action.rawValue] = $0 }
                if action != actions.last {
                    Divider().padding(.leading, 16)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - Every emoji

/// All the emoji, by group. Tap one to react; with 編集, swap one of the five favourites for it.
struct ToocEmojiPicker: View {
    var onPick: (String) -> Void

    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var editing = false
    @State private var slot = 0

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 8)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    favoritesRow
                    ForEach(ToocEmoji.groups, id: \.title) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            LazyVGrid(columns: Self.columns, spacing: 4) {
                                ForEach(group.emoji, id: \.self) { emoji in
                                    Button { pick(emoji) } label: {
                                        Text(emoji)
                                            .font(.system(size: 30))
                                            .frame(maxWidth: .infinity, minHeight: 44)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle(editing ? "よく使う絵文字を入れ替え" : "リアクション")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editing ? "完了" : "編集") { withAnimation(.snappy) { editing.toggle() } }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// The five favourites. While editing, tap one, then any emoji below to put there.
    private var favoritesRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(editing ? "入れ替える場所を選んで、下の絵文字をタップ" : "よく使う")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                ForEach(Array(store.settings.favoriteReactions.enumerated()), id: \.offset) { index, emoji in
                    Button {
                        if editing { slot = index } else { pick(emoji) }
                    } label: {
                        Text(emoji)
                            .font(.system(size: 32))
                            .frame(maxWidth: .infinity, minHeight: 52)
                            .background(theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                if editing && slot == index {
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .strokeBorder(theme.accent, lineWidth: 2.5)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pick(_ emoji: String) {
        if editing {
            var favorites = store.settings.favoriteReactions
            guard favorites.indices.contains(slot) else { return }
            if let existing = favorites.firstIndex(of: emoji) { favorites[existing] = favorites[slot] }
            favorites[slot] = emoji
            withAnimation(.snappy) {
                store.settings.favoriteReactions = favorites
                slot = (slot + 1) % favorites.count
            }
        } else {
            onPick(emoji)
            dismiss()
        }
    }
}

enum ToocEmoji {
    struct EmojiGroup {
        let title: String
        let emoji: [String]
    }

    static let groups: [EmojiGroup] = [
        EmojiGroup(title: "顔", emoji: make([0x1F600...0x1F64F, 0x1F910...0x1F92F, 0x1F970...0x1F97A, 0x1FAE0...0x1FAE8])),
        EmojiGroup(title: "手・人", emoji: make([0x1F440...0x1F450, 0x1F466...0x1F487, 0x1F90C...0x1F90F, 0x1F930...0x1F93A,
                                            0x1FAF0...0x1FAF8])),
        EmojiGroup(title: "ハート・記号", emoji: ["❤️", "🧡", "💛", "💚", "💙", "💜", "🤎", "🖤", "🤍", "❣️", "‼️", "⁉️"] + make([0x1F493...0x1F49F, 0x2763...0x2764, 0x1F4A2...0x1F4AF, 0x2705...0x2705,
                                               0x274C...0x274C, 0x2728...0x2728, 0x1F525...0x1F525])),
        EmojiGroup(title: "動物・自然", emoji: make([0x1F400...0x1F43F, 0x1F980...0x1F9AE, 0x1F330...0x1F344, 0x1F308...0x1F31F])),
        EmojiGroup(title: "食べもの", emoji: make([0x1F345...0x1F37F, 0x1F950...0x1F96F])),
        EmojiGroup(title: "活動・もの", emoji: make([0x1F380...0x1F3CA, 0x1F4A0...0x1F4A1, 0x1F4B0...0x1F4FF, 0x26BD...0x26BE])),
        EmojiGroup(title: "乗りもの・場所", emoji: make([0x1F680...0x1F6C5, 0x1F3E0...0x1F3F0])),
    ]

    private static func make(_ ranges: [ClosedRange<UInt32>]) -> [String] {
        ranges.flatMap { $0 }
            .compactMap { Unicode.Scalar($0) }
            .filter { $0.properties.isEmojiPresentation }
            .map { String($0) }
    }
}
