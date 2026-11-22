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
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var chosen: Set<String> = []
    @State private var name = ""

    private var friends: [ToocUser] {
        let all = store.friends.sorted { $0.displayName < $1.displayName }
        guard !query.isEmpty else { return all }
        return all.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) || $0.id.localizedCaseInsensitiveContains(query)
        }
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
                                Text(friend.displayName)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if group {
                                    Image(systemName: chosen.contains(friend.id) ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(chosen.contains(friend.id) ? theme.accent : Color.secondary)
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
        let names = members.compactMap { store.user($0)?.displayName }
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
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var found: ToocUser?
    @State private var error: String?
    @FocusState private var focused: Bool

    private static let fieldHeight: CGFloat = 44

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
                .frame(height: Self.fieldHeight)
                .background(theme.card, in: Capsule())
                // As tall as the field.
                Button(action: search) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: Self.fieldHeight, height: Self.fieldHeight)
                        .background(Circle().fill(text.isEmpty ? Color.secondary.opacity(0.4) : theme.accent))
                }
                .buttonStyle(.plain)
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
            Text(current.displayName)
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
        .background(theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
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
    @State private var backgroundFile: String?
    @State private var hasBackground = true
    @State private var hasBirthday = false
    @State private var birthday = Calendar.current.date(from: DateComponents(year: 2005, month: 1, day: 1)) ?? .now
    @State private var iconItem: PhotosPickerItem?
    @State private var backgroundItem: PhotosPickerItem?
    @State private var crop: ToocCropRequest?
    /// Photos made here and not kept, removed on leaving.
    @State private var made: [String] = []
    @State private var loaded = false

    private var preview: ToocUser {
        var user = store.me
        user.name = name.isEmpty ? store.me.id : name
        user.hue = hue
        user.iconFile = iconFile
        user.backgroundFile = backgroundFile
        user.hasBackground = hasBackground
        return user
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack(alignment: .bottom) {
                        // The background as the profile shows it, with the icon on top.
                        ToocIconBackdrop(user: preview, blur: 0)
                            .frame(height: 170)
                            .overlay(Color.black.opacity(preview.backgroundFile == nil && !hasBackground ? 0.6 : 0.15))
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        ToocAvatar(user: preview, size: 92)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                            .offset(y: 30)
                    }
                    .padding(.bottom, 34)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section("アイコン") {
                    PhotosPicker(selection: $iconItem, matching: .images) {
                        Label("写真を選んで切り抜く", systemImage: "person.crop.circle")
                    }
                    if iconFile != nil {
                        Button("写真を外す", systemImage: "xmark.circle", role: .destructive) {
                            withAnimation(.snappy) { iconFile = nil }
                        }
                    } else {
                        Slider(value: $hue, in: 0...1) { Text("色") }
                            .tint(Color(hue: hue, saturation: 0.55, brightness: 0.85))
                    }
                }
                Section("背景") {
                    PhotosPicker(selection: $backgroundItem, matching: .images) {
                        Label("写真を選んで切り抜く", systemImage: "photo")
                    }
                    if backgroundFile != nil {
                        Button("背景の写真を外す", systemImage: "xmark.circle", role: .destructive) {
                            withAnimation(.snappy) { backgroundFile = nil }
                        }
                    } else {
                        Toggle("アイコンから背景をつくる", isOn: $hasBackground)
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
                    Toggle("誕生日を表示", isOn: $hasBirthday.animation(.snappy))
                    if hasBirthday {
                        DatePicker("誕生日", selection: $birthday, in: ...Date.now, displayedComponents: .date)
                    }
                }
                Section {
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
            .onChange(of: iconItem) { _, item in load(item, icon: true) }
            .onChange(of: backgroundItem) { _, item in load(item, icon: false) }
            .sheet(item: $crop) { request in
                ToocCropView(image: request.image, aspect: request.icon ? 1 : 1.6, circle: request.icon) { cropped in
                    guard let file = ToocFiles.save(cropped, side: request.icon ? 1024 : 2048) else { return }
                    made.append(file)
                    withAnimation(.snappy) {
                        if request.icon { iconFile = file } else { backgroundFile = file }
                    }
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let me = store.me
            name = me.name
            bio = me.bio
            hue = me.hue
            iconFile = me.iconFile
            backgroundFile = me.backgroundFile
            hasBackground = me.hasBackground
            hasBirthday = me.birthday != nil
            if let date = me.birthday { birthday = date }
        }
        .onDisappear {
            for file in made where file != store.me.iconFile && file != store.me.backgroundFile { ToocFiles.delete(file) }
        }
    }

    private func load(_ item: PhotosPickerItem?, icon: Bool) {
        guard let item else { return }
        if icon { iconItem = nil } else { backgroundItem = nil }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                crop = ToocCropRequest(image: image, icon: icon)
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        store.editProfile(name: trimmed.isEmpty ? store.me.id : trimmed, bio: bio, hue: hue, iconFile: iconFile,
                          backgroundFile: backgroundFile, hasBackground: hasBackground,
                          birthday: hasBirthday ? birthday : nil)
        dismiss()
    }
}

// MARK: - Search

/// Search across talks, friends and messages.
struct ToocSearchView: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme
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
            $0.displayName.localizedCaseInsensitiveContains(q) || $0.id.localizedCaseInsensitiveContains(q)
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
                        .listRowBackground(Color.clear)
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
                                    Text(friend.displayName).foregroundStyle(.primary)
                                    Text("@\(friend.id)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .listRowBackground(Color.clear)
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
                        .listRowBackground(Color.clear)
                    }
                }
            }
        }
        .listStyle(.plain)
        .toocBackground(theme)
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

