import AVFoundation
import CryptoKit
import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Gallery's photos and videos. They live in the app's own Application Support (not Documents, which the Files app shows),
/// are kept out of the device's iCloud backup and are only readable while the iPhone is unlocked.
@MainActor
@Observable
final class GalleryStore {
    static let shared = GalleryStore()

    private(set) var state = GalleryState()
    /// Photos still being copied in.
    private(set) var importing = 0
    /// A short message at the top (アルバムに追加しました and such).
    private(set) var notice: String?
    @ObservationIgnored private var noticeTask: Task<Void, Never>?

    init() {
        load()
        emptyOldTrash()
    }

    // MARK: Files

    nonisolated static let root: URL = {
        let fm = FileManager.default
        var root = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gallery", isDirectory: true)
        for dir in ["originals", "thumbs"] {
            try? fm.createDirectory(at: root.appendingPathComponent(dir, isDirectory: true), withIntermediateDirectories: true,
                                    attributes: [.protectionKey: FileProtectionType.complete])
        }
        try? fm.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: root.path)
        // Not in the iCloud backup of the device, with everything inside.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? root.setResourceValues(values)
        return root
    }()

    nonisolated static func fileURL(_ file: String) -> URL {
        root.appendingPathComponent("originals", isDirectory: true).appendingPathComponent(file)
    }

    nonisolated static func thumbURL(_ file: String) -> URL {
        root.appendingPathComponent("thumbs", isDirectory: true).appendingPathComponent(file + ".jpg")
    }

    private static var index: URL { root.appendingPathComponent("gallery.json") }

    func url(_ item: GalleryItem) -> URL { Self.fileURL(item.file) }

    private func load() {
        guard let data = try? Data(contentsOf: Self.index),
              let state = try? JSONDecoder().decode(GalleryState.self, from: data) else { return }
        self.state = state
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: Self.index, options: [.atomic, .completeFileProtection])
    }

    // MARK: Reading

    var albums: [GalleryAlbum] { state.albums }
    var holder: HolderSettings {
        get { state.holder }
        set { state.holder = newValue; save() }
    }

    /// Holder's photo, unless it has been deleted or locked away since.
    var holderItem: GalleryItem? {
        guard let item = item(state.holder.item), item.deleted == nil, !hidden.contains(item.id) else { return nil }
        return item
    }

    func item(_ id: String?) -> GalleryItem? {
        guard let id else { return nil }
        return state.items.first { $0.id == id }
    }

    func album(_ id: String?) -> GalleryAlbum? {
        guard let id else { return nil }
        return state.albums.first { $0.id == id }
    }

    /// Photos in locked albums: they stay out of everything but their album.
    var hidden: Set<String> {
        Set(state.albums.filter(\.locked).flatMap(\.items))
    }

    /// What a grid shows: all of Gallery but locked photos, or one album; filtered and sorted as chosen.
    func items(in albumID: String? = nil) -> [GalleryItem] {
        var list = state.items.filter { $0.deleted == nil }
        if let album = album(albumID) {
            let members = Set(album.items)
            list = list.filter { members.contains($0.id) }
            if !album.locked {
                let hiddenIDs = self.hidden
                list = list.filter { !hiddenIDs.contains($0.id) }
            }
        } else {
            let hiddenIDs = self.hidden
            list = list.filter { !hiddenIDs.contains($0.id) }
        }
        if state.favoritesOnly { list = list.filter(\.favorite) }
        return sorted(list)
    }

    /// Every photo the user may see outside locked albums, unfiltered (for choosing Holder's photo or a thumbnail).
    func pickable(in albumID: String? = nil, photosOnly: Bool = false) -> [GalleryItem] {
        let hiddenIDs = self.hidden
        var list = state.items.filter { $0.deleted == nil }
        if let album = album(albumID) {
            let members = Set(album.items)
            list = list.filter { members.contains($0.id) && (album.locked || !hiddenIDs.contains($0.id)) }
        } else {
            list = list.filter { !hiddenIDs.contains($0.id) }
        }
        if photosOnly { list = list.filter { !$0.isVideo } }
        return list.sorted { $0.added > $1.added }
    }

    private func sorted(_ list: [GalleryItem]) -> [GalleryItem] {
        let key: (GalleryItem) -> Date = state.sort == .added ? { $0.added } : { $0.taken ?? $0.added }
        return list.sorted { state.oldestFirst ? key($0) < key($1) : key($0) > key($1) }
    }

    var trashed: [GalleryItem] {
        state.items.filter { $0.deleted != nil }.sorted { $0.deleted! > $1.deleted! }
    }

    /// The album's own thumbnail, else its newest photo (none for a locked album, so nothing shows through).
    func cover(_ album: GalleryAlbum) -> GalleryItem? {
        if let cover = item(album.cover), cover.deleted == nil, album.items.contains(cover.id) { return cover }
        guard !album.locked else { return nil }
        return pickable(in: album.id).first
    }

    func count(_ album: GalleryAlbum) -> Int {
        pickable(in: album.id).count
    }

    // MARK: Sorting

    var sort: GallerySort {
        get { state.sort }
        set { state.sort = newValue; save() }
    }

    var oldestFirst: Bool {
        get { state.oldestFirst }
        set { state.oldestFirst = newValue; save() }
    }

    var favoritesOnly: Bool {
        get { state.favoritesOnly }
        set { state.favoritesOnly = newValue; save() }
    }

    // MARK: Adding

    /// Copies photos and videos chosen in the photo library. The originals stay in the library.
    func importPicked(_ picked: [PhotosPickerItem], into albumID: String?) {
        guard !picked.isEmpty else { return }
        importing += picked.count
        Task {
            var added: [GalleryItem] = []
            for entry in picked {
                if let item = await Self.copy(entry) {
                    added.append(item)
                }
                importing -= 1
            }
            insert(added, into: albumID)
            if added.count < picked.count {
                notify("\(picked.count - added.count)件を読み込めませんでした")
            }
        }
    }

    /// A photo from Gallery's own camera.
    func addCaptured(_ data: Data, into albumID: String?) {
        Task {
            if let item = await Self.write(data, ext: "heic", kind: .photo, taken: .now) {
                insert([item], into: albumID)
            }
        }
    }

    private func insert(_ added: [GalleryItem], into albumID: String?) {
        guard !added.isEmpty else { return }
        state.items += added
        if let albumID, let index = state.albums.firstIndex(where: { $0.id == albumID }) {
            state.albums[index].items += added.map(\.id)
        }
        save()
    }

    private nonisolated static func copy(_ entry: PhotosPickerItem) async -> GalleryItem? {
        let types = entry.supportedContentTypes
        if types.contains(where: { $0.conforms(to: .movie) }) {
            guard let movie = try? await entry.loadTransferable(type: GalleryMovie.self) else { return nil }
            return await move(movie.url)
        }
        guard let data = try? await entry.loadTransferable(type: Data.self) else { return nil }
        let type = types.first { $0.conforms(to: .image) }
        return await write(data, ext: type?.preferredFilenameExtension ?? "jpg", kind: .photo, taken: GalleryImages.takenDate(data))
    }

    private nonisolated static func write(_ data: Data, ext: String, kind: GalleryKind, taken: Date?) async -> GalleryItem? {
        let file = UUID().uuidString + "." + ext.lowercased()
        let url = fileURL(file)
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            return nil
        }
        await GalleryImages.makeThumb(of: url, kind: kind, file: file)
        return GalleryItem(kind: kind, file: file, taken: taken)
    }

    private nonisolated static func move(_ source: URL) async -> GalleryItem? {
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let file = UUID().uuidString + "." + ext.lowercased()
        let url = fileURL(file)
        do {
            try FileManager.default.moveItem(at: source, to: url)
            try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
        } catch {
            return nil
        }
        let asset = AVURLAsset(url: url)
        let duration = try? await asset.load(.duration).seconds
        var taken: Date?
        if let metadata = try? await asset.load(.creationDate) {
            taken = try? await metadata.load(.dateValue)
        }
        await GalleryImages.makeThumb(of: url, kind: .video, file: file)
        return GalleryItem(kind: .video, file: file, taken: taken, duration: duration)
    }

    // MARK: Changing

    func toggleFavorite(_ id: String) {
        guard let index = state.items.firstIndex(where: { $0.id == id }) else { return }
        state.items[index].favorite.toggle()
        save()
    }

    func setFavorite(_ ids: Set<String>, _ favorite: Bool) {
        for index in state.items.indices where ids.contains(state.items[index].id) {
            state.items[index].favorite = favorite
        }
        save()
    }

    /// To ゴミ箱 (最近削除した項目).
    func trash(_ ids: Set<String>) {
        for index in state.items.indices where ids.contains(state.items[index].id) {
            state.items[index].deleted = .now
        }
        save()
    }

    func restore(_ ids: Set<String>) {
        for index in state.items.indices where ids.contains(state.items[index].id) {
            state.items[index].deleted = nil
        }
        save()
    }

    /// Gone for good: the files, and the photo in every album and in Holder.
    func purge(_ ids: Set<String>) {
        for item in state.items where ids.contains(item.id) {
            for file in [item.file, item.original].compactMap({ $0 }) {
                try? FileManager.default.removeItem(at: Self.fileURL(file))
                try? FileManager.default.removeItem(at: Self.thumbURL(file))
                GalleryImages.forget(file)
            }
        }
        state.items.removeAll { ids.contains($0.id) }
        for index in state.albums.indices {
            state.albums[index].items.removeAll { ids.contains($0) }
            if let cover = state.albums[index].cover, ids.contains(cover) { state.albums[index].cover = nil }
        }
        if let item = state.holder.item, ids.contains(item) { state.holder.item = nil }
        save()
    }

    private func emptyOldTrash() {
        let limit = Date.now.addingTimeInterval(-30 * 24 * 3600)
        let old = state.items.filter { ($0.deleted ?? .distantFuture) < limit }.map(\.id)
        if !old.isEmpty { purge(Set(old)) }
    }

    /// 切り抜き: the cropped image replaces the photo; the first original is kept for 元に戻す.
    func replaceImage(_ id: String, with data: Data) async {
        guard let item = item(id), let new = await Self.write(data, ext: "heic", kind: .photo, taken: nil),
              let index = state.items.firstIndex(where: { $0.id == id }) else { return }
        if item.original == nil {
            state.items[index].original = item.file
        } else {
            try? FileManager.default.removeItem(at: Self.fileURL(item.file))
            try? FileManager.default.removeItem(at: Self.thumbURL(item.file))
            GalleryImages.forget(item.file)
        }
        state.items[index].file = new.file
        save()
    }

    func revert(_ id: String) {
        guard let index = state.items.firstIndex(where: { $0.id == id }),
              let original = state.items[index].original else { return }
        let cropped = state.items[index].file
        try? FileManager.default.removeItem(at: Self.fileURL(cropped))
        try? FileManager.default.removeItem(at: Self.thumbURL(cropped))
        GalleryImages.forget(cropped)
        state.items[index].file = original
        state.items[index].original = nil
        save()
    }

    // MARK: Albums

    func saveAlbum(_ album: GalleryAlbum) {
        if let index = state.albums.firstIndex(where: { $0.id == album.id }) {
            state.albums[index] = album
        } else {
            state.albums.append(album)
        }
        save()
    }

    /// The album goes; its photos stay in Gallery, or go to ゴミ箱 with it.
    func deleteAlbum(_ id: String, trashPhotos: Bool) {
        guard let album = album(id) else { return }
        if trashPhotos { trash(Set(album.items)) }
        state.albums.removeAll { $0.id == id }
        if state.recentAlbum == id { state.recentAlbum = nil }
        save()
    }

    func add(_ ids: [String], to albumID: String) {
        guard let index = state.albums.firstIndex(where: { $0.id == albumID }) else { return }
        let existing = Set(state.albums[index].items)
        state.albums[index].items += ids.filter { !existing.contains($0) }
        state.recentAlbum = albumID
        save()
        notify("「\(state.albums[index].name)」に追加しました")
    }

    func remove(_ ids: Set<String>, from albumID: String) {
        guard let index = state.albums.firstIndex(where: { $0.id == albumID }) else { return }
        state.albums[index].items.removeAll { ids.contains($0) }
        save()
    }

    var recentAlbum: GalleryAlbum? { album(state.recentAlbum) }

    nonisolated static func hash(_ code: String, album: String) -> String {
        SHA256.hash(data: Data((album + ":" + code).utf8)).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: Notice

    func notify(_ text: String) {
        noticeTask?.cancel()
        withAnimation(.snappy) { notice = text }
        noticeTask = Task {
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { notice = nil }
        }
    }
}

