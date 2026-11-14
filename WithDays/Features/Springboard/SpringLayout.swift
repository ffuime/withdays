import Foundation

/// The apps on the home screen.
enum SpringApp: String, Codable, CaseIterable, Identifiable {
    case cal, todo, go, mo, notes, slides, settings

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cal: "Cal"
        case .todo: "Td"
        case .go: "Go"
        case .mo: "Mo"
        case .notes: "Notes"
        case .slides: "Slides"
        case .settings: "設定"
        }
    }

    /// The screen of HomeView it opens; 設定 has its own.
    var mode: HomeMode? {
        switch self {
        case .cal: .calendar
        case .todo: .todo
        case .go: .go
        case .mo: .mo
        case .notes: .notes
        case .slides: .slides
        case .settings: nil
        }
    }

    init(mode: HomeMode) {
        switch mode {
        case .calendar: self = .cal
        case .todo: self = .todo
        case .go: self = .go
        case .mo: self = .mo
        case .notes: self = .notes
        case .slides: self = .slides
        }
    }
}

struct SpringFolder: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var apps: [SpringApp]
}

/// An icon on a page or in the Dock: an app or a folder of apps.
enum SpringItem: Codable, Hashable, Identifiable {
    case app(SpringApp)
    case folder(SpringFolder)

    var id: String {
        switch self {
        case .app(let app): "app-\(app.rawValue)"
        case .folder(let folder): "folder-\(folder.id.uuidString)"
        }
    }

    var apps: [SpringApp] {
        switch self {
        case .app(let app): [app]
        case .folder(let folder): folder.apps
        }
    }

    var name: String {
        switch self {
        case .app(let app): app.name
        case .folder(let folder): folder.name
        }
    }
}

/// Where an icon sits: a page, the Dock, or inside a folder.
enum SpringContainer: Hashable {
    case page(Int)
    case dock
    case folder(UUID)
}

/// The home screen: pages of up to 6 × 4 icons, filled from the top left, and a Dock of up to four.
struct SpringLayout: Codable, Equatable {
    static let columns = 4
    static let rows = 6
    static let perPage = columns * rows
    static let dockSize = 4
    static let folderColumns = 3
    static let folderSize = 9

    var pages: [[SpringItem]]
    var dock: [SpringItem]

    static let standard = SpringLayout(
        pages: [[.app(.go), .app(.mo), .app(.settings)]],
        dock: [.app(.cal), .app(.todo), .app(.notes), .app(.slides)]
    )

    // MARK: Reading

    func items(in container: SpringContainer) -> [SpringItem] {
        switch container {
        case .page(let index): pages.indices.contains(index) ? pages[index] : []
        case .dock: dock
        case .folder(let id): folder(id)?.apps.map(SpringItem.app) ?? []
        }
    }

    func folder(_ id: UUID) -> SpringFolder? {
        for item in pages.joined() + dock {
            if case .folder(let folder) = item, folder.id == id { return folder }
        }
        return nil
    }

    /// Where the top-level item holding `app` is (the app itself, or its folder).
    func place(of app: SpringApp) -> (container: SpringContainer, index: Int, item: SpringItem)? {
        for (page, items) in pages.enumerated() {
            if let index = items.firstIndex(where: { $0.apps.contains(app) }) { return (.page(page), index, items[index]) }
        }
        if let index = dock.firstIndex(where: { $0.apps.contains(app) }) { return (.dock, index, dock[index]) }
        return nil
    }

    func capacity(of container: SpringContainer) -> Int {
        switch container {
        case .page: Self.perPage
        case .dock: Self.dockSize
        case .folder: Self.folderSize
        }
    }

    // MARK: Changing

    /// Takes an item out (an app may come out of a folder).
    mutating func remove(_ item: SpringItem, from container: SpringContainer) {
        switch container {
        case .page(let index):
            guard pages.indices.contains(index) else { return }
            pages[index].removeAll { $0.id == item.id }
        case .dock:
            dock.removeAll { $0.id == item.id }
        case .folder(let id):
            guard case .app(let app) = item else { return }
            changeFolder(id) { $0.apps.removeAll { $0 == app } }
        }
    }

    mutating func insert(_ item: SpringItem, into container: SpringContainer, at index: Int) {
        switch container {
        case .page(let page):
            while pages.count <= page { pages.append([]) }
            pages[page].insert(item, at: min(max(index, 0), pages[page].count))
        case .dock:
            dock.insert(item, at: min(max(index, 0), dock.count))
        case .folder(let id):
            guard case .app(let app) = item else { return }
            changeFolder(id) { $0.apps.insert(app, at: min(max(index, 0), $0.apps.count)) }
        }
    }

    /// Drops an app onto another icon: onto a folder it joins it, onto an app the two make a new folder there.
    mutating func merge(_ app: SpringApp, onto targetID: String) {
        func merged(_ item: SpringItem) -> SpringItem? {
            guard item.id == targetID else { return nil }
            switch item {
            case .folder(var folder):
                folder.apps.append(app)
                return .folder(folder)
            case .app(let other):
                return .folder(SpringFolder(name: "フォルダ", apps: [other, app]))
            }
        }
        for page in pages.indices {
            if let index = pages[page].firstIndex(where: { $0.id == targetID }), let item = merged(pages[page][index]) {
                pages[page][index] = item
                return
            }
        }
        if let index = dock.firstIndex(where: { $0.id == targetID }), let item = merged(dock[index]) {
            dock[index] = item
        }
    }

    mutating func renameFolder(_ id: UUID, to name: String) {
        changeFolder(id) { $0.name = name }
    }

    private mutating func changeFolder(_ id: UUID, _ body: (inout SpringFolder) -> Void) {
        func apply(_ item: inout SpringItem) {
            guard case .folder(var folder) = item, folder.id == id else { return }
            body(&folder)
            item = .folder(folder)
        }
        for page in pages.indices {
            for index in pages[page].indices { apply(&pages[page][index]) }
        }
        for index in dock.indices { apply(&dock[index]) }
    }

    /// Every app exactly once; a folder with one app becomes the app, an empty one goes; `dropEmptyPages`
    /// removes empty pages (there's always one).
    mutating func normalize(dropEmptyPages: Bool) {
        var seen = Set<SpringApp>()
        func clean(_ items: [SpringItem]) -> [SpringItem] {
            items.compactMap { item in
                switch item {
                case .app(let app):
                    return seen.insert(app).inserted ? item : nil
                case .folder(var folder):
                    folder.apps = folder.apps.filter { seen.insert($0).inserted }
                    if folder.apps.isEmpty { return nil }
                    if folder.apps.count == 1 { return .app(folder.apps[0]) }
                    return .folder(folder)
                }
            }
        }
        dock = Array(clean(dock).prefix(Self.dockSize))
        pages = pages.map { Array(clean($0).prefix(Self.perPage)) }
        if dropEmptyPages { pages.removeAll { $0.isEmpty } }
        if pages.isEmpty { pages = [[]] }
        for app in SpringApp.allCases where !seen.contains(app) {
            if let page = pages.firstIndex(where: { $0.count < Self.perPage }) {
                pages[page].append(.app(app))
            } else {
                pages.append([.app(app)])
            }
        }
    }
}
