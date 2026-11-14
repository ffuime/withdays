import SwiftUI
import UIKit

/// A grid of cells in screen points: where each icon sits, and which cell a point falls in.
struct SpringGrid {
    var frame: CGRect
    var columns: Int
    var rows: Int
    var iconSize: CGFloat
    /// The label under the icon and the space above it (0 in the Dock).
    var labelHeight: CGFloat

    var cell: CGSize {
        CGSize(width: frame.width / CGFloat(max(columns, 1)), height: frame.height / CGFloat(max(rows, 1)))
    }

    func cellRect(_ index: Int) -> CGRect {
        let column = index % max(columns, 1)
        let row = index / max(columns, 1)
        return CGRect(
            x: frame.minX + CGFloat(column) * cell.width, y: frame.minY + CGFloat(row) * cell.height,
            width: cell.width, height: cell.height
        )
    }

    /// The icon (without its label), centered in its cell with the label below.
    func iconRect(_ index: Int) -> CGRect {
        let cell = cellRect(index)
        return CGRect(
            x: cell.midX - iconSize / 2, y: cell.midY - (iconSize + labelHeight) / 2,
            width: iconSize, height: iconSize
        )
    }

    func index(at point: CGPoint) -> Int {
        let column = min(max(Int((point.x - frame.minX) / cell.width), 0), columns - 1)
        let row = min(max(Int((point.y - frame.minY) / cell.height), 0), rows - 1)
        return row * columns + column
    }
}

/// What a container shows: its icons, with a gap where a dragged icon would land.
enum SpringEntry: Identifiable {
    case item(SpringItem)
    case gap

    var id: String {
        switch self {
        case .item(let item): item.id
        case .gap: "gap"
        }
    }
}

/// Asks HomeView to show a screen; each request is new.
struct LaunchRequest: Equatable {
    let id = UUID()
    let mode: HomeMode
}

/// An icon being carried in 編集 (jiggle) mode.
struct SpringDrag {
    var item: SpringItem
    var source: SpringContainer
    /// The finger, in screen points.
    var location: CGPoint
    /// From the finger to the icon's middle.
    var grab: CGSize
    /// The home screen without the carried icon.
    var base: SpringLayout
    /// Where it would land: a gap in a container…
    var insert: (container: SpringContainer, index: Int)?
    /// …or onto an icon, making or joining a folder.
    var merge: String?
}

/// The home screen's state: the layout (saved), editing, dragging, the open folder, the wallpaper, and which
/// app is open on top.
@MainActor
@Observable
final class Springboard {
    private static let layoutKey = "springboardLayout"
    static let labelHeight: CGFloat = 20

    var layout: SpringLayout {
        didSet {
            if let data = try? JSONEncoder().encode(layout) { UserDefaults.standard.set(data, forKey: Self.layoutKey) }
        }
    }

    var editing = false
    /// The page shown.
    var page: Int? = 0
    var openFolder: UUID?
    var drag: SpringDrag?
    /// The open folder steps aside while an app dragged out of it is carried over the pages.
    var folderSetAside = false
    var wallpaper: UIImage?

    /// The app on screen (nil: the home screen).
    var openApp: SpringApp?
    /// Where the open app is drawn, in screen points: its icon while opening or closing, the screen when open.
    var appRect: CGRect?
    /// HomeView's screen, told by HomeView, so going home lands on the right icon.
    var activeMode: HomeMode = .calendar
    /// Asks HomeView to show a screen; a new id each time.
    var launchRequest: LaunchRequest?

    // Measured by the views, in screen points.
    var gridFrame: CGRect = .zero
    var dockFrame: CGRect = .zero
    var folderGridFrame: CGRect = .zero
    var folderPanelFrame: CGRect = .zero
    var screen: CGRect = .zero
    var iconSize: CGFloat = 62

    private var mergeCandidate: String?
    private var mergeTask: Task<Void, Never>?
    private var edgeTask: Task<Void, Never>?

    init() {
        var layout = SpringLayout.standard
        if let data = UserDefaults.standard.data(forKey: Self.layoutKey),
           let saved = try? JSONDecoder().decode(SpringLayout.self, from: data) {
            layout = saved
        }
        layout.normalize(dropEmptyPages: true)
        self.layout = layout
        wallpaper = Wallpaper.load()
    }

    var currentPage: Int { min(max(page ?? 0, 0), max(shownLayout.pages.count - 1, 0)) }

    /// The layout as drawn: while carrying, without the carried icon.
    var shownLayout: SpringLayout { drag?.base ?? layout }

    /// The open app's icon on the home screen: what it's on (in the Dock, on a page or in a folder).
    var activeApp: SpringApp {
        openApp == .settings ? .settings : SpringApp(mode: activeMode)
    }

    // MARK: Geometry

