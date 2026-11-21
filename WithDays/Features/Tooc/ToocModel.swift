import Foundation
import Security
import SwiftUI

// tooc: a personal talk app. For now only its frame: the lists, profiles and rooms are filled with sample data,
// and nothing is sent anywhere.

struct ToocUser: Identifiable, Hashable {
    /// The toocID.
    let id: String
    var name: String
    var bio: String
    /// The hue of the generated icon (there are no photos yet).
    var hue: Double
    /// Whether a profile background is set (drawn from the icon's colours).
    var hasBackground = false
    var addedAt: Date = .distantPast
    var profileUpdatedAt: Date = .distantPast
    var isFriend = true
    var isFavorite = false

    var color: Color { Color(hue: hue, saturation: 0.55, brightness: 0.85) }
    var initial: String { String(name.prefix(1)) }
}

struct ToocMessage: Identifiable, Hashable {
    enum Kind: Hashable { case text(String), photo }

    let id = UUID()
    let senderID: String
    let kind: Kind
    let date: Date
    /// Still on its way.
    var sending = false
    /// How many have read it (in a group), or whether the other person has (1 / 0).
    var readCount = 0
    var replyTo: UUID?

    var preview: String {
        switch kind {
        case .text(let text): text
        case .photo: "写真"
        }
    }
}

struct ToocRoom: Identifiable, Hashable {
    let id: String
    /// A group's name; a one-to-one room is named after the other person.
    var title: String?
    var memberIDs: [String]
    var isGroup = false
    /// The room only for yourself (like a memo). It can't be deleted or made a favourite.
    var isMynote = false
    var messages: [ToocMessage] = []
    var unread = 0
    var pinned = false
    var muted = false
    var hidden = false
    var draft = ""
    var scheduled = false

    var last: ToocMessage? { messages.last }
}

enum ToocTalkSort: String, CaseIterable, Identifiable {
    case added, conversation, profile
    var id: String { rawValue }

    var label: String {
        switch self {
        case .added: "友だち追加が新しい順"
        case .conversation: "会話が新しい順"
        case .profile: "Myprofileの更新が新しい順"
        }
    }
}

/// Everything tooc shows, kept in memory: sample friends and rooms around the signed-in account.
@MainActor
@Observable
final class ToocStore {
    private(set) var account: String?
    var me: ToocUser
    var users: [String: ToocUser] = [:]
    var rooms: [ToocRoom] = []

    var talkSort: ToocTalkSort = .conversation
    var favoritesFirst = false
    var unreadFirst = false
    var friendSort: ToocTalkSort = .added

    init() {
        let account = ToocKeychain.savedID()
        self.account = account
        me = ToocUser(id: account ?? "me", name: account ?? "じぶん", bio: "", hue: 0.58, hasBackground: true)
        if account != nil { loadSamples() }
    }

    // MARK: Account (kept on this device until there is a server)

    var signedIn: Bool { account != nil }

    func createAccount(id: String, password: String) throws {
        try ToocKeychain.save(id: id, password: password)
        signIn(id)
    }

    func logIn(id: String, password: String) -> Bool {
        guard ToocKeychain.savedID() == id, ToocKeychain.password(for: id) == password else { return false }
        signIn(id)
        return true
    }

    var hasDeviceAccount: Bool { ToocKeychain.savedID() != nil }

    private func signIn(_ id: String) {
        account = id
        me = ToocUser(id: id, name: id, bio: "tooc はじめました。\nよろしくお願いします！", hue: 0.58, hasBackground: true,
                      profileUpdatedAt: .now)
        loadSamples()
    }

    // MARK: Lookups

    func user(_ id: String) -> ToocUser? { id == me.id ? me : users[id] }

    var unreadTotal: Int { rooms.filter { !$0.hidden && !$0.muted }.reduce(0) { $0 + $1.unread } }

    func name(of room: ToocRoom) -> String {
        if room.isMynote { return "Mynote" }
        if let title = room.title { return title }
        return room.memberIDs.compactMap { user($0) }.first?.name ?? "トーク"
    }