// MARK: - Members, notices, scheduled

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
                        Text(member.id == store.me.id ? "\(member.displayName)（あなた）" : member.displayName)
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

/// お知らせ: messages that arrived while you were elsewhere, and friends added.
struct ToocNoticesView: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme

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
                                .foregroundStyle(theme.accent)
                                .frame(width: 40, height: 40)
                                .background(theme.card, in: Circle())
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
                .listRowBackground(Color.clear)
            }
            .onDelete { store.notices.remove(atOffsets: $0) }
        }
        .listStyle(.plain)
        .toocBackground(theme)
        .overlay {
            if store.notices.isEmpty {
                ContentUnavailableView("お知らせはありません", systemImage: "bell")
            }
        }
        .toolbar {
            if !store.notices.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { withAnimation { store.notices.removeAll() } } label: { ToocBarIcon("trash") }
                        .accessibilityLabel("すべて削除")
                }
            }
        }
        .navigationTitle("お知らせ")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.markNoticesSeen() }
    }
}

/// Every message waiting to be sent, soonest first.
struct ToocScheduledView: View {
    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.toocTheme) private var theme

    var body: some View {
        let waiting = store.scheduledMessages
        List {
            ForEach(waiting) { entry in
                Button { router.path.append(.room(entry.room.id)) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        ToocAvatar(user: store.iconUser(of: entry.room), size: 40)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack {
                                Text(store.name(of: entry.room)).font(.subheadline.bold()).lineLimit(1)
                                Spacer()
                                Label(ToocTime.scheduled(entry.message.scheduledAt ?? .now), systemImage: "clock")
                                    .font(.caption)
                                    .foregroundStyle(theme.accent)
                            }
                            Text(entry.message.preview)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .listRowBackground(Color.clear)
                .swipeActions(edge: .leading) {
                    Button {
                        withAnimation(.snappy) { store.sendNow(entry.message.id, in: entry.room.id) }
                    } label: { Image(systemName: "paperplane.fill") }
                        .tint(theme.accent)
                        .accessibilityLabel("今すぐ送信")
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        withAnimation(.snappy) { store.deleteMessage(entry.message.id, in: entry.room.id) }
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("送信予約を取り消す")
                }
            }
        }
        .listStyle(.plain)
        .toocBackground(theme)
        .overlay {
            if waiting.isEmpty {
                ContentUnavailableView("送信予約はありません", systemImage: "clock",
                                       description: Text("送信ボタンを長押しして「時刻指定して送信」で予約できます。"))
            }
        }
        .navigationTitle("送信予約")
        .navigationBarTitleDisplayMode(.inline)
    }
}
