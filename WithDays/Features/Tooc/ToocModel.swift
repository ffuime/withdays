import Foundation
import Security
import SwiftUI
import UIKit

// tooc: a personal talk app. There is no server yet, so everything lives on this device: what you send stays here,
// and the sample friends read it and answer after a moment.

struct ToocUser: Identifiable, Hashable, Codable {
    /// The toocID.
    let id: String
    var name: String
    var bio: String
    /// The hue of the generated icon, when there is no photo.
    var hue: Double
    /// A photo chosen for the icon (a file in tooc's photo folder).
    var iconFile: String?
    /// Whether a profile background is set (drawn from the icon).
    var hasBackground = false
    var addedAt: Date = .distantPast
    var profileUpdatedAt: Date = .distantPast
    var isFriend = true
    var isFavorite = false
    var isHidden = false
    var isBlocked = false

    var color: Color { Color(hue: hue, saturation: 0.55, brightness: 0.85) }
    var initial: String { String(name.prefix(1)) }

    /// Stands for Mynote's own icon, the same for every account.
    static let mynoteID = "__mynote"
    var isMynote: Bool { id == Self.mynoteID }
    static let mynote = ToocUser(id: mynoteID, name: "Mynote", bio: "", hue: 0.57)

    /// A steady hue from any text (the same ID always gets the same colour).
    static func hue(for text: String) -> Double {
        Double(text.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 997 }) / 997
    }
}

struct ToocMessage: Identifiable, Hashable, Codable {
    enum Kind: Hashable, Codable {
        case text(String)
        /// A photo file in tooc's photo folder (nil: a sample with no picture).
        case photo(String?)
    }

    var id = UUID()
    let senderID: String
    var kind: Kind
    var date: Date
    /// Still on its way.
    var sending = false
    /// How many have read it (in a group), or whether the other person has (1 / 0).
    var readCount = 0
    var replyTo: UUID?
    /// Sent as a mute message: it reaches them without a notification.
    var silent = false
    /// Waiting to be sent at this time.
    var scheduledAt: Date?

    var preview: String {
        switch kind {
        case .text(let text): text
        case .photo: "写真"
        }
    }

    var isPhoto: Bool {
        if case .photo = kind { return true }
        return false
    }
}

struct ToocRoom: Identifiable, Hashable, Codable {
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

    /// Sent (or arrived) messages, oldest first; scheduled ones wait apart.
    var sent: [ToocMessage] { messages.filter { $0.scheduledAt == nil } }
    var waiting: [ToocMessage] {
        messages.filter { $0.scheduledAt != nil }.sorted { ($0.scheduledAt ?? .now) < ($1.scheduledAt ?? .now) }
    }
    var last: ToocMessage? { messages.last { $0.scheduledAt == nil } }
    var scheduled: Bool { messages.contains { $0.scheduledAt != nil } }
}

enum ToocTalkSort: String, CaseIterable, Identifiable, Codable {
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

/// Something that happened: shown in お知らせ, and as a banner when notifications are on.
struct ToocNotice: Identifiable, Hashable, Codable {
    var id = UUID()
    var date = Date.now
    let title: String
    let body: String
    var userID: String?
    var roomID: String?
    var seen = false
}

struct ToocSettings: Hashable, Codable {
    var notifications = true
    var showContent = true
    var textSize: ToocTextSize = .standard
    var background: ToocRoomBackground = .none
    /// Return sends instead of starting a new line.
    var returnSends = false
}

enum ToocTextSize: String, CaseIterable, Identifiable, Codable {
    case small, standard, large, larger
    var id: String { rawValue }
    var label: String {
        switch self {
        case .small: "小"
        case .standard: "標準"
        case .large: "大"
        case .larger: "特大"
        }
    }
    var points: CGFloat {
        switch self {
        case .small: 15
        case .standard: 17
        case .large: 20
        case .larger: 23
        }
    }
}

enum ToocRoomBackground: String, CaseIterable, Identifiable, Codable {
    case none, sky, sakura, mint, sand, night
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "なし"
        case .sky: "空"
        case .sakura: "さくら"
        case .mint: "ミント"
        case .sand: "すな"
        case .night: "夜"
        }
    }
    var color: Color? {
        switch self {
        case .none: nil
        case .sky: Color(hue: 0.57, saturation: 0.18, brightness: 0.96)
        case .sakura: Color(hue: 0.95, saturation: 0.12, brightness: 0.98)
        case .mint: Color(hue: 0.42, saturation: 0.14, brightness: 0.95)
        case .sand: Color(hue: 0.1, saturation: 0.14, brightness: 0.96)
        case .night: Color(hue: 0.64, saturation: 0.45, brightness: 0.22)
        }
    }
}

