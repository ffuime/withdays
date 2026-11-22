import SwiftUI
import UIKit

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
