import Foundation
import Security
import SwiftUI
import UIKit

// tooc: a personal talk app. There is no server yet, so everything lives on this device: what you send stays here,
// and the sample friends read it, react, vote and answer after a moment.

struct ToocUser: Identifiable, Hashable, Codable {
    /// The toocID.
    let id: String
    var name: String
    var bio: String
    /// The hue of the generated icon, when there is no photo.
    var hue: Double
    /// A photo chosen for the icon (a file in tooc's photo folder, already cut square).
    var iconFile: String?
    /// A photo chosen for the profile background.
    var backgroundFile: String?
    /// Whether a profile background is drawn from the icon (when there's no background photo).
    var hasBackground = false
    var birthday: Date?
    /// The name you gave this friend, shown instead of theirs (only on this device).
    var nickname: String?
    var addedAt: Date = .distantPast
    var profileUpdatedAt: Date = .distantPast
    var isFriend = true
    var isFavorite = false
    var isHidden = false
    var isBlocked = false

    var displayName: String { nickname ?? name }
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

// MARK: Messages

struct ToocPoll: Hashable, Codable {
    var question: String
    var options: [String]
    var multiple: Bool
    /// Who chose which options.
    var votes: [String: [Int]] = [:]
    /// After this, nobody can vote or change their vote.
    var deadline: Date?

    var closed: Bool { deadline.map { $0 <= .now } ?? false }

    func count(_ option: Int) -> Int { votes.values.filter { $0.contains(option) }.count }
}

/// 日程調整: candidate dates, each answered ○ (2), △ (1) or × (0).
struct ToocDatePoll: Hashable, Codable {
    var title: String
    var dates: [Date]
    var answers: [String: [Int]] = [:]
    var deadline: Date?

    var closed: Bool { deadline.map { $0 <= .now } ?? false }

    func count(_ date: Int, _ answer: Int) -> Int {
        answers.values.filter { date < $0.count && $0[date] == answer }.count
    }
}

/// あみだくじ: entrants at the top, prizes at the bottom, rungs in between.
struct ToocAmida: Hashable, Codable {
    struct Rung: Hashable, Codable {
        let level: Int
        /// Joins this line and the next.
        let column: Int
    }

    var title: String
    var entrants: [String]
    var prizes: [String]
    var rungs: [Rung]
    var revealed = false
    var deadline: Date?

    var closed: Bool { deadline.map { $0 <= .now } ?? false }

    static let levels = 9

    init(title: String, entrants: [String], prizes: [String], deadline: Date? = nil) {
        self.title = title
        self.entrants = entrants
        self.prizes = prizes
        self.deadline = deadline
        var rungs: [Rung] = []
        for level in 0..<Self.levels {
            var column = 0
            while column < entrants.count - 1 {
                if Bool.random() {
                    rungs.append(Rung(level: level, column: column))
                    column += 2
                } else {
                    column += 1
                }
            }
        }
        // At least one rung per pair of lines, so nobody walks straight down.
        for column in 0..<max(0, entrants.count - 1) where !rungs.contains(where: { $0.column == column }) {
            let level = Int.random(in: 0..<Self.levels)
            if !rungs.contains(where: { $0.level == level && abs($0.column - column) <= 1 }) {
                rungs.append(Rung(level: level, column: column))
            }
        }
        self.rungs = rungs
    }

    /// The columns an entrant passes through, one per level (plus the start).
    func walk(from start: Int) -> [Int] {
        var column = start
        var path = [column]
        for level in 0..<Self.levels {
            if rungs.contains(Rung(level: level, column: column)) {
                column += 1
            } else if rungs.contains(Rung(level: level, column: column - 1)) {
                column -= 1
            }
            path.append(column)
        }
        return path
    }

    func result(for entrant: Int) -> Int { walk(from: entrant).last ?? entrant }
}

struct ToocMessage: Identifiable, Hashable, Codable {
    enum Kind: Hashable, Codable {
        case text(String)
        /// A photo file in tooc's photo folder.
        case photo(String?)
        /// A photo from the web (the sample friends' photos), saved once it arrives.
        case remotePhoto(String)
        case file(name: String, file: String, size: Int)
        case location(latitude: Double, longitude: Double, title: String)
        case poll(ToocPoll)
        case datePoll(ToocDatePoll)
        case amida(ToocAmida)
        /// What's left after unsending.
        case unsent
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
    /// Who reacted with what.
    var reactions: [String: String] = [:]
    var edited = false

