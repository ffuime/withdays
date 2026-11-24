import AVKit
import SwiftUI

/// One photo or video at a time, swiped through. Top: back, アルバムに追加 and お気に入り. Bottom: 共有, 切り抜き, 削除.
struct GalleryViewer: View {
    @Environment(GalleryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var ids: [String]
    @State private var current: String?
    @State private var chrome = true
    @State private var confirmDelete = false
    @State private var addingToAlbum = false
    @State private var cropping: GalleryItem?
    /// The photo being crumpled into the trash button (held all the way).
    @State private var crumpling: (id: String, image: UIImage)?
    @State private var crumple: Double = 0
    @State private var trashCenter: CGPoint = .zero

    init(ids: [String], start: String) {
        _ids = State(initialValue: ids)
        _current = State(initialValue: start)
    }

    private var item: GalleryItem? { store.item(current) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(ids, id: \.self) { id in
                    page(id)
                        .tag(Optional(id))
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .ignoresSafeArea()

            if let crumpling {
                GeometryReader { geo in
                    let frame = geo.frame(in: .named("viewer"))
                    Image(uiImage: crumpling.image)
                        .resizable()
                        .scaledToFit()
                        .modifier(GalleryCrumple(
                            progress: crumple,
                            target: CGSize(width: trashCenter.x - frame.midX, height: trashCenter.y - frame.midY)
                        ))
                        .frame(width: geo.size.width, height: geo.size.height)
                }
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }

            if chrome {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }
        }
        .coordinateSpace(.named("viewer"))
        .toolbar(.hidden, for: .navigationBar)
        // In the album sheet a swipe down closes the photo, not the sheet.
        .interactiveDismissDisabled()
        .statusBarHidden(!chrome)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.2), value: chrome)
        .alert("この\(item?.isVideo == true ? "ビデオ" : "写真")を削除しますか？", isPresented: $confirmDelete) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                if let current { remove(current) }
            }
        } message: {
            Text("「最近削除した項目」に30日間残ります。")
        }
        .sheet(isPresented: $addingToAlbum) {
            if let current {
                GalleryAddToAlbumSheet(ids: [current]) {}
                    .environment(store)
            }
        }
        .fullScreenCover(item: $cropping) { item in
            GalleryCropView(item: item)
                .environment(store)
        }
        .onChange(of: store.state.items) {
            // Gone elsewhere (another screen emptied the trash, say).
            let alive = Set(store.state.items.filter { $0.deleted == nil }.map(\.id))
            if ids.contains(where: { !alive.contains($0) }) {
                ids.removeAll { !alive.contains($0) }
                if ids.isEmpty { dismiss() } else if let current, !ids.contains(current) { self.current = ids.first }
            }
        }
    }

    @ViewBuilder
    private func page(_ id: String) -> some View {
        if let item = store.item(id) {
            Group {
                if item.isVideo {
                    GalleryVideoPage(url: store.url(item), active: current == id)
                } else {
                    GalleryPhotoPage(item: item) {
                        chrome.toggle()
                    }
                }
            }
            .opacity(crumpling?.id == id ? 0 : 1)
        } else {
            Color.black
        }
    }

    // MARK: Bars

    private var topBar: some View {
        HStack {
            GalleryPill(symbol: "chevron.left", color: .white) { dismiss() }
                .accessibilityLabel("一覧に戻る")
            Spacer()
            HStack(spacing: 0) {
                GalleryHoldButton(symbol: "rectangle.stack.badge.plus", size: CGSize(width: 44, height: 44)) {
                    addingToAlbum = true
                } onHold: {
                    guard let current else { return }
                    if let recent = store.recentAlbum {
                        store.add([current], to: recent.id)
                    } else {
                        addingToAlbum = true
                    }
                }
                .accessibilityLabel("アルバムに追加")
                .accessibilityHint("長押しで、最近使ったアルバムに入れます")
                Button {
                    if let current { store.toggleFavorite(current) }
                } label: {
                    Image(systemName: item?.favorite == true ? "heart.fill" : "heart")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.selection, trigger: item?.favorite)
                .accessibilityLabel("お気に入り")
            }
            .glassEffect(.regular.interactive(), in: .capsule)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private var bottomBar: some View {
        HStack(spacing: 0) {
            if let item {
                ShareLink(item: store.url(item)) {
                    icon("square.and.arrow.up")
                }
                .accessibilityLabel("共有")
                Button {
                    cropping = item
                } label: {
                    icon("crop")
                }
                .disabled(item.isVideo)
                .opacity(item.isVideo ? 0.35 : 1)
                .accessibilityLabel("切り抜き")
            }
            GalleryHoldButton(symbol: "trash", tint: .red, duration: 1.0) {
                confirmDelete = true
            } onHold: {
                crumpleAway()
            }
            .onGeometryChange(for: CGPoint.self) { geo in
                let frame = geo.frame(in: .named("viewer"))
                return CGPoint(x: frame.midX, y: frame.midY)
            } action: { trashCenter = $0 }
            .accessibilityLabel("削除")
            .accessibilityHint("長押しで、確認なしで削除します")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.bottom, 8)
    }

    private func icon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 56, height: 46)
            .contentShape(Rectangle())
    }

    // MARK: Deleting

    /// Held to the end: the photo is crumpled up and thrown into the trash button, without asking.
    private func crumpleAway() {
        guard let current, let item = store.item(current), crumpling == nil else { return }
        Task {
            let loaded: UIImage?
            if item.isVideo {
                loaded = await GalleryImages.thumb(item)
            } else {
                loaded = await GalleryImages.display(item)
            }
            guard let image = loaded else {
                remove(current)
                return
            }
            crumple = 0
            crumpling = (current, image)
            withAnimation(.easeIn(duration: 0.75)) {
                crumple = 1
            } completion: {
                remove(current)
                crumpling = nil
                crumple = 0
            }
        }
    }

    private func remove(_ id: String) {
        guard let index = ids.firstIndex(of: id) else { return }
        store.trash([id])
        var rest = ids
        rest.remove(at: index)
        if rest.isEmpty {
            dismiss()
            return
        }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            current = rest[min(index, rest.count - 1)]
            ids = rest
        }
    }
}

