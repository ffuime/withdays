import Foundation

/// Every Keykie setting: its key in the App Group's defaults and its default value.
/// The app edits them with `@AppStorage(KK.x, store: KeykieGroup.defaults)`; the keyboard reads them
/// into `KeykieSettings` each time it appears.
enum KK {
    static let prefix = "keykie."

    // 入力
    static let flickThreshold = "keykie.flickThreshold"
    static let flickGuide = "keykie.flickGuide"
    static let longPress = "keykie.longPress"
    static let toggleInput = "keykie.toggleInput"
    static let prediction = "keykie.prediction"
    static let learning = "keykie.learning"
    static let englishCandidates = "keykie.englishCandidates"
    static let spellCheck = "keykie.spellCheck"
    static let spaceFullWidth = "keykie.spaceFullWidth"
    static let punctuation = "keykie.punctuation"
    static let autoCapitalize = "keykie.autoCapitalize"
    static let japaneseLayout = "keykie.japaneseLayout"
    static let englishLayout = "keykie.englishLayout"

    // ジェスチャー
    static let backspaceSwipe = "keykie.backspaceSwipe"
    static let backspaceConfirm = "keykie.backspaceConfirm"
    static let backspaceUndo = "keykie.backspaceUndo"
    static let deleteSwipe = "keykie.deleteSwipe"
    static let spaceCursor = "keykie.spaceCursor"
    static let cursorStep = "keykie.cursorStep"
    static let candidateSwipe = "keykie.candidateSwipe"
    static let numberFlicks = "keykie.numberFlicks"

    // 見た目
    static let skin = "keykie.skin"
    static let appearance = "keykie.appearance"
    static let colorBackground = "keykie.colorBackground"
    static let colorKey = "keykie.colorKey"
    static let colorSpecialKey = "keykie.colorSpecialKey"
    static let colorText = "keykie.colorText"
    static let colorAccent = "keykie.colorAccent"
    static let backgroundImage = "keykie.backgroundImage"
    static let keyRadius = "keykie.keyRadius"
    static let keyShadow = "keykie.keyShadow"
    static let keyBorder = "keykie.keyBorder"
    static let keyHeight = "keykie.keyHeight"
    static let fontSize = "keykie.fontSize"
    static let heightScale = "keykie.heightScale"
    static let oneHanded = "keykie.oneHanded"
    static let barHeight = "keykie.barHeight"

    // フィードバック
    static let sound = "keykie.sound"
    static let haptics = "keykie.haptics"
    static let hapticStrength = "keykie.hapticStrength"
    static let keyPopup = "keykie.keyPopup"

    // クリップボード
    static let clipEnabled = "keykie.clipEnabled"
    static let clipMax = "keykie.clipMax"
    static let clipURLs = "keykie.clipURLs"
    static let clipMaxLength = "keykie.clipMaxLength"
    static let clipSkipConcealed = "keykie.clipSkipConcealed"
    static let clipExclude = "keykie.clipExclude"
    static let clipExpireDays = "keykie.clipExpireDays"

    // 辞書
    static let trendingEnabled = "keykie.trendingEnabled"
    static let trendingInterval = "keykie.trendingInterval"
    static let trendingURL = "keykie.trendingURL"
    static let trendingUpdated = "keykie.trendingUpdated"

    // The keyboard's own notes (not settings: left out of backups).
    static let revision = "keykie.state.revision"
    static let lastSeen = "keykie.state.lastSeen"
    static let fullAccess = "keykie.state.fullAccess"
    static let pasteboardCount = "keykie.state.pasteboardCount"
    static let recentEmoji = "keykie.state.recentEmoji"
    static let statePrefix = "keykie.state."

    static let defaultTrendingURL = "https://raw.githubusercontent.com/ffuime/withdays/main/trending/trending.json"

