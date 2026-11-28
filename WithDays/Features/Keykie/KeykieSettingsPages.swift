import PhotosUI
import SwiftUI

private let kkStore = KeykieGroup.defaults

// MARK: - 入力

struct KeykieInputSettings: View {
    @AppStorage(KK.flickThreshold, store: kkStore) private var flickThreshold = 24.0
    @AppStorage(KK.flickGuide, store: kkStore) private var flickGuide = true
    @AppStorage(KK.longPress, store: kkStore) private var longPress = 0.4
    @AppStorage(KK.toggleInput, store: kkStore) private var toggleInput = true
    @AppStorage(KK.prediction, store: kkStore) private var prediction = true
    @AppStorage(KK.learning, store: kkStore) private var learning = true
    @AppStorage(KK.englishCandidates, store: kkStore) private var englishCandidates = true
    @AppStorage(KK.spellCheck, store: kkStore) private var spellCheck = true
    @AppStorage(KK.spaceFullWidth, store: kkStore) private var spaceFullWidth = false
    @AppStorage(KK.punctuation, store: kkStore) private var punctuation = 0
    @AppStorage(KK.autoCapitalize, store: kkStore) private var autoCapitalize = true
    @AppStorage(KK.japaneseLayout, store: kkStore) private var japaneseLayout = 0
    @AppStorage(KK.englishLayout, store: kkStore) private var englishLayout = 0
    @State private var confirmResetLearning = false
    @State private var learningReset = false

    var body: some View {
        Form {
            Section("配列") {
                Picker("日本語", selection: $japaneseLayout) {
                    Text("フリック").tag(0)
                    Text("ローマ字（QWERTY）").tag(1)
                }
                Picker("英語", selection: $englishLayout) {
                    Text("テンキー").tag(0)
                    Text("QWERTY").tag(1)
                }
            }

            Section {
                keykieSlider("フリック感度", value: $flickThreshold, in: 10...44, step: 2,
                       text: flickThreshold <= 18 ? "敏感" : flickThreshold >= 32 ? "鈍め" : "ふつう")
                Toggle("フリックガイドを表示", isOn: $flickGuide)
                keykieSlider("長押しの時間", value: $longPress, in: 0.2...1.0, step: 0.05, text: String(format: "%.2f秒", longPress))
                Toggle("同じキーを続けて押して文字を進める", isOn: $toggleInput)
            } header: {
                Text("フリック")
            } footer: {
                Text("感度は、どれだけ指を動かしたらフリックとみなすかです。長押しの時間は、ガイドが出るまでと、削除の連続が始まるまでの時間です。")
            }

            Section("変換") {
                Toggle("予測変換", isOn: $prediction)
                Toggle("学習", isOn: $learning)
                Button("学習データをリセット", role: .destructive) { confirmResetLearning = true }
                Toggle("英語の変換候補", isOn: $englishCandidates)
                Toggle("スペルチェック（英語の候補）", isOn: $spellCheck)
            }

            Section("文字") {
                Picker("空白キー", selection: $spaceFullWidth) {
                    Text("半角（左スワイプで全角）").tag(false)
                    Text("全角（左スワイプで半角）").tag(true)
                }
                Picker("句読点", selection: $punctuation) {
                    ForEach(KK.punctuations.indices, id: \.self) { index in
                        Text(KK.punctuations[index].0 + KK.punctuations[index].1).tag(index)
                    }
                }
                Toggle("英語の自動大文字化", isOn: $autoCapitalize)
            }
        }
        .navigationTitle("入力")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("学習した変換をすべて忘れますか？", isPresented: $confirmResetLearning, titleVisibility: .visible) {
            Button("リセット", role: .destructive) {
                KeykieDictionary.resetLearning()
                learningReset = true
            }
        }
        .alert("学習データをリセットしました", isPresented: $learningReset) { Button("OK") {} }
    }
}

// MARK: - ジェスチャー

