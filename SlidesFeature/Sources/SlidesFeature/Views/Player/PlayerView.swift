import SwiftUI

/// The steps of a slide's animations: what runs on entering the slide, then what each tap runs.
struct AnimationPlan {
    struct Timed {
        let animation: ElementAnimation
        /// Seconds after the step starts.
        let start: Double
    }

    /// Runs as the slide appears (animations before the first タップ時).
    var auto: [Timed] = []
    var taps: [[Timed]] = []

    init(_ slide: SlideContent) {
        let present = Set(slide.elements.map(\.id))
        var autoSteps: [Timed] = []
        var tapSteps: [[Timed]] = []
        var current: [Timed] = []
        var isAuto = true
        var previousStart = 0.0
        var previousEnd = 0.0
        for animation in slide.animations where present.contains(animation.elementID) {
            let start: Double
            switch animation.start {
            case .onTap:
                if isAuto { autoSteps = current } else if !current.isEmpty { tapSteps.append(current) }
                current = []
                isAuto = false
                start = animation.delay
            case .withPrevious:
                start = previousStart + animation.delay
            case .afterPrevious:
                start = previousEnd + animation.delay
            }
            current.append(Timed(animation: animation, start: start))
            previousStart = start
            previousEnd = max(previousEnd, start + animation.duration)
            if animation.start == .onTap { previousEnd = start + animation.duration }
        }
        if isAuto { autoSteps = current } else if !current.isEmpty { tapSteps.append(current) }
        auto = autoSteps
        taps = tapSteps
    }
}

/// How an element looks at a moment of playback.
struct ElementLook: Equatable {
    var visible: Bool
    /// How it comes in or goes out.
    var effect: AnimationEffect
    var category: AnimationCategory
    var angle: Double = 90
    var zoomOut = false

    init(_ animation: ElementAnimation, visible: Bool) {
        self.visible = visible
        effect = animation.effect
        category = animation.category
        angle = animation.angle
        zoomOut = animation.zoomOut
    }

    /// 移動: where the same element was on the slide before, relative to where it is now.
    var moveFrom: MoveFrom?
}

/// The difference between an element and the same element on the slide before, in slide points.
struct MoveFrom: Equatable {
    var dx: Double = 0
    var dy: Double = 0
    var scaleX: Double = 1
    var scaleY: Double = 1
    var rotation: Double = 0
    var opacity: Double = 1

    static let none = MoveFrom()

    init() {}

    init(from old: SlideElement, to new: SlideElement) {
        dx = Double(old.frame.center.x - new.frame.center.x)
        dy = Double(old.frame.center.y - new.frame.center.y)
        scaleX = old.frame.width / max(new.frame.width, 1)
        scaleY = old.frame.height / max(new.frame.height, 1)
        rotation = old.rotation - new.rotation
        opacity = new.opacity > 0 ? old.opacity / new.opacity : 1
    }
}

/// 再生: full screen in landscape, one slide at a time on black.
/// Tap the right part (or swipe left) for next, the left part (or swipe right) for previous; a tap runs the next
/// animation step first. Tap the middle for the controls. Hold to edit this slide; swipe down to go back.
/// It opens on black, turns the screen, then fades the slide in (and the other way round when leaving),
/// so the turn happens out of sight.
struct PlayerView: View {
    let slides: [SlideContent]
    let deck: UUID
    var onExit: (Int) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index: Int
    @State private var step = 0
    @State private var looks: [UUID: ElementLook] = [:]
    @State private var forward = true
    /// During a transition: the slide leaving (drawn until the new one has fully arrived), how it looked, and how far
    /// the transition has got (0 → 1).
    @State private var outgoing: Int?
    @State private var outgoingLooks: [UUID: ElementLook] = [:]
    @State private var transitionKind = TransitionKind.none
    @State private var activeTransition = SlideTransition()
    @State private var progress: CGFloat = 1
    /// During a transition both slides are pictures, so even angled pushes move smoothly.
    @State private var outgoingImage: UIImage?
    @State private var incomingImage: UIImage?
    @State private var stageSize = CGSize(width: 1920, height: 1080)
    @Environment(\.displayScale) private var displayScale
    @State private var shown = false
    @State private var leaving = false
    @State private var showsControls = false
    @State private var hideControls: Task<Void, Never>?
    @State private var dragDown: CGFloat = 0
    /// Bumped on every slide change, so timers from the last slide stop.
    @State private var generation = 0
    /// Bumped when there's no slide to go to: the slide shakes.
    @State private var bump = 0

    init(slides: [SlideContent], deck: UUID, start: Int, onExit: @escaping (Int) -> Void) {
        self.slides = slides
        self.deck = deck
        self.onExit = onExit
        _index = State(initialValue: min(max(start, 0), max(slides.count - 1, 0)))
    }

