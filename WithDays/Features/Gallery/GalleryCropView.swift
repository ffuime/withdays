import SwiftUI

/// 切り抜き: drag the corners or the frame, pick a shape, turn the photo. 完了 replaces the photo; 元に戻す brings the original back.
struct GalleryCropView: View {
    let item: GalleryItem

    @Environment(GalleryStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var image: UIImage?
    /// The crop, as fractions of the image (0...1), so it survives layout changes.
    @State private var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    @State private var ratio: GalleryCropRatio = .free
    @State private var dragStart: CGRect?
    @State private var saving = false
    @State private var confirmRevert = false

    private static let minSide: CGFloat = 50

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let area = CGRect(origin: .zero, size: geo.size).insetBy(dx: 24, dy: 24)
                if let image {
                    let frame = fitted(image.size, in: area)
                    let rect = denormalize(crop, in: frame)
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                        dim(rect, size: geo.size)
                        grid(rect)
                        ForEach(GalleryCropCorner.allCases, id: \.self) { corner in
                            handle(corner, rect: rect, frame: frame, image: image)
                        }
                    }
                    .contentShape(Rectangle())
                    .gesture(move(rect: rect, frame: frame))
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color.black)
            .safeAreaInset(edge: .bottom) { tools }
            .navigationTitle("切り抜き")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("キャンセル")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if saving { ProgressView() } else { Image(systemName: "checkmark") }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(image == nil || saving)
                    .accessibilityLabel("完了")
                }
            }
        }
        .environment(\.colorScheme, .dark)
        .task {
            image = await GalleryImages.full(item)
        }
        .alert("元の写真に戻しますか？", isPresented: $confirmRevert) {
            Button("キャンセル", role: .cancel) {}
            Button("元に戻す", role: .destructive) {
                store.revert(item.id)
                dismiss()
            }
        } message: {
            Text("切り抜く前の写真に戻ります。")
        }
    }

    // MARK: Drawing

    private func dim(_ rect: CGRect, size: CGSize) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: size))
            path.addRect(rect)
        }
        .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    private func grid(_ rect: CGRect) -> some View {
        Path { path in
            for step in 1...2 {
                let x = rect.minX + rect.width * CGFloat(step) / 3
                let y = rect.minY + rect.height * CGFloat(step) / 3
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
        }
        .stroke(Color.white.opacity(0.5), lineWidth: 0.5)
        .overlay {
            Path { $0.addRect(rect) }
                .stroke(Color.white, lineWidth: 1.5)
        }
        .allowsHitTesting(false)
    }

    private func handle(_ corner: GalleryCropCorner, rect: CGRect, frame: CGRect, image: UIImage) -> some View {
        let point = corner.point(in: rect)
        return GalleryCropHandle(corner: corner)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .position(point)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let start = dragStart ?? rect
                        if dragStart == nil { dragStart = rect }
                        let anchor = corner.opposite.point(in: start)
                        let finger = CGPoint(x: corner.point(in: start).x + value.translation.width,
                                             y: corner.point(in: start).y + value.translation.height)
                        crop = normalize(resize(anchor: anchor, finger: finger, corner: corner, frame: frame, image: image), in: frame)
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }

    private func move(rect: CGRect, frame: CGRect) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = dragStart ?? rect
                if dragStart == nil { dragStart = rect }
                var moved = start.offsetBy(dx: value.translation.width, dy: value.translation.height)
                moved.origin.x = min(max(moved.minX, frame.minX), frame.maxX - moved.width)
                moved.origin.y = min(max(moved.minY, frame.minY), frame.maxY - moved.height)
                crop = normalize(moved, in: frame)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var tools: some View {
        HStack(spacing: 10) {
            Button {
                rotate()
            } label: {
                Image(systemName: "rotate.left")
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("左に回転")
            Menu {
                Picker("比率", selection: $ratio) {
                    ForEach(GalleryCropRatio.allCases) { ratio in
                        Text(ratio.label).tag(ratio)
                    }
                }
            } label: {
                Label(ratio.label, systemImage: "aspectratio")
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
            }
            .onChange(of: ratio) { _, new in apply(new) }
            Spacer()
            if item.original != nil {
                Button("元に戻す") { confirmRevert = true }
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 14)
                    .frame(height: 44)
            }
            Button("リセット") {
                withAnimation(.snappy) {
                    ratio = .free
                    crop = CGRect(x: 0, y: 0, width: 1, height: 1)
                }
            }
            .font(.system(size: 15, weight: .semibold))
            .padding(.horizontal, 14)
            .frame(height: 44)
        }
        .foregroundStyle(.white)
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color.black)
    }

    // MARK: Math

    private func fitted(_ size: CGSize, in area: CGRect) -> CGRect {
        let scale = min(area.width / size.width, area.height / size.height)
        let fitted = CGSize(width: size.width * scale, height: size.height * scale)
        return CGRect(x: area.midX - fitted.width / 2, y: area.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }

    private func denormalize(_ rect: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + rect.minX * frame.width, y: frame.minY + rect.minY * frame.height,
               width: rect.width * frame.width, height: rect.height * frame.height)
    }

    private func normalize(_ rect: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: (rect.minX - frame.minX) / frame.width, y: (rect.minY - frame.minY) / frame.height,
               width: rect.width / frame.width, height: rect.height / frame.height)
    }

    /// The corner follows the finger, the opposite corner stays, inside the photo and in the chosen shape.
    private func resize(anchor: CGPoint, finger: CGPoint, corner: GalleryCropCorner, frame: CGRect, image: UIImage) -> CGRect {
        let left = corner.isLeft, top = corner.isTop
        let maxW = left ? anchor.x - frame.minX : frame.maxX - anchor.x
        let maxH = top ? anchor.y - frame.minY : frame.maxY - anchor.y
        var w = min(max(left ? anchor.x - finger.x : finger.x - anchor.x, Self.minSide), maxW)
        var h = min(max(top ? anchor.y - finger.y : finger.y - anchor.y, Self.minSide), maxH)
        if let r = ratio.value(for: image.size) {
            if w / h > r { w = h * r } else { h = w / r }
        }
        return CGRect(x: left ? anchor.x - w : anchor.x, y: top ? anchor.y - h : anchor.y, width: w, height: h)
    }

    /// The largest crop of that shape, in the middle.
    private func apply(_ ratio: GalleryCropRatio) {
        guard let image, let r = ratio.value(for: image.size) else { return }
        // In fractions of the image: a shape r (width / height) is r * h / w wide.
        let fraction = r * image.size.height / image.size.width
        var size = CGSize(width: 1, height: 1)
        if fraction < 1 { size.width = fraction } else { size.height = 1 / fraction }
        withAnimation(.snappy) {
            crop = CGRect(x: (1 - size.width) / 2, y: (1 - size.height) / 2, width: size.width, height: size.height)
        }
    }

    private func rotate() {
        guard let image else { return }
        let size = CGSize(width: image.size.height, height: image.size.width)
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        let rotated = UIGraphicsImageRenderer(size: size, format: format).image { context in
            context.cgContext.translateBy(x: 0, y: size.height)
            context.cgContext.rotate(by: -.pi / 2)
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
        self.image = rotated
        crop = CGRect(x: 0, y: 0, width: 1, height: 1)
        if ratio != .free { apply(ratio) }
    }

    private func save() {
        guard let image, let cg = image.cgImage else { return }
        saving = true
        let pixels = CGRect(x: crop.minX * CGFloat(cg.width), y: crop.minY * CGFloat(cg.height),
                            width: crop.width * CGFloat(cg.width), height: crop.height * CGFloat(cg.height)).integral
        Task {
            if let cropped = cg.cropping(to: pixels), let data = UIImage(cgImage: cropped).heicData() {
                await store.replaceImage(item.id, with: data)
            }
            saving = false
            dismiss()
        }
    }
}

