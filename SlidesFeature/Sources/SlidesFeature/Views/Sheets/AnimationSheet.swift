import SwiftUI

/// アニメーション: the selected element's 登場 / 退場 effects, and the slide's play order.
struct AnimationSheet: View {
    @Bindable var editor: DeckEditor
    let elementID: UUID

    var body: some View {
        NavigationStack {
            Form {
                let animations = editor.animations(of: elementID)
                ForEach(animations) { animation in
                    Section {
                        editorRows(animation)
                    } header: {
                        HStack {
                            Text("\(animation.category.label) \(position(of: animation))")
                            Spacer()
                            Button(role: .destructive) {
                                editor.deleteAnimation(animation.id)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .accessibilityLabel("削除")
                        }
                    }
                }
                if !animations.contains(where: { $0.category == .entrance }) || !animations.contains(where: { $0.category == .exit }) {
                    Section {
                        if !animations.contains(where: { $0.category == .entrance }) {
                            Button("登場を追加", systemImage: "plus.circle") { editor.addAnimation(to: elementID, category: .entrance) }
                        }
                        if !animations.contains(where: { $0.category == .exit }) {
                            Button("退場を追加", systemImage: "minus.circle") { editor.addAnimation(to: elementID, category: .exit) }
                        }
                    }
                }
                Section {
                    NavigationLink("このスライドの再生順") {
                        AnimationOrderView(editor: editor)
                    }
                    .disabled(editor.current.animations.isEmpty)
                }
            }
            .navigationTitle("アニメーション")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func position(of animation: ElementAnimation) -> String {
        guard let index = editor.current.animations.firstIndex(where: { $0.id == animation.id }) else { return "" }
        return "（\(index + 1)番目）"
    }

    @ViewBuilder
    private func editorRows(_ animation: ElementAnimation) -> some View {
        Picker("効果", selection: binding(animation, \.effect)) {
            // 移動 is a way in: from where the same element was on the slide before.
            ForEach(AnimationEffect.allCases.filter { animation.category == .entrance || $0 != .move }, id: \.self) { Text($0.label).tag($0) }
        }
        if animation.effect == .move {
            Text("前のスライドにある同じ要素（同じ文字・画像・図形）の位置・大きさ・角度から動きます。無ければ「表示」と同じです。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        if animation.effect == .slideIn {
            AngleControl(angle: binding(animation, \.angle))
        }
        if animation.effect == .zoom {
            Picker("ズーム", selection: binding(animation, \.zoomOut)) {
                Text("ズームイン").tag(false)
                Text("ズームアウト").tag(true)
            }
            .pickerStyle(.segmented)
        }
        Picker("開始", selection: binding(animation, \.start)) {
            ForEach(AnimationStart.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        ValueSlider(title: "時間", value: binding(animation, \.duration), range: 0.1...5, step: 0.1, format: { String(format: "%.1f秒", $0) })
        ValueSlider(title: "遅延", value: binding(animation, \.delay), range: 0...5, step: 0.1, format: { String(format: "%.1f秒", $0) })
    }

    private func binding<Value>(_ animation: ElementAnimation, _ keyPath: WritableKeyPath<ElementAnimation, Value>) -> Binding<Value> {
        Binding(
            get: { editor.current.animations.first { $0.id == animation.id }?[keyPath: keyPath] ?? animation[keyPath: keyPath] },
            set: { value in
                guard var current = editor.current.animations.first(where: { $0.id == animation.id }) else { return }
                current[keyPath: keyPath] = value
                editor.updateAnimation(current)
            }
        )
    }
}

/// Every animation on the slide in play order: drag to reorder, swipe to delete.
struct AnimationOrderView: View {
    @Bindable var editor: DeckEditor

    var body: some View {
        List {
            ForEach(Array(editor.current.animations.enumerated()), id: \.element.id) { index, animation in
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal")
                        .foregroundStyle(.tertiary)
                    Text("\(index + 1)")
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(SlidesTheme.brandText)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(name(of: animation.elementID))：\(effectLabel(animation))（\(animation.category.label)）")
                            .font(.system(size: 14, weight: .semibold))
                        Text(animation.start.label)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button("削除", systemImage: "trash", role: .destructive) { editor.deleteAnimation(animation.id) }
                        .tint(.red)
                }
            }
            .onMove { editor.moveAnimations(from: $0, to: $1) }
        }
        .navigationTitle("再生順（長押しで並べ替え）")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func effectLabel(_ animation: ElementAnimation) -> String {
        switch animation.effect {
        case .slideIn: "\(animation.effect.label)・\(MotionAngle.label(animation.angle))"
        case .zoom: animation.zoomOut ? "ズームアウト" : "ズームイン"
        default: animation.effect.label
        }
    }

    private func name(of id: UUID) -> String {
        guard let element = editor.current.elements.first(where: { $0.id == id }) else { return "要素" }
        if case .text(let box) = element.content {
            let text = box.text.plainText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { return String(text.prefix(12)) }
        }
        return element.kindLabel
    }
}
