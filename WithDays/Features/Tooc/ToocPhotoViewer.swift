import SwiftUI
import UIKit

/// What opens the talk's photo viewer: every photo in the talk, the one tapped, and where it was.
struct ToocPhotoViewerItem: Identifiable {
    let id = UUID()
    let photos: [ToocMessage]
    let start: UUID
    let image: UIImage
    let source: CGRect
}

/// The talk's photos full screen. Swipe sideways for the ones before and after, tap to hide the buttons,
/// pinch or double-tap to zoom, drag down (or ×) to close. 保存 and 転送 sit in one pill at the bottom.
struct ToocPhotoViewer: View {
    let item: ToocPhotoViewerItem
    var onClose: () -> Void

    @State private var current: UUID
    @State private var images: [UUID: UIImage]
    @State private var chrome = true
    /// 0 = the photo sits in its bubble, 1 = full screen.
    @State private var progress: CGFloat = 0
    /// The pager is up (the photo grown out of its bubble has handed over to it).
    @State private var opened = false
    @State private var fading = false
    @State private var drag: CGSize = .zero
    @State private var dragAxis: Axis?
    @State private var zoomed = false
    @State private var saved: Set<UUID> = []
    @State private var forwarding: ToocMessage?

    init(item: ToocPhotoViewerItem, onClose: @escaping () -> Void) {
        self.item = item
        self.onClose = onClose
        _current = State(initialValue: item.start)
        _images = State(initialValue: [item.start: item.image])
    }

    private var message: ToocMessage? { item.photos.first { $0.id == current } }
    private var index: Int { item.photos.firstIndex { $0.id == current } ?? 0 }