struct KeykieGestureSettings: View {
    @AppStorage(KK.backspaceSwipe, store: kkStore) private var backspaceSwipe = true
    @AppStorage(KK.backspaceConfirm, store: kkStore) private var backspaceConfirm = false
    @AppStorage(KK.backspaceUndo, store: kkStore) private var backspaceUndo = true
    @AppStorage(KK.deleteSwipe, store: kkStore) private var deleteSwipe = false
    @AppStorage(KK.spaceCursor, store: kkStore) private var spaceCursor = false
    @AppStorage(KK.cursorStep, store: kkStore) private var cursorStep = 12.0
    @AppStorage(KK.candidateSwipe, store: kkStore) private var candidateSwipe = true

    var body: some View {
        Form {
            Section {
                Picker("⌫ の左スワイプ", selection: $backspaceSwipe) {
                    Text("行頭まで削除").tag(true)
                    Text("なし").tag(false)
                }
                Toggle("削除する前に確認", isOn: $backspaceConfirm)
                    .disabled(!backspaceSwipe)
                Toggle("「元に戻す」を表示", isOn: $backspaceUndo)
            } header: {
                Text("⌫（カーソルの左を消す）")
            } footer: {
                Text("行頭で左スワイプすると、前の改行をひとつだけ消します。「元に戻す」は候補バーに5秒ほど出ます。")
            }

            Section {
                Picker("Delete の右スワイプ", selection: $deleteSwipe) {
                    Text("行末まで削除").tag(true)
                    Text("なし").tag(false)
                }
            } header: {
                Text("Delete（カーソルの右を消す）")
            }

            Section {
                Toggle("候補バーをスワイプしてカーソル移動", isOn: $candidateSwipe)
                Picker("空白キーのスワイプ", selection: $spaceCursor) {
                    Text("左で全角／半角").tag(false)
                    Text("左右でカーソル移動").tag(true)
                }
                keykieSlider("カーソル移動の感度", value: $cursorStep, in: 6...30, step: 1,
                       text: cursorStep <= 9 ? "速い" : cursorStep >= 20 ? "ゆっくり" : "ふつう")
            } header: {
                Text("カーソル")
            } footer: {
                Text("空白キーでカーソルを動かすときは、上スワイプで全角／半角の空白になります。")
            }

            Section {
                NavigationLink("数字キーのフリック記号") { KeykieNumberFlickEditor() }
            }
        }
        .navigationTitle("ジェスチャー")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct KeykieNumberFlickEditor: View {
    @AppStorage(KK.numberFlicks, store: kkStore) private var json = ""
    @State private var map: [String: [String]] = [:]

    private static let digits = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"]
    private static let directions = ["左", "上", "右", "下"]

    var body: some View {
        Form {
            ForEach(Self.digits, id: \.self) { digit in
                Section(digit) {
                    HStack(spacing: 8) {
                        ForEach(0..<4, id: \.self) { index in
                            VStack(spacing: 3) {
                                Text(Self.directions[index]).font(.system(size: 11)).foregroundStyle(.secondary)
                                TextField("", text: binding(digit, index))
                                    .multilineTextAlignment(.center)
                                    .font(.system(size: 18))
                                    .frame(height: 34)
                                    .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemFill)))
                            }
                        }
                    }
                }
            }
            Section {
                Button("初期値に戻す", role: .destructive) {
                    json = ""
                    map = KK.defaultNumberFlicks
                }
            }
        }
        .navigationTitle("数字キーの記号")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { map = KK.numberFlicks(json) }
    }

    private func binding(_ digit: String, _ index: Int) -> Binding<String> {
        Binding {
            let list = map[digit] ?? []
            return index < list.count ? list[index] : ""
        } set: { value in
            var list = map[digit] ?? ["", "", "", ""]
            while list.count < 4 { list.append("") }
            // One symbol (a few characters at most) per direction.
            list[index] = String(value.prefix(4))
            map[digit] = list
            json = KK.encodeNumberFlicks(map)
        }
    }
}