/// Crumpling: the photo rounds into a creased ball, spins, and drops into the trash button.
struct GalleryCrumple: ViewModifier, Animatable {
    var progress: Double
    let target: CGSize

    var animatableData: Double {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let crush = min(progress / 0.5, 1)
        let travel = max((progress - 0.4) / 0.6, 0)
        content
            .overlay {
                GalleryCreases(seed: 7)
                    .opacity(crush * 0.9)
            }
            .clipShape(RoundedRectangle(cornerRadius: 400 * crush, style: .continuous))
            .rotation3DEffect(.degrees(sin(crush * .pi) * 28), axis: (x: 1, y: 0.6, z: 0))
            .scaleEffect(x: 1 - 0.74 * crush - 0.18 * travel, y: 1 - 0.7 * crush - 0.2 * travel)
            .rotationEffect(.degrees(300 * progress))
            .offset(x: target.width * travel * travel,
                    y: target.height * travel * travel - 70 * sin(travel * .pi))
            .opacity(progress > 0.93 ? (1 - progress) / 0.07 : 1)
    }
}

/// Creases of crumpled paper: light and dark folds over the photo.
private struct GalleryCreases: View {
    let seed: Int

    var body: some View {
        Canvas { context, size in
            Self.draw(in: &context, size: size, seed: seed)
        }
        .allowsHitTesting(false)
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize, seed: Int) {
        var random = SeededRandom(seed: UInt64(seed))
        let w: CGFloat = size.width
        let h: CGFloat = size.height
        let center = CGPoint(x: w / 2, y: h / 2)
        let reach: CGFloat = max(w, h) * 0.6
        for index in 0..<26 {
            let turn: CGFloat = CGFloat(index) / 26 + random.next() * 0.06
            let angle: CGFloat = turn * 2 * CGFloat.pi
            let sx: CGFloat = center.x + (random.next() - 0.5) * w * 0.5
            let sy: CGFloat = center.y + (random.next() - 0.5) * h * 0.5
            let ex: CGFloat = sx + cos(angle) * reach
            let ey: CGFloat = sy + sin(angle) * reach
            let mx: CGFloat = (sx + ex) / 2 + (random.next() - 0.5) * 60
            let my: CGFloat = (sy + ey) / 2 + (random.next() - 0.5) * 60
            var path = Path()
            path.move(to: CGPoint(x: sx, y: sy))
            path.addLine(to: CGPoint(x: mx, y: my))
            path.addLine(to: CGPoint(x: ex, y: ey))
            let dark = index % 2 == 0
            let color: Color = dark ? Color.black.opacity(0.35) : Color.white.opacity(0.45)
            let width: CGFloat = dark ? 2.5 : 1.5
            context.stroke(path, with: .color(color), lineWidth: width)
        }
        // A shadow toward the edge, so the ball looks round.
        let shade = Gradient(colors: [Color.clear, Color.black.opacity(0.45)])
        context.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .radialGradient(shade, center: center, startRadius: 0, endRadius: reach))
    }
}

