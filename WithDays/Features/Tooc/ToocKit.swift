import SwiftUI
import UIKit

// MARK: - Theme

/// tooc's look: the accent for buttons, text and your bubbles, the background behind everything, and the other
/// person's bubble. 夜 is dark throughout.
enum ToocTheme: String, CaseIterable, Identifiable, Codable {
    case standard, sky, sakura, mint, sand, night
    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "標準"
        case .sky: "空"
        case .sakura: "さくら"
        case .mint: "ミント"
        case .sand: "すな"
        case .night: "夜"
        }
    }

    var accent: Color {
        switch self {
        case .standard: .brand
        case .sky: Color(hue: 0.56, saturation: 0.75, brightness: 0.82)
        case .sakura: Color(hue: 0.95, saturation: 0.55, brightness: 0.86)
        case .mint: Color(hue: 0.45, saturation: 0.7, brightness: 0.62)
        case .sand: Color(hue: 0.07, saturation: 0.62, brightness: 0.78)
        case .night: Color(hue: 0.62, saturation: 0.5, brightness: 0.82)
        }
    }

    /// Behind lists and talks; nil keeps the system's.
    var background: Color? {
        switch self {
        case .standard: nil
        case .sky: Color(hue: 0.57, saturation: 0.1, brightness: 0.98)
        case .sakura: Color(hue: 0.95, saturation: 0.07, brightness: 0.99)
        case .mint: Color(hue: 0.43, saturation: 0.08, brightness: 0.97)
        case .sand: Color(hue: 0.1, saturation: 0.09, brightness: 0.97)
        case .night: Color(hue: 0.64, saturation: 0.5, brightness: 0.15)
        }
    }

    var dark: Bool { self == .night }

    /// See-through, so the background shows.
    var myBubble: Color { accent.opacity(0.84) }
    var theirBubble: Color {
        switch self {
        case .standard: Color(.secondarySystemBackground).opacity(0.85)
        case .night: Color.white.opacity(0.14)
        default: Color.white.opacity(0.72)
        }
    }

    /// A card or box on the background.
    var card: Color {
        switch self {
        case .standard: Color(.secondarySystemBackground)
        case .night: Color.white.opacity(0.08)
        default: Color.white.opacity(0.75)
        }
    }

    var fill: Color { background ?? Color(.systemBackground) }
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

// MARK: - Tab bar

/// tooc's tab bar: a glass bar with a glass lens on the chosen tab. Only what's under the lens is filled and coloured,
/// so dragging the lens across fills each icon just where it overlaps.
struct ToocTabBar: View {
    @Binding var selection: ToocTab
    var badge: Int

    @Environment(\.toocTheme) private var theme
    /// The lens's centre while a finger moves it.
    @State private var dragX: CGFloat?

    private struct Item: Hashable {
        let tab: ToocTab
        let title: String
        let symbol: String
    }

