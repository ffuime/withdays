import SwiftUI

/// tooc's settings: your profile, then アカウント・通知・非表示とブロック・トーク.
struct ToocSettingsView: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router

    var body: some View {
        List {
            Section {
                Button { router.sheet = .editProfile } label: {
                    HStack(spacing: 14) {
                        ToocAvatar(user: store.me, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.me.name).toocFont(.headline).foregroundStyle(.primary)
                            Text("@\(store.me.id)").toocFont(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("編集").toocFont(.subheadline).foregroundStyle(store.theme.accent)
                    }
                }
            }
            Section {
                link("アカウント", "person.crop.circle", .settingsAccount)
                link("通知", "bell", .settingsNotifications)
                link("非表示・ブロック", "eye.slash", .settingsHidden)
                link("トーク", "message", .settingsTalk)
            }
            Section {
                Toggle("toocIDで友だち追加を許可", isOn: Binding(get: { store.me.findable }, set: { store.setFindable($0) }))
            } header: {
                Text("プライバシー").toocFont(.footnote)
            } footer: {
                Text("オフのあいだは、toocIDを入力して検索されても見つかりません。QRコードとリンクからは追加できます。").toocFont(.footnote)
            }
            Section {
                link("tooc について", "info.circle", .settingsAbout)
                link("更新履歴", "clock.arrow.circlepath", .settingsChangelog)
                link("権利表示", "c.circle", .settingsCredits)
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func link(_ title: String, _ symbol: String, _ route: ToocRoute) -> some View {
        NavigationLink(value: route) {
            Label(title, systemImage: symbol)
        }
    }
}

struct ToocAccountSettingsView: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @State private var confirmLogOut = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                LabeledContent("toocID", value: "@\(store.me.id)")
                NavigationLink("パスワードを変更", value: ToocRoute.settingsPassword)
                NavigationLink("メールアドレス", value: ToocRoute.settingsEmail)
                NavigationLink("電話番号", value: ToocRoute.settingsPhone)
            }
            Section {
                Button("アカウントを切り替え", systemImage: "person.2.circle") { router.sheet = .accounts }
            } footer: {
                Text("じぶんタブの長押しでも切り替えられます。ダブルタップで前のアカウントに戻ります。").toocFont(.footnote)
            }
            Section {
                Button("ログアウト") { confirmLogOut = true }
            }
            Section {
                Button("アカウントを削除", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle("アカウント")
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(isPresented: $confirmDelete) { ToocDeleteAccountView() }
        .alert("ログアウトしますか？", isPresented: $confirmLogOut) {
            Button("キャンセル", role: .cancel) {}
            Button("ログアウト", role: .destructive) { store.logOut() }
        }
    }
}

struct ToocPasswordView: View {
    @Environment(ToocStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var current = ""
    @State private var new = ""
    @State private var again = ""
    @State private var error: String?
    @State private var done = false

    private var valid: Bool { !current.isEmpty && new.count >= 8 && new == again }

    var body: some View {
        Form {
            Section {
                SecureField("いまのパスワード", text: $current)
                    .textContentType(.password)
            }
            Section {
                SecureField("新しいパスワード", text: $new)
                    .textContentType(.newPassword)
                SecureField("もう一度", text: $again)
                    .textContentType(.newPassword)
            } footer: {
                if !again.isEmpty, new != again {
                    Text("新しいパスワードが一致しません。").toocFont(.footnote)
                } else {
                    Text("8文字以上").toocFont(.footnote)
                }
            }
            Section {
                Button("変更する") {
                    Task {
                        do {
                            try await store.changePassword(current: current, new: new)
                            done = true
                        } catch {
                            self.error = error.localizedDescription
                        }
                    }
                }
                .disabled(!valid)
            }
        }
        .navigationTitle("パスワードを変更")
        .navigationBarTitleDisplayMode(.inline)
        .alert("できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
        .alert("パスワードを変更しました", isPresented: $done) {
            Button("OK") { dismiss() }
        }
    }
}

struct ToocNotificationSettingsView: View {
    @Environment(ToocStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                Toggle("通知", isOn: $store.settings.notifications)
                    .onChange(of: store.settings.notifications) { _, on in
                        if on { ToocNotifications.requestAuthorization() }
                    }
                Toggle("メッセージの内容を表示", isOn: $store.settings.showContent)
                    .disabled(!store.settings.notifications)
            }
        }
        .navigationTitle("通知")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct ToocHiddenSettingsView: View {
    @Environment(ToocStore.self) private var store

    var body: some View {
        List {
            Section {
                if store.hiddenFriends.isEmpty { empty }
                ForEach(store.hiddenFriends) { user in
                    row(user.displayName, user: user, action: "再表示") { store.showFriend(user.id) }
                }
            } header: {
                Text("非表示の友だち").toocFont(.footnote)
            }
            Section {
                if store.blockedUsers.isEmpty { empty }
                ForEach(store.blockedUsers) { user in
                    row(user.displayName, user: user, action: "ブロック解除") { store.unblock(user.id) }
                }
            } header: {
                Text("ブロック中").toocFont(.footnote)
            }
            Section {
                if store.hiddenRooms.isEmpty { empty }
                ForEach(store.hiddenRooms) { room in
                    row(store.name(of: room), user: store.iconUser(of: room), action: "再表示") {
                        store.update(room.id) { $0.hidden = false }
                    }
                }
            } header: {
                Text("非表示のトーク").toocFont(.footnote)
            }
        }
        .navigationTitle("非表示・ブロック")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var empty: some View {
        Text("ありません").foregroundStyle(.secondary)
    }

    private func row(_ name: String, user: ToocUser, action: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            ToocAvatar(user: user, size: 36)
            Text(name).lineLimit(1)
            Spacer()
            Button(action) { withAnimation(.snappy) { perform() } }
                .buttonStyle(.bordered)
                .toocFont(.subheadline)
        }
    }
}

struct ToocTalkSettingsView: View {
    @Environment(ToocStore.self) private var store

    /// Themes as tiny talks to choose from, three to a row.
    private func themeGrid(_ themes: [ToocTheme], store: ToocStore) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
            ForEach(themes) { option in
                Button {
                    withAnimation(.smooth) { store.settings.theme = option }
                } label: {
                    VStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 4) {
                            Capsule().fill(option.theirBubble).frame(width: 34, height: 12)
                            Capsule().fill(option.myBubble).frame(width: 42, height: 12)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                        .padding(10)
                        .frame(height: 64)
                        .background(option.fill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .strokeBorder(store.settings.theme == option ? option.accent : Color.secondary.opacity(0.25),
                                              lineWidth: store.settings.theme == option ? 2.5 : 1)
                        }
                        Text(option.label)
                            .toocFont(.caption.weight(store.settings.theme == option ? .bold : .regular))
                            .foregroundStyle(store.settings.theme == option ? store.settings.theme.accent : Color.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    var body: some View {
        @Bindable var store = store
        Form {
            Section {
                HStack(spacing: 12) {
                    Text("あ").toocFont(.system(size: 13))
                    Slider(value: $store.settings.textPoints, in: 12...30)
                    Text("あ").toocFont(.system(size: 24))
                }
                .foregroundStyle(.secondary)
                Text("こんにちは！tooc の文字はこの大きさです。")
                    .toocFont(.system(size: store.settings.textPoints))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(store.theme.myBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } header: {
                Text("文字サイズ").toocFont(.footnote)
            }
            Section {
                NavigationLink(value: ToocRoute.settingsFont) {
                    LabeledContent("フォント", value: ToocFontChoice.find(store.settings.font)?.label ?? "システム標準")
                }
            }
            Section {
                themeGrid(ToocTheme.brightThemes, store: store)
            } header: {
                Text("明るいテーマ").toocFont(.footnote)
            }
            Section {
                themeGrid(ToocTheme.darkThemes, store: store)
            } header: {
                Text("暗いテーマ").toocFont(.footnote)
            }
            Section {
                Toggle("改行キーで送信", isOn: $store.settings.returnSends)
            }
        }
        .navigationTitle("トーク")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - About tooc

/// tooc について: the logo, what it is, and the version.
struct ToocAboutView: View {
    static var summary: String {
        ToocNotifications.standalone
            ? "tooc は、友だちやグループとメッセージ・写真・ファイル・スタンプをやり取りできるトークアプリです。"
            : "tooc は WithDays の中で使えるトークアプリです。友だちやグループと、メッセージ・写真・ファイル・スタンプをやり取りできます。"
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    Image("ToocLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 110)
                        .accessibilityLabel("tooc")
                    Text(Self.summary)
                        .toocFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            Section {
                LabeledContent("バージョン", value: "\(AppInfo.version) (\(AppInfo.build))")
                NavigationLink("更新履歴", value: ToocRoute.settingsChangelog)
                NavigationLink("権利表示", value: ToocRoute.settingsCredits)
            } footer: {
                if !ToocNotifications.standalone {
                    Text("tooc は WithDays と一緒に更新されます。バージョンは WithDays と同じです。").toocFont(.footnote)
                }
            }
        }
        .navigationTitle("tooc について")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 更新履歴: only tooc's lines from WithDays' releases.
struct ToocChangelogView: View {
    private static let prefix = "tooc："

    private struct Entry: Identifiable {
        let release: AppInfo.Release
        let notes: [String]
        var id: String { release.id }
    }

    private var entries: [Entry] {
        // The tooc app: its own releases, numbered on their own.
        if ToocNotifications.standalone {
            return ToocInfo.changelog.map { Entry(release: $0, notes: $0.notes) }
        }
        return AppInfo.changelog.compactMap { release in
            let notes = release.notes.filter { $0.hasPrefix(Self.prefix) }.map { String($0.dropFirst(Self.prefix.count)) }
            return notes.isEmpty ? nil : Entry(release: release, notes: notes)
        }
    }

    var body: some View {
        List(entries) { entry in
            Section {
                ForEach(entry.notes, id: \.self) { Text($0).toocFont(.system(size: 14)) }
            } header: {
                HStack {
                    Text(entry.release.version).toocFont(.footnote)
                    Spacer()
                    Text(entry.release.date).toocFont(.footnote)
                }
            }
        }
        .navigationTitle("更新履歴")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 権利表示: the services tooc runs on, the fonts, and the other companies' marks it shows.
struct ToocCreditsView: View {
    private struct Credit: Identifiable {
        let name: String
        let detail: String
        var id: String { name }
    }

    private let services: [Credit] = [
        Credit(name: "Firebase", detail: "Authentication・Cloud Firestore・Cloud Storage（Google LLC）。Firebase Apple SDK は Apache License 2.0 で提供されています。"),
        Credit(name: "Google Fonts", detail: "フォントのダウンロードに使用しています。各フォントは SIL Open Font License 1.1 で提供されています。"),
        Credit(name: "Apple マップ", detail: "位置情報の送信と表示に MapKit を使用しています。地図データの権利は Apple および各提供元に帰属します。"),
    ]

    private let marks: [Credit] = [
        Credit(name: "Instagram", detail: "Instagram および Instagram のロゴは Meta Platforms, Inc. の商標です。"),
        Credit(name: "Facebook", detail: "Facebook および Facebook のロゴは Meta Platforms, Inc. の商標です。"),
        Credit(name: "X", detail: "X および X のロゴは X Corp. の商標です。"),
        Credit(name: "LINE", detail: "LINE および LINE のロゴは LINEヤフー株式会社の商標または登録商標です。"),
    ]

    private let references: [Credit] = [
        Credit(name: "LINE", detail: "LINEヤフー株式会社"),
        Credit(name: "Instagram", detail: "Meta Platforms, Inc."),
        Credit(name: "iMessage", detail: "Apple Inc."),
    ]

    var body: some View {
        List {
            Section {
                ForEach(references) { row($0) }
            } header: {
                Text("UI・機能の参考").toocFont(.footnote)
            } footer: {
                Text("tooc の画面や機能は、これらのアプリを参考にしています。tooc は各社とは関係ありません。").toocFont(.footnote)
            }
            Section {
                ForEach(services) { row($0) }
            } header: {
                Text("サービス・API").toocFont(.footnote)
            }
            Section {
                ForEach(ToocFontChoice.all) { font in
                    Text(font.label)
                }
            } header: {
                Text("フォント").toocFont(.footnote)
            } footer: {
                Text("いずれも Google Fonts から配布され、SIL Open Font License 1.1 のもとで使用しています。").toocFont(.footnote)
            }
            Section {
                ForEach(marks) { row($0) }
            } header: {
                Text("ロゴ・商標").toocFont(.footnote)
            } footer: {
                Text("共有ボタンに各社のロゴを使用しています。各社のロゴは、各社のブランドガイドラインに沿って表示しています。").toocFont(.footnote)
            }
        }
        .navigationTitle("権利表示")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ credit: Credit) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(credit.name).toocFont(.headline)
            Text(credit.detail)
                .toocFont(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
