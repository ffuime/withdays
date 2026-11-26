import CryptoKit
import LocalAuthentication
import Security
import SwiftUI
import UIKit

// MARK: - Passcode lock

/// パスコードロック: a 4- or 6-digit code kept on this device only (in the keychain, as a hash), asked for on opening tooc
/// and on coming back after a minute or more away, in a sheet over the loading screen. Face ID can open it too.
@MainActor
@Observable
final class ToocLock {
    static let shared = ToocLock()

    private static let service = "com.ffuime.tooc.passcode"
    private static let faceIDKey = "toocLockFaceID"
    private static let installedKey = "toocLockInstalled"
    private static let themeKey = "toocLockTheme"
    /// Asked by the lock screen when the code is forgotten: signing out lifts the lock.
    static let forgotNotification = Notification.Name("toocLockForgot")

    private(set) var enabled = false
    private(set) var length = 4
    var faceID = false {
        didSet { UserDefaults.standard.set(faceID, forKey: Self.faceIDKey) }
    }
    /// Not yet opened since launch or since leaving.
    var needsUnlock = true
    /// The signed-in account's theme, for the lock screen (kept for the next launch, before the account loads).
    var theme: ToocTheme = .standard {
        didSet {
            guard theme != oldValue else { return }
            UserDefaults.standard.set(theme.rawValue, forKey: Self.themeKey)
            window?.overrideUserInterfaceStyle = theme.colorScheme == .dark ? .dark : .light
        }
    }
    /// tooc is what's on screen (in WithDays it's one place among others).
    var onScreen = false
    @ObservationIgnored private var window: UIWindow?
    @ObservationIgnored private var leftAt: Date?
    /// How long away before the code is asked again.
    private static let grace: TimeInterval = 60

    func left() {
        if leftAt == nil { leftAt = .now }
    }

    func cameBack() {
        if let leftAt, Date.now.timeIntervalSince(leftAt) >= Self.grace { needsUnlock = true }
        leftAt = nil
    }

    private init() {
        faceID = UserDefaults.standard.bool(forKey: Self.faceIDKey)
        // The keychain outlives the app: a code from before a reinstall is forgotten with it.
        if !UserDefaults.standard.bool(forKey: Self.installedKey) {
            Self.deleteStored()
            UserDefaults.standard.set(true, forKey: Self.installedKey)
            faceID = false
        }
        if let stored = Self.stored() {
            enabled = true
            length = stored.length
        }
        theme = UserDefaults.standard.string(forKey: Self.themeKey).flatMap(ToocTheme.init(rawValue:)) ?? .standard
        // The tooc app: locking the iPhone locks tooc too, however soon it's opened again.
        if ToocNotifications.standalone {
            NotificationCenter.default.addObserver(forName: UIApplication.protectedDataWillBecomeUnavailableNotification,
                                                   object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { ToocLock.shared.needsUnlock = true }
            }
        }
    }

    // MARK: Code

    private static func hash(_ code: String) -> String {
        SHA256.hash(data: Data("tooc-lock:\(code)".utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
         kSecAttrAccount as String: "passcode"]
    }

    private static func stored() -> (length: Int, hash: String)? {
        var item = query
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(item as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let parts = text.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let length = Int(parts[0]) else { return nil }
        return (length, parts[1])
    }

    private static func deleteStored() {
        SecItemDelete(query as CFDictionary)
    }

    func set(_ code: String) {
        Self.deleteStored()
        var item = Self.query
        item[kSecValueData as String] = Data("\(code.count):\(Self.hash(code))".utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
        enabled = true
        length = code.count
        needsUnlock = false
    }

    func remove() {
        Self.deleteStored()
        enabled = false
        faceID = false
    }

    func check(_ code: String) -> Bool {
        Self.stored()?.hash == Self.hash(code)
    }

    // MARK: Face ID

    var biometryAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
    }

    var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .touchID ? "Touch ID" : "Face ID"
    }

    var biometrySymbol: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return context.biometryType == .touchID ? "touchid" : "faceid"
    }

    func authenticate() async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics,
                                                  localizedReason: "tooc のロックを解除します")) ?? false
    }

    // MARK: The lock screen

    /// Covers everything (sheets too) in a window of its own until the code is entered.
    func lockIfNeeded() {
        guard enabled, needsUnlock, window == nil,
              let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState != .unattached }) else { return }
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.overrideUserInterfaceStyle = theme.colorScheme == .dark ? .dark : .light
        let screen = ToocLockScreen { [weak self] in self?.unlocked() }
        window.rootViewController = UIHostingController(rootView: screen)
        window.makeKeyAndVisible()
        self.window = window
    }

    private func unlocked() {
        needsUnlock = false
        guard let window else { return }
        self.window = nil
        UIView.animate(withDuration: 0.3, delay: 0.1, options: [.curveEaseOut]) {
            window.alpha = 0
        } completion: { _ in
            window.isHidden = true
            window.windowScene?.windows.first { $0 !== window && $0.windowLevel == .normal }?.makeKey()
        }
    }

    /// Forgot the code: the lock is lifted and the account signed out (signing in again needs the password).
    func forgot() {
        remove()
        NotificationCenter.default.post(name: Self.forgotNotification, object: nil)
        unlocked()
    }
}

