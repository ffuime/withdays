import KanaKanjiConverterModuleWithDefaultDictionary
import SwiftUI

extension KeykieState {
    var palette: KeykiePalette { KeykiePalette(settings, dark: dark) }
    var spacing: CGFloat { KeykieKeyboardSettings.keySpacing }
    var boardHeight: CGFloat { settings.keyHeight * 4 + spacing * 5 }
}

/// Candidate bar on top, the board below; the clipboard covers both.
struct KeykieRootView: View {
    @Environment(KeykieState.self) private var state

    var body: some View {
        let palette = state.palette
        VStack(spacing: 0) {
            KeykieCandidateBar()
                .frame(height: state.settings.barHeight)
            ZStack {
                oneHanded { board }
                if state.showAllCandidates {
                    KeykieAllCandidates()
                        .transition(.opacity)
                }
            }
            .frame(height: state.boardHeight)
            .zIndex(1)
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background { background(palette) }
        .overlay {
            if state.showClipboard {
                KeykieClipboardSheet()
                    .transition(.move(edge: .bottom))
            }
        }
        .foregroundStyle(palette.text)
        .environment(\.colorScheme, state.dark ? .dark : .light)
        .animation(.snappy(duration: 0.2), value: state.mode)
    }

    @ViewBuilder
    private var board: some View {
        switch state.mode {
        case .emoji:
            KeykieEmojiBoard()
        case .alpha where state.settings.englishQwerty:
            KeykieQwertyBoard(romaji: false)
        case .kana where state.settings.japaneseQwerty:
            KeykieQwertyBoard(romaji: true)
        case .number:
            KeykieFlickBoard(rows: KeykieLayout.number(flicks: state.settings.numberFlicks))
        case .alpha:
            KeykieFlickBoard(rows: KeykieLayout.alpha)
        case .kana:
            KeykieFlickBoard(rows: KeykieLayout.kana(punctuation: state.settings.punctuation))
        }
    }

    /// 片手モード: the board narrowed to one side.
    @ViewBuilder
    private func oneHanded(@ViewBuilder _ content: () -> some View) -> some View {
        if state.settings.oneHanded == 0 {
            content()
        } else {
            let board = content()
            GeometryReader { geo in
                board
                    .frame(width: geo.size.width * 0.86)
                    .frame(maxWidth: .infinity, alignment: state.settings.oneHanded == 1 ? .leading : .trailing)
            }
        }
    }

    @ViewBuilder
    private func background(_ palette: KeykiePalette) -> some View {
        if let image = state.backgroundImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .overlay(palette.background.opacity(0.25))
                .clipped()
        } else {
            palette.background
        }
    }
}

// MARK: - Keys

/// A key's face: the skin's key color, corner, shadow and border.
struct KeykieKeyFace<Label: View>: View {
    var special = false
    var pressed = false
    var accent = false
    @ViewBuilder var label: Label

    @Environment(KeykieState.self) private var state

