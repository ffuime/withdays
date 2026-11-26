import SwiftUI

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
                    Text("通報は tooc の公式アカウント（@\(ToocStore.officialID)）へのトークとして送られます。通報したことは相手には伝わりません。")
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
