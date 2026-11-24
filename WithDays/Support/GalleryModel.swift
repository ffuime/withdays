import Foundation

enum GalleryKind: String, Codable {
    case photo, video
}

/// One photo or video kept inside the app (never in the photo library or iCloud).
struct GalleryItem: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var kind = GalleryKind.photo
    /// The file in Gallery/originals. A crop writes a new file, so the name also keys the thumbnail.
    var file: String
    /// The file before the first crop, for 元に戻す.
    var original: String?
    var added = Date.now
    var taken: Date?
    var duration: Double?
    var favorite = false
    /// In ゴミ箱 since then; emptied after 30 days.
    var deleted: Date?

    var isVideo: Bool { kind == .video }
}

enum GalleryLock: String, Codable, CaseIterable, Identifiable {
    case faceID, passcode

    var id: String { rawValue }
    var label: String {
        switch self {
        case .faceID: "Face ID"
        case .passcode: "パスコード"
        }
    }
}

struct GalleryAlbum: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var name = ""
    /// Oldest added first.
    var items: [String] = []
    var cover: String?
    /// A locked album's photos are only seen inside it.
    var locked = false
    var lock = GalleryLock.faceID
    /// SHA-256 of the album's 4 digits.
    var passcode: String?
    var created = Date.now
}

enum HolderBackground: String, Codable, CaseIterable, Identifiable {
    case white, black, gray, lightBlur, darkBlur

    var id: String { rawValue }
    var label: String {
        switch self {
        case .white: "ホワイト"
        case .black: "ブラック"
        case .gray: "グレー"
        case .lightBlur: "明るいぼかし"
        case .darkBlur: "暗いぼかし"
        }
    }
}

/// Holder: one photo, full screen.
struct HolderSettings: Codable, Hashable {
    var item: String?
    var statusBar = true
    var zoom = true
    var background = HolderBackground.lightBlur
    var autoSleep = true
}

enum GallerySort: String, Codable, CaseIterable, Identifiable {
    case added, taken

    var id: String { rawValue }
    var label: String {
        switch self {
        case .added: "追加した日"
        case .taken: "撮影した日"
        }
    }
}

struct GalleryState: Codable {
    var items: [GalleryItem] = []
    var albums: [GalleryAlbum] = []
    var holder = HolderSettings()
    /// The album the last photos went into: holding アルバムに追加 puts them there.
    var recentAlbum: String?
    var sort = GallerySort.added
    var oldestFirst = false
    var favoritesOnly = false
}
