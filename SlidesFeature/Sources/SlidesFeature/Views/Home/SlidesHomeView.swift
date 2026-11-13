import SwiftData
import SwiftUI

/// The Slides feature: decks, the editor and the player. It owns its navigation and its own data store.
public struct SlidesHomeView: View {
    private let onClose: (() -> Void)?

    /// `onClose` adds a button (top right) for leaving the feature.
    public init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    public var body: some View {
        SlidesRoot(onClose: onClose)
            .modelContainer(SlidesStore.container)
    }
}

enum SlidesRoute: Hashable {
    case editor(UUID, slide: Int)
}

enum DeckSort: String, CaseIterable, Identifiable {
    case lastOpened, updatedNewest, updatedOldest, createdNewest, createdOldest, nameAscending, nameDescending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .lastOpened: "最終閲覧"
        case .updatedNewest: "更新が新しい"
        case .updatedOldest: "更新が古い"
        case .createdNewest: "作成が新しい"
        case .createdOldest: "作成が古い"
        case .nameAscending: "名前（あ→ん）"
        case .nameDescending: "名前（ん→あ）"
        }
    }

    func sorted(_ decks: [Deck]) -> [Deck] {
        let japanese = Locale(identifier: "ja_JP")
        let byName: (Deck, Deck) -> Bool = {
            $0.title.compare($1.title, options: [.caseInsensitive, .numeric, .widthInsensitive], locale: japanese) == .orderedAscending
        }
        switch self {
        case .lastOpened: return decks.sorted { $0.lastOpenedAt > $1.lastOpenedAt }
        case .updatedNewest: return decks.sorted { $0.updatedAt > $1.updatedAt }
        case .updatedOldest: return decks.sorted { $0.updatedAt < $1.updatedAt }
        case .createdNewest: return decks.sorted { $0.createdAt > $1.createdAt }
        case .createdOldest: return decks.sorted { $0.createdAt < $1.createdAt }
        case .nameAscending: return decks.sorted(by: byName)
        case .nameDescending: return decks.sorted { byName($1, $0) }
        }
    }
}

/// A title being asked for: a new deck, or a new name for one.
struct TitleRequest: Identifiable {
    enum Kind {
        case create
        case rename(Deck)
    }

    let kind: Kind
    let id = UUID()
}

struct SlidesRoot: View {
    let onClose: (() -> Void)?

    @Environment(\.modelContext) private var context
    @Query private var decks: [Deck]
    @Query private var imageTexts: [ImageTextEntry]

    @State private var path: [SlidesRoute] = []
    @AppStorage("slides.sort") private var sort = DeckSort.lastOpened
    @AppStorage("slides.favoritesOnly") private var favoritesOnly = false
    @State private var query = ""
    /// The query after a short pause, so typing stays smooth.
    @State private var searchQuery = ""
    @FocusState private var searchFocused: Bool
    /// The search field and controls float over the grid; they go up while scrolling down and come back on the way up.
    @State private var headerShown = true
    @State private var headerHeight: CGFloat = 110
    @State private var titleRequest: TitleRequest?
    @State private var details: Deck?
    @State private var deleting: Deck?
    @State private var export: ExportRequest?

    private let columns = [GridItem(.flexible(), spacing: 16, alignment: .top), GridItem(.flexible(), spacing: 16, alignment: .top)]

