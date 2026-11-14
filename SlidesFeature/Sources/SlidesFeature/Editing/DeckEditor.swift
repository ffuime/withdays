import Foundation
import SwiftData
import SwiftUI
import UIKit

/// What's being typed in: a text box, or one cell of a table.
enum EditTarget: Equatable {
    case text(UUID)
    case cell(UUID, row: Int, column: Int)

    var elementID: UUID {
        switch self {
        case .text(let id): id
        case .cell(let id, _, _): id
        }
    }
}

/// One deck open in the editor: its slides as values, the current slide and selection, undo history,
/// and saving back to SwiftData (debounced, and right away when leaving).
@MainActor
@Observable
final class DeckEditor {
    struct Snapshot: Equatable {
        var slides: [SlideContent]
        var index: Int
    }

    let deck: Deck
    let deckID: UUID
    private let context: ModelContext

    private(set) var slides: [SlideContent]
    var currentIndex: Int {
        didSet {
            let clamped = min(max(currentIndex, 0), max(slides.count - 1, 0))
            if clamped != currentIndex { currentIndex = clamped }
            if oldValue != currentIndex {
                selection = nil
                editing = nil
                multiSelecting = false
            }
        }
    }

    var selection: UUID? {
        didSet {
            if selection == nil || selection != editing?.elementID { editing = nil }
            if selection != nil { multiSelecting = false }
        }
    }

    var editing: EditTarget?
    /// 複数選択: several elements chosen at once, changed together.
    var multiSelecting = false {
        didSet { if !multiSelecting { multiSelection = [] } }
    }
    var multiSelection: Set<UUID> = []
    /// The lines a dragged element is lined up with, while it's dragged.
    var snapLines: [SnapLine] = []
    /// Which way the last change of slide went, for the slide's motion.
    var movingForward = true

    private var history = EditHistory<Snapshot>(limit: 100)
    private var interactionStart: Snapshot?
    /// What each page held when last saved, to write only what changed.
    private var savedData: [UUID: Data] = [:]
    private var savedOrder: [UUID] = []
    private var saveTask: Task<Void, Never>?
    var saveError: String?

    init(deck: Deck, context: ModelContext, start: Int = 0) {
        self.deck = deck
        deckID = deck.id
        self.context = context
        let pages = deck.sortedPages
        var slides = pages.compactMap { SlideContent.decode($0.data) }
        if slides.isEmpty { slides = [SlideLayout.titleSubtitle.make()] }
        self.slides = slides
        currentIndex = min(max(start, 0), slides.count - 1)
        for page in pages { savedData[page.id] = page.data }
        savedOrder = pages.map(\.id)
    }

    // MARK: Reading

    var current: SlideContent { slides[min(currentIndex, slides.count - 1)] }

    var selectedElement: SlideElement? {
        guard let selection else { return nil }
        return current.elements.first { $0.id == selection }
    }

    var canUndo: Bool { history.canUndo }
    var canRedo: Bool { history.canRedo }

    private var snapshot: Snapshot { Snapshot(slides: slides, index: currentIndex) }

    // MARK: Changing

    /// One step of undo. Changes with the same `coalesce` key in quick succession make one step (typing, sliders).
    func change(coalesce key: String? = nil, _ body: (inout [SlideContent]) -> Void) {
        let before = snapshot
        var changed = slides
        body(&changed)
        guard changed != slides else { return }
        if interactionStart == nil { history.record(before, coalesce: key) }
        slides = changed
        scheduleSave()
    }

    func changeCurrentSlide(coalesce key: String? = nil, _ body: (inout SlideContent) -> Void) {
        let index = currentIndex
        change(coalesce: key) { slides in
            guard slides.indices.contains(index) else { return }
            body(&slides[index])
        }
    }

    func changeElement(_ id: UUID, coalesce key: String? = nil, _ body: (inout SlideElement) -> Void) {
        changeCurrentSlide(coalesce: key) { slide in
            guard let index = slide.index(of: id) else { return }
            body(&slide.elements[index])
        }
    }

    /// A drag, a pinch or a rotation: everything until `endInteraction` is one step.
    func beginInteraction() {
        guard interactionStart == nil else { return }
        interactionStart = snapshot
    }

    func endInteraction() {
        guard let start = interactionStart else { return }
        interactionStart = nil
        if start.slides != slides {
            history.record(start)
            history.breakCoalescing()
        }
    }

    func undo() {
        endInteraction()
        guard let previous = history.undo(from: snapshot) else { return }
        restore(previous)
    }