/// Everything tooc keeps for one account.
private struct ToocData: Codable {
    var me: ToocUser
    var users: [String: ToocUser]
    var rooms: [ToocRoom]
    var notices: [ToocNotice]
    var settings: ToocSettings
    var talkSort: ToocTalkSort
    var favoritesFirst: Bool
    var unreadFirst: Bool
    var friendSort: ToocTalkSort
}

/// Everything tooc shows, saved on this device per account.
@MainActor
@Observable
final class ToocStore {
    private(set) var account: String? = nil
    var me: ToocUser { didSet { save() } }
    var users: [String: ToocUser] = [:] { didSet { save() } }
    var rooms: [ToocRoom] = [] { didSet { save() } }
    var notices: [ToocNotice] = [] { didSet { save() } }
    var settings = ToocSettings() { didSet { save() } }

    var talkSort: ToocTalkSort = .conversation { didSet { save() } }
    var favoritesFirst = false { didSet { save() } }
    var unreadFirst = false { didSet { save() } }
    var friendSort: ToocTalkSort = .added { didSet { save() } }

    /// The room on screen: what arrives there is read at once.
    var openRoomID: String? = nil
    /// The newest notice to show as a banner.
    var banner: ToocNotice? = nil

    @ObservationIgnored private var loading = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let account = ToocKeychain.savedID().flatMap { ToocKeychain.signedIn ? $0 : nil }
        me = ToocUser(id: account ?? "me", name: account ?? "じぶん", bio: "", hue: 0.58)
        if let account { open(account) }
    }

    // MARK: Account (kept on this device until there is a server)

    var signedIn: Bool { account != nil }
    var hasDeviceAccount: Bool { ToocKeychain.savedID() != nil }

    func createAccount(id: String, password: String) throws {
        try ToocKeychain.save(id: id, password: password)
        ToocStorage.remove(id)
        open(id)
    }

    func logIn(id: String, password: String) -> Bool {
        guard ToocKeychain.savedID() == id, ToocKeychain.password(for: id) == password else { return false }
        open(id)
        return true
    }

    func logOut() {
        flush()
        ToocKeychain.signedIn = false
        account = nil
        openRoomID = nil
        banner = nil
    }

    func changePassword(current: String, new: String) throws {
        guard let account, ToocKeychain.password(for: account) == current else {
            throw ToocError("いまのパスワードが違います。")
        }
        try ToocKeychain.save(id: account, password: new)
    }

    func deleteAccount() {
        guard let account else { return }
        saveTask?.cancel()
        ToocKeychain.delete()
        ToocStorage.remove(account)
        self.account = nil
        openRoomID = nil
        banner = nil
    }

    private func open(_ id: String) {
        loading = true
        defer { loading = false }
        account = id
        ToocKeychain.signedIn = true
        if let data = ToocStorage.load(id) {
            me = data.me
            users = data.users
            rooms = data.rooms
            notices = data.notices
            settings = data.settings
            talkSort = data.talkSort
            favoritesFirst = data.favoritesFirst
            unreadFirst = data.unreadFirst
            friendSort = data.friendSort
        } else {
            me = ToocUser(id: id, name: id, bio: "tooc はじめました。\nよろしくお願いします！", hue: 0.58, hasBackground: true,
                          profileUpdatedAt: .now)
            loadSamples()
            loading = false
            flush()
        }
        finishSending()
    }

    // MARK: Saving

    private func save() {
        guard !loading, account != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    func flush() {
        guard let account else { return }
        ToocStorage.save(account, ToocData(
            me: me, users: users, rooms: rooms, notices: notices, settings: settings, talkSort: talkSort,
            favoritesFirst: favoritesFirst, unreadFirst: unreadFirst, friendSort: friendSort
        ))
    }

    // MARK: Lookups

    func user(_ id: String) -> ToocUser? {
        if id == me.id { return me }
        if id == ToocUser.mynoteID { return .mynote }
        return users[id]
    }

    var unreadTotal: Int { rooms.filter { !$0.hidden && !$0.muted }.reduce(0) { $0 + $1.unread } }
    var unseenNotices: Int { notices.filter { !$0.seen }.count }

    func room(_ id: String) -> ToocRoom? { rooms.first { $0.id == id } }

    func name(of room: ToocRoom) -> String {
        if room.isMynote { return "Mynote" }
        if let title = room.title { return title }
        return room.memberIDs.compactMap { user($0) }.first?.name ?? "トーク"
    }

    /// The icon's owner: the other person, Mynote's own icon, or a group's generated one.
    func iconUser(of room: ToocRoom) -> ToocUser {
        if room.isMynote { return .mynote }
        if room.isGroup {
            return ToocUser(id: room.id, name: room.title ?? "G", bio: "", hue: ToocUser.hue(for: room.id))
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

    var hiddenFriends: [ToocUser] { users.values.filter { $0.isFriend && $0.isHidden && !$0.isBlocked }.sorted { $0.name < $1.name } }
    var blockedUsers: [ToocUser] { users.values.filter(\.isBlocked).sorted { $0.name < $1.name } }
    var hiddenRooms: [ToocRoom] { rooms.filter(\.hidden) }

    // MARK: Changes

    func update(_ id: String, _ change: (inout ToocRoom) -> Void) {
        guard let index = rooms.firstIndex(where: { $0.id == id }) else { return }
        change(&rooms[index])
    }

    func updateUser(_ id: String, _ change: (inout ToocUser) -> Void) {
        guard var user = users[id] else { return }
        change(&user)
        users[id] = user
    }

    func markRead(_ id: String) { update(id) { $0.unread = 0 } }
    func markAllRead() { for index in rooms.indices where rooms[index].unread > 0 { rooms[index].unread = 0 } }

    func delete(_ id: String) {
        guard let room = room(id), !room.isMynote else { return }
        ToocPhotos.remove(room.messages)
        rooms.removeAll { $0.id == id }
    }

    func clearHistory(_ id: String) {
        guard let room = room(id) else { return }
        ToocPhotos.remove(room.messages)
        update(id) {
            $0.messages.removeAll()
            $0.unread = 0
        }
    }

    func toggleFavorite(_ id: String) { updateUser(id) { $0.isFavorite.toggle() } }
    func hideFriend(_ id: String) { updateUser(id) { $0.isHidden = true } }
    func showFriend(_ id: String) { updateUser(id) { $0.isHidden = false } }

    func block(_ id: String) {
        updateUser(id) {
            $0.isBlocked = true
            $0.isFavorite = false
        }
        for room in rooms where !room.isGroup && room.memberIDs == [id] { update(room.id) { $0.hidden = true } }
    }

    func unblock(_ id: String) { updateUser(id) { $0.isBlocked = false } }

    /// Someone found by toocID or QR. With no server to ask, a provisional person is made from the ID.
    func lookUp(_ id: String) -> ToocUser {
        if let user = users[id] { return user }
        return ToocUser(id: id, name: id, bio: "", hue: ToocUser.hue(for: id), isFriend: false)
    }

    func addFriend(_ found: ToocUser) {
        var user = users[found.id] ?? found
        user.isFriend = true
        user.isHidden = false
        user.isBlocked = false
        user.addedAt = .now
        users[user.id] = user
        notify(ToocNotice(title: "友だち追加", body: "\(user.name)を友だちに追加しました", userID: user.id))
    }

    /// The one-to-one room with a friend, made (empty) if there isn't one yet.
    @discardableResult
    func room(with userID: String) -> ToocRoom {
        if let room = rooms.first(where: { !$0.isGroup && !$0.isMynote && $0.memberIDs == [userID] }) {
            if room.hidden { update(room.id) { $0.hidden = false } }
            return room
        }
        let room = ToocRoom(id: "dm-\(userID)", memberIDs: [userID])
        rooms.append(room)
        return room
    }

    func makeGroup(name: String, members: [String]) -> ToocRoom {
        let room = ToocRoom(id: "g-\(UUID().uuidString.prefix(8))", title: name, memberIDs: members, isGroup: true)
        rooms.append(room)
        return room
    }

    func leave(_ id: String) {
        guard let room = room(id), room.isGroup else { return }
        delete(room.id)
    }

    func editProfile(name: String, bio: String, hue: Double, iconFile: String?, hasBackground: Bool) {
        if me.iconFile != iconFile, let old = me.iconFile { ToocPhotos.delete(old) }
        me.name = name
        me.bio = bio
        me.hue = hue
        me.iconFile = iconFile
        me.hasBackground = hasBackground
        me.profileUpdatedAt = .now
    }

    // MARK: Sending (kept here; the sample friends read and answer)

    func send(_ kind: ToocMessage.Kind, in roomID: String, replyTo: UUID? = nil, silent: Bool = false, at time: Date? = nil) {
        var message = ToocMessage(senderID: me.id, kind: kind, date: time ?? .now, sending: time == nil, replyTo: replyTo,
                                  silent: silent, scheduledAt: time)
        if let time, time <= .now {
            message.scheduledAt = nil
            message.sending = true
        }
        update(roomID) {
            $0.messages.append(message)
            $0.draft = ""
            $0.hidden = false
        }
        if message.scheduledAt == nil { delivered(message.id, in: roomID) }
    }

    func deleteMessage(_ id: UUID, in roomID: String) {
        guard let message = room(roomID)?.messages.first(where: { $0.id == id }) else { return }
        ToocPhotos.remove([message])
        update(roomID) { $0.messages.removeAll { $0.id == id } }
    }

    func sendNow(_ id: UUID, in roomID: String) {
        update(roomID) { room in
            guard let index = room.messages.firstIndex(where: { $0.id == id }) else { return }
            var message = room.messages.remove(at: index)
            message.scheduledAt = nil
            message.date = .now
            message.sending = true
            room.messages.append(message)
        }
        delivered(id, in: roomID)
    }

    /// Sends the scheduled messages whose time has come.
    func deliverDue() {
        let now = Date.now
        for room in rooms {
            for message in room.messages where (message.scheduledAt ?? .distantFuture) <= now {
                let time = message.scheduledAt ?? now
                update(room.id) { room in
                    guard let index = room.messages.firstIndex(where: { $0.id == message.id }) else { return }
                    var sent = room.messages.remove(at: index)
                    sent.scheduledAt = nil
                    sent.date = time
                    sent.sending = true
                    room.messages.append(sent)
                }
                delivered(message.id, in: room.id)
                notify(ToocNotice(title: "予約したメッセージ", body: "\(name(of: room))へ送信しました", roomID: room.id))
            }
        }
    }

    /// After a moment the message is "sent", then read; someone may answer.
    private func delivered(_ id: UUID, in roomID: String) {
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int.random(in: 500...900)))
            self?.setMessage(id, in: roomID) { $0.sending = false }
            guard let room = self?.room(roomID), !room.isMynote else { return }
            let others = room.memberIDs.filter { self?.users[$0]?.isBlocked != true }
            guard !others.isEmpty else { return }
            try? await Task.sleep(for: .seconds(Double.random(in: 1.2...2.5)))
            self?.setMessage(id, in: roomID) { $0.readCount = room.isGroup ? Int.random(in: 1...others.count) : 1 }
            guard Double.random(in: 0...1) < (room.isGroup ? 0.6 : 0.85), let sender = others.randomElement() else { return }
            try? await Task.sleep(for: .seconds(Double.random(in: 1.5...4)))
            self?.receive(from: sender, in: roomID)
        }
    }

    private func setMessage(_ id: UUID, in roomID: String, _ change: (inout ToocMessage) -> Void) {
        update(roomID) { room in
            guard let index = room.messages.firstIndex(where: { $0.id == id }) else { return }
            change(&room.messages[index])
        }
    }

    private static let replies = [
        "了解！", "いいね👍", "ありがとう！", "なるほど", "それな", "あとで確認するね", "おっけー", "たしかに😂",
        "ちょうど同じこと考えてた", "まじか！", "了解です🙆", "また連絡するね", "ほんとに？", "楽しみ！",
    ]

    private func receive(from sender: String, in roomID: String) {
        guard let room = room(roomID) else { return }
        let kind: ToocMessage.Kind = Double.random(in: 0...1) < 0.08 ? .photo(nil) : .text(Self.replies.randomElement()!)
        let message = ToocMessage(senderID: sender, kind: kind, date: .now)
        let viewing = openRoomID == roomID
        update(roomID) {
            $0.messages.append(message)
            $0.hidden = false
            if !viewing { $0.unread += 1 }
        }
        guard !viewing, !room.muted else { return }
        let who = user(sender)?.name ?? ""
        let title = room.isGroup ? "\(name(of: room))・\(who)" : who
        notify(ToocNotice(title: title, body: message.preview, userID: sender, roomID: roomID))
    }

    func notify(_ notice: ToocNotice) {
        notices.insert(notice, at: 0)
        if notices.count > 100 { notices.removeLast(notices.count - 100) }
        if settings.notifications { banner = notice }
    }

    func markNoticesSeen() {
        guard notices.contains(where: { !$0.seen }) else { return }
        for index in notices.indices { notices[index].seen = true }
    }

    /// A sample message left "sending" finishes once tooc opens.
    private func finishSending() {
        for room in rooms {
            for message in room.messages where message.sending {
                Task { [weak self] in
                    try? await Task.sleep(for: .seconds(3))
                    self?.setMessage(message.id, in: room.id) {
                        $0.sending = false
                        $0.readCount = 1
                    }
                }
            }
        }
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
                ToocMessage(senderID: "haruka_m", kind: .photo(nil), date: ago(11)),
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
                ToocMessage(senderID: me, kind: .photo(nil), date: ago(1), sending: true),
            ]),
            ToocRoom(id: "dm-mom", memberIDs: ["mom"], messages: [
                ToocMessage(senderID: "mom", kind: .text("今日は何時に帰る？"), date: ago(60 * 24 * 5)),
                ToocMessage(senderID: me, kind: .text("7時くらい"), date: ago(60 * 24 * 5 - 3), readCount: 1),
                ToocMessage(senderID: me, kind: .text("お誕生日おめでとう🎂"), date: now.addingTimeInterval(60 * 60 * 24 * 2),
                            scheduledAt: now.addingTimeInterval(60 * 60 * 24 * 2)),
            ], muted: true),
            ToocRoom(id: "dm-taku", memberIDs: ["taku"], messages: [
                ToocMessage(senderID: "taku", kind: .text("久しぶり！"), date: ago(60 * 24 * 600)),
            ]),
            ToocRoom(id: "dm-yui_s", memberIDs: ["yui_s"]),
        ]
    }
}

