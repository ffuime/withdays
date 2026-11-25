import FirebaseAuth
import FirebaseFirestore
import PhotosUI
import SwiftUI
import UIKit

// A talk's ノート (posts with likes and comments) and アルバム (named sets of photos), as LINE has them.
//
// Server:
//   rooms/{roomID}/notes/{noteID}                 authorID, authorUID, text, photos [url], date, likes [toocID], comments
//   rooms/{roomID}/notes/{noteID}/comments/{id}   authorID, authorUID, text, date
//   rooms/{roomID}/albums/{albumID}               title, authorID, authorUID, date, updatedAt, photos [{url, by, date}]
// Storage: rooms/{roomID}/notes/{noteID}/…  and  rooms/{roomID}/albums/{albumID}/…

struct ToocNote: Identifiable, Hashable {
    let id: String
    let authorID: String
    var text: String
    var photos: [String]
    var date: Date
    var likes: [String]
    var comments: Int
}

struct ToocComment: Identifiable, Hashable {
    let id: String
    let authorID: String
    let text: String
    let date: Date
}

struct ToocAlbumPhoto: Hashable {
    let url: String
    let by: String
    let date: Date

    var fields: [String: Any] { ["url": url, "by": by, "date": Timestamp(date: date)] }
}

struct ToocAlbum: Identifiable, Hashable {
    let id: String
    var title: String
    let authorID: String
    var updatedAt: Date
    var photos: [ToocAlbumPhoto]
}

/// One talk's notes and albums, kept in step with the server while their screen is open.
@MainActor
@Observable
final class ToocBoard {
    let roomID: String
    private(set) var notes: [ToocNote] = []
    private(set) var albums: [ToocAlbum] = []
    private(set) var loadedNotes = false
    private(set) var loadedAlbums = false
    @ObservationIgnored private var listeners: [String: ListenerRegistration] = [:]

    init(roomID: String) { self.roomID = roomID }

    private var room: DocumentReference { ToocServer.room(roomID) }
    private var uid: String { Auth.auth().currentUser?.uid ?? "" }

