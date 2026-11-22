import SwiftUI

extension ToocAccounts.Saved {
    /// Enough of a user to draw the account's icon.
    var user: ToocUser {
        var user = ToocUser(id: id, name: name, bio: "", hue: hue)
        user.iconURL = iconURL
        return user
    }
}

/// The accounts on this device (from holding じぶん): tap one to switch, swipe to take it off this device, or sign in
/// to another.
struct ToocAccountsView: View {
    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var switching: String?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(store.savedAccounts) { saved in
                        Button { switchTo(saved.id) } label: {
                            HStack(spacing: 12) {
                                ToocAvatar(user: saved.id == store.me.id ? store.me : saved.user, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(saved.id == store.me.id ? store.me.name : saved.name)
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text("@\(saved.id)")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if switching == saved.id {
                                    ProgressView()
                                } else if saved.id == store.me.id {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.title3)
                                        .foregroundStyle(theme.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(switching != nil)
                        .swipeActions(edge: .trailing) {
                            if saved.id != store.me.id {
                                Button(role: .destructive) { store.forgetAccount(saved.id) } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("この端末から外す")
                            }
                        }
                    }
                }
                Section {
                    Button("別のアカウントでログイン", systemImage: "person.badge.plus") {
                        dismiss()
                        store.logOut()
                    }
                }
            }
            .navigationTitle("アカウント")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
            }
            .alert("切り替えられませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func switchTo(_ id: String) {
        guard id != store.me.id else { return dismiss() }
        switching = id
        dismiss()
        store.switchAccountShowingErrors(to: id)
    }
}

/// On the sign-in screen: the accounts this device remembers, one tap to sign back in.
struct ToocSavedAccountsSection: View {
    @Environment(ToocStore.self) private var store
    @State private var working: String?
    @State private var error: String?

    var body: some View {
        if !store.savedAccounts.isEmpty {
            Section("この端末のアカウント") {
                ForEach(store.savedAccounts) { saved in
                    Button {
                        working = saved.id
                        Task {
                            do {
                                try await store.switchAccount(to: saved.id)
                            } catch {
                                self.error = error.localizedDescription
                            }
                            working = nil
                        }
                    } label: {
                        HStack(spacing: 12) {
                            ToocAvatar(user: saved.user, size: 36)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(saved.name).foregroundStyle(.primary)
                                Text("@\(saved.id)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if working == saved.id { ProgressView() }
                        }
                    }
                    .disabled(working != nil)
                }
                .onDelete { offsets in
                    for index in offsets { store.forgetAccount(store.savedAccounts[index].id) }
                }
            }
            .alert("ログインできませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }
}