struct ToocError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - On this device

/// Each account's data as a JSON file in Application Support.
private enum ToocStorage {
    static var folder: URL {
        let url = URL.applicationSupportDirectory.appending(path: "tooc", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func file(_ account: String) -> URL { folder.appending(path: "\(account).json") }

    static func load(_ account: String) -> ToocData? {
        guard let data = try? Data(contentsOf: file(account)) else { return nil }
        return try? JSONDecoder().decode(ToocData.self, from: data)
    }

    static func save(_ account: String, _ value: ToocData) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: file(account), options: .atomic)
    }

    static func remove(_ account: String) {
        if let data = load(account) {
            for room in data.rooms { ToocPhotos.remove(room.messages) }
            if let icon = data.me.iconFile { ToocPhotos.delete(icon) }
        }
        try? FileManager.default.removeItem(at: file(account))
    }
}

/// Photos sent in talks and chosen for the icon, as JPEG files.
enum ToocPhotos {
    private static let cache = NSCache<NSString, UIImage>()

    private static var folder: URL {
        let url = URL.applicationSupportDirectory.appending(path: "tooc/photos", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Saves a photo (scaled down to 2048 at most) and returns its file name.
    static func save(_ image: UIImage, side: CGFloat = 2048) -> String? {
        let scale = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: folder.appending(path: name), options: .atomic)
        } catch {
            return nil
        }
        cache.setObject(resized, forKey: name as NSString)
        return name
    }

