import SwiftUI

/// What the deck's ⋯ menu does. The home card and the editor show the same menu, except 複製 (home only)
/// and ガイド (editor only).
struct DeckMenuActions {
    var rename: () -> Void
    /// Only on the home screen.
    var duplicate: (() -> Void)?
    /// Only in the editor.
    var toggleGuides: (() -> Void)?
    var showDetails: () -> Void
    var export: (ExportFormat) -> Void
    /// Only in the editor, where there's a slide on screen.
    var exportCurrent: ((ExportFormat) -> Void)?
    var toggleFavorite: () -> Void
    var delete: () -> Void
}

/// 名前を変更 / 複製 / ガイド / 詳細 / 書き出し / お気に入り / 削除.
struct DeckMenuItems: View {
    let deck: Deck
    let actions: DeckMenuActions

    var body: some View {
        Button("名前を変更", systemImage: "pencil", action: actions.rename)
        if let duplicate = actions.duplicate {
            Button("複製", systemImage: "plus.square.on.square", action: duplicate)
        }
        if let toggleGuides = actions.toggleGuides {
            Button(deck.showsGuides ? "ガイドを非表示" : "ガイドを表示", systemImage: "squareshape.split.2x2.dotted", action: toggleGuides)
        }
        Button("詳細", systemImage: "info.circle", action: actions.showDetails)
        Menu("書き出し", systemImage: "square.and.arrow.up") {
            Section("すべてのスライド") {
                Button("PDF (.pdf)", systemImage: "doc") { actions.export(.pdf) }
                Button("PowerPoint (.pptx)", systemImage: "doc.richtext") { actions.export(.pptx) }
            }
            if let exportCurrent = actions.exportCurrent {
                Section("このスライドのみ") {
                    Button("画像を写真に保存", systemImage: "photo") { exportCurrent(.png) }
                    Button("PDF (.pdf)", systemImage: "doc") { exportCurrent(.pdf) }
                }
            }
        }
        Button(deck.isFavorite ? "お気に入りから削除" : "お気に入りに追加", systemImage: deck.isFavorite ? "star.slash" : "star", action: actions.toggleFavorite)
        Divider()
        Button("削除", systemImage: "trash", role: .destructive, action: actions.delete)
    }
}
