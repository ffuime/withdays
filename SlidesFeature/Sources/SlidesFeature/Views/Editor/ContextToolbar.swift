import SwiftUI

/// The editor's sheets.
enum EditorSheet: String, Identifiable {
    case insert, textFormat, textColor, shapeFill, shapeStroke, shapeEffects, lineFormat, imageCrop
    case tableSize, tableFormat, animation, background, transition, details
    case groupFormat, groupAnimation

    var id: String { rawValue }
}

/// A glass bar above the slides for the selected element; with nothing selected, the slide's 背景 and トランジション.
/// コピー, 複製, the stacking order and 削除 are under その他; with nothing selected, その他 has 貼り付け and 背景.
/// In 複数選択: 整列, 書式, アニメーション, その他 (複製, 最前面/最背面, 削除) and 完了.
struct ContextToolbar: View {
    @Bindable var editor: DeckEditor
    var open: (EditorSheet) -> Void
    var paste: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            if editor.multiSelecting {
                groupItems
            } else if let element = editor.selectedElement {
                items(for: element)
                more(element)
            } else {
                item("挿入", "plus") { open(.insert) }
                item("トランジション", "rectangle.portrait.on.rectangle.portrait.angled") { open(.transition) }
                slideMore
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 56)
        .glassEffect(.regular, in: .capsule)
        .animation(.snappy(duration: 0.2), value: editor.selection)
        .animation(.snappy(duration: 0.2), value: editor.multiSelecting)
    }

    /// 複数選択: changes for every chosen element.
    @ViewBuilder
    private var groupItems: some View {
        let ids = editor.multiSelection
        let none = ids.isEmpty
        Menu {
            ForEach(DeckEditor.GroupAlignment.allCases, id: \.self) { alignment in
                Button(alignment.label, systemImage: alignment.icon) { editor.align(ids, alignment) }
            }
        } label: {
            itemLabel("整列", "align.horizontal.left")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .tint(.primary)
        .menuOrder(.fixed)
        .disabled(none)
        .opacity(none ? 0.35 : 1)
        item("書式", "paintpalette") { open(.groupFormat) }
            .disabled(none)
            .opacity(none ? 0.35 : 1)
        item("アニメーション", "sparkles") { open(.groupAnimation) }
            .disabled(none)
            .opacity(none ? 0.35 : 1)
        Menu {
            Button("複製", systemImage: "plus.square.on.square") { editor.duplicateElements(ids) }
            Divider()
            Button("最前面へ", systemImage: "square.3.layers.3d.top.filled") { editor.reorderElements(ids, toFront: true) }
            Button("最背面へ", systemImage: "square.3.layers.3d.bottom.filled") { editor.reorderElements(ids, toFront: false) }
            Divider()
            Button("削除", systemImage: "trash", role: .destructive) { editor.deleteElements(ids) }
        } label: {
            itemLabel("その他", "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .tint(.primary)
        .menuOrder(.fixed)
        .disabled(none)
        .opacity(none ? 0.35 : 1)
        .accessibilityLabel("その他")
        item("完了", "checkmark") { editor.endMultiSelect() }
    }

    @ViewBuilder
    private func items(for element: SlideElement) -> some View {
        switch element.content {
        case .text(let box):
            item("書式", "textformat") { open(.textFormat) }
            item("色", "paintpalette") { open(.textColor) }
            alignMenu(box.text, id: element.id)
        case .shape(let shape):
            item("塗り", "drop") { open(.shapeFill) }
            item("枠線", "square.dashed") { open(.shapeStroke) }
            if shape.kind == .roundRect {
                item("角丸", "app") { open(.shapeFill) }
            }
        case .image:
            item("切り抜き", "crop") { open(.imageCrop) }
        case .line:
            item("線", "line.diagonal") { open(.lineFormat) }
        case .table:
            item("行/列", "tablecells") { open(.tableSize) }
            item("表の書式", "tablecells.badge.ellipsis") { open(.tableFormat) }
        }
        item("アニメーション", "sparkles") { open(.animation) }
    }

    /// 配置: the text's horizontal and vertical alignment.
    private func alignMenu(_ text: RichText, id: UUID) -> some View {
        Menu {
            Section("横") {
                ForEach(HAlign.allCases, id: \.self) { align in
                    Button {
                        editor.formatText(id, key: "hAlign") { $0.hAlign = align }
                    } label: {
                        Label(align.label, systemImage: text.hAlign == align ? "checkmark" : align.icon)
                    }
                }
            }
            Section("縦") {
                ForEach(VAlign.allCases, id: \.self) { align in
                    Button {
                        editor.formatText(id, key: "vAlign") { $0.vAlign = align }
                    } label: {
                        Label(align.label, systemImage: text.vAlign == align ? "checkmark" : align.icon)
                    }
                }
            }
        } label: {
            itemLabel("配置", text.hAlign.icon)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .tint(.primary)
        .menuOrder(.fixed)
    }

    private func more(_ element: SlideElement) -> some View {
        Menu {
            Button("コピー", systemImage: "doc.on.doc") { editor.copyElement(element.id) }
            Button("複製", systemImage: "plus.square.on.square") { editor.duplicateElement(element.id) }
            Divider()
            Button("最前面へ", systemImage: "square.3.layers.3d.top.filled") { editor.reorder(element.id, .front) }
            Button("前面へ", systemImage: "square.2.layers.3d.top.filled") { editor.reorder(element.id, .forward) }
            Button("背面へ", systemImage: "square.2.layers.3d.bottom.filled") { editor.reorder(element.id, .backward) }
            Button("最背面へ", systemImage: "square.3.layers.3d.bottom.filled") { editor.reorder(element.id, .back) }
            Divider()
            Button("削除", systemImage: "trash", role: .destructive) { editor.deleteElement(element.id) }
        } label: {
            itemLabel("その他", "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .tint(.primary)
        .menuOrder(.fixed)
        .accessibilityLabel("その他")
    }

    /// With nothing selected: 貼り付け and 背景.
    private var slideMore: some View {
        Menu {
            Button("貼り付け", systemImage: "doc.on.clipboard", action: paste)
                .disabled(!ElementClipboard.canPaste)
            Button("背景", systemImage: "paintbrush") { open(.background) }
        } label: {
            itemLabel("その他", "ellipsis")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .tint(.primary)
        .menuOrder(.fixed)
        .accessibilityLabel("その他")
    }

    private func item(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            itemLabel(title, icon)
        }
        .buttonStyle(.plain)
    }

    private func itemLabel(_ title: String, _ icon: String) -> some View {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(height: 22)
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .foregroundStyle(.primary)
        .frame(minWidth: 52, minHeight: 48)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
    }
}

/// ＋: what to put on the slide.
struct InsertSheet: View {
    var insertText: () -> Void
    var insertImageFromPhotos: () -> Void
    var insertImageFromFiles: () -> Void
    /// An image fetched from a link (SVG already drawn to PNG).
    var insertImageData: (Data) throws -> Void
    var insertShape: (ShapeKind) -> Void
    var insertLine: (_ startArrow: Bool, _ endArrow: Bool) -> Void
    var insertTable: (_ rows: Int, _ columns: Int) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Button { pick(insertText) } label: {
                    Label("テキストボックス", systemImage: "textbox")
                }
                NavigationLink {
                    List {
                        Button { pick(insertImageFromPhotos) } label: {
                            Label("写真ライブラリ", systemImage: "photo.on.rectangle")
                        }
                        Button { pick(insertImageFromFiles) } label: {
                            Label("ファイル", systemImage: "folder")
                        }
                        NavigationLink {
                            ImageLinkView { data in
                                try insertImageData(data)
                                dismiss()
                            }
                        } label: {
                            Label("リンク", systemImage: "link")
                        }
                    }
                    .foregroundStyle(.primary)
                    .navigationTitle("画像")
                    .navigationBarTitleDisplayMode(.inline)
                } label: {
                    Label("画像", systemImage: "photo")
                }
                NavigationLink {
                    shapes
                } label: {
                    Label("シェイプ", systemImage: "square.on.circle")
                }
                NavigationLink {
                    lines
                } label: {
                    Label("ライン", systemImage: "line.diagonal")
                }
                NavigationLink {
                    TableSizePicker { rows, columns in pick { insertTable(rows, columns) } }
                } label: {
                    Label("テーブル", systemImage: "tablecells")
                }
            }
            .foregroundStyle(.primary)
            .navigationTitle("挿入")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var shapes: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 14)], spacing: 14) {
                ForEach(ShapeKind.allCases) { kind in
                    Button { pick { insertShape(kind) } } label: {
                        VStack(spacing: 8) {
                            Image(systemName: kind.icon)
                                .font(.system(size: 34))
                                .foregroundStyle(SlidesTheme.brand)
                                .frame(height: 48)
                            Text(kind.label)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 96)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .navigationTitle("シェイプ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var lines: some View {
        List {
            Button { pick { insertLine(false, false) } } label: { Label("線", systemImage: "line.diagonal") }
            Button { pick { insertLine(false, true) } } label: { Label("矢印", systemImage: "arrow.right") }
            Button { pick { insertLine(true, true) } } label: { Label("両矢印", systemImage: "arrow.left.and.right") }
        }
        .foregroundStyle(.primary)
        .navigationTitle("ライン")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// Closes the sheet, then acts (pickers can't open over a sheet that's going away).
    private func pick(_ action: @escaping () -> Void) {
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }
}

/// Rows × columns for a new table (3×3 to start).
struct TableSizePicker: View {
    var onInsert: (Int, Int) -> Void

    @State private var rows = 3
    @State private var columns = 3

    var body: some View {
        Form {
            Stepper("行 \(rows)", value: $rows, in: 1...20)
            Stepper("列 \(columns)", value: $columns, in: 1...10)
            Section {
                Button {
                    onInsert(rows, columns)
                } label: {
                    Text("挿入")
                        .font(.system(size: 16, weight: .bold))
                        .frame(maxWidth: .infinity)
                }
                .brandGlass()
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("テーブル")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// An image from a web address: PNG, JPEG, GIF, HEIC, WebP… and SVG.
struct ImageLinkView: View {
    var onLoaded: (Data) throws -> Void

    @State private var link = ""
    @State private var loading = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                TextField("https://…", text: $link)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused)
                    .submitLabel(.go)
                    .onSubmit(load)
            } footer: {
                Text("画像（PNG・JPEG・GIF・WebP・SVG など）のリンクを入力します。")
            }
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.system(size: 14))
                        .foregroundStyle(.red)
                }
            }
            Section {
                Button(action: load) {
                    HStack {
                        Spacer()
                        if loading { ProgressView() } else { Text("挿入").font(.system(size: 16, weight: .bold)) }
                        Spacer()
                    }
                    .frame(minHeight: 34)
                }
                .brandGlass(enabled: !link.isEmpty && !loading)
                .disabled(link.isEmpty || loading)
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle("リンク")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
    }

    private func load() {
        guard !link.isEmpty, !loading else { return }
        loading = true
        errorMessage = nil
        Task {
            do {
                let data = try await ImageLoading.download(link)
                try onLoaded(data)
            } catch {
                errorMessage = error.localizedDescription
            }
            loading = false
        }
    }
}
