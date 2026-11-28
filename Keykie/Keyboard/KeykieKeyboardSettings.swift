import SwiftUI
import UIKit

/// The settings as the keyboard uses them, read once each time it appears.
struct KeykieKeyboardSettings {
    var flickThreshold: CGFloat
    var flickGuide: Bool
    var longPress: Double
    var toggleInput: Bool
    var prediction: Bool
    var learning: Bool
    var englishCandidates: Bool
    var spellCheck: Bool
    var spaceFullWidth: Bool
    var punctuation: (String, String)
    var autoCapitalize: Bool
    var japaneseQwerty: Bool
    var englishQwerty: Bool

    var backspaceSwipe: Bool
    var backspaceConfirm: Bool
    var backspaceUndo: Bool
    var deleteSwipe: Bool
    var spaceCursor: Bool
    var cursorStep: CGFloat
    var candidateSwipe: Bool
    var numberFlicks: [String: [String]]

    var skin: KeykieSkin
    var appearance: Int
    var custom: (background: Int, key: Int, specialKey: Int, text: Int, accent: Int)
    var backgroundImage: Bool
    var keyRadius: CGFloat
    var keyShadow: Bool
    var keyBorder: Bool
    var keyHeight: CGFloat
    var fontSize: CGFloat
    var oneHanded: Int
    var barHeight: CGFloat

    var sound: Bool
    var haptics: Bool
    var hapticStrength: Int
    var keyPopup: Bool

    static func load() -> Self {
        let d = KeykieGroup.defaults
        func double(_ key: String) -> CGFloat { CGFloat(d.double(forKey: key)) }
        let punct = d.integer(forKey: KK.punctuation)
        return Self(
            flickThreshold: max(8, double(KK.flickThreshold)),
            flickGuide: d.bool(forKey: KK.flickGuide),
            longPress: max(0.15, d.double(forKey: KK.longPress)),
            toggleInput: d.bool(forKey: KK.toggleInput),
            prediction: d.bool(forKey: KK.prediction),
            learning: d.bool(forKey: KK.learning),
            englishCandidates: d.bool(forKey: KK.englishCandidates),
            spellCheck: d.bool(forKey: KK.spellCheck),
            spaceFullWidth: d.bool(forKey: KK.spaceFullWidth),
            punctuation: KK.punctuations[KK.punctuations.indices.contains(punct) ? punct : 0],
            autoCapitalize: d.bool(forKey: KK.autoCapitalize),
            japaneseQwerty: d.integer(forKey: KK.japaneseLayout) == 1,
            englishQwerty: d.integer(forKey: KK.englishLayout) == 1,
            backspaceSwipe: d.bool(forKey: KK.backspaceSwipe),
            backspaceConfirm: d.bool(forKey: KK.backspaceConfirm),
            backspaceUndo: d.bool(forKey: KK.backspaceUndo),
            deleteSwipe: d.bool(forKey: KK.deleteSwipe),
            spaceCursor: d.bool(forKey: KK.spaceCursor),
            cursorStep: max(4, double(KK.cursorStep)),
            candidateSwipe: d.bool(forKey: KK.candidateSwipe),
            numberFlicks: KK.numberFlicks(d.string(forKey: KK.numberFlicks) ?? ""),
            skin: KeykieSkin.named(d.string(forKey: KK.skin) ?? "standard"),
            appearance: d.integer(forKey: KK.appearance),
            custom: (d.integer(forKey: KK.colorBackground), d.integer(forKey: KK.colorKey), d.integer(forKey: KK.colorSpecialKey),
                     d.integer(forKey: KK.colorText), d.integer(forKey: KK.colorAccent)),
            backgroundImage: d.bool(forKey: KK.backgroundImage),
            keyRadius: double(KK.keyRadius),
            keyShadow: d.bool(forKey: KK.keyShadow),
            keyBorder: d.bool(forKey: KK.keyBorder),
            keyHeight: min(80, max(34, double(KK.keyHeight))) * min(1.4, max(0.7, double(KK.heightScale))),
            fontSize: min(30, max(12, double(KK.fontSize))),
            oneHanded: d.integer(forKey: KK.oneHanded),
            barHeight: min(60, max(32, double(KK.barHeight))),
            sound: d.bool(forKey: KK.sound),
            haptics: d.bool(forKey: KK.haptics),
            hapticStrength: d.integer(forKey: KK.hapticStrength),
            keyPopup: d.bool(forKey: KK.keyPopup)
        )
    }

    static let keySpacing: CGFloat = 6

    /// Candidate bar, four rows of keys and the gaps.
    var totalHeight: CGFloat {
        barHeight + keyHeight * 4 + Self.keySpacing * 5
    }
}

/// The skin's colors for the current light / dark.
struct KeykiePalette {
    var background: Color
    var key: Color
    var specialKey: Color
    var text: Color
    var accent: Color
    var pressedKey: Color

    init(_ settings: KeykieKeyboardSettings, dark: Bool) {
        let skin = settings.skin
        func color(_ hex: Int) -> Color {
            Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        if skin.id == "custom" {
            let c = settings.custom
            background = color(c.background); key = color(c.key); specialKey = color(c.specialKey)
            text = color(c.text); accent = color(c.accent)
        } else if dark, let night = skin.dark {
            background = color(night.background); key = color(night.key); specialKey = color(night.specialKey)
            text = color(night.text); accent = color(skin.accent)
        } else {
            background = color(skin.background); key = color(skin.key); specialKey = color(skin.specialKey)
            text = color(skin.text); accent = color(skin.accent)
        }
        pressedKey = specialKey
    }
}
