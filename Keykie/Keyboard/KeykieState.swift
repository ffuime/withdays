import AudioToolbox
import KanaKanjiConverterModuleWithDefaultDictionary
import SwiftUI
import UIKit

/// Everything the keyboard does: composing and converting, the editing keys and gestures, the clipboard.
@MainActor @Observable
final class KeykieState {
    enum Mode { case kana, alpha, number, emoji }

    @ObservationIgnored weak var controller: KeykieViewController?
    @ObservationIgnored private let converter = KeykieConverter()

    var settings = KeykieKeyboardSettings.load()
    var hasFullAccess = false
    var mode: Mode = .kana
    /// The board to go back to from 123 / emoji.
    var textMode: Mode = .kana

    // Composing
    private(set) var composing = ComposingText()
    var candidates: [Candidate] = []
    /// The candidate the space key stepped to.
    var selected: Int?
    var showAllCandidates = false
    @ObservationIgnored private var requestID = 0

    // Toggle input (the same key tapped again)
    @ObservationIgnored private var lastTap: (key: String, index: Int, time: Date)?

    // QWERTY
    var shift = false
    var capsLock = false

    // Line deletion
    var confirmingLineDelete = false
    var undoText: String?
    @ObservationIgnored private var undoAfterCursor = false
    @ObservationIgnored private var undoTask: Task<Void, Never>?

    // Clipboard
    var showClipboard = false
    var clips: [KeykieClip] = []
    var phrases: [KeykiePhrase] = []

    // Emoji
    var emojiQuery: String?
    var emojiResults: [String] = []
    var recentEmoji: [String] = []

    var returnLabel = "改行"
    var dark = false
    @ObservationIgnored var backgroundImage: UIImage?
    @ObservationIgnored private var imageRevision: Double = -1

    /// Which key is pressed, so its row and guide draw above the others.
    var activeKey: String?

    init() {}

    var proxy: UITextDocumentProxy? { controller?.textDocumentProxy }
    var isComposing: Bool { !composing.convertTarget.isEmpty }
    var composingText: String { composing.convertTarget }
    var isSearchingEmoji: Bool { emojiQuery != nil }
    private var isRomaji: Bool { mode == .kana && settings.japaneseQwerty }
    private var isEnglish: Bool { mode == .alpha }

    // MARK: Appearing

    func appeared() {
        settings = KeykieKeyboardSettings.load()
        hasFullAccess = controller?.hasFullAccess ?? false
        let defaults = KeykieGroup.defaults
        defaults.set(Date().timeIntervalSince1970, forKey: KK.lastSeen)
        defaults.set(hasFullAccess, forKey: KK.fullAccess)
        let revision = defaults.double(forKey: KK.revision)
        converter.reloadDictionaryIfNeeded(revision: revision)
        if revision != imageRevision {
            imageRevision = revision
            backgroundImage = Self.loadBackground()
        }
        recentEmoji = defaults.stringArray(forKey: KK.recentEmoji) ?? []
        clips = KeykieClipboard.load()
        phrases = KeykieDictionary.phrases()
        checkPasteboard()
        refreshContext()
        if hasFullAccess, KeykieDictionary.trendingIsDue {
            Task {
                if (try? await KeykieDictionary.updateTrending()) != nil {
                    converter.reloadDictionaryIfNeeded(revision: KeykieGroup.defaults.double(forKey: KK.revision))
                }
            }
        }
    }

    private static func loadBackground() -> UIImage? {
        guard KeykieGroup.defaults.bool(forKey: KK.backgroundImage),
              let image = UIImage(contentsOfFile: KeykieGroup.file("background.jpg").path) else { return nil }
        // Kept small: the extension has little memory.
        let width: CGFloat = 900
        guard image.size.width > width else { return image }
        let size = CGSize(width: width, height: image.size.height * width / image.size.width)
        return UIGraphicsImageRenderer(size: size).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
    }

    func disappeared() {
        if isComposing { commitRaw() }
        showClipboard = false
        showAllCandidates = false
        emojiQuery = nil
    }

