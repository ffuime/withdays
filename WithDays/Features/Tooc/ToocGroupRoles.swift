import SwiftUI

/// A group's 管理人・権限: who the 管理人 are, the オペレーター and what each may do, and whether joining and
/// leaving are said in the talk. Only a 管理人 changes anything; everyone else sees who's who.
struct ToocGroupRolesView: View {
    let roomID: String

    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var transferTo: ToocUser?

    private var room: ToocRoom? { store.room(roomID) }

    var body: some View {
        NavigationStack {
            Group {
                if let room {
                    list(room)
                } else {
                    ContentUnavailableView("グループが見つかりません", systemImage: "person.3")
                }
            }
            .navigationTitle("管理人・権限")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Color.toocBrand) }
                        .accessibilityLabel("閉じる")
                }
            }
            .alert("管理人を譲りますか？", isPresented: Binding(get: { transferTo != nil }, set: { if !$0 { transferTo = nil } }),
                   presenting: transferTo) { user in
                Button("キャンセル", role: .cancel) {}
                Button("譲る") { withAnimation(.snappy) { store.transferAdmin(to: user.id, in: roomID) } }
            } message: { user in
                Text("\(user.displayName)が管理人になり、あなたは管理人ではなくなります。")
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func list(_ room: ToocRoom) -> some View {
        let admin = store.isAdmin(room)
        let everyone = [store.me] + room.memberIDs.compactMap { store.user($0) }
        let admins = everyone.filter { room.admins.contains($0.id) }
        let operators = everyone.filter { !room.admins.contains($0.id) && room.operators[$0.id] != nil }
        let members = everyone.filter { !room.admins.contains($0.id) && room.operators[$0.id] == nil }
        return List {
            Section {
                ForEach(admins) { user in row(user, role: "管理人", room: room, admin: admin) }
            } header: {
                Text("管理人")
            } footer: {
                Text("メンバーの追加・削除、グループプロフィールの変更、グループの削除、権限の設定ができます。")
            }
            if !operators.isEmpty {
                Section("オペレーター") {
                    ForEach(operators) { user in
                        row(user, role: "オペレーター", room: room, admin: admin)
                        if admin {
                            ForEach(ToocGroupPermission.allCases) { permission in
                                Toggle(isOn: Binding(
                                    get: { room.operators[user.id]?.contains(permission) == true },
                                    set: { on in
                                        var set = room.operators[user.id] ?? []
                                        if on { set.insert(permission) } else { set.remove(permission) }
                                        withAnimation(.snappy) { store.setOperator(user.id, permissions: set, in: roomID) }
                                    }
                                )) {
                                    Label(permission.label, systemImage: permission.symbol)
                                        .toocFont(.subheadline)
                                }
                                .padding(.leading, 44)
                            }
                        } else {
                            let granted = ToocGroupPermission.allCases.filter { room.operators[user.id]?.contains($0) == true }
                            Text(granted.isEmpty ? "権限なし" : granted.map(\.label).joined(separator: "・"))
                                .toocFont(.footnote)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 44)
                        }
                    }
                }
            }
            if !members.isEmpty {
                Section("メンバー") {
                    ForEach(members) { user in row(user, role: nil, room: room, admin: admin) }
                }
            }
            Section {
                Toggle("追加・退会をトークに表示", isOn: Binding(
                    get: { room.announceMembership },
                    set: { on in store.setAnnounceMembership(on, in: roomID) }
                ))
                .disabled(!admin)
            } footer: {
                Text("オンにすると「◯◯を追加しました」「◯◯が退会しました」がトークに出ます。")
            }
        }
        .tint(theme.accent)
    }

    /// Someone with their role; a 管理人 gets a menu to change it.
    private func row(_ user: ToocUser, role: String?, room: ToocRoom, admin: Bool) -> some View {
        let isMe = user.id == store.me.id
        let isAdmin = room.admins.contains(user.id)
        let isOperator = room.operators[user.id] != nil
        return HStack(spacing: 12) {
            ToocAvatar(user: user, size: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text(isMe ? "\(user.displayName)（あなた）" : user.displayName)
                    .toocFont(.body.weight(.semibold))
                    .lineLimit(1)
                if let role {
                    Text(role)
                        .toocFont(.caption)
                        .foregroundStyle(isAdmin ? Color.toocBrand : Color.secondary)
                }
            }
            Spacer()
            if admin {
                Menu {
                    if isAdmin {
                        if room.admins.count > 1 {
                            Button("管理人から外す", systemImage: "person.badge.minus") {
                                withAnimation(.snappy) { store.setAdmin(user.id, false, in: roomID) }
                            }
                        }
                    } else {
                        Button("管理人にする（共同）", systemImage: "person.2.badge.key") {
                            withAnimation(.snappy) { store.setAdmin(user.id, true, in: roomID) }
                        }
                        Button("管理人を譲る", systemImage: "arrow.right.circle") { transferTo = user }
                        if isOperator {
                            Button("オペレーターから外す", systemImage: "person.crop.circle.badge.xmark") {
                                withAnimation(.snappy) { store.setOperator(user.id, permissions: nil, in: roomID) }
                            }
                        } else {
                            Button("オペレーターにする", systemImage: "person.crop.circle.badge.checkmark") {
                                withAnimation(.snappy) {
                                    store.setOperator(user.id, permissions: [], in: roomID)
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .toocFont(.system(size: 20))
                        .foregroundStyle(Color.toocBrand)
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("\(user.displayName)の役割")
            }
        }
    }
}