/// The loading screen with the passcode over it: a full-screen sheet that can't be closed.
private struct ToocLockScreen: View {
    let onUnlock: () -> Void
    @State private var lock = ToocLock.shared
    @State private var asking = false

    private var theme: ToocTheme { lock.theme }

    var body: some View {
        ZStack {
            theme.fill.ignoresSafeArea()
            Image("ToocLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 120)
                .accessibilityLabel("tooc")
        }
        .environment(\.toocTheme, theme)
        .tint(theme.accent)
        .task {
            try? await Task.sleep(for: .milliseconds(150))
            asking = true
        }
        .fullScreenCover(isPresented: $asking) {
            ToocUnlockView {
                asking = false
                onUnlock()
            }
            .environment(\.toocTheme, theme)
            .tint(theme.accent)
            .background(theme.fill.ignoresSafeArea())
            .interactiveDismissDisabled()
        }
    }
}

/// Entering the code (or Face ID) to open tooc.
private struct ToocUnlockView: View {
    let onUnlock: () -> Void
    @State private var lock = ToocLock.shared
    @State private var code = ""
    @State private var shake = 0
    @State private var confirmForgot = false

    var body: some View {
        ToocPasscodePad(
            title: "パスコードを入力",
            code: $code,
            slots: lock.length,
            shake: shake,
            biometry: lock.faceID ? lock.biometrySymbol : nil,
            onBiometry: { Task { await tryBiometry() } }
        ) {
            Button("パスコードを忘れた場合") { confirmForgot = true }
                .toocFont(.footnote)
                .foregroundStyle(.secondary)
        }
        .onChange(of: code) { _, new in
            guard new.count == lock.length else { return }
            if lock.check(new) {
                onUnlock()
            } else {
                shake += 1
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    code = ""
                }
            }
        }
        .task { if lock.faceID { await tryBiometry() } }
        .alert("パスコードを忘れた場合", isPresented: $confirmForgot) {
            Button("キャンセル", role: .cancel) {}
            Button("ログアウトして解除", role: .destructive) { lock.forgot() }
        } message: {
            Text("ログアウトすると、パスコードロックが解除されます。もう一度ログインするにはパスワードが必要です。")
        }
    }

    private func tryBiometry() async {
        if await lock.authenticate() { onUnlock() }
    }
}

/// The keypad: plain digits with no background across most of the width, Face ID at the bottom left and delete at
/// the bottom right; something of its own (a button) under it.
struct ToocPasscodePad<Below: View>: View {
    let title: String
    var message: String? = nil
    @Binding var code: String
    /// How many dots (the code's length, or 4 / 6 while choosing one).
    let slots: Int
    var maxLength = 6
    var shake = 0
    var biometry: String? = nil
    var onBiometry: () -> Void = {}
    /// A small line under the dots (how long a code can be).
    var note: String? = nil
    @ViewBuilder var below: Below