    /// The host's text changed (or the cursor moved): the return key's label and the shift state follow.
    func refreshContext() {
        guard let proxy else { return }
        switch proxy.returnKeyType ?? .default {
        case .search, .google, .yahoo: returnLabel = "検索"
        case .go: returnLabel = "開く"
        case .send: returnLabel = "送信"
        case .done: returnLabel = "完了"
        case .next: returnLabel = "次へ"
        case .join: returnLabel = "参加"
        default: returnLabel = "改行"
        }
        if settings.englishQwerty, mode == .alpha, !capsLock {
            shift = shouldCapitalize
        }
    }

    // MARK: Keys

    func tap(_ key: KeykieKey) {
        feedback()
        let now = Date()
        let cycle = key.toggleCycle
        if settings.toggleInput, cycle.count > 1, let last = lastTap, last.key == key.id,
           now.timeIntervalSince(last.time) < 1.0, let previous = cycle[safe: last.index] {
            let index = (last.index + 1) % cycle.count
            replaceLast(previous, with: cycle[index])
            lastTap = (key.id, index, now)
            return
        }
        lastTap = nil
        guard let output = key.output(.center) else { return }
        perform(output)
        if case .text = output { lastTap = (key.id, 0, now) }
    }

    func flick(_ key: KeykieKey, _ direction: FlickDirection) {
        guard direction != .center else { return tap(key) }
        feedback()
        lastTap = nil
        guard let output = key.output(direction) else { return }
        perform(output)
    }

    private func perform(_ output: KeyOutput) {
        switch output {
        case .text(let text):
            if mode == .alpha, text.count == 1, text.first?.isLetter == true, shouldCapitalize {
                type(text.uppercased())
            } else {
                type(text)
            }
        case .cycleModifier:
            modifyLast { KeykieKana.cycled($0) }
        case .dakuten, .handakuten, .small:
            modifyLast { KeykieKana.variant($0, output) }
        case .caseToggle:
            modifyLast { $0.isLetter ? KeykieKana.toggledCase($0) : nil }
        }
    }

    /// A QWERTY letter: shifted when shift or caps lock is on.
    func typeLetter(_ letter: String) {
        feedback()
        lastTap = nil
        let text = shift || capsLock ? letter.uppercased() : letter
        type(text)
        if shift, !capsLock { shift = false }
    }

    /// Text from a key: into the composition (kana, or letters with English candidates), else straight in.
    func type(_ text: String) {
        if let query = emojiQuery {
            emojiQuery = query + text
            searchEmoji()
            return
        }
        if let selected, candidates.indices.contains(selected) {
            commit(candidates[selected])
        }
        switch mode {
        case .kana:
            composing.insertAtCursorPosition(text, inputStyle: isRomaji ? .roman2kana : .direct)
            composingChanged()
        case .alpha where settings.englishCandidates && text.allSatisfy({ $0.isLetter || $0 == "'" || $0 == "-" }):
            composing.insertAtCursorPosition(text, inputStyle: .direct)
            composingChanged()
        default:
            if isComposing { commitRaw() }
            proxy?.insertText(text)
        }
    }

    /// The text before the cursor, composition included.
    private var lastCharacter: Character? {
        if let query = emojiQuery { return query.last }
        if isComposing { return composing.convertTargetBeforeCursor.last }
        return proxy?.documentContextBeforeInput?.last
    }

    private func modifyLast(_ transform: (Character) -> Character?) {
        guard let last = lastCharacter, let new = transform(last) else { return }
        replaceLast(String(last), with: String(new))
    }

    private func replaceLast(_ old: String, with new: String) {
        if var query = emojiQuery {
            if query.hasSuffix(old) { query.removeLast(old.count) }
            emojiQuery = query + new
            searchEmoji()
        } else if isComposing {
            selected = nil
            composing.deleteBackwardFromCursorPosition(count: old.count)
            composing.insertAtCursorPosition(new, inputStyle: .direct)
            composingChanged()
        } else {
            for _ in 0..<old.count { proxy?.deleteBackward() }
            proxy?.insertText(new)
        }
    }

    private var shouldCapitalize: Bool {
        guard mode == .alpha, settings.autoCapitalize, emojiQuery == nil, !isComposing, let proxy else { return false }
        switch proxy.autocapitalizationType ?? .sentences {
        case .none: return false
        case .allCharacters: return true
        case .words:
            let before = proxy.documentContextBeforeInput ?? ""
            return before.isEmpty || before.last?.isWhitespace == true
        default:
            let before = proxy.documentContextBeforeInput ?? ""
            if before.isEmpty || before.hasSuffix("\n") { return true }
            let trimmed = before.trimmingCharacters(in: .whitespaces)
            return before.last == " " && (trimmed.hasSuffix(".") || trimmed.hasSuffix("!") || trimmed.hasSuffix("?"))
        }
    }

