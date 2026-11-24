import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import FirebaseStorage
import Foundation
import SwiftUI
import UIKit

// tooc on Firebase.
//
// Server (Firestore):
//   users/{toocID}                 profile: uid, name, bio, hue, iconURL, backgroundURL, birthday, updatedAt
//   users/{toocID}/friends/{id}    who you added: addedAt
//   rooms/{roomID}                 members (toocIDs), memberUIDs, isGroup, isMynote, title, iconURL, backgroundURL,
//                                  updatedAt, typing {toocID: time}
//   rooms/{roomID}/messages/{id}   senderID, senderUID, date, kind (JSON), replyTo, silent, edited,
//                                  reactions {toocID: emoji}, votes / answers {toocID: [Int]}, readBy [toocID]
// Storage: users/{toocID}/…  and  rooms/{roomID}/…
//
// Kept on this device only: pins, mutes, hidden talks, drafts, what you've read, favourites, nicknames, blocks,
// notices, settings and messages waiting for their send time.

/// What this device remembers for one account.
private struct ToocLocal: Codable {
    struct RoomPrefs: Codable {
        var pinned = false
        var muted = false
        var hidden = false
        var draft = ""
        var lastRead: Date = .distantPast
        var clearedAt: Date = .distantPast
        var deleted: Set<UUID> = []
    }

    struct FriendPrefs: Codable {
        var favorite = false
        var hidden = false
        var blocked = false
        var nickname: String?
    }

    var rooms: [String: RoomPrefs] = [:]
    var friends: [String: FriendPrefs] = [:]
    var notices: [ToocNotice] = []
    var settings = ToocSettings()
    var talkSort: ToocTalkSort = .conversation
    var favoritesFirst = false
    var unreadFirst = false
    var friendSort: ToocTalkSort = .added
    var scheduled: [String: [ToocMessage]] = [:]
    var revealed: Set<UUID> = []
    var laters: [ToocLater] = []
    var laterFirst = false

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rooms = (try? c.decode([String: RoomPrefs].self, forKey: .rooms)) ?? [:]
        friends = (try? c.decode([String: FriendPrefs].self, forKey: .friends)) ?? [:]
        notices = (try? c.decode([ToocNotice].self, forKey: .notices)) ?? []
        settings = (try? c.decode(ToocSettings.self, forKey: .settings)) ?? ToocSettings()
        talkSort = (try? c.decode(ToocTalkSort.self, forKey: .talkSort)) ?? .conversation
        favoritesFirst = (try? c.decode(Bool.self, forKey: .favoritesFirst)) ?? false
        unreadFirst = (try? c.decode(Bool.self, forKey: .unreadFirst)) ?? false
        friendSort = (try? c.decode(ToocTalkSort.self, forKey: .friendSort)) ?? .added
        scheduled = (try? c.decode([String: [ToocMessage]].self, forKey: .scheduled)) ?? [:]
        revealed = (try? c.decode(Set<UUID>.self, forKey: .revealed)) ?? []
        laters = (try? c.decode([ToocLater].self, forKey: .laters)) ?? []
        laterFirst = (try? c.decode(Bool.self, forKey: .laterFirst)) ?? false
    }

    static func file(_ account: String) -> URL {
        let folder = URL.applicationSupportDirectory.appending(path: "tooc", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "\(account).local.json")
    }

    static func load(_ account: String) -> ToocLocal {
        guard let data = try? Data(contentsOf: file(account)),
              let local = try? JSONDecoder().decode(ToocLocal.self, from: data) else { return ToocLocal() }
        return local
    }

    func save(_ account: String) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: Self.file(account), options: .atomic)
    }
}

enum ToocServer {
    /// Whether the app was built with Firebase's settings (GoogleService-Info.plist).
    static var available: Bool { FirebaseApp.app() != nil }
    static func email(_ id: String) -> String { "\(id)@fftooc.app" }

    static var db: Firestore { Firestore.firestore() }
    static func user(_ id: String) -> DocumentReference { db.collection("users").document(id) }
    static func friends(_ id: String) -> CollectionReference { user(id).collection("friends") }
    static func requests(_ id: String) -> CollectionReference { user(id).collection("requests") }
    static func room(_ id: String) -> DocumentReference { db.collection("rooms").document(id) }
    static func messages(_ id: String) -> CollectionReference { room(id).collection("messages") }

    static func upload(_ data: Data, to path: String, type: String) async throws -> String {
        let ref = Storage.storage().reference().child(path)
        let metadata = StorageMetadata()
        metadata.contentType = type
        _ = try await ref.putDataAsync(data, metadata: metadata)
        return try await ref.downloadURL().absoluteString
    }

    static func jpeg(_ image: UIImage, side: CGFloat) -> Data? {
        let scale = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .jpegData(compressionQuality: 0.85)
    }

    /// The value, or Firestore's "remove this field" when there is none.
    static func orDelete(_ value: Any?) -> Any {
        value ?? FieldValue.delete()
    }

    static func encode(_ kind: ToocMessage.Kind) -> String {
        (try? JSONEncoder().encode(kind)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }

    static func decode(_ text: String) -> ToocMessage.Kind? {
        try? JSONDecoder().decode(ToocMessage.Kind.self, from: Data(text.utf8))
    }

    /// Japanese words for what went wrong.
    static func describe(_ error: Error) -> String {
        let code = AuthErrorCode(rawValue: (error as NSError).code)
        switch code {
        case .wrongPassword, .invalidCredential, .userNotFound, .invalidEmail: return "toocIDかパスワードが違います。"
        case .emailAlreadyInUse: return "このtoocIDはもう使われています。"
        case .weakPassword: return "パスワードが短すぎます。"
        case .networkError: return "ネットにつながっていません。"
        case .requiresRecentLogin: return "安全のため、一度ログインし直してからもう一度お試しください。"
        case .tooManyRequests: return "試行が多すぎます。しばらくしてからお試しください。"
        default: return error.localizedDescription
        }
    }
}

/// Accounts used on this device, so you can switch without typing the password again. Passwords stay in the
/// keychain; names and icons are remembered for the account list.
enum ToocAccounts {
    struct Saved: Codable, Identifiable, Hashable {
        let id: String
        var name: String
        var hue: Double
        var iconURL: String?
    }

    private static let service = "com.ffuime.withdays.tooc"
    private static let listKey = "toocSavedAccounts"
    private static let previousKey = "toocPreviousAccount"

    static var saved: [Saved] {
        get {
            guard let data = UserDefaults.standard.data(forKey: listKey),
                  let list = try? JSONDecoder().decode([Saved].self, from: data) else { return [] }
            return list
        }
        set { UserDefaults.standard.set(try? JSONEncoder().encode(newValue), forKey: listKey) }
    }

    /// The account used before the current one (a double tap on じぶん goes back to it).
    static var previous: String? {
        get { UserDefaults.standard.string(forKey: previousKey) }
        set { UserDefaults.standard.set(newValue, forKey: previousKey) }
    }

    static func remember(_ user: ToocUser) {
        var list = saved
        let entry = Saved(id: user.id, name: user.name, hue: user.hue, iconURL: user.iconURL)
        if let index = list.firstIndex(where: { $0.id == user.id }) { list[index] = entry } else { list.append(entry) }
        saved = list
    }

