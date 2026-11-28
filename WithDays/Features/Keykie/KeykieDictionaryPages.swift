import SwiftUI
import UniformTypeIdentifiers

private let kkStore = KeykieGroup.defaults

/// ユーザー辞書, 定型文 and the trending words.
struct KeykieDictionarySettings: View {
    @AppStorage(KK.trendingEnabled, store: kkStore) private var trendingEnabled = true
    @AppStorage(KK.trendingInterval, store: kkStore) private var trendingInterval = 1
    @AppStorage(KK.trendingURL, store: kkStore) private var trendingURL = KK.defaultTrendingURL
    @AppStorage(KK.trendingUpdated, store: kkStore) private var trendingUpdated = 0.0
    @State private var updating = false
    @State private var result: String?
    @State private var trendingCount = 0

    var body: some View {
        Form {
            Section {
                NavigationLink { KeykieUserDictionaryView() } label: {
                    LabeledContent("ユーザー辞書", value: "\(KeykieDictionary.userWords().count)語")
                }
                NavigationLink { KeykiePhrasesView() } label: {
                    LabeledContent("定型文", value: "\(KeykieDictionary.phrases().count)件")
                }
            } footer: {
                Text("定型文は、キーボードのクリップボードボタンから入力できます。")
            }

            Section {
                Toggle("流行語辞書を自動で更新", isOn: $trendingEnabled)
                Picker("更新の頻度", selection: $trendingInterval) {
                    Text("毎日").tag(1)
                    Text("毎週").tag(7)
                    Text("手動のみ").tag(0)
                }
                .disabled(!trendingEnabled)
                LabeledContent("最終更新", value: trendingUpdated == 0 ? "まだ" : Self.date(trendingUpdated))
                LabeledContent("収録", value: "\(trendingCount)語")
                Button {
                    update()
                } label: {
                    HStack {
                        Text("今すぐ更新")
                        if updating { Spacer(); ProgressView() }
                    }
                }
                .disabled(updating)
                if let result {
                    Text(result).font(.system(size: 13)).foregroundStyle(.secondary)
                }
            } header: {
                Text("流行語辞書")
            } footer: {
                Text("Wikipedia日本語版で急に読まれ始めた記事の名前を、毎日まとめたものです。WithDays を開いたときと、フルアクセスのある Keykie を開いたときに、設定した頻度で取り込みます。")
            }

            Section {
                TextField("URL", text: $trendingURL, axis: .vertical)
                    .font(.system(size: 13, design: .monospaced))
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if trendingURL != KK.defaultTrendingURL {
                    Button("初期のURLに戻す") { trendingURL = KK.defaultTrendingURL }
                }
            } header: {
                Text("更新URL")
            } footer: {
                Text("trending.json（{\"words\":[{\"reading\",\"word\",\"pos\"}]}）か、読み,表記,品詞 のCSVを置いたURLです。")
            }
        }
        .navigationTitle("辞書")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { trendingCount = KeykieDictionary.trendingWords().count }
    }

    private func update() {
        updating = true
        result = nil
        Task {
            do {
                let count = try await KeykieDictionary.updateTrending()
                result = "\(count)語を取り込みました"
            } catch {
                result = "更新できませんでした：\(error.localizedDescription)"
            }
            trendingCount = KeykieDictionary.trendingWords().count
            updating = false
        }
    }

    static func date(_ time: Double) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.dateFormat = "yyyy/M/d H:mm"
        return formatter.string(from: Date(timeIntervalSince1970: time))
    }
}

// MARK: - ユーザー辞書

struct KeykieUserDictionaryView: View {
    @State private var words: [KeykieUserWord] = []
    @State private var editing: KeykieUserWord?
    @State private var search = ""
    @State private var importing = false
    @State private var exporting = false
    @State private var message: String?