    private static let items = [
        Item(tab: .talk, title: "トーク", symbol: "message"),
        Item(tab: .friends, title: "友だち", symbol: "person.2"),
        Item(tab: .me, title: "じぶん", symbol: "face.smiling"),
    ]

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width / CGFloat(Self.items.count)
            let index = Self.items.firstIndex { $0.tab == selection } ?? 0
            let center = dragX ?? (CGFloat(index) + 0.5) * width
            let lens = CGRect(x: center - width / 2 + 4, y: 4, width: width - 8, height: proxy.size.height - 8)
            ZStack {
                row(filled: false)
                    .foregroundStyle(.primary)
                row(filled: true)
                    .foregroundStyle(theme.accent)
                    .mask {
                        Capsule()
                            .frame(width: lens.width, height: lens.height)
                            .position(x: lens.midX, y: lens.midY)
                    }
                Capsule()
                    .fill(.clear)
                    .glassEffect(.clear.interactive(), in: .capsule)
                    .frame(width: lens.width, height: lens.height)
                    .position(x: lens.midX, y: lens.midY)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let x = min(max(value.location.x, width / 2), proxy.size.width - width / 2)
                        if dragX == nil {
                            withAnimation(.snappy(duration: 0.2)) { dragX = x }
                        } else {
                            dragX = x
                        }
                    }
                    .onEnded { value in
                        let picked = min(max(Int(value.location.x / width), 0), Self.items.count - 1)
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            dragX = nil
                            selection = Self.items[picked].tab
                        }
                    }
            )
        }
        .frame(height: 60)
        .glassEffect(.regular, in: .capsule)
        .padding(.horizontal, 28)
        .padding(.bottom, 4)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func row(filled: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Self.items, id: \.self) { item in
                VStack(spacing: 3) {
                    Image(systemName: filled ? "\(item.symbol).fill" : item.symbol)
                        .font(.system(size: 20, weight: .medium))
                        .frame(height: 24)
                        .overlay(alignment: .topTrailing) {
                            if item.tab == .talk, badge > 0 {
                                Text(badge > 99 ? "99+" : "\(badge)")
                                    .font(.system(size: 11, weight: .bold))
                                    .monospacedDigit()
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .frame(minWidth: 18, minHeight: 18)
                                    .background(Capsule().fill(.red))
                                    .offset(x: 12, y: -6)
                            }
                        }
                    Text(item.title)
                        .font(.system(size: 10, weight: filled ? .bold : .medium))
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(item.tab == selection ? AccessibilityTraits([.isButton, .isSelected]) : AccessibilityTraits.isButton)
            }
        }
        .environment(\.symbolVariants, .none)
    }
}

// MARK: - Zoom

/// Something small (an icon, a photo in a bubble) grown from where it sits to fill the screen. Drag it or pinch in to
/// take it back step by step, its corners rounding as it shrinks; a tap puts it back too.
struct ToocZoomLayer<Content: View, Backdrop: View, Accessory: View>: View {
    /// Where the small one is, in global coordinates.
    let source: CGRect
    /// Height ÷ width of the full view.
    let aspect: CGFloat
    /// The small one's corner radius.
    let sourceRadius: CGFloat
    @Binding var progress: CGFloat
    var onClosed: () -> Void
    @ViewBuilder var content: () -> Content
    @ViewBuilder var backdrop: () -> Backdrop
    @ViewBuilder var accessory: () -> Accessory

    @State private var drag: CGSize = .zero

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
                    .position(x: rect.midX + drag.width, y: rect.midY + drag.height)
                accessory()
                    .opacity(Double(max(0, progress * 2 - 1)))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 48)
            }
            .contentShape(Rectangle())
            .gesture(dragBack)
            .simultaneousGesture(pinchBack)
            .onTapGesture(perform: close)
        }
        .ignoresSafeArea()
    }

    private var dragBack: some Gesture {
        DragGesture()
            .onChanged { value in
                drag = value.translation
                progress = max(0.3, 1 - hypot(value.translation.width, value.translation.height) / 500)
            }
            .onEnded { value in
                if hypot(value.translation.width, value.translation.height) > 90 { close() } else { settle() }
            }
    }

    private var pinchBack: some Gesture {
        MagnifyGesture()
            .onChanged { value in progress = min(1, max(0, value.magnification)) }
            .onEnded { _ in if progress < 0.8 { close() } else { settle() } }
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

/// Move and pinch a photo inside a frame (round for an icon), then keep just what's inside.
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
                                scale = max(1, min(8, lastScale * value.magnification))
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
                    Button { dismiss() } label: { Image(systemName: "xmark") }
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

    private func clamp(_ offset: CGSize, frame: CGSize) -> CGSize {
        let shownWidth = image.size.width * fill(frame) * scale
        let shownHeight = image.size.height * fill(frame) * scale
        let maxX = max(0, (shownWidth - frame.width) / 2)
        let maxY = max(0, (shownHeight - frame.height) / 2)
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
        return UIGraphicsImageRenderer(size: cropSize, format: format).image { _ in
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
