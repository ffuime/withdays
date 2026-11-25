import SwiftUI
import UIKit

// MARK: - Theme

/// tooc's look, drawn from its logo (violet into blue): the accent for buttons and text, a quiet background behind
/// everything, your bubble (a lighter accent, white text) and the other person's. 夜 is dark throughout.
enum ToocTheme: String, CaseIterable, Identifiable, Codable {
    case standard, lavender, sky, sakura, mint, sand, night
    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "tooc"
        case .lavender: "ラベンダー"
        case .sky: "空"
        case .sakura: "さくら"
        case .mint: "ミント"
        case .sand: "すな"
        case .night: "夜"
        }
    }

    var accent: Color {
        switch self {
        case .standard: .toocBrand
        case .lavender: Color(red: 0.49, green: 0.38, blue: 0.96)
        case .sky: Color(red: 0.13, green: 0.56, blue: 0.94)
        case .sakura: Color(red: 0.91, green: 0.38, blue: 0.58)
        case .mint: Color(red: 0.12, green: 0.66, blue: 0.55)
        case .sand: Color(red: 0.86, green: 0.53, blue: 0.27)
        case .night: Color(red: 0.55, green: 0.6, blue: 1.0)
        }
    }

    /// Behind lists and talks: barely tinted, so text stays easy to read. nil keeps the system's.
    var background: Color? {
        switch self {
        case .standard: nil
        case .lavender: Color(red: 0.975, green: 0.97, blue: 1.0)
        case .sky: Color(red: 0.965, green: 0.98, blue: 1.0)
        case .sakura: Color(red: 1.0, green: 0.972, blue: 0.978)
        case .mint: Color(red: 0.962, green: 0.988, blue: 0.978)
        case .sand: Color(red: 0.99, green: 0.978, blue: 0.962)
        case .night: Color(red: 0.07, green: 0.075, blue: 0.12)
        }
    }

    var dark: Bool { self == .night }

    /// Your bubble: the accent, lightened, under white text.
    var myBubble: Color {
        switch self {
        case .standard: Color(red: 0.42, green: 0.5, blue: 1.0)
        case .night: accent.mix(with: .black, by: 0.25)
        default: accent.mix(with: .white, by: 0.18)
        }
    }

    var theirBubble: Color {
        switch self {
        case .standard: Color(.secondarySystemBackground)
        case .night: Color.white.opacity(0.1)
        default: Color.white
        }
    }

    /// A card or box on the background.
    var card: Color {
        switch self {
        case .standard: Color(.secondarySystemBackground)
        case .night: Color.white.opacity(0.07)
        default: Color.white
        }
    }

    var fill: Color { background ?? Color(.systemBackground) }
}

extension Color {
    /// tooc's own colour: the middle of its logo's violet-to-blue.
    static let toocBrand = Color(red: 0.29, green: 0.36, blue: 1.0)
}

extension EnvironmentValues {
    @Entry var toocTheme: ToocTheme = .standard
}

extension View {
    /// A list or scroll view on the theme's background, rows see-through.
    func toocBackground(_ theme: ToocTheme) -> some View {
        scrollContentBackground(.hidden)
            .background(theme.fill.ignoresSafeArea())
    }
}

// MARK: - Zoom

/// Something small (an icon, a photo in a bubble) grown from where it sits to fill the screen. Drag it or pinch in to
/// take it back step by step, its corners rounding as it shrinks; a tap puts it back too. When `zoomable`, pinching
/// out (or a double tap) zooms into it, and a drag then moves around.
struct ToocZoomLayer<Content: View, Backdrop: View, Accessory: View>: View {
    /// Where the small one is, in global coordinates.
    let source: CGRect
    /// Height ÷ width of the full view.
    let aspect: CGFloat
    /// The small one's corner radius.
    let sourceRadius: CGFloat
    var zoomable = false
    @Binding var progress: CGFloat
    var onClosed: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var backdrop: () -> Backdrop
    @ViewBuilder var accessory: () -> Accessory