    // MARK: Composition

    private func composingChanged() {
        if !isComposing {
            proxy?.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            proxy?.unmarkText()
            candidates = []
            selected = nil
            showAllCandidates = false
            converter.stop()
            return
        }
        updateMarkedText()
        requestCandidates()
    }

    private func updateMarkedText() {
        let text = selected.flatMap { candidates[safe: $0]?.text } ?? composing.convertTarget
        let cursor = selected == nil ? composing.convertTargetBeforeCursor.utf16.count : text.utf16.count
        proxy?.setMarkedText(text, selectedRange: NSRange(location: cursor, length: 0))
    }

    private func requestCandidates() {
        requestID += 1
        let id = requestID
        let text = composing
        let options = KeykieConverter.Options(
            english: isEnglish, prediction: settings.prediction, learning: settings.learning,
            englishCandidates: settings.englishCandidates, spellCheck: settings.spellCheck)
        Task {
            let results = await converter.candidates(for: text, options: options)
            guard id == requestID else { return }
            candidates = results
        }
    }

    func commit(_ candidate: Candidate) {
        feedback()
        let text = candidate.text
        proxy?.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
        proxy?.unmarkText()
        composing.prefixComplete(composingCount: candidate.composingCount)
        let finished = !isComposing
        converter.commit(candidate, learning: settings.learning, finished: finished)
        for action in candidate.actions {
            if case .moveCursor(let offset) = action { proxy?.adjustTextPosition(byCharacterOffset: offset) }
        }
        selected = nil
        showAllCandidates = false
        if finished {
            composing = ComposingText()
            candidates = []
        } else {
            updateMarkedText()
            requestCandidates()
        }
    }

    /// The composition as typed (確定 without converting).
    func commitRaw() {
        if let selected, let candidate = candidates[safe: selected] { return commit(candidate) }
        let text = composing.convertTarget
        proxy?.setMarkedText(text, selectedRange: NSRange(location: text.utf16.count, length: 0))
        proxy?.unmarkText()
        composing = ComposingText()
        candidates = []
        selected = nil
        showAllCandidates = false
        converter.stop()
    }

    func cancelComposition() {
        composing = ComposingText()
        composingChanged()
    }

    // MARK: Space, return

    func space(fullWidth: Bool? = nil) {
        feedback()
        lastTap = nil
        if let query = emojiQuery {
            emojiQuery = query + " "
            return searchEmoji()
        }
        let full = fullWidth ?? settings.spaceFullWidth
        if isComposing {
            if mode == .alpha {
                commitRaw()
                proxy?.insertText(" ")
            } else if !candidates.isEmpty {
                // 変換: step through the candidates.
                selected = ((selected ?? -1) + 1) % candidates.count
                updateMarkedText()
            } else {
                commitRaw()
                proxy?.insertText(full ? "　" : " ")
            }
            return
        }
        proxy?.insertText(mode == .alpha ? " " : (full ? "　" : " "))
    }

    func returnKey() {
        feedback()
        lastTap = nil
        if emojiQuery != nil { return endEmojiSearch() }
        if isComposing { return commitRaw() }
        proxy?.insertText("\n")
    }

    // MARK: Deleting

    /// ⌫: the character before the cursor (or of the composition).
    func backspace() {
        lastTap = nil
        if var query = emojiQuery {
            if !query.isEmpty { query.removeLast() }
            emojiQuery = query
            return searchEmoji()
        }
        if isComposing {
            if selected != nil {
                selected = nil
                updateMarkedText()
                return
            }
            composing.deleteBackwardFromCursorPosition(count: 1)
            return composingChanged()
        }
        proxy?.deleteBackward()
    }