    private var slide: SlideContent? { slides.indices.contains(index) ? slides[index] : nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            stage
                .ignoresSafeArea()
                .opacity(shown ? 1 : 0)
            if showsControls, shown {
                controls
                    .transition(.opacity)
            }
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear {
            enter(animated: false, runAuto: false)
            SlidesOrientation.lock(.landscape, turnTo: .landscapeRight)
            // After the turn, behind black.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                withAnimation(.easeOut(duration: 0.3)) { shown = true }
                enter(animated: true)
            }
        }
        .sensoryFeedback(.selection, trigger: index)
        .sensoryFeedback(.error, trigger: bump)
    }

    private var stage: some View {
        GeometryReader { geo in
            let scale = min(geo.size.width / 1920, geo.size.height / 1080)
            ZStack {
                if outgoing != nil, let outgoingImage {
                    Image(uiImage: outgoingImage)
                        .resizable()
                        .frame(width: 1920 * scale, height: 1080 * scale)
                        .modifier(SlideTransitionEffect(
                            kind: effectiveKind, transition: activeTransition, progress: progress, incoming: false,
                            forward: forward, size: geo.size
                        ))
                }
                if let slide {
                    ZStack {
                        PlayedSlide(slide: slide, deck: deck, scale: scale, looks: looks)
                            .opacity(incomingImage == nil ? 1 : 0)
                        if let incomingImage {
                            Image(uiImage: incomingImage)
                                .resizable()
                        }
                    }
                        .frame(width: 1920 * scale, height: 1080 * scale)
                        .modifier(SlideTransitionEffect(
                            kind: outgoing == nil ? .none : effectiveKind, transition: activeTransition, progress: progress, incoming: true,
                            forward: forward, size: geo.size
                        ))
                        .id(slide.id)
                        .scaleEffect(1 - min(dragDown, 600) / 1400)
                        .offset(y: dragDown)
                        .keyframeAnimator(initialValue: CGFloat(0), trigger: bump) { content, x in
                            content.offset(x: x)
                        } keyframes: { _ in
                            KeyframeTrack {
                                LinearKeyframe(-18, duration: 0.06)
                                LinearKeyframe(14, duration: 0.07)
                                LinearKeyframe(-8, duration: 0.07)
                                LinearKeyframe(4, duration: 0.06)
                                LinearKeyframe(0, duration: 0.06)
                            }
                        }
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
            .contentShape(Rectangle())
            .onAppear { stageSize = geo.size }
            .onChange(of: geo.size) { _, size in stageSize = size }
            .onTapGesture(coordinateSpace: .local) { location in
                tapped(at: location.x / max(geo.size.width, 1))
            }
            .onLongPressGesture(minimumDuration: 0.6) {
                exit()
            }
            .simultaneousGesture(drag)
        }
    }

    // MARK: Controls

    /// Inside the safe area (clear of the notch / Dynamic Island), small and translucent.
    private var controls: some View {
        ZStack {
            VStack {
                HStack {
                    controlButton("xmark", label: "閉じる") { exit() }
                    Spacer()
                }
                Spacer()
                Text("\(index + 1)/\(slides.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .glassEffect(.regular, in: .capsule)
            }
            HStack {
                controlButton("chevron.left", label: "前へ") { go(-1, animated: true) }
                    .disabled(index == 0)
                    .opacity(index == 0 ? 0.4 : 1)
                Spacer()
                controlButton("chevron.right", label: "次へ") { advance() }
                    .opacity(index >= slides.count - 1 ? 0.4 : 1)
            }
        }
        .padding(12)
        .environment(\.colorScheme, .dark)
    }

    private func controlButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .circle)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) { showsControls.toggle() }
        hideControls?.cancel()
        guard showsControls else { return }
        hideControls = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.3)) { showsControls = false }
        }
    }

    // MARK: Gestures

    /// `fraction` is how far across the screen the tap was.
    private func tapped(at fraction: CGFloat) {
        guard shown else { return }
        if fraction > 0.38, fraction < 0.62 {
            toggleControls()
        } else if fraction >= 0.62 {
            advance()
        } else {
            go(-1, animated: true)
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 16)
            .onChanged { value in
                let dy = value.translation.height
                if dy > 0, dy > abs(value.translation.width) { dragDown = dy }
            }
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                if dragDown > 0 {
                    if dy > 160 {
                        exit()
                    } else {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { dragDown = 0 }
                    }
                } else if abs(dx) > 50, abs(dx) > abs(dy) {
                    // A swipe skips the animations: the slide shows as it ends.
                    go(dx < 0 ? 1 : -1, animated: false)
                }
            }
    }

    /// Fades to black, turns back to portrait out of sight, then leaves.
    private func exit() {
        guard !leaving else { return }
        leaving = true
        let current = index
        withAnimation(.easeIn(duration: 0.2)) {
            shown = false
            showsControls = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            SlidesOrientation.lock(.portrait, turnTo: .portrait)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                onExit(current)
            }
        }
    }

    // MARK: Playing

    /// The next animation step, or the next slide when there's none left.
    private func advance() {
        guard let slide else { return }
        let plan = AnimationPlan(slide)
        if step < plan.taps.count {
            run(plan.taps[step])
            step += 1
        } else {
            go(1, animated: true)
        }
    }

    /// A slide's transition belongs to the way into it: going forward plays the next slide's, going back plays the
    /// current slide's backwards (so coming back to a slide doesn't replay its own).
    private func go(_ delta: Int, animated: Bool) {
        let target = index + delta
        guard !leaving else { return }
        guard slides.indices.contains(target) else {
            // Past the last slide (or before the first): a shake says there's no more.
            bump += 1
            return
        }
        let previous = index
        let transition = delta > 0 ? slides[target].transition : slides[index].transition
        forward = delta > 0
        if transition.kind == .none {
            outgoing = nil
            progress = 1
            index = target
            enter(animated: animated, from: previous)
            return
        }
        // Both slides go in as pictures (as they look now / as the new one starts), so the move is light;
        // the new slide's own animations start once it has arrived.
        let scale = min(stageSize.width / 1920, stageSize.height / 1080)
        let leavingImage = snapshot(slides[previous], looks: looks, scale: scale)
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            outgoingLooks = looks
            outgoingImage = leavingImage
            outgoing = previous
            transitionKind = transition.kind
            activeTransition = transition
            progress = 0
            index = target
            enter(animated: animated, from: previous, runAuto: false)
            incomingImage = snapshot(slides[target], looks: looks, scale: scale)
        }
        let started = generation
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: transition.duration)) {
                progress = 1
            } completion: {
                // A newer change has its own outgoing slide.
                guard generation == started else { return }
                outgoing = nil
                outgoingImage = nil
                incomingImage = nil
                if animated, let slide { run(AnimationPlan(slide).auto) }
            }
        }
    }

    private var effectiveKind: TransitionKind {
        reduceMotion && transitionKind != .none ? .fade : transitionKind
    }

    /// The slide as it looks at a moment: hidden elements left out, 移動 elements where they're coming from.
    private func snapshot(_ slide: SlideContent, looks: [UUID: ElementLook], scale: CGFloat) -> UIImage {
        var shown = slide
        shown.elements = slide.elements.compactMap { element in
            guard let look = looks[element.id] else { return element }
            guard look.visible else { return nil }
            guard let move = look.moveFrom else { return element }
            var moved = element
            moved.frame = SlideRect(
                x: element.frame.center.x + move.dx - element.frame.width * move.scaleX / 2,
                y: element.frame.center.y + move.dy - element.frame.height * move.scaleY / 2,
                width: element.frame.width * move.scaleX, height: element.frame.height * move.scaleY
            )
            moved.rotation = element.rotation + move.rotation
            moved.opacity = element.opacity * move.opacity
            return moved
        }
        return SlideRenderer.image(of: shown, deck: deck, width: 1920 * scale, scale: displayScale, preview: true)
    }

    /// Sets up the slide's elements: with animations, as they start (then runs the automatic step);
    /// without, as they end. `previous` is the slide just left, for 移動.
    private func enter(animated: Bool, from previous: Int? = nil, runAuto: Bool = true) {
        generation += 1
        step = 0
        guard let slide else { return }
        let plan = AnimationPlan(slide)
        // The same elements on the slide before, each matched once.
        var before = previous.flatMap { slides.indices.contains($0) ? slides[$0].elements : nil } ?? []
        var start: [UUID: ElementLook] = [:]
        var end: [UUID: ElementLook] = [:]
        for animation in slide.animations {
            var look = ElementLook(animation, visible: animation.category == .exit)
            if animation.effect == .move, animation.category == .entrance,
               let element = slide.elements.first(where: { $0.id == animation.elementID }) {
                if let match = before.firstIndex(where: { $0.matchKey == element.matchKey }) {
                    look.visible = true
                    look.moveFrom = MoveFrom(from: before[match], to: element)
                    before.remove(at: match)
                } else {
                    // Nothing to move from: it appears, like 表示.
                    look.effect = .appear
                }
            }
            if start[animation.elementID] == nil { start[animation.elementID] = look }
            end[animation.elementID] = ElementLook(animation, visible: animation.category == .entrance)
        }
        if animated {
            looks = start
            if runAuto { run(plan.auto) }
        } else {
            looks = end
            step = plan.taps.count
        }
    }

    private func run(_ timed: [AnimationPlan.Timed]) {
        let current = generation
        for item in timed {
            let animation = item.animation
            let look = ElementLook(animation, visible: animation.category == .entrance)
            // 移動 with nothing to move from appears at once, like 表示.
            let instant = animation.effect == .appear || (animation.effect == .move && looks[animation.elementID]?.moveFrom == nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + item.start) {
                guard current == generation else { return }
                let curve: Animation? = instant ? nil : .easeInOut(duration: animation.duration)
                withAnimation(curve) { looks[animation.elementID] = look }
            }
        }
    }

}