    func redo() {
        endInteraction()
        guard let next = history.redo(from: snapshot) else { return }
        restore(next)
    }

    private func restore(_ state: Snapshot) {
        editing = nil
        selection = nil
        multiSelecting = false
        slides = state.slides
        currentIndex = min(state.index, slides.count - 1)
        scheduleSave()
    }

    // MARK: Slides

    /// Goes to a slide with the slide motion. The direction is set first, so the slide leaving moves the right way too.
    func show(_ target: Int) {
        guard slides.indices.contains(target), target != currentIndex else { return }
        movingForward = target > currentIndex
        DispatchQueue.main.async {
            withAnimation(.snappy(duration: 0.3)) { self.currentIndex = target }
        }
    }

    /// New slides go after the current one.
    func addSlide(_ layout: SlideLayout) {
        insertSlide(layout.make(), after: currentIndex)
    }

    func addCopyOfCurrent() {
        insertSlide(current.withNewIDs(), after: currentIndex)
    }

    func addCopyOfLast() {
        guard let last = slides.last else { return }
        insertSlide(last.withNewIDs(), after: currentIndex)
    }

    func duplicateSlide(at index: Int) {
        guard slides.indices.contains(index) else { return }
        insertSlide(slides[index].withNewIDs(), after: index)
    }

    func duplicateSlideToEnd(at index: Int) {
        guard slides.indices.contains(index) else { return }
        insertSlide(slides[index].withNewIDs(), after: slides.count - 1)
    }

    func copySlide(at index: Int) {
        guard slides.indices.contains(index) else { return }
        SlideClipboard.slide = slides[index]
        SlideClipboard.deck = deckID
    }

    var canPaste: Bool { SlideClipboard.slide != nil }

    /// Pastes the copied slide after `index`, bringing its images over from the deck it came from.
    func pasteSlide(after index: Int) {
        guard let slide = SlideClipboard.slide else { return }
        if let source = SlideClipboard.deck { SlidesFiles.copyAssets(slide.assetNames, from: source, to: deckID) }
        insertSlide(slide.withNewIDs(), after: index)
    }

    private func insertSlide(_ slide: SlideContent, after index: Int) {
        let position = min(index + 1, slides.count)
        change { $0.insert(slide, at: position) }
        currentIndex = position
    }

    /// A deck always keeps one slide.
    var canDeleteSlide: Bool { slides.count > 1 }

    func deleteSlide(at index: Int) {
        guard canDeleteSlide, slides.indices.contains(index) else { return }
        let showing = currentIndex
        change { $0.remove(at: index) }
        currentIndex = index < showing ? showing - 1 : min(showing, slides.count - 1)
    }

    /// Moves a slide so it sits before the slide now at `target` (or at the end when `target` is the count).
    func moveSlide(_ id: UUID, before target: Int) {
        guard let from = slides.firstIndex(where: { $0.id == id }) else { return }
        let showingID = current.id
        change { slides in
            let slide = slides.remove(at: from)
            let destination = min(target > from ? target - 1 : target, slides.count)
            slides.insert(slide, at: destination)
        }
        if let index = slides.firstIndex(where: { $0.id == showingID }) { currentIndex = index }
    }

    // MARK: Elements

    /// Adds an element in the middle of the slide and selects it.
    func insert(_ element: SlideElement, at center: CGPoint = CGPoint(x: 960, y: 540)) {
        var placed = element
        placed.move(by: Double(center.x - placed.frame.center.x), Double(center.y - placed.frame.center.y))
        changeCurrentSlide { $0.elements.append(placed) }
        selection = placed.id
    }

    // MARK: Copy and paste

    func copyElement(_ id: UUID) {
        guard let element = current.elements.first(where: { $0.id == id }) else { return }
        ElementClipboard.copy(element, deck: deckID)
    }

    /// Pastes what's on the pasteboard: a Slides element (where it was, nudged if that spot is taken),
    /// an image (SVG drawn first), or text as a new text box.
    func paste() async throws {
        switch ElementClipboard.read() {
        case .element(let payload):
            SlidesFiles.copyAssets(payload.element.assetNames, from: payload.deck, to: deckID)
            var element = payload.element
            element.id = UUID()
            while current.elements.contains(where: { $0.frame == element.frame }) {
                element.move(by: 40, 40)
            }
            changeCurrentSlide { $0.elements.append(element) }
            selection = element.id
            for asset in element.assetNames {
                ImageTextIndexer.shared.index(asset, deck: deckID, context: context)
            }
        case .image(let data):
            try insertImage(try await ImageLoading.usableData(data))
        case .text(let string):
            var text = RichText.plain(string, size: 44)
            text.runs[0].text = string
            let lines = max(1, string.components(separatedBy: "\n").count)
            insert(SlideElement(
                frame: SlideRect(x: 0, y: 0, width: 1200, height: Double(min(lines, 12)) * 66 + 20),
                content: .text(TextBoxElement(text: text))
            ))
        case nil:
            break
        }
    }