    /// Delete: the character after the cursor, Windows style. The proxy has no forward delete, so the
    /// cursor steps over the character and deletes backward.
    func forwardDelete() {
        lastTap = nil
        if emojiQuery != nil { return }
        if isComposing {
            if composing.isAtEndIndex { return }
            composing.deleteForwardFromCursorPosition(count: 1)
            return composingChanged()
        }
        guard let proxy, let next = proxy.documentContextAfterInput?.first else { return }
        proxy.adjustTextPosition(byCharacterOffset: next.utf16.count)
        proxy.deleteBackward()
    }

    /// ⌫ swiped left: back to the start of the line (at the start, just the line break before it).
    func requestDeleteToLineStart() {
        guard settings.backspaceSwipe else { return }
        if isComposing { return cancelComposition() }
        if settings.backspaceConfirm {
            confirmingLineDelete = true
        } else {
            deleteToLineStart()
        }
    }

    func deleteToLineStart() {
        confirmingLineDelete = false
        guard let proxy else { return }
        feedback()
        var removed = ""
        let first = proxy.documentContextBeforeInput ?? ""
        if first.isEmpty { return }
        if first.hasSuffix("\n") {
            proxy.deleteBackward()
            removed = "\n"
        } else {
            // The context is only part of the text, so read again after each part until a line break shows.
            var previous: String?
            for _ in 0..<40 {
                let context = proxy.documentContextBeforeInput ?? ""
                if context.isEmpty || context == previous { break }
                previous = context
                let line: Substring
                if let newline = context.lastIndex(of: "\n") {
                    line = context[context.index(after: newline)...]
                } else {
                    line = context[...]
                }
                if line.isEmpty { break }
                for _ in 0..<line.count { proxy.deleteBackward() }
                removed = String(line) + removed
                if context.contains("\n") { break }
            }
        }
        offerUndo(removed, afterCursor: false)
    }

    /// Delete swiped right: to the end of the line (at the end, just the line break after it).
    func deleteToLineEnd() {
        guard settings.deleteSwipe, let proxy, emojiQuery == nil else { return }
        if isComposing { return cancelComposition() }
        feedback()
        var removed = ""
        let first = proxy.documentContextAfterInput ?? ""
        if first.isEmpty { return }
        if first.hasPrefix("\n") {
            proxy.adjustTextPosition(byCharacterOffset: 1)
            proxy.deleteBackward()
            removed = "\n"
        } else {
            var previous: String?
            for _ in 0..<40 {
                let context = proxy.documentContextAfterInput ?? ""
                if context.isEmpty || context == previous { break }
                previous = context
                let line = context.prefix { $0 != "\n" }
                if line.isEmpty { break }
                proxy.adjustTextPosition(byCharacterOffset: line.utf16.count)
                for _ in 0..<line.count { proxy.deleteBackward() }
                removed += line
                if context.contains("\n") { break }
            }
        }
        offerUndo(removed, afterCursor: true)
    }

    private func offerUndo(_ text: String, afterCursor: Bool) {
        guard settings.backspaceUndo, !text.isEmpty else { return }
        undoText = text
        undoAfterCursor = afterCursor
        undoTask?.cancel()
        undoTask = Task {
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { undoText = nil }
        }
    }

    func undoDelete() {
        guard let text = undoText, let proxy else { return }
        feedback()
        proxy.insertText(text)
        if undoAfterCursor { proxy.adjustTextPosition(byCharacterOffset: -text.utf16.count) }
        undoTask?.cancel()
        undoText = nil
    }

    // MARK: Cursor

    /// Moves the cursor a character at a time (only when nothing is being composed).
    func moveCursor(_ steps: Int) {
        guard let proxy, steps != 0, !isComposing else { return }
        for _ in 0..<abs(steps) {
            let offset: Int
            if steps > 0 {
                guard let next = proxy.documentContextAfterInput?.first else { break }
                offset = next.utf16.count
            } else {
                guard let previous = proxy.documentContextBeforeInput?.last else { break }
                offset = -previous.utf16.count
            }
            proxy.adjustTextPosition(byCharacterOffset: offset)
        }
        selectionFeedback()
    }

    // MARK: Modes

    func toggleNumber() {
        feedback()
        if isComposing { commitRaw() }
        mode = mode == .number ? textMode : .number
    }

    func toggleKanaAlpha() {
        feedback()
        if isComposing { commitRaw() }
        textMode = textMode == .kana ? .alpha : .kana
        mode = textMode
        shift = false
        capsLock = false
        refreshContext()
    }