    func listenNotes() {
        guard listeners["notes"] == nil else { return }
        listeners["notes"] = room.collection("notes").order(by: "date", descending: true).limit(to: 300)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self, let snapshot else { return }
                    self.notes = snapshot.documents.map { Self.note($0.documentID, $0.data()) }
                    self.loadedNotes = true
                }
            }
    }

    func listenAlbums() {
        guard listeners["albums"] == nil else { return }
        listeners["albums"] = room.collection("albums").order(by: "updatedAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self, let snapshot else { return }
                    self.albums = snapshot.documents.map { Self.album($0.documentID, $0.data()) }
                    self.loadedAlbums = true
                }
            }
    }

    func stop() {
        listeners.values.forEach { $0.remove() }
        listeners = [:]
    }

    private static func note(_ id: String, _ data: [String: Any]) -> ToocNote {
        ToocNote(id: id, authorID: data["authorID"] as? String ?? "", text: data["text"] as? String ?? "",
                 photos: data["photos"] as? [String] ?? [], date: (data["date"] as? Timestamp)?.dateValue() ?? .now,
                 likes: data["likes"] as? [String] ?? [], comments: data["comments"] as? Int ?? 0)
    }

    private static func album(_ id: String, _ data: [String: Any]) -> ToocAlbum {
        let photos = (data["photos"] as? [[String: Any]] ?? []).compactMap { item -> ToocAlbumPhoto? in
            guard let url = item["url"] as? String else { return nil }
            return ToocAlbumPhoto(url: url, by: item["by"] as? String ?? "", date: (item["date"] as? Timestamp)?.dateValue() ?? .now)
        }
        return ToocAlbum(id: id, title: data["title"] as? String ?? "アルバム", authorID: data["authorID"] as? String ?? "",
                         updatedAt: (data["updatedAt"] as? Timestamp)?.dateValue() ?? .now, photos: photos)
    }

    private func upload(_ images: [UIImage], folder: String) async throws -> [String] {
        var urls: [String] = []
        for image in images {
            guard let data = ToocServer.jpeg(image, side: 2048) else { continue }
            let url = try await ToocServer.upload(data, to: "\(folder)/\(UUID().uuidString).jpg", type: "image/jpeg")
            try? data.write(to: ToocFiles.url(ToocFiles.remoteName(url)))
            urls.append(url)
        }
        return urls
    }

    // MARK: Notes

    func post(text: String, images: [UIImage], store: ToocStore) async throws {
        let id = UUID().uuidString
        do {
            let urls = try await upload(images, folder: "rooms/\(roomID)/notes/\(id)")
            try await room.collection("notes").document(id).setData([
                "authorID": store.me.id, "authorUID": uid, "text": text, "photos": urls,
                "date": Timestamp(date: .now), "likes": [String](), "comments": 0,
            ])
            store.send(.note(id: id, text: text.isEmpty ? "写真\(urls.count)枚" : text), in: roomID)
        } catch {
            throw ToocError(ToocServer.describe(error))
        }
    }

    func toggleLike(_ note: ToocNote, me: String) {
        let liked = note.likes.contains(me)
        if let index = notes.firstIndex(where: { $0.id == note.id }) {
            if liked { notes[index].likes.removeAll { $0 == me } } else { notes[index].likes.append(me) }
        }
        Task {
            try? await room.collection("notes").document(note.id)
                .updateData(["likes": liked ? FieldValue.arrayRemove([me]) : FieldValue.arrayUnion([me])])
        }
    }

    func delete(_ note: ToocNote) {
        notes.removeAll { $0.id == note.id }
        Task { try? await room.collection("notes").document(note.id).delete() }
    }

    func listenComments(_ noteID: String, onChange: @escaping ([ToocComment]) -> Void) -> ListenerRegistration {
        room.collection("notes").document(noteID).collection("comments").order(by: "date")
            .addSnapshotListener { snapshot, _ in
                guard let snapshot else { return }
                let list = snapshot.documents.map { doc in
                    let data = doc.data()
                    return ToocComment(id: doc.documentID, authorID: data["authorID"] as? String ?? "",
                                       text: data["text"] as? String ?? "", date: (data["date"] as? Timestamp)?.dateValue() ?? .now)
                }
                Task { @MainActor in onChange(list) }
            }
    }

    func comment(_ text: String, on noteID: String, me: String) {
        let note = room.collection("notes").document(noteID)
        Task {
            try? await note.collection("comments").document(UUID().uuidString).setData([
                "authorID": me, "authorUID": uid, "text": text, "date": Timestamp(date: .now),
            ])
            try? await note.updateData(["comments": FieldValue.increment(Int64(1))])
        }
    }

    func deleteComment(_ comment: ToocComment, on noteID: String) {
        let note = room.collection("notes").document(noteID)
        Task {
            try? await note.collection("comments").document(comment.id).delete()
            try? await note.updateData(["comments": FieldValue.increment(Int64(-1))])
        }
    }

    // MARK: Albums

    @discardableResult
    func createAlbum(title: String, images: [UIImage], store: ToocStore) async throws -> String {
        let id = UUID().uuidString
        do {
            let urls = try await upload(images, folder: "rooms/\(roomID)/albums/\(id)")
            let photos = urls.map { ToocAlbumPhoto(url: $0, by: store.me.id, date: .now).fields }
            try await room.collection("albums").document(id).setData([
                "title": title, "authorID": store.me.id, "authorUID": uid, "date": Timestamp(date: .now),
                "updatedAt": Timestamp(date: .now), "photos": photos,
            ])
            store.send(.album(id: id, title: title, count: urls.count), in: roomID)
        } catch {
            throw ToocError(ToocServer.describe(error))
        }
        return id
    }

    func add(_ images: [UIImage], to album: ToocAlbum, store: ToocStore) async throws {
        do {
            let urls = try await upload(images, folder: "rooms/\(roomID)/albums/\(album.id)")
            let photos = urls.map { ToocAlbumPhoto(url: $0, by: store.me.id, date: .now).fields }
            try await room.collection("albums").document(album.id).updateData([
                "photos": FieldValue.arrayUnion(photos), "updatedAt": Timestamp(date: .now),
            ])
            store.send(.album(id: album.id, title: album.title, count: urls.count), in: roomID)
        } catch {
            throw ToocError(ToocServer.describe(error))
        }
    }

    func remove(_ photo: ToocAlbumPhoto, from album: ToocAlbum) {
        let rest = album.photos.filter { $0 != photo }
        if let index = albums.firstIndex(where: { $0.id == album.id }) { albums[index].photos = rest }
        Task { try? await room.collection("albums").document(album.id).updateData(["photos": rest.map(\.fields)]) }
    }

    func rename(_ album: ToocAlbum, to title: String) {
        Task { try? await room.collection("albums").document(album.id).updateData(["title": title]) }
    }

    func delete(_ album: ToocAlbum) {
        albums.removeAll { $0.id == album.id }
        Task { try? await room.collection("albums").document(album.id).delete() }
    }
}

