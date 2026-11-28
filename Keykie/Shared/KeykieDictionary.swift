import Foundation

/// Parts of speech the user dictionary offers.
enum KeykiePOS: String, Codable, CaseIterable, Identifiable {
    case noun = "名詞"
    case properNoun = "固有名詞"
    case person = "人名"
    case place = "地名"
    case organization = "組織"
    case symbol = "記号"

    var id: String { rawValue }

    /// azooKey's context ids for the part of speech (CIDData).
    var cid: Int {
        switch self {
        case .noun: 1285
        case .properNoun: 1288
        case .person: 1289
        case .place: 1293
        case .organization: 1292
        case .symbol: 5
        }
    }

    /// Reads "名詞", "固有名詞" and the like, defaulting to 名詞.
    init(label: String) {
        let label = label.trimmingCharacters(in: .whitespaces)
        self = Self.allCases.first { label.hasPrefix($0.rawValue) }
            ?? (label.contains("人") ? .person : label.contains("地") ? .place : label.contains("固有") ? .properNoun : .noun)
    }
}

struct KeykieUserWord: Codable, Identifiable, Hashable {
    var id = UUID()
    /// ひらがな.
    var reading: String
    var word: String
    var pos: KeykiePOS = .noun
}

struct KeykiePhrase: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var body: String
}

/// One trending word as the daily script writes it (trending/trending.json).
struct KeykieTrendingWord: Codable, Hashable {
    var reading: String
    var word: String
    var pos: String?
}

struct KeykieTrendingFile: Codable {
    var updated: String?
    var words: [KeykieTrendingWord]
}

enum KeykieDictionary {
    static func userWords() -> [KeykieUserWord] {
        KeykieGroup.load([KeykieUserWord].self, from: "userdict.json") ?? []
    }

    static func saveUserWords(_ words: [KeykieUserWord]) {
        KeykieGroup.save(words, to: "userdict.json")
        KeykieGroup.touch()
    }

    static func phrases() -> [KeykiePhrase] {
        KeykieGroup.load([KeykiePhrase].self, from: "phrases.json") ?? []
    }

    static func savePhrases(_ phrases: [KeykiePhrase]) {
        KeykieGroup.save(phrases, to: "phrases.json")
    }

    static func trendingWords() -> [KeykieTrendingWord] {
        KeykieGroup.load([KeykieTrendingWord].self, from: "trending.json") ?? []
    }

    // MARK: CSV (読み,表記,品詞 — a header line is skipped)

    static func csv(_ words: [KeykieUserWord]) -> String {
        var lines = ["読み,表記,品詞"]
        for word in words {
            lines.append([word.reading, word.word, word.pos.rawValue].map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func parseCSV(_ text: String) -> [KeykieUserWord] {
        var words: [KeykieUserWord] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let fields = csvFields(String(line))
            guard fields.count >= 2 else { continue }
            let reading = hiragana(fields[0].trimmingCharacters(in: .whitespaces))
            let word = fields[1].trimmingCharacters(in: .whitespaces)
            guard !reading.isEmpty, !word.isEmpty, reading != "読み", reading != "よみ" else { continue }
            words.append(KeykieUserWord(reading: reading, word: word, pos: KeykiePOS(label: fields.count > 2 ? fields[2] : "")))
        }
        return words
    }

    private static func csvField(_ value: String) -> String {
        value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline })
            ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            : value
    }

    private static func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var quoted = false
        var iterator = Array(line).makeIterator()
        var pending: Character? = nil
        while let char = pending ?? iterator.next() {
            pending = nil
            if quoted {
                if char == "\"" {
                    if let next = iterator.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else { quoted = false }
                } else { field.append(char) }
            } else if char == "\"" {
                quoted = true
            } else if char == "," || char == "\t" {
                fields.append(field); field = ""
            } else {
                field.append(char)
            }
        }
        fields.append(field)
        return fields
    }

    static func hiragana(_ text: String) -> String {
        text.applyingTransform(.hiraganaToKatakana, reverse: true) ?? text
    }

    static func katakana(_ text: String) -> String {
        text.applyingTransform(.hiraganaToKatakana, reverse: false) ?? text
    }

    // MARK: Trending words

    enum UpdateError: LocalizedError {
        case badURL, badData
        var errorDescription: String? {
            switch self {
            case .badURL: "更新URLが正しくありません"
            case .badData: "流行語辞書を読み込めませんでした"
            }
        }
    }

    /// Whether the set interval has passed since the last update.
    static var trendingIsDue: Bool {
        let defaults = KeykieGroup.defaults
        guard defaults.bool(forKey: KK.trendingEnabled) else { return false }
        let days = defaults.integer(forKey: KK.trendingInterval)
        guard days > 0 else { return false }
        let last = defaults.double(forKey: KK.trendingUpdated)
        return Date().timeIntervalSince1970 - last > Double(days) * 86_400 - 3_600
    }

    /// Downloads trending.json and keeps it as the trending dictionary. Returns the number of words.
    @discardableResult
    static func updateTrending() async throws -> Int {
        let string = KeykieGroup.defaults.string(forKey: KK.trendingURL) ?? KK.defaultTrendingURL
        guard let url = URL(string: string), url.scheme?.hasPrefix("http") == true else { throw UpdateError.badURL }
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw UpdateError.badData }
        let words: [KeykieTrendingWord]
        if let file = try? JSONDecoder().decode(KeykieTrendingFile.self, from: data) {
            words = file.words
        } else if let list = try? JSONDecoder().decode([KeykieTrendingWord].self, from: data) {
            words = list
        } else if let text = String(data: data, encoding: .utf8) {
            words = parseCSV(text).map { KeykieTrendingWord(reading: $0.reading, word: $0.word, pos: $0.pos.rawValue) }
        } else {
            throw UpdateError.badData
        }
        let clean = words
            .map { KeykieTrendingWord(reading: hiragana($0.reading), word: $0.word, pos: $0.pos) }
            .filter { !$0.reading.isEmpty && !$0.word.isEmpty }
        KeykieGroup.save(Array(clean.prefix(5000)), to: "trending.json")
        KeykieGroup.defaults.set(Date().timeIntervalSince1970, forKey: KK.trendingUpdated)
        KeykieGroup.touch()
        return clean.count
    }

    /// The learning memory is the converter's files; deleting them resets learning.
    static func resetLearning() {
        try? FileManager.default.removeItem(at: KeykieGroup.directory.appendingPathComponent("Memory", isDirectory: true))
        KeykieGroup.touch()
    }
}