    var body: some View {
        let palette = state.palette
        let settings = state.settings
        let shape = RoundedRectangle(cornerRadius: settings.keyRadius, style: .continuous)
        let fill = accent ? palette.accent : pressed ? palette.pressedKey : special ? palette.specialKey : palette.key
        label
            .foregroundStyle(accent ? Color.white : palette.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                shape
                    .fill(fill.opacity(state.backgroundImage == nil ? 1 : 0.85))
                    .shadow(color: .black.opacity(settings.keyShadow ? 0.28 : 0), radius: 0, x: 0, y: 1)
            }
            .overlay {
                if settings.keyBorder {
                    shape.strokeBorder(palette.text.opacity(0.25), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
    }
}

struct KeykieKeyButtonStyle: ButtonStyle {
    var special = true
    var accent = false

    func makeBody(configuration: Configuration) -> some View {
        KeykieKeyFace(special: special, pressed: configuration.isPressed, accent: accent) {
            configuration.label
        }
    }
}

/// A 12-key key: tap, or flick in four directions. Holding shows the guide.
struct KeykieFlickKey: View {
    let key: KeykieKey

    @Environment(KeykieState.self) private var state
    @State private var pressed = false
    @State private var direction = FlickDirection.center
    @State private var holding = false
    @State private var holdTask: Task<Void, Never>?

    var body: some View {
        let settings = state.settings
        KeykieKeyFace(special: key.id == "mod" || key.id == "case", pressed: pressed) {
            label(settings)
        }
        .overlay {
            if pressed {
                if settings.flickGuide, key.hasFlicks, holding || direction != .center {
                    KeykieFlickGuide(key: key, direction: direction)
                } else if settings.keyPopup, direction == .center, let text = popupText {
                    KeykiePopup(text: text)
                }
            }
        }
        .zIndex(pressed ? 10 : 0)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !pressed {
                        pressed = true
                        state.activeKey = key.id
                        holdTask = Task {
                            try? await Task.sleep(for: .seconds(settings.longPress))
                            if !Task.isCancelled { holding = true }
                        }
                    }
                    direction = Self.direction(value.translation, threshold: settings.flickThreshold)
                }
                .onEnded { value in
                    let direction = Self.direction(value.translation, threshold: settings.flickThreshold)
                    holdTask?.cancel()
                    pressed = false
                    holding = false
                    self.direction = .center
                    state.activeKey = nil
                    if direction == .center { state.tap(key) } else { state.flick(key, direction) }
                }
        )
    }

    private var popupText: String? {
        if case .text(let text) = key.output(.center) { return text }
        return nil
    }

    @ViewBuilder
    private func label(_ settings: KeykieKeyboardSettings) -> some View {
        let size = settings.fontSize
        if key.id.hasPrefix("n"), key.id.count == 2 {
            // Digits: the flicks underneath, small.
            VStack(spacing: 1) {
                Text(key.label).font(.system(size: size + 2, weight: .regular))
                Text(key.toggleCycle.dropFirst().joined())
                    .font(.system(size: 9))
                    .opacity(0.55)
                    .lineLimit(1)
            }
        } else {
            Text(key.label)
                .font(.system(size: key.label.count > 2 ? size * 0.72 : size, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
    }

    static func direction(_ translation: CGSize, threshold: CGFloat) -> FlickDirection {
        let dx = translation.width
        let dy = translation.height
        guard max(abs(dx), abs(dy)) >= threshold else { return .center }
        if abs(dx) > abs(dy) { return dx < 0 ? .left : .right }
        return dy < 0 ? .up : .down
    }
}

/// The cross of the key's five characters, the chosen one in the accent color.
struct KeykieFlickGuide: View {
    let key: KeykieKey
    let direction: FlickDirection

    @Environment(KeykieState.self) private var state

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack {
                ForEach(FlickDirection.allCases, id: \.self) { dir in
                    if let output = key.output(dir) {
                        cell(output.label, chosen: dir == direction)
                            .frame(width: w, height: h)
                            .offset(x: dir == .left ? -w : dir == .right ? w : 0,
                                    y: dir == .up ? -h : dir == .down ? h : 0)
                    }
                }
            }
            .frame(width: w, height: h)
        }
        .allowsHitTesting(false)
    }

    private func cell(_ text: String, chosen: Bool) -> some View {
        let palette = state.palette
        return Text(text)
            .font(.system(size: state.settings.fontSize, weight: chosen ? .bold : .regular))
            .lineLimit(1)
            .minimumScaleFactor(0.4)
            .foregroundStyle(chosen ? Color.white : palette.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: state.settings.keyRadius, style: .continuous)
                .fill(chosen ? palette.accent : palette.key)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1))
    }
}

/// The pressed character, enlarged above the key.
struct KeykiePopup: View {
    let text: String
    @Environment(KeykieState.self) private var state

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(.system(size: state.settings.fontSize * 1.5))
                .frame(width: geo.size.width * 1.1, height: geo.size.height)
                .background(RoundedRectangle(cornerRadius: state.settings.keyRadius + 2, style: .continuous)
                    .fill(state.palette.key)
                    .shadow(color: .black.opacity(0.3), radius: 4, y: 1))
                .offset(x: -geo.size.width * 0.05, y: -geo.size.height - 4)
        }
        .allowsHitTesting(false)
    }
}

/// ⌫ and Delete: tap for one character, hold to repeat, swipe for the whole line part.
struct KeykieDeleteKey: View {
    /// Delete (the character after the cursor) instead of ⌫.
    var forward = false

    @Environment(KeykieState.self) private var state
    @State private var pressed = false
    @State private var repeating = false
    @State private var swiped = false
    @State private var repeatTask: Task<Void, Never>?