    @State private var drag: CGSize = .zero
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var lastPan: CGSize = .zero
    @State private var zooming = false

    var body: some View {
        GeometryReader { proxy in
            let layer = proxy.frame(in: .global)
            let small = source.offsetBy(dx: -layer.minX, dy: -layer.minY)
            let width = min(proxy.size.width, proxy.size.height / max(aspect, 0.1))
            let height = width * aspect
            let full = CGRect(x: (proxy.size.width - width) / 2, y: (proxy.size.height - height) / 2, width: width, height: height)
            let rect = Self.mix(small, full, progress)
            ZStack {
                backdrop()
                    .opacity(Double(progress))
                content()
                    .frame(width: rect.width, height: rect.height)
                    .clipShape(RoundedRectangle(cornerRadius: sourceRadius * (1 - progress), style: .continuous))
                    .scaleEffect(scale)
                    .offset(pan)
                    .position(x: rect.midX + drag.width, y: rect.midY + drag.height)
                accessory()
                    .opacity(Double(max(0, progress * 2 - 1)) * (scale > 1.01 ? 0 : 1))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 48)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(full.size))
            .simultaneousGesture(pinch(full.size))
            .onTapGesture(count: 2) {
                guard zoomable else { return }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                    scale = scale > 1.01 ? 1 : 2.5
                    lastScale = scale
                    pan = .zero
                    lastPan = .zero
                }
            }
            .onTapGesture { if scale <= 1.01 { close() } }
        }
        .ignoresSafeArea()
    }

    private func dragGesture(_ size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if scale > 1.01 {
                    pan = CGSize(width: lastPan.width + value.translation.width,
                                 height: lastPan.height + value.translation.height)
                } else {
                    drag = value.translation
                    progress = max(0.3, 1 - hypot(value.translation.width, value.translation.height) / 500)
                }
            }
            .onEnded { value in
                if scale > 1.01 {
                    lastPan = pan
                } else if hypot(value.translation.width, value.translation.height) > 90 {
                    close()
                } else {
                    settle()
                }
            }
    }

    private func pinch(_ size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomable && (zooming || lastScale > 1.01 || (value.magnification > 1 && progress >= 1)) {
                    zooming = true
                    scale = min(10, max(1, lastScale * value.magnification))
                } else {
                    progress = min(1, max(0, value.magnification))
                }
            }
            .onEnded { _ in
                if zooming {
                    zooming = false
                    lastScale = scale
                    lastPan = pan
                    if scale <= 1.01 {
                        withAnimation(.snappy) {
                            scale = 1
                            lastScale = 1
                            pan = .zero
                            lastPan = .zero
                        }
                    }
                } else if progress < 0.8 {
                    close()
                } else {
                    settle()
                }
            }
    }

    private func settle() {
        withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
            progress = 1
            drag = .zero
        }
    }

    private func close() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
            progress = 0
            drag = .zero
            scale = 1
            pan = .zero
        } completion: {
            onClosed()
        }
    }

    static func mix(_ a: CGRect, _ b: CGRect, _ t: CGFloat) -> CGRect {
        CGRect(x: a.minX + (b.minX - a.minX) * t, y: a.minY + (b.minY - a.minY) * t,
               width: a.width + (b.width - a.width) * t, height: a.height + (b.height - a.height) * t)
    }
}

// MARK: - Crop

/// Move and pinch a photo inside a frame (round for an icon), larger or smaller, then keep what's inside. Space the
/// photo doesn't cover comes out black.
struct ToocCropView: View {
    let image: UIImage
    /// Height ÷ width of the result.
    let aspect: CGFloat
    let circle: Bool
    var onDone: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var area: CGSize = .zero

    private static let minScale: CGFloat = 0.3

