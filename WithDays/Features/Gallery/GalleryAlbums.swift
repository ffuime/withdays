import LocalAuthentication
import SwiftUI

/// The album list: Holder on top, the albums, then 最近削除した項目. ＋ makes an album.
struct GalleryAlbumsSheet: View {
    var onHolder: () -> Void

    @Environment(GalleryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [GalleryRoute] = []
    @State private var editing: GalleryAlbumEditing?
    @State private var deleting: GalleryAlbum?
    @State private var asking: GalleryPasscodeAsk?
    @Namespace private var zoom

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Section {
                    HolderBox(item: store.holderItem, action: onHolder)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    ForEach(store.albums) { album in
                        Button {
                            unlock(album) { path.append(.album(album.id)) }
                        } label: {
                            GalleryAlbumRow(album: album)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                unlock(album) { editing = GalleryAlbumEditing(album: album, isNew: false) }
                            } label: {
                                Label("編集", systemImage: "pencil.circle")
                                    .labelStyle(.iconOnly)
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                unlock(album) { deleting = album }
                            } label: {
                                Label("削除", systemImage: "minus.circle")
                                    .labelStyle(.iconOnly)
                            }
                            .tint(.red)
                        }
                    }
                } header: {
                    if !store.albums.isEmpty { Text("アルバム") }
                }
                Section {
                    NavigationLink(value: GalleryRoute.trash) {
                        HStack(spacing: 14) {
                            Image(systemName: "trash")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 60, height: 60)
                                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)))
                            Text("最近削除した項目")
                                .font(.system(size: 17, weight: .semibold))
                            Spacer()
                            Text("\(store.trashed.count)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Color.clear
                    .frame(height: 60)
                    .listRowBackground(Color.clear)
            }
            .navigationTitle("アルバム")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Button {
                    editing = GalleryAlbumEditing(album: GalleryAlbum(), isNew: true)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Color.brand).interactive(), in: .circle)
                .padding(20)
                .accessibilityLabel("アルバムを追加")
            }
            .navigationDestination(for: GalleryRoute.self) { route in
                GalleryDestination(route: route, zoom: zoom)
            }
        }
        .galleryNotice(store)
        .sheet(item: $editing) { editing in
            GalleryAlbumEditor(album: editing.album, isNew: editing.isNew) { store.saveAlbum($0) }
                .environment(store)
        }
        .sheet(item: $asking) { ask in
            GalleryPasscodeSheet(title: "「\(ask.album.name)」のパスコード", mode: .verify(ask.album)) { _ in
                asking = nil
                ask.then()
            }
        }
        .confirmationDialog("「\(deleting?.name ?? "")」を削除しますか？",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible, presenting: deleting) { album in
            Button("アルバムだけ削除", role: .destructive) {
                withAnimation(.snappy) { store.deleteAlbum(album.id, trashPhotos: false) }
            }
            Button("写真もゴミ箱に入れる", role: .destructive) {
                withAnimation(.snappy) { store.deleteAlbum(album.id, trashPhotos: true) }
            }
            Button("キャンセル", role: .cancel) {}
        } message: { album in
            Text(album.locked ? "アルバムだけ削除すると、中の写真はGalleryに表示されるようになります。" : "アルバムだけ削除しても、写真はGalleryに残ります。")
        }
        .onChange(of: scenePhase) { _, phase in
            // A locked album closes when the app leaves the screen.
            guard phase != .active else { return }
            let locked = Set(store.albums.filter(\.locked).map(\.id))
            let showsLocked = path.contains { route in
                guard case .album(let id) = route else { return false }
                return locked.contains(id)
            }
            if showsLocked {
                path.removeAll()
            }
        }
    }

    /// A locked album asks for Face ID or its passcode first.
    private func unlock(_ album: GalleryAlbum, then: @escaping () -> Void) {
        guard album.locked else { return then() }
        if album.lock == .passcode, album.passcode != nil {
            asking = GalleryPasscodeAsk(album: album, then: then)
        } else {
            Task {
                if await GalleryUnlock.deviceOwner(reason: "「\(album.name)」を開きます") { then() }
            }
        }
    }
}

struct GalleryAlbumEditing: Identifiable {
    let id = UUID()
    var album: GalleryAlbum
    var isNew: Bool
}

struct GalleryPasscodeAsk: Identifiable {
    let id = UUID()
    let album: GalleryAlbum
    let then: () -> Void
}

