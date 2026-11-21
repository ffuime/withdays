import SwiftUI

private enum ToocProfilePage: Hashable { case bio, name }

/// Someone's profile (or your own): their background, dark and blurred, behind the icon, name and one line of bio.
/// Tap the icon to see it whole; tap the bio or the name for all of it.
struct ToocProfileSheet: View {
    let user: ToocUser
    /// Opens the talk with this friend; nil for yourself.
    var onTalk: (() -> Void)?

    @Environment(ToocStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var path: [ToocProfilePage] = []
    @State private var qr: ToocQRSheet?

    /// The icon's place in the sheet, so the enlarged icon grows out of it and goes back into it.
    @State private var avatarFrame: CGRect = .zero
    @State private var zoomShown = false
    @State private var zoomOpen = false
    @State private var zoomDrag: CGSize = .zero

    private static let space = "toocProfile"
    private static let avatarSize: CGFloat = 112

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
        .background { backdrop.ignoresSafeArea() }
        .overlay { zoomLayer }
        .coordinateSpace(.named(Self.space))
        .environment(\.colorScheme, .dark)
        .presentationBackground(.black)
        .sheet(item: $qr) { ToocQRView(start: $0) }
        .toocUnimplementedHost()
    }

    private var isMe: Bool { user.id == store.me.id }

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

    private var main: some View {
        VStack(spacing: 14) {
            Spacer()
            ToocIconImage(user: user)
                .frame(width: Self.avatarSize, height: Self.avatarSize)
                .clipShape(Circle())
                .opacity(zoomShown ? 0 : 1)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.space)) } action: { avatarFrame = $0 }
                .onTapGesture(perform: openZoom)
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
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .accessibilityLabel("閉じる")
        }
        ToolbarItem(placement: .topBarTrailing) {
            if isMe {
                Button { qr = .show } label: { Image(systemName: "qrcode") }
                    .accessibilityLabel("MyQR")
            } else if user.isFriend, let onTalk {
                Button(action: onTalk) { Image(systemName: "message") }
                    .accessibilityLabel("トーク")
            } else {
                AddFriendButton()
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

    /// The icon, uncut and as wide as the screen, grown out of the round one. Drag it anywhere to put it back.
    @ViewBuilder
    private var zoomLayer: some View {
        if zoomShown {
            GeometryReader { proxy in
                let width = proxy.size.width
                let full = CGRect(x: 0, y: (proxy.size.height - width) / 2, width: width, height: width)
                let distance: CGFloat = hypot(zoomDrag.width, zoomDrag.height)
                let shrink: CGFloat = max(0.7, 1 - distance / 900)
                let fade: Double = zoomOpen ? max(0, 1 - Double(distance) / 400) : 0
                // The round icon's place, from the sheet's space into this layer's (which reaches under the bars).
                let origin = proxy.frame(in: .named(Self.space)).origin
                let small = avatarFrame.offsetBy(dx: -origin.x, dy: -origin.y)
                let frame = zoomOpen ? full : small
                ZStack {
                    ZStack {
                        ToocIconBackdrop(user: user, blur: 60)
                        Color.black.opacity(0.55)
                    }
                    .opacity(fade)
                    .ignoresSafeArea()
                    ToocIconImage(user: user)
                        .frame(width: frame.width, height: frame.height)
                        .clipShape(RoundedRectangle(cornerRadius: zoomOpen ? 0 : frame.width / 2, style: .continuous))
                        .scaleEffect(zoomOpen ? shrink : 1)
                        .position(x: frame.midX + (zoomOpen ? zoomDrag.width : 0),
                                  y: frame.midY + (zoomOpen ? zoomDrag.height : 0))
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture()
                        .onChanged { zoomDrag = $0.translation }
                        .onEnded { value in
                            if hypot(value.translation.width, value.translation.height) > 90 {
                                closeZoom()
                            } else {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { zoomDrag = .zero }
                            }
                        }
                )
                .onTapGesture(perform: closeZoom)
            }
            .ignoresSafeArea()
        }
    }

    private func openZoom() {
        zoomDrag = .zero
        zoomShown = true
        Task { @MainActor in
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) { zoomOpen = true }
        }
    }

    private func closeZoom() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            zoomOpen = false
            zoomDrag = .zero
        } completion: {
            zoomShown = false
        }
    }
}

private struct AddFriendButton: View {
    @Environment(\.toocUnimplemented) private var unimplemented

    var body: some View {
        Button(action: unimplemented) { Image(systemName: "person.badge.plus") }
            .accessibilityLabel("友だち追加")
    }
}
