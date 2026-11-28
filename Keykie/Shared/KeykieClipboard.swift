import Foundation

struct KeykieClip: Codable, Identifiable, Hashable {
    var id = UUID()
    var text: String
    var date = Date()
    var pinned = false
}

/// The clipboard history (clipboard.json). iOS gives no way to watch the pasteboard in the background,
/// so the keyboard only looks when it appears (see the README).
enum KeykieClipboard {
    static func load() -> [KeykieClip] {
        let clips = KeykieGroup.load([KeykieClip].self, from: "clipboard.json") ?? []
        return expire(clips)
    }

    static func save(_ clips: [KeykieClip]) {
        KeykieGroup.save(clips, to: "clipboard.json")
    }

    /// Pinned first, then newest first.
    static func sorted(_ clips: [KeykieClip]) -> [KeykieClip] {
        clips.sorted { ($0.pinned ? 1 : 0, $0.date) > ($1.pinned ? 1 : 0, $1.date) }
    }

    /// Whether the settings allow keeping this text.
    static func accepts(_ text: String) -> Bool {
        let defaults = KeykieGroup.defaults
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard defaults.bool(forKey: KK.clipEnabled), !trimmed.isEmpty else { return false }
        let maxLength = defaults.integer(forKey: KK.clipMaxLength)
        if maxLength > 0, text.count > maxLength { return false }
        if !defaults.bool(forKey: KK.clipURLs), let url = URL(string: trimmed), url.scheme != nil, !trimmed.contains(" ") {
            return false
        }
        for rule in KK.lines(defaults.string(forKey: KK.clipExclude) ?? "") {
            if matches(text, rule: rule) { return false }
        }
        return true
    }

    /// A rule is a regular expression when written as /…/, otherwise text the clip must not contain.
    static func matches(_ text: String, rule: String) -> Bool {
        if rule.count > 2, rule.hasPrefix("/"), rule.hasSuffix("/") {
            let pattern = String(rule.dropFirst().dropLast())
            return text.range(of: pattern, options: .regularExpression) != nil
        }
        return text.localizedCaseInsensitiveContains(rule)
    }

    /// Adds text at the top; a duplicate moves to the top instead (keeping its pin).
    static func add(_ text: String, to clips: [KeykieClip]) -> [KeykieClip] {
        var clips = clips
        var clip = KeykieClip(text: text)
        if let index = clips.firstIndex(where: { $0.text == text }) {
            clip.pinned = clips[index].pinned
            clips.remove(at: index)
        }
        clips.insert(clip, at: 0)
        return trim(clips)
    }

    /// Keeps at most the set number of unpinned clips.
    static func trim(_ clips: [KeykieClip]) -> [KeykieClip] {
        let limit = max(1, KeykieGroup.defaults.integer(forKey: KK.clipMax))
        var unpinned = 0
        return clips.filter { clip in
            if clip.pinned { return true }
            unpinned += 1
            return unpinned <= limit
        }
    }

    static func expire(_ clips: [KeykieClip]) -> [KeykieClip] {
        let days = KeykieGroup.defaults.integer(forKey: KK.clipExpireDays)
        guard days > 0 else { return clips }
        let limit = Date().addingTimeInterval(-Double(days) * 86_400)
        return clips.filter { $0.pinned || $0.date >= limit }
    }
}
