import Foundation

enum FlickDirection: Int, CaseIterable {
    case center, left, up, right, down
}

/// What one direction of a key does.
enum KeyOutput: Equatable {
    case text(String)
    /// 小゛゜: tap cycles the last character through its variants.
    case cycleModifier
    case dakuten
    case handakuten
    case small
    /// a/A: the last letter's case.
    case caseToggle

    var label: String {
        switch self {
        case .text(let text): text
        case .cycleModifier: "小゛゜"
        case .dakuten: "゛"
        case .handakuten: "゜"
        case .small: "小"
        case .caseToggle: "a/A"
        }
    }
}

/// A key of the 12-key boards: its face and its five flicks.
struct KeykieKey: Identifiable, Equatable {
    let id: String
    let label: String
    /// center, left, up, right, down.
    let outputs: [KeyOutput?]

    init(_ id: String, label: String? = nil, _ outputs: [KeyOutput?]) {
        self.id = id
        let first: KeyOutput? = outputs.first ?? nil
        self.label = label ?? first?.label ?? id
        var padded = outputs
        while padded.count < 5 { padded.append(nil) }
        self.outputs = padded
    }

    /// From text: "" means nothing in that direction.
    init(text id: String, label: String? = nil, _ texts: [String]) {
        self.init(id, label: label, texts.map { $0.isEmpty ? nil : KeyOutput.text($0) })
    }

    func output(_ direction: FlickDirection) -> KeyOutput? {
        outputs[direction.rawValue]
    }

    /// The texts a repeated tap steps through (トグル入力).
    var toggleCycle: [String] {
        outputs.compactMap { output in
            if case .text(let text) = output { return text }
            return nil
        }
    }

    var hasFlicks: Bool { outputs.dropFirst().contains { $0 != nil } }
}

enum KeykieLayout {
    /// あ か さ / た な は / ま や ら / 小゛゜ わ 、。？！
    static func kana(punctuation: (String, String)) -> [[KeykieKey]] {
        [
            [KeykieKey(text: "a", ["あ", "い", "う", "え", "お"]),
             KeykieKey(text: "ka", ["か", "き", "く", "け", "こ"]),
             KeykieKey(text: "sa", ["さ", "し", "す", "せ", "そ"])],
            [KeykieKey(text: "ta", ["た", "ち", "つ", "て", "と"]),
             KeykieKey(text: "na", ["な", "に", "ぬ", "ね", "の"]),
             KeykieKey(text: "ha", ["は", "ひ", "ふ", "へ", "ほ"])],
            [KeykieKey(text: "ma", ["ま", "み", "む", "め", "も"]),
             KeykieKey(text: "ya", ["や", "「", "ゆ", "」", "よ"]),
             KeykieKey(text: "ra", ["ら", "り", "る", "れ", "ろ"])],
            [KeykieKey("mod", label: "小゛゜", [.cycleModifier, .dakuten, .small, .handakuten]),
             KeykieKey(text: "wa", ["わ", "を", "ん", "ー"]),
             KeykieKey(text: "punct", label: "、。?!", [punctuation.0, punctuation.1, "？", "！", "…"])],
        ]
    }

    /// @#/&_ ABC DEF / GHI JKL MNO / PQRS TUV WXYZ / a/A '"() .,?!
    static let alpha: [[KeykieKey]] = [
        [KeykieKey(text: "sym", label: "@#/&_", ["@", "#", "/", "&", "_"]),
         KeykieKey(text: "abc", label: "ABC", ["a", "b", "c"]),
         KeykieKey(text: "def", label: "DEF", ["d", "e", "f"])],
        [KeykieKey(text: "ghi", label: "GHI", ["g", "h", "i"]),
         KeykieKey(text: "jkl", label: "JKL", ["j", "k", "l"]),
         KeykieKey(text: "mno", label: "MNO", ["m", "n", "o"])],
        [KeykieKey(text: "pqrs", label: "PQRS", ["p", "q", "r", "s"]),
         KeykieKey(text: "tuv", label: "TUV", ["t", "u", "v"]),
         KeykieKey(text: "wxyz", label: "WXYZ", ["w", "x", "y", "z"])],
        [KeykieKey("case", label: "a/A", [.caseToggle]),
         KeykieKey(text: "quote", label: "'\"()", ["'", "\"", "(", ")"]),
         KeykieKey(text: "period", label: ".,?!", [".", ",", "?", "!"])],
    ]