    private static var keyHeight: CGFloat { 68 }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 12)
            VStack(spacing: 6) {
                Text(title).toocFont(.title3.weight(.semibold))
                Text(message ?? " ")
                    .toocFont(.footnote)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 18) {
                ForEach(0..<max(slots, code.count), id: \.self) { index in
                    // Entered: one solid colour; not yet: an outline.
                    if index < code.count {
                        Circle().fill(Color.primary).frame(width: 14, height: 14)
                    } else {
                        Circle().strokeBorder(Color.primary.opacity(0.45), lineWidth: 1.5).frame(width: 14, height: 14)
                    }
                }
            }
            .animation(.snappy(duration: 0.15), value: code)
            .animation(.snappy(duration: 0.2), value: slots)
            .keyframeAnimator(initialValue: 0.0, trigger: shake) { content, x in
                content.offset(x: x)
            } keyframes: { _ in
                KeyframeTrack {
                    CubicKeyframe(-14, duration: 0.06)
                    CubicKeyframe(12, duration: 0.08)
                    CubicKeyframe(-8, duration: 0.08)
                    CubicKeyframe(5, duration: 0.08)
                    CubicKeyframe(0, duration: 0.08)
                }
            }
            .frame(height: 20)
            Text(note ?? " ")
                .toocFont(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)

            VStack(spacing: 8) {
                ForEach([["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]], id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(row, id: \.self) { key($0) }
                    }
                }
                HStack(spacing: 0) {
                    if let biometry {
                        Button(action: onBiometry) {
                            Image(systemName: biometry)
                                .font(.system(size: 28))
                                .frame(maxWidth: .infinity)
                                .frame(height: Self.keyHeight)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("生体認証で解除")
                    } else {
                        Color.clear.frame(maxWidth: .infinity).frame(height: Self.keyHeight)
                    }
                    key("0")
                    Button {
                        if !code.isEmpty { code.removeLast() }
                    } label: {
                        Image(systemName: "delete.left")
                            .font(.system(size: 24))
                            .frame(maxWidth: .infinity)
                            .frame(height: Self.keyHeight)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("削除")
                }
            }
            .foregroundStyle(Color.primary)
            .padding(.horizontal, 20)

            below
                .padding(.horizontal, 24)
                .frame(minHeight: 50)
        }
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sensoryFeedback(.selection, trigger: code)
        .sensoryFeedback(.error, trigger: shake)
    }

    private func key(_ digit: String) -> some View {
        Button {
            if code.count < maxLength { code.append(digit) }
        } label: {
            Text(digit)
                .font(.system(size: 34, weight: .regular, design: .rounded))
                .frame(maxWidth: .infinity)
                .frame(height: Self.keyHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Setting, changing or turning off the code. A new code is 4 digits, or 6 when more than 4 are typed.
struct ToocPasscodeSetup: View {
    enum Mode: String, Identifiable {
        case create, change, remove
        var id: String { rawValue }
    }

    private enum Step { case current, new, confirm }

    let mode: Mode
    @Environment(\.dismiss) private var dismiss
    @State private var lock = ToocLock.shared
    @State private var step: Step
    @State private var code = ""
    @State private var chosen = ""
    @State private var shake = 0
    @State private var message: String?

    init(mode: Mode) {
        self.mode = mode
        _step = State(initialValue: mode == .create ? .new : .current)
    }

    private var slots: Int {
        switch step {
        case .current: lock.length
        case .confirm: chosen.count
        case .new: code.count > 4 ? 6 : 4
        }
    }

    var body: some View {
        NavigationStack {
            ToocPasscodePad(
                title: title,
                message: message,
                code: $code,
                slots: slots,
                shake: shake,
                note: step == .new ? "4桁を超えて入力すると、6桁のパスコードになります" : nil
            ) {
                if step == .new {
                    Button { choose() } label: {
                        Text("決定")
                            .toocFont(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(code.count != 4)
                }
            }
            .id(step)
            .transition(.push(from: .trailing))
            .navigationTitle(mode == .remove ? "パスコードをオフ" : "パスコード")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", systemImage: "xmark") { dismiss() }
                }
            }
        }
        .onChange(of: code) { _, new in entered(new) }
    }

    private var title: String {
        switch step {
        case .current: "いまのパスコード"
        case .new: "新しいパスコード"
        case .confirm: "もう一度入力"
        }
    }

    private func entered(_ new: String) {
        switch step {
        case .current:
            guard new.count == lock.length else { return }
            if lock.check(new) {
                if mode == .remove {
                    lock.remove()
                    dismiss()
                } else {
                    advance(to: .new, message: nil)
                }
            } else {
                fail("パスコードが違います")
            }
        case .new:
            if new.count == 6 { choose() }
        case .confirm:
            guard new.count == chosen.count else { return }
            if new == chosen {
                lock.set(new)
                dismiss()
            } else {
                chosen = ""
                fail("一致しませんでした。もう一度決めてください")
                withAnimation(.smooth) { step = .new }
            }
        }
    }

    private func choose() {
        guard code.count == 4 || code.count == 6 else { return }
        chosen = code
        advance(to: .confirm, message: nil)
    }

    private func advance(to next: Step, message: String?) {
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            self.message = message
            code = ""
            withAnimation(.smooth) { step = next }
        }
    }

    private func fail(_ text: String) {
        shake += 1
        message = text
        Task {
            try? await Task.sleep(for: .milliseconds(350))
            code = ""
        }
    }
}

// MARK: - Settings

/// プライバシー: the passcode lock (and Face ID), and whether a typed toocID finds you.
struct ToocPrivacySettingsView: View {
    @Environment(ToocStore.self) private var store
    @State private var lock = ToocLock.shared
    @State private var setup: ToocPasscodeSetup.Mode?

    var body: some View {
        List {
            Section {
                Toggle("パスコードロック", isOn: Binding(get: { lock.enabled }, set: { setup = $0 ? .create : .remove }))
                if lock.enabled {
                    Button("パスコードを変更") { setup = .change }
                    if lock.biometryAvailable {
                        Toggle("\(lock.biometryName)で解除", isOn: Binding(get: { lock.faceID }, set: { on in
                            if on {
                                Task { if await lock.authenticate() { lock.faceID = true } }
                            } else {
                                lock.faceID = false
                            }
                        }))
                    }
                }
            } footer: {
                Text("tooc を開くときと、1分以上ほかのアプリにいて戻ったときに、4桁または6桁のパスコードを入力します。パスコードはこの iPhone の中だけに保存されます。").toocFont(.footnote)
            }
            Section {
                Toggle("toocIDによる検索を許可", isOn: Binding(get: { store.me.findable }, set: { store.setFindable($0) }))
            } footer: {
                Text("オフのあいだは、toocIDを入力して検索されても見つかりません。QRコードとリンクからは追加できます。").toocFont(.footnote)
            }
        }
        .navigationTitle("プライバシー")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $setup) { mode in ToocPasscodeSetup(mode: mode) }
    }
}