// MARK: - Photos in a grid

/// A photo from the server cut to fill its frame; a tap opens it full screen from where it is.
struct ToocGridPhoto: View {
    let url: String
    var open: (UIImage, CGRect) -> Void

    @State private var image: UIImage?
    @State private var frame: CGRect = .zero

    var body: some View {
        Color(.tertiarySystemFill)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else {
                    ProgressView()
                }
            }
            .clipped()
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .onTapGesture { if let image { open(image, frame) } }
            .task(id: url) {
                if let cached = ToocFiles.image(ToocFiles.remoteName(url)) {
                    image = cached
                } else if let fetched = await ToocFiles.remoteImage(url) {
                    withAnimation(.easeOut(duration: 0.2)) { image = fetched }
                }
            }
    }
}

/// Opens a photo full screen without the system's sheet animation (the photo grows out of its place instead).
private struct ToocZoomCover: ViewModifier {
    @Binding var item: ToocPhotoZoomItem?

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $item) { item in
            ToocPhotoZoom(item: item) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { self.item = nil }
            }
        }
    }
}

extension View {
    func toocZoomCover(_ item: Binding<ToocPhotoZoomItem?>) -> some View { modifier(ToocZoomCover(item: item)) }
}

/// Opens a photo grown from where it was tapped.
@MainActor
func toocOpenZoom(_ binding: Binding<ToocPhotoZoomItem?>, _ image: UIImage, _ frame: CGRect) {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) { binding.wrappedValue = ToocPhotoZoomItem(image: image, source: frame) }
}

/// Up to `limit` photos: one wide, or a grid of squares (the last shows how many more there are).
struct ToocPhotoMosaic: View {
    let urls: [String]
    var limit = 4
    var open: (UIImage, CGRect) -> Void

