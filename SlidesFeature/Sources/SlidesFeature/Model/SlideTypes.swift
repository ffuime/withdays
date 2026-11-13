import CoreGraphics
import Foundation
import UIKit

// The slide's content as value types. A slide is stored as one JSON blob (see `SlidePage`);
// everything is laid out in a fixed 1920×1080 space and scaled to the view.

/// A color with alpha, 0...1 per channel. Slide content keeps its colors in light and dark mode.
struct RGBA: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1

    init(r: Double, g: Double, b: Double, a: Double = 1) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// 0xRRGGBB.
    init(hex: Int, alpha: Double = 1) {
        r = Double((hex >> 16) & 0xFF) / 255
        g = Double((hex >> 8) & 0xFF) / 255
        b = Double(hex & 0xFF) / 255
        a = alpha
    }

    init(_ color: UIColor) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        r = Double(min(max(red, 0), 1))
        g = Double(min(max(green, 0), 1))
        b = Double(min(max(blue, 0), 1))
        a = Double(min(max(alpha, 0), 1))
    }

    var uiColor: UIColor { UIColor(red: r, green: g, blue: b, alpha: a) }
    var cgColor: CGColor { uiColor.cgColor }

    /// "RRGGBB", for PowerPoint.
    var hexString: String {
        let part: (Double) -> Int = { Int((min(max($0, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", part(r), part(g), part(b))
    }

    func withAlpha(_ alpha: Double) -> RGBA {
        var copy = self
        copy.a = alpha
        return copy
    }

    static let black = RGBA(hex: 0x000000)
    static let white = RGBA(hex: 0xFFFFFF)
    static let text = RGBA(hex: 0x1C1C1E)
    static let gray = RGBA(hex: 0x6B7280)
    static let brand = RGBA(hex: 0x02B9B9)
}

struct SlideRect: Codable, Hashable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    init(_ rect: CGRect) {
        self.init(x: Double(rect.minX), y: Double(rect.minY), width: Double(rect.width), height: Double(rect.height))
    }

    var cg: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var center: CGPoint { CGPoint(x: x + width / 2, y: y + height / 2) }
}

struct SlidePoint: Codable, Hashable {
    var x: Double
    var y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    init(_ point: CGPoint) {
        self.init(x: Double(point.x), y: Double(point.y))
    }

    var cg: CGPoint { CGPoint(x: x, y: y) }
}

// MARK: Fills and strokes

struct GradientStop: Codable, Hashable, Identifiable {
    var id = UUID()
    var color: RGBA
    /// 0...1 along the gradient.
    var location: Double
}

/// A linear gradient. 0° runs left to right and the angle grows clockwise (as in PowerPoint).
struct LinearGradientFill: Codable, Hashable {
    var stops: [GradientStop]
    var angle: Double

    var sortedStops: [GradientStop] { stops.sorted { $0.location < $1.location } }

    static let `default` = LinearGradientFill(
        stops: [GradientStop(color: RGBA(hex: 0x02B9B9), location: 0), GradientStop(color: RGBA(hex: 0x2563EB), location: 1)],
        angle: 135
    )
}

enum ImageFitMode: String, Codable, CaseIterable {
    case stretch, fit, fill

    var label: String {
        switch self {
        case .stretch: "枠に合わせて伸ばす"
        case .fit: "全体を表示"
        case .fill: "枠に合わせて切り抜く"
        }
    }
}

/// An image file in the deck's asset folder.
struct ImageRef: Codable, Hashable {
    var asset: String
    var mode: ImageFitMode = .fill
}

enum Fill: Codable, Hashable {
    case none
    case solid(RGBA)
    case gradient(LinearGradientFill)
    case image(ImageRef)

    var kindLabel: String {
        switch self {
        case .none: "なし"
        case .solid: "単色"
        case .gradient: "グラデーション"
        case .image: "画像"
        }
    }
}

enum DashStyle: String, Codable, CaseIterable {
    case solid, dash, dot

    var label: String {
        switch self {
        case .solid: "実線"
        case .dash: "破線"
        case .dot: "点線"
        }
    }

    func pattern(width: Double) -> [CGFloat] {
        switch self {
        case .solid: []
        case .dash: [CGFloat(width * 3), CGFloat(width * 2)]
        case .dot: [CGFloat(width), CGFloat(width * 1.6)]
        }
    }
}

struct Stroke: Codable, Hashable {
    var color: RGBA
    var width: Double
    var dash: DashStyle = .solid
}

struct ShadowStyle: Codable, Hashable {
    var color: RGBA = RGBA(hex: 0x000000, alpha: 0.35)
    var blur: Double = 24
    var x: Double = 0
    var y: Double = 12
}

// MARK: Text

enum HAlign: String, Codable, CaseIterable {
    case left, center, right, justified

    var label: String {
        switch self {
        case .left: "左"
        case .center: "中央"
        case .right: "右"
        case .justified: "両端"
        }
    }

    var icon: String {
        switch self {
        case .left: "text.alignleft"
        case .center: "text.aligncenter"
        case .right: "text.alignright"
        case .justified: "text.justify"
        }
    }
}

enum VAlign: String, Codable, CaseIterable {
    case top, middle, bottom

    var label: String {
        switch self {
        case .top: "上"
        case .middle: "中"
        case .bottom: "下"
        }
    }

    var icon: String {
        switch self {
        case .top: "arrow.up.to.line"
        case .middle: "arrow.up.and.down"
        case .bottom: "arrow.down.to.line"
        }
    }
}

/// A run of text with one formatting. `font` is a PostScript name, a family name, or "System".
/// New text is set in ヒラギノ角ゴシック.
struct TextRun: Codable, Hashable {
    static let defaultFont = "HiraginoSans-W3"

    var text: String
    var font: String = TextRun.defaultFont
    var size: Double = 44
    var bold = false
    var italic = false
    var underline = false
    var strike = false
    var color: RGBA = .text

    /// The same formatting, with other text.
    func with(_ text: String) -> TextRun {
        var copy = self
        copy.text = text
        return copy
    }

    var sameFormat: TextRun { with("") }
}

/// The text of a text box, a table cell or a shape: runs, and how the box lays them out.
struct RichText: Codable, Hashable {
    var runs: [TextRun]
    var hAlign: HAlign = .left
    var vAlign: VAlign = .top
    /// A multiple of the font's line height.
    var lineSpacing: Double = 1.0
    /// Extra space between characters, in points.
    var charSpacing: Double = 0
    /// An outline around the letters.
    var outline: Stroke?
    /// A shadow behind the letters.
    var shadow: ShadowStyle?

    var plainText: String { runs.map(\.text).joined() }

    /// The formatting new text gets: the first run's.
    var baseRun: TextRun { runs.first?.sameFormat ?? TextRun(text: "") }

    static func plain(
        _ text: String, size: Double, bold: Bool = false, color: RGBA = .text,
        hAlign: HAlign = .left, vAlign: VAlign = .top
    ) -> RichText {
        RichText(runs: [TextRun(text: text, size: size, bold: bold, color: color)], hAlign: hAlign, vAlign: vAlign)
    }

    /// Changes every run (for formatting a whole box).
    mutating func applyToAll(_ change: (inout TextRun) -> Void) {
        if runs.isEmpty { runs = [TextRun(text: "")] }
        for index in runs.indices { change(&runs[index]) }
    }

    /// Joins neighbouring runs with the same formatting and drops empty ones (keeping one to hold the formatting).
    func compacted() -> RichText {
        var merged: [TextRun] = []
        for run in runs where !run.text.isEmpty {
            if let last = merged.last, last.sameFormat == run.sameFormat {
                merged[merged.count - 1].text += run.text
            } else {
                merged.append(run)
            }
        }
        var copy = self
        copy.runs = merged.isEmpty ? [baseRun] : merged
        return copy
    }
}

// MARK: Elements

enum ShapeKind: String, Codable, CaseIterable, Identifiable {
    case rect, roundRect, ellipse, triangle, star, arrow

    var id: String { rawValue }

    var label: String {
        switch self {
        case .rect: "四角"
        case .roundRect: "角丸四角"
        case .ellipse: "円"
        case .triangle: "三角"
        case .star: "星"
        case .arrow: "矢印"
        }
    }

    var icon: String {
        switch self {
        case .rect: "rectangle.fill"
        case .roundRect: "app.fill"
        case .ellipse: "circle.fill"
        case .triangle: "triangle.fill"
        case .star: "star.fill"
        case .arrow: "arrow.right"
        }
    }
}

struct ShapeElement: Codable, Hashable {
    var kind: ShapeKind
    var cornerRadius: Double = 32
    var fill: Fill = .solid(.brand)
    var stroke: Stroke?
    var shadow: ShadowStyle?
}

/// A straight line between two points in slide space. Its element frame is kept as their bounding box.
struct LineElement: Codable, Hashable {
    var start: SlidePoint
    var end: SlidePoint
    var stroke = Stroke(color: .text, width: 8)
    var startArrow = false
    var endArrow = false

    var bounds: CGRect {
        CGRect(
            x: min(start.x, end.x), y: min(start.y, end.y),
            width: abs(end.x - start.x), height: abs(end.y - start.y)
        )
    }
}

/// How much of the image is cut away on each side, as a fraction of its size.
struct CropInsets: Codable, Hashable {
    var left: Double = 0
    var top: Double = 0
    var right: Double = 0
    var bottom: Double = 0

    var isEmpty: Bool { left == 0 && top == 0 && right == 0 && bottom == 0 }
}

struct ImageElement: Codable, Hashable {
    var asset: String
    var mode: ImageFitMode = .fit
    var crop = CropInsets()
    var cornerRadius: Double = 0
}

struct TableCell: Codable, Hashable {
    var text: RichText
    var fill: RGBA?
}

struct TableElement: Codable, Hashable {
    /// Rows of cells.
    var cells: [[TableCell]]
    /// Relative sizes; each set is scaled to fill the table's frame.
    var rowHeights: [Double]
    var columnWidths: [Double]
    var borderColor: RGBA = RGBA(hex: 0x9CA3AF)
    var borderWidth: Double = 2

    var rows: Int { cells.count }
    var columns: Int { cells.first?.count ?? 0 }

    static func emptyCell(header: Bool = false) -> TableCell {
        TableCell(
            text: RichText.plain("", size: 32, bold: header, vAlign: .middle),
            fill: header ? RGBA(hex: 0xE6F7F7) : nil
        )
    }

    static func make(rows: Int, columns: Int) -> TableElement {
        let cells = (0..<rows).map { row in
            (0..<columns).map { _ in emptyCell(header: row == 0) }
        }
        return TableElement(
            cells: cells,
            rowHeights: Array(repeating: 1, count: rows),
            columnWidths: Array(repeating: 1, count: columns)
        )
    }

    /// Adds or removes rows / columns at the end, keeping what's already there.
    mutating func resize(rows newRows: Int, columns newColumns: Int) {
        let newRows = max(1, newRows)
        let newColumns = max(1, newColumns)
        var resized: [[TableCell]] = []
        for row in 0..<newRows {
            var line: [TableCell] = []
            for column in 0..<newColumns {
                if row < cells.count, column < cells[row].count {
                    line.append(cells[row][column])
                } else {
                    line.append(Self.emptyCell())
                }
            }
            resized.append(line)
        }
        cells = resized
        rowHeights = (0..<newRows).map { $0 < rowHeights.count ? rowHeights[$0] : 1 }
        columnWidths = (0..<newColumns).map { $0 < columnWidths.count ? columnWidths[$0] : 1 }
    }

    /// Where a cell is, inside a table of this size.
    func cellRect(row: Int, column: Int, in size: CGSize) -> CGRect {
        let totalHeight = max(rowHeights.reduce(0, +), 0.0001)
        let totalWidth = max(columnWidths.reduce(0, +), 0.0001)
        let y = rowHeights.prefix(row).reduce(0, +) / totalHeight * Double(size.height)
        let x = columnWidths.prefix(column).reduce(0, +) / totalWidth * Double(size.width)
        let height = (row < rowHeights.count ? rowHeights[row] : 1) / totalHeight * Double(size.height)
        let width = (column < columnWidths.count ? columnWidths[column] : 1) / totalWidth * Double(size.width)
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

struct TextBoxElement: Codable, Hashable {
    var text: RichText
    /// Shown in gray in the editor while the box is empty (「タイトルを入力」…); never played or exported.
    var placeholder: String?
}

enum ElementContent: Codable, Hashable {
    case text(TextBoxElement)
    case shape(ShapeElement)
    case line(LineElement)
    case image(ImageElement)
    case table(TableElement)
}

enum ElementKind {
    case text, shape, line, image, table
}

struct SlideElement: Codable, Hashable, Identifiable {
    var id = UUID()
    var frame: SlideRect
    /// Degrees, clockwise.
    var rotation: Double = 0
    var opacity: Double = 1
    var content: ElementContent

    var kind: ElementKind {
        switch content {
        case .text: .text
        case .shape: .shape
        case .line: .line
        case .image: .image
        case .table: .table
        }
    }

    var kindLabel: String {
        switch content {
        case .text: "テキストボックス"
        case .shape(let shape): shape.kind.label
        case .line: "ライン"
        case .image: "画像"
        case .table: "テーブル"
        }
    }

    /// Lines keep their frame as the box around their two ends.
    mutating func syncLineFrame() {
        guard case .line(let line) = content else { return }
        frame = SlideRect(line.bounds)
    }

    /// Moves the element (and a line's ends) by an offset in slide space.
    mutating func move(by dx: Double, _ dy: Double) {
        frame.x += dx
        frame.y += dy
        if case .line(var line) = content {
            line.start.x += dx
            line.start.y += dy
            line.end.x += dx
            line.end.y += dy
            content = .line(line)
        }
    }

    /// What makes two elements on neighbouring slides "the same" for 移動: the same text, image, shape kind…
    var matchKey: String {
        switch content {
        case .text(let box): "text:" + box.text.plainText
        case .image(let image): "image:" + image.asset
        case .shape(let shape): "shape:" + shape.kind.rawValue
        case .line: "line"
        case .table(let table): "table:\(table.rows)x\(table.columns):" + table.cells.flatMap { $0 }.map(\.text.plainText).joined(separator: "|")
        }
    }

    /// Every piece of text in the element, for searching.
    var searchableText: String {
        switch content {
        case .text(let box): box.text.plainText
        case .table(let table): table.cells.flatMap { $0 }.map(\.text.plainText).joined(separator: " ")
        default: ""
        }
    }

    var assetNames: [String] {
        switch content {
        case .image(let image): [image.asset]
        case .shape(let shape):
            if case .image(let ref) = shape.fill { [ref.asset] } else { [] }
        default: []
        }
    }

    /// Every font name used in the element.
    var fontNames: Set<String> {
        switch content {
        case .text(let box): Set(box.text.runs.map(\.font))
        case .table(let table): Set(table.cells.flatMap { $0 }.flatMap { $0.text.runs.map(\.font) })
        default: []
        }
    }
}

// MARK: Animations and transitions

enum AnimationCategory: String, Codable, CaseIterable {
    case entrance, exit

    var label: String { self == .entrance ? "登場" : "退場" }
}

enum AnimationEffect: String, Codable, CaseIterable {
    case appear, fade, slideIn, zoom, move

    var label: String {
        switch self {
        case .appear: "表示"
        case .fade: "フェード"
        case .slideIn: "スライドイン"
        case .zoom: "ズーム"
        case .move: "移動"
        }
    }

    /// Older decks stored the side in the effect; `legacyAngle` reads it back.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AnimationEffect(rawValue: raw) ?? (raw.hasPrefix("slideFrom") ? .slideIn : .fade)
    }

    static func legacyAngle(_ raw: String) -> Double? {
        switch raw {
        case "slideFromRight": 0
        case "slideFromBottom": 90
        case "slideFromLeft": 180
        case "slideFromTop": 270
        default: nil
        }
    }
}

/// Which way something moves, as the side it comes from: 0° the right, 90° below, 180° the left, 270° above.
enum MotionAngle {
    static func label(_ angle: Double) -> String {
        let names = ["右", "右下", "下", "左下", "左", "左上", "上", "右上"]
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        let index = Int((normalized / 45).rounded()) % 8
        let exact = abs(normalized - Double(index) * 45) < 0.5 || abs(normalized - 360) < 0.5
        return exact ? "\(names[index])から" : "\(Int(normalized.rounded()))°"
    }

    /// A unit vector toward the side it comes from (y down).
    static func vector(_ angle: Double) -> CGPoint {
        let radians = angle * .pi / 180
        return CGPoint(x: cos(radians), y: sin(radians))
    }
}

enum AnimationStart: String, Codable, CaseIterable {
    case onTap, withPrevious, afterPrevious

    var label: String {
        switch self {
        case .onTap: "タップ時"
        case .withPrevious: "前の動作と同時"
        case .afterPrevious: "前の動作の後"
        }
    }
}

struct ElementAnimation: Codable, Hashable, Identifiable {
    var id = UUID()
    var elementID: UUID
    var category: AnimationCategory = .entrance
    var effect: AnimationEffect = .fade
    var start: AnimationStart = .onTap
    var duration: Double = 0.5
    var delay: Double = 0
    /// スライドイン: the side it comes from (see `MotionAngle`).
    var angle: Double = 90
    /// ズーム: out (from big to its size) instead of in (from small).
    var zoomOut = false

    init(
        id: UUID = UUID(), elementID: UUID, category: AnimationCategory = .entrance, effect: AnimationEffect = .fade,
        start: AnimationStart = .onTap, duration: Double = 0.5, delay: Double = 0, angle: Double = 90, zoomOut: Bool = false
    ) {
        self.id = id
        self.elementID = elementID
        self.category = category
        self.effect = effect
        self.start = start
        self.duration = duration
        self.delay = delay
        self.angle = angle
        self.zoomOut = zoomOut
    }

    private enum CodingKeys: String, CodingKey {
        case id, elementID, category, effect, start, duration, delay, angle, zoomOut
    }

    /// Reads older decks too (no angle / zoom mode; the side was in the effect).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        elementID = try container.decode(UUID.self, forKey: .elementID)
        category = try container.decodeIfPresent(AnimationCategory.self, forKey: .category) ?? .entrance
        effect = try container.decodeIfPresent(AnimationEffect.self, forKey: .effect) ?? .fade
        start = try container.decodeIfPresent(AnimationStart.self, forKey: .start) ?? .onTap
        duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0.5
        delay = try container.decodeIfPresent(Double.self, forKey: .delay) ?? 0
        let raw = (try? container.decodeIfPresent(String.self, forKey: .effect)) ?? nil
        angle = try container.decodeIfPresent(Double.self, forKey: .angle) ?? raw.flatMap(AnimationEffect.legacyAngle) ?? 90
        zoomOut = try container.decodeIfPresent(Bool.self, forKey: .zoomOut) ?? false
    }
}

enum TransitionKind: String, Codable, CaseIterable {
    case none, fade, push, cover, zoom

    var label: String {
        switch self {
        case .none: "なし"
        case .fade: "フェード"
        case .push: "プッシュ"
        case .cover: "カバー"
        case .zoom: "ズーム"
        }
    }

    var hasAngle: Bool { self == .push || self == .cover }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TransitionKind(rawValue: raw) ?? (raw.hasPrefix("push") ? .push : .fade)
    }
}

struct SlideTransition: Codable, Hashable {
    var kind: TransitionKind = .none
    var duration: Double = 0.5
    /// プッシュ / カバー: the side the new slide comes from (see `MotionAngle`).
    var angle: Double = 0
    /// ズーム: out (the new slide shrinks into place) instead of in (it grows).
    var zoomOut = false

    init(kind: TransitionKind = .none, duration: Double = 0.5, angle: Double = 0, zoomOut: Bool = false) {
        self.kind = kind
        self.duration = duration
        self.angle = angle
        self.zoomOut = zoomOut
    }

    private enum CodingKeys: String, CodingKey {
        case kind, duration, angle, zoomOut
    }

    /// Reads older decks too ("pushLeft" / "pushRight", no angle).
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decodeIfPresent(TransitionKind.self, forKey: .kind) ?? .none
        duration = try container.decodeIfPresent(Double.self, forKey: .duration) ?? 0.5
        let raw = (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? nil
        angle = try container.decodeIfPresent(Double.self, forKey: .angle) ?? (raw == "pushRight" ? 180 : 0)
        zoomOut = try container.decodeIfPresent(Bool.self, forKey: .zoomOut) ?? false
    }
}

enum SlideBackground: Codable, Hashable {
    case solid(RGBA)
    case gradient(LinearGradientFill)
    case image(ImageRef)

    var fill: Fill {
        switch self {
        case .solid(let color): .solid(color)
        case .gradient(let gradient): .gradient(gradient)
        case .image(let ref): .image(ref)
        }
    }

    init(fill: Fill) {
        switch fill {
        case .none: self = .solid(.white)
        case .solid(let color): self = .solid(color)
        case .gradient(let gradient): self = .gradient(gradient)
        case .image(let ref): self = .image(ref)
        }
    }
}

// MARK: Slide

struct SlideContent: Codable, Hashable, Identifiable {
    static let size = CGSize(width: 1920, height: 1080)

    var id = UUID()
    var background: SlideBackground = .solid(.white)
    /// Back to front.
    var elements: [SlideElement] = []
    var transition = SlideTransition()
    /// In the order they play.
    var animations: [ElementAnimation] = []

    var searchableText: String {
        elements.map(\.searchableText).filter { !$0.isEmpty }.joined(separator: " ")
    }

    var assetNames: [String] {
        var names = elements.flatMap(\.assetNames)
        if case .image(let ref) = background { names.append(ref.asset) }
        return names
    }

    var fontNames: Set<String> {
        elements.reduce(into: Set<String>()) { $0.formUnion($1.fontNames) }
    }

    func index(of id: UUID) -> Int? {
        elements.firstIndex { $0.id == id }
    }

    /// The same slide with new IDs for it, its elements and their animations (for copies).
    func withNewIDs() -> SlideContent {
        var copy = self
        copy.id = UUID()
        var map: [UUID: UUID] = [:]
        for index in copy.elements.indices {
            let fresh = UUID()
            map[copy.elements[index].id] = fresh
            copy.elements[index].id = fresh
        }
        copy.animations = copy.animations.compactMap { animation in
            guard let element = map[animation.elementID] else { return nil }
            var moved = animation
            moved.id = UUID()
            moved.elementID = element
            return moved
        }
        return copy
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func encoded() -> Data {
        (try? Self.encoder.encode(self)) ?? Data()
    }

    static func decode(_ data: Data) -> SlideContent? {
        try? JSONDecoder().decode(SlideContent.self, from: data)
    }
}
