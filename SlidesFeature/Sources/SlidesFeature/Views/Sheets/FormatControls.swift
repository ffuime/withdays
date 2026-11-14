import PhotosUI
import SwiftUI

/// Formatting text from the sheets: to the selected range while typing, otherwise to the whole box
/// (or every cell of a table).
@MainActor
struct TextFormatter {
    let editor: DeckEditor
    let controller: TextEditingController
    let elementID: UUID

    var typing: Bool { editor.editing?.elementID == elementID && controller.isActive }

    /// The box's text: a text box's, or a table's first cell.
    var text: RichText {
        if typing { return controller.base }
        guard let element = editor.current.elements.first(where: { $0.id == elementID }) else { return RichText(runs: []) }
        switch element.content {
        case .text(let box): return box.text
        case .table(let table): return table.cells.first?.first?.text ?? RichText(runs: [])
        default: return RichText(runs: [])
        }
    }

    var run: TextRun {
        typing ? controller.currentRun() : text.baseRun
    }

    func applyRun(key: String, _ change: @escaping (inout TextRun) -> Void) {
        if typing {
            controller.applyRun(change)
        } else {
            editor.formatText(elementID, key: key) { $0.applyToAll(change) }
        }
    }

    func applyBox(key: String, _ change: @escaping (inout RichText) -> Void) {
        if typing {
            controller.applyBox(change)
        } else {
            editor.formatText(elementID, key: key, change)
        }
    }
}

/// The preset swatches and a picker for any color.
struct ColorRow: View {
    let color: RGBA
    var supportsOpacity = true
    var onPick: (RGBA) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(SlidesTheme.swatches, id: \.self) { swatch in
                Button { onPick(swatch.withAlpha(color.a)) } label: {
                    Circle()
                        .fill(swatch.color)
                        .frame(width: 24, height: 24)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(0.18), lineWidth: 1))
                        .padding(3)
                        .overlay {
                            if swatch.hexString == color.hexString {
                                Circle().strokeBorder(SlidesTheme.brand, lineWidth: 2)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("#\(swatch.hexString)")
            }
            ColorPicker("色", selection: Binding(get: { color.color }, set: { onPick(RGBA($0)) }), supportsOpacity: supportsOpacity)
                .labelsHidden()
                .padding(.leading, 4)
        }
    }
}

/// A slider with its value written beside it. Round values (0, the middle and the ends, or `marks`) hold the thumb
/// for a little way and tap as it lands on them.
struct ValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var format: (Double) -> String = { String(Int($0.rounded())) }
    var marks: [Double]?

    /// The round value the thumb is resting on.
    @State private var resting: Double?

    private var points: [Double] {
        if let marks { return marks }
        var points = [range.lowerBound, range.upperBound, (range.lowerBound + range.upperBound) / 2]
        if range.contains(0) { points.append(0) }
        return points
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(format(value))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 14))
            Slider(value: Binding(get: { value }, set: settle), in: range, step: step)
                .tint(SlidesTheme.brand)
        }
        .sensoryFeedback(.impact(weight: .light), trigger: resting) { _, new in new != nil }
    }

    /// Within 2.5 % of the range from a round value, the thumb stays on it.
    private func settle(_ raw: Double) {
        let window = (range.upperBound - range.lowerBound) * 0.025
        if let point = points.min(by: { abs($0 - raw) < abs($1 - raw) }), abs(point - raw) <= window {
            value = point
            if resting != point { resting = point }
        } else {
            value = raw
            if resting != nil { resting = nil }
        }
    }
}

/// 単色 / グラデーション / 画像, for shapes and slide backgrounds.
struct FillEditor: View {
    @Binding var fill: Fill
    /// Saves a picked image and returns its file name.
    var storeImage: (Data) throws -> String

    @State private var kind = 0
    @State private var selectedStop: UUID?
    @State private var photo: PhotosPickerItem?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Picker("種類", selection: Binding(get: { currentKind }, set: switchKind)) {
                Text("単色").tag(0)
                Text("グラデーション").tag(1)
                Text("画像").tag(2)
            }
            .pickerStyle(.segmented)