    private func frame(_ area: CGSize) -> CGSize {
        let width = max(1, min(area.width - 40, (area.height - 40) / aspect))
        return CGSize(width: width, height: width * aspect)
    }

    private func fill(_ frame: CGSize) -> CGFloat {
        max(frame.width / max(1, image.size.width), frame.height / max(1, image.size.height))
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                let frame = frame(proxy.size)
                let shown = CGSize(width: image.size.width * fill(frame) * scale, height: image.size.height * fill(frame) * scale)
                ZStack {
                    Color.black
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: shown.width, height: shown.height)
                        .offset(offset)
                    // Darkens everything outside the frame.
                    Rectangle()
                        .fill(.black.opacity(0.6))
                        .mask {
                            ZStack {
                                Rectangle()
                                cutout
                                    .frame(width: frame.width, height: frame.height)
                                    .blendMode(.destinationOut)
                            }
                            .compositingGroup()
                        }
                        .allowsHitTesting(false)
                    cutoutStroke
                        .frame(width: frame.width, height: frame.height)
                        .allowsHitTesting(false)
                }
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .contentShape(Rectangle())
                .gesture(
                    SimultaneousGesture(
                        MagnifyGesture()
                            .onChanged { value in
                                scale = max(Self.minScale, min(8, lastScale * value.magnification))
                                offset = clamp(offset, frame: frame)
                            }
                            .onEnded { _ in
                                lastScale = scale
                                lastOffset = offset
                            },
                        DragGesture()
                            .onChanged { value in
                                offset = clamp(CGSize(width: lastOffset.width + value.translation.width,
                                                      height: lastOffset.height + value.translation.height), frame: frame)
                            }
                            .onEnded { _ in lastOffset = offset }
                    )
                )
            }
            .onGeometryChange(for: CGSize.self) { $0.size } action: { area = $0 }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(circle ? "アイコンを切り抜く" : "背景を切り抜く")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.primary) }
                        .accessibilityLabel("キャンセル")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        onDone(crop())
                        dismiss()
                    } label: { Image(systemName: "checkmark") }
                        .buttonStyle(.glassProminent)
                        .accessibilityLabel("切り抜く")
                }
            }
        }
        .environment(\.colorScheme, .dark)
    }

    @ViewBuilder
    private var cutout: some View {
        if circle { Circle() } else { RoundedRectangle(cornerRadius: 20, style: .continuous) }
    }

    @ViewBuilder
    private var cutoutStroke: some View {
        if circle {
            Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2)
        } else {
            RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.white.opacity(0.9), lineWidth: 2)
        }
    }

    /// Larger than the frame: the photo must cover it. Smaller: the photo must stay inside it.
    private func clamp(_ offset: CGSize, frame: CGSize) -> CGSize {
        let shownWidth = image.size.width * fill(frame) * scale
        let shownHeight = image.size.height * fill(frame) * scale
        let maxX = abs(shownWidth - frame.width) / 2
        let maxY = abs(shownHeight - frame.height) / 2
        return CGSize(width: min(max(offset.width, -maxX), maxX), height: min(max(offset.height, -maxY), maxY))
    }

    private func crop() -> UIImage {
        let frame = frame(area)
        let factor = fill(frame) * scale
        let cropSize = CGSize(width: frame.width / factor, height: frame.height / factor)
        let origin = CGPoint(
            x: (image.size.width - cropSize.width) / 2 - offset.width / factor,
            y: (image.size.height - cropSize.height) / 2 - offset.height / factor
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: cropSize, format: format).image { context in
            UIColor.black.setFill()
            context.fill(CGRect(origin: .zero, size: cropSize))
            image.draw(in: CGRect(x: -origin.x, y: -origin.y, width: image.size.width, height: image.size.height))
        }
    }
}

/// Picks a photo, then crops it. Used for the icon (round) and the profile background.
struct ToocCropRequest: Identifiable {
    let id = UUID()
    let image: UIImage
    let icon: Bool
}
