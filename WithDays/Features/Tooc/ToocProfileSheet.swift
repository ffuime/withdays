import SwiftUI

private enum ToocProfilePage: Hashable { case bio, name }

/// Someone's profile (or your own): their background, dark and blurred, with the icon in the middle and the name,
/// one line of bio and the birthday under it. Tap or pinch out the icon to see it whole; tap the bio or the name for
/// all of it; tap anywhere else to see the background clearly (tap again to go back).
struct ToocProfileSheet: View {
    let userID: String

    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var path: [ToocProfilePage] = []
    @State private var showQR = false
    @State private var editing = false
    @State private var clear = false
    @State private var renaming = false
    @State private var nickname = ""
    @FocusState private var nameFocused: Bool
    /// Your own name or bio, being changed right where it's shown.
    @State private var editingInPlace = false
    @State private var draft = ""
    @FocusState private var draftFocused: Bool

    /// The round icon's place on screen, so the enlarged one grows out of it and goes back into it.
    @State private var avatarFrame: CGRect = .zero
    @State private var zoomShown = false
    /// 0: the round icon; 1: the whole icon, as wide as the screen.
    @State private var progress: CGFloat = 0

    private static let avatarSize: CGFloat = 112

    private var user: ToocUser { store.user(userID) ?? store.lookUp(userID) }
    private var isMe: Bool { userID == store.me.id }

    var body: some View {
        NavigationStack(path: $path) {
            main
                .containerBackground(.clear, for: .navigation)
                .toolbar { toolbar }
                .navigationDestination(for: ToocProfilePage.self) { page in
                    detail(page)
                        .containerBackground(.clear, for: .navigation)
                }
        }
        .tint(.white)
        .background { backdrop.ignoresSafeArea() }
        .overlay { zoomLayer }
        .environment(\.colorScheme, .dark)
        .presentationBackground(.black)
        .sheet(isPresented: $showQR) { ToocQRView(start: .show) }
        .sheet(isPresented: $editing) { ToocEditProfileView() }

    }

    // MARK: Parts

    /// Their background photo, or one drawn from their icon; dark and blurred unless cleared by a tap.
    private var backdrop: some View {
        ZStack {
            if user.backgroundFile != nil || user.backgroundURL != nil || user.hasBackground {
                ToocIconBackdrop(user: user, blur: clear ? 0 : 9)
            } else {
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
            }
            Color.black.opacity(clear ? 0 : 0.3)
        }
        .animation(.easeInOut(duration: 0.35), value: clear)
    }

