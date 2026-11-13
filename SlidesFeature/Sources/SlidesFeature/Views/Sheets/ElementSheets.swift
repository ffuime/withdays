import SwiftUI

/// シェイプ: 塗り / 枠線 / 効果.
struct ShapeFormatSheet: View {
    @Bindable var editor: DeckEditor
    let elementID: UUID
    @State var tab: Tab

    enum Tab: Hashable {
        case fill, stroke, effects
    }

    private var element: SlideElement? { editor.current.elements.first { $0.id == elementID } }

    private var shape: ShapeElement? {
        if case .shape(let shape) = element?.content { return shape }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Picker("", selection: $tab) {
                    Text("塗り").tag(Tab.fill)
                    Text("枠線").tag(Tab.stroke)
                    Text("効果").tag(Tab.effects)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                if let shape {
                    switch tab {
                    case .fill: fillSection(shape)
                    case .stroke: strokeSection(shape)
                    case .effects: effectsSection(shape)
                    }
                }
            }
            .navigationTitle("シェイプ")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func update(_ key: String, _ change: @escaping (inout ShapeElement) -> Void) {
        editor.changeElement(elementID, coalesce: "shape-\(elementID)-\(key)") { element in
            guard case .shape(var shape) = element.content else { return }
            change(&shape)
            element.content = .shape(shape)
        }
    }

    @ViewBuilder
    private func fillSection(_ shape: ShapeElement) -> some View {
        Section("塗り") {
            FillEditor(
                fill: Binding(get: { shape.fill }, set: { fill in update("fill") { $0.fill = fill } }),
                storeImage: editor.storeImage
            )
        }
        if shape.kind == .roundRect {
            Section("角丸") {
                ValueSlider(
                    title: "角丸",
                    value: Binding(get: { shape.cornerRadius }, set: { radius in update("radius") { $0.cornerRadius = radius } }),
                    range: 0...400
                )
            }
        }
    }

    @ViewBuilder
    private func strokeSection(_ shape: ShapeElement) -> some View {
        Section {
            Toggle("枠線", isOn: Binding(get: { shape.stroke != nil }, set: { on in
                update("strokeOn") { $0.stroke = on ? ($0.stroke ?? Stroke(color: .text, width: 6)) : nil }
            }))
            .tint(SlidesTheme.brand)
        }
        if let stroke = shape.stroke {
            Section("色") {
                ColorRow(color: stroke.color) { color in update("strokeColor") { $0.stroke?.color = color } }
            }
            Section {
                ValueSlider(
                    title: "太さ",
                    value: Binding(get: { stroke.width }, set: { width in update("strokeWidth") { $0.stroke?.width = width } }),
                    range: 1...60
                )
                Picker("線の種類", selection: Binding(get: { stroke.dash }, set: { dash in update("dash") { $0.stroke?.dash = dash } })) {
                    ForEach(DashStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
    }

    @ViewBuilder
    private func effectsSection(_ shape: ShapeElement) -> some View {
        Section {
            Toggle("影", isOn: Binding(get: { shape.shadow != nil }, set: { on in
                update("shadowOn") { $0.shadow = on ? ($0.shadow ?? ShadowStyle()) : nil }
            }))
            .tint(SlidesTheme.brand)
        }
        if let shadow = shape.shadow {
            Section("影") {
                ColorRow(color: shadow.color) { color in update("shadowColor") { $0.shadow?.color = color } }
                ValueSlider(title: "ぼかし", value: Binding(get: { shadow.blur }, set: { value in update("blur") { $0.shadow?.blur = value } }), range: 0...120)
                ValueSlider(title: "横のずれ", value: Binding(get: { shadow.x }, set: { value in update("shadowX") { $0.shadow?.x = value } }), range: -80...80)
                ValueSlider(title: "縦のずれ", value: Binding(get: { shadow.y }, set: { value in update("shadowY") { $0.shadow?.y = value } }), range: -80...80)
            }
        }
        OpacitySection(editor: editor, elementID: elementID)
    }
}

/// 不透明度, for any element.
struct OpacitySection: View {
    @Bindable var editor: DeckEditor
    let elementID: UUID

    var body: some View {
        let opacity = editor.current.elements.first { $0.id == elementID }?.opacity ?? 1
        Section("不透明度") {
            ValueSlider(
                title: "不透明度",
                value: Binding(get: { opacity * 100 }, set: { value in
                    editor.changeElement(elementID, coalesce: "opacity-\(elementID)") { $0.opacity = value / 100 }
                }),
                range: 0...100, format: { "\(Int($0.rounded()))%" }
            )
        }
    }
}

/// 線: color, width, dash and arrowheads.
struct LineFormatSheet: View {
    @Bindable var editor: DeckEditor
    let elementID: UUID

    var body: some View {
        NavigationStack {
            Form {
                if case .line(let line) = editor.current.elements.first(where: { $0.id == elementID })?.content {
                    Section("色") {
                        ColorRow(color: line.stroke.color) { color in update("color") { $0.stroke.color = color } }
                    }
                    Section {
                        ValueSlider(title: "太さ", value: Binding(get: { line.stroke.width }, set: { width in update("width") { $0.stroke.width = width } }), range: 1...60)
                        Picker("線の種類", selection: Binding(get: { line.stroke.dash }, set: { dash in update("dash") { $0.stroke.dash = dash } })) {
                            ForEach(DashStyle.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("矢印") {
                        Toggle("始点", isOn: Binding(get: { line.startArrow }, set: { on in update("start") { $0.startArrow = on } }))
                            .tint(SlidesTheme.brand)
                        Toggle("終点", isOn: Binding(get: { line.endArrow }, set: { on in update("end") { $0.endArrow = on } }))
                            .tint(SlidesTheme.brand)
                    }
                    OpacitySection(editor: editor, elementID: elementID)
                }
            }
            .navigationTitle("線")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func update(_ key: String, _ change: @escaping (inout LineElement) -> Void) {
        editor.changeElement(elementID, coalesce: "line-\(elementID)-\(key)") { element in
            guard case .line(var line) = element.content else { return }
            change(&line)
            element.content = .line(line)
        }
    }
}

/// 切り抜き: how the image fits its frame, how much is cut from each side, and its corners.
struct ImageCropSheet: View {
    @Bindable var editor: DeckEditor
    let elementID: UUID

    var body: some View {
        NavigationStack {
            Form {
                if case .image(let image) = editor.current.elements.first(where: { $0.id == elementID })?.content {
                    Section {
                        Picker("表示", selection: Binding(get: { image.mode }, set: { mode in update("mode") { $0.mode = mode } })) {
                            ForEach(ImageFitMode.allCases, id: \.self) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    Section("切り抜き") {
                        crop("左", image.crop.left) { value in update("left") { $0.crop.left = value } }
                        crop("右", image.crop.right) { value in update("right") { $0.crop.right = value } }
                        crop("上", image.crop.top) { value in update("top") { $0.crop.top = value } }
                        crop("下", image.crop.bottom) { value in update("bottom") { $0.crop.bottom = value } }
                    }
                    Section("角丸") {
                        ValueSlider(title: "角丸", value: Binding(get: { image.cornerRadius }, set: { value in update("radius") { $0.cornerRadius = value } }), range: 0...400)
                    }
                    OpacitySection(editor: editor, elementID: elementID)
                }
            }
            .navigationTitle("切り抜き")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func crop(_ title: String, _ value: Double, _ set: @escaping (Double) -> Void) -> some View {
        ValueSlider(
            title: title,
            value: Binding(get: { value * 100 }, set: { set($0 / 100) }),
            range: 0...45, format: { "\(Int($0.rounded()))%" }
        )
    }

    private func update(_ key: String, _ change: @escaping (inout ImageElement) -> Void) {
        editor.changeElement(elementID, coalesce: "image-\(elementID)-\(key)") { element in
            guard case .image(var image) = element.content else { return }
            change(&image)
            element.content = .image(image)
        }
    }
}

/// 行/列: how many, and each row's / column's share of the table.
struct TableSizeSheet: View {
    @Bindable var editor: DeckEditor
    let elementID: UUID

    var body: some View {
        NavigationStack {
            Form {
                if case .table(let table) = editor.current.elements.first(where: { $0.id == elementID })?.content {
                    Section {
                        Stepper("行 \(table.rows)", value: Binding(get: { table.rows }, set: { rows in
                            update("rows") { $0.resize(rows: rows, columns: $0.columns) }
                        }), in: 1...20)
                        Stepper("列 \(table.columns)", value: Binding(get: { table.columns }, set: { columns in
                            update("columns") { $0.resize(rows: $0.rows, columns: columns) }
                        }), in: 1...10)
                    }
                    Section("行の高さ") {
                        ForEach(0..<table.rows, id: \.self) { row in
                            ValueSlider(
                                title: "\(row + 1)行目",
                                value: Binding(get: { table.rowHeights[row] }, set: { value in update("row\(row)") { $0.rowHeights[row] = value } }),
                                range: 0.3...4, step: 0.1, format: { String(format: "%.1f", $0) }
                            )
                        }
                        Button("均等にする") { update("evenRows") { $0.rowHeights = Array(repeating: 1, count: $0.rows) } }
                    }
                    Section("列の幅") {
                        ForEach(0..<table.columns, id: \.self) { column in
                            ValueSlider(
                                title: "\(column + 1)列目",
                                value: Binding(get: { table.columnWidths[column] }, set: { value in update("column\(column)") { $0.columnWidths[column] = value } }),
                                range: 0.3...4, step: 0.1, format: { String(format: "%.1f", $0) }
                            )
                        }
                        Button("均等にする") { update("evenColumns") { $0.columnWidths = Array(repeating: 1, count: $0.columns) } }
                    }
                }
            }
            .navigationTitle("行/列")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func update(_ key: String, _ change: @escaping (inout TableElement) -> Void) {
        editor.changeElement(elementID, coalesce: "table-\(elementID)-\(key)") { element in
            guard case .table(var table) = element.content else { return }
            change(&table)
            element.content = .table(table)
        }
    }
}

/// 表の書式: borders, cell fills, and the cells' text.
struct TableFormatSheet: View {
    @Bindable var editor: DeckEditor
    let elementID: UUID
    let formatter: TextFormatter

    /// Which cells a fill goes to.
    @State private var target = 0

    var body: some View {
        NavigationStack {
            Form {
                if case .table(let table) = editor.current.elements.first(where: { $0.id == elementID })?.content {
                    Section("枠線") {
                        ColorRow(color: table.borderColor) { color in update("borderColor") { $0.borderColor = color } }
                        ValueSlider(title: "太さ", value: Binding(get: { table.borderWidth }, set: { width in update("borderWidth") { $0.borderWidth = width } }), range: 0...20)
                    }
                    Section("セルの塗り") {
                        Picker("対象", selection: $target) {
                            Text("すべて").tag(0)
                            Text("1行目").tag(1)
                            if editingCell != nil { Text("選択中のセル").tag(2) }
                        }
                        .pickerStyle(.segmented)
                        ColorRow(color: currentFill(table) ?? .white) { color in fillCells(color) }
                        Button("塗りなし") { fillCells(nil) }
                    }
                    Section {
                        NavigationLink("テキスト") {
                            TextFormatForm(formatter: formatter)
                                .navigationTitle("テキスト")
                                .navigationBarTitleDisplayMode(.inline)
                        }
                    }
                    OpacitySection(editor: editor, elementID: elementID)
                }
            }
            .navigationTitle("表の書式")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var editingCell: (row: Int, column: Int)? {
        if case .cell(let id, let row, let column) = editor.editing, id == elementID { return (row, column) }
        return nil
    }

    private func currentFill(_ table: TableElement) -> RGBA? {
        switch target {
        case 2:
            guard let cell = editingCell else { return nil }
            return table.cells[cell.row][cell.column].fill
        default:
            return table.cells.first?.first?.fill
        }
    }

    private func fillCells(_ color: RGBA?) {
        let cell = editingCell
        let target = target
        update("fill\(target)") { table in
            for row in table.cells.indices {
                for column in table.cells[row].indices {
                    let chosen: Bool = switch target {
                    case 1: row == 0
                    case 2: cell.map { $0.row == row && $0.column == column } ?? false
                    default: true
                    }
                    if chosen { table.cells[row][column].fill = color }
                }
            }
        }
    }

    private func update(_ key: String, _ change: @escaping (inout TableElement) -> Void) {
        editor.changeElement(elementID, coalesce: "tableFormat-\(elementID)-\(key)") { element in
            guard case .table(var table) = element.content else { return }
            change(&table)
            element.content = .table(table)
        }
    }
}

/// 背景: the slide's fill, and a button to give every slide the same.
struct BackgroundSheet: View {
    @Bindable var editor: DeckEditor

    @State private var applied = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("背景") {
                    FillEditor(
                        fill: Binding(get: { editor.current.background.fill }, set: { fill in
                            if case .image(let ref) = fill, ref.asset.isEmpty { return }
                            editor.changeCurrentSlide(coalesce: "background-\(editor.current.id)") { $0.background = SlideBackground(fill: fill) }
                        }),
                        storeImage: editor.storeImage
                    )
                }
                Section {
                    Button("すべてのスライドに適用", systemImage: "square.stack.3d.down.forward") {
                        editor.applyBackgroundToAll()
                        applied += 1
                    }
                    .disabled(editor.slides.count < 2)
                }
            }
            .sensoryFeedback(.success, trigger: applied)
            .navigationTitle("背景")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// トランジション: how this slide comes in.
struct TransitionSheet: View {
    @Bindable var editor: DeckEditor

    var body: some View {
        let transition = editor.current.transition
        NavigationStack {
            Form {
                Section("トランジション") {
                    ForEach(TransitionKind.allCases, id: \.self) { kind in
                        Button {
                            editor.changeCurrentSlide { $0.transition.kind = kind }
                        } label: {
                            HStack {
                                Text(kind.label).foregroundStyle(.primary)
                                Spacer()
                                if transition.kind == kind {
                                    Image(systemName: "checkmark").foregroundStyle(SlidesTheme.brandText)
                                }
                            }
                        }
                    }
                }
                if transition.kind.hasAngle {
                    Section("方向") {
                        AngleControl(angle: Binding(get: { transition.angle }, set: { value in
                            editor.changeCurrentSlide(coalesce: "transitionAngle-\(editor.current.id)") { $0.transition.angle = value }
                        }))
                    }
                }
                if transition.kind == .zoom {
                    Section {
                        Picker("ズーム", selection: Binding(get: { transition.zoomOut }, set: { value in
                            editor.changeCurrentSlide { $0.transition.zoomOut = value }
                        })) {
                            Text("ズームイン").tag(false)
                            Text("ズームアウト").tag(true)
                        }
                        .pickerStyle(.segmented)
                    }
                }
                if transition.kind != .none {
                    Section {
                        ValueSlider(
                            title: "時間",
                            value: Binding(get: { transition.duration }, set: { value in
                                editor.changeCurrentSlide(coalesce: "transition-\(editor.current.id)") { $0.transition.duration = value }
                            }),
                            range: 0.2...3, step: 0.1, format: { String(format: "%.1f秒", $0) }
                        )
                    }
                }
            }
            .navigationTitle("トランジション")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// The side something comes from: eight arrows for the usual sides, and a slider for any angle.
struct AngleControl: View {
    @Binding var angle: Double

    private static let presets: [(angle: Double, icon: String)] = [
        (225, "arrow.down.right"), (270, "arrow.down"), (315, "arrow.down.left"),
        (180, "arrow.right"), (0, "arrow.left"),
        (135, "arrow.up.right"), (90, "arrow.up"), (45, "arrow.up.left"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            // Arrows point the way it moves, laid out around the middle like the sides they come from.
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow { arrow(225); arrow(270); arrow(315) }
                GridRow {
                    arrow(180)
                    Text(MotionAngle.label(angle))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 64, height: 40)
                    arrow(0)
                }
                GridRow { arrow(135); arrow(90); arrow(45) }
            }
            ValueSlider(title: "角度", value: $angle, range: 0...359, step: 1, format: { "\(Int($0.rounded()))°" }, marks: [0, 45, 90, 135, 180, 225, 270, 315])
        }
    }

    private func arrow(_ value: Double) -> some View {
        let icon = Self.presets.first { $0.angle == value }?.icon ?? "arrow.left"
        let on = abs(angle - value) < 0.5
        return Button {
            angle = value
        } label: {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(on ? SlidesTheme.onBrand : Color.primary)
                .frame(width: 64, height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(on ? SlidesTheme.brand : Color.primary.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(MotionAngle.label(value))
    }
}
