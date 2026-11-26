import AuthenticationServices
import CryptoKit
import Foundation
import Security
import SwiftUI
import UIKit

// MARK: Model

/// A signed-in Google account.
struct GmailAccount: Codable, Identifiable, Hashable {
    let email: String
    var name: String
    var picture: URL?
    var id: String { email }
}

/// The sidebar's mailboxes. すべての受信トレイ spans every account; the rest are the current account's.
enum GmailFolder: String, CaseIterable, Identifiable {
    case allInboxes, primary, social, promotions, updates, starred, trash
    var id: String { rawValue }

    var title: String {
        switch self {
        case .allInboxes: "すべての受信トレイ"
        case .primary: "メイン"
        case .social: "ソーシャル"
        case .promotions: "プロモーション"
        case .updates: "新着"
        case .starred: "スター付き"
        case .trash: "ごみ箱"
        }
    }

    var symbol: String {
        switch self {
        case .allInboxes: "tray.2.fill"
        case .primary: "tray.fill"
        case .social: "person.2.crop.square.stack"
        case .promotions: "tag.fill"
        case .updates: "exclamationmark.circle.fill"
        case .starred: "star.fill"
        case .trash: "trash.fill"
        }
    }

    /// Gmail's own search words for the mailbox.
    var query: String {
        switch self {
        // Every account's inbox, without ソーシャル・プロモーション・新着 (and フォーラム).
        case .allInboxes: "in:inbox -category:social -category:promotions -category:updates -category:forums"
        case .primary: "in:inbox category:primary"
        case .social: "in:inbox category:social"
        case .promotions: "in:inbox category:promotions"
        case .updates: "in:inbox category:updates"
        case .starred: "is:starred"
        case .trash: "in:trash"
        }
    }
}

/// A message in a list.
struct GmailMessage: Identifiable, Hashable {
    let account: String
    let messageID: String
    let threadID: String
    var fromName: String
    var fromAddress: String
    var to: String
    var subject: String
    var snippet: String
    var date: Date
    var labels: Set<String>

    var id: String { account + "/" + messageID }
    var unread: Bool { labels.contains("UNREAD") }
    var starred: Bool { labels.contains("STARRED") }
}

/// A message's body, fetched when it's opened.
struct GmailBody {
    var html: String?
    var text: String?
    var attachments: [GmailAttachment]
    var cc: String
    var replyTo: String
}

struct GmailAttachment: Identifiable, Hashable {
    let id: String
    let name: String
    let mimeType: String
    let size: Int
}

enum GmailError: LocalizedError {
    case noClientID
    case notSignedIn
    case http(Int, String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .noClientID: "Client ID を入力してください"
        case .notSignedIn: "もう一度ログインしてください"
        case .http(let status, let message): message.isEmpty ? "通信に失敗しました（\(status)）" : message
        case .cancelled: nil
        }
    }
}

// MARK: Store

/// Gmail inside WithDays: Google accounts signed in with OAuth (the user's own iOS Client ID), their mail read
/// through the Gmail API. Nothing is sent; marks, stars and the bin are changed on Gmail itself.
@MainActor
@Observable
final class GmailStore {
    static let shared = GmailStore()

    private static let clientIDKey = "gmailClientID"
    private static let accountsKey = "gmailAccounts"
    private static let currentKey = "gmailCurrentAccount"
    private static let keychainService = "com.ffuime.withdays.gmail"
    private static let scopes = "openid email profile https://www.googleapis.com/auth/gmail.modify"

    var clientID: String {
        didSet { UserDefaults.standard.set(clientID.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.clientIDKey) }
    }
    private(set) var accounts: [GmailAccount] {
        didSet { saveAccounts() }
    }
    var currentEmail: String? {
        didSet { UserDefaults.standard.set(currentEmail, forKey: Self.currentKey) }
    }

    var folder: GmailFolder = .primary
    var search = ""