/// The same creases every time.
private struct SeededRandom {
    var state: UInt64

    init(seed: UInt64) { state = seed &* 6364136223846793005 &+ 1442695040888963407 }

    mutating func next() -> CGFloat {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return CGFloat(Double(state >> 11) / 9_007_199_254_740_992)
    }
}

/// A photo page: pinch and double-tap to zoom; a tap shows or hides the bars.
struct GalleryPhotoPage: View {
    let item: GalleryItem
    var onTap: () -> Void

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                GalleryZoomableImage(image: image, zoomEnabled: true, onTap: onTap)
            } else if let thumb = GalleryImages.cachedThumb(item.file) {
                Image(uiImage: thumb)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: item.file) {
            image = await GalleryImages.display(item)
        }
    }
}

/// A video page, playing while it's the one on screen.
struct GalleryVideoPage: View {
    let url: URL
    let active: Bool

    @State private var player: AVPlayer?

    var body: some View {
        VideoPlayer(player: player)
            .onAppear {
                if player == nil { player = AVPlayer(url: url) }
            }
            .onChange(of: active) { _, active in
                if !active { player?.pause() }
            }
            .onDisappear { player?.pause() }
    }
}

/// An image in a scroll view: pinch to zoom, double-tap to zoom in or out, a tap and a long press for the caller.
struct GalleryZoomableImage: UIViewRepresentable {
    let image: UIImage
    var zoomEnabled = true
    var onTap: (() -> Void)?
    var onLongPress: (() -> Void)?
    /// Told when the photo starts or stops being zoomed in.
    var onZoom: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> GalleryZoomScroll {
        let scroll = GalleryZoomScroll()
        scroll.onLayout = { [weak coordinator = context.coordinator] in coordinator?.boundsChanged() }
        scroll.delegate = context.coordinator
        scroll.showsVerticalScrollIndicator = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.backgroundColor = .clear
        scroll.decelerationRate = .fast
        let view = UIImageView()
        view.contentMode = .scaleAspectFit
        view.isUserInteractionEnabled = true
        scroll.addSubview(view)
        context.coordinator.scroll = scroll
        context.coordinator.imageView = view

        let double = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.doubleTap(_:)))
        double.numberOfTapsRequired = 2
        scroll.addGestureRecognizer(double)
        let single = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tap))
        single.require(toFail: double)
        scroll.addGestureRecognizer(single)
        let long = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        long.minimumPressDuration = 0.5
        scroll.addGestureRecognizer(long)
        context.coordinator.double = double
        return scroll
    }

    func updateUIView(_ scroll: GalleryZoomScroll, context: Context) {
        let coordinator = context.coordinator
        coordinator.onTap = onTap
        coordinator.onLongPress = onLongPress
        coordinator.onZoom = onZoom
        scroll.maximumZoomScale = zoomEnabled ? 5 : 1
        scroll.pinchGestureRecognizer?.isEnabled = zoomEnabled
        coordinator.double?.isEnabled = zoomEnabled
        if !zoomEnabled, scroll.zoomScale != 1 { scroll.setZoomScale(1, animated: true) }
        if coordinator.imageView?.image !== image {
            coordinator.imageView?.image = image
            scroll.zoomScale = 1
            coordinator.layout()
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var scroll: UIScrollView?
        weak var imageView: UIImageView?
        weak var double: UITapGestureRecognizer?
        var onTap: (() -> Void)?
        var onLongPress: (() -> Void)?
        var onZoom: ((Bool) -> Void)?
        private var zoomed = false
        private var lastSize: CGSize = .zero

        func boundsChanged() {
            guard let scroll, scroll.bounds.size != lastSize else { return }
            scroll.zoomScale = 1
            layout()
        }

        /// Fits the image in the scroll view at zoom 1.
        func layout() {
            guard let scroll, let imageView, let image = imageView.image else { return }
            let bounds = scroll.bounds.size
            guard bounds.width > 0, bounds.height > 0 else { return }
            lastSize = bounds
            let scale = min(bounds.width / image.size.width, bounds.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            imageView.frame = CGRect(origin: .zero, size: size)
            scroll.contentSize = size
            center()
        }

        func center() {
            guard let scroll, let imageView else { return }
            let bounds = scroll.bounds.size
            let frame = imageView.frame
            scroll.contentInset = UIEdgeInsets(
                top: max((bounds.height - frame.height) / 2, 0),
                left: max((bounds.width - frame.width) / 2, 0),
                bottom: 0, right: 0
            )
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            center()
            let now = scrollView.zoomScale > 1.01
            if now != zoomed {
                zoomed = now
                onZoom?(now)
            }
        }

        @objc func tap() { onTap?() }

        @objc func longPress(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began { onLongPress?() }
        }

        @objc func doubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scroll else { return }
            if scroll.zoomScale > 1 {
                scroll.setZoomScale(1, animated: true)
            } else {
                let point = gesture.location(in: imageView)
                let scale: CGFloat = 2.5
                let size = CGSize(width: scroll.bounds.width / scale, height: scroll.bounds.height / scale)
                scroll.zoom(to: CGRect(x: point.x - size.width / 2, y: point.y - size.height / 2,
                                       width: size.width, height: size.height), animated: true)
            }
        }
    }
}