    var preview: String {
        switch kind {
        case .text(let text): text
        case .photo, .remotePhoto: "写真"
        case .file(let name, _, _): "ファイル：\(name)"
        case .location(_, _, let title): "位置情報：\(title)"
        case .poll(let poll): "投票：\(poll.question)"
        case .datePoll(let poll): "日程調整：\(poll.title)"
        case .amida(let amida): "あみだくじ：\(amida.title)"
        case .unsent: "送信が取り消されました"
        }
    }

    var symbol: String? {
        switch kind {
        case .photo, .remotePhoto: "photo.fill"
        case .file: "doc.fill"
        case .location: "mappin.circle.fill"
        case .poll: "chart.bar.fill"
        case .datePoll: "calendar"
        case .amida: "line.3.horizontal"
        case .text, .unsent: nil
        }
    }

    var isText: Bool {
        if case .text = kind { return true }
        return false
    }

    var isUnsent: Bool {
        if case .unsent = kind { return true }
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

enum ToocTalkFilter: String, CaseIterable, Identifiable {
    case all, friends, groups
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: "すべて"
        case .friends: "友だち"
        case .groups: "グループ"
        }
    }
}

struct ToocScheduledEntry: Identifiable {
    let room: ToocRoom
    let message: ToocMessage
    var id: UUID { message.id }
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
    var theme: ToocTheme = .standard
    /// Return sends instead of starting a new line.
    var returnSends = false
    /// The five reactions at the top of a message's long-press menu.
    var favoriteReactions = ["👍", "❤️", "😂", "😮", "🙏"]

    init() {}

    /// Settings saved by an older version keep what they have; anything new takes its default.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = ToocSettings()
        notifications = try container.decodeIfPresent(Bool.self, forKey: .notifications) ?? defaults.notifications
        showContent = try container.decodeIfPresent(Bool.self, forKey: .showContent) ?? defaults.showContent
        textSize = try container.decodeIfPresent(ToocTextSize.self, forKey: .textSize) ?? defaults.textSize
        theme = try container.decodeIfPresent(ToocTheme.self, forKey: .theme) ?? defaults.theme
        returnSends = try container.decodeIfPresent(Bool.self, forKey: .returnSends) ?? defaults.returnSends
        favoriteReactions = try container.decodeIfPresent([String].self, forKey: .favoriteReactions) ?? defaults.favoriteReactions
    }
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
    /// Who is typing in which room (room ID → user ID).
    var typing: [String: String] = [:]

    @ObservationIgnored private var loading = false
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let account = ToocKeychain.savedID().flatMap { ToocKeychain.signedIn ? $0 : nil }
        me = ToocUser(id: account ?? "me", name: account ?? "じぶん", bio: "", hue: 0.58)
        if let account { open(account) }
    }

    var theme: ToocTheme { settings.theme }

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
        fetchSamplePhotos(for: Array(users.keys))
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