    var body: some View {
        let settings = state.settings
        let canSwipe = forward ? settings.deleteSwipe : settings.backspaceSwipe
        KeykieKeyFace(special: true, pressed: pressed) {
            if swiped {
                Text(forward ? "行末まで" : "行頭まで")
                    .font(.system(size: 12, weight: .bold))
            } else {
                Image(systemName: forward ? "delete.right" : "delete.left")
                    .font(.system(size: 19))
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if !pressed {
                        pressed = true
                        state.feedback()
                        repeatTask = Task {
                            try? await Task.sleep(for: .seconds(settings.longPress))
                            while !Task.isCancelled {
                                repeating = true
                                act()
                                try? await Task.sleep(for: .milliseconds(70))
                            }
                        }
                    }
                    let dx = value.translation.width
                    if canSwipe, !repeating, (forward ? dx > 36 : dx < -36) {
                        if !swiped { swiped = true; state.selectionFeedback() }
                        repeatTask?.cancel()
                    } else if swiped, abs(dx) < 20 {
                        swiped = false
                    }
                }
                .onEnded { _ in
                    repeatTask?.cancel()
                    if swiped {
                        if forward { state.deleteToLineEnd() } else { state.requestDeleteToLineStart() }
                    } else if !repeating {
                        act()
                    }
                    pressed = false
                    repeating = false
                    swiped = false
                }
        )
    }

    private func act() {
        if forward { state.forwardDelete() } else { state.backspace() }
    }
}

/// 空白: tap for the default width, swipe left for the other; or, when set, drag to move the cursor.
struct KeykieSpaceKey: View {
    @Environment(KeykieState.self) private var state
    @State private var pressed = false
    @State private var moved = 0
    @State private var moving = false

    var body: some View {
        let settings = state.settings
        let converts = state.isComposing && state.mode == .kana && !state.candidates.isEmpty
        KeykieKeyFace(special: true, pressed: pressed) {
            Text(converts ? "変換" : state.mode == .alpha ? "space" : "空白")
                .font(.system(size: 15))
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    pressed = true
                    guard settings.spaceCursor, !state.isComposing else { return }
                    let steps = Int(value.translation.width / settings.cursorStep)
                    if steps != moved {
                        state.moveCursor(steps - moved)
                        moved = steps
                        moving = true
                    }
                }
                .onEnded { value in
                    defer { pressed = false; moved = 0; moving = false }
                    if moving { return }
                    let swiped = settings.spaceCursor ? value.translation.height < -30 : value.translation.width < -30
                    state.space(fullWidth: swiped ? !settings.spaceFullWidth : nil)
                }
        )
    }
}

/// 改行 / 確定 (and 検索, 送信… as the field asks).
struct KeykieReturnKey: View {
    @Environment(KeykieState.self) private var state

    var body: some View {
        let label = state.isComposing || state.isSearchingEmoji ? "確定" : state.returnLabel
        Button { state.returnKey() } label: {
            Text(label).font(.system(size: 15, weight: .semibold))
        }
        .buttonStyle(KeykieKeyButtonStyle(accent: label != "改行"))
    }
}

/// The 12-key board: Delete / 123 / あA / emoji on the left, ⌫ / 空白 / 改行 on the right.
struct KeykieFlickBoard: View {
    let rows: [[KeykieKey]]

    @Environment(KeykieState.self) private var state

    var body: some View {
        let sp = state.spacing
        let h = state.settings.keyHeight
        GeometryReader { geo in
            let side = (geo.size.width - sp * 6) * 0.16
            let right = (geo.size.width - sp * 6) * 0.19
            HStack(alignment: .top, spacing: sp) {
                VStack(spacing: sp) {
                    KeykieDeleteKey(forward: true).frame(height: h)
                    Button { state.toggleNumber() } label: {
                        Text(state.mode == .number ? (state.textMode == .kana ? "あいう" : "ABC") : "☆123")
                            .font(.system(size: 14))
                    }
                    .buttonStyle(KeykieKeyButtonStyle())
                    .frame(height: h)
                    Button { state.toggleKanaAlpha() } label: { kanaAlphaLabel }
                        .buttonStyle(KeykieKeyButtonStyle())
                        .frame(height: h)
                    KeykieEmojiKey().frame(height: h)
                }
                .frame(width: side)

                VStack(spacing: sp) {
                    ForEach(rows.indices, id: \.self) { index in
                        HStack(spacing: sp) {
                            ForEach(rows[index]) { key in
                                KeykieFlickKey(key: key)
                            }
                        }
                        .frame(height: h)
                        .zIndex(rows[index].contains(where: { $0.id == state.activeKey }) ? 10 : 0)
                    }
                }
                .zIndex(1)

                VStack(spacing: sp) {
                    KeykieDeleteKey().frame(height: h)
                    KeykieSpaceKey().frame(height: h)
                    KeykieReturnKey().frame(height: h * 2 + sp)
                }
                .frame(width: right)
            }
            .padding(sp)
        }
    }

