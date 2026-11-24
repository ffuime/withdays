import Foundation
import Security
import SwiftUI
import UIKit

// tooc: a personal talk app on Firebase. These are its value types; ToocStore keeps them in step with the server.

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
    /// The Firebase account behind this toocID.
    var uid: String?
    /// The icon and background photos on the server.
    var iconURL: String?
    var backgroundURL: String?
    /// Whether others can find this person by typing the toocID.
    var findable = false

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
        /// A file on the server.
        case remoteFile(name: String, url: String, size: Int)
        case location(latitude: Double, longitude: Double, title: String)
        case poll(ToocPoll)
        case datePoll(ToocDatePoll)
        case amida(ToocAmida)
        /// A sticker made from someone's photo (a PNG on the server).
        case sticker(url: String)
        /// A post in the talk's ノート, announced in the talk.
        case note(id: String, text: String)
        /// Photos added to one of the talk's アルバム.
        case album(id: String, title: String, count: Int)
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
    /// Who was called with @name (toocIDs).
    var mentions: [String] = []
    /// Couldn't be sent: kept here, to send again or delete.
    var failed = false

    var preview: String {
        switch kind {
        case .text(let text): text
        case .photo, .remotePhoto: "写真"
        case .file(let name, _, _), .remoteFile(let name, _, _): "ファイル：\(name)"
        case .location(_, _, let title): "位置情報：\(title)"
        case .poll(let poll): "投票：\(poll.question)"
        case .datePoll(let poll): "日程調整：\(poll.title)"
        case .amida(let amida): "あみだくじ：\(amida.title)"
        case .sticker: "スタンプ"
        case .note(_, let text): "ノート：\(text)"
        case .album(_, let title, let count): "アルバム「\(title)」に写真を\(count)枚追加"
        case .unsent: "送信が取り消されました"
        }
    }

    var symbol: String? {
        switch kind {
        case .photo, .remotePhoto: "photo.fill"
        case .file, .remoteFile: "doc.fill"
        case .location: "mappin.circle.fill"
        case .poll: "chart.bar.fill"
        case .datePoll: "calendar"
        case .amida: "line.3.horizontal"
        case .sticker: "face.smiling"
        case .note: "note.text"
        case .album: "photo.stack"
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

    /// Can go to another talk as it is (not polls and the like, whose answers belong to this one).
    var forwardable: Bool {
        switch kind {
        case .text, .remotePhoto, .remoteFile, .location, .sticker: !sending && !failed
        default: false
        }
    }
}

extension ToocMessage {
    enum CodingKeys: String, CodingKey {
        case id, senderID, kind, date, sending, readCount, replyTo, silent, scheduledAt, reactions, edited, mentions
    }

    /// Messages saved by an older version (scheduled ones) have no mentions yet.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(senderID: try c.decode(String.self, forKey: .senderID), kind: try c.decode(Kind.self, forKey: .kind),
                  date: try c.decode(Date.self, forKey: .date))
        id = try c.decode(UUID.self, forKey: .id)
        sending = try c.decodeIfPresent(Bool.self, forKey: .sending) ?? false
        readCount = try c.decodeIfPresent(Int.self, forKey: .readCount) ?? 0
        replyTo = try c.decodeIfPresent(UUID.self, forKey: .replyTo)
        silent = try c.decodeIfPresent(Bool.self, forKey: .silent) ?? false
        scheduledAt = try c.decodeIfPresent(Date.self, forKey: .scheduledAt)
        reactions = try c.decodeIfPresent([String: String].self, forKey: .reactions) ?? [:]
        edited = try c.decodeIfPresent(Bool.self, forKey: .edited) ?? false
        mentions = try c.decodeIfPresent([String].self, forKey: .mentions) ?? []
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
    /// Someone called you with @ in a message you haven't read.
    var mentioned = false
    /// A group's own icon and background photos.
    var iconFile: String?
    var backgroundFile: String?
    var iconURL: String?
    var backgroundURL: String?

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
    /// The Google font tooc is drawn in (its id); nil for the system font.
    var font: String?

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
        font = try container.decodeIfPresent(String.self, forKey: .font)
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

struct ToocError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// MARK: - On this device

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
