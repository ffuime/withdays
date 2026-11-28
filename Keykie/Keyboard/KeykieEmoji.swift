import Foundation

/// The emoji board's categories, built from Unicode ranges; only what this iOS can draw is kept.
enum KeykieEmoji {
    struct Category: Identifiable {
        let id: String
        let symbol: String
        let emoji: [String]
    }

    private static func range(_ ranges: [ClosedRange<UInt32>], textStyleToo: Bool = false) -> [String] {
        var result: [String] = []
        for range in ranges {
            for value in range {
                guard let scalar = Unicode.Scalar(value) else { continue }
                let properties = scalar.properties
                if properties.isEmojiPresentation {
                    result.append(String(scalar))
                } else if textStyleToo, properties.isEmoji, value > 0xFF {
                    result.append(String(scalar) + "\u{FE0F}")
                }
            }
        }
        return result
    }

    private static func flags(_ codes: String) -> [String] {
        codes.split(separator: " ").map { code in
            var flag = ""
            flag.unicodeScalars.append(contentsOf: code.unicodeScalars.compactMap { Unicode.Scalar(0x1F1E6 + $0.value - 65) })
            return flag
        }
    }

    static let categories: [Category] = [
        Category(id: "smileys", symbol: "face.smiling", emoji: range([
            0x1F600...0x1F64F, 0x1F910...0x1F92F, 0x1F970...0x1F97A, 0x1F9D0...0x1F9D0, 0x1FAE0...0x1FAE9,
        ])),
        Category(id: "people", symbol: "hand.wave", emoji: range([
            0x1F440...0x1F450, 0x1F466...0x1F487, 0x1F4AA...0x1F4AA, 0x1F574...0x1F57A, 0x1F590...0x1F596,
            0x1F918...0x1F91F, 0x1F926...0x1F926, 0x1F930...0x1F939, 0x1F9B0...0x1F9B9, 0x1F9D1...0x1F9DF, 0x1FAF0...0x1FAF8,
        ], textStyleToo: true)),
        Category(id: "nature", symbol: "leaf", emoji: range([
            0x1F400...0x1F43F, 0x1F980...0x1F9AE, 0x1F330...0x1F344, 0x1FAB0...0x1FABD, 0x1FAE8...0x1FAE8,
        ], textStyleToo: true)),
        Category(id: "food", symbol: "fork.knife", emoji: range([
            0x1F345...0x1F37F, 0x1F950...0x1F96F, 0x1F9C0...0x1F9CB, 0x1FAD0...0x1FADB,
        ])),
        Category(id: "activity", symbol: "soccerball", emoji: range([
            0x1F380...0x1F3D3, 0x1F93A...0x1F94F, 0x1F3F8...0x1F3FF, 0x26BD...0x26BE, 0x1FA80...0x1FA8F,
        ], textStyleToo: true)),
        Category(id: "travel", symbol: "car", emoji: range([
            0x1F680...0x1F6FF, 0x1F3D4...0x1F3F0, 0x1F30D...0x1F32F, 0x2600...0x2604, 0x26C4...0x26F5,
        ], textStyleToo: true)),
        Category(id: "objects", symbol: "lightbulb", emoji: range([
            0x1F4A1...0x1F4FF, 0x1F507...0x1F53D, 0x1F9E0...0x1F9FF, 0x1FA70...0x1FA7F, 0x1FA90...0x1FAAF, 0x231A...0x231B, 0x23F0...0x23F3,
        ], textStyleToo: true)),
        Category(id: "symbols", symbol: "heart", emoji: range([
            0x2764...0x2764, 0x1F493...0x1F49F, 0x1F5A4...0x1F5A4, 0x1F90D...0x1F90F, 0x1FA75...0x1FA77, 0x1F4AF...0x1F4AF,
            0x2705...0x2705, 0x274C...0x274E, 0x2753...0x2757, 0x2795...0x2797, 0x27B0...0x27BF, 0x1F534...0x1F53D, 0x1F7E0...0x1F7EB,
            0x2B50...0x2B55, 0x2648...0x2653,
        ], textStyleToo: true)),
        Category(id: "flags", symbol: "flag", emoji: ["🏁", "🚩", "🎌", "🏴", "🏳️", "🏳️‍🌈"] + flags(
            "JP US GB FR DE IT ES PT NL BE CH AT SE NO DK FI IE IS PL CZ HU GR TR UA RU CA MX BR AR CL CO PE AU NZ KR KP CN TW HK MO SG MY TH VN PH ID IN PK BD LK NP MN SA AE QA IL EG ZA NG KE MA"
        )),
    ]

    /// English names: "cat" finds 🐱 and 🐈.
    static func search(_ query: String) -> [String] {
        let query = query.lowercased()
        guard query.allSatisfy({ $0.isASCII }), query.count >= 2 else { return [] }
        var results: [String] = []
        for category in categories {
            for emoji in category.emoji {
                guard let scalar = emoji.unicodeScalars.first, let name = scalar.properties.name?.lowercased() else { continue }
                if name.contains(query) { results.append(emoji) }
                if results.count >= 60 { return results }
            }
        }
        return results
    }
}