    func pageGrid(in frame: CGRect) -> SpringGrid {
        SpringGrid(frame: frame, columns: SpringLayout.columns, rows: SpringLayout.rows, iconSize: iconSize, labelHeight: Self.labelHeight)
    }

    func dockGrid(in frame: CGRect, slots: Int) -> SpringGrid {
        SpringGrid(frame: frame, columns: max(slots, 1), rows: 1, iconSize: iconSize, labelHeight: 0)
    }

    func folderGrid(in frame: CGRect) -> SpringGrid {
        SpringGrid(frame: frame, columns: SpringLayout.folderColumns, rows: 3, iconSize: iconSize, labelHeight: Self.labelHeight)
    }

    func entries(in container: SpringContainer) -> [SpringEntry] {
        var entries = shownLayout.items(in: container).map(SpringEntry.item)
        if let insert = drag?.insert, insert.container == container {
            entries.insert(.gap, at: min(max(insert.index, 0), entries.count))
        }
        return entries
    }

    /// Where an app's icon is on screen now (in the open folder, on the page shown, or in the Dock).
    func iconFrame(of app: SpringApp) -> CGRect? {
        if let id = openFolder, let folder = layout.folder(id), let index = folder.apps.firstIndex(of: app) {
            return folderGrid(in: folderGridFrame).iconRect(index)
        }
        guard let place = layout.place(of: app) else { return nil }
        switch place.container {
        case .page(let page):
            guard page == currentPage else { return nil }
            return pageGrid(in: gridFrame).iconRect(place.index)
        case .dock:
            return dockGrid(in: dockFrame, slots: layout.dock.count).iconRect(place.index)
        case .folder:
            return nil
        }
    }

    // MARK: Editing

    func startEditing() {
        guard !editing else { return }
        withAnimation(.snappy(duration: 0.25)) { editing = true }
    }

    /// 完了: empty pages go.
    func endEditing() {
        guard drag == nil else { return }
        withAnimation(.snappy(duration: 0.25)) {
            editing = false
            layout.normalize(dropEmptyPages: true)
            if let page, page >= layout.pages.count { self.page = layout.pages.count - 1 }
        }
    }

    func renameFolder(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        layout.renameFolder(id, to: trimmed.isEmpty ? "フォルダ" : trimmed)
    }

    // MARK: Dragging

    func beginDrag(_ item: SpringItem, from container: SpringContainer, at index: Int, finger: CGPoint, iconCenter: CGPoint) {
        guard drag == nil else { return }
        startEditing()
        var base = layout
        base.remove(item, from: container)
        withAnimation(.spring(duration: 0.3)) {
            drag = SpringDrag(
                item: item, source: container, location: finger,
                grab: CGSize(width: iconCenter.x - finger.x, height: iconCenter.y - finger.y),
                base: base, insert: (container: container, index: index), merge: nil
            )
        }
    }

    func moveDrag(to point: CGPoint) {
        guard drag != nil else { return }
        drag?.location = point
        guard let container = container(at: point) else { return }
        if case .page = container { watchEdges(point) } else { stopEdges() }
        aim(at: point, in: container)
    }

    func endDrag() {
        guard let drag else { return }
        mergeTask?.cancel()
        stopEdges()
        mergeCandidate = nil
        var result = drag.base
        if let target = drag.merge, case .app(let app) = drag.item {
            result.merge(app, onto: target)
        } else if let insert = drag.insert {
            result.insert(drag.item, into: insert.container, at: insert.index)
        } else {
            result = layout
        }
        result.normalize(dropEmptyPages: false)
        withAnimation(.spring(duration: 0.35)) {
            layout = result
            self.drag = nil
            if folderSetAside {
                openFolder = nil
                folderSetAside = false
            }
            if let id = openFolder, layout.folder(id) == nil { openFolder = nil }
        }
    }

    /// Which container a point is over; nil keeps the current aim.
    private func container(at point: CGPoint) -> SpringContainer? {
        if let id = openFolder, !folderSetAside {
            if folderPanelFrame.contains(point) { return .folder(id) }
            guard case .folder = drag?.source else { return nil }
            // Carried out of the folder: the folder steps aside and the pages take over.
            withAnimation(.snappy(duration: 0.25)) {
                folderSetAside = true
                drag?.insert = nil
            }
        }
        if dockFrame.insetBy(dx: 0, dy: -14).contains(point) { return .dock }
        if gridFrame.insetBy(dx: -gridFrame.minX, dy: 0).contains(point) { return .page(currentPage) }
        return nil
    }

