import SwiftUI

/// Make a tooc account with just a toocID and a password (email or phone can be added later), or sign back in.
/// Until there is a server the account lives in this device's keychain.
struct ToocLoginView: View {
    var onCalendar: () -> Void

    @Environment(ToocStore.self) private var store
    @State private var creating = true
    @State private var id = ""
    @State private var password = ""
    @State private var errorMessage: String?
    @State private var working = false
    @State private var phoneLogin = false
    @FocusState private var field: Field?

    private enum Field { case id, password }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 6) {
                        Image("ToocLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 96)
                            .accessibilityLabel("tooc")
                        Text(creating ? "toocIDとパスワードを決めるだけではじめられます" : "toocID（またはメールアドレス）とパスワードでログイン")
                            .toocFont(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section {
                    Picker("", selection: $creating.animation(.snappy)) {
                        Text("新規登録").tag(true)
                        Text("ログイン").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    HStack(spacing: 2) {
                        Text("@").foregroundStyle(.secondary)
                        TextField(creating ? "toocID" : "toocID・メールアドレス", text: $id)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .focused($field, equals: .id)
                            .submitLabel(.next)
                            .onSubmit { field = .password }
                    }
                    SecureField("パスワード", text: $password)
                        // Lets iOS suggest a strong password and offer to save it in Passwords.
                        .textContentType(creating ? .newPassword : .password)
                        .focused($field, equals: .password)
                        .submitLabel(.go)
                        .onSubmit(submit)
                } footer: {
                    if creating {
                        Text("toocIDは半角英数字と . _ の4〜20文字、パスワードは8文字以上です。メールアドレスや電話番号の登録はあとからできます。")
                    }
                }

                Section {
                    Button(action: submit) {
                        ZStack {
                            Text(creating ? "アカウントを作成" : "ログイン")
                                .opacity(working ? 0 : 1)
                            if working { ProgressView().tint(.white) }
                        }
                        .toocFont(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!valid || working)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                if !creating {
                    Section {
                        Button("電話番号でログイン・パスワードを忘れた", systemImage: "phone") { phoneLogin = true }
                    }
                }

                ToocSavedAccountsSection()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onCalendar) { Image(systemName: "chevron.left").foregroundStyle(Color.toocBrand) }
                        .accessibilityLabel("カレンダーに戻る")
                }
            }
            .alert("できませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear { creating = !store.hasDeviceAccount }
            .sheet(isPresented: $phoneLogin) { ToocPhoneLoginView() }
        }
    }

    private var normalizedID: String { id.trimmingCharacters(in: .whitespaces).lowercased() }

    private var valid: Bool {
        if !creating { return !normalizedID.isEmpty && !password.isEmpty }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._")
        return (4...20).contains(normalizedID.count)
            && normalizedID.unicodeScalars.allSatisfy(allowed.contains)
            && password.count >= 8
    }

    private func submit() {
        guard valid, !working else { return }
        working = true
        Task {
            do {
                if creating {
                    try await store.createAccount(id: normalizedID, password: password)
                } else {
                    try await store.logIn(id: normalizedID, password: password)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            working = false
        }
    }
}