    var body: some View {
        NavigationStack(path: $path) {
            home
                .navigationTitle("Slides")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    if let onClose {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: onClose) {
                                Image(systemName: "calendar")
                                    .foregroundStyle(.primary)
                            }
                            .tint(.primary)
                            .accessibilityLabel("カレンダーに戻る")
                        }
                    }
                }
                .navigationDestination(for: SlidesRoute.self) { route in
                    switch route {
                    case .editor(let id, let slide):
                        EditorScreen(deckID: id, startSlide: slide, path: $path)
                    }
                }
        }
        .tint(SlidesTheme.brandText)
        .sheet(item: $titleRequest) { request in
            titleSheet(request)
        }
        .sheet(item: $details) { deck in
            DeckDetailsSheet(deck: deck)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert(
            "「\(deleting?.title ?? "")」を削除",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            presenting: deleting
        ) { deck in
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) { DeckActions.delete(deck, context: context) }
        } message: { _ in
            Text("この操作は取り消せません。")
        }
        .deckExport($export)
        .task {
            FontLibrary.shared.reload()
            ImageTextIndexer.shared.backfill(context: context)
        }
    }

    // MARK: Home

    private var visibleDecks: [Deck] {
        let filtered = favoritesOnly ? decks.filter(\.isFavorite) : decks
        return sort.sorted(filtered)
    }

    private var searching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var home: some View {
        let shown = visibleDecks
        let texts = Dictionary(imageTexts.map { ($0.key, $0.text) }, uniquingKeysWith: { first, _ in first })
        let results: [(deck: Deck, match: SlidesSearch.Match?)] = searching
            ? shown.compactMap { deck in SlidesSearch.match(deck, query: searchQuery, imageText: texts).map { (deck, $0) } }
            : shown.map { ($0, nil) }
        return ScrollView {
            LazyVGrid(columns: columns, spacing: 22) {
                ForEach(results, id: \.deck.id) { item in
                    DeckCard(
                        deck: item.deck, caption: item.match?.caption,
                        open: { open(item.deck) },
                        rename: { titleRequest = TitleRequest(kind: .rename(item.deck)) },
                        duplicate: { DeckActions.duplicate(item.deck, context: context) },
                        toggleGuides: {
                            item.deck.showsGuides.toggle()
                            try? context.save()
                        },
                        export: { export = ExportRequest(deck: item.deck, format: $0) },
                        toggleFavorite: { DeckActions.toggleFavorite(item.deck, context: context) },
                        showDetails: { details = item.deck },
                        delete: { deleting = item.deck }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, headerHeight + 8)
            .padding(.bottom, 110)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { old, new in
            // Scrolling down hides the header; the smallest move back up brings it back.
            let delta = new - old
            if new < 12 {
                if !headerShown { withAnimation(.snappy) { headerShown = true } }
            } else if delta > 6, headerShown, !searchFocused {
                withAnimation(.snappy) { headerShown = false }
            } else if delta < -1, !headerShown {
                withAnimation(.snappy) { headerShown = true }
            }
        }
        .overlay(alignment: .top) {
            header
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
                .offset(y: headerShown ? 0 : -headerHeight - 20)
                .opacity(headerShown ? 1 : 0)
        }
        .overlay {
            if decks.isEmpty {
                ContentUnavailableView {
                    Label("スライドがありません", systemImage: "rectangle.on.rectangle.angled")
                } description: {
                    Text("右下の＋から作成できます")
                }
            } else if searching, results.isEmpty {
                Text("一致するスライドがありません")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .bottomTrailing) { fab }
        .task(id: query) {
            // Live results, a moment after the last keystroke.
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            searchQuery = query
        }
        .animation(.snappy, value: favoritesOnly)
        .animation(.snappy, value: sort)
    }

    private var header: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("検索", text: $query)
                        .focused($searchFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("消去")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 44)
                .glassEffect(.regular.interactive(), in: .capsule)
                if searchFocused {
                    Button {
                        query = ""
                        searchQuery = ""
                        searchFocused = false
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 44, height: 44)
                            .glassEffect(.regular.interactive(), in: .circle)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("キャンセル")
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            HStack(spacing: 10) {
                Spacer()
                Picker("表示", selection: $favoritesOnly) {
                    Text("すべて").tag(false)
                    Text("お気に入り").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Menu {
                    Picker("並べ替え", selection: $sort) {
                        ForEach(DeckSort.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(sort.label)
                            .font(.system(size: 14, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 14)
                    .frame(height: 36)
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
                .accessibilityLabel("並べ替え：\(sort.label)")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .animation(.snappy, value: searchFocused)
    }

    private var fab: some View {
        Button {
            titleRequest = TitleRequest(kind: .create)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26, weight: .semibold))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(SlidesTheme.brand)
        .foregroundStyle(.white)
        .padding(20)
        .accessibilityLabel("新規作成")
    }

    @ViewBuilder
    private func titleSheet(_ request: TitleRequest) -> some View {
        switch request.kind {
        case .create:
            TitleInputView(mode: .create) { title in
                let deck = DeckActions.create(title: title, context: context)
                // After the sheet has gone, so the push isn't lost.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { open(deck) }
            }
            .presentationDetents([.large])
        case .rename(let deck):
            TitleInputView(mode: .rename, initial: deck.title) { title in
                DeckActions.rename(deck, to: title, context: context)
            }
            .presentationDetents([.large])
        }
    }

    private func open(_ deck: Deck, slide: Int = 0) {
        searchFocused = false
        deck.lastOpenedAt = .now
        try? context.save()
        path.append(.editor(deck.id, slide: slide))
    }
}

/// A deck in the grid: its first slide (a star at its corner for favorites), its title and a ⋯ menu.
/// Holding the card shows the same menu.
struct DeckCard: View {
    let deck: Deck
    let caption: String?
    var open: () -> Void
    var rename: () -> Void
    var duplicate: () -> Void
    var toggleGuides: () -> Void
    var export: (ExportFormat) -> Void
    var toggleFavorite: () -> Void
    var showDetails: () -> Void
    var delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: open) {
                Group {
                    if let first = deck.sortedPages.first {
                        SlideThumbnail(data: first.data, deck: deck.id, width: 180, cornerRadius: 12)
                    } else {
                        RoundedRectangle(cornerRadius: 12).fill(Color.white).aspectRatio(16 / 9, contentMode: .fit)
                    }
                }
                .overlay(alignment: .topLeading) {
                    if deck.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color(red: 0.97, green: 0.75, blue: 0.1))
                            .padding(5)
                            .background(Circle().fill(Color.white.opacity(0.9)))
                            .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                            .padding(6)
                            .accessibilityLabel("お気に入り")
                    }
                }
                .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .contextMenu { menuItems }
            .accessibilityLabel(deck.title)
            HStack(alignment: .center, spacing: 4) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(deck.title)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if let caption {
                        Text(caption)
                            .font(.system(size: 11))
                            .foregroundStyle(SlidesTheme.brandText)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: open)
                Menu {
                    menuItems
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("その他")
            }
        }
    }

    /// The same menu as the editor's ⋯.
    private var menuItems: some View {
        DeckMenuItems(deck: deck, actions: DeckMenuActions(
            rename: rename, duplicate: duplicate, toggleGuides: toggleGuides, showDetails: showDetails,
            export: export, exportCurrent: nil, toggleFavorite: toggleFavorite, delete: delete
        ))
    }
}
