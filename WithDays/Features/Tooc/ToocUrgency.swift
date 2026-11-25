import SwiftUI

/// 温度感を伝える: a half sheet with a four-step slider (返信不要 → 急遽！！) and the message, sent with that feeling.
struct ToocUrgencySheet: View {
    let text: String
    var onSend: (ToocUrgency) -> Void

    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var urgency: ToocUrgency = .whenFree

    var body: some View {
        NavigationStack {
            VStack(spacing: 26) {
                // What it will look like.
                VStack(alignment: .trailing, spacing: 4) {
                    ToocUrgencyChip(urgency: urgency)
                        .contentTransition(.interpolate)
                    Text(text)
                        .toocFont(.body)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 8)
                        .background(theme.myBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .frame(maxWidth: .infinity, alignment: .trailing)

                ToocUrgencySlider(value: $urgency)

                Button {
                    onSend(urgency)
                } label: {
                    Label("この温度感で送信", systemImage: "paperplane.fill")
                        .toocFont(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(urgency.color)
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .frame(maxHeight: .infinity, alignment: .top)
            .navigationTitle("温度感を伝える")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.primary) }
                        .accessibilityLabel("閉じる")
                }
            }
        }
        .presentationDetents([.medium])
        .animation(.snappy, value: urgency)
        .sensoryFeedback(.selection, trigger: urgency)
    }
}

/// Four stops on a track: drag the knob or tap a stop. The track fills up to the knob in that step's colour,
/// and each stop's name sits under it (the chosen one in bold).
struct ToocUrgencySlider: View {
    @Binding var value: ToocUrgency

    @State private var dragX: CGFloat?

    private static let knob: CGFloat = 30
    private static let track: CGFloat = 10

    var body: some View {
        let steps = ToocUrgency.allCases
        VStack(spacing: 12) {
            // The stops sit over the middles of the four names below.
            GeometryReader { proxy in
                let column = proxy.size.width / CGFloat(steps.count)
                let first = column / 2
                let last = proxy.size.width - column / 2
                let center = dragX ?? first + CGFloat(value.rawValue) * column
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                        .frame(width: last - first + Self.track, height: Self.track)
                        .offset(x: first - Self.track / 2)
                    Capsule()
                        .fill(LinearGradient(colors: steps.prefix(value.rawValue + 1).map(\.color) + [value.color],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: center - first + Self.track, height: Self.track)
                        .offset(x: first - Self.track / 2)
                    ForEach(steps) { step in
                        Circle()
                            .fill(step.rawValue <= value.rawValue ? Color.white.opacity(0.9) : Color(.systemGray3))
                            .frame(width: 6, height: 6)
                            .offset(x: first + CGFloat(step.rawValue) * column - 3)
                    }
                    Circle()
                        .fill(.white)
                        .frame(width: Self.knob, height: Self.knob)
                        .overlay(Circle().fill(value.color).padding(7))
                        .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        .offset(x: center - Self.knob / 2)
                }
                .frame(height: Self.knob)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            let clamped = min(max(first, drag.location.x), last)
                            dragX = clamped
                            let index = Int(((clamped - first) / column).rounded())
                            if let step = ToocUrgency(rawValue: index), step != value { value = step }
                        }
                        .onEnded { _ in
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { dragX = nil }
                        }
                )
            }
            .frame(height: Self.knob)

            HStack(spacing: 0) {
                ForEach(steps) { step in
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { value = step }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: step.symbol)
                                .font(.system(size: 15, weight: .semibold))
                            Text(step.label)
                                .toocFont(.caption.weight(step == value ? .bold : .regular))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                        .foregroundStyle(step == value ? step.color : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("温度感")
        .accessibilityValue(value.label)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if let next = ToocUrgency(rawValue: value.rawValue + 1) { value = next }
            case .decrement: if let previous = ToocUrgency(rawValue: value.rawValue - 1) { value = previous }
            @unknown default: break
            }
        }
    }
}