    var body: some View {
        let shown = Array(urls.prefix(limit))
        if shown.count == 1 {
            ToocGridPhoto(url: shown[0], open: open)
                .frame(height: 220)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        } else if !shown.isEmpty {
            let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: shown.count == 2 || shown.count == 4 ? 2 : 3)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(shown.enumerated()), id: \.offset) { index, url in
                    ToocGridPhoto(url: url, open: open)
                        .aspectRatio(1, contentMode: .fill)
                        .overlay {
                            if index == shown.count - 1 && urls.count > shown.count {
                                ZStack {
                                    Color.black.opacity(0.45)
                                    Text("+\(urls.count - shown.count)")
                                        .toocFont(.title2.bold())
                                        .foregroundStyle(.white)
                                }
                                .allowsHitTesting(false)
                            }
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

// MARK: - Notes

/// A talk's ノート: everyone's posts, newest first; open one for its comments.
struct ToocNotesView: View {
    let roomID: String
    var openID: String?

    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var board: ToocBoard
    @State private var path: [String] = []
    @State private var composing = false
    @State private var zoom: ToocPhotoZoomItem?

    init(roomID: String, openID: String?) {
        self.roomID = roomID
        self.openID = openID
        _board = State(initialValue: ToocBoard(roomID: roomID))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(board.notes) { note in
                        ToocNoteCard(note: note, board: board, full: false) { image, frame in toocOpenZoom($zoom, image, frame) }
                            .contentShape(Rectangle())
                            .onTapGesture { path.append(note.id) }
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .padding(16)
                .animation(.snappy, value: board.notes.map(\.id))
            }
            .background(theme.fill.ignoresSafeArea())
            .overlay {
                if !board.loadedNotes {
                    ProgressView()
                } else if board.notes.isEmpty {
                    ContentUnavailableView("ノートはまだありません", systemImage: "note.text",
                                           description: Text("残しておきたいことや写真を投稿できます。"))
                }
            }
            .navigationTitle("ノート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.primary) }
                        .accessibilityLabel("閉じる")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { composing = true } label: { Image(systemName: "square.and.pencil").foregroundStyle(.primary) }
                        .accessibilityLabel("投稿する")
                }
            }
            .navigationDestination(for: String.self) { id in
                ToocNoteDetail(noteID: id, board: board)
            }
        }
        .sheet(isPresented: $composing) { ToocNoteComposer(board: board) }
        .toocZoomCover($zoom)
        .onAppear {
            board.listenNotes()
            if let openID, path.isEmpty { path = [openID] }
        }
        .onDisappear { board.stop() }
    }
}

/// A post: who and when, the words, the photos, then ♡ and comments.
struct ToocNoteCard: View {
    let note: ToocNote
    let board: ToocBoard
    let full: Bool
    var open: (UIImage, CGRect) -> Void

    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme
    @State private var confirmDelete = false