enum GalleryCropCorner: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight

    var isLeft: Bool { self == .topLeft || self == .bottomLeft }
    var isTop: Bool { self == .topLeft || self == .topRight }

    var opposite: GalleryCropCorner {
        switch self {
        case .topLeft: .bottomRight
        case .topRight: .bottomLeft
        case .bottomLeft: .topRight
        case .bottomRight: .topLeft
        }
    }

    func point(in rect: CGRect) -> CGPoint {
        CGPoint(x: isLeft ? rect.minX : rect.maxX, y: isTop ? rect.minY : rect.maxY)
    }
}

/// The L of a crop corner.
private struct GalleryCropHandle: View {
    let corner: GalleryCropCorner

    var body: some View {
        Path { path in
            let length: CGFloat = 18
            let c = CGPoint(x: 22, y: 22)
            let dx: CGFloat = corner.isLeft ? 1 : -1
            let dy: CGFloat = corner.isTop ? 1 : -1
            path.move(to: CGPoint(x: c.x, y: c.y + dy * length))
            path.addLine(to: c)
            path.addLine(to: CGPoint(x: c.x + dx * length, y: c.y))
        }
        .stroke(Color.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
    }
}

enum GalleryCropRatio: String, CaseIterable, Identifiable {
    case free, original, square, fourThree, threeFour, sixteenNine, nineSixteen

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: "自由"
        case .original: "オリジナル"
        case .square: "正方形"
        case .fourThree: "4:3"
        case .threeFour: "3:4"
        case .sixteenNine: "16:9"
        case .nineSixteen: "9:16"
        }
    }

    /// Width / height.
    func value(for size: CGSize) -> CGFloat? {
        switch self {
        case .free: nil
        case .original: size.width / size.height
        case .square: 1
        case .fourThree: 4.0 / 3
        case .threeFour: 3.0 / 4
        case .sixteenNine: 16.0 / 9
        case .nineSixteen: 9.0 / 16
        }
    }
}