/// Where a slide is during a transition. Incoming at 0 is where it starts; outgoing at 1 is where it ends.
/// Push and cover come from the transition's side, a whole screen away; going back runs them the other way.
struct SlideTransitionEffect: ViewModifier {
    let kind: TransitionKind
    let transition: SlideTransition
    let progress: CGFloat
    let incoming: Bool
    let forward: Bool
    let size: CGSize

    func body(content: Content) -> some View {
        content
            .offset(offset)
            .scaleEffect(scale)
            .opacity(opacity)
    }

    /// A screen's distance toward the side the new slide comes from (the other side going back).
    private var away: CGSize {
        let vector = MotionAngle.vector(transition.angle)
        let sign: CGFloat = forward ? 1 : -1
        return CGSize(width: vector.x * size.width * sign, height: vector.y * size.height * sign)
    }

    private var offset: CGSize {
        switch kind {
        case .push:
            return incoming
                ? CGSize(width: away.width * (1 - progress), height: away.height * (1 - progress))
                : CGSize(width: -away.width * progress, height: -away.height * progress)
        case .cover:
            return incoming ? CGSize(width: away.width * (1 - progress), height: away.height * (1 - progress)) : .zero
        default:
            return .zero
        }
    }

    private var scale: CGFloat {
        guard kind == .zoom, incoming else { return 1 }
        let from: CGFloat = transition.zoomOut ? 1.8 : 0.3
        return from + (1 - from) * progress
    }

