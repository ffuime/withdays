import PDFKit
import PencilKit
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// The editor's handle on the page on screen: undo / redo, the selection and its actions,
/// and saving right away (before an export or leaving).
@MainActor
@Observable
final class NoteCanvasController {
    fileprivate(set) var canUndo = false
    fileprivate(set) var canRedo = false
    fileprivate(set) var hasSelection = false
    /// Handwriting is selected, so it can be read as text.
    fileprivate(set) var hasSelectedStrokes = false
    fileprivate(set) var canPaste = false
    @ObservationIgnored fileprivate weak var page: NotePageView?
    @ObservationIgnored fileprivate var flushAction: (() -> Void)?

    func undo() {
        page?.undo()
    }

    func redo() {
        page?.redo()
    }

    func flush() {
        flushAction?()
    }

    func perform(_ action: NoteSelectionAction) {
        page?.overlay.perform(action)
        refresh()
    }

    func paste() {
        page?.overlay.paste()
        refresh()
    }

    /// Reads the selected handwriting and puts a text box in its place; false when nothing could be read.
    func selectionToText() async -> Bool {
        guard let page, let (image, bounds) = page.overlay.selectedStrokesImage() else { return false }
        let text = await NoteOCR.recognize(image).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }
        page.overlay.replaceSelectedStrokes(with: text, in: bounds)
        refresh()
        return true
    }

    fileprivate func refresh() {
        canUndo = page?.canUndo ?? false
        canRedo = page?.canRedo ?? false
        hasSelection = !(page?.overlay.selection.isEmpty ?? true)
        hasSelectedStrokes = !(page?.overlay.selection.strokes.isEmpty ?? true)
        canPaste = NoteClipboard.clip != nil
    }
}

extension NoteToolSettings {
    /// The width PencilKit draws with: it has a thinnest width for each ink. Thinner lines are drawn by the page
    /// itself while the finger moves (PencilKit's own stroke is kept invisible), then stored at the width asked for.
    static func toolWidth(_ width: Double, _ ink: PKInkingTool.InkType) -> CGFloat {
        max(CGFloat(width), ink.validWidthRange.lowerBound)
    }

    /// The ink's colour for PencilKit: invisible when the line is thinner than PencilKit can draw, so only the thin
    /// line the page draws shows (never a thick one that thins on lifting).
    static func toolColor(_ hex: Int, _ width: Double, _ ink: PKInkingTool.InkType) -> UIColor {
        let color = UIColor(notesHex: hex)
        return CGFloat(width) < ink.validWidthRange.lowerBound - 0.01 ? color.withAlphaComponent(0.01) : color
    }

    /// The PencilKit tool for the pen, highlighter and eraser; selecting, tape and text aren't PencilKit's.
    func pkTool(_ tool: NoteTool) -> (any PKTool)? {
        switch tool {
        case .pen: PKInkingTool(.pen, color: Self.toolColor(pen.color, pen.width, .pen), width: Self.toolWidth(pen.width, .pen))
        case .marker: PKInkingTool(.marker, color: Self.toolColor(marker.color, marker.width, .marker), width: Self.toolWidth(marker.width, .marker))
        case .eraser: eraserWhole ? PKEraserTool(.vector) : PKEraserTool(.bitmap, width: eraserWidth)
        case .select, .tape, .text: nil
        }
    }
}