    private(set) var messages: [GmailMessage] = []
    private(set) var loading = false
    private(set) var loadingMore = false
    var errorMessage: String?
    private(set) var unread: [GmailFolder: Int] = [:]
    /// The next page for each account in the current list (none left: missing).
    @ObservationIgnored private var pageTokens: [String: String] = [:]
    /// Bumped with each new list, so a slow old answer doesn't overwrite a newer one.
    @ObservationIgnored private var generation = 0

    @ObservationIgnored private var accessTokens: [String: (token: String, expiry: Date)] = [:]

    private init() {
        clientID = UserDefaults.standard.string(forKey: Self.clientIDKey) ?? ""
        if let data = UserDefaults.standard.data(forKey: Self.accountsKey),
           let saved = try? JSONDecoder().decode([GmailAccount].self, from: data) {
            accounts = saved
        } else {
            accounts = []
        }
        currentEmail = UserDefaults.standard.string(forKey: Self.currentKey)
        if currentEmail.map({ email in !accounts.contains { $0.email == email } }) ?? true {
            currentEmail = accounts.first?.email
        }
    }

    var current: GmailAccount? { accounts.first { $0.email == currentEmail } }
    var hasClientID: Bool { !trimmedClientID.isEmpty }
    private var trimmedClientID: String { clientID.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func saveAccounts() {
        UserDefaults.standard.set(try? JSONEncoder().encode(accounts), forKey: Self.accountsKey)
    }

    // MARK: Signing in

    /// com.googleusercontent.apps.<id>: Google's redirect for an iOS client.
    private var redirectScheme: String {
        let id = trimmedClientID.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps." + id
    }

    private var redirectURI: String { redirectScheme + ":/oauth2redirect" }

    /// Google's sign-in in a browser sheet; the account is added (or refreshed) and becomes the current one.
    func addAccount() async {
        guard hasClientID else {
            errorMessage = GmailError.noClientID.errorDescription
            return
        }
        do {
            let verifier = Self.randomString(64)
            let challenge = Self.base64URL(Data(Self.sha256(Data(verifier.utf8))))
            let state = Self.randomString(24)
            var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
            components.queryItems = [
                URLQueryItem(name: "client_id", value: trimmedClientID),
                URLQueryItem(name: "redirect_uri", value: redirectURI),
                URLQueryItem(name: "response_type", value: "code"),
                URLQueryItem(name: "scope", value: Self.scopes),
                URLQueryItem(name: "code_challenge", value: challenge),
                URLQueryItem(name: "code_challenge_method", value: "S256"),
                URLQueryItem(name: "state", value: state),
                URLQueryItem(name: "access_type", value: "offline"),
                URLQueryItem(name: "prompt", value: "select_account consent"),
            ]
            let callback = try await GmailWebAuth.run(url: components.url!, scheme: redirectScheme)
            let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let error = items.first(where: { $0.name == "error" })?.value {
                throw GmailError.http(400, error == "access_denied" ? "ログインがキャンセルされました" : error)
            }
            guard items.first(where: { $0.name == "state" })?.value == state,
                  let code = items.first(where: { $0.name == "code" })?.value else {
                throw GmailError.http(400, "ログインに失敗しました")
            }
            let token = try await tokenRequest([
                "code": code,
                "client_id": trimmedClientID,
                "redirect_uri": redirectURI,
                "grant_type": "authorization_code",
                "code_verifier": verifier,
            ])
            guard let access = token.access_token else { throw GmailError.http(400, "ログインに失敗しました") }
            let info = try await userInfo(access)
            let email = info.email ?? ""
            guard !email.isEmpty else { throw GmailError.http(400, "メールアドレスを取得できませんでした") }
            if let refresh = token.refresh_token { Self.saveRefreshToken(refresh, for: email) }
            accessTokens[email] = (access, Date.now.addingTimeInterval(TimeInterval(token.expires_in ?? 3600) - 60))
            let account = GmailAccount(email: email, name: info.name ?? email, picture: info.picture.flatMap(URL.init(string:)))
            if let index = accounts.firstIndex(where: { $0.email == email }) {
                accounts[index] = account
            } else {
                accounts.append(account)
            }
            currentEmail = email
            await reload()
        } catch GmailError.cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// ログアウト: the token is given back to Google and forgotten here.
    func remove(_ account: GmailAccount) {
        if let refresh = Self.refreshToken(for: account.email) {
            var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.form(["token": refresh])
            let revoke = request
            Task.detached { _ = try? await URLSession.shared.data(for: revoke) }
        }
        Self.deleteRefreshToken(for: account.email)
        accessTokens[account.email] = nil
        accounts.removeAll { $0.email == account.email }
        messages.removeAll { $0.account == account.email }
        // The list follows (GmailView reloads when the current account changes).
        if currentEmail == account.email { currentEmail = accounts.first?.email }
    }

    func switchTo(_ account: GmailAccount) {
        guard currentEmail != account.email else { return }
        currentEmail = account.email
        if folder != .allInboxes { messages = [] }
    }

    private struct TokenResponse: Decodable {
        let access_token: String?
        let refresh_token: String?
        let expires_in: Int?
        let error: String?
        let error_description: String?
    }

    private struct UserInfo: Decodable {
        let email: String?
        let name: String?
        let picture: String?
    }

    private func tokenRequest(_ fields: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.form(fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            if decoded.error == "invalid_grant" { throw GmailError.notSignedIn }
            throw GmailError.http(status, decoded.error_description ?? decoded.error ?? "")
        }
        return decoded
    }

    private func userInfo(_ access: String) async throws -> UserInfo {
        var request = URLRequest(url: URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!)
        request.setValue("Bearer " + access, forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(UserInfo.self, from: data)
    }

    private func accessToken(_ email: String) async throws -> String {
        if let cached = accessTokens[email], cached.expiry > .now { return cached.token }
        guard let refresh = Self.refreshToken(for: email) else { throw GmailError.notSignedIn }
        let token = try await tokenRequest([
            "client_id": trimmedClientID,
            "refresh_token": refresh,
            "grant_type": "refresh_token",
        ])
        guard let access = token.access_token else { throw GmailError.notSignedIn }
        accessTokens[email] = (access, Date.now.addingTimeInterval(TimeInterval(token.expires_in ?? 3600) - 60))
        return access
    }

    // MARK: Gmail API

    private func api(_ email: String, _ path: String, method: String = "GET", query: [URLQueryItem] = [],
                     body: [String: Any]? = nil, retry: Bool = true) async throws -> Data {
        let token = try await accessToken(email)
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/" + path)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401, retry {
            accessTokens[email] = nil
            return try await api(email, path, method: method, query: query, body: body, retry: false)
        }
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(APIError.self, from: data))?.error.message ?? ""
            throw GmailError.http(status, message)
        }
        return data
    }