enum GalleryUnlock {
    /// Face ID (or the iPhone's passcode when Face ID can't be used).
    @MainActor
    static func deviceOwner(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return false }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }
}

/// The big Holder box at the top of the album list.
struct HolderBox: View {
    let item: GalleryItem?
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let item {
                        GalleryThumb(item: item)
                            .overlay(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom))
                    } else {
                        LinearGradient(colors: [Color.brand.opacity(0.75), Color.brand], startPoint: .top, endPoint: .bottom)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 150)
                .clipped()
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                            .font(.system(size: 18, weight: .semibold))
                        Text("Holder")
                            .font(.system(size: 26, weight: .bold))
                    }
                    Text(item == nil ? "写真を1枚、全画面で表示します" : "全画面で表示。画面の長押しで設定")
                        .font(.system(size: 13, weight: .medium))
                        .opacity(0.85)
                }
                .foregroundStyle(.white)
                .padding(18)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Holderを開く")
    }
}

/// An album in the list: its thumbnail, its name, how many, ›.
struct GalleryAlbumRow: View {
    let album: GalleryAlbum
    @Environment(GalleryStore.self) private var store

    var body: some View {
        HStack(spacing: 14) {
            Group {
                if let cover = store.cover(album) {
                    GalleryThumb(item: cover)
                } else {
                    Image(systemName: album.locked ? "lock.fill" : "photo.on.rectangle")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.tertiarySystemFill))
                }
            }
            .frame(width: 60, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            HStack(spacing: 6) {
                Text(album.name.isEmpty ? "名称未設定" : album.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)
                if album.locked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Text("\(store.count(album))")
                .font(.system(size: 15, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// An album's thumbnail, name and lock.
struct GalleryAlbumEditor: View {
    var onSave: (GalleryAlbum) -> Void
    let isNew: Bool

    @Environment(GalleryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var album: GalleryAlbum
    @State private var choosingCover = false
    @State private var settingPasscode = false
    @FocusState private var nameFocused: Bool

    init(album: GalleryAlbum, isNew: Bool, onSave: @escaping (GalleryAlbum) -> Void) {
        _album = State(initialValue: album)
        self.isNew = isNew
        self.onSave = onSave
    }

    private var canSave: Bool {
        !album.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !(album.locked && album.lock == .passcode && album.passcode == nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Button {
                        choosingCover = true
                    } label: {
                        Group {
                            if let cover = store.item(album.cover) {
                                GalleryThumb(item: cover)
                            } else {
                                VStack(spacing: 8) {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 36, weight: .semibold))
                                    Text("サムネイルを選ぶ")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(Color(.tertiarySystemFill))
                            }
                        }
                        .frame(width: 180, height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("サムネイル")
                    .padding(.top, 12)

                    TextField("アルバム名", text: $album.name)
                        .font(.system(size: 28, weight: .bold))
                        .multilineTextAlignment(.center)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .padding(.horizontal, 24)

                    VStack(spacing: 0) {
                        Toggle(isOn: $album.locked.animation(.snappy)) {
                            Label("ロック", systemImage: "lock")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .padding(16)
                        if album.locked {
                            Divider().padding(.leading, 16)
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("ロック方法", selection: $album.lock) {
                                    ForEach(GalleryLock.allCases) { lock in
                                        Text(lock.label).tag(lock)
                                    }
                                }
                                .pickerStyle(.segmented)
                                if album.lock == .passcode {
                                    Button(album.passcode == nil ? "パスコードを設定" : "パスコードを変更") {
                                        settingPasscode = true
                                    }
                                    .font(.system(size: 15, weight: .semibold))
                                }
                                Text("ロックしたアルバムの写真は、Galleryの一覧やほかのアルバムには表示されません。")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(16)
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 30)
            }
            .navigationTitle(isNew ? "新規アルバム" : "アルバムを編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("キャンセル")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        album.name = album.name.trimmingCharacters(in: .whitespaces)
                        onSave(album)
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(!canSave)
                    .accessibilityLabel("保存")
                }
            }
            .onChange(of: album.lock) { _, lock in
                if lock == .passcode, album.passcode == nil { settingPasscode = true }
            }
            .onAppear { if isNew { nameFocused = true } }
        }
        .sheet(isPresented: $choosingCover) {
            let inAlbum = store.pickable(in: album.id)
            GalleryItemPicker(title: "サムネイル", items: inAlbum.isEmpty ? store.pickable() : inAlbum) { item in
                album.cover = item.id
                // A thumbnail from outside joins the album.
                if !album.items.contains(item.id) { album.items.append(item.id) }
            }
            .environment(store)
        }
        .sheet(isPresented: $settingPasscode, onDismiss: {
            if album.lock == .passcode, album.passcode == nil { album.lock = .faceID }
        }) {
            GalleryPasscodeSheet(title: "4桁のパスコード", mode: .create) { code in
                album.passcode = GalleryStore.hash(code, album: album.id)
                settingPasscode = false
            }
        }
    }
}

/// Choose one photo (a thumbnail, Holder's photo).
struct GalleryItemPicker: View {
    let title: String
    let items: [GalleryItem]
    var onPick: (GalleryItem) -> Void

    @Environment(\.dismiss) private var dismiss
    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: Self.columns, spacing: 2) {
                    ForEach(items) { item in
                        Button {
                            onPick(item)
                            dismiss()
                        } label: {
                            Color.clear
                                .aspectRatio(1, contentMode: .fit)
                                .overlay { GalleryThumb(item: item) }
                                .clipped()
                                .overlay(alignment: .bottom) { GalleryCellBadges(item: item) }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .overlay {
                if items.isEmpty {
                    ContentUnavailableView("写真がありません", systemImage: "photo.on.rectangle",
                                           description: Text("Galleryに写真を追加してください。"))
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
            }
        }
    }
}

/// アルバムに追加: pick an album (or make one) for these photos.
struct GalleryAddToAlbumSheet: View {
    let ids: [String]
    var onDone: () -> Void

    @Environment(GalleryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var creating: GalleryAlbumEditing?

    var body: some View {
        NavigationStack {
            List {
                Button {
                    creating = GalleryAlbumEditing(album: GalleryAlbum(), isNew: true)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.brand)
                            .frame(width: 60, height: 60)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(.tertiarySystemFill)))
                        Text("新規アルバム")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Color.brand)
                    }
                }
                ForEach(store.albums) { album in
                    Button {
                        add(to: album.id)
                    } label: {
                        GalleryAlbumRow(album: album)
                    }
                    .buttonStyle(.plain)
                }
            }
            .navigationTitle(ids.count == 1 ? "アルバムに追加" : "\(ids.count)項目をアルバムに追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $creating) { editing in
            GalleryAlbumEditor(album: editing.album, isNew: true) { album in
                store.saveAlbum(album)
                add(to: album.id)
            }
            .environment(store)
        }
    }

    private func add(to albumID: String) {
        store.add(ids, to: albumID)
        onDone()
        dismiss()
    }
}

/// 最近削除した項目: tap to choose, then 復元 or 削除. Each is removed for good 30 days after.
struct GalleryTrashView: View {
    @Environment(GalleryStore.self) private var store
    @State private var selected: Set<String> = []
    @State private var confirm: GalleryTrashConfirm?

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 5)

    var body: some View {
        let items = store.trashed
        let hidden = store.hidden
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: 2) {
                ForEach(items) { item in
                    Color.clear
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            if hidden.contains(item.id) {
                                // From a locked album: not shown here.
                                Image(systemName: "lock.fill")
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(Color(.tertiarySystemFill))
                            } else {
                                GalleryThumb(item: item)
                            }
                        }
                        .clipped()
                        .overlay(alignment: .bottomLeading) {
                            Text("\(daysLeft(item))日")
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.5), radius: 2)
                                .padding(4)
                        }
                        .overlay {
                            if selected.contains(item.id) { Color.white.opacity(0.25) }
                        }
                        .overlay(alignment: .topTrailing) {
                            GalleryCheck(on: selected.contains(item.id))
                                .padding(4)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if selected.contains(item.id) { selected.remove(item.id) } else { selected.insert(item.id) }
                        }
                }
            }
            Color.clear.frame(height: 100)
        }
        .overlay {
            if items.isEmpty {
                ContentUnavailableView("最近削除した項目はありません", systemImage: "trash",
                                       description: Text("削除した写真とビデオは、30日間ここに残ります。"))
            }
        }
        .overlay(alignment: .bottom) {
            if !items.isEmpty {
                HStack(spacing: 0) {
                    Button {
                        let ids = selected.isEmpty ? Set(items.map(\.id)) : selected
                        withAnimation(.snappy) { store.restore(ids) }
                        selected = []
                    } label: {
                        Text(selected.isEmpty ? "すべて復元" : "復元")
                            .font(.system(size: 15, weight: .semibold))
                            .padding(.horizontal, 22)
                            .frame(height: 50)
                            .contentShape(Rectangle())
                    }
                    Divider().frame(height: 24)
                    Button {
                        confirm = GalleryTrashConfirm(ids: selected.isEmpty ? Set(items.map(\.id)) : selected)
                    } label: {
                        Text(selected.isEmpty ? "すべて削除" : "削除")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 22)
                            .frame(height: 50)
                            .contentShape(Rectangle())
                    }
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .padding(.bottom, 12)
            }
        }
        .navigationTitle(selected.isEmpty ? "最近削除した項目" : "\(selected.count)項目を選択")
        .navigationBarTitleDisplayMode(.inline)
        .alert("\(confirm?.ids.count ?? 0)項目を完全に削除しますか？",
               isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
               presenting: confirm) { confirm in
            Button("キャンセル", role: .cancel) {}
            Button("完全に削除", role: .destructive) {
                withAnimation(.snappy) { store.purge(confirm.ids) }
                selected = []
            }
        } message: { _ in
            Text("この操作は取り消せません。")
        }
    }

    private func daysLeft(_ item: GalleryItem) -> Int {
        guard let deleted = item.deleted else { return 30 }
        let passed = Calendar.current.dateComponents([.day], from: deleted, to: .now).day ?? 0
        return max(30 - passed, 0)
    }
}