    private var kanaAlphaLabel: some View {
        let kana = state.textMode == .kana
        return HStack(spacing: 1) {
            Text("あ").fontWeight(kana ? .bold : .regular).opacity(kana ? 1 : 0.45)
            Text("/").opacity(0.45)
            Text("A").fontWeight(kana ? .regular : .bold).opacity(kana ? 0.45 : 1)
        }
        .font(.system(size: 15))
    }
}

/// The emoji board's key; holding it switches to the next keyboard.
struct KeykieEmojiKey: View {
    @Environment(KeykieState.self) private var state
    @State private var longPressed = false

    var body: some View {
        Button {
            if longPressed { longPressed = false } else { state.toggleEmoji() }
        } label: {
            Image(systemName: state.mode == .emoji || state.isSearchingEmoji ? "character" : "face.smiling")
                .font(.system(size: 18))
        }
        .buttonStyle(KeykieKeyButtonStyle())
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in
            longPressed = true
            state.nextKeyboard()
        })
    }
}

// MARK: - QWERTY

struct KeykieQwertyBoard: View {
    /// Japanese (ローマ字) instead of English.
    let romaji: Bool

    @Environment(KeykieState.self) private var state

    var body: some View {
        let sp = state.spacing
        let h = state.settings.keyHeight
        GeometryReader { geo in
            let unit = (geo.size.width - sp * 11) / 10
            VStack(spacing: sp) {
                row(KeykieLayout.qwertyRows[0], unit: unit).frame(height: h)
                row(KeykieLayout.qwertyRows[1] + (romaji ? ["ー"] : []), unit: unit).frame(height: h)
                HStack(spacing: sp) {
                    if romaji {
                        Button { state.type(state.settings.punctuation.0) } label: { Text(state.settings.punctuation.0) }
                            .buttonStyle(KeykieKeyButtonStyle())
                            .frame(width: unit * 1.4)
                    } else {
                        Button { shiftTapped() } label: {
                            Image(systemName: state.capsLock ? "capslock.fill" : state.shift ? "shift.fill" : "shift")
                        }
                        .buttonStyle(KeykieKeyButtonStyle())
                        .frame(width: unit * 1.4)
                    }
                    Spacer(minLength: 0)
                    row(KeykieLayout.qwertyRows[2], unit: unit)
                    Spacer(minLength: 0)
                    KeykieDeleteKey().frame(width: unit * 1.4)
                }
                .frame(height: h)
                HStack(spacing: sp) {
                    Button { state.toggleNumber() } label: { Text("123").font(.system(size: 14)) }
                        .buttonStyle(KeykieKeyButtonStyle())
                        .frame(width: unit * 1.2)
                    Button { state.toggleKanaAlpha() } label: { Text(romaji ? "A" : "あ").font(.system(size: 15)) }
                        .buttonStyle(KeykieKeyButtonStyle())
                        .frame(width: unit * 1.2)
                    KeykieEmojiKey().frame(width: unit * 1.2)
                    KeykieSpaceKey()
                    Button { state.type(romaji ? state.settings.punctuation.1 : ".") } label: {
                        Text(romaji ? state.settings.punctuation.1 : ".")
                    }
                    .buttonStyle(KeykieKeyButtonStyle(special: false))
                    .frame(width: unit)
                    KeykieReturnKey().frame(width: unit * 2)
                }
                .frame(height: h)
            }
            .padding(sp)
        }
    }

    @State private var lastShift = Date.distantPast

    private func shiftTapped() {
        state.feedback()
        let now = Date()
        if now.timeIntervalSince(lastShift) < 0.35 {
            state.capsLock = true
            state.shift = true
        } else if state.capsLock {
            state.capsLock = false
            state.shift = false
        } else {
            state.shift.toggle()
        }
        lastShift = now
    }

    private func row(_ letters: [String], unit: CGFloat) -> some View {
        HStack(spacing: state.spacing) {
            ForEach(letters, id: \.self) { letter in
                KeykieLetterKey(letter: letter)
                    .frame(width: unit)
            }
        }
    }
}

struct KeykieLetterKey: View {
    let letter: String

    @Environment(KeykieState.self) private var state
    @State private var pressed = false

    var body: some View {
        let shown = state.shift || state.capsLock ? letter.uppercased() : letter
        KeykieKeyFace(pressed: pressed) {
            Text(shown).font(.system(size: state.settings.fontSize))
        }
        .overlay {
            if pressed, state.settings.keyPopup { KeykiePopup(text: shown) }
        }
        .zIndex(pressed ? 10 : 0)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in
                    pressed = false
                    if letter == "ー" { state.type("-") } else { state.typeLetter(letter) }
                }
        )
    }
}