    private static func query(_ id: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id]
    }

    static func store(_ id: String, password: String) {
        SecItemDelete(query(id) as CFDictionary)
        var item = query(id)
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(item as CFDictionary, nil)
        if !saved.contains(where: { $0.id == id }) {
            saved.append(Saved(id: id, name: id, hue: ToocUser.hue(for: id)))
        }
    }

    static func password(_ id: String) -> String? {
        var item = query(id)
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func forget(_ id: String) {
        SecItemDelete(query(id) as CFDictionary)
        saved.removeAll { $0.id == id }
        if previous == id { previous = nil }
    }
}

/// Everything tooc shows: the server's profiles, friends, talks and messages, joined with what this device keeps.
@MainActor
@Observable
final class ToocStore {
    private(set) var account: String? = nil
    var me = ToocUser(id: "me", name: "じぶん", bio: "", hue: 0.58)
    private(set) var users: [String: ToocUser] = [:]
    private(set) var rooms: [ToocRoom] = []
    /// Still finding out who's signed in (at launch).
    private(set) var starting = true

    var notices: [ToocNotice] = [] { didSet { local.notices = notices; save() } }
    var settings = ToocSettings() { didSet { local.settings = settings; save() } }
    var talkSort: ToocTalkSort = .conversation { didSet { local.talkSort = talkSort; save() } }
    var favoritesFirst = false { didSet { local.favoritesFirst = favoritesFirst; save() } }
    var unreadFirst = false { didSet { local.unreadFirst = unreadFirst; save() } }
    var friendSort: ToocTalkSort = .added { didSet { local.friendSort = friendSort; save() } }
    /// Messages marked あとで返信, newest mark first.
    var laters: [ToocLater] = [] { didSet { local.laters = laters; save() } }
    var laterFirst = false { didSet { local.laterFirst = laterFirst; save() } }

    /// The room on screen: what arrives there is read at once.
    var openRoomID: String? = nil {
        didSet { if let openRoomID { markRead(openRoomID) } }
    }
    /// The newest notice to show as a banner.
    var banner: ToocNotice? = nil
    /// Who is typing in which room (room ID → toocID).
    private(set) var typing: [String: String] = [:]
    /// People who added you and you haven't added back.
    private(set) var requests: [ToocUser] = []
    /// The accounts on this device, for switching.
    private(set) var savedAccounts: [ToocAccounts.Saved] = ToocAccounts.saved
    /// Your stickers, newest first.
    private(set) var stickers: [ToocSticker] = []
    /// The account being switched to (for the animation), until it's ready or fails.
    var switchingTo: ToocAccounts.Saved? = nil
    var switchError: String? = nil
    @ObservationIgnored private var requestIDs: [String: Date] = [:]

    @ObservationIgnored private var local = ToocLocal()
    @ObservationIgnored private var profiles: [String: ToocUser] = [:]
    @ObservationIgnored private var friendIDs: [String: Date] = [:]
    @ObservationIgnored private var serverRooms: [String: ToocRoom] = [:]
    @ObservationIgnored private var serverMessages: [String: [ToocMessage]] = [:]
    @ObservationIgnored private var readBy: [UUID: [String]] = [:]
    @ObservationIgnored private var pending: [String: [ToocMessage]] = [:]
    @ObservationIgnored private var typingTimes: [String: [String: Date]] = [:]
    @ObservationIgnored private var listeners: [String: ListenerRegistration] = [:]
    @ObservationIgnored private var loadedRooms: Set<String> = []
    @ObservationIgnored private var lastTypingSent: Date = .distantPast
    @ObservationIgnored private var authHandle: AuthStateDidChangeListenerHandle?
    @ObservationIgnored private var saveTask: Task<Void, Never>?
    /// Talks being made on the server; a first message waits for them.
    @ObservationIgnored private var creating: [String: Task<Void, Never>] = [:]

    private static let accountKey = "toocAccountID"