// MARK: - 見た目

struct KeykieAppearanceSettings: View {
    @AppStorage(KK.skin, store: kkStore) private var skin = "standard"
    @AppStorage(KK.appearance, store: kkStore) private var appearance = 0
    @AppStorage(KK.colorBackground, store: kkStore) private var colorBackground = 0xD1D4DA
    @AppStorage(KK.colorKey, store: kkStore) private var colorKey = 0xFFFFFF
    @AppStorage(KK.colorSpecialKey, store: kkStore) private var colorSpecialKey = 0xADB2BC
    @AppStorage(KK.colorText, store: kkStore) private var colorText = 0x111111
    @AppStorage(KK.colorAccent, store: kkStore) private var colorAccent = 0x2F7CF6
    @AppStorage(KK.backgroundImage, store: kkStore) private var backgroundImage = false
    @AppStorage(KK.keyRadius, store: kkStore) private var keyRadius = 7.0
    @AppStorage(KK.keyShadow, store: kkStore) private var keyShadow = true
    @AppStorage(KK.keyBorder, store: kkStore) private var keyBorder = false
    @AppStorage(KK.keyHeight, store: kkStore) private var keyHeight = 50.0
    @AppStorage(KK.fontSize, store: kkStore) private var fontSize = 20.0
    @AppStorage(KK.heightScale, store: kkStore) private var heightScale = 1.0
    @AppStorage(KK.oneHanded, store: kkStore) private var oneHanded = 0
    @AppStorage(KK.barHeight, store: kkStore) private var barHeight = 42.0
    @State private var photo: PhotosPickerItem?
    @State private var image: UIImage?

    var body: some View {
        Form {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(KeykieSkin.all) { item in
                            Button { skin = item.id } label: { swatch(item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 6)
                }
                Picker("ダーク／ライト", selection: $appearance) {
                    Text("システムに合わせる").tag(0)
                    Text("ライト").tag(1)
                    Text("ダーク").tag(2)
                }
            } header: {
                Text("スキン")
            }

            if skin == "custom" {
                Section("カスタムの色") {
                    ColorPicker("背景", selection: color($colorBackground), supportsOpacity: false)
                    ColorPicker("キー", selection: color($colorKey), supportsOpacity: false)
                    ColorPicker("機能キー", selection: color($colorSpecialKey), supportsOpacity: false)
                    ColorPicker("文字", selection: color($colorText), supportsOpacity: false)
                    ColorPicker("アクセント", selection: color($colorAccent), supportsOpacity: false)
                }
            }

            Section {
                Toggle("背景画像を使う", isOn: $backgroundImage)
                    .onChange(of: backgroundImage) { KeykieGroup.touch() }
                PhotosPicker(selection: $photo, matching: .images) {
                    Label(image == nil ? "写真を選ぶ" : "写真を変える", systemImage: "photo")
                }
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            } header: {
                Text("背景画像")
            }

            Section("キー") {
                keykieSlider("角丸", value: $keyRadius, in: 0...20, step: 1, text: "\(Int(keyRadius))")
                Toggle("影", isOn: $keyShadow)
                Toggle("枠線", isOn: $keyBorder)
                keykieSlider("キーの高さ", value: $keyHeight, in: 36...70, step: 1, text: "\(Int(keyHeight))pt")
                keykieSlider("文字の大きさ", value: $fontSize, in: 14...28, step: 1, text: "\(Int(fontSize))pt")
            }

            Section("キーボード") {
                keykieSlider("全体の高さ", value: $heightScale, in: 0.8...1.3, step: 0.05, text: "\(Int((heightScale * 100).rounded()))%")
                keykieSlider("候補バーの高さ", value: $barHeight, in: 34...56, step: 1, text: "\(Int(barHeight))pt")
                Picker("片手モード", selection: $oneHanded) {
                    Text("オフ").tag(0)
                    Text("左寄せ").tag(1)
                    Text("右寄せ").tag(2)
                }
            }
        }
        .navigationTitle("見た目")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { image = UIImage(contentsOfFile: KeykieGroup.file("background.jpg").path) }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self), let picked = UIImage(data: data) else { return }
                let width: CGFloat = 1200
                let size = picked.size.width > width
                    ? CGSize(width: width, height: picked.size.height * width / picked.size.width) : picked.size
                let resized = UIGraphicsImageRenderer(size: size).image { _ in picked.draw(in: CGRect(origin: .zero, size: size)) }
                try? resized.jpegData(compressionQuality: 0.8)?.write(to: KeykieGroup.file("background.jpg"), options: .atomic)
                image = resized
                backgroundImage = true
                KeykieGroup.touch()
            }
        }
    }

    private func swatch(_ item: KeykieSkin) -> some View {
        let selected = skin == item.id
        return VStack(spacing: 6) {
            ZStack {
                if item.id == "custom" {
                    RoundedRectangle(cornerRadius: 10).fill(AngularGradient(colors: [.red, .yellow, .green, .blue, .purple, .red], center: .center))
                } else {
                    RoundedRectangle(cornerRadius: 10).fill(Color(hexValue: item.background))
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { index in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(hexValue: index == 2 ? item.accent : item.key))
                                .frame(width: 12, height: 16)
                        }
                    }
                }
            }
            .frame(width: 64, height: 44)
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selected ? Color.accentColor : .secondary.opacity(0.3), lineWidth: selected ? 3 : 1))
            Text(item.name).font(.system(size: 11, weight: selected ? .bold : .regular))
        }
    }

    private func color(_ hex: Binding<Int>) -> Binding<Color> {
        Binding {
            Color(hexValue: hex.wrappedValue)
        } set: { color in
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            UIColor(color).getRed(&r, green: &g, blue: &b, alpha: &a)
            func byte(_ v: CGFloat) -> Int { Int((min(1, max(0, v)) * 255).rounded()) }
            hex.wrappedValue = byte(r) << 16 | byte(g) << 8 | byte(b)
        }
    }
}