    /// The icon sits in the middle of the sheet; the name, bio and birthday hang from it.
    private var main: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                // Empty space: a tap clears the background.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { clear.toggle() }
                VStack(spacing: 14) {
                    ToocIconImage(user: user)
                        .frame(width: Self.avatarSize, height: Self.avatarSize)
                        .clipShape(Circle())
                        .opacity(zoomShown ? 0 : 1)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { avatarFrame = $0 }
                        .onTapGesture(perform: openZoom)
                        .gesture(pinchOpen)
                        .accessibilityLabel("アイコンを拡大")
                        .accessibilityAddTraits(.isButton)
                    Button { path.append(.name) } label: {
                        HStack(spacing: 6) {
                            Text(user.displayName)
                                .toocFont(.title2.bold())
                                .lineLimit(1)
                            if user.nickname != nil {
                                Image(systemName: "pencil")
                                    .toocFont(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .accessibilityLabel("表示名を変更済み")
                            }
                        }
                        .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    if user.bio.isEmpty, isMe {
                        Button { path.append(.bio) } label: {
                            Text("Mybioを入力")
                                .toocFont(.subheadline)
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .buttonStyle(.plain)
                    } else if !user.bio.isEmpty {
                        Button { path.append(.bio) } label: {
                            Text(user.bio)
                                .toocFont(.subheadline)
                                .foregroundStyle(.white.opacity(0.8))
                                .lineLimit(1)
                        }
                        .buttonStyle(.plain)
                    }
                    if let birthday = user.birthday {
                        Label(ToocTime.birthday(birthday), systemImage: "birthday.cake")
                            .toocFont(.footnote)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.top, max(0, (proxy.size.height - Self.avatarSize) / 2))
                .opacity(clear ? 0 : 1)
                .allowsHitTesting(!clear)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
            .animation(.easeInOut(duration: 0.3), value: clear)
        }
        .ignoresSafeArea()
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: {
                Image(systemName: "xmark").foregroundStyle(.white)
            }
            .accessibilityLabel("閉じる")
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if isMe {
                Button { editing = true } label: {
                    Image(systemName: "pencil").foregroundStyle(.white)
                }
                .accessibilityLabel("プロフィールを編集")
                Button { showQR = true } label: {
                    Image(systemName: "qrcode").foregroundStyle(.white)
                }
                .accessibilityLabel("MyQR")
            } else if user.isFriend, !user.isBlocked {
                Button {
                    router.open(room: store.room(with: user.id).id)
                } label: {
                    Image(systemName: "message").foregroundStyle(.white)
                }
                .accessibilityLabel("トーク")
            } else {
                Button {
                    withAnimation(.snappy) { store.addFriend(user) }
                } label: {
                    Image(systemName: "person.badge.plus").foregroundStyle(.white)
                }
                .accessibilityLabel("友だち追加")
            }
        }
    }

    /// All of the bio, or the name with the toocID (and 変更 for a friend's display name).
    @ViewBuilder
    private func detail(_ page: ToocProfilePage) -> some View {
        GeometryReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch page {
                case .bio:
                    if editingInPlace {
                        TextField("Mybio", text: $draft, axis: .vertical)
                            .toocFont(.body)
                            .foregroundStyle(.white)
                            .focused($draftFocused)
                    } else {
                        Text(user.bio.isEmpty && isMe ? "Mybioはまだありません" : user.bio)
                            .toocFont(.body)
                            .foregroundStyle(.white.opacity(user.bio.isEmpty ? 0.55 : 1))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .name:
                    if editingInPlace {
                        TextField(store.me.id, text: $draft)
                            .toocFont(.largeTitle.bold())
                            .foregroundStyle(.white)
                            .focused($draftFocused)
                            .submitLabel(.done)
                            .onSubmit { finishInPlace(page) }
                    } else if renaming {
                        // The name itself becomes the field; empty goes back to their own name.
                        TextField(user.name, text: $nickname)
                            .toocFont(.largeTitle.bold())
                            .foregroundStyle(.white)
                            .focused($nameFocused)
                            .submitLabel(.done)
                            .onSubmit(finishRename)
                    } else {
                        Text(user.displayName)
                            .toocFont(.largeTitle.bold())
                            .foregroundStyle(.white)
                    }
                    if user.nickname != nil {
                        Text("本人の名前：\(user.name)")
                            .toocFont(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    Text("@\(user.id)")
                        .toocFont(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            // At least the screen's height, so a short one sits in the middle; a long one scrolls in full.
            .frame(minHeight: proxy.size.height, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
        }
        .onDisappear { if editingInPlace { finishInPlace(page) } }
        .toolbar {
            if isMe {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if editingInPlace {
                            finishInPlace(page)
                        } else {
                            draft = page == .name ? store.me.name : store.me.bio
                            withAnimation(.snappy) { editingInPlace = true }
                            draftFocused = true
                        }
                    } label: {
                        Image(systemName: editingInPlace ? "checkmark" : "pencil")
                            .foregroundStyle(.white)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .accessibilityLabel(editingInPlace ? "完了" : (page == .name ? "名前を編集" : "Mybioを編集"))
                }
            }
            if page == .name, !isMe, store.users[userID] != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(renaming ? "完了" : "変更") {
                        if renaming {
                            finishRename()
                        } else {
                            nickname = user.nickname ?? user.name
                            renaming = true
                            nameFocused = true
                        }
                    }
                    .fontWeight(renaming ? .semibold : .regular)
                    .foregroundStyle(.white)
                }
            }
        }
    }

    private func finishInPlace(_ page: ToocProfilePage) {
        switch page {
        case .name: store.editNameAndBio(name: draft)
        case .bio: store.editNameAndBio(bio: draft.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        withAnimation(.snappy) { editingInPlace = false }
        draftFocused = false
    }

    private func finishRename() {
        let typed = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
        store.rename(userID, to: typed == user.name ? nil : typed)
        renaming = false
        nameFocused = false
    }

    // MARK: Enlarged icon

    /// Pinching out the round icon opens it along with the fingers.
    private var pinchOpen: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !zoomShown { zoomShown = true }
                progress = min(1, max(0, (value.magnification - 1) / 1.2))
            }
            .onEnded { _ in
                if progress > 0.25 {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { progress = 1 }
                } else {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) { progress = 0 } completion: {
                        zoomShown = false
                    }
                }
            }
    }

    @ViewBuilder
    private var zoomLayer: some View {
        if zoomShown {
            ToocZoomLayer(
                source: avatarFrame,
                aspect: 1,
                sourceRadius: Self.avatarSize / 2,
                progress: $progress,
                onClosed: { zoomShown = false }
            ) {
                ToocIconImage(user: user)
            } backdrop: {
                ZStack {
                    ToocIconBackdrop(user: user, blur: 10)
                    Color.black.opacity(0.55)
                }
            } accessory: {
                EmptyView()
            }
        }
    }

    private func openZoom() {
        progress = 0
        zoomShown = true
        Task { @MainActor in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) { progress = 1 }
        }
    }
}
