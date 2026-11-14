import SwiftUI

/// What the app opens on: the home screen, with the apps above it. An app grows out of its icon; a swipe up from
/// the bottom edge shrinks it back into its icon. The apps (HomeView) stay alive underneath, like suspended apps.
struct LauncherView: View {
    @State private var board = Springboard()
    /// Going home: the app is shrinking into its icon and doesn't take touches.
    @State private var closing = false
    /// The app's layout frame (its safe area), in screen points.
    @State private var appLayout: CGRect = .zero

    var body: some View {
        ZStack {
            SpringboardView(board: board, launch: launch)
                .visualEffect { [openness] content, _ in
                    // The home screen sinks back a little behind an open app (without moving its measured frames).
                    content.scaleEffect(1 - 0.07 * openness)
                }
                .overlay {
                    Color.black.opacity(0.3 * openness)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                }
                .allowsHitTesting(board.openApp == nil)
                .accessibilityHidden(board.openApp != nil)
            appLayer
        }
        .environment(board)
    }

    /// 0 with the app at its icon (or away), 1 with it filling the screen.
    private var openness: CGFloat {
        guard let rect = board.appRect, board.screen.width > 0 else { return 0 }
        let icon = board.iconSize
        return min(max((rect.width - icon) / max(board.screen.width - icon, 1), 0), 1)
    }

    // MARK: The app

    private var appLayer: some View {
        let open = board.openApp != nil
        return ZStack {
            HomeView()
                .opacity(board.openApp?.mode != nil ? 1 : 0)
                .allowsHitTesting(board.openApp?.mode != nil)
            if board.openApp == .settings {
                NavigationStack {
                    SettingsView()
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .overlay(alignment: .bottom) { homeBar }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { appLayout = $0 }
        .modifier(AppZoom(
            rect: board.appRect ?? board.screen, screen: board.screen, layout: appLayout, app: board.activeApp
        ))
        .opacity(open && board.appRect != nil ? 1 : 0)
        .allowsHitTesting(open && !closing)
        .accessibilityHidden(!open)
        // Swiping up from the bottom edge is ours while an app is open; the system's needs a second swipe.
        .defersSystemGestures(on: open ? .bottom : [])
        .persistentSystemOverlays(open ? .hidden : .automatic)
    }

    /// The bar along the bottom edge: drag it up to go home.
    private var homeBar: some View {
        Color.clear
            .frame(height: 24)
            .contentShape(Rectangle())
            .overlay(alignment: .bottom) {
                Capsule()
                    .fill(Color.primary.opacity(0.75))
                    .frame(width: 136, height: 5)
                    .padding(.bottom, 8)
            }
            .gesture(homeSwipe)
            .ignoresSafeArea(.all, edges: .bottom)
            .accessibilityElement()
            .accessibilityLabel("ホームへ")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { goHome() }
    }

    /// The app shrinks with the finger, its bottom under it; let go high enough (or flicked) and it goes home.
    private var homeSwipe: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                guard board.openApp != nil, !closing else { return }
                let screen = board.screen
                let up = max(0, -value.translation.height)
                let scale = max(0.3, 1 - up / (screen.height * 1.1))
                let width = screen.width * scale
                let height = screen.height * scale
                let bottom = min(value.location.y + 24 * scale, screen.maxY)
                let midX = screen.midX + value.translation.width * 0.7
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    board.appRect = CGRect(x: midX - width / 2, y: bottom - height, width: width, height: height)
                }
            }
            .onEnded { value in
                guard board.openApp != nil, !closing else { return }
                let up = -value.translation.height
                let flicked = value.predictedEndTranslation.height < -280
                if up > 110 || flicked {
                    goHome()
                } else {
                    withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { board.appRect = board.screen }
                }
            }
    }

    // MARK: Opening and closing

    private func launch(_ app: SpringApp, from icon: CGRect) {
        guard board.openApp == nil, board.screen.width > 0 else { return }
        board.open(app)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { board.appRect = icon }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) { board.appRect = board.screen }
        }
    }

    /// Into the app's icon (in the open folder, on the page shown or in the Dock); elsewhere, into the middle.
    private func goHome() {
        guard board.openApp != nil, !closing else { return }
        let screen = board.screen
        let size = board.iconSize
        let target = board.iconFrame(of: board.activeApp)
            ?? CGRect(x: screen.midX - size / 2, y: screen.midY - size / 2, width: size, height: size)
        closing = true
        withAnimation(.spring(response: 0.42, dampingFraction: 0.88)) {
            board.appRect = target
        } completion: {
            board.openApp = nil
            board.appRect = nil
            closing = false
        }
    }
}

/// Draws the app at `rect` (screen points): scaled to its width and cut to a rounded tile of its height, so it
/// morphs between the screen and the icon; near icon size the icon itself shows through.
struct AppZoom: ViewModifier, Animatable {
    var rect: CGRect
    let screen: CGRect
    let layout: CGRect
    let app: SpringApp

    var animatableData: CGRect.AnimatableData {
        get { rect.animatableData }
        set { rect.animatableData = newValue }
    }

    func body(content: Content) -> some View {
        let ready = screen.width > 0 && layout.width > 0 && rect.width > 0
        let full = ready ? screen : CGRect(x: 0, y: 0, width: 1, height: 1)
        let target = ready ? rect : full
        let scale = max(target.width / full.width, 0.01)
        // The screen in the app's own coordinates (its layout frame stops at the safe area).
        let local = CGPoint(x: full.midX - layout.minX, y: full.midY - layout.minY)
        let maskHeight = min(target.height / scale, full.height)
        let progress = min(max((target.width - 60) / max(full.width - 60, 1), 0), 1)
        let atFull = !ready || (abs(target.width - full.width) < 0.5 && abs(target.height - full.height) < 0.5)
        let corner = atFull ? 0 : iconCornerRadius(target.width) * (1 - progress) + 48 * progress
        let layoutCenter = CGPoint(x: layout.midX, y: layout.midY)
        let shift = ready ? CGSize(
            width: target.midX - (layoutCenter.x + (full.midX - layoutCenter.x) * scale),
            height: target.midY - (layoutCenter.y + (full.midY - layoutCenter.y) * scale)
        ) : .zero
        let iconAlpha: Double = ready ? Double(min(max(1 - progress * 2.4, 0), 1)) : 0
        content
            .overlay {
                AppIconArt(app: app, size: full.width)
                    .position(local)
                    .opacity(iconAlpha)
                    .allowsHitTesting(false)
            }
            .mask {
                RoundedRectangle(cornerRadius: corner / scale, style: .continuous)
                    .frame(width: atFull ? full.width * 3 : full.width, height: atFull ? full.height * 3 : maskHeight)
                    .position(local)
            }
            .scaleEffect(scale, anchor: .center)
            .offset(shift)
    }
}