    /// The icon's owner: the other person, or yourself in Mynote. Groups have their own icon.
    func iconUser(of room: ToocRoom) -> ToocUser {
        if room.isMynote { return me }
        if room.isGroup {
            return ToocUser(id: room.id, name: room.title ?? "G", bio: "", hue: Double(abs(room.id.hashValue % 100)) / 100)
        }
        return room.memberIDs.compactMap { user($0) }.first ?? me
    }

    func isFavorite(_ room: ToocRoom) -> Bool {
        guard !room.isGroup, !room.isMynote else { return false }
        return room.memberIDs.contains { users[$0]?.isFavorite == true }
    }

    // MARK: Lists

    var visibleRooms: [ToocRoom] {
        rooms.filter { !$0.hidden }.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            if favoritesFirst, isFavorite(a) != isFavorite(b) { return isFavorite(a) }
            if unreadFirst, (a.unread > 0) != (b.unread > 0) { return a.unread > 0 }
            return key(a, talkSort) > key(b, talkSort)
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
        users.values.filter(\.isFriend).sorted { a, b in
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

    // MARK: Changes

    func update(_ id: String, _ change: (inout ToocRoom) -> Void) {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else { return }
        change(&rooms[index])
    }

    func markRead(_ id: String) { update(id) { $0.unread = 0 } }
    func markAllRead() { for index in rooms.indices { rooms[index].unread = 0 } }
    func delete(_ id: String) { rooms.removeAll { $0.id == id && !$0.isMynote } }

    func toggleFavorite(_ id: String) { users[id]?.isFavorite.toggle() }
    func hideFriend(_ id: String) { users[id]?.isFriend = false }
    func block(_ id: String) {
        users[id]?.isFriend = false
        rooms.removeAll { !$0.isGroup && $0.memberIDs == [id] }
    }

    /// The one-to-one room with a friend, made (empty) if there isn't one yet.
    func room(with userID: String) -> ToocRoom {
        if let room = rooms.first(where: { !$0.isGroup && !$0.isMynote && $0.memberIDs == [userID] }) {
            if room.hidden { update(room.id) { $0.hidden = false } }
            return room
        }
        let room = ToocRoom(id: "dm-\(userID)", memberIDs: [userID])
        rooms.append(room)
        return room
    }

    // MARK: Samples

    private func loadSamples() {
        let now = Date.now
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let samples = [
            ToocUser(id: "haruka_m", name: "春香", bio: "カフェ巡りが好き☕️\n週末はだいたい写真を撮りに出かけています。",
                     hue: 0.95, hasBackground: true, addedAt: ago(60 * 24 * 3), profileUpdatedAt: ago(30), isFavorite: true),
            ToocUser(id: "kenta.o", name: "大野 健太", bio: "サッカー部 ⚽️", hue: 0.33,
                     addedAt: ago(60 * 24 * 40), profileUpdatedAt: ago(60 * 24 * 2)),
            ToocUser(id: "yui_s", name: "Yui", bio: "", hue: 0.12, addedAt: ago(60 * 2), profileUpdatedAt: ago(60 * 2)),
            ToocUser(id: "taku", name: "たくみ", bio: "とても長いひとことを書いておくと、2行を超えた分は省略されて…で切られることを確かめるための文章です。",
                     hue: 0.68, hasBackground: true, addedAt: ago(60 * 24 * 400), profileUpdatedAt: ago(60 * 24 * 300)),
            ToocUser(id: "mom", name: "母", bio: "", hue: 0.05, addedAt: ago(60 * 24 * 800), profileUpdatedAt: ago(60 * 24 * 700),
                     isFavorite: true),
        ]
        users = Dictionary(uniqueKeysWithValues: samples.map { ($0.id, $0) })
        let me = self.me.id
        rooms = [
            ToocRoom(id: "mynote", memberIDs: [me], isMynote: true, messages: [
                ToocMessage(senderID: me, kind: .text("買うもの\n・牛乳\n・電池"), date: ago(60 * 26)),
            ]),
            ToocRoom(id: "dm-haruka_m", memberIDs: ["haruka_m"], messages: [
                ToocMessage(senderID: "haruka_m", kind: .text("明日のお昼どうする？"), date: ago(12)),
                ToocMessage(senderID: "haruka_m", kind: .text("駅前の新しいお店行ってみたい！"), date: ago(12)),
                ToocMessage(senderID: "haruka_m", kind: .photo, date: ago(11)),
            ], unread: 3, pinned: true),
            ToocRoom(id: "g-club", title: "サッカー部 2年", memberIDs: ["kenta.o", "taku", "yui_s"], isGroup: true, messages: [
                ToocMessage(senderID: "taku", kind: .text("来週の練習、グラウンド使えないらしい"), date: ago(60 * 3), readCount: 2),
                ToocMessage(senderID: me, kind: .text("了解！体育館は？"), date: ago(60 * 2.5), readCount: 3),
                ToocMessage(senderID: "kenta.o", kind: .text("体育館は空いてる！\n先生に確認しておくね。\nあと持ち物は\n・ボール\n・ビブス"),
                            date: ago(60 * 2), readCount: 1),
            ], unread: 12, draft: "じゃあ"),
            ToocRoom(id: "dm-kenta.o", memberIDs: ["kenta.o"], messages: [
                ToocMessage(senderID: "kenta.o", kind: .text("ノート見せてくれてありがとう"), date: ago(60 * 24 + 30)),
                ToocMessage(senderID: me, kind: .text("いいよー"), date: ago(60 * 24 + 20), readCount: 1),
                ToocMessage(senderID: me, kind: .photo, date: ago(1), sending: true),
            ]),
            ToocRoom(id: "dm-mom", memberIDs: ["mom"], messages: [
                ToocMessage(senderID: "mom", kind: .text("今日は何時に帰る？"), date: ago(60 * 24 * 5)),
                ToocMessage(senderID: me, kind: .text("7時くらい"), date: ago(60 * 24 * 5 - 3), readCount: 1),
            ], muted: true, scheduled: true),
            ToocRoom(id: "dm-taku", memberIDs: ["taku"], messages: [
                ToocMessage(senderID: "taku", kind: .text("久しぶり！"), date: ago(60 * 24 * 600)),
            ]),
            ToocRoom(id: "dm-yui_s", memberIDs: ["yui_s"]),
        ]
    }
}

/// tooc's account, kept in the device's keychain until accounts live on a server.
enum ToocKeychain {
    private static let service = "com.ffuime.withdays.tooc"
    private static let idKey = "toocAccountID"

    static func savedID() -> String? { UserDefaults.standard.string(forKey: idKey) }

    static func save(id: String, password: String) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
        ]
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecAttrAccount as String] = id
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                          userInfo: [NSLocalizedDescriptionKey: "アカウントを保存できませんでした（\(status)）"])
        }
        UserDefaults.standard.set(id, forKey: idKey)
    }

    static func password(for id: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: Dates

enum ToocTime {
    /// hh:mm today, 昨日, M/d this year, yyyy/MM/dd before.
    static func listLabel(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return clock(date) }
        if calendar.isDateInYesterday(date) { return "昨日" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = calendar.isDate(date, equalTo: now, toGranularity: .year) ? "M/d" : "yyyy/MM/dd"
        return formatter.string(from: date)
    }

    static func clock(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

// MARK: Not yet built

private struct ToocUnimplementedKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Shows 「未実装です」 for a part of tooc that isn't built yet.
    var toocUnimplemented: () -> Void {
        get { self[ToocUnimplementedKey.self] }
        set { self[ToocUnimplementedKey.self] = newValue }
    }
}

/// Hosts the 「未実装です」 alert for everything inside (each sheet hosts its own, since alerts don't cross sheets).
private struct ToocUnimplementedHost: ViewModifier {
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .environment(\.toocUnimplemented, { shown = true })
            .alert("未実装です", isPresented: $shown) {
                Button("OK", role: .cancel) {}
            }
    }
}

extension View {
    func toocUnimplementedHost() -> some View { modifier(ToocUnimplementedHost()) }
}