    /// Every message waiting to be sent, soonest first.
    var scheduledMessages: [ToocScheduledEntry] {
        rooms.flatMap { room in room.waiting.map { ToocScheduledEntry(room: room, message: $0) } }
            .sorted { ($0.message.scheduledAt ?? .now) < ($1.message.scheduledAt ?? .now) }
    }

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
        ToocFiles.remove(room.messages)
        rooms.removeAll { $0.id == id }
    }

    func clearHistory(_ id: String) {
        guard let room = room(id) else { return }
        ToocFiles.remove(room.messages)
        update(id) {
            $0.messages.removeAll()
            $0.unread = 0
        }
    }

    func toggleFavorite(_ id: String) { updateUser(id) { $0.isFavorite.toggle() } }
    func hideFriend(_ id: String) { updateUser(id) { $0.isHidden = true } }
    func showFriend(_ id: String) { updateUser(id) { $0.isHidden = false } }

    func rename(_ id: String, to nickname: String?) {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        updateUser(id) { $0.nickname = (trimmed?.isEmpty ?? true) ? nil : trimmed }
    }

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
        notify(ToocNotice(title: "友だち追加", body: "\(user.displayName)を友だちに追加しました", userID: user.id))
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

    func editProfile(name: String, bio: String, hue: Double, iconFile: String?, backgroundFile: String?,
                     hasBackground: Bool, birthday: Date?) {
        if me.iconFile != iconFile, let old = me.iconFile { ToocFiles.delete(old) }
        if me.backgroundFile != backgroundFile, let old = me.backgroundFile { ToocFiles.delete(old) }
        me.name = name
        me.bio = bio
        me.hue = hue
        me.iconFile = iconFile
        me.backgroundFile = backgroundFile
        me.hasBackground = hasBackground
        me.birthday = birthday
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
        if message.scheduledAt == nil { delivered(message, in: roomID) }
    }

    func edit(_ id: UUID, in roomID: String, text: String) {
        setMessage(id, in: roomID) {
            $0.kind = .text(text)
            $0.edited = true
        }
    }

    /// Removes a message from this device only.
    func deleteMessage(_ id: UUID, in roomID: String) {
        guard let message = room(roomID)?.messages.first(where: { $0.id == id }) else { return }
        ToocFiles.remove([message])
        update(roomID) { $0.messages.removeAll { $0.id == id } }
    }

    /// Takes your message back: everyone sees that it was unsent.
    func unsend(_ id: UUID, in roomID: String) {
        guard let message = room(roomID)?.messages.first(where: { $0.id == id }) else { return }
        ToocFiles.remove([message])
        setMessage(id, in: roomID) {
            $0.kind = .unsent
            $0.reactions = [:]
            $0.replyTo = nil
        }
    }

    func react(_ emoji: String?, to id: UUID, in roomID: String) {
        let me = me.id
        setMessage(id, in: roomID) { $0.reactions[me] = emoji }
    }

    func vote(_ option: Int, in id: UUID, roomID: String) {
        let me = me.id
        setMessage(id, in: roomID) { message in
            guard case .poll(var poll) = message.kind, !poll.closed else { return }
            var mine = poll.votes[me] ?? []
            if mine.contains(option) {
                mine.removeAll { $0 == option }
            } else {
                mine = poll.multiple ? mine + [option] : [option]
            }
            poll.votes[me] = mine.isEmpty ? nil : mine
            message.kind = .poll(poll)
        }
    }

    func answer(_ date: Int, _ answer: Int, in id: UUID, roomID: String) {
        let me = me.id
        setMessage(id, in: roomID) { message in
            guard case .datePoll(var poll) = message.kind, !poll.closed else { return }
            var mine = poll.answers[me] ?? Array(repeating: -1, count: poll.dates.count)
            mine[date] = mine[date] == answer ? -1 : answer
            poll.answers[me] = mine
            message.kind = .datePoll(poll)
        }
    }

    func reveal(_ id: UUID, roomID: String) {
        setMessage(id, in: roomID) { message in
            guard case .amida(var amida) = message.kind else { return }
            amida.revealed = true
            message.kind = .amida(amida)
        }
    }

    func sendNow(_ id: UUID, in roomID: String) {
        var sent: ToocMessage?
        update(roomID) { room in
            guard let index = room.messages.firstIndex(where: { $0.id == id }) else { return }
            var message = room.messages.remove(at: index)
            message.scheduledAt = nil
            message.date = .now
            message.sending = true
            room.messages.append(message)
            sent = message
        }
        if let sent { delivered(sent, in: roomID) }
    }

    /// Sends the scheduled messages whose time has come.
    func deliverDue() {
        let now = Date.now
        for room in rooms {
            for message in room.messages where (message.scheduledAt ?? .distantFuture) <= now {
                let time = message.scheduledAt ?? now
                var sent = message
                sent.scheduledAt = nil
                sent.date = time
                sent.sending = true
                update(room.id) { room in
                    room.messages.removeAll { $0.id == message.id }
                    room.messages.append(sent)
                }
                delivered(sent, in: room.id)
            }
        }
    }

    /// After a moment the message is "sent", then read; the others may react, vote, answer or reply.
    private func delivered(_ message: ToocMessage, in roomID: String) {
        let id = message.id
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(Int.random(in: 500...900)))
            self?.setMessage(id, in: roomID) { $0.sending = false }
            guard let self, let room = self.room(roomID), !room.isMynote else { return }
            let others = room.memberIDs.filter { self.users[$0]?.isBlocked != true }
            guard !others.isEmpty else { return }
            try? await Task.sleep(for: .seconds(Double.random(in: 1.2...2.5)))
            self.setMessage(id, in: roomID) { $0.readCount = room.isGroup ? Int.random(in: 1...others.count) : 1 }
            switch message.kind {
            case .poll, .datePoll:
                for member in others {
                    try? await Task.sleep(for: .seconds(Double.random(in: 0.8...2.5)))
                    self.dummyAnswer(member, to: id, in: roomID)
                }
            case .text, .photo:
                if Double.random(in: 0...1) < 0.25, let member = others.randomElement() {
                    try? await Task.sleep(for: .seconds(Double.random(in: 0.6...1.5)))
                    self.setMessage(id, in: roomID) { $0.reactions[member] = Self.emojis.randomElement() }
                }
            default:
                break
            }
            guard Double.random(in: 0...1) < (room.isGroup ? 0.6 : 0.85), let sender = others.randomElement() else { return }
            try? await Task.sleep(for: .seconds(Double.random(in: 0.8...2)))
            self.typing[roomID] = sender
            try? await Task.sleep(for: .seconds(Double.random(in: 1.5...3.5)))
            self.typing[roomID] = nil
            self.receive(from: sender, in: roomID)
        }
    }

    private func dummyAnswer(_ member: String, to id: UUID, in roomID: String) {
        setMessage(id, in: roomID) { message in
            switch message.kind {
            case .poll(var poll):
                guard !poll.options.isEmpty, !poll.closed else { return }
                poll.votes[member] = [Int.random(in: 0..<poll.options.count)]
                message.kind = .poll(poll)
            case .datePoll(var poll):
                guard !poll.closed else { return }
                poll.answers[member] = poll.dates.map { _ in [2, 2, 1, 0].randomElement()! }
                message.kind = .datePoll(poll)
            default:
                break
            }
        }
    }

    private func setMessage(_ id: UUID, in roomID: String, _ change: (inout ToocMessage) -> Void) {
        update(roomID) { room in
            guard let index = room.messages.firstIndex(where: { $0.id == id }) else { return }
            change(&room.messages[index])
        }
    }

    static let emojis = ["👍", "❤️", "😂", "😮", "😢", "🙏", "🎉", "🔥"]

    private static let replies = [
        "了解！", "いいね👍", "ありがとう！", "なるほど", "それな", "あとで確認するね", "おっけー", "たしかに😂",
        "ちょうど同じこと考えてた", "まじか！", "了解です🙆", "また連絡するね", "ほんとに？", "楽しみ！",
    ]

    private func receive(from sender: String, in roomID: String) {
        guard let room = room(roomID) else { return }
        let kind: ToocMessage.Kind = Double.random(in: 0...1) < 0.12
            ? .remotePhoto(ToocFiles.randomPhotoURL())
            : .text(Self.replies.randomElement()!)
        let message = ToocMessage(senderID: sender, kind: kind, date: .now)
        let viewing = openRoomID == roomID
        update(roomID) {
            $0.messages.append(message)
            $0.hidden = false
            if !viewing { $0.unread += 1 }
        }
        guard !viewing, !room.muted else { return }
        let who = displayName(sender)
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

    /// Icons and backgrounds for the sample people, from picsum.photos (anyone still without one gets one).
    private func fetchSamplePhotos(for ids: [String]) {
        Task { [weak self] in
            for id in ids {
                if self?.users[id]?.iconFile == nil {
                    let side = Int.random(in: 300...600)
                    if let icon = await ToocFiles.remoteImage("https://picsum.photos/\(side)/\(side)"),
                       let file = ToocFiles.save(icon, side: 600) {
                        self?.updateUser(id) { $0.iconFile = file }
                    }
                }
                if self?.users[id]?.backgroundFile == nil {
                    let width = Int.random(in: 600...900)
                    if let background = await ToocFiles.remoteImage("https://picsum.photos/\(width)/\(width * 16 / 10)"),
                       let file = ToocFiles.save(background, side: 1600) {
                        self?.updateUser(id) { $0.backgroundFile = file }
                    }
                }
            }
        }
    }

    private func loadSamples() {
        let now = Date.now
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let calendar = Calendar.current
        let samples = [
            ToocUser(id: "haruka_m", name: "春香", bio: "カフェ巡りが好き☕️\n週末はだいたい写真を撮りに出かけています。",
                     hue: 0.95, hasBackground: true,
                     birthday: calendar.date(from: DateComponents(year: 2008, month: 4, day: 12)),
                     addedAt: ago(60 * 24 * 3), profileUpdatedAt: ago(30), isFavorite: true),
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
                ToocMessage(senderID: "haruka_m", kind: .remotePhoto(ToocFiles.randomPhotoURL()), date: ago(11)),
            ], unread: 3, pinned: true),
            ToocRoom(id: "g-club", title: "サッカー部 2年", memberIDs: ["kenta.o", "taku", "yui_s"], isGroup: true, messages: [
                ToocMessage(senderID: "taku", kind: .text("来週の練習、グラウンド使えないらしい"), date: ago(60 * 3), readCount: 2),
                ToocMessage(senderID: me, kind: .text("了解！体育館は？"), date: ago(60 * 2.5), readCount: 3),
                ToocMessage(senderID: "kenta.o", kind: .text("体育館は空いてる！\n先生に確認しておくね。\nあと持ち物は\n・ボール\n・ビブス"),
                            date: ago(60 * 2), readCount: 1, reactions: ["taku": "👍", "yui_s": "🙏"]),
                ToocMessage(senderID: "yui_s", kind: .poll(ToocPoll(question: "打ち上げどこにする？", options: ["焼肉", "カラオケ", "ファミレス"],
                                                                     multiple: false, votes: ["taku": [0], "kenta.o": [1]])),
                            date: ago(60 * 1.5)),
            ], unread: 12, draft: "じゃあ"),
            ToocRoom(id: "dm-kenta.o", memberIDs: ["kenta.o"], messages: [
                ToocMessage(senderID: "kenta.o", kind: .text("ノート見せてくれてありがとう"), date: ago(60 * 24 + 30)),
                ToocMessage(senderID: me, kind: .text("いいよー"), date: ago(60 * 24 + 20), readCount: 1),
                ToocMessage(senderID: me, kind: .remotePhoto(ToocFiles.randomPhotoURL()), date: ago(1), sending: true),
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

    static func file(_ account: String) -> URL { folder.appending(path: "\(account).v2.json") }

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
            for room in data.rooms { ToocFiles.remove(room.messages) }
            if let icon = data.me.iconFile { ToocFiles.delete(icon) }
            if let background = data.me.backgroundFile { ToocFiles.delete(background) }
        }
        try? FileManager.default.removeItem(at: file(account))
    }
}

