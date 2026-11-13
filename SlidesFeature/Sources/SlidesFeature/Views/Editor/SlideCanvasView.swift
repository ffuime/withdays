import SwiftUI
import UniformTypeIdentifiers

/// The slide being edited, fitted to the space with margins. A tap selects an element and a tap on the selected
/// text box (or table cell) starts typing; a drag that starts on an element moves it (snapping to the slide, the
/// guides and other elements). A sideways swipe on empty slide or outside it changes slide: right to left for the
/// next one. Pinching with nothing selected zooms the view like a photo; zoomed in, a drag on empty space moves it.
struct SlideCanvasView: View {
    @Bindable var editor: DeckEditor
    let textController: TextEditingController
    let showsGuides: Bool
    /// Text just inserted is selected whole, so typing replaces it.
    @Binding var selectAllOnEdit: Bool

    @State private var dragOrigin: SlideElement?
    @State private var pinchOrigin: SlideElement?
    /// The view's zoom (1 = the whole slide fits) and how far it's moved.
    @State private var zoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var panStart: CGSize?
    /// The pinch in progress: drawn as a cheap scale of the view, applied to the zoom when it ends.
    @State private var liveZoom: CGFloat = 1
    @State private var liveAnchor = UnitPoint.center
    /// How far the fingers' middle has moved during the pinch.
    @State private var livePan: CGSize = .zero
    @State private var pinchStart: CGPoint?
    /// Pinching an element (resizing it) rather than the view.
    @State private var pinchingElement = false
    /// Two fingers are (or were just) on the screen: taps and drags on elements wait.
    @State private var pinching = false