    private var opacity: Double {
        switch kind {
        case .fade, .zoom: incoming ? Double(progress) : 1
        default: 1
        }
    }
}

/// A slide as played: the background, and each element with its animation state.
struct PlayedSlide: View {
    let slide: SlideContent
    let deck: UUID
    let scale: CGFloat
    let looks: [UUID: ElementLook]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .topLeading) {
            SlideBackgroundView(background: slide.background, deck: deck)
                .frame(width: 1920 * scale, height: 1080 * scale)
            ForEach(slide.elements) { element in
                let frame = element.frame.cg
                let padding = SlideRenderer.padding(for: element)
                let look = looks[element.id]
                let move = look?.moveFrom ?? .none
                ElementRenderView(element: element, deck: deck, scale: scale)
                    .frame(width: (frame.width + padding * 2) * scale, height: (frame.height + padding * 2) * scale)
                    .rotationEffect(.degrees(element.rotation + move.rotation))
                    .scaleEffect(x: move.scaleX, y: move.scaleY)
                    .scaleEffect(hiddenScale(look))
                    .offset(x: move.dx * scale, y: move.dy * scale)
                    .offset(hiddenOffset(look, frame: frame))
                    .opacity(element.opacity * move.opacity * hiddenOpacity(look))
                    .position(x: frame.midX * scale, y: frame.midY * scale)
            }
        }
        .frame(width: 1920 * scale, height: 1080 * scale, alignment: .topLeading)
        .clipped()
        .allowsHitTesting(false)
    }

    /// Slides stay opaque (they come from off the slide); everything else fades.
    private func hiddenOpacity(_ look: ElementLook?) -> Double {
        guard let look, !look.visible else { return 1 }
        if look.effect == .slideIn { return reduceMotion ? 0 : 1 }
        return 0
    }

    /// Zoom in grows from small (and goes out growing); zoom out shrinks from big (and goes out shrinking).
    private func hiddenScale(_ look: ElementLook?) -> CGFloat {
        guard let look, !look.visible, look.effect == .zoom, !reduceMotion else { return 1 }
        let small: CGFloat = 0.2
        let big: CGFloat = 2.5
        if look.category == .entrance { return look.zoomOut ? big : small }
        return look.zoomOut ? small : big
    }

    /// Off to its side while hidden, so it slides in from (or out to) there.
    private func hiddenOffset(_ look: ElementLook?, frame: CGRect) -> CGSize {
        guard let look, !look.visible, look.effect == .slideIn, !reduceMotion else { return .zero }
        let vector = MotionAngle.vector(look.angle)
        return CGSize(width: vector.x * 1920 * 1.1 * scale, height: vector.y * 1080 * 1.2 * scale)
    }
}