/// Photos and files sent in talks, and the profile's icon and background.
enum ToocFiles {
    private static let cache = NSCache<NSString, UIImage>()

    static var folder: URL {
        let url = URL.applicationSupportDirectory.appending(path: "tooc/files", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func url(_ name: String) -> URL { folder.appending(path: name) }

    /// A random photo for the sample friends: picsum.photos/width/height.
    static func randomPhotoURL() -> String {
        "https://picsum.photos/\(Int.random(in: 300...900))/\(Int.random(in: 300...900))"
    }

    /// Saves a photo (scaled down to `side` at most) and returns its file name.
    static func save(_ image: UIImage, side: CGFloat = 2048) -> String? {
        let scale = min(1, side / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
        guard let data = resized.jpegData(compressionQuality: 0.85) else { return nil }
        let name = "\(UUID().uuidString).jpg"
        do {
            try data.write(to: url(name), options: .atomic)
        } catch {
            return nil
        }
        cache.setObject(resized, forKey: name as NSString)
        return name
    }

    /// Copies a picked file in and returns its stored name.
    static func copy(_ source: URL) -> (name: String, file: String, size: Int)? {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let folder = url(UUID().uuidString)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appending(path: source.lastPathComponent)
        do {
            try FileManager.default.copyItem(at: source, to: target)
        } catch {
            return nil
        }
        let attributes = try? FileManager.default.attributesOfItem(atPath: target.path)
        let size = (attributes?[.size] as? NSNumber)?.intValue ?? 0
        return (source.lastPathComponent, "\(folder.lastPathComponent)/\(source.lastPathComponent)", size)
    }

    static func image(_ name: String) -> UIImage? {
        if let image = cache.object(forKey: name as NSString) { return image }
        guard let image = UIImage(contentsOfFile: url(name).path) else { return nil }
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    /// A web photo, kept once fetched so it never changes.
    static func remoteName(_ address: String) -> String {
        "web-" + String(address.unicodeScalars.map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }) + ".jpg"
    }

    static func remoteImage(_ address: String) async -> UIImage? {
        let name = remoteName(address)
        if let image = image(name) { return image }
        guard let url = URL(string: address),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let image = UIImage(data: data) else { return nil }
        try? data.write(to: Self.url(name), options: .atomic)
        cache.setObject(image, forKey: name as NSString)
        return image
    }

    static func delete(_ name: String) {
        cache.removeObject(forKey: name as NSString)
        try? FileManager.default.removeItem(at: url(name))
        // A copied file lives in its own folder.
        if name.contains("/") {
            try? FileManager.default.removeItem(at: url(String(name.split(separator: "/").first ?? "")))
        }
    }

    static func remove(_ messages: [ToocMessage]) {
        for message in messages {
            switch message.kind {
            case .photo(let name?): delete(name)
            case .file(_, let file, _): delete(file)
            default: break
            }
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

    /// A day in a talk: 今日, 昨日, 11月20日(木), 2025年3月1日(土).
    static func day(_ date: Date, now: Date = .now) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今日" }
        if calendar.isDateInYesterday(date) { return "昨日" }
        return format(date, calendar.isDate(date, equalTo: now, toGranularity: .year) ? "M月d日(E)" : "yyyy年M月d日(E)")
    }

    static func birthday(_ date: Date) -> String { format(date, "M月d日") }

    static func candidate(_ date: Date) -> String { format(date, "M/d(E) HH:mm") }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
