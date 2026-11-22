import CryptoKit
import FirebaseAuth
import FirebaseFirestore
import SwiftUI

// Signing in with an email address or a phone number, and getting back in with the phone when the password is lost.
//
// An email address is only a second way to type who you are: emailIndex/{sha256(email)} → toocID, then the usual
// password. A phone number is linked to the Firebase account itself, so an SMS code signs in on its own.

extension ToocServer {
    static func emailIndex(_ email: String) -> DocumentReference {
        db.collection("emailIndex").document(hash(email))
    }

    static func contact(_ id: String) -> DocumentReference { user(id).collection("private").document("contact") }

    static func hash(_ email: String) -> String {
        SHA256.hash(data: Data(email.lowercased().trimmingCharacters(in: .whitespaces).utf8))
            .map { String(format: "%02x", $0) }.joined()
    }

    /// 090-1234-5678 → +819012345678; numbers already starting with + stay as they are.
    static func phoneE164(_ text: String) -> String {
        let digits = text.filter { $0.isNumber || $0 == "+" }
        if digits.hasPrefix("+") { return digits }
        if digits.hasPrefix("0") { return "+81" + digits.dropFirst() }
        return "+" + digits
    }

    /// Firebase's own links (the phone check's reCAPTCHA comes back as one).
    @MainActor
    static func handle(_ url: URL) -> Bool {
        guard available else { return false }
        return Auth.auth().canHandle(url)
    }
}

extension ToocStore {
    // MARK: Email

    /// The email address linked to this account (this device reads it from the account's private record).
    func loadContact() async -> String? {
        guard let account else { return nil }
        return try? await ToocServer.contact(account).getDocument().data()?["email"] as? String
    }

    var linkedPhone: String? { Auth.auth().currentUser?.phoneNumber }

    func linkEmail(_ email: String, replacing old: String?) async throws {
        guard let account, let uid = Auth.auth().currentUser?.uid else { return }
        let address = email.lowercased().trimmingCharacters(in: .whitespaces)
        guard address.contains("@"), address.contains(".") else { throw ToocError("メールアドレスの形が違います。") }
        if let data = try? await ToocServer.emailIndex(address).getDocument().data(), data["toocID"] as? String != account {
            throw ToocError("このメールアドレスはほかのアカウントで使われています。")
        }
        do {
            if let old, old != address { try? await ToocServer.emailIndex(old).delete() }
            try await ToocServer.emailIndex(address).setData(["toocID": account, "uid": uid])
            try await ToocServer.contact(account).setData(["email": address], merge: true)
        } catch {
            throw ToocError(ToocServer.describe(error))
        }
    }

    func unlinkEmail(_ email: String) async {
        guard let account else { return }
        try? await ToocServer.emailIndex(email).delete()
        try? await ToocServer.contact(account).updateData(["email": FieldValue.delete()])
    }

    /// The toocID behind an email address (to sign in with it).
    static func toocID(forEmail email: String) async throws -> String {
        guard let id = try? await ToocServer.emailIndex(email).getDocument().data()?["toocID"] as? String else {
            throw ToocError("このメールアドレスのアカウントは見つかりませんでした。")
        }
        return id
    }

    // MARK: Phone

    /// Sends the SMS code; returns the ID that goes with it.
    func sendCode(to phone: String) async throws -> String {
        guard ToocServer.available else { throw ToocError("サーバーの設定が入っていません。") }
        do {
            return try await PhoneAuthProvider.provider().verifyPhoneNumber(ToocServer.phoneE164(phone), uiDelegate: nil)
        } catch {
            throw ToocError(ToocServer.describe(error))
        }
    }

    func linkPhone(verificationID: String, code: String) async throws {
        guard let user = Auth.auth().currentUser else { return }
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: code)
        do {
            _ = try await user.link(with: credential)
        } catch {
            throw ToocError(ToocServer.describe(error))
        }
    }

    func unlinkPhone() async throws {
        guard let user = Auth.auth().currentUser else { return }
        do {
            _ = try await user.unlink(fromProvider: "phone")
        } catch {
            throw ToocError(ToocServer.describe(error))
        }
    }

    /// Signs in with the SMS code alone (also the way back in when the password is forgotten).
    func logIn(verificationID: String, code: String) async throws {
        let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: code)
        let result: AuthDataResult
        do {
            result = try await Auth.auth().signIn(with: credential)
        } catch {
            throw ToocError(ToocServer.describe(error))
        }
        let found = try? await ToocServer.db.collection("users").whereField("uid", isEqualTo: result.user.uid).limit(to: 1)
            .getDocuments()
        guard let id = found?.documents.first?.documentID else {
            try? Auth.auth().signOut()
            try? await result.user.delete()
            throw ToocError("この電話番号はどのアカウントにも登録されていません。")
        }
        signedInByPhone(as: id)
    }

    /// A new password after getting in with the phone.
    func setPassword(_ password: String) async throws {
        guard let user = Auth.auth().currentUser, let account else { return }
        do {
            try await user.updatePassword(to: password)
        } catch {
            throw ToocError(ToocServer.describe(error))
        }
        ToocAccounts.store(account, password: password)
    }

    // MARK: Finding by toocID

    /// Whether others can find you by typing your toocID (QR codes and links always work).
    func setFindable(_ on: Bool) {
        guard let account else { return }
        me.findable = on
        Task { try? await ToocServer.user(account).updateData(["findable": on]) }
    }
}