    /// 1–9, then ( 0 . — the digits' flicks come from the settings.
    static func number(flicks: [String: [String]]) -> [[KeykieKey]] {
        func digit(_ d: String) -> KeykieKey {
            let extra = flicks[d] ?? []
            return KeykieKey(text: "n" + d, label: d, [d] + (0..<4).map { $0 < extra.count ? extra[$0] : "" })
        }
        return [
            [digit("1"), digit("2"), digit("3")],
            [digit("4"), digit("5"), digit("6")],
            [digit("7"), digit("8"), digit("9")],
            [KeykieKey(text: "paren", label: "()[]", ["(", ")", "[", "]"]),
             digit("0"),
             KeykieKey(text: "dot", label: ".,-/", [".", ",", "-", "/"])],
        ]
    }

    static let qwertyRows: [[String]] = [
        ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["a", "s", "d", "f", "g", "h", "j", "k", "l"],
        ["z", "x", "c", "v", "b", "n", "m"],
    ]
}

/// 小゛゜ for kana; case for letters.
enum KeykieKana {
    /// The tap of 小゛゜: each character's loop of variants.
    private static let cycles: [[Character]] = [
        ["あ", "ぁ"], ["い", "ぃ"], ["う", "ぅ", "ゔ"], ["え", "ぇ"], ["お", "ぉ"],
        ["か", "が"], ["き", "ぎ"], ["く", "ぐ"], ["け", "げ"], ["こ", "ご"],
        ["さ", "ざ"], ["し", "じ"], ["す", "ず"], ["せ", "ぜ"], ["そ", "ぞ"],
        ["た", "だ"], ["ち", "ぢ"], ["つ", "っ", "づ"], ["て", "で"], ["と", "ど"],
        ["は", "ば", "ぱ"], ["ひ", "び", "ぴ"], ["ふ", "ぶ", "ぷ"], ["へ", "べ", "ぺ"], ["ほ", "ぼ", "ぽ"],
        ["や", "ゃ"], ["ゆ", "ゅ"], ["よ", "ょ"], ["わ", "ゎ"],
        ["ア", "ァ"], ["イ", "ィ"], ["ウ", "ゥ", "ヴ"], ["エ", "ェ"], ["オ", "ォ"],
        ["カ", "ガ"], ["キ", "ギ"], ["ク", "グ"], ["ケ", "ゲ"], ["コ", "ゴ"],
        ["サ", "ザ"], ["シ", "ジ"], ["ス", "ズ"], ["セ", "ゼ"], ["ソ", "ゾ"],
        ["タ", "ダ"], ["チ", "ヂ"], ["ツ", "ッ", "ヅ"], ["テ", "デ"], ["ト", "ド"],
        ["ハ", "バ", "パ"], ["ヒ", "ビ", "ピ"], ["フ", "ブ", "プ"], ["ヘ", "ベ", "ペ"], ["ホ", "ボ", "ポ"],
        ["ヤ", "ャ"], ["ユ", "ュ"], ["ヨ", "ョ"], ["ワ", "ヮ"],
    ]

    static func cycled(_ char: Character) -> Character? {
        if char.isLetter, char.isASCII { return toggledCase(char) }
        guard let loop = cycles.first(where: { $0.contains(char) }), let index = loop.firstIndex(of: char) else { return nil }
        return loop[(index + 1) % loop.count]
    }

    /// The variant with ゛ / ゜ / small, or back to the plain one when it already is.
    static func variant(_ char: Character, _ output: KeyOutput) -> Character? {
        guard let loop = cycles.first(where: { $0.contains(char) }) else { return nil }
        let plain = loop[0]
        let target: Character?
        switch output {
        case .dakuten: target = loop.first { ["が", "ぎ", "ぐ", "げ", "ご", "ざ", "じ", "ず", "ぜ", "ぞ", "だ", "ぢ", "づ", "で", "ど", "ば", "び", "ぶ", "べ", "ぼ", "ゔ",
                                              "ガ", "ギ", "グ", "ゲ", "ゴ", "ザ", "ジ", "ズ", "ゼ", "ゾ", "ダ", "ヂ", "ヅ", "デ", "ド", "バ", "ビ", "ブ", "ベ", "ボ", "ヴ"].contains($0) }
        case .handakuten: target = loop.first { ["ぱ", "ぴ", "ぷ", "ぺ", "ぽ", "パ", "ピ", "プ", "ペ", "ポ"].contains($0) }
        case .small: target = loop.first { ["ぁ", "ぃ", "ぅ", "ぇ", "ぉ", "っ", "ゃ", "ゅ", "ょ", "ゎ", "ァ", "ィ", "ゥ", "ェ", "ォ", "ッ", "ャ", "ュ", "ョ", "ヮ"].contains($0) }
        default: target = nil
        }
        guard let target else { return nil }
        return char == target ? plain : target
    }

    static func toggledCase(_ char: Character) -> Character {
        let string = String(char)
        let flipped = char.isUppercase ? string.lowercased() : string.uppercased()
        return flipped.first ?? char
    }
}
