import SwiftUI
import UIKit
import WebKit

/// The accounts signed in: switch, add, log out (swipe left), and the OAuth Client ID they sign in with.
struct GmailAccountsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = GmailStore.shared
    @State private var loggingOut: GmailAccount?
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.accounts) { account in
                        Button {
                            store.switchTo(account)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                GmailAccountAvatar(account: account, size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(account.name).font(.headline)
                                    Text(account.email).font(.subheadline).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 8)
                                if account.email == store.currentEmail {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(GmailView.red)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button("ログアウト", systemImage: "rectangle.portrait.and.arrow.right") {
                                loggingOut = account
                            }
                            .tint(.red)
                        }
                    }
                    Button {
                        adding = true
                        Task {
                            await store.addAccount()
                            adding = false
                        }
                    } label: {
                        HStack {
                            Label("アカウントを追加", systemImage: "person.crop.circle.badge.plus")
                            Spacer()
                            if adding { ProgressView() }
                        }
                    }
                    .disabled(!store.hasClientID || adding)
                } header: {
                    Text("ログイン中のアカウント")
                } footer: {
                    if store.accounts.isEmpty {
                        Text("ログインしているアカウントはありません。")
                    } else {
                        Text("左へスワイプするとログアウトできます。")
                    }
                }

                Section {
                    TextField("xxxx.apps.googleusercontent.com", text: $store.clientID, axis: .vertical)
                        .font(.system(.callout, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Client ID")
                } footer: {
                    Text("Google Cloud で Gmail API を有効にし、種類「iOS」で作った OAuth クライアント ID（バンドル ID は com.ffuime.withdays）を入力してください。アカウントを追加するときに使います。")
                }
            }
            .navigationTitle("アカウント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる", systemImage: "xmark") { dismiss() }
                }
            }
            .confirmationDialog("ログアウトしますか？", isPresented: Binding(
                get: { loggingOut != nil },
                set: { if !$0 { loggingOut = nil } }
            ), titleVisibility: .visible, presenting: loggingOut) { account in
                Button("ログアウト", role: .destructive) {
                    withAnimation(.snappy) { store.remove(account) }
                }
            } message: { account in
                Text("\(account.email) からログアウトします。メールは Gmail に残ります。")
            }
            .alert("Gmail", isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
    }
}