    var body: some View {
        GeometryReader { geo in
            let fit = min((geo.size.width - 32) / 1920, (geo.size.height - 32) / 1080)
            let scale = fit * zoom
            let size = CGSize(width: 1920 * scale, height: 1080 * scale)
            ZStack {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { deselect() }
                    .gesture(emptyDrag(size: size, area: geo.size))
                slide(scale: scale, size: size, area: geo.size)
                    .frame(width: size.width, height: size.height)
                    .scaleEffect(liveZoom, anchor: liveAnchor)
                    .offset(CGSize(width: pan.width + livePan.width, height: pan.height + livePan.height))
                    .id(editor.current.id)
                    .transition(.asymmetric(
                        // The next slide comes in from the right, following a swipe to the left.
                        insertion: .move(edge: editor.movingForward ? .trailing : .leading).combined(with: .opacity),
                        removal: .move(edge: editor.movingForward ? .leading : .trailing).combined(with: .opacity)
                    ))
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(PinchPanGesture { phase, factor, location in
                pinched(phase, factor: factor, location: location, area: geo.size, slideSize: CGSize(width: 1920 * fit, height: 1080 * fit), size: size)
            })
            // Images dragged in from other apps land where they're dropped.
            .onDrop(of: [.image, .fileURL], isTargeted: nil) { providers, location in
                let origin = CGPoint(
                    x: geo.size.width / 2 + pan.width - size.width / 2,
                    y: geo.size.height / 2 + pan.height - size.height / 2
                )
                let point = CGPoint(
                    x: min(max((location.x - origin.x) / scale, 0), 1920),
                    y: min(max((location.y - origin.y) / scale, 0), 1080)
                )
                return dropImages(providers, at: point)
            }
            .clipped()
            .overlay(alignment: .topTrailing) {
                if zoom > 1.01 {
                    Button {
                        withAnimation(.snappy) {
                            zoom = 1
                            pan = .zero
                        }
                    } label: {
                        Text("\(Int((zoom * 100).rounded()))%")
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                    }
                    .buttonStyle(.glass)
                    .padding(10)
                    .accessibilityLabel("等倍に戻す")
                }
            }
        }
        .onChange(of: editor.currentIndex) { _, _ in
            zoom = 1
            pan = .zero
        }
    }

    // MARK: Slide

    private func slide(scale: CGFloat, size: CGSize, area: CGSize) -> some View {
        let slide = editor.current
        return ZStack(alignment: .topLeading) {
            ZStack(alignment: .topLeading) {
                SlideBackgroundView(background: slide.background, deck: editor.deckID)
                    .frame(width: size.width, height: size.height)
                    .contentShape(Rectangle())
                    .onTapGesture { deselect() }
                    .gesture(emptyDrag(size: size, area: area))
                ForEach(slide.elements) { element in
                    elementView(element, scale: scale)
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

            if showsGuides {
                GuidesOverlay()
                    .frame(width: size.width, height: size.height)
            }
            snapLines(scale: scale, size: size)
            if let element = editor.selectedElement {
                SelectionOverlay(editor: editor, element: element, scale: scale, editing: editor.editing != nil, guides: showsGuides)
            }
            if let editing = editor.editing, let element = editor.selectedElement, let text = editor.editingText() {
                textEditor(editing, element: element, text: text, scale: scale)
            }
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .coordinateSpace(.named("slide"))
    }

    /// Where a dragged element lines up.
    private func snapLines(scale: CGFloat, size: CGSize) -> some View {
        Canvas { context, _ in
            for line in editor.snapLines {
                var path = Path()
                if line.vertical {
                    path.move(to: CGPoint(x: line.position * scale, y: 0))
                    path.addLine(to: CGPoint(x: line.position * scale, y: size.height))
                } else {
                    path.move(to: CGPoint(x: 0, y: line.position * scale))
                    path.addLine(to: CGPoint(x: size.width, y: line.position * scale))
                }
                context.stroke(path, with: .color(Color(red: 0.95, green: 0.25, blue: 0.55)), lineWidth: 1)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func elementView(_ element: SlideElement, scale: CGFloat) -> some View {
        let frame = element.frame.cg
        let padding = SlideRenderer.padding(for: element)
        return ElementRenderView(element: displayed(element), deck: editor.deckID, scale: scale, placeholders: true)
            .frame(width: (frame.width + padding * 2) * scale, height: (frame.height + padding * 2) * scale)
            // The padding (room for strokes and shadows) only counts a little for touches.
            .contentShape(Rectangle().inset(by: max(padding * scale - 10, 0)))
            .allowsHitTesting(!pinching)
            .rotationEffect(.degrees(element.rotation))
            .opacity(element.opacity)
            .position(x: frame.midX * scale, y: frame.midY * scale)
            .onTapGesture(coordinateSpace: .named("slide")) { location in
                guard !pinching else { return }
                tap(element, at: CGPoint(x: location.x / scale, y: location.y / scale))
            }
            .gesture(move(element, scale: scale))
            .accessibilityElement()
            .accessibilityLabel(element.kindLabel)
            .accessibilityAddTraits(editor.selection == element.id ? [.isButton, .isSelected] : .isButton)
    }

    /// What's being typed in isn't drawn underneath the text view.
    private func displayed(_ element: SlideElement) -> SlideElement {
        guard let editing = editor.editing, editing.elementID == element.id else { return element }
        var shown = element
        switch (editing, element.content) {
        case (.text, .text):
            shown.content = .text(TextBoxElement(text: RichText(runs: [])))
        case (.cell(_, let row, let column), .table(var table)):
            if table.cells.indices.contains(row), table.cells[row].indices.contains(column) {
                table.cells[row][column].text.runs = []
            }
            shown.content = .table(table)
        default:
            break
        }
        return shown
    }

    // MARK: Typing

    @ViewBuilder
    private func textEditor(_ editing: EditTarget, element: SlideElement, text: RichText, scale: CGFloat) -> some View {
        let frame = element.frame.cg
        let area: CGRect = {
            if case .cell(_, let row, let column) = editing, case .table(let table) = element.content {
                return table.cellRect(row: row, column: column, in: frame.size)
            }
            return CGRect(origin: .zero, size: frame.size)
        }()
        // The area's middle, turned with the element around the element's middle.
        let angle = element.rotation * .pi / 180
        let local = CGPoint(x: area.midX - frame.width / 2, y: area.midY - frame.height / 2)
        let center = CGPoint(
            x: frame.midX + local.x * CGFloat(cos(angle)) - local.y * CGFloat(sin(angle)),
            y: frame.midY + local.x * CGFloat(sin(angle)) + local.y * CGFloat(cos(angle))
        )
        let inset: CGFloat = if case .cell = editing { SlideRenderer.cellInset } else { 0 }
        RichTextEditingView(
            text: text, size: area.size, inset: inset, scale: scale, controller: textController,
            selectAll: selectAllOnEdit
        ) { changed in
            editor.setEditingText(changed)
        }
        .id(editingKey(editing))
        .frame(width: area.width * scale, height: area.height * scale)
        .rotationEffect(.degrees(element.rotation))
        .opacity(element.opacity)
        .position(x: center.x * scale, y: center.y * scale)
        .onAppear { selectAllOnEdit = false }
    }

    private func editingKey(_ target: EditTarget) -> String {
        switch target {
        case .text(let id): "text-\(id)"
        case .cell(let id, let row, let column): "cell-\(id)-\(row)-\(column)"
        }
    }

    // MARK: Gestures

    /// `point` is in slide points.
    private func tap(_ element: SlideElement, at point: CGPoint) {
        guard editor.selection == element.id else {
            finishTyping()
            editor.selection = element.id
            return
        }
        switch element.content {
        case .text:
            editor.editing = .text(element.id)
        case .table(let table):
            // The cell under the finger, in the table's own (unturned) axes.
            let frame = element.frame.cg
            let angle = -element.rotation * .pi / 180
            let dx = Double(point.x - frame.midX)
            let dy = Double(point.y - frame.midY)
            let local = CGPoint(
                x: CGFloat(dx * cos(angle) - dy * sin(angle)) + frame.width / 2,
                y: CGFloat(dx * sin(angle) + dy * cos(angle)) + frame.height / 2
            )
            for row in 0..<table.rows {
                for column in 0..<table.columns where table.cellRect(row: row, column: column, in: frame.size).contains(local) {
                    if editor.editing != nil { textController.finish() }
                    editor.editing = .cell(element.id, row: row, column: column)
                    return
                }
            }
        default:
            break
        }
    }

    private func move(_ element: SlideElement, scale: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("slide"))
            .onChanged { value in
                guard !pinching else { return }
                if dragOrigin?.id != element.id {
                    finishTyping()
                    editor.selection = element.id
                    editor.beginInteraction()
                    dragOrigin = element
                }
                guard var moved = dragOrigin else { return }
                moved.move(by: Double(value.translation.width / scale), Double(value.translation.height / scale))
                let snapper = Snapper(slide: editor.current, excluding: element.id, guides: showsGuides, threshold: Double(8 / scale))
                let lines = snapper.snapMove(&moved)
                if lines != editor.snapLines { editor.snapLines = lines }
                editor.changeElement(element.id) { $0 = moved }
            }
            .onEnded { _ in
                dragOrigin = nil
                editor.snapLines = []
                editor.endInteraction()
            }
    }

    /// With an element selected, pinching resizes it around its middle. Otherwise it zooms the view around the
    /// fingers and moves it with them, like a photo: a scale while pinching, redrawn sharp when they lift.
    private func pinched(_ phase: PinchPanGesture.Phase, factor: CGFloat, location: CGPoint, area: CGSize, slideSize: CGSize, size: CGSize) {
        switch phase {
        case .began:
            pinching = true
            cancelDrag()
            pinchStart = location
            pinchingElement = editor.editing == nil && editor.selectedElement != nil
            if pinchingElement, let selected = editor.selectedElement {
                editor.beginInteraction()
                pinchOrigin = selected
            } else {
                // Where the fingers are, as a point of the slide view (before any of this pinch).
                let origin = CGPoint(
                    x: area.width / 2 + pan.width - size.width / 2,
                    y: area.height / 2 + pan.height - size.height / 2
                )
                liveAnchor = UnitPoint(
                    x: (location.x - origin.x) / max(size.width, 1),
                    y: (location.y - origin.y) / max(size.height, 1)
                )
            }
        case .changed:
            if pinchingElement {
                guard let origin = pinchOrigin else { return }
                let scale = max(0.1, min(Double(factor), 10))
                editor.changeElement(origin.id) { $0 = Self.scaled(origin, by: scale) }
                return
            }
            liveZoom = min(max(factor, 1 / zoom), 5 / zoom)
            if let start = pinchStart {
                livePan = CGSize(width: location.x - start.x, height: location.y - start.y)
            }
        case .ended:
            if pinchingElement {
                pinchOrigin = nil
                editor.endInteraction()
            } else {
                // The point that was under the fingers stays under them.
                let factor = liveZoom
                let shift = CGSize(
                    width: (0.5 - liveAnchor.x) * size.width * (factor - 1) + livePan.width,
                    height: (0.5 - liveAnchor.y) * size.height * (factor - 1) + livePan.height
                )
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    zoom = min(max(zoom * factor, 1), 5)
                    liveZoom = 1
                    liveAnchor = .center
                    livePan = .zero
                    pan = clampedPan(CGSize(width: pan.width + shift.width, height: pan.height + shift.height), area: area, slideSize: slideSize)
                }
                if zoom < 1.05 {
                    withAnimation(.snappy) {
                        zoom = 1
                        pan = .zero
                    }
                }
            }
            pinchStart = nil
            pinchingElement = false
            // Lifting two fingers often ends in a stray tap.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { pinching = false }
        }
    }

    /// A drag that turned into a pinch puts the element back.
    private func cancelDrag() {
        guard let origin = dragOrigin else { return }
        dragOrigin = nil
        editor.changeElement(origin.id) { $0 = origin }
        editor.snapLines = []
        editor.endInteraction()
    }

    /// Keeps the zoomed slide from leaving the view.
    private func clampedPan(_ pan: CGSize, area: CGSize, slideSize: CGSize) -> CGSize {
        let width = slideSize.width * zoom
        let height = slideSize.height * zoom
        let limitX = max(0, (width - area.width) / 2 + 40)
        let limitY = max(0, (height - area.height) / 2 + 40)
        return CGSize(width: min(max(pan.width, -limitX), limitX), height: min(max(pan.height, -limitY), limitY))
    }

    static func scaled(_ element: SlideElement, by factor: Double) -> SlideElement {
        var result = element
        let center = element.frame.center
        if case .line(var line) = element.content {
            for point in [\LineElement.start, \LineElement.end] {
                let value = line[keyPath: point]
                line[keyPath: point] = SlidePoint(
                    x: Double(center.x) + (value.x - Double(center.x)) * factor,
                    y: Double(center.y) + (value.y - Double(center.y)) * factor
                )
            }
            result.content = .line(line)
            result.syncLineFrame()
            return result
        }
        let width = max(element.frame.width * factor, 16)
        let height = max(element.frame.height * factor, 16)
        result.frame = SlideRect(x: Double(center.x) - width / 2, y: Double(center.y) - height / 2, width: width, height: height)
        return result
    }

    /// On empty space: moves the zoomed view around, or (not zoomed) swipes to another slide.
    private func emptyDrag(size: CGSize, area: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard zoom > 1.01, !pinching else { return }
                if panStart == nil { panStart = pan }
                let start = panStart ?? .zero
                let slideSize = CGSize(width: size.width / zoom, height: size.height / zoom)
                pan = clampedPan(
                    CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height),
                    area: area, slideSize: slideSize
                )
            }
            .onEnded { value in
                if panStart != nil {
                    panStart = nil
                    return
                }
                let dx = value.translation.width
                guard !pinching, abs(dx) > 60, abs(dx) > abs(value.translation.height) * 1.5 else { return }
                // Right to left for the next slide, left to right for the previous one.
                let target = editor.currentIndex + (dx < 0 ? 1 : -1)
                guard editor.slides.indices.contains(target) else { return }
                finishTyping()
                editor.show(target)
            }
    }

    /// Loads each dropped image (SVG drawn first) and puts it on the slide, a little apart from the one before.
    private func dropImages(_ providers: [NSItemProvider], at point: CGPoint) -> Bool {
        let images = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        guard !images.isEmpty else { return false }
        for (index, provider) in images.enumerated() {
            let type = provider.registeredTypeIdentifiers.first { UTType($0)?.conforms(to: .image) == true } ?? UTType.image.identifier
            provider.loadDataRepresentation(forTypeIdentifier: type) { data, _ in
                guard let data else { return }
                Task { @MainActor in
                    do {
                        let usable = try await ImageLoading.usableData(data)
                        let offset = CGFloat(index) * 40
                        try editor.insertImage(usable, at: CGPoint(x: point.x + offset, y: point.y + offset))
                    } catch {
                        // An image that can't be read is skipped.
                    }
                }
            }
        }
        return true
    }

    private func deselect() {
        finishTyping()
        editor.selection = nil
    }

    private func finishTyping() {
        guard editor.editing != nil else { return }
        textController.finish()
        editor.editing = nil
    }
}

/// The selected element's frame: eight handles to resize (corners keep the shape, edges change it), one above
/// to turn it. A line has a handle on each end. Edges and ends snap like moving does; turning settles on every 15°.
struct SelectionOverlay: View {
    @Bindable var editor: DeckEditor
    let element: SlideElement
    let scale: CGFloat
    let editing: Bool
    let guides: Bool

    @State private var origin: SlideElement?

    private static let handles: [(x: CGFloat, y: CGFloat)] = [
        (0, 0), (0.5, 0), (1, 0), (1, 0.5), (1, 1), (0.5, 1), (0, 1), (0, 0.5),
    ]

    private var snapper: Snapper {
        Snapper(slide: editor.current, excluding: element.id, guides: guides, threshold: Double(8 / scale))
    }

    var body: some View {
        if case .line(let line) = element.content {
            lineHandles(line)
        } else {
            frameHandles
        }
    }

    private var frameHandles: some View {
        let frame = element.frame.cg
        let width = frame.width * scale
        let height = frame.height * scale
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .stroke(SlidesTheme.brand, lineWidth: 1.5)
                .frame(width: width, height: height)
                .allowsHitTesting(false)
            if !editing {
                // The turning handle, on a short stem above the top edge.
                Rectangle()
                    .fill(SlidesTheme.brand)
                    .frame(width: 1.5, height: 22)
                    .position(x: width / 2, y: -11)
                    .allowsHitTesting(false)
                handle
                    .position(x: width / 2, y: -28)
                    .gesture(rotate)
                    .accessibilityLabel("回転")
                ForEach(Self.handles.indices, id: \.self) { index in
                    let point = Self.handles[index]
                    handle
                        .position(x: point.x * width, y: point.y * height)
                        .gesture(resize(point))
                        .accessibilityLabel("サイズ変更")
                }
            }
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .rotationEffect(.degrees(element.rotation))
        .position(x: frame.midX * scale, y: frame.midY * scale)
    }

    private var handle: some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().strokeBorder(SlidesTheme.brand, lineWidth: 2))
            .frame(width: 14, height: 14)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
    }

    private func lineHandles(_ line: LineElement) -> some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            handle
                .position(x: line.start.x * scale, y: line.start.y * scale)
                .gesture(moveEnd(\.start))
                .accessibilityLabel("始点")
            handle
                .position(x: line.end.x * scale, y: line.end.y * scale)
                .gesture(moveEnd(\.end))
                .accessibilityLabel("終点")
        }
    }

    private func begin() {
        guard origin == nil else { return }
        origin = element
        editor.beginInteraction()
    }

    private func end() {
        origin = nil
        editor.snapLines = []
        editor.endInteraction()
    }

    private func moveEnd(_ end: WritableKeyPath<LineElement, SlidePoint>) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("slide"))
            .onChanged { value in
                begin()
                guard let origin, case .line(var line) = origin.content else { return }
                var point = line[keyPath: end]
                point.x += Double(value.translation.width / scale)
                point.y += Double(value.translation.height / scale)
                editor.snapLines = snapper.snapPoint(&point)
                line[keyPath: end] = point
                editor.changeElement(origin.id) { element in
                    element.content = .line(line)
                    element.syncLineFrame()
                }
            }
            .onEnded { _ in self.end() }
    }

    /// Drags one edge or corner; the opposite one stays put, also when the element is turned.
    /// Unturned, the moving edges snap.
    private func resize(_ handle: (x: CGFloat, y: CGFloat)) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("slide"))
            .onChanged { value in
                begin()
                guard let origin else { return }
                let angle = origin.rotation * .pi / 180
                // The drag in the element's own (unturned) axes, in slide points.
                let dx = Double(value.translation.width / scale)
                let dy = Double(value.translation.height / scale)
                let localX = dx * cos(angle) + dy * sin(angle)
                let localY = -dx * sin(angle) + dy * cos(angle)
                let width = origin.frame.width
                let height = origin.frame.height
                var left = -width / 2, right = width / 2, top = -height / 2, bottom = height / 2
                if handle.x == 0 { left = min(left + localX, right - 16) }
                if handle.x == 1 { right = max(right + localX, left + 16) }
                if handle.y == 0 { top = min(top + localY, bottom - 16) }
                if handle.y == 1 { bottom = max(bottom + localY, top + 16) }
                let corner = handle.x != 0.5 && handle.y != 0.5
                if corner {
                    // A corner keeps the width-to-height ratio: the larger change wins, the opposite corner stays.
                    let factor = max((right - left) / width, (bottom - top) / height, 16 / min(width, height))
                    let newWidth = width * factor
                    let newHeight = height * factor
                    if handle.x == 0 { left = right - newWidth } else { right = left + newWidth }
                    if handle.y == 0 { top = bottom - newHeight } else { bottom = top + newHeight }
                }
                var lines: [SnapLine] = []
                let unturned = origin.rotation.truncatingRemainder(dividingBy: 360) == 0
                if unturned, !corner {
                    let center = origin.frame.center
                    let snapper = snapper
                    if handle.x != 0.5, let x = snapper.snap([Double(center.x) + (handle.x == 0 ? left : right)], vertical: true) {
                        if handle.x == 0 { left = min(left + x.shift, right - 16) } else { right = max(right + x.shift, left + 16) }
                        lines.append(SnapLine(vertical: true, position: x.line))
                    }
                    if handle.y != 0.5, let y = snapper.snap([Double(center.y) + (handle.y == 0 ? top : bottom)], vertical: false) {
                        if handle.y == 0 { top = min(top + y.shift, bottom - 16) } else { bottom = max(bottom + y.shift, top + 16) }
                        lines.append(SnapLine(vertical: false, position: y.line))
                    }
                }
                editor.snapLines = lines
                let shiftX = (left + right) / 2
                let shiftY = (top + bottom) / 2
                let center = origin.frame.center
                let newCenterX = Double(center.x) + shiftX * cos(angle) - shiftY * sin(angle)
                let newCenterY = Double(center.y) + shiftX * sin(angle) + shiftY * cos(angle)
                let newWidth = right - left
                let newHeight = bottom - top
                editor.changeElement(origin.id) { element in
                    element.frame = SlideRect(x: newCenterX - newWidth / 2, y: newCenterY - newHeight / 2, width: newWidth, height: newHeight)
                }
            }
            .onEnded { _ in end() }
    }

    /// Turns the element toward the finger; it settles on every 15° when close.
    private var rotate: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("slide"))
            .onChanged { value in
                begin()
                guard let origin else { return }
                let center = origin.frame.center
                let dx = Double(value.location.x / scale) - Double(center.x)
                let dy = Double(value.location.y / scale) - Double(center.y)
                var degrees = atan2(dy, dx) * 180 / .pi + 90
                degrees = degrees.truncatingRemainder(dividingBy: 360)
                if degrees < 0 { degrees += 360 }
                let nearest = (degrees / 15).rounded() * 15
                if abs(degrees - nearest) < 3 { degrees = nearest.truncatingRemainder(dividingBy: 360) }
                editor.changeElement(origin.id) { $0.rotation = degrees }
            }
            .onEnded { _ in end() }
    }
}
