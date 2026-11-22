import SwiftUI

private enum ToocProfilePage: Hashable { case bio, name }

/// Someone's profile (or your own): their background, dark and blurred, with the icon in the middle and the name and
/// one line of bio under it. Tap or pinch out the icon to see it whole; tap the bio or the name for all of it.
struct ToocProfileSheet: View {
    let userID: String

    @Environment(ToocStore.self) private var store
    @Environment(ToocRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var path: [ToocProfilePage] = []
    @State private var showQR = false
    @State private var editing = false

    /// The round icon's place on screen, so the enlarged one grows out of it and goes back into it.
    @State private var avatarFrame: CGRect = .zero
    @State private var zoomShown = false
    /// 0: the round icon; 1: the whole icon, as wide as the screen. Gestures move it in between.
    @State private var progress: CGFloat = 0
    @State private var drag: CGSize = .zero

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

    private var backdrop: some View {
        ZStack {
            if user.hasBackground {
                ToocIconBackdrop(user: user, blur: 50)
            } else {
                LinearGradient(colors: [Color(white: 0.22), Color(white: 0.08)], startPoint: .top, endPoint: .bottom)
            }
            Color.black.opacity(0.45)
        }
    }

    /// The icon sits in the middle of the sheet; the name and bio hang from it.
    private var main: some View {
        GeometryReader { proxy in
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
                    Text(user.name)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .buttonStyle(.plain)
                if !user.bio.isEmpty {
                    Button { path.append(.bio) } label: {
                        Text(user.bio)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, max(0, (proxy.size.height - Self.avatarSize) / 2))
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
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

    /// All of the bio, or the name with the toocID: left-aligned, in the middle of the screen, on the same background.
    @ViewBuilder
    private func detail(_ page: ToocProfilePage) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                switch page {
                case .bio:
                    Text(user.bio)
                        .font(.body)
                        .foregroundStyle(.white)
                case .name:
                    Text(user.name)
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                    Text("@\(user.id)")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 28)
            .containerRelativeFrame(.vertical, alignment: .center)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    // MARK: Enlarged icon

    /// Pinching out the round icon opens it along with the fingers.
    private var pinchOpen: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if !zoomShown {
                    drag = .zero
                    zoomShown = true
                }
                progress = min(1, max(0, (value.magnification - 1) / 1.2))
            }
            .onEnded { _ in
                if progress > 0.25 { settleOpen() } else { closeZoom() }
            }
    }

    /// The icon, uncut and as wide as the screen, grown out of the round one. Dragging or pinching in takes it
    /// back step by step, its corners rounding as it shrinks.
    @ViewBuilder
    private var zoomLayer: some View {
        if zoomShown {
            GeometryReader { proxy in
                let layer = proxy.frame(in: .global)
                let small = avatarFrame.offsetBy(dx: -layer.minX, dy: -layer.minY)
                let width = proxy.size.width
                let full = CGRect(x: 0, y: (proxy.size.height - width) / 2, width: width, height: width)
                let rect = Self.mix(small, full, progress)
                ZStack {
                    ZStack {
                        ToocIconBackdrop(user: user, blur: 60)
                        Color.black.opacity(0.55)
                    }
                    .opacity(Double(progress))
                    ToocIconImage(user: user)
                        .frame(width: rect.width, height: rect.height)
                        .clipShape(RoundedRectangle(cornerRadius: rect.width / 2 * (1 - progress), style: .continuous))
                        .position(x: rect.midX + drag.width, y: rect.midY + drag.height)
                }
                .contentShape(Rectangle())
                .gesture(dragBack)
                .simultaneousGesture(pinchBack)
                .onTapGesture(perform: closeZoom)
            }
            .ignoresSafeArea()
        }
    }

    private var dragBack: some Gesture {
        DragGesture()
            .onChanged { value in
                drag = value.translation
                progress = max(0.3, 1 - hypot(value.translation.width, value.translation.height) / 500)
            }
            .onEnded { value in
                if hypot(value.translation.width, value.translation.height) > 90 { closeZoom() } else { settleOpen() }
            }
    }

    private var pinchBack: some Gesture {
        MagnifyGesture()
            .onChanged { value in progress = min(1, max(0, value.magnification)) }
            .onEnded { _ in if progress < 0.8 { closeZoom() } else { settleOpen() } }
    }

    private static func mix(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }

    private func openZoom() {
        drag = .zero
        progress = 0
        zoomShown = true
        Task { @MainActor in settleOpen() }
    }

    private func settleOpen() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
            progress = 1
            drag = .zero
        }
    }

    private func closeZoom() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            progress = 0
            drag = .zero
        } completion: {
            zoomShown = false
        }
    }
}
