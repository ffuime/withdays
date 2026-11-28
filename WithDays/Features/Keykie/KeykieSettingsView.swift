import SwiftUI
import UniformTypeIdentifiers

/// Keykie's settings, by category. Everything is saved in the App Group; the keyboard reads it when it opens.
struct KeykieSettingsView: View {
    @State private var tryText = ""
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmReset = false
    @State private var backup: KeykieBackupFile?
    @State private var message: String?

    var body: some View {
        List {
            Section {
                NavigationLink { KeykieSetupView() } label: { KeykieStatusRow() }
            }

            Section("試し打ち") {
                TextField("ここで Keykie を試せます", text: $tryText, axis: .vertical)
                    .lineLimit(2...5)
            }

            Section("設定") {
                NavigationLink { KeykieInputSettings() } label: { Label("入力", systemImage: "character.cursor.ibeam") }
                NavigationLink { KeykieGestureSettings() } label: { Label("ジェスチャー", systemImage: "hand.draw") }
                NavigationLink { KeykieAppearanceSettings() } label: { Label("見た目", systemImage: "paintpalette") }
                NavigationLink { KeykieFeedbackSettings() } label: { Label("フィードバック", systemImage: "speaker.wave.2") }
                NavigationLink { KeykieClipboardSettings() } label: { Label("クリップボード", systemImage: "doc.on.clipboard") }
                NavigationLink { KeykieDictionarySettings() } label: { Label("辞書", systemImage: "character.book.closed") }
            }

            Section {
                Button("設定をバックアップ") {
                    if let data = KeykieBackup.export() {
                        backup = KeykieBackupFile(data: data)
                        exporting = true
                    }
                }
                Button("バックアップから復元") { importing = true }
                Button("すべての設定をリセット", role: .destructive) { confirmReset = true }
            } header: {
                Text("その他")
            } footer: {
                Text("バックアップには設定・ユーザー辞書・定型文が入ります（JSON）。リセットしても辞書・定型文・クリップボード履歴は残ります。")
            }

            Section {
                LabeledContent("バージョン", value: "\(AppInfo.version) (\(AppInfo.build))")
                LabeledContent("変換エンジン", value: "azooKey（MIT）")
            }
        }
        .navigationTitle("Keykie")
        .navigationBarTitleDisplayMode(.inline)
        .fileExporter(isPresented: $exporting, document: backup, contentType: .json,
                      defaultFilename: "Keykie-backup") { result in
            if case .success = result { message = "バックアップを書き出しました" }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                try KeykieBackup.restore(try Data(contentsOf: url))
                message = "復元しました"
            } catch {
                message = "このファイルは読み込めませんでした"
            }
        }
        .confirmationDialog("Keykie の設定をすべて初期値に戻しますか？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("リセット", role: .destructive) {
                KeykieBackup.resetSettings()
                message = "設定をリセットしました"
            }
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") {}
        }
    }
}

struct KeykieBackupFile: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// Whether the keyboard has been used, and with full access.
struct KeykieStatusRow: View {
    @AppStorage(KK.lastSeen, store: KeykieGroup.defaults) private var lastSeen = 0.0
    @AppStorage(KK.fullAccess, store: KeykieGroup.defaults) private var fullAccess = false

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "keyboard.fill")
                .font(.system(size: 22))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.gradient))
            VStack(alignment: .leading, spacing: 3) {
                Text(lastSeen == 0 ? "キーボードを追加する" : "Keykie を使えます")
                    .font(.system(size: 16, weight: .bold))
                Text(lastSeen == 0 ? "iPhoneの設定で Keykie を追加してください"
                     : fullAccess ? "フルアクセス：許可" : "フルアクセス：未許可（履歴・効果音・振動・流行語の自動更新に必要）")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

/// How to add the keyboard and allow full access.
struct KeykieSetupView: View {
    var body: some View {
        List {
            Section {
                step(1, "iPhoneの「設定」を開く", "下のボタンで WithDays の設定ページが開きます。")
                step(2, "「キーボード」をタップ", "WithDays の設定ページにある「キーボード」から Keykie をオンにします。")
                step(3, "「フルアクセスを許可」をオン", "クリップボード履歴・効果音・振動・流行語の自動更新に使います。")
                step(4, "地球儀キーで Keykie に切り替え", "どのアプリでも、キーボードの地球儀キー（長押しで一覧）から選べます。")
            } header: {
                Text("追加のしかた")
            }

            Section {
                Button("設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 16, weight: .semibold))
            }

            Section {
                Text("フルアクセスがあると、キーボードはネットワークに接続でき、コピーされたテキストを読めます。Keykie が通信するのは流行語辞書のダウンロード（辞書の設定にあるURL）だけで、入力した文字やクリップボードの内容をどこかへ送ることはありません。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } header: {
                Text("フルアクセスについて")
            }

            Section {
                Text("iOSでは、キーボードがバックグラウンドでクリップボードを見張ることはできません。Keykie は、キーボードが表示されたときと、アプリに戻ってきたときにだけクリップボードを確認して履歴に追加します。キーボードを開かないままコピーを重ねると、その間のものは履歴に残りません。")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            } header: {
                Text("クリップボード履歴のしくみ")
            }
        }
        .navigationTitle("キーボードの追加")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.accentColor))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