private extension Color {
    init(hexValue hex: Int) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - フィードバック

struct KeykieFeedbackSettings: View {
    @AppStorage(KK.sound, store: kkStore) private var sound = false
    @AppStorage(KK.haptics, store: kkStore) private var haptics = true
    @AppStorage(KK.hapticStrength, store: kkStore) private var hapticStrength = 0
    @AppStorage(KK.keyPopup, store: kkStore) private var keyPopup = true

    var body: some View {
        Form {
            Section {
                Toggle("キーの音", isOn: $sound)
                Toggle("振動", isOn: $haptics)
                Picker("振動の強さ", selection: $hapticStrength) {
                    Text("弱").tag(0)
                    Text("中").tag(1)
                    Text("強").tag(2)
                }
                .pickerStyle(.segmented)
                .disabled(!haptics)
            } footer: {
                Text("音と振動にはフルアクセスが必要です。音は iPhone の消音スイッチに従います。")
            }
            Section {
                Toggle("押したキーを大きく表示", isOn: $keyPopup)
            }
        }
        .navigationTitle("フィードバック")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - クリップボード

struct KeykieClipboardSettings: View {
    @AppStorage(KK.clipEnabled, store: kkStore) private var enabled = true
    @AppStorage(KK.clipMax, store: kkStore) private var maxCount = 50
    @AppStorage(KK.clipURLs, store: kkStore) private var urls = true
    @AppStorage(KK.clipMaxLength, store: kkStore) private var maxLength = 5000
    @AppStorage(KK.clipSkipConcealed, store: kkStore) private var skipConcealed = true
    @AppStorage(KK.clipExclude, store: kkStore) private var exclude = ""
    @AppStorage(KK.clipExpireDays, store: kkStore) private var expireDays = 0

    var body: some View {
        Form {
            Section {
                Toggle("クリップボード履歴", isOn: $enabled)
                NavigationLink("履歴を見る") { KeykieClipboardHistory() }
            } footer: {
                Text("iOSの制約で、キーボードが表示されたときとアプリに戻ってきたときにだけ確認します。フルアクセスが必要です。")
            }

            Section("保存") {
                Picker("保存する件数", selection: $maxCount) {
                    ForEach([10, 20, 30, 50, 100, 200, 500], id: \.self) { Text("\($0)件").tag($0) }
                }
                Picker("自動で消すまで", selection: $expireDays) {
                    Text("消さない").tag(0)
                    Text("1日").tag(1)
                    Text("1週間").tag(7)
                    Text("30日").tag(30)
                    Text("90日").tag(90)
                }
                Toggle("URLも保存", isOn: $urls)
                Picker("保存する長さ", selection: $maxLength) {
                    Text("1,000文字まで").tag(1000)
                    Text("5,000文字まで").tag(5000)
                    Text("20,000文字まで").tag(20000)
                    Text("制限なし").tag(0)
                }
            }

            Section {
                Toggle("パスワード管理アプリのコピーは保存しない", isOn: $skipConcealed)
                TextField("1行に1つ。/正規表現/ も使えます", text: $exclude, axis: .vertical)
                    .lineLimit(3...8)
                    .font(.system(size: 15, design: .monospaced))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } header: {
                Text("除外ルール")
            } footer: {
                Text("書いた文字を含むテキストは保存しません。例：「パスワード」、/^[0-9]{6}$/（6桁の確認コード）。ピン留めした項目は件数や期間を超えても残ります。\nコピー元のアプリで除外する設定は、iOSがキーボードにコピー元を教えないため作れません。パスワード管理アプリの多くは、コピーに「秘密」の印を付けるので、上のスイッチで除外できます。")
            }
        }
        .navigationTitle("クリップボード")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct KeykieClipboardHistory: View {
    @State private var clips: [KeykieClip] = []
    @State private var confirmClear = false

    var body: some View {
        List {
            ForEach(clips) { clip in
                HStack(alignment: .top) {
                    Text(clip.text).lineLimit(3)
                    Spacer()
                    if clip.pinned { Image(systemName: "pin.fill").foregroundStyle(.orange).font(.system(size: 12)) }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { update { list in list.removeAll { item in item.id == clip.id } } } label: { Image(systemName: "trash") }
                }
                .swipeActions(edge: .leading) {
                    Button { update { list in
                        if let index = list.firstIndex(where: { $0.id == clip.id }) { list[index].pinned.toggle() }
                    } } label: { Image(systemName: clip.pinned ? "pin.slash" : "pin") }
                    .tint(.orange)
                }
            }
        }
        .overlay {
            if clips.isEmpty {
                ContentUnavailableView("履歴はありません", systemImage: "doc.on.clipboard",
                                       description: Text("Keykie を開いたときにコピーされていたテキストが入ります。"))
            }
        }
        .navigationTitle("クリップボード履歴")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !clips.isEmpty {
                Button("全消去") { confirmClear = true }
            }
        }
        .confirmationDialog("ピン留め以外の履歴を消しますか？", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("消す", role: .destructive) { update { list in list.removeAll { item in !item.pinned } } }
        }
        .onAppear { clips = KeykieClipboard.sorted(KeykieClipboard.load()) }
    }

    private func update(_ change: (inout [KeykieClip]) -> Void) {
        var list = KeykieClipboard.load()
        change(&list)
        KeykieClipboard.save(list)
        clips = KeykieClipboard.sorted(list)
    }
}

// MARK: - Shared

/// A slider with its title and the current value on one line.
func keykieSlider(_ title: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double, text: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        HStack {
            Text(title)
            Spacer()
            Text(text).foregroundStyle(.secondary).monospacedDigit()
        }
        Slider(value: value, in: range, step: step)
    }
}