    init() {
        guard ToocServer.available else {
            starting = false
            return
        }
        authHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in self?.authChanged(user) }
        }
    }

    var theme: ToocTheme { settings.theme }

    // MARK: Account

    var signedIn: Bool { account != nil }
    var hasDeviceAccount: Bool { UserDefaults.standard.string(forKey: Self.accountKey) != nil }

    func createAccount(id: String, password: String) async throws {
        guard ToocServer.available else { throw ToocError("サーバーの設定が入っていません。") }
        let result: AuthDataResult
        do {
            result = try await Auth.auth().createUser(withEmail: ToocServer.email(id), password: password)
        } catch {
            throw ToocError(ToocServer.describe(error))
        }
        do {
            if try await ToocServer.user(id).getDocument().exists {
                try? await result.user.delete()
                throw ToocError("このtoocIDはもう使われています。")
            }
            try await ToocServer.user(id).setData([
                "uid": result.user.uid,
                "name": id,
                "bio": "",
                "hue": Double.random(in: 0...1),
                "updatedAt": Timestamp(date: .now),
            ])
            try await ToocServer.room("note_\(id)").setData([
                "members": [id], "memberUIDs": [result.user.uid], "isGroup": false, "isMynote": true,
                "updatedAt": Timestamp(date: .now),
            ])
        } catch let error as ToocError {
            throw error
        } catch {
            try? await result.user.delete()
            throw ToocError(ToocServer.describe(error))
        }
        signedIn(as: id, password: password)
    }

    func logIn(id typed: String, password: String) async throws {
        guard ToocServer.available else { throw ToocError("サーバーの設定が入っていません。") }
        // An email address stands for the toocID it's linked to.
        let id: String
        if typed.contains("@") { id = try await Self.toocID(forEmail: typed) } else { id = typed }
        do {
            _ = try await Auth.auth().signIn(withEmail: ToocServer.email(id), password: password)
        } catch {
            throw ToocError(ToocServer.describe(error))
        }
        signedIn(as: id, password: password)
    }

    private func signedIn(as id: String, password: String) {
        if let account, account != id { ToocAccounts.previous = account }
        ToocAccounts.store(id, password: password)
        savedAccounts = ToocAccounts.saved
        UserDefaults.standard.set(id, forKey: Self.accountKey)
        start(id)
    }

    /// After signing in with an SMS code (no password to remember for switching).
    func signedInByPhone(as id: String) {
        if let account, account != id { ToocAccounts.previous = account }
        if !ToocAccounts.saved.contains(where: { $0.id == id }) {
            ToocAccounts.saved.append(ToocAccounts.Saved(id: id, name: id, hue: ToocUser.hue(for: id)))
        }
        savedAccounts = ToocAccounts.saved
        UserDefaults.standard.set(id, forKey: Self.accountKey)
        start(id)
    }

    /// Signs out; the account stays on this device's list for switching back.
    func logOut() {
        flush()
        if let account { ToocAccounts.previous = account }
        try? Auth.auth().signOut()
        UserDefaults.standard.removeObject(forKey: Self.accountKey)
        stop()
    }

    /// Changes to another account saved on this device.
    func switchAccount(to id: String) async throws {
        guard id != account else { return }
        guard let password = ToocAccounts.password(id) else {
            throw ToocError("このアカウントのパスワードが保存されていません。ログインし直してください。")
        }
        flush()
        if account != nil { switchingTo = ToocAccounts.saved.first { $0.id == id } }
        do {
            try await logIn(id: id, password: password)
        } catch {
            switchingTo = nil
            throw error
        }
    }

    /// Switches, and shows what went wrong as an alert (for buttons that don't wait).
    func switchAccountShowingErrors(to id: String) {
        Task {
            do {
                try await switchAccount(to: id)
            } catch {
                switchError = error.localizedDescription
            }
        }
    }

    /// Back to the account used before this one.
    func switchToPrevious() async throws {
        guard let previous = ToocAccounts.previous, previous != account,
              ToocAccounts.saved.contains(where: { $0.id == previous }) else {
            throw ToocError("前に使ったアカウントがありません。")
        }
        try await switchAccount(to: previous)
    }

    func forgetAccount(_ id: String) {
        ToocAccounts.forget(id)
        savedAccounts = ToocAccounts.saved
    }

    func changePassword(current: String, new: String) async throws {
        guard let user = Auth.auth().currentUser, let account else { throw ToocError("ログインしていません。") }
        do {
            try await user.reauthenticate(with: EmailAuthProvider.credential(withEmail: ToocServer.email(account),
                                                                            password: current))
            try await user.updatePassword(to: new)
        } catch {
            throw ToocError(ToocServer.describe(error))
        }
    }

    /// Deletes the profile, the friend list and the sign-in. Talks stay with the others in them.
    func deleteAccount() async throws {
        guard let user = Auth.auth().currentUser, let account else { return }
        do {
            for id in friendIDs.keys { try? await ToocServer.friends(account).document(id).delete() }
            try? await ToocServer.room("note_\(account)").delete()
            try await ToocServer.user(account).delete()
            try await user.delete()
        } catch {
            throw ToocError(ToocServer.describe(error))
        }
        try? FileManager.default.removeItem(at: ToocLocal.file(account))
        UserDefaults.standard.removeObject(forKey: Self.accountKey)
        forgetAccount(account)
        stop()
    }

    private func authChanged(_ user: FirebaseAuth.User?) {
        defer { starting = false }
        guard let user else {
            if account != nil { stop() }
            return
        }
        guard account == nil else { return }
        if let id = UserDefaults.standard.string(forKey: Self.accountKey) {
            start(id)
            return
        }
        // Signed in, but this device doesn't know the toocID: ask the server.
        Task {
            let found = try? await ToocServer.db.collection("users").whereField("uid", isEqualTo: user.uid).limit(to: 1)
                .getDocuments()
            if let id = found?.documents.first?.documentID {
                UserDefaults.standard.set(id, forKey: Self.accountKey)
                start(id)
            }
        }
    }

    private func start(_ id: String) {
        guard account != id else { return }
        stop()
        local = ToocLocal.load(id)
        notices = local.notices
        settings = local.settings
        talkSort = local.talkSort
        favoritesFirst = local.favoritesFirst
        unreadFirst = local.unreadFirst
        friendSort = local.friendSort
        laters = local.laters
        laterFirst = local.laterFirst
        me = ToocUser(id: id, name: id, bio: "", hue: 0.58)
        account = id
        listenToMe(id)
        listenToFriends(id)
        listenToRequests(id)
        listenToStickers(id)
        listenToRooms()
    }

    private func stop() {
        listeners.values.forEach { $0.remove() }
        listeners = [:]
        profiles = [:]
        friendIDs = [:]
        serverRooms = [:]
        serverMessages = [:]
        readBy = [:]
        pending = [:]
        typingTimes = [:]
        loadedRooms = []
        users = [:]
        rooms = []
        typing = [:]
        requestIDs = [:]
        requests = []
        stickers = []
        account = nil
        openRoomID = nil
        banner = nil
    }

    // MARK: Listening

    private func listenToMe(_ id: String) {
        listeners["me"] = ToocServer.user(id).addSnapshotListener { [weak self] snapshot, _ in
            Task { @MainActor in
                guard let self, let snapshot, let data = snapshot.data() else { return }
                self.me = Self.profile(id, data, keeping: self.me)
                ToocAccounts.remember(self.me)
                self.savedAccounts = ToocAccounts.saved
            }
        }
    }

    private func listenToFriends(_ id: String) {
        listeners["friends"] = ToocServer.friends(id).addSnapshotListener { [weak self] snapshot, _ in
            Task { @MainActor in
                guard let self, let snapshot else { return }
                var ids: [String: Date] = [:]
                for doc in snapshot.documents {
                    ids[doc.documentID] = (doc.data()["addedAt"] as? Timestamp)?.dateValue() ?? .distantPast
                }
                self.friendIDs = ids
                ids.keys.forEach(self.watchUser)
                self.rebuildUsers()
            }
        }
    }

    /// Friend requests: people who added you. A new one is announced.
    private func listenToRequests(_ id: String) {
        listeners["requests"] = ToocServer.requests(id).addSnapshotListener { [weak self] snapshot, _ in
            Task { @MainActor in
                guard let self, let snapshot else { return }
                let first = self.requestIDs.isEmpty && !self.loadedRooms.contains("requests")
                self.loadedRooms.insert("requests")
                var ids: [String: Date] = [:]
                for doc in snapshot.documents {
                    ids[doc.documentID] = (doc.data()["at"] as? Timestamp)?.dateValue() ?? .now
                }
                let fresh = ids.keys.filter { self.requestIDs[$0] == nil && self.friendIDs[$0] == nil }
                self.requestIDs = ids
                ids.keys.forEach(self.watchUser)
                self.rebuildUsers()
                guard !first else { return }
                for from in fresh {
                    let user = await self.fetchUser(from)
                    self.announce(ToocNotice(title: "友だち申請", body: "\(user?.name ?? from)さんがあなたを友だちに追加しました",
                                             userID: from))
                }
            }
        }
    }

    /// A notice: tooc's banner when in front, the system's notification otherwise.
    private func announce(_ notice: ToocNotice) {
        if UIApplication.shared.applicationState == .active {
            notify(notice)
        } else {
            notices.insert(notice, at: 0)
            if settings.notifications {
                ToocNotifications.schedule(id: "tooc-\(notice.id.uuidString)", title: notice.title,
                                           body: settings.showContent ? notice.body : "新しいお知らせがあります",
                                           roomID: notice.roomID ?? "", at: .now)
            }
        }
    }

    private func listenToRooms() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        listeners["rooms"] = ToocServer.db.collection("rooms").whereField("memberUIDs", arrayContains: uid)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self, let snapshot else { return }
                    var seen: Set<String> = []
                    for doc in snapshot.documents {
                        let room = Self.room(doc.documentID, doc.data())
                        seen.insert(room.id)
                        self.serverRooms[room.id] = room
                        room.memberIDs.forEach(self.watchUser)
                        self.readTyping(doc.documentID, doc.data())
                        self.listenToMessages(room.id)
                    }
                    for id in self.serverRooms.keys where !seen.contains(id) {
                        self.serverRooms[id] = nil
                        self.listeners["messages:\(id)"]?.remove()
                        self.listeners["messages:\(id)"] = nil
                    }
                    self.rebuildRooms()
                }
            }
    }

    private func listenToMessages(_ roomID: String) {
        guard listeners["messages:\(roomID)"] == nil else { return }
        listeners["messages:\(roomID)"] = ToocServer.messages(roomID).order(by: "date").limit(toLast: 300)
            .addSnapshotListener { [weak self] snapshot, error in
                Task { @MainActor in
                    guard let self else { return }
                    if error != nil {
                        self.retryMessages(roomID)
                        return
                    }
                    guard let snapshot else { return }
                    let first = !self.loadedRooms.contains(roomID)
                    var list: [ToocMessage] = []
                    for doc in snapshot.documents {
                        if let message = self.message(doc.documentID, doc.data()) { list.append(message) }
                    }
                    self.serverMessages[roomID] = list
                    // Pending copies that reached the server are no longer needed.
                    let arrived = Set(list.map(\.id))
                    self.pending[roomID]?.removeAll { arrived.contains($0.id) }
                    if first {
                        self.loadedRooms.insert(roomID)
                    } else {
                        for change in snapshot.documentChanges where change.type == .added {
                            if let message = list.first(where: { $0.id.uuidString == change.document.documentID }) {
                                self.arrived(message, in: roomID)
                            }
                        }
                    }
                    self.rebuildRooms()
                    if self.openRoomID == roomID { self.markRead(roomID) }
                }
            }
    }

    /// A talk made a moment ago may not be readable yet (its listener is refused and stops): listen again shortly.
    private func retryMessages(_ roomID: String) {
        listeners["messages:\(roomID)"]?.remove()
        listeners["messages:\(roomID)"] = nil
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard let self, self.account != nil, self.serverRooms[roomID] != nil else { return }
            self.listenToMessages(roomID)
        }
    }

    private func listenToStickers(_ id: String) {
        listeners["stickers"] = ToocServer.user(id).collection("stickers").order(by: "createdAt", descending: true)
            .addSnapshotListener { [weak self] snapshot, _ in
                Task { @MainActor in
                    guard let self, let snapshot else { return }
                    self.stickers = snapshot.documents.compactMap { doc in
                        guard let url = doc.data()["url"] as? String else { return nil }
                        return ToocSticker(id: doc.documentID, url: url)
                    }
                }
            }
    }

    /// Profiles of everyone in a talk or the friend list.
    private func watchUser(_ id: String) {
        guard id != account, listeners["user:\(id)"] == nil else { return }
        listeners["user:\(id)"] = ToocServer.user(id).addSnapshotListener { [weak self] snapshot, _ in
            Task { @MainActor in
                guard let self, let snapshot, let data = snapshot.data() else { return }
                self.profiles[id] = Self.profile(id, data, keeping: nil)
                self.rebuildUsers()
            }
        }
    }

    private func readTyping(_ roomID: String, _ data: [String: Any]) {
        let map = data["typing"] as? [String: Any] ?? [:]
        typingTimes[roomID] = map.compactMapValues { ($0 as? Timestamp)?.dateValue() }
        refreshTyping(roomID)
    }

    private func refreshTyping(_ roomID: String) {
        let fresh = (typingTimes[roomID] ?? [:]).filter { $0.key != account && Date.now.timeIntervalSince($0.value) < 7 }
        let who = fresh.max { $0.value < $1.value }?.key
        if typing[roomID] != who { typing[roomID] = who }
        if who != nil {
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(7.5))
                self?.refreshTyping(roomID)
            }
        }
    }

    // MARK: Reading the server

    private static func profile(_ id: String, _ data: [String: Any], keeping old: ToocUser?) -> ToocUser {
        var user = old ?? ToocUser(id: id, name: id, bio: "", hue: 0.58)
        user.uid = data["uid"] as? String
        user.name = data["name"] as? String ?? id
        user.bio = data["bio"] as? String ?? ""
        user.hue = data["hue"] as? Double ?? ToocUser.hue(for: id)
        user.iconURL = data["iconURL"] as? String
        user.backgroundURL = data["backgroundURL"] as? String
        user.hasBackground = data["hasBackground"] as? Bool ?? true
        user.birthday = (data["birthday"] as? Timestamp)?.dateValue()
        user.profileUpdatedAt = (data["updatedAt"] as? Timestamp)?.dateValue() ?? .distantPast
        user.findable = data["findable"] as? Bool ?? false
        return user
    }

    private static func room(_ id: String, _ data: [String: Any]) -> ToocRoom {
        var room = ToocRoom(id: id, title: data["title"] as? String, memberIDs: data["members"] as? [String] ?? [],
                            isGroup: data["isGroup"] as? Bool ?? false, isMynote: data["isMynote"] as? Bool ?? false)
        room.iconURL = data["iconURL"] as? String
        room.backgroundURL = data["backgroundURL"] as? String
        return room
    }

    private func message(_ id: String, _ data: [String: Any]) -> ToocMessage? {
        guard let uuid = UUID(uuidString: id), let sender = data["senderID"] as? String,
              var kind = ToocServer.decode(data["kind"] as? String ?? "") else { return nil }
        if case .poll(var poll) = kind {
            poll.votes = (data["votes"] as? [String: [Int]]) ?? [:]
            kind = .poll(poll)
        }
        if case .datePoll(var poll) = kind {
            poll.answers = (data["answers"] as? [String: [Int]]) ?? [:]
            kind = .datePoll(poll)
        }
        if case .amida(var amida) = kind {
            amida.revealed = local.revealed.contains(uuid)
            kind = .amida(amida)
        }
        let read = (data["readBy"] as? [String] ?? []).filter { $0 != sender }
        readBy[uuid] = read
        var message = ToocMessage(id: uuid, senderID: sender, kind: kind,
                                  date: (data["date"] as? Timestamp)?.dateValue() ?? .now)
        message.readCount = read.count
        message.replyTo = (data["replyTo"] as? String).flatMap(UUID.init(uuidString:))
        message.silent = data["silent"] as? Bool ?? false
        message.edited = data["edited"] as? Bool ?? false
        message.reactions = data["reactions"] as? [String: String] ?? [:]
        message.mentions = data["mentions"] as? [String] ?? []
        message.laterBy = data["laterBy"] as? [String] ?? []
        message.urgency = (data["urgency"] as? Int).flatMap(ToocUrgency.init(rawValue:))
        return message
    }

    // MARK: Putting it together

    private func rebuildUsers() {
        var next: [String: ToocUser] = [:]
        let ids = Set(profiles.keys).union(friendIDs.keys).union(requestIDs.keys)
        for id in ids {
            var user = profiles[id] ?? ToocUser(id: id, name: id, bio: "", hue: ToocUser.hue(for: id))
            let prefs = local.friends[id] ?? .init()
            user.isFriend = friendIDs[id] != nil
            user.addedAt = friendIDs[id] ?? .distantPast
            user.isFavorite = prefs.favorite
            user.isHidden = prefs.hidden
            user.isBlocked = prefs.blocked
            user.nickname = prefs.nickname
            next[id] = user
        }
        users = next
        requests = requestIDs.keys.filter { friendIDs[$0] == nil && local.friends[$0]?.blocked != true }
            .compactMap { next[$0] ?? profiles[$0] }
            .sorted { (requestIDs[$0.id] ?? .now) > (requestIDs[$1.id] ?? .now) }
    }

    private func rebuildRooms() {
        var next: [ToocRoom] = []
        for var room in serverRooms.values {
            let prefs = local.rooms[room.id] ?? .init()
            let blocked = Set(local.friends.filter { $0.value.blocked }.map(\.key))
            var messages = (serverMessages[room.id] ?? []).filter {
                $0.date > prefs.clearedAt && !prefs.deleted.contains($0.id) && !blocked.contains($0.senderID)
            }
            let sent = Set(messages.map(\.id))
            messages += (pending[room.id] ?? []).filter { !sent.contains($0.id) }
            messages += local.scheduled[room.id] ?? []
            // Without the account's own ID in the list, a DM's other person is everyone in it but you.
            room.memberIDs = room.isMynote ? [me.id] : room.memberIDs.filter { $0 != account }
            room.messages = messages
            room.pinned = prefs.pinned
            room.muted = prefs.muted
            room.hidden = prefs.hidden
            room.draft = prefs.draft
            let unread = openRoomID == room.id ? [] : messages.filter {
                $0.scheduledAt == nil && $0.senderID != account && $0.date > prefs.lastRead
            }
            room.unread = unread.count
            room.mentioned = unread.contains { $0.mentions.contains(account ?? "") }
            if !room.isGroup && !room.isMynote, let other = room.memberIDs.first, local.friends[other]?.blocked == true {
                room.hidden = true
            }
            next.append(room)
        }
        rooms = next
    }

    /// A message from someone else just arrived: count it, and tell (banner in front, the system's otherwise).
    private func arrived(_ message: ToocMessage, in roomID: String) {
        guard message.senderID != account, openRoomID != roomID, let room = serverRooms[roomID] else { return }
        if local.rooms[roomID]?.hidden == true { local.rooms[roomID]?.hidden = false }
        guard local.friends[message.senderID]?.blocked != true else { return }
        let who = displayName(message.senderID)
        if let account, message.mentions.contains(account) {
            announce(ToocNotice(title: "\(who)があなたをメンションしました", body: message.preview, userID: message.senderID,
                                roomID: roomID))
            return
        }
        guard local.rooms[roomID]?.muted != true, !message.silent else { return }
        let title = room.isGroup ? "\(name(of: room))・\(who)" : who
        announce(ToocNotice(title: title, body: message.preview, userID: message.senderID, roomID: roomID))
    }

    private func save() {
        guard let account else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.local.save(account)
        }
    }

    func flush() {
        guard let account else { return }
        local.save(account)
    }

    // MARK: Lookups

    func user(_ id: String) -> ToocUser? {
        if id == me.id { return me }
        if id == ToocUser.mynoteID { return .mynote }
        return users[id]
    }

    func displayName(_ id: String) -> String { user(id)?.displayName ?? id }

    var unreadTotal: Int { rooms.filter { !$0.hidden && !$0.muted }.reduce(0) { $0 + $1.unread } }
    var unseenNotices: Int { notices.filter { !$0.seen }.count }

    func room(_ id: String) -> ToocRoom? { rooms.first { $0.id == id } }

    var mynote: ToocRoom? { rooms.first(where: \.isMynote) }

    func name(of room: ToocRoom) -> String {
        if room.isMynote { return "Mynote" }
        if let title = room.title { return title }
        return room.memberIDs.compactMap { user($0) }.first?.displayName ?? "トーク"
    }

    /// The icon's owner: the other person, Mynote's own icon, or the group's.
    func iconUser(of room: ToocRoom) -> ToocUser {
        if room.isMynote { return .mynote }
        if room.isGroup {
            var group = ToocUser(id: room.id, name: room.title ?? "G", bio: "", hue: ToocUser.hue(for: room.id))
            group.iconURL = room.iconURL
            group.backgroundURL = room.backgroundURL
            group.hasBackground = true
            return group
        }
        return room.memberIDs.compactMap { user($0) }.first ?? me
    }

    func isFavorite(_ room: ToocRoom) -> Bool {
        guard !room.isGroup, !room.isMynote else { return false }
        return room.memberIDs.contains { users[$0]?.isFavorite == true }
    }

    /// A stand-in until the server answers (also for an ID that doesn't exist).
    func lookUp(_ id: String) -> ToocUser {
        if let user = user(id) { return user }
        watchUser(id)
        return ToocUser(id: id, name: id, bio: "", hue: ToocUser.hue(for: id), isFriend: false)
    }

    /// Someone by toocID, from the server; nil when nobody has it. A typed search finds only people who allow it
    /// (or are already friends); QR codes and links always find.
    func fetchUser(_ id: String, bySearch: Bool = false) async -> ToocUser? {
        if id == account { return me }
        guard let snapshot = try? await ToocServer.user(id).getDocument(), let data = snapshot.data() else { return nil }
        if bySearch, data["findable"] as? Bool != true, friendIDs[id] == nil { return nil }
        var user = Self.profile(id, data, keeping: users[id])
        user.isFriend = friendIDs[id] != nil
        watchUser(id)
        return user
    }

    // MARK: Lists

    var visibleRooms: [ToocRoom] {
        rooms.filter { !$0.hidden }.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if laterFirst, hasLater(a.id) != hasLater(b.id) { return hasLater(a.id) }
            if favoritesFirst, isFavorite(a) != isFavorite(b) { return isFavorite(a) }
            if unreadFirst, (a.unread > 0) != (b.unread > 0) { return a.unread > 0 }
            let ka = key(a, talkSort), kb = key(b, talkSort)
            return ka != kb ? ka > kb : a.id < b.id
        }
    }

    func rooms(_ filter: ToocTalkFilter) -> [ToocRoom] {
        switch filter {
        case .all: visibleRooms
        case .friends: visibleRooms.filter { !$0.isGroup && !$0.isMynote }
        case .groups: visibleRooms.filter(\.isGroup)
        }
    }

    private func key(_ room: ToocRoom, _ sort: ToocTalkSort) -> Date {
        let members = room.memberIDs.compactMap { users[$0] }
        switch sort {
        case .conversation: return room.last?.date ?? .distantPast
        case .added: return members.map(\.addedAt).max() ?? .distantPast
        case .profile: return members.map(\.profileUpdatedAt).max() ?? .distantPast
        }
    }

    var friends: [ToocUser] {
        users.values.filter { $0.isFriend && !$0.isHidden && !$0.isBlocked }.sorted { a, b in
            switch friendSort {
            case .added: return a.addedAt > b.addedAt
            case .profile: return a.profileUpdatedAt > b.profileUpdatedAt
            case .conversation:
                let last = { (user: ToocUser) in
                    self.rooms.first { !$0.isGroup && $0.memberIDs == [user.id] }?.last?.date ?? .distantPast
                }
                return last(a) > last(b)
            }
        }
    }

    var favorites: [ToocUser] { friends.filter(\.isFavorite) }
    var hiddenFriends: [ToocUser] {
        users.values.filter { $0.isFriend && $0.isHidden && !$0.isBlocked }.sorted { $0.displayName < $1.displayName }
    }
    var blockedUsers: [ToocUser] { users.values.filter(\.isBlocked).sorted { $0.displayName < $1.displayName } }
    var hiddenRooms: [ToocRoom] { rooms.filter(\.hidden) }

    var scheduledMessages: [ToocScheduledEntry] {
        rooms.flatMap { room in room.waiting.map { ToocScheduledEntry(room: room, message: $0) } }
            .sorted { ($0.message.scheduledAt ?? .now) < ($1.message.scheduledAt ?? .now) }
    }

    // MARK: Changes kept on this device

    /// Pins, mutes, hiding and drafts (this device only).
    func update(_ id: String, _ change: (inout ToocRoom) -> Void) {
        guard var room = room(id) else { return }
        change(&room)
        var prefs = local.rooms[id] ?? .init()
        prefs.pinned = room.pinned
        prefs.muted = room.muted
        prefs.hidden = room.hidden
        prefs.draft = room.draft
        local.rooms[id] = prefs
        save()
        rebuildRooms()
    }

    private func friendPrefs(_ id: String, _ change: (inout ToocLocal.FriendPrefs) -> Void) {
        var prefs = local.friends[id] ?? .init()
        change(&prefs)
        local.friends[id] = prefs
        save()
        rebuildUsers()
        rebuildRooms()
    }

    func markRead(_ id: String) {
        var prefs = local.rooms[id] ?? .init()
        prefs.lastRead = .now
        local.rooms[id] = prefs
        save()
        if let index = rooms.firstIndex(where: { $0.id == id }), rooms[index].unread != 0 { rooms[index].unread = 0 }
        sendReadReceipts(id)
    }

    func markAllRead() { for room in rooms where room.unread > 0 { markRead(room.id) } }

    /// Removes a talk from this device's list (and its history here). It comes back if someone writes.
    func delete(_ id: String) {
        guard let room = room(id), !room.isMynote else { return }
        var prefs = local.rooms[id] ?? .init()
        prefs.hidden = true
        prefs.clearedAt = .now
        local.rooms[id] = prefs
        save()
        rebuildRooms()
    }

    func clearHistory(_ id: String) {
        var prefs = local.rooms[id] ?? .init()
        prefs.clearedAt = .now
        local.rooms[id] = prefs
        save()
        rebuildRooms()
    }

    func toggleFavorite(_ id: String) { friendPrefs(id) { $0.favorite.toggle() } }
    func hideFriend(_ id: String) { friendPrefs(id) { $0.hidden = true } }
    func showFriend(_ id: String) { friendPrefs(id) { $0.hidden = false } }
    func block(_ id: String) { friendPrefs(id) { $0.blocked = true; $0.favorite = false } }
    func unblock(_ id: String) { friendPrefs(id) { $0.blocked = false } }

    func rename(_ id: String, to nickname: String?) {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        friendPrefs(id) { $0.nickname = (trimmed?.isEmpty ?? true) ? nil : trimmed }
    }

    func notify(_ notice: ToocNotice, banner showBanner: Bool = true) {
        notices.insert(notice, at: 0)
        if notices.count > 100 { notices.removeLast(notices.count - 100) }
        if settings.notifications && showBanner { banner = notice }
    }

    func markNoticesSeen() {
        guard notices.contains(where: { !$0.seen }) else { return }
        for index in notices.indices { notices[index].seen = true }
    }

    // MARK: Changes on the server

    func addFriend(_ found: ToocUser) {
        guard let account, found.id != account else { return }
        friendIDs[found.id] = .now
        friendPrefs(found.id) { $0.hidden = false; $0.blocked = false }
        watchUser(found.id)
        requestIDs[found.id] = nil
        rebuildUsers()
        Task {
            try? await ToocServer.friends(account).document(found.id).setData(["addedAt": Timestamp(date: .now)])
            // They see a request, unless it was theirs we just answered.
            try? await ToocServer.requests(account).document(found.id).delete()
            try? await ToocServer.requests(found.id).document(account).setData(["at": Timestamp(date: .now)])
        }
        notices.insert(ToocNotice(title: "友だち追加", body: "\(found.displayName)を友だちに追加しました", userID: found.id), at: 0)
    }

    /// Turns down a request (they aren't told).
    func decline(_ id: String) {
        guard let account else { return }
        requestIDs[id] = nil
        rebuildUsers()
        Task { try? await ToocServer.requests(account).document(id).delete() }
    }

    /// The one-to-one room with someone; made on the server the first time.
    @discardableResult
    func room(with userID: String) -> ToocRoom {
        guard let account else { return ToocRoom(id: "none", memberIDs: []) }
        let id = "dm_" + [account, userID].sorted().joined(separator: "__")
        if local.rooms[id]?.hidden == true { update(id) { $0.hidden = false } }
        if let room = room(id) { return room }
        let room = ToocRoom(id: id, memberIDs: [userID])
        serverRooms[id] = room
        rebuildRooms()
        createDM(id, with: userID)
        return room
    }

    /// Writes a one-to-one talk to the server (again, harmlessly, if it's already there).
    private func createDM(_ id: String, with userID: String) {
        guard let account else { return }
        let theirUID = users[userID]?.uid ?? profiles[userID]?.uid
        creating[id] = Task {
            var uid = theirUID
            if uid == nil { uid = await fetchUser(userID)?.uid }
            guard let mine = Auth.auth().currentUser?.uid, let uid else { return }
            try? await ToocServer.room(id).setData([
                "members": [account, userID], "memberUIDs": [mine, uid], "isGroup": false, "isMynote": false,
                "updatedAt": Timestamp(date: .now),
            ], merge: true)
        }
    }

    func makeGroup(name: String, members: [String]) -> ToocRoom {
        let id = "g_\(UUID().uuidString)"
        let room = ToocRoom(id: id, title: name, memberIDs: members, isGroup: true)
        serverRooms[id] = room
        rebuildRooms()
        guard let account, let mine = Auth.auth().currentUser?.uid else { return room }
        let uids = members.compactMap { users[$0]?.uid }
        creating[id] = Task {
            try? await ToocServer.room(id).setData([
                "members": [account] + members, "memberUIDs": [mine] + uids, "isGroup": true, "isMynote": false,
                "title": name, "updatedAt": Timestamp(date: .now),
            ])
        }
        return room
    }

    func editGroup(_ id: String, name: String, iconFile: String?, backgroundFile: String?, members: [String]) {
        guard let account, let mine = Auth.auth().currentUser?.uid, let room = room(id) else { return }
        let uids = members.compactMap { users[$0]?.uid }
        Task {
            var fields: [String: Any] = [
                "title": name.isEmpty ? (room.title ?? "") : name,
                "members": [account] + members,
                "memberUIDs": [mine] + uids,
                "updatedAt": Timestamp(date: .now),
            ]
            let icon = await uploadPhoto(iconFile, current: room.iconURL, to: "rooms/\(id)/icon", side: 1024)
            let background = await uploadPhoto(backgroundFile, current: room.backgroundURL,
                                               to: "rooms/\(id)/background", side: 2048)
            fields["iconURL"] = ToocServer.orDelete(icon)
            fields["backgroundURL"] = ToocServer.orDelete(background)
            try? await ToocServer.room(id).updateData(fields)
        }
    }

    func leave(_ id: String) {
        guard let account, let mine = Auth.auth().currentUser?.uid, room(id)?.isGroup == true else { return }
        serverRooms[id] = nil
        rebuildRooms()
        Task {
            try? await ToocServer.room(id).updateData([
                "members": FieldValue.arrayRemove([account]),
                "memberUIDs": FieldValue.arrayRemove([mine]),
            ])
        }
    }

    // MARK: あとで返信

    func isLater(_ id: UUID) -> Bool { laters.contains { $0.messageID == id } }
    func hasLater(_ roomID: String) -> Bool { laters.contains { $0.roomID == roomID } }

    /// Marks or unmarks it, here (for the list) and on the server (so the others in the talk see it).
    func toggleLater(_ message: ToocMessage, in roomID: String) {
        guard message.senderID != me.id else { return }
        let marked = isLater(message.id) || message.laterBy.contains(me.id)
        if marked {
            laters.removeAll { $0.messageID == message.id }
        } else {
            laters.insert(ToocLater(roomID: roomID, messageID: message.id, marked: .now), at: 0)
        }
        change(message.id, in: roomID, ["laterBy": marked ? FieldValue.arrayRemove([me.id]) : FieldValue.arrayUnion([me.id])])
    }

    /// Everything you put off in the talk, cleared once you say something there.
    private func clearLaters(in roomID: String) {
        var ids = Set(laters.filter { $0.roomID == roomID }.map(\.messageID))
        for message in room(roomID)?.messages ?? [] where message.laterBy.contains(me.id) { ids.insert(message.id) }
        guard !ids.isEmpty else { return }
        laters.removeAll { $0.roomID == roomID }
        for id in ids { change(id, in: roomID, ["laterBy": FieldValue.arrayRemove([me.id])]) }
    }

    /// The marked messages still there, with their talks.
    var laterItems: [ToocLaterItem] {
        laters.compactMap { later in
            guard let room = room(later.roomID), let message = room.messages.first(where: { $0.id == later.messageID })
            else { return nil }
            return ToocLaterItem(message: message, room: room)
        }
    }

    /// Only the name or the bio, changed in place on the profile.
    func editNameAndBio(name: String? = nil, bio: String? = nil) {
        guard let account else { return }
        var fields: [String: Any] = ["updatedAt": Timestamp(date: .now)]
        if let name {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            me.name = trimmed.isEmpty ? account : trimmed
            fields["name"] = me.name
        }
        if let bio {
            me.bio = bio
            fields["bio"] = bio
        }
        Task { try? await ToocServer.user(account).updateData(fields) }
    }

    func editProfile(name: String, bio: String, hue: Double, iconFile: String?, backgroundFile: String?,
                     hasBackground: Bool, birthday: Date?) {
        guard let account else { return }
        let old = me
        // Shown at once; the photos follow once uploaded.
        me.name = name
        me.bio = bio
        me.hue = hue
        me.iconFile = iconFile
        me.backgroundFile = backgroundFile
        me.hasBackground = hasBackground
        me.birthday = birthday
        Task {
            var fields: [String: Any] = [
                "name": name, "bio": bio, "hue": hue, "hasBackground": hasBackground,
                "birthday": ToocServer.orDelete(birthday.map { Timestamp(date: $0) }),
                "updatedAt": Timestamp(date: .now),
            ]
            let icon = await uploadPhoto(iconFile, current: old.iconURL, to: "users/\(account)/icon", side: 1024)
            let background = await uploadPhoto(backgroundFile, current: old.backgroundURL,
                                               to: "users/\(account)/background", side: 2048)
            fields["iconURL"] = ToocServer.orDelete(icon)
            fields["backgroundURL"] = ToocServer.orDelete(background)
            try? await ToocServer.user(account).updateData(fields)
        }
    }

    /// A newly chosen local photo goes up and its address comes back; no photo means none; the one already on the
    /// server (its cached copy's name) stays as it is.
    private func uploadPhoto(_ file: String?, current: String?, to path: String, side: CGFloat) async -> String? {
        guard let file else { return nil }
        if let current, file == ToocFiles.remoteName(current) { return current }
        guard let image = ToocFiles.image(file), let data = ToocServer.jpeg(image, side: side),
              let url = try? await ToocServer.upload(data, to: "\(path)-\(UUID().uuidString.prefix(8)).jpg",
                                                     type: "image/jpeg") else { return current }
        // Keep the picture under its new address, so it isn't downloaded again.
        try? data.write(to: ToocFiles.url(ToocFiles.remoteName(url)))
        return url
    }

    // MARK: Sending

    @discardableResult
    func send(_ kind: ToocMessage.Kind, in roomID: String, replyTo: UUID? = nil, silent: Bool = false, at time: Date? = nil,
              mentions: [String] = [], urgency: ToocUrgency? = nil) -> UUID {
        var message = ToocMessage(senderID: me.id, kind: kind, date: time ?? .now, sending: true, replyTo: replyTo,
                                  silent: silent, scheduledAt: time)
        message.mentions = mentions
        message.urgency = urgency
        if let time, time > .now {
            message.sending = false
            local.scheduled[roomID, default: []].append(message)
            save()
            rebuildRooms()
            return message.id
        }
        // Saying something in the talk answers what was put off there.
        clearLaters(in: roomID)
        message.scheduledAt = nil
        pending[roomID, default: []].append(message)
        if var prefs = local.rooms[roomID] {
            prefs.draft = ""
            prefs.hidden = false
            local.rooms[roomID] = prefs
        }
        rebuildRooms()
        upload(message, in: roomID)
        return message.id
    }

    private func upload(_ message: ToocMessage, in roomID: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return failed(message, in: roomID) }
        let waitFor = creating[roomID]
        Task {
            await waitFor?.value
            var kind = message.kind
            switch kind {
            case .photo(let file?):
                guard let image = ToocFiles.image(file), let data = ToocServer.jpeg(image, side: 2048),
                      let url = try? await ToocServer.upload(data, to: "rooms/\(roomID)/\(message.id.uuidString).jpg",
                                                             type: "image/jpeg") else { return failed(message, in: roomID) }
                try? data.write(to: ToocFiles.url(ToocFiles.remoteName(url)))
                kind = .remotePhoto(url)
            case .file(let name, let file, let size):
                guard let data = try? Data(contentsOf: ToocFiles.url(file)),
                      let url = try? await ToocServer.upload(data, to: "rooms/\(roomID)/files/\(message.id.uuidString)/\(name)",
                                                             type: "application/octet-stream") else {
                    return failed(message, in: roomID)
                }
                kind = .remoteFile(name: name, url: url, size: size)
            default:
                break
            }
            var fields: [String: Any] = [
                "senderID": message.senderID,
                "senderUID": uid,
                "date": Timestamp(date: message.date),
                "kind": ToocServer.encode(kind),
                "silent": message.silent,
                "edited": false,
                "readBy": [String](),
            ]
            if let reply = message.replyTo { fields["replyTo"] = reply.uuidString }
            if !message.mentions.isEmpty { fields["mentions"] = message.mentions }
            if let urgency = message.urgency { fields["urgency"] = urgency.rawValue }
            do {
                try await ToocServer.messages(roomID).document(message.id.uuidString).setData(fields)
                // On the server: no longer "sending", even before the talk's listener hears of it.
                if let index = pending[roomID]?.firstIndex(where: { $0.id == message.id }) {
                    pending[roomID]?[index].sending = false
                    pending[roomID]?[index].kind = kind
                    rebuildRooms()
                }
                try? await ToocServer.room(roomID).updateData([
                    "updatedAt": Timestamp(date: .now),
                    FieldPath(["typing", message.senderID]): FieldValue.delete(),
                ])
            } catch {
                failed(message, in: roomID)
            }
        }
    }

    /// Kept in the talk with a mark, to send again or delete.
    private func failed(_ message: ToocMessage, in roomID: String) {
        if let index = pending[roomID]?.firstIndex(where: { $0.id == message.id }) {
            pending[roomID]?[index].sending = false
            pending[roomID]?[index].failed = true
        }
        rebuildRooms()
    }

    func resend(_ id: UUID, in roomID: String) {
        guard let index = pending[roomID]?.firstIndex(where: { $0.id == id }), var message = pending[roomID]?[index] else { return }
        message.failed = false
        message.sending = true
        message.date = .now
        pending[roomID]?.remove(at: index)
        pending[roomID, default: []].append(message)
        rebuildRooms()
        // The talk may still be missing on the server: make sure it's there first.
        if let room = serverRooms[roomID], !room.isGroup, !room.isMynote,
           let other = room.memberIDs.first(where: { $0 != account }) {
            createDM(roomID, with: other)
        }
        upload(message, in: roomID)
    }

    func discardFailed(_ id: UUID, in roomID: String) {
        pending[roomID]?.removeAll { $0.id == id }
        rebuildRooms()
    }

    /// Sends a copy of a message to other talks.
    func forward(_ message: ToocMessage, to roomIDs: [String]) {
        for id in roomIDs { send(message.kind, in: id) }
    }

    // MARK: Stickers

    /// Makes a sticker from a picture (already cut out): a PNG with see-through edges, kept on your account.
    func addSticker(_ image: UIImage) async throws {
        guard let account else { return }
        let side: CGFloat = 512
        let scale = min(side / max(image.size.width, 1), side / max(image.size.height, 1), 1)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let png = UIGraphicsImageRenderer(size: size, format: format)
            .image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
            .pngData()
        guard let png else { throw ToocError("画像を作れませんでした。") }
        let id = UUID().uuidString
        let url = try await ToocServer.upload(png, to: "users/\(account)/stickers/\(id).png", type: "image/png")
        try? png.write(to: ToocFiles.url(ToocFiles.remoteName(url)))
        try await ToocServer.user(account).collection("stickers").document(id)
            .setData(["url": url, "createdAt": Timestamp(date: .now)])
    }

    /// Someone else's sticker, kept among yours.
    func saveSticker(_ url: String) {
        guard let account, !stickers.contains(where: { $0.url == url }) else { return }
        Task {
            try? await ToocServer.user(account).collection("stickers").document(UUID().uuidString)
                .setData(["url": url, "createdAt": Timestamp(date: .now)])
        }
    }

    func deleteSticker(_ id: String) {
        guard let account else { return }
        stickers.removeAll { $0.id == id }
        Task { try? await ToocServer.user(account).collection("stickers").document(id).delete() }
    }

    /// Tells the others you're typing (at most every few seconds).
    func typed(in roomID: String) {
        guard let account, Date.now.timeIntervalSince(lastTypingSent) > 3, room(roomID)?.isMynote == false else { return }
        lastTypingSent = .now
        Task { try? await ToocServer.room(roomID).updateData([FieldPath(["typing", account]): Timestamp(date: .now)]) }
    }

    private func sendReadReceipts(_ roomID: String) {
        guard let account else { return }
        let unread = (serverMessages[roomID] ?? []).filter { $0.senderID != account && !(readBy[$0.id] ?? []).contains(account) }
        guard !unread.isEmpty else { return }
        for message in unread { readBy[message.id, default: []].append(account) }
        Task {
            let batch = ToocServer.db.batch()
            for message in unread.suffix(200) {
                batch.updateData(["readBy": FieldValue.arrayUnion([account])],
                                 forDocument: ToocServer.messages(roomID).document(message.id.uuidString))
            }
            try? await batch.commit()
        }
    }

    private func change(_ id: UUID, in roomID: String, _ fields: [AnyHashable: Any]) {
        Task { try? await ToocServer.messages(roomID).document(id.uuidString).updateData(fields) }
    }

    func edit(_ id: UUID, in roomID: String, text: String) {
        change(id, in: roomID, ["kind": ToocServer.encode(.text(text)), "edited": true])
    }

    /// Removes a message from this device only (or takes back one waiting for its time).
    func deleteMessage(_ id: UUID, in roomID: String) {
        if local.scheduled[roomID]?.contains(where: { $0.id == id }) == true {
            local.scheduled[roomID]?.removeAll { $0.id == id }
        } else {
            var prefs = local.rooms[roomID] ?? .init()
            prefs.deleted.insert(id)
            local.rooms[roomID] = prefs
        }
        save()
        rebuildRooms()
    }

    /// Takes your message back for everyone.
    func unsend(_ id: UUID, in roomID: String) {
        change(id, in: roomID, ["kind": ToocServer.encode(.unsent), "reactions": [String: String]()])
    }

    func react(_ emoji: String?, to id: UUID, in roomID: String) {
        change(id, in: roomID, [FieldPath(["reactions", me.id]): ToocServer.orDelete(emoji)])
    }

    func vote(_ option: Int, in id: UUID, roomID: String) {
        guard let message = room(roomID)?.messages.first(where: { $0.id == id }),
              case .poll(let poll) = message.kind, !poll.closed else { return }
        var mine = poll.votes[me.id] ?? []
        if mine.contains(option) { mine.removeAll { $0 == option } } else { mine = poll.multiple ? mine + [option] : [option] }
        change(id, in: roomID, [FieldPath(["votes", me.id]): ToocServer.orDelete(mine.isEmpty ? nil : mine)])
    }

    func answer(_ date: Int, _ answer: Int, in id: UUID, roomID: String) {
        guard let message = room(roomID)?.messages.first(where: { $0.id == id }),
              case .datePoll(let poll) = message.kind, !poll.closed else { return }
        var mine = poll.answers[me.id] ?? Array(repeating: -1, count: poll.dates.count)
        mine[date] = mine[date] == answer ? -1 : answer
        change(id, in: roomID, [FieldPath(["answers", me.id]): mine])
    }

    func reveal(_ id: UUID, roomID: String) {
        local.revealed.insert(id)
        save()
        if var list = serverMessages[roomID], let index = list.firstIndex(where: { $0.id == id }),
           case .amida(var amida) = list[index].kind {
            amida.revealed = true
            list[index].kind = .amida(amida)
            serverMessages[roomID] = list
            rebuildRooms()
        }
    }

    func sendNow(_ id: UUID, in roomID: String) {
        guard var message = local.scheduled[roomID]?.first(where: { $0.id == id }) else { return }
        local.scheduled[roomID]?.removeAll { $0.id == id }
        save()
        message.scheduledAt = nil
        message.date = .now
        message.sending = true
        pending[roomID, default: []].append(message)
        rebuildRooms()
        upload(message, in: roomID)
    }

    /// Sends the scheduled messages whose time has come.
    func deliverDue() {
        for (roomID, list) in local.scheduled {
            for message in list where (message.scheduledAt ?? .distantFuture) <= .now {
                sendNow(message.id, in: roomID)
            }
        }
    }

    static let emojis = ["👍", "❤️", "😂", "😮", "😢", "🙏", "🎉", "🔥"]
}