    static func image(_ name: String) -> UIImage? {
        if let image = cache.object(forKey: name as NSString) { return image }
        guard let image = UIImage(contentsOfFile: folder.appending(path: name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    static func delete(_ name: String) {
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: folder.appending(path: name))
    }

    static func remove(_ messages: [ToocMessage]) {
        for message in messages {
            if case .photo(let name?) = message.kind { delete(name) }
        }
    }
}

/// tooc's account, kept in the device's keychain until accounts live on a server.
enum ToocKeychain {
    private static let service = "com.ffuime.withdays.tooc"
    private static let idKey = "toocAccountID"
    private static let signedInKey = "toocSignedIn"

    static func savedID() -> String? { UserDefaults.standard.string(forKey: idKey) }

    /// Whether the saved account is signed in (logging out keeps the account and its talks).
    static var signedIn: Bool {
        get { UserDefaults.standard.object(forKey: signedInKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: signedInKey) }
    }

    private static var base: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service]
    }

    static func save(id: String, password: String) throws {
        SecItemDelete(base as CFDictionary)
        var item = base
        item[kSecAttrAccount as String] = id
        item[kSecValueData as String] = Data(password.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw ToocError("アカウントを保存できませんでした（\(status)）") }
        UserDefaults.standard.set(id, forKey: idKey)
    }

    static func delete() {
        SecItemDelete(base as CFDictionary)
        UserDefaults.standard.removeObject(forKey: idKey)
        UserDefaults.standard.removeObject(forKey: signedInKey)
    }

    static func password(for id: String) -> String? {
        var query = base
        query[kSecAttrAccount as String] = id
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
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
        return format(date, calendar.isDate(date, equalTo: now, toGranularity: .year) ? "M/d" : "yyyy/MM/dd")
    }

    static func clock(_ date: Date) -> String { format(date, "HH:mm") }

    /// For a scheduled message: 「11/24 09:00」.
    static func scheduled(_ date: Date) -> String {
        Calendar.current.isDateInToday(date) ? "今日 \(clock(date))" : format(date, "M/d HH:mm")
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
