import PhotosUI
import SwiftUI

enum GalleryRoute: Hashable {
    /// The photos to page through, and the one opened.
    case viewer([String], String)
    case album(String)
    case trash
}

/// Gallery: photos and videos kept only in this app. A 5×5 grid, albums (some locked), ゴミ箱 and Holder.
struct GalleryView: View {
    var onCalendar: () -> Void
    var onHolder: () -> Void

    @State private var store = GalleryStore.shared
    @State private var path: [GalleryRoute] = []
    @State private var showAlbums = false
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: $path) {
            GalleryGridScreen(albumID: nil, zoom: zoom, onCalendar: onCalendar) {
                showAlbums = true
            }
            .navigationDestination(for: GalleryRoute.self) { route in
                GalleryDestination(route: route, zoom: zoom)
            }
        }
        .environment(store)
        .galleryNotice(store)
        .sheet(isPresented: $showAlbums) {
            GalleryAlbumsSheet {
                showAlbums = false
                onHolder()
            }
            .environment(store)
            // Grows out of the album button.
            .navigationTransition(.zoom(sourceID: "albums", in: zoom))
        }
    }
}

/// Where a route leads, the same in Gallery and in the album sheet.
struct GalleryDestination: View {
    let route: GalleryRoute
    let zoom: Namespace.ID

    var body: some View {
        switch route {
        case .viewer(let ids, let start):
            GalleryViewer(ids: ids, start: start)
                .navigationTransition(.zoom(sourceID: start, in: zoom))
        case .album(let id):
            GalleryGridScreen(albumID: id, zoom: zoom)
        case .trash:
            GalleryTrashView()
        }
    }
}

/// The grid of Gallery or of one album, with selecting, filtering and the ＋ button.
struct GalleryGridScreen: View {
    /// nil: all of Gallery.
    let albumID: String?
    let zoom: Namespace.ID
    /// Gallery only: back to the calendar, and the album list.
    var onCalendar: (() -> Void)?
    var onAlbums: (() -> Void)?