    /// The current slide's background on every slide (one step).
    func applyBackgroundToAll() {
        let background = current.background
        change { slides in
            for index in slides.indices { slides[index].background = background }
        }
    }

    func duplicateElement(_ id: UUID) {
        guard let element = current.elements.first(where: { $0.id == id }) else { return }
        var copy = element
        copy.id = UUID()
        copy.move(by: 40, 40)
        changeCurrentSlide { slide in
            guard let index = slide.index(of: id) else { return }
            slide.elements.insert(copy, at: index + 1)
            let copies = slide.animations.filter { $0.elementID == id }.map { animation -> ElementAnimation in
                var moved = animation
                moved.id = UUID()
                moved.elementID = copy.id
                return moved
            }
            slide.animations.append(contentsOf: copies)
        }
        selection = copy.id
    }

    func deleteElement(_ id: UUID) {
        if selection == id { selection = nil }
        changeCurrentSlide { slide in
            slide.elements.removeAll { $0.id == id }
            slide.animations.removeAll { $0.elementID == id }
        }
    }

    enum Order {
        case forward, backward, front, back
    }

    func reorder(_ id: UUID, _ order: Order) {
        changeCurrentSlide { slide in
            guard let index = slide.index(of: id) else { return }
            let element = slide.elements.remove(at: index)
            let target: Int = switch order {
            case .forward: min(index + 1, slide.elements.count)
            case .backward: max(index - 1, 0)
            case .front: slide.elements.count
            case .back: 0
            }
            slide.elements.insert(element, at: target)
        }
    }

    /// Typing: a burst of changes to one box is one step.
    func setText(_ id: UUID, _ text: RichText) {
        changeElement(id, coalesce: "text-\(id)") { element in
            if case .text(var box) = element.content {
                box.text = text
                element.content = .text(box)
            }
        }
    }

    func setCellText(_ id: UUID, row: Int, column: Int, _ text: RichText) {
        changeElement(id, coalesce: "cell-\(id)-\(row)-\(column)") { element in
            guard case .table(var table) = element.content, table.cells.indices.contains(row),
                  table.cells[row].indices.contains(column) else { return }
            table.cells[row][column].text = text
            element.content = .table(table)
        }
    }

    /// The text being edited, or nil.
    func editingText() -> RichText? {
        guard let editing, let element = current.elements.first(where: { $0.id == editing.elementID }) else { return nil }
        switch (editing, element.content) {
        case (.text, .text(let box)): return box.text
        case (.cell(_, let row, let column), .table(let table)):
            guard table.cells.indices.contains(row), table.cells[row].indices.contains(column) else { return nil }
            return table.cells[row][column].text
        default: return nil
        }
    }

    func setEditingText(_ text: RichText) {
        switch editing {
        case .text(let id): setText(id, text)
        case .cell(let id, let row, let column): setCellText(id, row: row, column: column, text)
        case nil: break
        }
    }

    /// Changes the formatting of a whole text box or table (every cell).
    func formatText(_ id: UUID, key: String, _ body: (inout RichText) -> Void) {
        changeElement(id, coalesce: "format-\(id)-\(key)") { element in
            switch element.content {
            case .text(var box):
                body(&box.text)
                element.content = .text(box)
            case .table(var table):
                for row in table.cells.indices {
                    for column in table.cells[row].indices { body(&table.cells[row][column].text) }
                }
                element.content = .table(table)
            default:
                break
            }
        }
    }

    /// Saves an image to the deck and puts it on the slide, fitted inside 1280×720; its text is read in the background.
    func insertImage(_ data: Data, at center: CGPoint = CGPoint(x: 960, y: 540)) throws {
        let stored = try SlidesFiles.storeImage(data, deck: deckID)
        let scale = min(1280 / stored.size.width, 720 / stored.size.height, 1)
        let size = CGSize(width: stored.size.width * scale, height: stored.size.height * scale)
        insert(SlideElement(
            frame: SlideRect(x: 0, y: 0, width: Double(size.width), height: Double(size.height)),
            content: .image(ImageElement(asset: stored.name, mode: .stretch))
        ), at: center)
        ImageTextIndexer.shared.index(stored.name, deck: deckID, context: context)
    }