/// A button with two actions: a tap, and a hold — a ring fills inside the button and, full, does the hold action.
struct GalleryHoldButton: View {
    let symbol: String
    var tint: Color = .white
    var duration: Double = 0.8
    var size = CGSize(width: 56, height: 46)
    var onTap: () -> Void
    var onHold: () -> Void

    @State private var progress: CGFloat = 0
    @State private var showsRing = false
    @State private var startTask: Task<Void, Never>?
    @State private var held = 0

    /// Before this the press is still a tap, so the ring doesn't flash on every tap.
    private static let delay = 0.15

    var body: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.25), lineWidth: 2.5)
                .frame(width: 32, height: 32)
                .opacity(showsRing ? 1 : 0)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 32, height: 32)
                .opacity(showsRing ? 1 : 0)
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(tint)
                .scaleEffect(showsRing ? 0.72 : 1)
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 30) {
            reset()
            held += 1
            onHold()
        } onPressingChanged: { pressing in
            if pressing {
                startTask?.cancel()
                startTask = Task {
                    try? await Task.sleep(for: .seconds(Self.delay))
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeOut(duration: 0.12)) { showsRing = true }
                    withAnimation(.linear(duration: duration - Self.delay)) { progress = 1 }
                }
            } else {
                reset()
            }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: held)
    }

    private func reset() {
        startTask?.cancel()
        startTask = nil
        withAnimation(.easeOut(duration: 0.15)) {
            showsRing = false
            progress = 0
        }
    }
}

/// Tells its coordinator when it's laid out, so the image fits the real size.
final class GalleryZoomScroll: UIScrollView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }
}