    func toggleEmoji() {
        feedback()
        if emojiQuery != nil { return endEmojiSearch() }
        if isComposing { commitRaw() }
        mode = mode == .emoji ? textMode : .emoji
    }

    // MARK: Emoji

    func insertEmoji(_ emoji: String) {
        feedback()
        if emojiQuery != nil { endEmojiSearch() }
        proxy?.insertText(emoji)
        recentEmoji.removeAll { $0 == emoji }
        recentEmoji.insert(emoji, at: 0)
        recentEmoji = Array(recentEmoji.prefix(40))
        KeykieGroup.defaults.set(recentEmoji, forKey: KK.recentEmoji)
    }

    func startEmojiSearch() {
        feedback()
        emojiQuery = ""
        emojiResults = []
        mode = textMode
    }

    func endEmojiSearch() {
        emojiQuery = nil
        emojiResults = []
        mode = .emoji
    }

    private func searchEmoji() {
        let query = (emojiQuery ?? "").trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { emojiResults = []; return }
        Task {
            var results = await converter.emoji(for: query)
            results += KeykieEmoji.search(query)
            var seen = Set<String>()
            let unique = results.filter { seen.insert($0).inserted }
            if emojiQuery?.trimmingCharacters(in: .whitespaces) == query { emojiResults = unique }
        }
    }

    // MARK: Clipboard

    /// iOS can't watch the pasteboard in the background: this runs when the keyboard appears.
    func checkPasteboard() {
        guard hasFullAccess, KeykieGroup.defaults.bool(forKey: KK.clipEnabled) else { return }
        let pasteboard = UIPasteboard.general
        let count = pasteboard.changeCount
        let defaults = KeykieGroup.defaults
        guard count != defaults.integer(forKey: KK.pasteboardCount) else { return }
        defaults.set(count, forKey: KK.pasteboardCount)
        // Password managers mark what they copy as concealed or transient.
        if defaults.bool(forKey: KK.clipSkipConcealed),
           pasteboard.types.contains(where: { $0 == "org.nspasteboard.ConcealedType" || $0 == "org.nspasteboard.TransientType" }) {
            return
        }
        guard pasteboard.hasStrings, let text = pasteboard.string, KeykieClipboard.accepts(text) else { return }
        clips = KeykieClipboard.add(text, to: clips)
        KeykieClipboard.save(clips)
    }

    func openClipboard() {
        feedback()
        clips = KeykieClipboard.load()
        phrases = KeykieDictionary.phrases()
        withAnimation(.snappy) { showClipboard = true }
    }

    func insertFromClipboard(_ text: String) {
        feedback()
        if isComposing { commitRaw() }
        proxy?.insertText(text)
        withAnimation(.snappy) { showClipboard = false }
    }

    func deleteClip(_ clip: KeykieClip) {
        clips.removeAll { $0.id == clip.id }
        KeykieClipboard.save(clips)
    }

    func togglePin(_ clip: KeykieClip) {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[index].pinned.toggle()
        KeykieClipboard.save(clips)
    }

    /// Everything but the pinned clips.
    func clearClips() {
        clips.removeAll { !$0.pinned }
        KeykieClipboard.save(clips)
    }

    // MARK: Feedback

    @ObservationIgnored private var impact: UIImpactFeedbackGenerator?
    @ObservationIgnored private var impactStyle: UIImpactFeedbackGenerator.FeedbackStyle?

    /// Sound and haptics need full access.
    func feedback() {
        guard hasFullAccess else { return }
        if settings.sound { AudioServicesPlaySystemSound(1104) }
        if settings.haptics {
            let styles: [UIImpactFeedbackGenerator.FeedbackStyle] = [.light, .medium, .heavy]
            let style = styles[min(2, max(0, settings.hapticStrength))]
            if impact == nil || impactStyle != style {
                impact = UIImpactFeedbackGenerator(style: style)
                impactStyle = style
            }
            impact?.impactOccurred()
        }
    }

    func selectionFeedback() {
        guard hasFullAccess, settings.haptics else { return }
        UISelectionFeedbackGenerator().selectionChanged()
    }

    func dismiss() {
        if isComposing { commitRaw() }
        controller?.dismissKeyboard()
    }

    func nextKeyboard() {
        controller?.advanceToNextInputMode()
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