    static let defaults: [String: Any] = [
        flickThreshold: 24.0,
        flickGuide: true,
        longPress: 0.4,
        toggleInput: true,
        prediction: true,
        learning: true,
        englishCandidates: true,
        spellCheck: true,
        spaceFullWidth: false,
        punctuation: 0,
        autoCapitalize: true,
        japaneseLayout: 0,
        englishLayout: 0,

        backspaceSwipe: true,
        backspaceConfirm: false,
        backspaceUndo: true,
        deleteSwipe: false,
        spaceCursor: false,
        cursorStep: 12.0,
        candidateSwipe: true,
        numberFlicks: "",

        skin: "standard",
        appearance: 0,
        colorBackground: 0xD1D4DA,
        colorKey: 0xFFFFFF,
        colorSpecialKey: 0xADB2BC,
        colorText: 0x111111,
        colorAccent: 0x2F7CF6,
        backgroundImage: false,
        keyRadius: 7.0,
        keyShadow: true,
        keyBorder: false,
        keyHeight: 50.0,
        fontSize: 20.0,
        heightScale: 1.0,
        oneHanded: 0,
        barHeight: 42.0,

        sound: false,
        haptics: true,
        hapticStrength: 0,
        keyPopup: true,

        clipEnabled: true,
        clipMax: 50,
        clipURLs: true,
        clipMaxLength: 5000,
        clipSkipConcealed: true,
        clipExclude: "",
        clipExpireDays: 0,

        trendingEnabled: true,
        trendingInterval: 1,
        trendingURL: defaultTrendingURL,
        trendingUpdated: 0.0,
    ]

    /// Punctuation pairs (読点, 句点), by `punctuation`.
    static let punctuations: [(String, String)] = [("、", "。"), ("，", "．"), ("，", "。"), ("、", "．")]

    /// The number keys' default flicks: left, up, right, down ("" = nothing).
    static let defaultNumberFlicks: [String: [String]] = [
        "1": ["☆", "♪", "→", ""],
        "2": ["¥", "$", "€", ""],
        "3": ["%", "°", "#", ""],
        "4": ["○", "＊", "・", ""],
        "5": ["+", "×", "÷", ""],
        "6": ["<", "=", ">", ""],
        "7": ["「", "」", "：", ""],
        "8": ["〒", "々", "〆", ""],
        "9": ["^", "|", "\\", ""],
        "0": ["~", "…", "&", ""],
    ]

    static func numberFlicks(_ json: String) -> [String: [String]] {
        guard let data = json.data(using: .utf8),
              let map = try? JSONDecoder().decode([String: [String]].self, from: data) else { return defaultNumberFlicks }
        return defaultNumberFlicks.merging(map) { _, custom in custom }
    }

