import PhotosUI
import SwiftUI
import UIKit

/// toocIDs: 4–20 of a–z, 0–9, . and _.
enum ToocID {
    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._")

    static func normalize(_ text: String) -> String? {
        var id = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if id.hasPrefix("@") { id.removeFirst() }
        guard (4...20).contains(id.count), id.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return id
    }

    /// A tooc link's last part, or the text itself.
    static func fromQR(_ text: String) -> String? {
        if let url = URL(string: text), url.scheme != nil, url.host() != nil {
            return normalize(url.lastPathComponent)
        }
        return normalize(text)
    }
}

// MARK: - New talk / group

/// Pick a friend to talk to, or several (and a name) for a group.
struct ToocNewTalkView: View {
    let group: Bool

    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var chosen: Set<String> = []
    @State private var name = ""

    private var friends: [ToocUser] {
        let all = store.friends.sorted { $0.name < $1.name }
        guard !query.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        NavigationStack {
            List {
                if group {
                    Section {
                        TextField("グループ名", text: $name)
                    } footer: {
                        Text(chosen.isEmpty ? "メンバーを選んでください" : "\(chosen.count)人を選択中（あなたを含めて\(chosen.count + 1)人）")
                    }
                }
                Section {
                    ForEach(friends) { friend in
                        Button {
                            if group {
                                if chosen.contains(friend.id) { chosen.remove(friend.id) } else { chosen.insert(friend.id) }
                            } else {
                                router.open(room: store.room(with: friend.id).id)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ToocAvatar(user: friend, size: 40)
                                Text(friend.name)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if group {
                                    Image(systemName: chosen.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(chosen.contains(friend.id) ? Color.brand : Color.secondary)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .overlay {
                if store.friends.isEmpty {
                    ContentUnavailableView("友だちはまだいません", systemImage: "person.2")
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "名前・toocID")
            .navigationTitle(group ? "グループを作成" : "トークルームを作成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
                if group {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: makeGroup) { Image(systemName: "checkmark") }
                            .buttonStyle(.glassProminent)
                            .disabled(chosen.isEmpty)
                            .accessibilityLabel("作成")
                    }
                }
            }
        }
    }

    private func makeGroup() {
        let members = store.friends.map(\.id).filter(chosen.contains)
        let typed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let names = members.compactMap { store.user($0)?.name }
        let title = typed.isEmpty ? (names.prefix(3).joined(separator: "、") + (names.count > 3 ? "…" : "")) : typed
        router.open(room: store.makeGroup(name: title, members: members).id)
    }
}

// MARK: - Find by toocID

/// Look someone up by toocID and add them. With no server yet, the ID makes a provisional person.
struct ToocFindView: View {
    var initialID = ""
    /// Pushed inside another sheet (after a QR scan), so no close button or stack of its own.
    var embedded = false

    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var found: ToocUser?
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button { dismiss() } label: { Image(systemName: "xmark") }
                                .accessibilityLabel("閉じる")
                        }
                    }
            }
        }
    }

    private var content: some View {
        VStack(spacing: 24) {
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Text("@").foregroundStyle(.secondary)
                    TextField("toocID", text: $text)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.asciiCapable)
                        .submitLabel(.search)
                        .focused($focused)
                        .onSubmit(search)
                }
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(Color(.secondarySystemBackground), in: Capsule())
                Button(action: search) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.circle)
                .disabled(text.isEmpty)
                .accessibilityLabel("検索")
            }
            if let error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if let found {
                result(found)
                    .transition(.scale(scale: 0.95).combined(with: .opacity))
            }
            Spacer()
        }
        .padding(20)
        .navigationTitle("toocIDで検索")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            text = initialID
            if initialID.isEmpty { focused = true } else { search() }
        }
    }

    private func result(_ user: ToocUser) -> some View {
        let current = store.user(user.id) ?? user
        return VStack(spacing: 12) {
            ToocAvatar(user: current, size: 84)
            Text(current.name)
                .font(.title3.bold())
            Text("@\(current.id)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if current.id == store.me.id {
                Text("あなたのtoocIDです")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if current.isFriend && !current.isBlocked && !current.isHidden {
                Button {
                    router.open(room: store.room(with: current.id).id)
                } label: {
                    Label("トーク", systemImage: "message")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
            } else {
                Button {
                    withAnimation(.snappy) { store.addFriend(current) }
                } label: {
                    Label("友だちに追加", systemImage: "person.badge.plus")
                        .font(.headline)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.glassProminent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func search() {
        focused = false
        guard let id = ToocID.normalize(text) else {
            withAnimation(.snappy) {
                found = nil
                error = "toocIDは半角英数字と . _ の4〜20文字です。"
            }
            return
        }
        text = id
        withAnimation(.snappy) {
            error = nil
            found = id == store.me.id ? store.me : store.lookUp(id)
        }
    }
}

// MARK: - Edit profile

struct ToocEditProfileView: View {
    @Environment(ToocStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var bio = ""
    @State private var hue = 0.58
    @State private var iconFile: String?
    @State private var hasBackground = true
    @State private var photoItem: PhotosPickerItem?
    /// Photos chosen here and not kept, removed on leaving.
    @State private var picked: [String] = []
    @State private var loaded = false

    private var preview: ToocUser {
        var user = store.me
        user.name = name.isEmpty ? store.me.id : name
        user.hue = hue
        user.iconFile = iconFile
        return user
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 14) {
                        ToocAvatar(user: preview, size: 96)
                        HStack(spacing: 10) {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label("写真を選ぶ", systemImage: "photo")
                            }
                            .buttonStyle(.bordered)
                            if iconFile != nil {
                                Button("写真を外す", systemImage: "xmark", role: .destructive) {
                                    withAnimation(.snappy) { iconFile = nil }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                        .font(.subheadline)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
                if iconFile == nil {
                    Section("アイコンの色") {
                        Slider(value: $hue, in: 0...1)
                            .tint(Color(hue: hue, saturation: 0.55, brightness: 0.85))
                    }
                }
                Section("名前") {
                    TextField("名前", text: $name)
                        .onChange(of: name) { _, new in if new.count > 20 { name = String(new.prefix(20)) } }
                }
                Section {
                    TextField("ひとこと", text: $bio, axis: .vertical)
                        .lineLimit(3...8)
                        .onChange(of: bio) { _, new in if new.count > 500 { bio = String(new.prefix(500)) } }
                } header: {
                    Text("Mybio")
                } footer: {
                    Text("\(bio.count)/500")
                }
                Section {
                    Toggle("アイコンから背景をつくる", isOn: $hasBackground)
                    LabeledContent("toocID", value: "@\(store.me.id)")
                }
            }
            .navigationTitle("プロフィールを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("キャンセル")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .buttonStyle(.glassProminent)
                        .accessibilityLabel("保存")
                }
            }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                photoItem = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data),
                       let file = ToocPhotos.save(image, side: 1024) {
                        picked.append(file)
                        withAnimation(.snappy) { iconFile = file }
                    }
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            name = store.me.name
            bio = store.me.bio
            hue = store.me.hue
            iconFile = store.me.iconFile
            hasBackground = store.me.hasBackground
        }
        .onDisappear {
            for file in picked where file != store.me.iconFile { ToocPhotos.delete(file) }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.editProfile(name: trimmed.isEmpty ? store.me.id : trimmed, bio: bio, hue: hue, iconFile: iconFile,
                          hasBackground: hasBackground)
        dismiss()
    }
}

// MARK: - Search

/// Search across talks, friends and messages.
struct ToocSearchView: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @State private var query = ""
    @State private var presented = true

    private struct Hit: Identifiable {
        let room: ToocRoom
        let message: ToocMessage
        var id: UUID { message.id }
    }

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let rooms: [ToocRoom] = q.isEmpty ? [] : store.visibleRooms.filter { store.name(of: $0).localizedCaseInsensitiveContains(q) }
        let friends: [ToocUser] = q.isEmpty ? [] : store.friends.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q)
        }
        let hits: [Hit] = q.isEmpty ? [] : Self.hits(in: store.visibleRooms, q)
        List {
            if !rooms.isEmpty {
                Section("トーク") {
                    ForEach(rooms) { room in
                        Button { router.path = [.room(room.id)] } label: {
                            HStack(spacing: 12) {
                                ToocAvatar(user: store.iconUser(of: room), size: 40)
                                Text(store.name(of: room)).foregroundStyle(.primary)
                            }
                        }
                    }
                }
            }
            if !friends.isEmpty {
                Section("友だち") {
                    ForEach(friends) { friend in
                        Button { router.sheet = .profile(friend.id) } label: {
                            HStack(spacing: 12) {
                                ToocAvatar(user: friend, size: 40)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(friend.name).foregroundStyle(.primary)
                                    Text("@\(friend.id)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            if !hits.isEmpty {
                Section("メッセージ") {
                    ForEach(hits) { hit in
                        Button { router.path = [.room(hit.room.id)] } label: {
                            HStack(spacing: 12) {
                                ToocAvatar(user: store.iconUser(of: hit.room), size: 40)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(store.name(of: hit.room)).font(.subheadline.bold())
                                        Spacer()
                                        Text(ToocTime.listLabel(hit.message.date)).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(hit.message.preview)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .foregroundStyle(.primary)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if !q.isEmpty, rooms.isEmpty, friends.isEmpty, hits.isEmpty {
                ContentUnavailableView.search(text: q)
            }
        }
        .searchable(text: $query, isPresented: $presented, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "トーク・友だち・メッセージ")
        .navigationTitle("検索")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func hits(in rooms: [ToocRoom], _ q: String) -> [Hit] {
        var result: [Hit] = []
        for room in rooms {
            for message in room.sent.reversed() {
                if case .text(let text) = message.kind, text.localizedCaseInsensitiveContains(q) {
                    result.append(Hit(room: room, message: message))
                }
            }
        }
        return result
    }
}

/// Search inside one talk; picking a message scrolls to it.
struct ToocRoomSearchView: View {
    let roomID: String
    var onPick: (UUID) -> Void

    @Environment(ToocStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var presented = true

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let sent: [ToocMessage] = store.room(roomID)?.sent ?? []
        let hits: [ToocMessage] = q.isEmpty ? [] : sent.reversed().filter { (message: ToocMessage) -> Bool in
            if case .text(let text) = message.kind { return text.localizedCaseInsensitiveContains(q) }
            return false
        }
        NavigationStack {
            List(hits) { message in
                Button { onPick(message.id) } label: {
                    HStack(alignment: .top, spacing: 10) {
                        ToocAvatar(user: store.user(message.senderID) ?? store.me, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ToocTime.listLabel(message.date) + " " + ToocTime.clock(message.date))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(message.preview)
                                .foregroundStyle(.primary)
                                .lineLimit(3)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .overlay {
                if !q.isEmpty, hits.isEmpty { ContentUnavailableView.search(text: q) }
            }
            .searchable(text: $query, isPresented: $presented, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "トーク内を検索")
            .navigationTitle("トーク内を検索")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
            }
        }
    }
}

// MARK: - Members, notices

struct ToocMembersView: View {
    let roomID: String

    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let members = [store.me] + (store.room(roomID)?.memberIDs ?? []).compactMap { store.user($0) }
        NavigationStack {
            List(members) { member in
                Button {
                    dismiss()
                    if member.id != store.me.id { router.sheet = .profile(member.id) }
                } label: {
                    HStack(spacing: 12) {
                        ToocAvatar(user: member, size: 40)
                        Text(member.id == store.me.id ? "\(member.name)（あなた）" : member.name)
                            .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("メンバー（\(members.count)）")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
            }
        }
    }
}

/// お知らせ: messages that arrived while you were elsewhere, friends added, scheduled messages sent.
struct ToocNoticesView: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router

    var body: some View {
        List {
            ForEach(store.notices) { notice in
                Button {
                    if let room = notice.roomID, store.room(room) != nil {
                        router.path.append(.room(room))
                    } else if let user = notice.userID {
                        router.sheet = .profile(user)
                    }
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        if let id = notice.userID, let user = store.user(id) {
                            ToocAvatar(user: user, size: 40)
                        } else {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(Color.brand)
                                .frame(width: 40, height: 40)
                                .background(Color(.secondarySystemBackground), in: Circle())
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(notice.title).font(.subheadline.bold()).lineLimit(1)
                                Spacer()
                                Text(ToocTime.listLabel(notice.date)).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(store.settings.showContent ? notice.body : "新しいお知らせがあります")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }
            .onDelete { store.notices.remove(atOffsets: $0) }
        }
        .listStyle(.plain)
        .overlay {
            if store.notices.isEmpty {
                ContentUnavailableView("お知らせはありません", systemImage: "bell")
            }
        }
        .toolbar {
            if !store.notices.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation { store.notices.removeAll() } } label: { Image(systemName: "trash") }
                        .accessibilityLabel("すべて削除")
                }
            }
        }
        .navigationTitle("お知らせ")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.markNoticesSeen() }
    }
}