    private struct APIError: Decodable {
        struct Inner: Decodable { let message: String }
        let error: Inner
    }

    private struct ListResponse: Decodable {
        struct Ref: Decodable { let id: String }
        let messages: [Ref]?
        let nextPageToken: String?
        let resultSizeEstimate: Int?
    }

    struct Part: Decodable {
        struct Header: Decodable { let name: String; let value: String }
        struct Body: Decodable { let size: Int?; let data: String?; let attachmentId: String? }
        let partId: String?
        let mimeType: String?
        let filename: String?
        let headers: [Header]?
        let body: Body?
        let parts: [Part]?

        func header(_ name: String) -> String? {
            headers?.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    private struct MessageResponse: Decodable {
        let id: String
        let threadId: String
        let labelIds: [String]?
        let snippet: String?
        let internalDate: String?
        let payload: Part?
    }

    private var listAccounts: [String] {
        folder == .allInboxes ? accounts.map(\.email) : (currentEmail.map { [$0] } ?? [])
    }

    private var fullQuery: String {
        let words = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return words.isEmpty ? folder.query : folder.query + " " + words
    }

    /// The first page of the current mailbox (every account's, newest first, for すべての受信トレイ).
    func reload() async {
        generation += 1
        let mine = generation
        let emails = listAccounts
        guard !emails.isEmpty else {
            messages = []
            return
        }
        loading = true
        defer { if mine == generation { loading = false } }
        do {
            var found: [GmailMessage] = []
            var tokens: [String: String] = [:]
            for email in emails {
                let page = try await fetchPage(email, token: nil)
                found += page.messages
                if let next = page.next { tokens[email] = next }
            }
            guard mine == generation else { return }
            pageTokens = tokens
            withAnimation(.snappy) { messages = found.sorted { $0.date > $1.date } }
            errorMessage = nil
        } catch {
            if mine == generation { errorMessage = error.localizedDescription }
        }
        await refreshUnread()
    }

    var canLoadMore: Bool { !pageTokens.isEmpty }

    func loadMore() async {
        guard !loadingMore, !pageTokens.isEmpty else { return }
        loadingMore = true
        defer { loadingMore = false }
        let mine = generation
        var more: [GmailMessage] = []
        var tokens: [String: String] = [:]
        do {
            for (email, token) in pageTokens {
                let page = try await fetchPage(email, token: token)
                more += page.messages
                if let next = page.next { tokens[email] = next }
            }
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        guard mine == generation else { return }
        pageTokens = tokens
        let known = Set(messages.map(\.id))
        messages = (messages + more.filter { !known.contains($0.id) }).sorted { $0.date > $1.date }
    }

    private func fetchPage(_ email: String, token: String?) async throws -> (messages: [GmailMessage], next: String?) {
        var query = [URLQueryItem(name: "q", value: fullQuery), URLQueryItem(name: "maxResults", value: "30")]
        if folder == .trash { query.append(URLQueryItem(name: "includeSpamTrash", value: "true")) }
        if let token { query.append(URLQueryItem(name: "pageToken", value: token)) }
        let list = try JSONDecoder().decode(ListResponse.self, from: try await api(email, "messages", query: query))
        let ids = list.messages?.map(\.id) ?? []
        let found = try await withThrowingTaskGroup(of: (Int, GmailMessage?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { (index, try await self.metadata(email, id)) }
            }
            var result = [(Int, GmailMessage)]()
            for try await (index, message) in group {
                if let message { result.append((index, message)) }
            }
            return result.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return (found, list.nextPageToken)
    }

    private func metadata(_ email: String, _ id: String) async throws -> GmailMessage? {
        let query = ["From", "To", "Subject"].map { URLQueryItem(name: "metadataHeaders", value: $0) }
            + [URLQueryItem(name: "format", value: "metadata")]
        let data = try await api(email, "messages/" + id, query: query)
        let message = try JSONDecoder().decode(MessageResponse.self, from: data)
        return Self.message(message, account: email)
    }

    private static func message(_ response: MessageResponse, account: String) -> GmailMessage {
        let from = parseAddress(response.payload?.header("From") ?? "")
        let millis = Double(response.internalDate ?? "") ?? 0
        return GmailMessage(
            account: account,
            messageID: response.id,
            threadID: response.threadId,
            fromName: from.name,
            fromAddress: from.address,
            to: response.payload?.header("To") ?? "",
            subject: response.payload?.header("Subject") ?? "",
            snippet: decodeEntities(response.snippet ?? ""),
            date: Date(timeIntervalSince1970: millis / 1000),
            labels: Set(response.labelIds ?? [])
        )
    }

    /// Unread counts beside すべての受信トレイ (every account) and メイン (the current one).
    func refreshUnread() async {
        var counts: [GmailFolder: Int] = [:]
        var all = 0
        for account in accounts {
            if let count = try? await unreadCount(account.email, query: GmailFolder.allInboxes.query + " is:unread") { all += count }
        }
        counts[.allInboxes] = all
        if let email = currentEmail, let count = try? await unreadCount(email, query: "in:inbox category:primary is:unread") {
            counts[.primary] = count
        }
        unread = counts
    }

    private func unreadCount(_ email: String, query: String) async throws -> Int {
        let data = try await api(email, "messages", query: [URLQueryItem(name: "q", value: query),
                                                            URLQueryItem(name: "maxResults", value: "500")])
        // Counted from the ids (the estimate is rough); up to 500.
        let list = try JSONDecoder().decode(ListResponse.self, from: data)
        return list.messages?.count ?? 0
    }

    // MARK: Changes

    private func update(_ ids: Set<String>, _ change: (inout GmailMessage) -> Void) {
        for index in messages.indices where ids.contains(messages[index].id) {
            change(&messages[index])
        }
    }

    /// Adds or removes a label on Gmail, changing the list right away (and back if Gmail refuses).
    private func modify(_ targets: [GmailMessage], add: [String] = [], remove: [String] = []) {
        let ids = Set(targets.map(\.id))
        let before = messages
        withAnimation(.snappy) {
            update(ids) { message in
                message.labels.formUnion(add)
                message.labels.subtract(remove)
            }
        }
        Task {
            do {
                for (email, group) in Dictionary(grouping: targets, by: \.account) {
                    _ = try await api(email, "messages/batchModify", method: "POST",
                                      body: ["ids": group.map(\.messageID), "addLabelIds": add, "removeLabelIds": remove])
                }
                await refreshUnread()
            } catch {
                messages = before
                errorMessage = error.localizedDescription
            }
        }
    }

    func setRead(_ targets: [GmailMessage], read: Bool) {
        modify(targets, add: read ? [] : ["UNREAD"], remove: read ? ["UNREAD"] : [])
    }

    func setStarred(_ targets: [GmailMessage], starred: Bool) {
        modify(targets, add: starred ? ["STARRED"] : [], remove: starred ? [] : ["STARRED"])
        if folder == .starred, !starred {
            let ids = Set(targets.map(\.id))
            withAnimation(.snappy) { messages.removeAll { ids.contains($0.id) } }
        }
    }

    /// To the bin (or, in ごみ箱, back out of it). Returns what was moved, for 元に戻す.
    @discardableResult
    func trash(_ targets: [GmailMessage]) -> [GmailMessage] {
        let restoring = folder == .trash
        let ids = Set(targets.map(\.id))
        withAnimation(.snappy) { messages.removeAll { ids.contains($0.id) } }
        Task {
            do {
                for message in targets {
                    _ = try await api(message.account, "messages/\(message.messageID)/" + (restoring ? "untrash" : "trash"),
                                      method: "POST")
                }
                await refreshUnread()
            } catch {
                errorMessage = error.localizedDescription
                await reload()
            }
        }
        return targets
    }

    /// 元に戻す after a delete: back out of the bin and into the list.
    func undoTrash(_ targets: [GmailMessage]) {
        let restoring = folder == .trash
        withAnimation(.snappy) {
            let known = Set(messages.map(\.id))
            messages = (messages + targets.filter { !known.contains($0.id) }).sorted { $0.date > $1.date }
        }
        Task {
            do {
                for message in targets {
                    _ = try await api(message.account, "messages/\(message.messageID)/" + (restoring ? "trash" : "untrash"),
                                      method: "POST")
                }
                await refreshUnread()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: A message

    func body(of message: GmailMessage) async throws -> GmailBody {
        let data = try await api(message.account, "messages/" + message.messageID,
                                 query: [URLQueryItem(name: "format", value: "full")])
        let response = try JSONDecoder().decode(MessageResponse.self, from: data)
        var body = GmailBody(html: nil, text: nil, attachments: [], cc: response.payload?.header("Cc") ?? "",
                             replyTo: response.payload?.header("Reply-To") ?? "")
        if let payload = response.payload { Self.collect(payload, into: &body) }
        return body
    }

    private static func collect(_ part: Part, into body: inout GmailBody) {
        let type = (part.mimeType ?? "").lowercased()
        if let name = part.filename, !name.isEmpty, let attachment = part.body?.attachmentId {
            body.attachments.append(GmailAttachment(id: attachment, name: name, mimeType: type, size: part.body?.size ?? 0))
            return
        }
        if let parts = part.parts {
            for child in parts { collect(child, into: &body) }
            return
        }
        guard let data = part.body?.data.flatMap(decodeBase64URL) else { return }
        let text = decodeText(data, contentType: part.header("Content-Type") ?? "")
        if type == "text/html", body.html == nil {
            body.html = text
        } else if type == "text/plain", body.text == nil {
            body.text = text
        }
    }

    /// Mails can be in any charset (ISO-2022-JP and Shift_JIS among them); it's named in Content-Type.
    private static func decodeText(_ data: Data, contentType: String) -> String {
        if let range = contentType.range(of: "charset=", options: .caseInsensitive) {
            let name = contentType[range.upperBound...]
                .split(whereSeparator: { $0 == ";" || $0 == " " }).first
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) } ?? ""
            let cf = CFStringConvertIANACharSetNameToEncoding(name as CFString)
            if cf != kCFStringEncodingInvalidId {
                let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
                if let string = String(data: data, encoding: encoding) { return string }
            }
        }
        return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
    }

    // MARK: Helpers

    static func parseAddress(_ raw: String) -> (name: String, address: String) {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if let open = trimmed.lastIndex(of: "<"), let close = trimmed.lastIndex(of: ">"), open < close {
            let address = String(trimmed[trimmed.index(after: open)..<close])
            var name = String(trimmed[..<open]).trimmingCharacters(in: .whitespaces)
            name = name.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            return (name.isEmpty ? address : name, address)
        }
        return (trimmed, trimmed)
    }

    static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, value) in [("&quot;", "\""), ("&#39;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " "), ("&amp;", "&")] {
            result = result.replacingOccurrences(of: entity, with: value)
        }
        return result
    }

    private static func decodeBase64URL(_ string: String) -> Data? {
        var base = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while base.count % 4 != 0 { base += "=" }
        return Data(base64Encoded: base)
    }

    private static func form(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return fields.map { key, value in
            key + "=" + (value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value)
        }
        .joined(separator: "&")
        .data(using: .utf8) ?? Data()
    }

    private static func randomString(_ length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return String(base64URL(Data(bytes)).prefix(length))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func sha256(_ data: Data) -> [UInt8] {
        Array(SHA256.hash(data: data))
    }

    // MARK: Keychain (refresh tokens)

    private static func keychainQuery(_ email: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: keychainService,
         kSecAttrAccount as String: email]
    }

    private static func saveRefreshToken(_ token: String, for email: String) {
        SecItemDelete(keychainQuery(email) as CFDictionary)
        var item = keychainQuery(email)
        item[kSecValueData as String] = Data(token.utf8)
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    private static func refreshToken(for email: String) -> String? {
        var query = keychainQuery(email)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteRefreshToken(for email: String) {
        SecItemDelete(keychainQuery(email) as CFDictionary)
    }
}

// MARK: Browser sign-in

/// Google's sign-in page in ASWebAuthenticationSession, back through the client's redirect scheme.
@MainActor
private final class GmailWebAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static var running: GmailWebAuth?
    private var session: ASWebAuthenticationSession?

    static func run(url: URL, scheme: String) async throws -> URL {
        let auth = GmailWebAuth()
        running = auth
        defer { running = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    continuation.resume(throwing: GmailError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? GmailError.cancelled)
                }
            }
            session.presentationContextProvider = auth
            session.prefersEphemeralWebBrowserSession = false
            auth.session = session
            if !session.start() { continuation.resume(throwing: GmailError.http(0, "ログイン画面を開けませんでした")) }
        }
    }

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}