            switch fill {
            case .solid(let color):
                ColorRow(color: color) { fill = .solid($0) }
            case .gradient(let gradient):
                gradientEditor(gradient)
            case .image(let ref):
                imageEditor(ref)
            default:
                ColorRow(color: .brand) { fill = .solid($0) }
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { return }
                    let name = try storeImage(data)
                    let mode: ImageFitMode = if case .image(let ref) = fill { ref.mode } else { .fill }
                    fill = .image(ImageRef(asset: name, mode: mode))
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .alert("画像を読み込めませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var currentKind: Int {
        switch fill {
        case .none, .solid: 0
        case .gradient: 1
        case .image: 2
        }
    }

    private func switchKind(_ kind: Int) {
        switch kind {
        case 0:
            if case .gradient(let gradient) = fill, let first = gradient.sortedStops.first {
                fill = .solid(first.color)
            } else if currentKind != 0 {
                fill = .solid(.brand)
            }
        case 1:
            if case .solid(let color) = fill {
                fill = .gradient(LinearGradientFill(stops: [GradientStop(color: color, location: 0), GradientStop(color: RGBA(hex: 0x2563EB), location: 1)], angle: 135))
            } else if currentKind != 1 {
                fill = .gradient(.default)
            }
        default:
            if currentKind != 2 { fill = .image(ImageRef(asset: "", mode: .fill)) }
        }
    }

    // MARK: Gradient

    private func gradientEditor(_ gradient: LinearGradientFill) -> some View {
        let selected = gradient.stops.first { $0.id == selectedStop } ?? gradient.sortedStops.first
        return VStack(alignment: .leading, spacing: 12) {
            GradientBar(gradient: gradient, selected: selected?.id) { id in
                selectedStop = id
            } move: { id, location in
                update { gradient in
                    if let index = gradient.stops.firstIndex(where: { $0.id == id }) { gradient.stops[index].location = location }
                }
            }
            HStack(spacing: 10) {
                Button {
                    update { gradient in
                        let stop = GradientStop(color: selected?.color ?? .white, location: 0.5)
                        gradient.stops.append(stop)
                        selectedStop = stop.id
                    }
                } label: {
                    Label("色を追加", systemImage: "plus")
                        .font(.system(size: 13, weight: .semibold))
                }
                .buttonStyle(.glass)
                Button(role: .destructive) {
                    guard let selected else { return }
                    update { gradient in gradient.stops.removeAll { $0.id == selected.id } }
                    selectedStop = nil
                } label: {
                    Label("色を削除", systemImage: "minus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.glass)
                .disabled(gradient.stops.count <= 2)
                Spacer()
            }
            if let selected {
                ColorRow(color: selected.color) { color in
                    update { gradient in
                        if let index = gradient.stops.firstIndex(where: { $0.id == selected.id }) { gradient.stops[index].color = color }
                    }
                }
            }
            ValueSlider(
                title: "角度",
                value: Binding(get: { gradient.angle }, set: { angle in update { $0.angle = angle } }),
                range: 0...360, format: { "\(Int($0.rounded()))°" }
            )
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(SlidesTheme.gradientPresets.indices, id: \.self) { index in
                        let preset = SlidesTheme.gradientPresets[index]
                        Button {
                            fill = .gradient(preset)
                            selectedStop = nil
                        } label: {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(LinearGradient(
                                    stops: preset.sortedStops.map { .init(color: $0.color.color, location: $0.location) },
                                    startPoint: .leading, endPoint: .trailing
                                ))
                                .frame(width: 64, height: 40)
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.15)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("グラデーションのプリセット\(index + 1)")
                    }
                }
            }
            .scrollIndicators(.hidden)
        }
    }

    private func update(_ change: (inout LinearGradientFill) -> Void) {
        guard case .gradient(var gradient) = fill else { return }
        change(&gradient)
        fill = .gradient(gradient)
    }

    // MARK: Image

    private func imageEditor(_ ref: ImageRef) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            PhotosPicker(selection: $photo, matching: .images) {
                Label(ref.asset.isEmpty ? "画像を選択" : "画像を変更", systemImage: "photo")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            Picker("表示", selection: Binding(get: { ref.mode }, set: { mode in
                if case .image(var current) = fill {
                    current.mode = mode
                    fill = .image(current)
                }
            })) {
                ForEach(ImageFitMode.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }
}

/// The gradient with a handle per color stop: tap to pick one, drag to move it.
struct GradientBar: View {
    let gradient: LinearGradientFill
    let selected: UUID?
    var select: (UUID) -> Void
    var move: (UUID, Double) -> Void

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width - 28
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(LinearGradient(
                        stops: gradient.sortedStops.map { .init(color: $0.color.color, location: $0.location) },
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(height: 28)
                    .overlay(Capsule().strokeBorder(Color.primary.opacity(0.15)))
                    .padding(.horizontal, 14)
                ForEach(gradient.stops) { stop in
                    Circle()
                        .fill(stop.color.color)
                        .overlay(Circle().strokeBorder(Color.white, lineWidth: 3))
                        .overlay(Circle().strokeBorder(stop.id == selected ? SlidesTheme.brand : Color.black.opacity(0.25), lineWidth: stop.id == selected ? 2 : 1).padding(-2))
                        .frame(width: 24, height: 24)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                        .position(x: 14 + width * stop.location, y: geo.size.height / 2)
                        .onTapGesture { select(stop.id) }
                        .gesture(
                            DragGesture(minimumDistance: 1, coordinateSpace: .named("gradientBar"))
                                .onChanged { value in
                                    select(stop.id)
                                    move(stop.id, min(max((value.location.x - 14) / max(width, 1), 0), 1))
                                }
                        )
                        .accessibilityLabel("色の位置 \(Int(stop.location * 100))%")
                }
            }
            .coordinateSpace(.named("gradientBar"))
        }
        .frame(height: 48)
    }
}

extension View {
    /// The format sheets: the slide stays in view above, and the sheet keeps its height and scrolls inside.
    func formatSheet() -> some View {
        presentationDetents([.medium])
            .presentationContentInteraction(.scrolls)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .presentationDragIndicator(.visible)
    }
}