    private var shown: [KeykieUserWord] {
        let list = words.sorted { $0.reading < $1.reading }
        guard !search.isEmpty else { return list }
        return list.filter { $0.reading.contains(search) || $0.word.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            ForEach(shown) { word in
                Button { editing = word } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(word.word).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                        Text("\(word.reading)・\(word.pos.rawValue)").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { save(words.filter { $0.id != word.id }) } label: { Image(systemName: "trash") }
                }
            }
        }
        .searchable(text: $search, prompt: "読み・表記")
        .overlay {
            if words.isEmpty {
                ContentUnavailableView("単語はまだありません", systemImage: "character.book.closed",
                                       description: Text("＋で読みと表記を登録すると、変換候補に出ます。"))
            }
        }
        .navigationTitle("ユーザー辞書")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { importing = true } label: { Label("CSVを読み込む", systemImage: "square.and.arrow.down") }
                    Button { exporting = true } label: { Label("CSVを書き出す", systemImage: "square.and.arrow.up") }
                        .disabled(words.isEmpty)
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = KeykieUserWord(reading: "", word: "") } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { word in
            KeykieWordEditor(word: word) { saved in
                var list = words
                if let index = list.firstIndex(where: { $0.id == saved.id }) { list[index] = saved } else { list.append(saved) }
                save(list)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.commaSeparatedText, .plainText, .tabSeparatedText]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .shiftJIS) else {
                message = "ファイルを読めませんでした"
                return
            }
            let imported = KeykieDictionary.parseCSV(text)
            let existing = Set(words.map { "\($0.reading)\t\($0.word)" })
            let added = imported.filter { !existing.contains("\($0.reading)\t\($0.word)") }
            save(words + added)
            message = "\(added.count)語を追加しました（同じ読みと表記の\(imported.count - added.count)語は飛ばしました）"
        }
        .fileExporter(isPresented: $exporting, document: KeykieBackupFile(data: Data(KeykieDictionary.csv(words).utf8)),
                      contentType: .commaSeparatedText, defaultFilename: "Keykie-userdict") { _ in }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        }
        .onAppear { words = KeykieDictionary.userWords() }
    }

    private func save(_ list: [KeykieUserWord]) {
        words = list
        KeykieDictionary.saveUserWords(list)
    }
}

struct KeykieWordEditor: View {
    @State var word: KeykieUserWord
    var onSave: (KeykieUserWord) -> Void
    @Environment(\.dismiss) private var dismiss

    private var valid: Bool {
        let reading = KeykieDictionary.hiragana(word.reading.trimmingCharacters(in: .whitespaces))
        return !reading.isEmpty && !word.word.trimmingCharacters(in: .whitespaces).isEmpty
            && reading.unicodeScalars.allSatisfy { (0x3041...0x3096).contains($0.value) || $0.value == 0x30FC }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("読み（ひらがな）", text: $word.reading)
                    TextField("表記", text: $word.word)
                    Picker("品詞", selection: $word.pos) {
                        ForEach(KeykiePOS.allCases) { Text($0.rawValue).tag($0) }
                    }
                } footer: {
                    if !word.reading.isEmpty && !valid {
                        Text("読みはひらがなで入れてください")
                    }
                }
            }
            .navigationTitle(word.word.isEmpty ? "単語を登録" : word.word)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var saved = word
                        saved.reading = KeykieDictionary.hiragana(saved.reading.trimmingCharacters(in: .whitespaces))
                        saved.word = saved.word.trimmingCharacters(in: .whitespaces)
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(!valid)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - 定型文

struct KeykiePhrasesView: View {
    @State private var phrases: [KeykiePhrase] = []
    @State private var editing: KeykiePhrase?

    var body: some View {
        List {
            ForEach(phrases) { phrase in
                Button { editing = phrase } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(phrase.title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                        Text(phrase.body).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .onDelete { offsets in
                var list = phrases
                list.remove(atOffsets: offsets)
                save(list)
            }
            .onMove { from, to in
                var list = phrases
                list.move(fromOffsets: from, toOffset: to)
                save(list)
            }
        }
        .overlay {
            if phrases.isEmpty {
                ContentUnavailableView("定型文はまだありません", systemImage: "text.quote",
                                       description: Text("よく使う文章を登録しておくと、キーボードからすぐ入力できます。"))
            }
        }
        .navigationTitle("定型文")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().disabled(phrases.isEmpty) }
            ToolbarItem(placement: .topBarTrailing) {
                Button { editing = KeykiePhrase(title: "", body: "") } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { phrase in
            KeykiePhraseEditor(phrase: phrase) { saved in
                var list = phrases
                if let index = list.firstIndex(where: { $0.id == saved.id }) { list[index] = saved } else { list.append(saved) }
                save(list)
            }
        }
        .onAppear { phrases = KeykieDictionary.phrases() }
    }

    private func save(_ list: [KeykiePhrase]) {
        phrases = list
        KeykieDictionary.savePhrases(list)
    }
}

struct KeykiePhraseEditor: View {
    @State var phrase: KeykiePhrase
    var onSave: (KeykiePhrase) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                TextField("タイトル", text: $phrase.title)
                TextField("本文", text: $phrase.body, axis: .vertical)
                    .lineLimit(4...12)
            }
            .navigationTitle(phrase.title.isEmpty ? "定型文" : phrase.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var saved = phrase
                        if saved.title.trimmingCharacters(in: .whitespaces).isEmpty {
                            saved.title = String(saved.body.prefix(16))
                        }
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(phrase.body.isEmpty)
                }
            }
        }
    }
}
