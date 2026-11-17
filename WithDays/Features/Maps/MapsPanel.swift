import SwiftUI

/// Maps' bottom sheet in liquid glass: the map stays usable around it. Drag the header between
/// collapsed (only the header), half the screen and nearly full; the content scrolls on its own.
struct MapsPanel<Header: View, Content: View>: View {
    @Binding var detent: PanelDetent
    /// The space the panel may use (the screen minus the search bar), and the home indicator's inset.
    let available: CGFloat
    let bottomInset: CGFloat
    /// Its height as it moves, so the buttons above it follow.
    var onHeight: (CGFloat) -> Void = { _ in }
    @ViewBuilder var header: Header
    @ViewBuilder var content: Content

    @State private var headerHeight: CGFloat = 64
    @State private var dragStart: CGFloat?
    @State private var dragHeight: CGFloat?

    static var margin: CGFloat { 8 }

    /// The settled height of each detent, from the bottom of the screen.
    static func height(_ detent: PanelDetent, header: CGFloat, available: CGFloat, bottomInset: CGFloat) -> CGFloat {
        let collapsed = header + 14 + max(bottomInset, margin)
        switch detent {
        case .collapsed: return collapsed
        case .half: return max(collapsed, available * 0.5)
        case .large: return max(collapsed, available - margin)
        }
    }

    private func height(_ detent: PanelDetent) -> CGFloat {
        Self.height(detent, header: headerHeight, available: available, bottomInset: bottomInset)
    }

    var body: some View {
        let current = dragHeight ?? height(detent)
        VStack(spacing: 0) {
            VStack(spacing: 6) {
                Capsule()
                    .fill(.secondary.opacity(0.5))
                    .frame(width: 36, height: 5)
                    .padding(.top, 8)
                header
            }
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { headerHeight = $0 }
            .contentShape(Rectangle())
            .gesture(drag)
            .onTapGesture {
                // A tap on the header of a collapsed panel opens it.
                if detent == .collapsed { withAnimation(.snappy) { detent = .half } }
            }

            content
                .frame(maxHeight: .infinity, alignment: .top)
                .opacity(detent == .collapsed && dragHeight == nil ? 0 : 1)
        }
        .padding(.bottom, max(bottomInset, Self.margin))
        .frame(height: current, alignment: .top)
        .clipShape(.rect(cornerRadius: 32))
        .glassEffect(.regular, in: .rect(cornerRadius: 32))
        .padding(.horizontal, Self.margin)
        .padding(.bottom, Self.margin)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .onChange(of: current, initial: true) { _, new in onHeight(new + Self.margin) }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .global)
            .onChanged { value in
                let start = dragStart ?? height(detent)
                dragStart = start
                dragHeight = min(height(.large), max(height(.collapsed), start - value.translation.height))
            }
            .onEnded { value in
                let start = dragStart ?? height(detent)
                let projected = start - value.predictedEndTranslation.height
                let nearest = [PanelDetent.collapsed, .half, .large]
                    .min { abs(height($0) - projected) < abs(height($1) - projected) } ?? .half
                withAnimation(.snappy(duration: 0.3)) {
                    detent = nearest
                    dragHeight = nil
                }
                dragStart = nil
            }
    }
}
