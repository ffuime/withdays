import Foundation

/// The talks' messages kept on this device (text, stickers, cards; photos are only their addresses), so opening
/// tooc reads just what's new from the server.
enum ToocMessageCache {
    /// How many of the newest kept messages are read again from the server, for their reactions, reads and edits.
    static let overlap = 30
    /// The most kept per talk.
    static let limit = 3000

    private struct Saved: Codable {
        var messages: [ToocMessage]
        var readBy: [UUID: [String]]
    }

    static func folder(_ account: String) -> URL {
        let url = URL.applicationSupportDirectory.appending(path: "tooc/messages-\(account)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var marked = url
        try? marked.setResourceValues(values)
        return url
    }

    private static func file(_ roomID: String, account: String) -> URL {
        folder(account).appending(path: "\(roomID).json")
    }

    static func load(_ roomID: String, account: String) -> (messages: [ToocMessage], readBy: [UUID: [String]])? {
        guard let data = try? Data(contentsOf: file(roomID, account: account)),
              let saved = try? JSONDecoder().decode(Saved.self, from: data) else { return nil }
        return (saved.messages, saved.readBy)
    }

    /// Written off the main thread; only sent messages (nothing still on its way).
    static func save(_ messages: [ToocMessage], readBy: [UUID: [String]], roomID: String, account: String) {
        let kept = Array(messages.filter { !$0.sending && !$0.failed && $0.scheduledAt == nil }.suffix(limit))
        let ids = Set(kept.map(\.id))
        let saved = Saved(messages: kept, readBy: readBy.filter { ids.contains($0.key) })
        let url = file(roomID, account: account)
        Task.detached(priority: .utility) {
            guard let data = try? JSONEncoder().encode(saved) else { return }
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
}