/// One mail: subject, sender, recipients and date, the body as the sender laid it out, and its attachments.
/// Opening it marks it read.
struct GmailMessageView: View {
    let message: GmailMessage
    var onTrash: (GmailMessage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var store = GmailStore.shared
    @State private var content: GmailBody?
    @State private var failure: String?
    @State private var webHeight: CGFloat = 120
    @State private var showRecipients = false

    /// The list's copy, so star and read changes show here too.
    private var current: GmailMessage { store.messages.first { $0.id == message.id } ?? message }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Text(current.subject.isEmpty ? "（件名なし）" : current.subject)
                        .font(.title2.weight(.bold))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button {
                        store.setStarred([current], starred: !current.starred)
                    } label: {
                        Image(systemName: current.starred ? "star.fill" : "star")
                            .font(.system(size: 22))
                            .foregroundStyle(current.starred ? Color.yellow : Color.secondary)
                            .symbolEffect(.bounce, value: current.starred)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(current.starred ? "スターを外す" : "スターを付ける")
                }

                sender

                Group {
                    if let content {
                        if let html = content.html {
                            GmailHTMLView(html: html, height: $webHeight)
                                .frame(height: webHeight)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        } else {
                            Text(content.text ?? current.snippet)
                                .font(.body)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !content.attachments.isEmpty { attachments(content.attachments) }
                    } else if let failure {
                        ContentUnavailableView("読み込めませんでした", systemImage: "exclamationmark.triangle",
                                               description: Text(failure))
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("未読にする", systemImage: "envelope.badge") {
                    store.setRead([current], read: false)
                    dismiss()
                }
                Button(store.folder == .trash ? "戻す" : "削除",
                       systemImage: store.folder == .trash ? "tray.and.arrow.up" : "trash") {
                    let target = current
                    dismiss()
                    onTrash(target)
                }
                Menu("その他", systemImage: "ellipsis") {
                    if let url = URL(string: "https://mail.google.com/mail/u/\(current.account)/#all/\(current.threadID)") {
                        Link(destination: url) { Label("Gmail で開く", systemImage: "safari") }
                    }
                    Button("送信元のアドレスをコピー", systemImage: "doc.on.doc") {
                        UIPasteboard.general.string = current.fromAddress
                    }
                }
            }
        }
        .task {
            if current.unread { store.setRead([current], read: true) }
            do {
                content = try await store.body(of: message)
            } catch {
                failure = error.localizedDescription
            }
        }
    }

    private var sender: some View {
        HStack(alignment: .top, spacing: 12) {
            GmailAvatar(name: current.fromName, address: current.fromAddress, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(current.fromName)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(GmailDate.list(current.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(current.fromAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                Button {
                    withAnimation(.snappy) { showRecipients.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text("詳細")
                        Image(systemName: "chevron.down")
                            .rotationEffect(.degrees(showRecipients ? 180 : 0))
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(GmailView.red)
                }
                .buttonStyle(.plain)
                if showRecipients {
                    VStack(alignment: .leading, spacing: 4) {
                        detail("日時", GmailDate.full(current.date))
                        detail("宛先", current.to)
                        if let cc = content?.cc, !cc.isEmpty { detail("Cc", cc) }
                        if let reply = content?.replyTo, !reply.isEmpty { detail("返信先", reply) }
                        detail("アカウント", current.account)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
    }

    private func detail(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
            Text(value)
                .font(.caption)
                .textSelection(.enabled)
        }
    }

    private func attachments(_ files: [GmailAttachment]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("添付ファイル \(files.count)件", systemImage: "paperclip")
                .font(.subheadline.weight(.semibold))
            ForEach(files) { file in
                HStack(spacing: 10) {
                    Image(systemName: symbol(for: file.mimeType))
                        .font(.title3)
                        .foregroundStyle(GmailView.red)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.name).font(.subheadline).lineLimit(1)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(file.size), countStyle: .file))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            Text("添付ファイルは Gmail で開けます。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func symbol(for type: String) -> String {
        if type.hasPrefix("image/") { return "photo" }
        if type == "application/pdf" { return "doc.richtext" }
        if type.hasPrefix("video/") { return "film" }
        if type.hasPrefix("audio/") { return "waveform" }
        if type.contains("zip") { return "doc.zipper" }
        return "doc"
    }
}

/// A mail's HTML, as tall as it is (the page around it scrolls). Its own scripts don't run; links open in Safari;
/// a layout wider than the screen is scaled down to fit.
struct GmailHTMLView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.dataDetectorTypes = [.link, .phoneNumber, .address]
        let web = WKWebView(frame: CGRect(x: 0, y: 0, width: 320, height: 100), configuration: configuration)
        web.isOpaque = false
        web.backgroundColor = .white
        web.scrollView.isScrollEnabled = false
        web.scrollView.bounces = false
        web.navigationDelegate = context.coordinator
        context.coordinator.loaded = html
        web.loadHTMLString(Self.page(html), baseURL: nil)
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        context.coordinator.height = $height
        if context.coordinator.loaded != html {
            context.coordinator.loaded = html
            web.loadHTMLString(Self.page(html), baseURL: nil)
        }
    }

    private static func page(_ html: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <meta name="color-scheme" content="light">
        <style>
        html, body { margin: 0; padding: 0; background: #fff; color: #202124; }
        body { padding: 12px; font: -apple-system-body; font-family: -apple-system, sans-serif;
               overflow-wrap: anywhere; -webkit-text-size-adjust: 100%; }
        img { max-width: 100%; height: auto; }
        pre { white-space: pre-wrap; }
        </style></head><body>\(html)</body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var height: Binding<CGFloat>
        var loaded = ""

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func webView(_ web: WKWebView, didFinish navigation: WKNavigation!) {
            measure(web)
            // Pictures arrive later and make the page taller.
            for delay in [0.4, 1.2, 3.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak web] in
                    if let web { self?.measure(web) }
                }
            }
        }

        private func measure(_ web: WKWebView) {
            let script = """
            (function() {
              var w = document.documentElement.clientWidth;
              document.body.style.zoom = 1;
              var s = document.body.scrollWidth;
              if (s > w + 2) { document.body.style.zoom = w / s; }
              return document.documentElement.scrollHeight;
            })()
            """
            web.evaluateJavaScript(script) { [weak self] value, _ in
                guard let self, let number = value as? NSNumber else { return }
                let new = max(CGFloat(number.doubleValue), 40)
                if abs(new - self.height.wrappedValue) > 1 { self.height.wrappedValue = new }
            }
        }

        func webView(_ web: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}