/// A video from the photo library, copied to a temporary file first.
struct GalleryMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { movie in
            SentTransferredFile(movie.url)
        } importing: { received in
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
            try FileManager.default.copyItem(at: received.file, to: copy)
            return GalleryMovie(url: copy)
        }
    }
}

/// Thumbnails and screen-sized images, made off the main thread and remembered for a while.
enum GalleryImages {
    nonisolated(unsafe) private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 600
        return cache
    }()

    static func forget(_ file: String) {
        cache.removeObject(forKey: file as NSString)
    }

    static func cachedThumb(_ file: String) -> UIImage? {
        cache.object(forKey: file as NSString)
    }

    static func thumb(_ item: GalleryItem) async -> UIImage? {
        let file = item.file
        if let image = cache.object(forKey: file as NSString) { return image }
        let url = GalleryStore.thumbURL(file)
        if !FileManager.default.fileExists(atPath: url.path) {
            await makeThumb(of: GalleryStore.fileURL(file), kind: item.kind, file: file)
        }
        let image = await Task.detached(priority: .userInitiated) {
            UIImage(contentsOfFile: url.path)?.preparingForDisplay()
        }.value
        if let image { cache.setObject(image, forKey: file as NSString) }
        return image
    }

    static func makeThumb(of url: URL, kind: GalleryKind, file: String) async {
        let target = GalleryStore.thumbURL(file)
        var image: CGImage?
        if kind == .video {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 360, height: 360)
            image = try? await generator.image(at: .zero).image
        } else {
            image = await Task.detached { downsample(url, max: 360) }.value
        }
        guard let image, let data = UIImage(cgImage: image).jpegData(compressionQuality: 0.8) else { return }
        try? data.write(to: target, options: [.atomic, .completeFileProtection])
    }

    /// The image no larger than needed, turned upright.
    nonisolated static func downsample(_ url: URL, max: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// For the viewer and Holder: sharp on the screen, with room to zoom.
    static func display(_ item: GalleryItem) async -> UIImage? {
        let url = GalleryStore.fileURL(item.file)
        return await Task.detached(priority: .userInitiated) {
            downsample(url, max: 3600).map { UIImage(cgImage: $0) }
        }.value
    }

    /// The whole image, upright, for cropping.
    static func full(_ item: GalleryItem) async -> UIImage? {
        let url = GalleryStore.fileURL(item.file)
        return await Task.detached(priority: .userInitiated) {
            guard let image = UIImage(contentsOfFile: url.path) else { return nil }
            guard image.imageOrientation != .up else { return image }
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: image.size))
            }
        }.value
    }

    nonisolated static func takenDate(_ data: Data) -> Date? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
              let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }
}