    static func encodeNumberFlicks(_ map: [String: [String]]) -> String {
        guard let data = try? JSONEncoder().encode(map) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

/// The skins (着せ替え). "custom" uses the five colors set by hand.
struct KeykieSkin: Identifiable, Hashable {
    let id: String
    let name: String
    let background: Int
    let key: Int
    let specialKey: Int
    let text: Int
    let accent: Int
    let dark: (background: Int, key: Int, specialKey: Int, text: Int)?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static let all: [KeykieSkin] = [
        KeykieSkin(id: "standard", name: "スタンダード", background: 0xD1D4DA, key: 0xFFFFFF, specialKey: 0xADB2BC, text: 0x111111, accent: 0x2F7CF6,
                   dark: (0x2B2B2D, 0x6B6B6E, 0x464648, 0xFFFFFF)),
        KeykieSkin(id: "sakura", name: "さくら", background: 0xF6DDE4, key: 0xFFF8FA, specialKey: 0xE9B7C5, text: 0x5A2A3A, accent: 0xE0607E,
                   dark: (0x3A2229, 0x6E4652, 0x51323C, 0xFFE9EF)),
        KeykieSkin(id: "mint", name: "ミント", background: 0xD5EFE6, key: 0xF7FFFC, specialKey: 0xA8D9C8, text: 0x1F4A3D, accent: 0x1FA67A,
                   dark: (0x1E302A, 0x3F5E54, 0x2D463E, 0xE6FFF6)),
        KeykieSkin(id: "sky", name: "そら", background: 0xD6E6F7, key: 0xF8FBFF, specialKey: 0xA9C6E8, text: 0x1D3557, accent: 0x2F7CF6,
                   dark: (0x1C2738, 0x3D5272, 0x2B3B55, 0xE8F1FF)),
        KeykieSkin(id: "lemon", name: "レモン", background: 0xF6EFC8, key: 0xFFFDF1, specialKey: 0xE6D98E, text: 0x4A4012, accent: 0xD6A400,
                   dark: (0x34301A, 0x666038, 0x4A4526, 0xFFF8D9)),
        KeykieSkin(id: "navy", name: "ネイビー", background: 0x1B2A41, key: 0x324A6D, specialKey: 0x243753, text: 0xF1F5FB, accent: 0x6FB1FF, dark: nil),
        KeykieSkin(id: "mono", name: "モノクロ", background: 0xEDEDED, key: 0xFFFFFF, specialKey: 0xD5D5D5, text: 0x000000, accent: 0x000000,
                   dark: (0x111111, 0x2E2E2E, 0x1E1E1E, 0xFFFFFF)),
        KeykieSkin(id: "custom", name: "カスタム", background: 0, key: 0, specialKey: 0, text: 0, accent: 0, dark: nil),
    ]

    static func named(_ id: String) -> KeykieSkin {
        all.first { $0.id == id } ?? all[0]
    }
}

/// Exports and restores every setting plus the dictionaries as one JSON file.
enum KeykieBackup {
    struct Payload: Codable {
        var version = 1
        var settings: [String: Value]
        var userWords: [KeykieUserWord]
        var phrases: [KeykiePhrase]
    }

    /// The JSON values a setting can hold.
    enum Value: Codable {
        case bool(Bool), number(Double), string(String)

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Bool.self) { self = .bool(value) }
            else if let value = try? container.decode(Double.self) { self = .number(value) }
            else { self = .string(try container.decode(String.self)) }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .bool(let value): try container.encode(value)
            case .number(let value): try container.encode(value)
            case .string(let value): try container.encode(value)
            }
        }
    }

    static func export() -> Data? {
        let defaults = KeykieGroup.defaults
        var settings: [String: Value] = [:]
        for (key, fallback) in KK.defaults {
            let value = defaults.object(forKey: key) ?? fallback
            switch value {
            case let string as String: settings[key] = .string(string)
            case let number as NSNumber:
                // NSNumber from a Bool is CFBoolean.
                if CFGetTypeID(number) == CFBooleanGetTypeID() { settings[key] = .bool(number.boolValue) }
                else { settings[key] = .number(number.doubleValue) }
            default: break
            }
        }
        let payload = Payload(settings: settings, userWords: KeykieDictionary.userWords(), phrases: KeykieDictionary.phrases())
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try? encoder.encode(payload)
    }

    static func restore(_ data: Data) throws {
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        let defaults = KeykieGroup.defaults
        for (key, value) in payload.settings {
            guard let fallback = KK.defaults[key] else { continue }
            switch value {
            case .bool(let bool): defaults.set(bool, forKey: key)
            case .number(let number):
                if fallback is Int { defaults.set(Int(number), forKey: key) } else { defaults.set(number, forKey: key) }
            case .string(let string): defaults.set(string, forKey: key)
            }
        }
        KeykieDictionary.saveUserWords(payload.userWords)
        KeykieDictionary.savePhrases(payload.phrases)
        KeykieGroup.touch()
    }

    /// Every setting back to its default. Dictionaries, phrases and the clipboard stay.
    static func resetSettings() {
        for key in KK.defaults.keys {
            KeykieGroup.defaults.removeObject(forKey: key)
        }
        try? FileManager.default.removeItem(at: KeykieGroup.file("background.jpg"))
        KeykieGroup.touch()
    }
}
