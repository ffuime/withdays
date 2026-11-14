import SwiftUI

/// 複数選択の書式: what the chosen elements can share — opacity, the text's color and size, the shapes' fill,
/// and the color of outlines and lines.
struct GroupFormatSheet: View {
    @Bindable var editor: DeckEditor

    var body: some View {
        let chosen = editor.chosenElements
        let ids = editor.multiSelection
        let texts = chosen.compactMap(Self.text(of:))
        let shapes = chosen.compactMap { element -> ShapeElement? in
            if case .shape(let shape) = element.content { return shape }
            return nil
        }
        let lines = chosen.compactMap { element -> LineElement? in
            if case .line(let line) = element.content { return line }
            return nil
        }
        NavigationStack {
            Form {
                Section {
                    ValueSlider(
                        title: "不透明度",
                        value: Binding(
                            get: { (chosen.first?.opacity ?? 1) * 100 },
                            set: { value in editor.changeElements(ids, coalesce: "group-opacity") { $0.opacity = value / 100 } }
                        ),
                        range: 0...100,
                        format: { "\(Int($0.rounded()))%" }
                    )
                }
                if let text = texts.first {
                    Section("文字") {
                        ColorRow(color: text.baseRun.color, supportsOpacity: false) { color in
                            editor.formatTexts(ids, key: "color") { $0.applyToAll { $0.color = color } }
                        }
                        HStack {
                            Text("サイズ")
                            Spacer()
                            Button {
                                resizeText(ids, by: 1 / 1.1)
                            } label: {
                                Image(systemName: "textformat.size.smaller")
                                    .frame(width: 44, height: 34)
                            }
                            .accessibilityLabel("小さく")
                            Button {
                                resizeText(ids, by: 1.1)
                            } label: {
                                Image(systemName: "textformat.size.larger")
                                    .frame(width: 44, height: 34)
                            }
                            .accessibilityLabel("大きく")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                if let shape = shapes.first {
                    Section("塗り") {
                        ColorRow(color: Self.solidColor(shape.fill) ?? .brand) { color in
                            editor.changeElements(ids, coalesce: "group-fill") { element in
                                guard case .shape(var shape) = element.content else { return }
                                shape.fill = .solid(color)
                                element.content = .shape(shape)
                            }
                        }
                    }
                }
                if !shapes.isEmpty || !lines.isEmpty {
                    Section("線・枠線の色") {
                        ColorRow(color: lines.first?.stroke.color ?? shapes.first?.stroke?.color ?? .text) { color in
                            editor.changeElements(ids, coalesce: "group-stroke") { element in
                                switch element.content {
                                case .shape(var shape):
                                    shape.stroke = Stroke(color: color, width: shape.stroke?.width ?? 4, dash: shape.stroke?.dash ?? .solid)
                                    element.content = .shape(shape)
                                case .line(var line):
                                    line.stroke.color = color
                                    element.content = .line(line)
                                default:
                                    break
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("書式（\(chosen.count)個）")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func resizeText(_ ids: Set<UUID>, by factor: Double) {
        editor.formatTexts(ids, key: "size") { text in
            text.applyToAll { $0.size = min(max(($0.size * factor).rounded(), 8), 400) }
        }
    }

    private static func text(of element: SlideElement) -> RichText? {
        switch element.content {
        case .text(let box): box.text
        case .table(let table): table.cells.first?.first?.text
        default: nil
        }
    }

    private static func solidColor(_ fill: Fill) -> RGBA? {
        if case .solid(let color) = fill { return color }
        return nil
    }
}

/// 複数選択のアニメーション: one 登場 or 退場 for every chosen element, played at the same time.
struct GroupAnimationSheet: View {
    @Bindable var editor: DeckEditor

    @Environment(\.dismiss) private var dismiss
    @State private var animation = ElementAnimation(elementID: UUID())

    var body: some View {
        let ids = editor.multiSelection
        let hasAnimations = editor.current.animations.contains { ids.contains($0.elementID) }
        NavigationStack {
            Form {
                Section {
                    Picker("種類", selection: $animation.category) {
                        ForEach(AnimationCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                } footer: {
                    Text("選んだ\(ids.count)個の要素に同じ動きを付け、同時に再生します。同じ種類の動きがあれば置き換えます。")
                }
                Section {
                    Picker("効果", selection: $animation.effect) {
                        // 移動 is a way in: from where the same element was on the slide before.
                        ForEach(AnimationEffect.allCases.filter { animation.category == .entrance || $0 != .move }, id: \.self) {
                            Text($0.label).tag($0)
                        }
                    }
                    if animation.effect == .move {
                        Text("前のスライドにある同じ要素の位置・大きさ・角度から動きます。無ければ「表示」と同じです。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    if animation.effect == .slideIn {
                        AngleControl(angle: $animation.angle)
                    }
                    if animation.effect == .zoom {
                        Picker("ズーム", selection: $animation.zoomOut) {
                            Text("ズームイン").tag(false)
                            Text("ズームアウト").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                    Picker("開始", selection: $animation.start) {
                        ForEach(AnimationStart.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    ValueSlider(title: "時間", value: $animation.duration, range: 0.1...5, step: 0.1, format: { String(format: "%.1f秒", $0) })
                    ValueSlider(title: "遅延", value: $animation.delay, range: 0...5, step: 0.1, format: { String(format: "%.1f秒", $0) })
                }
                Section {
                    Button {
                        editor.applyGroupAnimation(animation, to: ids)
                        dismiss()
                    } label: {
                        Text("適用")
                            .font(.system(size: 16, weight: .bold))
                            .frame(maxWidth: .infinity)
                    }
                    .brandGlass(enabled: !ids.isEmpty)
                    .disabled(ids.isEmpty)
                    .listRowBackground(Color.clear)
                }
                if hasAnimations {
                    Section {
                        Button("選んだ要素のアニメーションをすべて削除", role: .destructive) {
                            editor.removeAnimations(of: ids)
                            dismiss()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("アニメーション（\(ids.count)個）")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: animation.category) { _, category in
            if category == .exit, animation.effect == .move { animation.effect = .fade }
        }
    }
}