// MARK: - Screens

/// Settings → アカウント → メールアドレス: link one to sign in with it.
struct ToocEmailSettingsView: View {
    @Environment(ToocStore.self) private var store
    @State private var current: String?
    @State private var email = ""
    @State private var working = false
    @State private var error: String?
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField("メールアドレス", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } footer: {
                Text("ログイン画面で toocID の代わりに使えます。")
            }
            Section {
                Button(current == nil ? "登録する" : "変更する") {
                    working = true
                    Task {
                        do {
                            try await store.linkEmail(email, replacing: current)
                            current = email.lowercased()
                        } catch {
                            self.error = error.localizedDescription
                        }
                        working = false
                    }
                }
                .disabled(working || email.isEmpty || email.lowercased() == current)
                if let current {
                    Button("登録を解除", role: .destructive) {
                        Task {
                            await store.unlinkEmail(current)
                            self.current = nil
                            email = ""
                        }
                    }
                }
            }
        }
        .navigationTitle("メールアドレス")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loaded else { return }
            loaded = true
            current = await store.loadContact()
            email = current ?? ""
        }
        .alert("できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }
}

/// Settings → アカウント → 電話番号: link one with an SMS code, to sign in and to get back in without the password.
struct ToocPhoneSettingsView: View {
    @Environment(ToocStore.self) private var store
    @State private var phone = ""
    @State private var verificationID: String?
    @State private var code = ""
    @State private var working = false
    @State private var error: String?
    @State private var linked: String?

    var body: some View {
        Form {
            if let linked {
                Section {
                    LabeledContent("電話番号", value: linked)
                }
                Section {
                    Button("登録を解除", role: .destructive) {
                        Task {
                            do {
                                try await store.unlinkPhone()
                                self.linked = nil
                            } catch {
                                self.error = error.localizedDescription
                            }
                        }
                    }
                }
            } else {
                ToocPhoneCodeFields(phone: $phone, code: $code, verificationID: $verificationID, working: $working, error: $error)
                if verificationID != nil {
                    Section {
                        Button("登録する") {
                            guard let verificationID else { return }
                            working = true
                            Task {
                                do {
                                    try await store.linkPhone(verificationID: verificationID, code: code)
                                    linked = store.linkedPhone
                                } catch {
                                    self.error = error.localizedDescription
                                }
                                working = false
                            }
                        }
                        .disabled(working || code.count < 6)
                    }
                }
            }
        }
        .navigationTitle("電話番号")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { linked = store.linkedPhone }
        .alert("できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(error ?? "")
        }
    }
}

/// The phone number, 「コードを送る」, then the 6-digit code.
struct ToocPhoneCodeFields: View {
    @Binding var phone: String
    @Binding var code: String
    @Binding var verificationID: String?
    @Binding var working: Bool
    @Binding var error: String?
    @Environment(ToocStore.self) private var store

    var body: some View {
        Section {
            TextField("電話番号（例：09012345678）", text: $phone)
                .keyboardType(.phonePad)
                .textContentType(.telephoneNumber)
            Button(verificationID == nil ? "SMSでコードを送る" : "コードを送り直す") {
                working = true
                Task {
                    do {
                        verificationID = try await store.sendCode(to: phone)
                    } catch {
                        self.error = error.localizedDescription
                    }
                    working = false
                }
            }
            .disabled(working || phone.filter(\.isNumber).count < 10)
        }
        if verificationID != nil {
            Section {
                TextField("6桁のコード", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            }
        }
    }
}

/// From the sign-in screen: in with an SMS code; then, if wanted, a new password (for a forgotten one).
struct ToocPhoneLoginView: View {
    @Environment(ToocStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var phone = ""
    @State private var code = ""
    @State private var verificationID: String?
    @State private var working = false
    @State private var error: String?
    @State private var signedIn = false
    @State private var newPassword = ""

    var body: some View {
        NavigationStack {
            Form {
                if signedIn {
                    Section {
                        SecureField("新しいパスワード（8文字以上）", text: $newPassword)
                            .textContentType(.newPassword)
                    } header: {
                        Text("パスワードを変える場合")
                    }
                    Section {
                        Button("パスワードを設定") {
                            Task {
                                do {
                                    try await store.setPassword(newPassword)
                                    dismiss()
                                } catch {
                                    self.error = error.localizedDescription
                                }
                            }
                        }
                        .disabled(newPassword.count < 8)
                        Button("このまま使う") { dismiss() }
                    }
                } else {
                    ToocPhoneCodeFields(phone: $phone, code: $code, verificationID: $verificationID, working: $working, error: $error)
                    if verificationID != nil {
                        Section {
                            Button("ログイン") {
                                guard let verificationID else { return }
                                working = true
                                Task {
                                    do {
                                        try await store.logIn(verificationID: verificationID, code: code)
                                        signedIn = true
                                    } catch {
                                        self.error = error.localizedDescription
                                    }
                                    working = false
                                }
                            }
                            .disabled(working || code.count < 6)
                        }
                    }
                }
            }
            .navigationTitle("電話番号でログイン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
            }
            .alert("できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }
}

// MARK: - Links in messages

enum ToocLinks {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)

    /// The text with its web addresses (and e-mail, phone) made tappable.
    static func attributed(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        guard let detector else { return result }
        let ns = text as NSString
        for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let url = match.url, let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].link = url
            result[lower..<upper].underlineStyle = .single
        }
        return result
    }
}
