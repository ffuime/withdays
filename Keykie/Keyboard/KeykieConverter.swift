import Foundation
import KanaKanjiConverterModuleWithDefaultDictionary

/// azooKey's converter on a queue of its own, so conversion never blocks the keys.
/// The dictionary is read from disk as it is needed (no preload), which keeps the extension's memory low.
final class KeykieConverter: @unchecked Sendable {
    private let queue = DispatchQueue(label: "keykie.converter", qos: .userInitiated)
    private var converter: KanaKanjiConverter?
    private var dictionaryRevision: Double = -1
    private lazy var emojiReplacer = TextReplacer.withDefaultEmojiDictionary()

    struct Options {
        var english: Bool
        var prediction: Bool
        var learning: Bool
        var englishCandidates: Bool
        var spellCheck: Bool
    }

    private func make() -> KanaKanjiConverter {
        if let converter { return converter }
        let converter = KanaKanjiConverter.withDefaultDictionary(preloadDictionary: false)
        self.converter = converter
        return converter
    }

    private func requestOptions(_ options: Options) -> ConvertRequestOptions {
        ConvertRequestOptions(
            N_best: 10,
            requireJapanesePrediction: options.prediction && !options.english,
            requireEnglishPrediction: options.english && options.spellCheck,
            keyboardLanguage: options.english ? .en_US : .ja_JP,
            englishCandidateInRoman2KanaInput: options.englishCandidates,
            fullWidthRomanCandidate: !options.english,
            halfWidthKanaCandidate: false,
            learningType: options.learning ? .inputAndOutput : .nothing,
            maxMemoryCount: 65536,
            shouldResetMemory: false,
            memoryDirectoryURL: KeykieGroup.memoryDirectory,
            sharedContainerURL: KeykieGroup.directory,
            textReplacer: emojiReplacer,
            specialCandidateProviders: KanaKanjiConverter.defaultSpecialCandidateProviders,
            metadata: .init(versionString: "Keykie")
        )
    }

    /// Re-reads the user, trending and kaomoji words when the app changed them (or on first use).
    func reloadDictionaryIfNeeded(revision: Double) {
        queue.async { [self] in
            guard revision != dictionaryRevision else { return }
            if dictionaryRevision >= 0 {
                // The app may have reset learning: start a fresh converter.
                converter = nil
            }
            dictionaryRevision = revision
            let converter = make()
            var elements: [DicdataElement] = []
            for word in KeykieDictionary.userWords() {
                elements.append(Self.element(word.word, reading: word.reading, cid: word.pos.cid, value: -5))
            }
            for word in KeykieDictionary.trendingWords() {
                let pos = word.pos.map { KeykiePOS(label: $0) } ?? .properNoun
                elements.append(Self.element(word.word, reading: word.reading, cid: pos.cid, value: -9))
            }
            for (reading, faces) in KeykieKaomoji.all {
                for face in faces {
                    elements.append(Self.element(face, reading: reading, cid: KeykiePOS.symbol.cid, value: -12))
                }
            }
            converter.importDynamicUserDictionary(elements)
        }
    }

    private static func element(_ word: String, reading: String, cid: Int, value: Float) -> DicdataElement {
        DicdataElement(word: word, ruby: KeykieDictionary.katakana(reading), cid: cid, mid: MIDData.一般.mid, value: PValue(value))
    }

    func candidates(for text: ComposingText, options: Options) async -> [Candidate] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                let results = make().requestCandidates(text, options: requestOptions(options))
                continuation.resume(returning: results.mainResults)
            }
        }
    }

    /// After a candidate is chosen: remember it, and save when the whole input is done.
    func commit(_ candidate: Candidate, learning: Bool, finished: Bool) {
        queue.async { [self] in
            let converter = make()
            converter.setCompletedData(candidate)
            if learning { converter.updateLearningData(candidate) }
            if finished {
                if learning { converter.commitUpdateLearningData() }
                converter.stopComposition()
            }
        }
    }

    func stop() {
        queue.async { [self] in converter?.stopComposition() }
    }

    func emoji(for query: String) async -> [String] {
        await withCheckedContinuation { continuation in
            queue.async { [self] in
                continuation.resume(returning: emojiReplacer.getSearchResult(query: query, target: [.emoji]).map(\.text))
            }
        }
    }
}
