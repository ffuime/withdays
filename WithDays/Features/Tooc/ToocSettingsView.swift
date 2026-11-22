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
                            Text(store.me.name).font(.headline).foregroundStyle(.primary)
                            Text("@\(store.me.id)").font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("編集").font(.subheadline).foregroundStyle(Color.brand)
                    }
                }
            }
            Section {
                link("アカウント", "person.crop.circle", .settingsAccount)
                link("通知", "bell", .settingsNotifications)
                link("非表示・ブロック", "eye.slash", .settingsHidden)
                link("トーク", "message", .settingsTalk)
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
    @State private var confirmLogOut = false
    @State private var confirmDelete = false

    var body: some View {
        List {
            Section {
                LabeledContent("toocID", value: "@\(store.me.id)")
                NavigationLink("パスワードを変更", value: ToocRoute.settingsPassword)
            } footer: {
                Text("アカウントはこの端末の中に保存されています。メールアドレスや電話番号の登録は、サーバーができてからになります。")
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
        .confirmationDialog("ログアウトしますか？", isPresented: $confirmLogOut, titleVisibility: .visible) {
            Button("ログアウト", role: .destructive) { store.logOut() }
        } message: {
            Text("トークはこの端末に残り、もう一度ログインすると戻ります。")
        }
        .confirmationDialog("アカウントを削除しますか？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("アカウントを削除", role: .destructive) { store.deleteAccount() }
        } message: {
            Text("友だち・トーク・写真がすべて消え、元に戻せません。")
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
                    Text("新しいパスワードが一致しません。")
                } else {
                    Text("8文字以上")
                }
            }
            Section {
                Button("変更する") {
                    do {
                        try store.changePassword(current: current, new: new)
                        done = true
                    } catch {
                        self.error = error.localizedDescription
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
                Toggle("メッセージの内容を表示", isOn: $store.settings.showContent)
                    .disabled(!store.settings.notifications)
            } footer: {
                Text("ほかの画面を見ているあいだに届いたメッセージを、上にバナーで知らせます。お知らせ（じぶんタブのベル）にはいつでも残ります。ミュートしたトークは知らせません。")
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
            Section("非表示の友だち") {
                if store.hiddenFriends.isEmpty { empty }
                ForEach(store.hiddenFriends) { user in
                    row(user.name, user: user, action: "再表示") { store.showFriend(user.id) }
                }
            }
            Section("ブロック中") {
                if store.blockedUsers.isEmpty { empty }
                ForEach(store.blockedUsers) { user in
                    row(user.name, user: user, action: "ブロック解除") { store.unblock(user.id) }
                }
            }
            Section("非表示のトーク") {
                if store.hiddenRooms.isEmpty { empty }
                ForEach(store.hiddenRooms) { room in
                    row(store.name(of: room), user: store.iconUser(of: room), action: "再表示") {
                        store.update(room.id) { $0.hidden = false }
                    }
                }
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
                .font(.subheadline)
        }
    }
}

struct ToocTalkSettingsView: View {
    @Environment(ToocStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            Section("文字サイズ") {
                Picker("文字サイズ", selection: $store.settings.textSize) {
                    ForEach(ToocTextSize.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("こんにちは！tooc の文字はこの大きさです。")
                    .font(.system(size: store.settings.textSize.points))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 8)
                    .background(Color.brand, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            Section("トーク背景") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                    ForEach(ToocRoomBackground.allCases) { background in
                        Button {
                            store.settings.background = background
                        } label: {
                            VStack(spacing: 4) {
                                Circle()
                                    .fill(background.color ?? Color(.systemBackground))
                                    .overlay(Circle().strokeBorder(.quaternary))
                                    .overlay {
                                        if store.settings.background == background {
                                            Image(systemName: "checkmark")
                                                .font(.caption.bold())
                                                .foregroundStyle(background == .night ? Color.white : Color.brand)
                                        }
                                    }
                                    .frame(width: 36, height: 36)
                                Text(background.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 4)
            }
            Section {
                Toggle("改行キーで送信", isOn: $store.settings.returnSends)
            } footer: {
                Text("オンにすると、キーボードの改行キーでそのまま送信します。")
            }
        }
        .navigationTitle("トーク")
        .navigationBarTitleDisplayMode(.inline)
    }
}