    var body: some View {
        let author = store.lookUp(note.authorID)
        let liked = note.likes.contains(store.me.id)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ToocAvatar(user: author, size: 36)
                    .onTapGesture { router.sheet = .profile(author.id) }
                VStack(alignment: .leading, spacing: 1) {
                    author.nameText
                        .toocFont(.subheadline.bold())
                    Text("\(ToocTime.listLabel(note.date)) \(ToocTime.clock(note.date))")
                        .toocFont(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if note.authorID == store.me.id {
                    Menu {
                        Button("削除", systemImage: "trash", role: .destructive) { confirmDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .foregroundStyle(.secondary)
                }
            }
            if !note.text.isEmpty {
                Text(ToocLinks.attributed(note.text))
                    .toocFont(.body)
                    .lineLimit(full ? nil : 6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ToocPhotoMosaic(urls: note.photos, limit: full ? 30 : 4, open: open)
            HStack(spacing: 18) {
                Button {
                    withAnimation(.snappy) { board.toggleLike(note, me: store.me.id) }
                } label: {
                    Label("\(note.likes.count)", systemImage: liked ? "heart.fill" : "heart")
                        .foregroundStyle(liked ? Color.pink : Color.secondary)
                        .contentTransition(.numericText())
                }
                .sensoryFeedback(.impact(weight: .light), trigger: liked)
                Label("\(note.comments)", systemImage: "bubble.right")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .toocFont(.subheadline)
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .alert("ノートを削除しますか？", isPresented: $confirmDelete) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) { withAnimation(.snappy) { board.delete(note) } }
        } message: {
            Text("元に戻せません。")
        }
    }
}

/// One post with all its photos and its comments, and a field to comment.
struct ToocNoteDetail: View {
    let noteID: String
    let board: ToocBoard

    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @State private var comments: [ToocComment] = []
    @State private var listener: ListenerRegistration?
    @State private var draft = ""
    @State private var zoom: ToocPhotoZoomItem?
    @FocusState private var focused: Bool

    private var note: ToocNote? { board.notes.first { $0.id == noteID } }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let note {
                        ToocNoteCard(note: note, board: board, full: true) { image, frame in toocOpenZoom($zoom, image, frame) }
                    } else if board.loadedNotes {
                        ContentUnavailableView("このノートは削除されました", systemImage: "note.text")
                    }
                    ForEach(comments) { comment in
                        commentRow(comment)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(16)
                .animation(.snappy, value: comments.map(\.id))
            }
            .onChange(of: comments.count) { _, _ in
                withAnimation(.snappy) { reader.scrollTo("end", anchor: .bottom) }
            }
        }
        .background(theme.fill.ignoresSafeArea())
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if note != nil { commentBar }
        }
        .navigationTitle("ノート")
        .navigationBarTitleDisplayMode(.inline)
        .toocZoomCover($zoom)
        .onAppear {
            listener = board.listenComments(noteID) { list in comments = list }
        }
        .onDisappear {
            listener?.remove()
            listener = nil
        }
    }

    private func commentRow(_ comment: ToocComment) -> some View {
        let author = store.lookUp(comment.authorID)
        return HStack(alignment: .top, spacing: 10) {
            ToocAvatar(user: author, size: 32)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    author.nameText.toocFont(.subheadline.bold())
                    Text(ToocTime.listLabel(comment.date)).toocFont(.caption).foregroundStyle(.secondary)
                }
                Text(ToocLinks.attributed(comment.text))
                    .toocFont(.subheadline)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .contextMenu {
            Button("コピー", systemImage: "doc.on.doc") { UIPasteboard.general.string = comment.text }
            if comment.authorID == store.me.id {
                Button("削除", systemImage: "trash", role: .destructive) {
                    withAnimation(.snappy) { board.deleteComment(comment, on: noteID) }
                }
            }
        }
    }

    private var commentBar: some View {
        HStack(alignment: .bottom, spacing: 6) {
            TextField("コメントを書く", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($focused)
                .padding(.vertical, 13)
                .padding(.leading, 16)
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Button {
                    let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    draft = ""
                    board.comment(text, on: noteID, me: store.me.id)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .toocFont(.system(size: 32))
                        .foregroundStyle(theme.accent)
                }
                .padding(.bottom, 6)
                .transition(.scale.combined(with: .opacity))
                .accessibilityLabel("送信")
            }
        }
        .padding(.trailing, 6)
        .frame(minHeight: 48)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .animation(.snappy(duration: 0.2), value: draft.isEmpty)
    }
}

/// Write a post: words and up to 20 photos.
struct ToocNoteComposer: View {
    let board: ToocBoard

    @Environment(ToocStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var items: [PhotosPickerItem] = []
    @State private var images: [ToocPendingPhoto] = []
    @State private var posting = false
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("みんなに残しておきたいこと", text: $text, axis: .vertical)
                        .lineLimit(6...20)
                        .focused($focused)
                }
                Section {
                    ToocPickedPhotos(images: $images)
                    PhotosPicker(selection: $items, maxSelectionCount: 20, matching: .images) {
                        Label("写真を追加", systemImage: "photo.on.rectangle")
                    }
                }
            }
            .navigationTitle("ノートを書く")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.primary) }
                        .accessibilityLabel("キャンセル")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: post) {
                        if posting { ProgressView() } else { Text("投稿") }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(posting || (text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && images.isEmpty))
                }
            }
            .onAppear { focused = true }
            .onChange(of: items) { _, picked in load(picked) }
            .alert("投稿できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
        .interactiveDismissDisabled(posting)
    }

    private func load(_ picked: [PhotosPickerItem]) {
        guard !picked.isEmpty else { return }
        items = []
        Task {
            for item in picked {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    withAnimation(.snappy) { images.append(ToocPendingPhoto(image: image)) }
                }
            }
        }
    }

    private func post() {
        posting = true
        Task {
            do {
                try await board.post(text: text.trimmingCharacters(in: .whitespacesAndNewlines), images: images.map(\.image), store: store)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            posting = false
        }
    }
}

/// The photos chosen so far, each with ✕ to take it off.
struct ToocPickedPhotos: View {
    @Binding var images: [ToocPendingPhoto]