    /// Moves the gap under the finger, or (holding over an icon's middle) aims to make or join a folder.
    private func aim(at point: CGPoint, in container: SpringContainer) {
        guard let drag else { return }
        let shown = entries(in: container)
        let baseItems = drag.base.items(in: container)
        let grid: SpringGrid = switch container {
        case .page: pageGrid(in: gridFrame)
        case .dock: dockGrid(in: dockFrame, slots: max(shown.count, 1))
        case .folder: folderGrid(in: folderGridFrame)
        }
        let index = grid.index(at: point)
        guard shown.indices.contains(index) else {
            cancelMerge()
            setInsert(container, baseItems.count)
            return
        }
        guard case .item(let item) = shown[index] else {
            cancelMerge()
            return
        }
        let icon = grid.iconRect(index)
        let middle = icon.insetBy(dx: icon.width * 0.2, dy: icon.height * 0.2)
        if canMerge(drag.item, onto: item, in: container), middle.contains(point) {
            startMerge(item.id)
            return
        }
        cancelMerge()
        guard let baseIndex = baseItems.firstIndex(where: { $0.id == item.id }) else { return }
        setInsert(container, baseIndex + (point.x > icon.midX ? 1 : 0))
    }

    private func canMerge(_ carried: SpringItem, onto item: SpringItem, in container: SpringContainer) -> Bool {
        guard case .app = carried else { return false }
        if case .folder = container { return false }
        if case .folder(let folder) = item { return folder.apps.count < SpringLayout.folderSize }
        return true
    }

    private func setInsert(_ container: SpringContainer, _ index: Int) {
        guard let drag else { return }
        if let insert = drag.insert, insert.container == container, insert.index == index { return }
        guard drag.base.items(in: container).count < drag.base.capacity(of: container) else { return }
        withAnimation(.spring(duration: 0.32)) { self.drag?.insert = (container: container, index: index) }
    }

    private func startMerge(_ id: String) {
        guard mergeCandidate != id else { return }
        mergeCandidate = id
        mergeTask?.cancel()
        mergeTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled, let self, self.mergeCandidate == id, self.drag != nil else { return }
            withAnimation(.spring(duration: 0.3)) { self.drag?.merge = id }
        }
    }

    private func cancelMerge() {
        mergeCandidate = nil
        mergeTask?.cancel()
        if drag?.merge != nil {
            withAnimation(.spring(duration: 0.3)) { drag?.merge = nil }
        }
    }

    /// Held at the left or right edge, the pages turn (past the last one, a new page).
    private func watchEdges(_ point: CGPoint) {
        let side = point.x < screen.minX + 22 ? -1 : point.x > screen.maxX - 22 ? 1 : 0
        guard side != 0 else {
            stopEdges()
            return
        }
        guard edgeTask == nil else { return }
        edgeTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(600))
                guard !Task.isCancelled, let self, let drag = self.drag else { return }
                let still = side < 0 ? drag.location.x < self.screen.minX + 22 : drag.location.x > self.screen.maxX - 22
                guard still else { break }
                self.turnPage(side)
            }
            self?.edgeTask = nil
        }
    }

    private func stopEdges() {
        edgeTask?.cancel()
        edgeTask = nil
    }

    private func turnPage(_ side: Int) {
        guard var drag else { return }
        let target = currentPage + side
        guard target >= 0 else { return }
        if target >= drag.base.pages.count {
            // A new page, unless this one is already empty.
            guard !drag.base.pages[currentPage].isEmpty else { return }
            drag.base.pages.append([])
        }
        let count = drag.base.pages[target].count
        if count < SpringLayout.perPage { drag.insert = (container: .page(target), index: count) }
        drag.merge = nil
        mergeCandidate = nil
        withAnimation(.snappy(duration: 0.35)) {
            self.drag = drag
            page = target
        }
    }

    // MARK: Opening apps

    func open(_ app: SpringApp) {
        if let mode = app.mode {
            UserDefaults.standard.set(mode.rawValue, forKey: SettingsKey.homeMode)
            launchRequest = LaunchRequest(mode: mode)
            activeMode = mode
        }
        openApp = app
    }

    /// A widget link: the app comes up at once, without zooming.
    func revealApp() {
        guard openApp == nil else { return }
        openApp = .cal
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { appRect = screen }
    }

    // MARK: Wallpaper

    func setWallpaper(_ data: Data) {
        wallpaper = Wallpaper.save(data)
    }

    func resetWallpaper() {
        Wallpaper.remove()
        wallpaper = nil
    }
}

/// The picked wallpaper, kept in Application Support at about screen size.
enum Wallpaper {
    private static var url: URL? {
        try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appending(path: "wallpaper.jpg")
    }

    static func load() -> UIImage? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    @MainActor
    static func save(_ data: Data) -> UIImage? {
        guard let image = UIImage(data: data), let url else { return nil }
        let bounds = UIScreen.main.bounds.size
        let longest = max(bounds.width, bounds.height) * 3
        let scale = min(1, longest / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        try? resized.jpegData(compressionQuality: 0.88)?.write(to: url, options: .atomic)
        return resized
    }

    static func remove() {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