    /// Saves an image for a fill or a background; returns its file name.
    func storeImage(_ data: Data) throws -> String {
        let stored = try SlidesFiles.storeImage(data, deck: deckID)
        ImageTextIndexer.shared.index(stored.name, deck: deckID, context: context)
        return stored.name
    }

    // MARK: Animations

    func animations(of id: UUID) -> [ElementAnimation] {
        current.animations.filter { $0.elementID == id }
    }

    /// An element has at most one 登場 and one 退場, its 登場 first.
    func addAnimation(to id: UUID, category: AnimationCategory) {
        changeCurrentSlide { slide in
            guard !slide.animations.contains(where: { $0.elementID == id && $0.category == category }) else { return }
            let animation = ElementAnimation(elementID: id, category: category)
            if category == .entrance, let exit = slide.animations.firstIndex(where: { $0.elementID == id && $0.category == .exit }) {
                slide.animations.insert(animation, at: exit)
            } else {
                slide.animations.append(animation)
            }
        }
    }

    func updateAnimation(_ animation: ElementAnimation) {
        changeCurrentSlide(coalesce: "animation-\(animation.id)") { slide in
            guard let index = slide.animations.firstIndex(where: { $0.id == animation.id }) else { return }
            slide.animations[index] = animation
        }
    }

    func deleteAnimation(_ id: UUID) {
        changeCurrentSlide { $0.animations.removeAll { $0.id == id } }
    }

    func moveAnimations(from source: IndexSet, to destination: Int) {
        changeCurrentSlide { $0.animations.move(fromOffsets: source, toOffset: destination) }
    }

    // MARK: 複数選択

    /// Starts choosing several elements, with the selected one and `id` already chosen.
    func beginMultiSelect(with id: UUID?) {
        var chosen: Set<UUID> = []
        if let selection { chosen.insert(selection) }
        if let id { chosen.insert(id) }
        editing = nil
        selection = nil
        multiSelection = chosen
        multiSelecting = true
    }

    func endMultiSelect() {
        multiSelecting = false
    }

    /// The chosen elements, back to front.
    var chosenElements: [SlideElement] {
        current.elements.filter { multiSelection.contains($0.id) }
    }

    func changeElements(_ ids: Set<UUID>, coalesce key: String? = nil, _ body: (inout SlideElement) -> Void) {
        changeCurrentSlide(coalesce: key) { slide in
            for index in slide.elements.indices where ids.contains(slide.elements[index].id) {
                body(&slide.elements[index])
            }
        }
    }

    /// The text of every chosen text box and table (all cells).
    func formatTexts(_ ids: Set<UUID>, key: String, _ body: (inout RichText) -> Void) {
        changeElements(ids, coalesce: "group-\(key)") { element in
            switch element.content {
            case .text(var box):
                body(&box.text)
                element.content = .text(box)
            case .table(var table):
                for row in table.cells.indices {
                    for column in table.cells[row].indices { body(&table.cells[row][column].text) }
                }
                element.content = .table(table)
            default:
                break
            }
        }
    }

    func deleteElements(_ ids: Set<UUID>) {
        changeCurrentSlide { slide in
            slide.elements.removeAll { ids.contains($0.id) }
            slide.animations.removeAll { ids.contains($0.elementID) }
        }
        multiSelecting = false
    }

    /// Copies go in front, a little apart, and become the chosen ones.
    func duplicateElements(_ ids: Set<UUID>) {
        var copies: Set<UUID> = []
        changeCurrentSlide { slide in
            let originals = slide.elements.filter { ids.contains($0.id) }
            var newIDs: [UUID: UUID] = [:]
            for element in originals {
                var copy = element
                copy.id = UUID()
                copy.move(by: 40, 40)
                newIDs[element.id] = copy.id
                copies.insert(copy.id)
                slide.elements.append(copy)
            }
            let animations = slide.animations.compactMap { animation -> ElementAnimation? in
                guard let id = newIDs[animation.elementID] else { return nil }
                var moved = animation
                moved.id = UUID()
                moved.elementID = id
                return moved
            }
            slide.animations.append(contentsOf: animations)
        }
        multiSelection = copies
    }