    var body: some View {
        if !images.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(images) { photo in
                        Image(uiImage: photo.image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 72, height: 72)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(alignment: .topTrailing) {
                                Button {
                                    withAnimation(.snappy) { images.removeAll { $0.id == photo.id } }
                                } label: {
                                    Image(systemName: "xmark")
                                        .toocFont(.system(size: 10, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 22, height: 22)
                                        .background(Circle().fill(.black.opacity(0.6)))
                                }
                                .buttonStyle(.plain)
                                .padding(3)
                                .accessibilityLabel("外す")
                            }
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.vertical, 4)
            }
            .scrollIndicators(.hidden)
        }
    }
}

// MARK: - Albums

/// A talk's アルバム: their covers in two columns; open one for its photos.
struct ToocAlbumsView: View {
    let roomID: String
    var openID: String?

    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var board: ToocBoard
    @State private var path: [String] = []
    @State private var creating = false

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 14), count: 2)

    init(roomID: String, openID: String?) {
        self.roomID = roomID
        self.openID = openID
        _board = State(initialValue: ToocBoard(roomID: roomID))
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 18) {
                    ForEach(board.albums) { album in
                        Button { path.append(album.id) } label: { tile(album) }
                            .buttonStyle(ToocPressStyle())
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                    }
                }
                .padding(16)
                .animation(.snappy, value: board.albums.map(\.id))
            }
            .background(theme.fill.ignoresSafeArea())
            .overlay {
                if !board.loadedAlbums {
                    ProgressView()
                } else if board.albums.isEmpty {
                    ContentUnavailableView("アルバムはまだありません", systemImage: "photo.stack",
                                           description: Text("写真をまとめて、みんなで見られます。"))
                }
            }
            .navigationTitle("アルバム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.primary) }
                        .accessibilityLabel("閉じる")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { creating = true } label: { Image(systemName: "plus").foregroundStyle(.primary) }
                        .accessibilityLabel("アルバムを作成")
                }
            }
            .navigationDestination(for: String.self) { id in
                ToocAlbumDetail(albumID: id, board: board)
            }
        }
        .sheet(isPresented: $creating) {
            ToocAlbumCreate(board: board) { id in path = [id] }
        }
        .onAppear {
            board.listenAlbums()
            if let openID, path.isEmpty { path = [openID] }
        }
        .onDisappear { board.stop() }
    }

    private func tile(_ album: ToocAlbum) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Group {
                if let cover = album.photos.last?.url {
                    ToocGridPhoto(url: cover) { _, _ in }
                        .allowsHitTesting(false)
                } else {
                    Color(.tertiarySystemFill)
                        .overlay {
                            Image(systemName: "photo")
                                .toocFont(.title)
                                .foregroundStyle(.secondary)
                        }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text(album.title)
                .toocFont(.subheadline.bold())
                .lineLimit(1)
            Text("\(album.photos.count)枚")
                .toocFont(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}

/// An album's photos, three across. ＋ adds more; the one who made it can rename or delete it.
struct ToocAlbumDetail: View {
    let albumID: String
    let board: ToocBoard

    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var items: [PhotosPickerItem] = []
    @State private var uploading = false
    @State private var zoom: ToocPhotoZoomItem?
    @State private var renaming = false
    @State private var newTitle = ""
    @State private var confirmDelete = false
    @State private var error: String?

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 3)

    private var album: ToocAlbum? { board.albums.first { $0.id == albumID } }

    var body: some View {
        Group {
            if let album {
                ScrollView {
                    LazyVGrid(columns: Self.columns, spacing: 2) {
                        ForEach(album.photos, id: \.self) { photo in
                            ToocGridPhoto(url: photo.url) { image, frame in toocOpenZoom($zoom, image, frame) }
                                .aspectRatio(1, contentMode: .fill)
                                .contextMenu { photoMenu(photo, in: album) }
                        }
                    }
                    .animation(.snappy, value: album.photos)
                }
                .overlay {
                    if album.photos.isEmpty && !uploading {
                        ContentUnavailableView("写真はまだありません", systemImage: "photo")
                    }
                }
                .navigationTitle(album.title)
                .toolbar { toolbar(album) }
            } else if board.loadedAlbums {
                ContentUnavailableView("このアルバムは削除されました", systemImage: "photo.stack")
            } else {
                ProgressView()
            }
        }
        .background(theme.fill.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .overlay(alignment: .bottom) {
            if uploading {
                Label("アップロード中…", systemImage: "arrow.up.circle")
                    .toocFont(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: uploading)
        .toocZoomCover($zoom)
        .onChange(of: items) { _, picked in add(picked) }
        .alert("アルバム名を変更", isPresented: $renaming) {
            TextField("アルバム名", text: $newTitle)
            Button("キャンセル", role: .cancel) {}
            Button("変更") {
                let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                if let album, !title.isEmpty { board.rename(album, to: title) }
            }
        }
        .alert("アルバムを削除しますか？", isPresented: $confirmDelete) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                if let album {
                    dismiss()
                    board.delete(album)
                }
            }
        } message: {
            Text("中の写真もすべて見られなくなります。")
        }
        .alert("追加できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }

    @ToolbarContentBuilder
    private func toolbar(_ album: ToocAlbum) -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            PhotosPicker(selection: $items, maxSelectionCount: 30, matching: .images) {
                Image(systemName: "plus")
            }
            .disabled(uploading)
            .accessibilityLabel("写真を追加")
            if album.authorID == store.me.id {
                Menu {
                    Button("名前を変更", systemImage: "pencil") {
                        newTitle = album.title
                        renaming = true
                    }
                    Button("アルバムを削除", systemImage: "trash", role: .destructive) { confirmDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .accessibilityLabel("その他")
            }
        }
    }

    @ViewBuilder
    private func photoMenu(_ photo: ToocAlbumPhoto, in album: ToocAlbum) -> some View {
        Button("保存", systemImage: "square.and.arrow.down") {
            Task {
                if let image = await ToocFiles.remoteImage(photo.url) {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            }
        }
        if photo.by == store.me.id || album.authorID == store.me.id {
            Button("アルバムから削除", systemImage: "trash", role: .destructive) {
                withAnimation(.snappy) { board.remove(photo, from: album) }
            }
        }
    }

    private func add(_ picked: [PhotosPickerItem]) {
        guard !picked.isEmpty, let album else { return }
        items = []
        uploading = true
        Task {
            var images: [UIImage] = []
            for item in picked {
                if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    images.append(image)
                }
            }
            do {
                try await board.add(images, to: album, store: store)
            } catch {
                self.error = error.localizedDescription
            }
            uploading = false
        }
    }
}

/// A new album: its name and its first photos.
struct ToocAlbumCreate: View {
    let board: ToocBoard
    var onCreated: (String) -> Void

    @Environment(ToocStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var items: [PhotosPickerItem] = []
    @State private var images: [ToocPendingPhoto] = []
    @State private var working = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("アルバム名") {
                    TextField("例：夏休み", text: $title)
                }
                Section {
                    ToocPickedPhotos(images: $images)
                    PhotosPicker(selection: $items, maxSelectionCount: 30, matching: .images) {
                        Label("写真を選ぶ", systemImage: "photo.on.rectangle")
                    }
                }
            }
            .navigationTitle("アルバムを作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.primary) }
                        .accessibilityLabel("キャンセル")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: create) {
                        if working { ProgressView() } else { Text("作成") }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(working || images.isEmpty)
                }
            }
            .onChange(of: items) { _, picked in
                guard !picked.isEmpty else { return }
                items = []
                Task {
                    for item in picked {
                        if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                            withAnimation(.snappy) { images.append(ToocPendingPhoto(image: image)) }
                        }
                    }
                }
            }
            .alert("作成できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
        .interactiveDismissDisabled(working)
    }

    private func create() {
        working = true
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                let id = try await board.createAlbum(title: name.isEmpty ? ToocTime.day(.now) : name,
                                                     images: images.map(\.image), store: store)
                dismiss()
                onCreated(id)
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}

// MARK: - In the talk

/// ○○ posted to the ノート / added photos to an アルバム: a card that opens it.
struct ToocBoardCard: View {
    let message: ToocMessage
    let roomID: String
    let mine: Bool

    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 8) {
                switch message.kind {
                case .note(_, let text):
                    Label("ノート", systemImage: "note.text")
                        .toocFont(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent)
                    Text(text)
                        .toocFont(.subheadline)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                case .album(_, let title, let count):
                    Label("アルバム", systemImage: "photo.stack")
                        .toocFont(.caption.weight(.semibold))
                        .foregroundStyle(theme.accent)
                    Text(title)
                        .toocFont(.headline)
                        .lineLimit(1)
                    Text("写真を\(count)枚追加しました")
                        .toocFont(.subheadline)
                        .foregroundStyle(.secondary)
                default:
                    EmptyView()
                }
                Divider()
                Text("開く")
                    .toocFont(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity)
            }
            .padding(12)
            .frame(width: 240, alignment: .leading)
            .background(theme.theirBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(mine ? theme.accent.opacity(0.6) : Color.clear, lineWidth: 1.5)
            }
        }
        .buttonStyle(.plain)
    }

    private func open() {
        switch message.kind {
        case .note(let id, _): router.sheet = .notes(roomID, id)
        case .album(let id, _, _): router.sheet = .albums(roomID, id)
        default: break
        }
    }
}