/// One page to write on with a finger: one finger draws, two fingers scroll and pinch to zoom,
/// and a two-finger sideways swipe on the whole page (or one finger beside the page) turns it.
/// A two-finger tap undoes, a three-finger tap redoes.
struct NoteCanvas: UIViewRepresentable {
    let page: NotePage
    let pdf: PDFPage?
    let image: UIImage?
    let tool: NoteTool
    let settings: NoteToolSettings
    /// Every tape is out of sight (and out of reach) for now.
    let hideTapes: Bool
    let controller: NoteCanvasController
    var load: () -> PKDrawing
    var save: (PKDrawing) -> Void
    var loadItems: () -> NoteItems
    var saveItems: (NoteItems) -> Void
    /// +1 for the next page, -1 for the previous one.
    var onTurn: (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> NotePageView {
        let view = NotePageView(page: page, pdf: pdf, image: image, items: loadItems())
        let coordinator = context.coordinator
        coordinator.view = view
        coordinator.loading = true
        view.canvas.drawing = load()
        coordinator.loading = false
        view.resetHistory()
        view.canvas.delegate = coordinator
        view.onSaveItems = { [weak coordinator] in coordinator?.parent.saveItems($0) }
        view.onTurn = { [weak coordinator] in coordinator?.parent.onTurn($0) }
        view.onHistory = { [weak coordinator] in coordinator?.parent.controller.refresh() }
        view.apply(tool: tool, settings: settings)
        view.overlay.tapesHidden = hideTapes
        coordinator.applied = Applied(tool: tool, settings: settings)

        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.twoFingerPan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = coordinator
        view.addGestureRecognizer(pan)

        controller.page = view
        controller.flushAction = { [weak coordinator] in coordinator?.flush() }
        controller.refresh()
        return view
    }

    func updateUIView(_ view: NotePageView, context: Context) {
        context.coordinator.parent = self
        // Only when something changed: the canvas mustn't be given a tool in the middle of a stroke.
        let applied = Applied(tool: tool, settings: settings)
        if context.coordinator.applied != applied {
            context.coordinator.applied = applied
            view.apply(tool: tool, settings: settings)
        }
        view.overlay.tapesHidden = hideTapes
        view.update(page: page)
    }

    static func dismantleUIView(_ view: NotePageView, coordinator: Coordinator) {
        coordinator.flush()
    }

    struct Applied: Equatable {
        let tool: NoteTool
        let settings: NoteToolSettings
    }

    @MainActor
    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var parent: NoteCanvas
        weak var view: NotePageView?
        var applied: Applied?
        var loading = false
        private var pending: DispatchWorkItem?

        init(_ parent: NoteCanvas) {
            self.parent = parent
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard !loading else { return }
            view?.drawingChanged()
            // Saved a moment after the last change, not on every point.
            pending?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.saveNow() }
            pending = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }

        private func saveNow() {
            guard pending != nil, let canvas = view?.canvas else { return }
            pending?.cancel()
            pending = nil
            parent.save(canvas.drawing)
        }

        /// Saves what's waiting and finishes any text being typed.
        func flush() {
            view?.overlay.endEditing()
            saveNow()
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            view?.place()
            view?.moved()
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            view?.moved()
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with zoomed: UIView?, atScale scale: CGFloat) {
            view?.sharpen()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        /// Turns the page only when the whole page is showing; zoomed in, two fingers just move around.
        @objc func twoFingerPan(_ pan: UIPanGestureRecognizer) {
            guard pan.state == .ended, let view else { return }
            let canvas = view.canvas
            guard canvas.zoomScale <= canvas.minimumZoomScale * 1.03 else { return }
            let moved = pan.translation(in: view)
            guard abs(moved.x) > 60, abs(moved.x) > abs(moved.y) * 2 else { return }
            parent.onTurn(moved.x < 0 ? 1 : -1)
        }
    }
}

/// Follows one finger on the canvas without getting in PencilKit's way, for straightening a held stroke,
/// for the eraser to reach tapes and text boxes, and for swiping beside the page.
private final class NoteTouchTracker: UIGestureRecognizer {
    var onBegan: (CGPoint) -> Void = { _ in }
    var onMoved: (CGPoint) -> Void = { _ in }
    /// `true` when the finger was lifted, `false` when the touch was taken away (a second finger, a system gesture).
    var onEnded: (Bool) -> Void = { _ in }

    private weak var tracked: UITouch?

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // Two fingers scroll and zoom; that's not a stroke.
        if tracked != nil || (event.allTouches?.count ?? 1) > 1 {
            if tracked != nil {
                tracked = nil
                state = .cancelled
                onEnded(false)
            } else {
                state = .failed
            }
            return
        }
        guard let touch = touches.first else { return }
        tracked = touch
        state = .began
        onBegan(touch.location(in: view))
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let tracked, touches.contains(tracked) else { return }
        state = .changed
        onMoved(tracked.location(in: view))
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = tracked, touches.contains(touch) else { return }
        tracked = nil
        state = .ended
        onEnded(true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        guard let touch = tracked, touches.contains(touch) else { return }
        tracked = nil
        state = .cancelled
        onEnded(false)
    }

