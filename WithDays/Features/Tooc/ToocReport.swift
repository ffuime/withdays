import SwiftUI

/// A report that has reached the report account, with the talk it came in.
struct ToocReportItem: Identifiable {
    let message: ToocMessage
    let roomID: String
    let record: ToocReportRecord
    var id: UUID { message.id }
}

/// The report account's mark: it is tooc's own.
struct ToocOfficialMark: View {
    var size: CGFloat = 16

    var body: some View {
        Image(systemName: "checkmark.seal.fill")
            .font(.system(size: size, weight: .semibold))
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color(red: 1.0, green: 0.36, blue: 0.3))
            .accessibilityLabel("公式")
    }
}

/// A report in a talk: for the one who sent it, what they reported and how it stands; for the report account,
/// with 対応済みにする.
struct ToocReportCard: View {
    let record: ToocReportRecord
    let messageID: UUID
    let roomID: String

    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme

    private static let red = Color(red: 1.0, green: 0.36, blue: 0.3)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("通報", systemImage: "flag.fill")
                    .toocFont(.caption.weight(.semibold))
                    .foregroundStyle(Self.red)
                Spacer(minLength: 12)
                ToocReportState(done: record.done)
            }
            Text(record.reasonLabel)
                .toocFont(.headline)
            Button {
                if let id = record.userID { router.sheet = .profile(id) }
            } label: {
                Text(record.targetLabel)
                    .toocFont(.subheadline)
                    .foregroundStyle(record.userID == nil ? Color.secondary : theme.accent)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .disabled(record.userID == nil)
            if store.isOfficial && !record.done {
                Divider()
                Button("対応済みにする") {
                    withAnimation(.snappy) { store.closeReport(messageID, in: roomID) }
                }
                .toocFont(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .frame(width: 250, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// 受付済み / 対応済み.
struct ToocReportState: View {
    let done: Bool

    var body: some View {
        Text(done ? "対応済み" : "受付済み")
            .toocFont(.caption2.weight(.bold))
            .foregroundStyle(done ? Color.white : Color.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(done ? Color.green : Color.primary.opacity(0.08), in: Capsule())
    }
}

/// The report account's 受付箱: every report as a card, newest first, by state and reason; how many times the same
/// one has been reported; the reporter and the reported a tap away; 対応済みにする.
struct ToocReportInbox: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme

    private enum Filter: String, CaseIterable, Identifiable {
        case open, done, all
        var id: String { rawValue }
        var label: String {
            switch self {
            case .open: "未対応"
            case .done: "対応済み"
            case .all: "すべて"
            }
        }
    }

    @State private var filter: Filter = .open
    @State private var reason: ToocReportReason?

    var body: some View {
        let all = store.reports
        let counts = Dictionary(grouping: all, by: { $0.record.targetKey }).mapValues(\.count)
        let shown = all.filter { item in
            switch filter {
            case .open: if item.record.done { return false }
            case .done: if !item.record.done { return false }
            case .all: break
            }
            return reason.map { $0.rawValue == item.record.reason } ?? true
        }
        List {
            ForEach(shown) { item in
                row(item, count: counts[item.record.targetKey] ?? 1)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            }
        }
        .listStyle(.plain)
        .toocBackground(theme)
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 10) {
                Picker("表示", selection: $filter.animation(.snappy)) {
                    ForEach(Filter.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Menu {
                    Picker("理由", selection: $reason.animation(.snappy)) {
                        Text("すべての理由").tag(ToocReportReason?.none)
                        ForEach(ToocReportReason.allCases) { Text($0.label).tag(Optional($0)) }
                    }
                } label: {
                    Image(systemName: reason == nil ? "line.3.horizontal.decrease.circle"
                                                    : "line.3.horizontal.decrease.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.primary)
                }
                .accessibilityLabel("理由で絞り込む")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .overlay {
            if shown.isEmpty {
                ContentUnavailableView(filter == .open ? "未対応の通報はありません" : "通報はありません",
                                       systemImage: "tray")
            }
        }
    }

    private func row(_ item: ToocReportItem, count: Int) -> some View {
        let record = item.record
        let reporter = item.message.senderID
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Label(record.reasonLabel, systemImage: "flag.fill")
                    .toocFont(.headline)
                    .foregroundStyle(Color.primary)
                Spacer(minLength: 8)
                ToocReportState(done: record.done)
            }
            HStack(spacing: 6) {
                Text("相手").toocFont(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                Button {
                    if let id = record.userID { router.sheet = .profile(id) }
                } label: {
                    Text(record.targetLabel)
                        .toocFont(.subheadline.weight(.semibold))
                        .foregroundStyle(record.userID == nil ? Color.primary : theme.accent)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                .disabled(record.userID == nil)
                if count > 1 {
                    Text("通報\(count)件")
                        .toocFont(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color(red: 1.0, green: 0.36, blue: 0.3), in: Capsule())
                }
            }
            HStack(spacing: 6) {
                Text("通報者").toocFont(.caption).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                Button { router.sheet = .profile(reporter) } label: {
                    Text("\(store.displayName(reporter))（@\(reporter)）")
                        .toocFont(.subheadline)
                        .foregroundStyle(theme.accent)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                Spacer(minLength: 8)
                Text(ToocTime.listLabel(item.message.date))
                    .toocFont(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 10) {
                Button {
                    router.open(room: item.roomID)
                } label: {
                    Label("トークを開く", systemImage: "message")
                        .toocFont(.subheadline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                if !record.done {
                    Button {
                        withAnimation(.snappy) { store.closeReport(item.message.id, in: item.roomID) }
                    } label: {
                        Text("対応済みにする")
                            .toocFont(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .padding(14)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Why someone (or a group) is reported.
enum ToocReportReason: String, CaseIterable, Identifiable {
    case spam, hate, sexual, dating, other
    var id: String { rawValue }

    var label: String {
        switch self {
        case .spam: "スパム・宣伝"
        case .hate: "ヘイト・攻撃的な行為"
        case .sexual: "性的な嫌がらせ"
        case .dating: "出会い目的"
        case .other: "その他"
        }
    }
}

/// 通報: choose why, and it goes to tooc's account as a message. The one reported isn't told.
struct ToocReportSheet: View {
    enum Target {
        case user(String)
        case group(String)
    }

    let target: Target

    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ToocReportReason?
    @State private var sent = false

    private var title: String {
        switch target {
        case .user(let id): "\(store.displayName(id))を通報"
        case .group: "グループを通報"
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ToocReportReason.allCases) { option in
                        Button {
                            withAnimation(.snappy) { reason = option }
                        } label: {
                            HStack {
                                Text(option.label).foregroundStyle(Color.primary)
                                Spacer()
                                if reason == option {
                                    Image(systemName: "checkmark")
                                        .fontWeight(.semibold)
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                    }
                } header: {
                    Text("通報の理由").toocFont(.footnote)
                } footer: {
                    Text("通報は tooc の通報用アカウント（@\(ToocStore.officialID)）へのトークとして送られます。通報したことは相手には伝わりません。")
                        .toocFont(.footnote)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("送信", systemImage: "checkmark") {
                        guard let reason else { return }
                        store.report(target, reason: reason)
                        sent = true
                    }
                    .disabled(reason == nil)
                }
            }
            .alert("通報しました", isPresented: $sent) {
                Button("OK") { dismiss() }
            } message: {
                Text("ご報告ありがとうございました。")
            }
        }
        .presentationDetents([.medium, .large])
    }
}