/// アルバムに追加: one photo from the talk into one of its albums, or into a new one.
struct ToocAddToAlbumSheet: View {
    let roomID: String
    let message: ToocMessage

    @Environment(ToocStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var board: ToocBoard
    @State private var image: UIImage?
    @State private var working = false
    @State private var error: String?
    @State private var naming = false
    @State private var title = ""

    init(roomID: String, message: ToocMessage, image: UIImage? = nil) {
        self.roomID = roomID
        self.message = message
        _board = State(initialValue: ToocBoard(roomID: roomID))
        _image = State(initialValue: image)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        title = ""
                        naming = true
                    } label: {
                        Label("新しいアルバム", systemImage: "plus.rectangle.on.rectangle")
                            .foregroundStyle(Color.toocBrand)
                    }
                }
                Section("このトークのアルバム") {
                    if !board.loadedAlbums {
                        ProgressView().frame(maxWidth: .infinity)
                    } else if board.albums.isEmpty {
                        Text("アルバムはまだありません")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(board.albums) { album in
                        Button { add(to: album) } label: {
                            HStack {
                                Label(album.title, systemImage: "photo.stack")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Text("\(album.photos.count)枚")
                                    .foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                    }
                }
            }
            .toocFont(.body)
            .disabled(working || image == nil)
            .overlay { if working { ProgressView().controlSize(.large) } }
            .navigationTitle("アルバムに追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.primary) }
                        .accessibilityLabel("閉じる")
                }
            }
            .alert("新しいアルバム", isPresented: $naming) {
                TextField("アルバム名", text: $title)
                Button("キャンセル", role: .cancel) {}
                Button("作成して追加") { create() }
            }
            .alert("追加できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
        .presentationDetents([.medium, .large])
        .task {
            board.listenAlbums()
            if image == nil { image = await ToocViewerPage.load(message) }
        }
        .onDisappear { board.stop() }
    }

    private func add(to album: ToocAlbum) {
        guard let image else { return }
        working = true
        Task {
            do {
                try await board.add([image], to: album, store: store)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }

    private func create() {
        guard let image else { return }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        working = true
        Task {
            do {
                try await board.createAlbum(title: name.isEmpty ? "アルバム" : name, images: [image], store: store)
                dismiss()
            } catch {
                self.error = error.localizedDescription
            }
            working = false
        }
    }
}