    override func reset() {
        tracked = nil
    }
}

/// The PencilKit canvas with the paper under it and the tapes / text boxes / selection over it.
/// The canvas scrolls and zooms; the paper and the overlay follow.
final class NotePageView: UIView, UIGestureRecognizerDelegate, NoteOverlayHost {
    let canvas = PKCanvasView()
    let overlay: NoteOverlayView
    var onSaveItems: (NoteItems) -> Void = { _ in }
    var onTurn: (Int) -> Void = { _ in }
    /// Undo / redo or the selection changed.
    var onHistory: () -> Void = {}

    private let paper: NotePaperView
    private var page: NotePage
    private var laidOut = CGSize.zero
    private var keyboardInset: CGFloat = 0

    /// What a held stroke is straightened into; nil for tools that don't draw lines.
    private struct LineInk {
        let type: PKInkingTool.InkType
        let color: UIColor
        let width: CGFloat
        /// What PencilKit draws with; wider than `width` when that's thinner than the ink allows.
        let toolWidth: CGFloat

        /// Thinner than PencilKit draws: the page draws the line live and stores it at `width`.
        var isThin: Bool { width < toolWidth - 0.01 }
    }

    private var lineInk: LineInk?
    private var erasesItems = false

    // One finger, as the tracker sees it. Points are in page points unless said otherwise.
    private var strokePoints: [CGPoint] = []
    private var strokeCount = 0
    private var travelled: CGFloat = 0
    private var holdAnchor = CGPoint.zero
    private var holdWork: DispatchWorkItem?
    /// The corners of the straightened stroke; the last one follows the finger.
    private var vertices: [CGPoint]?
    /// Where a swipe beside the page began and has got to, in the canvas's coordinates.
    private var marginSwipe: (start: CGPoint, now: CGPoint)?
    private var erasing = false

    /// The strokes, tapes and text boxes at one moment. Undo and redo put a whole state back;
    /// PencilKit's own undo isn't used, so the two can never disagree.
    private struct PageState {
        let drawing: PKDrawing
        let items: NoteItems
    }

