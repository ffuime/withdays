import SwiftUI
import UIKit

// MARK: - Theme

/// tooc's look, drawn from its logo (violet into blue): the accent for buttons and text, a quiet background behind
/// everything, your bubble (the accent under white text) and the other person's. Every theme has a light and a dark
/// version; which one shows follows ライト・ダーク・自動 (ToocAppearance).
enum ToocTheme: String, CaseIterable, Identifiable, Codable {
    case standard, lavender, sky, sakura, mint, sand
    /// 夜 from before themes had a dark version: read as tooc in dark.
    case night
    var id: String { rawValue }

    static var allCases: [ToocTheme] { [.standard, .lavender, .sky, .sakura, .mint, .sand] }

    var label: String {
        switch self {
        case .standard, .night: "tooc"
        case .lavender: "ラベンダー"
        case .sky: "スカイ"
        case .sakura: "さくら"
        case .mint: "ミント"
        case .sand: "すな"
        }
    }

    /// The accent, bright enough to read on black in dark.
    private func accentRGB(dark: Bool) -> ToocRGB {
        switch self {
        case .standard, .night: dark ? ToocRGB(0.5, 0.58, 1.0) : ToocRGB(0.29, 0.36, 1.0)
        case .lavender: dark ? ToocRGB(0.69, 0.61, 1.0) : ToocRGB(0.49, 0.38, 0.96)
        case .sky: dark ? ToocRGB(0.42, 0.74, 1.0) : ToocRGB(0.13, 0.56, 0.94)
        case .sakura: dark ? ToocRGB(1.0, 0.58, 0.72) : ToocRGB(0.91, 0.38, 0.58)
        case .mint: dark ? ToocRGB(0.35, 0.84, 0.72) : ToocRGB(0.12, 0.66, 0.55)
        case .sand: dark ? ToocRGB(1.0, 0.71, 0.46) : ToocRGB(0.86, 0.53, 0.27)
        }
    }

    var accent: Color { .tooc(light: accentRGB(dark: false).ui, dark: accentRGB(dark: true).ui) }

    /// Behind lists and talks: barely tinted, so text stays easy to read. nil keeps the system's.
    var background: Color? {
        switch self {
        case .standard, .night: nil
        case .lavender: .tooc(light: ToocRGB(0.975, 0.97, 1.0).ui, dark: ToocRGB(0.07, 0.06, 0.11).ui)
        case .sky: .tooc(light: ToocRGB(0.965, 0.98, 1.0).ui, dark: ToocRGB(0.05, 0.075, 0.11).ui)
        case .sakura: .tooc(light: ToocRGB(1.0, 0.972, 0.978).ui, dark: ToocRGB(0.1, 0.06, 0.075).ui)
        case .mint: .tooc(light: ToocRGB(0.962, 0.988, 0.978).ui, dark: ToocRGB(0.05, 0.09, 0.08).ui)
        case .sand: .tooc(light: ToocRGB(0.99, 0.978, 0.962).ui, dark: ToocRGB(0.1, 0.08, 0.06).ui)
        }
    }

    /// Your bubble: the accent under white text (lighter in light, deeper in dark, so white reads on both).
    var myBubble: Color {
        let light = self == .standard || self == .night ? ToocRGB(0.42, 0.5, 1.0) : accentRGB(dark: false).mix(.white, 0.18)
        let dark = accentRGB(dark: false).mix(.black, 0.12)
        return .tooc(light: light.ui, dark: dark.ui)
    }

    var theirBubble: Color {
        switch self {
        case .standard, .night: Color(.secondarySystemBackground)
        default: .tooc(light: .white, dark: UIColor(white: 1, alpha: 0.11))
        }
    }

    /// A card or box on the background.
    var card: Color {
        switch self {
        case .standard, .night: Color(.secondarySystemBackground)
        default: .tooc(light: .white, dark: UIColor(white: 1, alpha: 0.08))
        }
    }

    var fill: Color { background ?? Color(.systemBackground) }
}

/// ライト・ダーク, or the same as the iPhone (自動).
enum ToocAppearance: String, CaseIterable, Identifiable, Codable {
    case system, light, dark
    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "自動"
        case .light: "ライト"
        case .dark: "ダーク"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// A colour by its parts, for mixing the themes' light and dark versions.
struct ToocRGB {
    let r: CGFloat
    let g: CGFloat
    let b: CGFloat

    init(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) {
        self.r = r
        self.g = g
        self.b = b
    }

    static let white = ToocRGB(1, 1, 1)
    static let black = ToocRGB(0, 0, 0)

    func mix(_ other: ToocRGB, _ amount: CGFloat) -> ToocRGB {
        ToocRGB(r + (other.r - r) * amount, g + (other.g - g) * amount, b + (other.b - b) * amount)
    }

    var ui: UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
}

extension Color {
    /// tooc's own colour: the middle of its logo's violet-to-blue (lighter in dark, to read on black).
    static let toocBrand = Color.tooc(light: ToocRGB(0.29, 0.36, 1.0).ui, dark: ToocRGB(0.5, 0.58, 1.0).ui)

    /// One colour in light, another in dark.
    static func tooc(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? dark : light })
    }
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
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Color.primary) }
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

/// A destructive menu item with its symbol in red too (menus draw symbols in the text colour).
struct ToocDestructiveButton: View {
    let title: String
    let symbol: String
    let action: () -> Void

    init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.symbol = systemImage
        self.action = action
    }

    var body: some View {
        Button(role: .destructive, action: action) {
            Label {
                Text(title)
            } icon: {
                Image(uiImage: UIImage(systemName: symbol)?.withTintColor(.systemRed, renderingMode: .alwaysOriginal)
                      ?? UIImage())
            }
        }
    }
}