    var body: some View {
        GeometryReader { proxy in
            let layer = proxy.frame(in: .global)
            let fade: Double = 1 - min(1, Double(abs(drag.height)) / 420)
            ZStack {
                Color.black
                    .opacity(fading ? 0 : Double(progress) * fade)

                TabView(selection: $current) {
                    ForEach(item.photos) { photo in
                        ToocViewerPage(message: photo, image: images[photo.id]) {
                            withAnimation(.easeInOut(duration: 0.2)) { chrome.toggle() }
                        } onZoom: { zoomed = $0 } onLoad: { images[photo.id] = $0 }
                        .tag(photo.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .offset(drag)
                .scaleEffect(1 - min(0.2, abs(drag.height) / 1800))
                .opacity(opened && !fading ? 1 : 0)
                .simultaneousGesture(dismissDrag)

                if !opened, let image = images[current] {
                    hero(image, in: proxy.size, layer: layer)
                }

                buttons
                    .opacity(opened && chrome && drag == .zero && !fading ? 1 : 0)
                    .allowsHitTesting(opened && chrome)
            }
        }
        .ignoresSafeArea()
        .presentationBackground(.clear)
        .statusBarHidden(!chrome)
        .sensoryFeedback(.success, trigger: saved)
        .sheet(item: $forwarding) { ToocForwardView(message: $0) }
        .task(id: current) { preload() }
        .onAppear {
            withAnimation(.spring(response: 0.38, dampingFraction: 0.86)) { progress = 1 } completion: {
                opened = true
            }
        }
    }

    // MARK: Grow and shrink

    /// The photo on its way between its bubble and the full screen.
    private func hero(_ image: UIImage, in size: CGSize, layer: CGRect) -> some View {
        let aspect = image.size.height / max(1, image.size.width)
        let width = min(size.width, size.height / max(aspect, 0.1))
        let height = width * aspect
        let full = CGRect(x: (size.width - width) / 2 + drag.width, y: (size.height - height) / 2 + drag.height,
                          width: width, height: height)
        let small = item.source.offsetBy(dx: -layer.minX, dy: -layer.minY)
        let rect = CGRect(x: small.minX + (full.minX - small.minX) * progress,
                          y: small.minY + (full.minY - small.minY) * progress,
                          width: small.width + (full.width - small.width) * progress,
                          height: small.height + (full.height - small.height) * progress)
        return Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: rect.width, height: rect.height)
            .clipShape(RoundedRectangle(cornerRadius: 16 * (1 - progress), style: .continuous))
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    private func close() {
        // The photo it opened from goes back into its bubble; any other fades away.
        if current == item.start, !zoomed, images[current] != nil {
            opened = false
            withAnimation(.spring(response: 0.36, dampingFraction: 0.9)) {
                progress = 0
                drag = .zero
            } completion: { finish() }
        } else {
            withAnimation(.easeOut(duration: 0.22)) {
                fading = true
                drag.height += drag.height >= 0 ? 80 : -80
            } completion: { finish() }
        }
    }

    private func finish() {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { onClose() }
    }

    /// Down (or up) to close; sideways is left to the pager.
    private var dismissDrag: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard opened, !zoomed else { return }
                if dragAxis == nil {
                    dragAxis = abs(value.translation.height) > abs(value.translation.width) ? .vertical : .horizontal
                }
                guard dragAxis == .vertical else { return }
                drag = CGSize(width: value.translation.width * 0.4, height: value.translation.height)
            }
            .onEnded { value in
                defer { dragAxis = nil }
                guard dragAxis == .vertical, opened, !zoomed else { return }
                if abs(value.translation.height) > 110 || abs(value.predictedEndTranslation.height) > 300 {
                    close()
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { drag = .zero }
                }
            }
    }

    // MARK: Buttons

    private var buttons: some View {
        VStack {
            HStack {
                Button(action: close) {
                    Image(systemName: "xmark")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("閉じる")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 60)
            Spacer()
            HStack(spacing: 0) {
                Button(action: save) {
                    Image(systemName: saved.contains(current) ? "checkmark" : "square.and.arrow.down")
                        .font(.system(size: 18, weight: .semibold))
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: 60, height: 48)
                }
                .disabled(images[current] == nil || saved.contains(current))
                .accessibilityLabel(saved.contains(current) ? "保存しました" : "保存")
                Button {
                    forwarding = message
                } label: {
                    Image(systemName: "arrowshape.turn.up.right")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: 60, height: 48)
                }
                .disabled(message?.forwardable != true)
                .accessibilityLabel("転送")
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.interactive(), in: .capsule)
            .padding(.bottom, 44)
        }
        .foregroundStyle(.white)
        .environment(\.colorScheme, .dark)
    }

    private func save() {
        guard let image = images[current] else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        _ = withAnimation(.snappy) { saved.insert(current) }
    }

    /// Fetches the photos either side, so a swipe finds them ready.
    private func preload() {
        for offset in [-1, 1] {
            let i = index + offset
            guard item.photos.indices.contains(i) else { continue }
            let photo = item.photos[i]
            guard images[photo.id] == nil else { continue }
            Task {
                if let image = await ToocViewerPage.load(photo) { images[photo.id] = image }
            }
        }
    }
}

/// One photo in the viewer, zoomable.
private struct ToocViewerPage: View {
    let message: ToocMessage
    let image: UIImage?
    var onTap: () -> Void
    var onZoom: (Bool) -> Void
    var onLoad: (UIImage) -> Void

    var body: some View {
        Group {
            if let image {
                GalleryZoomableImage(image: image, onTap: onTap, onZoom: onZoom)
            } else {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onTap)
            }
        }
        .task(id: message.id) {
            guard image == nil, let loaded = await Self.load(message) else { return }
            onLoad(loaded)
        }
    }

    static func load(_ message: ToocMessage) async -> UIImage? {
        switch message.kind {
        case .photo(let file):
            guard let file else { return nil }
            return ToocFiles.image(file)
        case .remotePhoto(let address):
            return await ToocFiles.remoteImage(address)
        default:
            return nil
        }
    }
}