    @Environment(GalleryStore.self) private var store
    @State private var selecting = false
    @State private var selected: Set<String> = []
    @State private var picking = false
    @State private var picked: [PhotosPickerItem] = []
    @State private var camera = false
    @State private var addingToAlbum: [String]?
    @State private var confirmDelete = false

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 5)

    private var isRoot: Bool { albumID == nil }

    var body: some View {
        let items = store.items(in: albumID)
        let ids = items.map(\.id)
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: 2) {
                ForEach(items) { item in
                    cell(item, ids: ids)
                }
            }
            if !items.isEmpty {
                footer(items)
                    .padding(.top, 14)
            }
            Color.clear.frame(height: 110)
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView {
                    Label(store.favoritesOnly ? "お気に入りはありません" : "写真がありません",
                          systemImage: store.favoritesOnly ? "heart" : "photo.on.rectangle")
                } description: {
                    Text(store.favoritesOnly ? "写真を開いて♡を押すと、ここに表示されます。" : "＋で写真を追加、長押しでカメラを開けます。")
                }
            }
        }
        .overlay(alignment: .top) {
            if store.importing > 0 {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("\(store.importing)件を読み込み中")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular, in: .capsule)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: store.importing > 0)
        .overlay(alignment: .bottom) { bottomBar(items) }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar(items) }
        .photosPicker(isPresented: $picking, selection: $picked, maxSelectionCount: nil, selectionBehavior: .ordered,
                      matching: .any(of: [.images, .videos]), preferredItemEncoding: .current)
        .onChange(of: picked) { _, new in
            guard !new.isEmpty else { return }
            store.importPicked(new, into: albumID)
            picked = []
        }
        .fullScreenCover(isPresented: $camera) {
            GalleryCameraView(albumID: albumID)
        }
        .sheet(item: Binding(get: { addingToAlbum.map(GalleryIDs.init) }, set: { addingToAlbum = $0?.ids })) { ids in
            GalleryAddToAlbumSheet(ids: ids.ids) {
                endSelecting()
            }
            .environment(store)
        }
        .alert("\(selected.count)項目を削除しますか？", isPresented: $confirmDelete) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                withAnimation(.snappy) { store.trash(selected) }
                endSelecting()
            }
        } message: {
            Text("「最近削除した項目」に30日間残ります。")
        }
    }

    private var title: String {
        if selecting {
            return selected.isEmpty ? "項目を選択" : "\(selected.count)項目を選択"
        }
        return store.album(albumID)?.name ?? ""
    }

    // MARK: Cells

    @ViewBuilder
    private func cell(_ item: GalleryItem, ids: [String]) -> some View {
        let square = Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay { GalleryThumb(item: item) }
            .clipped()
            .overlay(alignment: .bottom) { GalleryCellBadges(item: item) }
            .contentShape(Rectangle())
        if selecting {
            square
                .overlay {
                    if selected.contains(item.id) {
                        Color.white.opacity(0.25)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    GalleryCheck(on: selected.contains(item.id))
                        .padding(4)
                }
                .onTapGesture {
                    if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                }
        } else {
            NavigationLink(value: GalleryRoute.viewer(ids, item.id)) {
                square
            }
            .buttonStyle(.plain)
            .matchedTransitionSource(id: item.id, in: zoom)
        }
    }

    private func footer(_ items: [GalleryItem]) -> some View {
        let videos = items.filter(\.isVideo).count
        let photos = items.count - videos
        let parts = [photos > 0 ? "写真\(photos)枚" : nil, videos > 0 ? "ビデオ\(videos)本" : nil].compactMap { $0 }
        return Text(parts.joined(separator: "、"))
            .font(.system(size: 13, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(.secondary)
    }

    // MARK: Bars

    @ToolbarContentBuilder
    private func toolbar(_ items: [GalleryItem]) -> some ToolbarContent {
        if let onCalendar {
            ToolbarItem(placement: .topBarLeading) {
                GalleryPill(symbol: "chevron.left", action: onCalendar)
                    .accessibilityLabel("カレンダーに戻る")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 0) {
                if selecting {
                    Button {
                        if selected.count == items.count { selected = [] } else { selected = Set(items.map(\.id)) }
                    } label: {
                        Text(selected.count == items.count && !items.isEmpty ? "選択解除" : "すべて")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.horizontal, 14)
                            .frame(height: 38)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    filterMenu
                }
                Button {
                    withAnimation(.snappy) {
                        if selecting { endSelecting() } else { selecting = true }
                    }
                } label: {
                    Image(systemName: selecting ? "xmark" : "checkmark.circle")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 46, height: 38)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(selecting ? "選択をやめる" : "選択")
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private var filterMenu: some View {
        @Bindable var store = store
        return Menu {
            Toggle(isOn: $store.favoritesOnly) {
                Label("お気に入りのみ", systemImage: "heart")
            }
            Divider()
            Picker("並べ替え", selection: $store.sort) {
                ForEach(GallerySort.allCases) { sort in
                    Text(sort.label).tag(sort)
                }
            }
            Divider()
            Toggle(isOn: $store.oldestFirst) {
                Label("古い順", systemImage: "arrow.up.arrow.down")
            }
        } label: {
            Image(systemName: store.favoritesOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(store.favoritesOnly ? Color.brand : Color.primary)
                .frame(width: 46, height: 38)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("しぼりこみ")
    }

    @ViewBuilder
    private func bottomBar(_ items: [GalleryItem]) -> some View {
        if selecting {
            selectionBar(items)
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            HStack(alignment: .bottom) {
                if let onAlbums {
                    Button(action: onAlbums) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 56, height: 56)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .matchedTransitionSource(id: "albums", in: zoom)
                    .accessibilityLabel("アルバム")
                }
                Spacer()
                GalleryAddButton {
                    picking = true
                } onHold: {
                    camera = true
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
            .transition(.opacity)
        }
    }

    private func selectionBar(_ items: [GalleryItem]) -> some View {
        let chosen = items.filter { selected.contains($0.id) }
        let allFavorite = !chosen.isEmpty && chosen.allSatisfy(\.favorite)
        return HStack(spacing: 0) {
            ShareLink(items: chosen.map { store.url($0) }) {
                barIcon("square.and.arrow.up")
            }
            .disabled(chosen.isEmpty)
            Button {
                addingToAlbum = chosen.map(\.id)
            } label: {
                barIcon("rectangle.stack.badge.plus")
            }
            .disabled(chosen.isEmpty)
            Button {
                store.setFavorite(selected, !allFavorite)
            } label: {
                barIcon(allFavorite ? "heart.fill" : "heart")
            }
            .disabled(chosen.isEmpty)
            if let albumID {
                Button {
                    withAnimation(.snappy) { store.remove(selected, from: albumID) }
                    endSelecting()
                } label: {
                    barIcon("rectangle.stack.badge.minus")
                }
                .disabled(chosen.isEmpty)
                .accessibilityLabel("アルバムから外す")
            }
            Button {
                confirmDelete = true
            } label: {
                barIcon("trash", color: .red)
            }
            .disabled(chosen.isEmpty)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func barIcon(_ symbol: String, color: Color = .primary) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(color)
            .frame(width: 54, height: 50)
            .contentShape(Rectangle())
    }

    private func endSelecting() {
        withAnimation(.snappy) {
            selecting = false
            selected = []
        }
    }
}

/// Identifiable ids for a sheet.
struct GalleryIDs: Identifiable {
    let ids: [String]
    var id: String { ids.joined(separator: ",") }
}

// MARK: Shared parts

/// A cell's thumbnail, loaded off the main thread.
struct GalleryThumb: View {
    let item: GalleryItem
    @State private var image: UIImage?

    var body: some View {
        Rectangle()
            .fill(Color(.secondarySystemFill))
            .overlay {
                if let image = image ?? GalleryImages.cachedThumb(item.file) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .task(id: item.file) {
                image = await GalleryImages.thumb(item)
            }
    }
}

/// A video's length and the favorite heart, along a cell's bottom.
struct GalleryCellBadges: View {
    let item: GalleryItem

    var body: some View {
        HStack(spacing: 2) {
            if item.favorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9, weight: .bold))
            }
            Spacer(minLength: 0)
            if let duration = item.duration {
                Text(Self.time(duration))
                    .font(.system(size: 10, weight: .semibold))
                    .monospacedDigit()
            }
        }
        .foregroundStyle(.white)
        .shadow(color: .black.opacity(0.5), radius: 2)
        .padding(.horizontal, 4)
        .padding(.bottom, 3)
    }

    static func time(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

struct GalleryCheck: View {
    let on: Bool

    var body: some View {
        Image(systemName: on ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, on ? Color.brand : Color.black.opacity(0.15))
            .shadow(color: .black.opacity(0.3), radius: 2)
    }
}

/// A glass pill in the top bar.
struct GalleryPill: View {
    let symbol: String
    var color: Color = .primary
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 52, height: 38)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .capsule)
    }
}

/// The blue ＋: a tap adds from the photo library, holding opens the (silent) camera.
struct GalleryAddButton: View {
    var onTap: () -> Void
    var onHold: () -> Void

    var body: some View {
        Image(systemName: "plus")
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 56)
            .glassEffect(.regular.tint(Color.brand).interactive(), in: .circle)
            .contentShape(Circle())
            .onTapGesture(perform: onTap)
            .onLongPressGesture(minimumDuration: 0.45, perform: onHold)
            .accessibilityLabel("写真を追加")
            .accessibilityHint("長押しでカメラを開きます")
            .accessibilityAction(named: "カメラ", onHold)
    }
}

/// A short message at the top of Gallery.
private struct GalleryNotice: ViewModifier {
    let store: GalleryStore

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let notice = store.notice {
                Text(notice)
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    func galleryNotice(_ store: GalleryStore) -> some View {
        modifier(GalleryNotice(store: store))
    }
}