    /// 最前面 / 最背面 for the chosen elements, keeping their order among themselves.
    func reorderElements(_ ids: Set<UUID>, toFront: Bool) {
        changeCurrentSlide { slide in
            let chosen = slide.elements.filter { ids.contains($0.id) }
            let others = slide.elements.filter { !ids.contains($0.id) }
            slide.elements = toFront ? others + chosen : chosen + others
        }
    }

    enum GroupAlignment: CaseIterable {
        case left, centerX, right, top, centerY, bottom

        var label: String {
            switch self {
            case .left: "左揃え"
            case .centerX: "左右中央"
            case .right: "右揃え"
            case .top: "上揃え"
            case .centerY: "上下中央"
            case .bottom: "下揃え"
            }
        }

        var icon: String {
            switch self {
            case .left: "align.horizontal.left"
            case .centerX: "align.horizontal.center"
            case .right: "align.horizontal.right"
            case .top: "align.vertical.top"
            case .centerY: "align.vertical.center"
            case .bottom: "align.vertical.bottom"
            }
        }
    }

    /// Lines the chosen elements up with the box around them all (one element: with the slide).
    func align(_ ids: Set<UUID>, _ alignment: GroupAlignment) {
        let chosen = current.elements.filter { ids.contains($0.id) }
        guard !chosen.isEmpty else { return }
        let area = chosen.count == 1
            ? CGRect(x: 0, y: 0, width: 1920, height: 1080)
            : chosen.map(Snapper.bounds(of:)).reduce(CGRect.null) { $0.union($1) }
        changeElements(ids) { element in
            let bounds = Snapper.bounds(of: element)
            switch alignment {
            case .left: element.move(by: Double(area.minX - bounds.minX), 0)
            case .centerX: element.move(by: Double(area.midX - bounds.midX), 0)
            case .right: element.move(by: Double(area.maxX - bounds.maxX), 0)
            case .top: element.move(by: 0, Double(area.minY - bounds.minY))
            case .centerY: element.move(by: 0, Double(area.midY - bounds.midY))
            case .bottom: element.move(by: 0, Double(area.maxY - bounds.maxY))
            }
        }
    }

    /// Gives the chosen elements the same 登場 or 退場, played at the same time: the first starts as `template`
    /// says, the rest with it. Their earlier animation of that kind is replaced.
    func applyGroupAnimation(_ template: ElementAnimation, to ids: Set<UUID>) {
        changeCurrentSlide { slide in
            let order = slide.elements.map(\.id).filter { ids.contains($0) }
            guard !order.isEmpty else { return }
            slide.animations.removeAll { ids.contains($0.elementID) && $0.category == template.category }
            let block = order.enumerated().map { index, id -> ElementAnimation in
                var animation = template
                animation.id = UUID()
                animation.elementID = id
                if index > 0 { animation.start = .withPrevious }
                return animation
            }
            // 登場 comes before any 退場 of the same elements.
            if template.category == .entrance,
               let exit = slide.animations.firstIndex(where: { ids.contains($0.elementID) && $0.category == .exit }) {
                slide.animations.insert(contentsOf: block, at: exit)
            } else {
                slide.animations.append(contentsOf: block)
            }
        }
    }

    func removeAnimations(of ids: Set<UUID>) {
        changeCurrentSlide { $0.animations.removeAll { ids.contains($0.elementID) } }
    }

    // MARK: Deck settings (not part of undo)

    func toggleGuides() {
        deck.showsGuides.toggle()
        try? context.save()
    }

    func toggleFavorite() {
        deck.isFavorite.toggle()
        try? context.save()
    }

    // MARK: Saving

    /// Saves half a second after the last change.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    /// Writes the pages that changed, in order, and drops the removed ones.
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        let order = slides.map(\.id)
        var changed = order != savedOrder
        var pages = Dictionary(deck.pages.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (index, slide) in slides.enumerated() {
            let data = slide.encoded()
            if let page = pages.removeValue(forKey: slide.id) {
                if page.order != index { page.order = index }
                if savedData[slide.id] != data {
                    page.update(slide, encoded: data)
                    changed = true
                }
            } else {
                let page = SlidePage(slide, order: index)
                page.deck = deck
                context.insert(page)
                changed = true
            }
            savedData[slide.id] = data
        }
        for page in pages.values {
            context.delete(page)
            savedData[page.id] = nil
            changed = true
        }
        savedOrder = order
        guard changed else { return }
        deck.updatedAt = .now
        do {
            try context.save()
            saveError = nil
        } catch {
            saveError = "保存できませんでした。空き容量を確認してください。"
        }
    }
}