    private var current = PageState(drawing: PKDrawing(), items: NoteItems())
    private var past: [PageState] = []
    private var future: [PageState] = []
    /// Between `beginChange` and `endChange`: everything in between is one step.
    private var inChange = false
    private var restoring = false
    /// A finger is down; what it does becomes one step when it lifts.
    private var touching = false
    /// When the page last scrolled or zoomed; a tap right after isn't an undo.
    private var lastMotion = Date.distantPast

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    init(page: NotePage, pdf: PDFPage?, image: UIImage?, items: NoteItems) {
        self.page = page
        paper = NotePaperView(page: page, pdf: pdf, image: image)
        overlay = NoteOverlayView(pageSize: page.size, items: items)
        super.init(frame: .zero)

        canvas.drawingPolicy = .anyInput
        canvas.isOpaque = false
        canvas.backgroundColor = .clear
        // The paper is always white, so the ink keeps its colors in dark mode.
        canvas.overrideUserInterfaceStyle = .light
        canvas.showsVerticalScrollIndicator = false
        canvas.showsHorizontalScrollIndicator = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.bouncesZoom = true
        addSubview(canvas)
        canvas.insertSubview(paper, at: 0)
        canvas.addSubview(overlay)

        overlay.host = self
        overlay.onEditingFrame = { [weak self] frame in self?.reveal(frame) }
        overlay.onSelection = { [weak self] _ in self?.onHistory() }

        let tracker = NoteTouchTracker()
        tracker.cancelsTouchesInView = false
        tracker.delaysTouchesBegan = false
        tracker.delaysTouchesEnded = false
        tracker.delegate = self
        tracker.onBegan = { [weak self] in self?.touchBegan($0) }
        tracker.onMoved = { [weak self] in self?.touchMoved($0) }
        tracker.onEnded = { [weak self] in self?.touchEnded(lifted: $0) }
        canvas.addGestureRecognizer(tracker)

        // Two fingers tap to undo, three to redo; not when the fingers were scrolling or pinching.
        for (touches, action) in [(2, #selector(tappedUndo)), (3, #selector(tappedRedo))] {
            let tap = UITapGestureRecognizer(target: self, action: action)
            tap.numberOfTouchesRequired = touches
            tap.delegate = self
            tap.require(toFail: canvas.panGestureRecognizer)
            if let pinch = canvas.pinchGestureRecognizer { tap.require(toFail: pinch) }
            addGestureRecognizer(tap)
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardChanged(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }

    func update(page: NotePage) {
        guard page != self.page else { return }
        self.page = page
        paper.page = page
        paper.setNeedsDisplay()
    }

    /// Hands the tool and its settings to the canvas and the overlay.
    func apply(tool: NoteTool, settings: NoteToolSettings) {
        if let pkTool = settings.pkTool(tool) { canvas.tool = pkTool }
        // Selecting, tape and text happen on the overlay; a finger mustn't also draw under it.
        canvas.drawingGestureRecognizer.isEnabled = tool == .pen || tool == .marker || tool == .eraser

        overlay.tapeWidth = settings.tape.width
        overlay.tapeColor = settings.tape.color
        overlay.textStyle = NoteTextStyle(
            size: settings.text.width, color: settings.text.color, bold: settings.textBold,
            background: settings.textBackground, font: settings.textFont
        )
        switch tool {
        case .select: overlay.mode = .select
        case .tape: overlay.mode = .tape
        case .text: overlay.mode = .text
        default: overlay.mode = .none
        }

        switch tool {
        case .pen:
            lineInk = LineInk(
                type: .pen, color: UIColor(notesHex: settings.pen.color), width: CGFloat(settings.pen.width),
                toolWidth: NoteToolSettings.toolWidth(settings.pen.width, .pen)
            )
        case .marker:
            lineInk = LineInk(
                type: .marker, color: UIColor(notesHex: settings.marker.color), width: CGFloat(settings.marker.width),
                toolWidth: NoteToolSettings.toolWidth(settings.marker.width, .marker)
            )
        default:
            lineInk = nil
        }
        erasesItems = tool == .eraser
    }

    // MARK: Changes and undo

    var drawing: PKDrawing {
        get { canvas.drawing }
        set { canvas.drawing = newValue }
    }

    var visibleCenter: CGPoint {
        let zoom = canvas.zoomScale
        let x = (canvas.contentOffset.x + bounds.width / 2) / zoom
        let y = (canvas.contentOffset.y + (bounds.height - keyboardInset) / 2) / zoom
        return CGPoint(x: min(max(x, 20), page.size.width - 20), y: min(max(y, 20), page.size.height - 20))
    }

    /// The page as loaded is where undo stops.
    func resetHistory() {
        current = PageState(drawing: canvas.drawing, items: overlay.items)
        past = []
        future = []
    }

    /// Marks where a change to the strokes or the tapes / text boxes starts.
    func beginChange() {
        inChange = true
    }

    /// Ends the change: if anything is different it becomes one step of undo.
    func endChange() {
        guard inChange else { return }
        inChange = false
        commit()
    }

    /// The tapes changed in a way that isn't a step of its own (peeling one back): saved, not undoable.
    func itemsChangedQuietly() {
        current = PageState(drawing: current.drawing, items: overlay.items)
        onSaveItems(overlay.items)
    }

    /// PencilKit changed the strokes. While a finger is down or a change is marked, that waits for its end.
    func drawingChanged() {
        guard !inChange, !restoring, !touching else { return }
        thinNewStrokes()
        commit()
    }

    /// Strokes just drawn with a width thinner than PencilKit's thinnest are stored at the width asked for,
    /// in the ink's real colour (PencilKit drew them invisible; the page showed the thin line meanwhile).
    private func thinNewStrokes() {
        guard let ink = lineInk, ink.isThin else { return }
        var strokes = canvas.drawing.strokes
        let known = current.drawing.strokes.count
        guard strokes.count > known else { return }
        let factor = ink.width / ink.toolWidth
        for index in known..<strokes.count where strokes[index].ink.inkType == ink.type {
            let path = strokes[index].path
            let points = path.map { point in
                PKStrokePoint(
                    location: point.location, timeOffset: point.timeOffset,
                    size: CGSize(width: point.size.width * factor, height: point.size.height * factor),
                    opacity: point.opacity, force: point.force, azimuth: point.azimuth, altitude: point.altitude
                )
            }
            strokes[index].path = PKStrokePath(controlPoints: points, creationDate: path.creationDate)
            strokes[index].ink = PKInk(ink.type, color: ink.color)
        }
        restoring = true
        canvas.drawing = PKDrawing(strokes: strokes)
        restoring = false
    }

    /// Makes what's on the page now a step, if it differs from the last one.
    private func commit() {
        let now = PageState(drawing: canvas.drawing, items: overlay.items)
        let itemsChanged = now.items != current.items
        guard itemsChanged || Self.differ(now.drawing, current.drawing) else { return }
        past.append(current)
        if past.count > 100 { past.removeFirst() }
        future = []
        current = now
        if itemsChanged { onSaveItems(now.items) }
        onHistory()
    }

    private static func differ(_ a: PKDrawing, _ b: PKDrawing) -> Bool {
        a.strokes.count != b.strokes.count || a.dataRepresentation() != b.dataRepresentation()
    }

    private func show(_ state: PageState) {
        restoring = true
        // A new drawing with the same strokes, not the old one itself: a drawing remembers where it came from,
        // and the canvas would merge the strokes that were undone back in with the next stroke drawn.
        canvas.drawing = PKDrawing(strokes: state.drawing.strokes)
        overlay.replace(state.items)
        restoring = false
        let itemsChanged = state.items != current.items
        current = PageState(drawing: canvas.drawing, items: state.items)
        if itemsChanged { onSaveItems(state.items) }
        onHistory()
    }

    func undo() {
        overlay.endEditing()
        overlay.clearSelection()
        commit()
        guard let previous = past.popLast() else { return }
        future.append(current)
        show(previous)
    }

    func redo() {
        overlay.endEditing()
        overlay.clearSelection()
        commit()
        guard let next = future.popLast() else { return }
        past.append(current)
        show(next)
    }

    /// The page scrolled or zoomed.
    func moved() {
        lastMotion = Date()
    }

    @objc private func tappedUndo() {
        guard Date().timeIntervalSince(lastMotion) > 0.4 else { return }
        undo()
    }

    @objc private func tappedRedo() {
        guard Date().timeIntervalSince(lastMotion) > 0.4 else { return }
        redo()
    }

    // MARK: Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        canvas.frame = bounds
        guard bounds.size != laidOut, bounds.width > 0, bounds.height > 0 else { return }
        let first = laidOut == .zero
        laidOut = bounds.size
        // The whole page fits, with a little room around it.
        let fit = min((bounds.width - 24) / page.size.width, (bounds.height - 24) / page.size.height)
        canvas.minimumZoomScale = fit
        canvas.maximumZoomScale = max(fit * 24, 12)
        if first {
            canvas.contentSize = page.size
            canvas.zoomScale = fit
        } else if canvas.zoomScale < fit {
            canvas.zoomScale = fit
        }
        place()
        sharpen()
    }

    /// Redraws the paper at the zoom it's shown at, so its lines and any PDF stay sharp.
    func sharpen() {
        paper.sharpen(zoom: canvas.zoomScale, screen: window?.screen.scale ?? traitCollection.displayScale)
    }

    /// Keeps the drawable area the page's size at this zoom, centers it, and puts the paper under it
    /// and the overlay over it.
    func place() {
        let zoom = canvas.zoomScale
        let size = CGSize(width: page.size.width * zoom, height: page.size.height * zoom)
        if abs(canvas.contentSize.width - size.width) > 0.5 || abs(canvas.contentSize.height - size.height) > 0.5 {
            canvas.contentSize = size
        }
        // Zoomed in, there's room past the page's edges, so any part of it (a corner too) can sit mid-screen.
        // The room grows in as the zoom leaves the whole-page fit, so nothing jumps.
        let zoomedIn = min(max((zoom / max(canvas.minimumZoomScale, 0.01) - 1) / 0.5, 0), 1)
        let horizontal = max((bounds.width - size.width) / 2, bounds.width * 0.45 * zoomedIn, 0)
        let vertical = max((bounds.height - size.height) / 2, bounds.height * 0.45 * zoomedIn, 0)
        canvas.contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: max(vertical, keyboardInset), right: horizontal)
        paper.transform = CGAffineTransform(scaleX: zoom, y: zoom)
        paper.layer.position = .zero
        overlay.frame = CGRect(origin: .zero, size: size)
        overlay.zoom = zoom
        canvas.bringSubviewToFront(overlay)
    }

    // MARK: Keyboard

    @objc private func keyboardChanged(_ notification: Notification) {
        guard let window, let end = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
        let mine = convert(bounds, to: window)
        keyboardInset = max(0, mine.maxY - end.minY)
        place()
        if let frame = overlay.editingFrame { reveal(frame) }
    }

    /// Scrolls so the text box being typed in is above the keyboard.
    private func reveal(_ frame: CGRect) {
        guard keyboardInset > 0 else { return }
        canvas.scrollRectToVisible(frame.insetBy(dx: 0, dy: -24), animated: true)
    }

    // MARK: One finger

    private func pagePoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x / canvas.zoomScale, y: point.y / canvas.zoomScale)
    }

    /// Drops the stroke PencilKit has in progress.
    private func cancelInk() {
        let recognizer = canvas.drawingGestureRecognizer
        guard recognizer.isEnabled else { return }
        recognizer.isEnabled = false
        recognizer.isEnabled = true
    }

    private func touchBegan(_ point: CGPoint) {
        touching = true
        let start = pagePoint(point)
        // Beside the page: nothing to write on, so a sideways swipe turns the page.
        guard CGRect(origin: .zero, size: page.size).contains(start) else {
            marginSwipe = (point, point)
            cancelInk()
            return
        }
        if erasesItems {
            erasing = true
            overlay.erase(at: start)
        }
        guard lineInk != nil else { return }
        strokePoints = [start]
        strokeCount = canvas.drawing.strokes.count
        travelled = 0
        holdAnchor = point
        vertices = nil
        scheduleHold()
    }

    private func touchMoved(_ point: CGPoint) {
        if marginSwipe != nil {
            marginSwipe?.now = point
            return
        }
        let current = pagePoint(point)
        if erasing { overlay.erase(at: current) }
        guard let ink = lineInk, let last = strokePoints.last else { return }
        if var corners = vertices {
            corners[corners.count - 1] = current
            vertices = corners
            overlay.showPreview(corners, width: ink.width, color: previewColor(ink))
            return
        }
        travelled += hypot(current.x - last.x, current.y - last.y)
        strokePoints.append(current)
        // A line thinner than PencilKit draws: shown at its own width as it's drawn.
        if ink.isThin { overlay.showPreview(strokePoints, width: ink.width, color: previewColor(ink)) }
        if hypot(point.x - holdAnchor.x, point.y - holdAnchor.y) > 6 {
            // Still moving: the hold starts over from here.
            holdAnchor = point
            scheduleHold()
        }
    }

    private func touchEnded(lifted: Bool) {
        touching = false
        // Whatever the finger did (a stroke, erasing strokes and tapes) is one step.
        let straightened = vertices != nil
        defer {
            if !inChange {
                // A straightened line is already the width asked for.
                if !straightened { thinNewStrokes() }
                commit()
            }
        }
        holdWork?.cancel()
        holdWork = nil
        if let swipe = marginSwipe {
            marginSwipe = nil
            let dx = swipe.now.x - swipe.start.x
            let dy = swipe.now.y - swipe.start.y
            if lifted, abs(dx) > 50, abs(dx) > abs(dy) * 2 { onTurn(dx < 0 ? 1 : -1) }
            return
        }
        erasing = false
        strokePoints = []
        if lineInk?.isThin == true, vertices == nil { overlay.hidePreview() }
        guard let corners = vertices else { return }
        vertices = nil
        overlay.hidePreview()
        guard lifted, let ink = lineInk else { return }
        commitLine(through: corners, ink: ink)
    }

    /// Keeping the finger still for half a second at the end of a stroke straightens it:
    /// one line, or straight lines between its corners if it bends.
    private func scheduleHold() {
        holdWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.beginStraightening() }
        holdWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func beginStraightening() {
        guard let ink = lineInk, vertices == nil, travelled > 12, let first = strokePoints.first, let last = strokePoints.last else { return }
        let xs = strokePoints.map(\.x)
        let ys = strokePoints.map(\.y)
        let diagonal = hypot((xs.max() ?? 0) - (xs.min() ?? 0), (ys.max() ?? 0) - (ys.min() ?? 0))
        var corners = Self.simplify(strokePoints, tolerance: max(5, diagonal * 0.04))
        // Too many corners is a curve, not a bent line: that becomes one straight line.
        if corners.count < 2 || corners.count > 10 { corners = [first, last] }
        vertices = corners
        cancelInk()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        overlay.showPreview(corners, width: ink.width, color: previewColor(ink))
    }

    /// Ramer–Douglas–Peucker: the points that stay when everything within `tolerance` of a straight run is dropped.
    private static func simplify(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        let dx = last.x - first.x
        let dy = last.y - first.y
        let length = hypot(dx, dy)
        var farthest = 0
        var distance: CGFloat = 0
        for index in 1..<(points.count - 1) {
            let point = points[index]
            let away = length > 0
                ? abs((point.x - first.x) * dy - (point.y - first.y) * dx) / length
                : hypot(point.x - first.x, point.y - first.y)
            if away > distance {
                distance = away
                farthest = index
            }
        }
        guard distance > tolerance else { return [first, last] }
        let head = simplify(Array(points[...farthest]), tolerance: tolerance)
        let tail = simplify(Array(points[farthest...]), tolerance: tolerance)
        return Array(head.dropLast()) + tail
    }

    private func previewColor(_ ink: LineInk) -> UIColor {
        ink.type == .marker ? ink.color.withAlphaComponent(0.45) : ink.color
    }

    private func commitLine(through corners: [CGPoint], ink: LineInk) {
        guard corners.count > 1 else { return }
        let size = CGSize(width: ink.width, height: ink.width)
        var points: [PKStrokePoint] = []
        func add(_ location: CGPoint) {
            points.append(PKStrokePoint(
                location: location, timeOffset: TimeInterval(points.count) * 0.01,
                size: size, opacity: 1, force: 1, azimuth: 0, altitude: .pi / 2
            ))
        }
        for index in 0..<(corners.count - 1) {
            let start = corners[index]
            let end = corners[index + 1]
            let length = hypot(end.x - start.x, end.y - start.y)
            let steps = max(1, Int(length / 4))
            // Three points on a corner keep it sharp; the curve through them can't round it off.
            add(start)
            add(start)
            for step in 0..<steps {
                let t = CGFloat(step) / CGFloat(steps)
                add(CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
            }
        }
        if let end = corners.last {
            add(end)
            add(end)
            add(end)
        }
        guard points.count > 3 else { return }
        let stroke = PKStroke(ink: PKInk(ink.type, color: ink.color), path: PKStrokePath(controlPoints: points, creationDate: Date()))
        // If the dropped stroke was kept after all, the line takes its place.
        var strokes = canvas.drawing.strokes
        if strokes.count > strokeCount { strokes = Array(strokes.prefix(strokeCount)) }
        strokes.append(stroke)
        restoring = true
        canvas.drawing = PKDrawing(strokes: strokes)
        restoring = false
    }
}

/// The paper. It's drawn on the main thread only (PDF pages can't be drawn from several threads at once),
/// stretched while pinching and redrawn sharp when the zoom settles.
final class NotePaperView: UIView {
    var page: NotePage
    private let pdf: PDFPage?
    private let image: UIImage?

    init(page: NotePage, pdf: PDFPage?, image: UIImage?) {
        self.page = page
        self.pdf = pdf
        self.image = image
        super.init(frame: CGRect(origin: .zero, size: page.size))
        backgroundColor = .white
        isOpaque = true
        isUserInteractionEnabled = false
        layer.anchorPoint = .zero
        layer.position = .zero
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 6
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowPath = UIBezierPath(rect: bounds).cgPath
    }

    /// As many pixels as the zoom needs, up to a size that keeps the bitmap's memory in hand.
    func sharpen(zoom: CGFloat, screen: CGFloat) {
        let limit = 3600 / max(page.size.width, page.size.height)
        let scale = max(1, min(screen * zoom, limit))
        guard abs(scale - contentScaleFactor) > 0.01 else { return }
        contentScaleFactor = scale
        setNeedsDisplay()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        NotePaperRenderer.draw(page, pdf: pdf, image: image, in: context)
    }
}