struct GalleryTrashConfirm: Identifiable {
    let id = UUID()
    let ids: Set<String>
}

// MARK: Passcode

enum GalleryPasscodeMode {
    /// Enter it twice.
    case create
    /// Check against an album's.
    case verify(GalleryAlbum)
}

/// Four digits on a keypad like the lock screen's.
struct GalleryPasscodeSheet: View {
    let title: String
    let mode: GalleryPasscodeMode
    var onDone: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var first: String?
    @State private var message = ""
    @State private var shake = 0

    private var prompt: String {
        switch mode {
        case .create: first == nil ? "新しいパスコードを入力" : "もう一度入力"
        case .verify: "パスコードを入力"
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer(minLength: 0)
                VStack(spacing: 8) {
                    Text(prompt)
                        .font(.system(size: 18, weight: .semibold))
                    Text(message)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(height: 16)
                }
                HStack(spacing: 22) {
                    ForEach(0..<4, id: \.self) { index in
                        Circle()
                            .strokeBorder(Color.primary, lineWidth: 1.5)
                            .background(Circle().fill(index < code.count ? Color.primary : .clear))
                            .frame(width: 14, height: 14)
                    }
                }
                .keyframeAnimator(initialValue: 0.0, trigger: shake) { view, x in
                    view.offset(x: x)
                } keyframes: { _ in
                    KeyframeTrack {
                        LinearKeyframe(-14.0, duration: 0.06)
                        LinearKeyframe(12.0, duration: 0.06)
                        LinearKeyframe(-9.0, duration: 0.06)
                        LinearKeyframe(6.0, duration: 0.06)
                        LinearKeyframe(-3.0, duration: 0.06)
                        LinearKeyframe(0.0, duration: 0.06)
                    }
                }
                Spacer(minLength: 0)
                keypad
            }
            .padding(.bottom, 24)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("キャンセル")
                }
            }
        }
        .sensoryFeedback(.error, trigger: shake)
    }

    private var keypad: some View {
        let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["", "0", "⌫"]]
        return VStack(spacing: 16) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 26) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func keyButton(_ key: String) -> some View {
        if key.isEmpty {
            Color.clear.frame(width: 76, height: 76)
        } else if key == "⌫" {
            Button {
                if !code.isEmpty { code.removeLast() }
            } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.primary)
                    .frame(width: 76, height: 76)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("削除")
        } else {
            Button {
                type(key)
            } label: {
                Text(key)
                    .font(.system(size: 32, weight: .regular, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(width: 76, height: 76)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .circle)
        }
    }

    private func type(_ digit: String) {
        guard code.count < 4 else { return }
        code += digit
        guard code.count == 4 else { return }
        let entered = code
        switch mode {
        case .create:
            if let first {
                if first == entered {
                    onDone(entered)
                } else {
                    fail("一致しませんでした。もう一度")
                    self.first = nil
                }
            } else {
                first = entered
                message = ""
                code = ""
            }
        case .verify(let album):
            if GalleryStore.hash(entered, album: album.id) == album.passcode {
                onDone(entered)
            } else {
                fail("パスコードが違います")
            }
        }
    }

    private func fail(_ text: String) {
        message = text
        shake += 1
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            code = ""
        }
    }
}
