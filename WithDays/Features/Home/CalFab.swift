import SwiftUI

/// Cal's ＋. A tap adds an event. Holding it dims and blurs the screen and Maps / Slides / Notes / Td / Go / Mo split out of it as liquid glass;
/// slide onto one and let go to open it, or let go on ＋ to add an event.
/// It keeps the finger's state to itself, so following the finger doesn't redraw the calendar.
struct CalFab: View {
    let icon: String
    /// The same size as the other bottom button (a glass button's circle), measured by the caller.
    let size: CGFloat
    /// Off while moving / duplicating, when ＋ is the confirm button.
    let menuEnabled: Bool
    let disabled: Bool
    var onTap: () -> Void
    var onOpenMenu: () -> Void
    var onPick: (HomeMode) -> Void

    @Namespace private var glass
    @State private var shown = false
    @State private var hover: HomeMode?
    /// The finger is still on ＋ (or hasn't moved).
    @State private var onFab = true
    @State private var fabFrame: CGRect = .zero
    /// The long press opened the menu; the release must not also count as a tap.
    @State private var longPressed = false

    private struct Item: Identifiable {
        let mode: HomeMode
        let name: String
        let logo: String
        /// An SF Symbol standing in until there's a logo.
        var symbol = false
        var id: HomeMode { mode }
    }

    /// Top to bottom; Cal's new event is ＋ itself.
    private static let items = [
        Item(mode: .maps, name: "Maps", logo: "map", symbol: true),
        Item(mode: .slides, name: "Slides", logo: "rectangle.on.rectangle.angled", symbol: true),
        Item(mode: .notes, name: "Notes", logo: "pencil.and.scribble", symbol: true),
        Item(mode: .todo, name: "Td", logo: "TdLogo"),
        Item(mode: .go, name: "Go", logo: "GoLogo"),
        Item(mode: .mo, name: "Mo", logo: "MoLogo"),
    ]
    private static let circle: CGFloat = 52
    private static let spacing: CGFloat = 26

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if shown {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .overlay(Color.black.opacity(0.12))
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }
            HStack(alignment: .bottom, spacing: 14) {
                labels
                // Small enough that a grown (hovered) logo never melts into the next one,
                // while a logo leaving ＋ still flows out of it.
                GlassEffectContainer(spacing: 10) {
                    VStack(alignment: .trailing, spacing: Self.spacing) {
                        if shown {
                            ForEach(Array(Self.items.enumerated()), id: \.element.id) { index, item in
                                logo(item)
                                    .transition(split(rank: Self.items.count - index))
                            }
                        }
                        fabButton
                    }
                }
            }
            .padding(20)
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: shown) { _, new in new }
        .sensoryFeedback(.selection, trigger: hover) { _, new in new != nil }
    }

    // MARK: Parts

    /// The names, level with their logos; they fade in once the logos have split off.
    private var labels: some View {
        VStack(alignment: .trailing, spacing: Self.spacing) {
            if shown {
                ForEach(Self.items) { item in
                    Text(item.name)
                        .font(.system(size: 22, weight: .regular))
                        .foregroundStyle(.primary)
                        .frame(height: Self.circle)
                        .scaleEffect(hover == item.mode ? 1.1 : 1, anchor: .trailing)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .offset(x: 12))
                                .animation(.easeOut(duration: 0.2).delay(0.18)),
                            removal: .opacity.animation(.easeIn(duration: 0.1))
                        ))
                }
            }
            Color.clear.frame(width: 0, height: size)
        }
        .allowsHitTesting(false)
    }

    private func logo(_ item: Item) -> some View {
        let hovered = hover == item.mode
        return Group {
            if item.symbol {
                Image(systemName: item.logo)
                    .font(.system(size: 20, weight: .semibold))
            } else {
                Image(item.logo)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
            }
        }
            .frame(width: 28, height: 28)
            .foregroundStyle(hovered ? Color.white : Color.brand)
            .frame(width: Self.circle, height: Self.circle)
            .glassEffect(hovered ? .regular.tint(Color.brand) : .regular, in: .circle)
            .glassEffectID(item.mode.rawValue, in: glass)
            .scaleEffect(hovered ? 1.1 : 1)
            // Lines up with the middle of ＋ below.
            .padding(.trailing, (size - Self.circle) / 2)
            .allowsHitTesting(false)
    }

    /// Each logo starts inside ＋ and is pulled up out of it; in the glass container they stay joined
    /// until they're far enough apart, so it reads as one drop splitting.
    private func split(rank: Int) -> AnyTransition {
        let distance = CGFloat(rank) * (Self.circle + Self.spacing) - (size - Self.circle) / 2
        return .asymmetric(
            insertion: .offset(y: distance).combined(with: .scale(scale: 0.6))
                .animation(.spring(response: 0.42, dampingFraction: 0.72).delay(Double(rank - 1) * 0.04)),
            removal: .offset(y: distance).combined(with: .scale(scale: 0.6)).combined(with: .opacity)
                .animation(.easeIn(duration: 0.18))
        )
    }

    private var fabButton: some View {
        Image(systemName: icon)
            .font(.system(size: 26.4, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            // Not interactive while the menu is up: the press effect would chase the finger.
            .glassEffect(.regular.tint(Color.brand).interactive(!shown), in: .circle)
            .glassEffectID("fab", in: glass)
            .contentShape(Circle())
            .scaleEffect(shown && hover == nil && onFab ? 1.06 : 1)
            .opacity(disabled ? 0.5 : 1)
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { fabFrame = $0 }
            .onTapGesture {
                if longPressed {
                    longPressed = false
                } else if !disabled {
                    onTap()
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.5)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
                    .onChanged { value in
                        guard menuEnabled, case .second(true, let drag) = value else { return }
                        if !shown {
                            longPressed = true
                            onOpenMenu()
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.72)) { shown = true }
                        }
                        guard let drag else { return }
                        // Only real changes are stored, so a moving finger doesn't redraw anything.
                        let target = item(at: drag.location)
                        let over = fabFrame.insetBy(dx: -8, dy: -8).contains(drag.location)
                        guard target != hover || over != onFab else { return }
                        // One explicit spring for each change, so the scales move smoothly.
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            hover = target
                            onFab = over
                        }
                    }
                    .onEnded { _ in
                        guard shown else { return }
                        let target = hover
                        let tapLike = onFab
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            shown = false
                            hover = nil
                        }
                        onFab = true
                        if let target {
                            onPick(target)
                        } else if tapLike {
                            onTap()
                        }
                        // The tap may or may not see the release; don't let the flag eat a later tap.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { longPressed = false }
                    }
            )
    }

    /// Which row the finger is on: worked out from ＋'s place (the rows sit at fixed steps above it),
    /// from well left of the names to the screen's edge, up to halfway to the next row.
    private func item(at point: CGPoint) -> HomeMode? {
        guard point.x >= fabFrame.maxX - 220 else { return nil }
        for (index, item) in Self.items.enumerated() {
            let rank = CGFloat(Self.items.count - 1 - index)
            let bottom = fabFrame.minY - Self.spacing - rank * (Self.circle + Self.spacing)
            let top = bottom - Self.circle
            if point.y >= top - Self.spacing / 2, point.y <= bottom + Self.spacing / 2 { return item.mode }
        }
        return nil
    }
}
