import SwiftUI

/// A service inside WithDays, as the list from ＋ shows it.
struct WithDaysService: Identifiable, Hashable {
    let mode: HomeMode
    let name: String
    let summary: String
    let icon: String
    var id: String { mode.rawValue }

    /// The order a new install starts with.
    static let all: [WithDaysService] = [
        WithDaysService(mode: .tooc, name: "tooc", summary: "友だちやグループとトークするメッセージアプリ", icon: "ServiceIconTooc"),
        WithDaysService(mode: .slides, name: "Slides", summary: "スライドを作って、そのまま発表", icon: "ServiceIconSlides"),
        WithDaysService(mode: .notes, name: "Notes", summary: "手書きと文字のノート。書類のスキャンも", icon: "ServiceIconNotes"),
        WithDaysService(mode: .todo, name: "ToDo", summary: "Appleのリマインダーをそのまま使うToDoリスト", icon: "ServiceIconTodo"),
        WithDaysService(mode: .go, name: "Go", summary: "最寄り駅の電車の時刻と、出かける前の準備", icon: "ServiceIconGo"),
        WithDaysService(mode: .mo, name: "Planner", summary: "収入と支出を記録して、お金の予定を立てる", icon: "ServiceIconPlanner"),
        WithDaysService(mode: .subs, name: "Subscribes", summary: "サブスクの支払いと更新日をまとめて管理", icon: "ServiceIconSubs"),
        WithDaysService(mode: .gallery, name: "Gallery", summary: "写真をアルバムで整理。ロックもできる", icon: "ServiceIconGallery"),
        WithDaysService(mode: .gmail, name: "Gmail", summary: "Gmail のメールを読む（複数アカウント対応）", icon: "ServiceIconGmail"),
    ]
}

/// The user's order of the services and their favourites (kept on the device).
@MainActor
@Observable
final class ServiceShelf {
    static let shared = ServiceShelf()

    private static let orderKey = "serviceOrder"
    private static let favoritesKey = "serviceFavorites"

    private(set) var order: [String]
    private(set) var favorites: Set<String>

    private init() {
        let defaults = UserDefaults.standard
        let known = WithDaysService.all.map(\.id)
        var saved = (defaults.stringArray(forKey: Self.orderKey) ?? []).filter(known.contains)
        // Services added since the order was saved go at the end.
        saved += known.filter { !saved.contains($0) }
        order = saved
        favorites = Set(defaults.stringArray(forKey: Self.favoritesKey) ?? []).intersection(known)
    }

    private func service(_ id: String) -> WithDaysService? { WithDaysService.all.first { $0.id == id } }

    var favoriteServices: [WithDaysService] { order.filter(favorites.contains).compactMap(service) }
    var otherServices: [WithDaysService] { order.filter { !favorites.contains($0) }.compactMap(service) }

    /// Moves rows within one section (favourites or the rest).
    func move(favorites inFavorites: Bool, from source: IndexSet, to destination: Int) {
        var favs = favoriteServices.map(\.id)
        var others = otherServices.map(\.id)
        if inFavorites { favs.move(fromOffsets: source, toOffset: destination) } else { others.move(fromOffsets: source, toOffset: destination) }
        order = favs + others
        save()
    }

    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }

    func toggleFavorite(_ id: String) {
        setFavorite([id], on: !favorites.contains(id))
    }

    func setFavorite(_ ids: Set<String>, on: Bool) {
        if on { favorites.formUnion(ids) } else { favorites.subtract(ids) }
        save()
    }

    private func save() {
        UserDefaults.standard.set(order, forKey: Self.orderKey)
        UserDefaults.standard.set(Array(favorites), forKey: Self.favoritesKey)
    }
}

/// A service's icon: square art with the rounded corners of an app icon.
struct ServiceIcon: View {
    let name: String
    var size: CGFloat = 52

    var body: some View {
        Image(name)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
    }
}

/// Holding ＋: every service with its icon and what it is, opened out of ＋ over the whole screen.
/// 選択 lets the rows be reordered and starred; a swipe to the right stars one too.
struct ServicePicker: View {
    var onPick: (HomeMode) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var shelf = ServiceShelf.shared
    @State private var selecting = false
    @State private var selection = Set<String>()

    private var allSelectedFavorite: Bool {
        !selection.isEmpty && selection.allSatisfy(shelf.isFavorite)
    }

    var body: some View {
        NavigationStack {
            List(selection: $selection) {
                let favorites = shelf.favoriteServices
                if !favorites.isEmpty {
                    Section("お気に入り") {
                        ForEach(favorites) { row($0) }
                            .onMove { shelf.move(favorites: true, from: $0, to: $1) }
                    }
                }
                Section(favorites.isEmpty ? "サービス" : "そのほか") {
                    ForEach(shelf.otherServices) { row($0) }
                        .onMove { shelf.move(favorites: false, from: $0, to: $1) }
                }
            }
            .environment(\.editMode, .constant(selecting ? .active : .inactive))
            .animation(.snappy, value: shelf.order)
            .animation(.snappy, value: shelf.favorites)
            .navigationTitle(selecting ? (selection.isEmpty ? "選択" : "\(selection.count)件選択") : "サービス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる", systemImage: "xmark") { dismiss() }
                }
                if selecting {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Button(allSelectedFavorite ? "お気に入りから外す" : "お気に入りに追加",
                               systemImage: allSelectedFavorite ? "star.fill" : "star") {
                            shelf.setFavorite(selection, on: !allSelectedFavorite)
                        }
                        .disabled(selection.isEmpty)
                        Button("完了", systemImage: "checkmark.circle.fill") {
                            withAnimation(.snappy) {
                                selecting = false
                                selection = []
                            }
                        }
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("選択", systemImage: "checkmark.circle") {
                            withAnimation(.snappy) { selecting = true }
                        }
                    }
                }
            }
        }
        .sensoryFeedback(.selection, trigger: shelf.favorites)
    }

    @ViewBuilder
    private func row(_ service: WithDaysService) -> some View {
        let favorite = shelf.isFavorite(service.id)
        Group {
            if selecting {
                rowContent(service, favorite: favorite)
            } else {
                Button {
                    onPick(service.mode)
                } label: {
                    rowContent(service, favorite: favorite)
                }
                .buttonStyle(.plain)
            }
        }
        .tag(service.id)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button(favorite ? "外す" : "お気に入り", systemImage: favorite ? "star.slash.fill" : "star.fill") {
                shelf.toggleFavorite(service.id)
            }
            .tint(.yellow)
        }
    }

    private func rowContent(_ service: WithDaysService, favorite: Bool) -> some View {
        HStack(spacing: 14) {
            ServiceIcon(name: service.icon, size: 52)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(service.name)
                        .font(.headline)
                    if favorite {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("お気に入り")
                    }
                }
                Text(service.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
