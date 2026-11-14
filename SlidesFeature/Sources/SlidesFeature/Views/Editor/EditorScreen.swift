import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Opens a deck in the editor.
struct EditorScreen: View {
    let deckID: UUID
    let startSlide: Int
    @Binding var path: [SlidesRoute]

    @Environment(\.modelContext) private var context
    @State private var editor: DeckEditor?

    var body: some View {
        Group {
            if let editor {
                EditorView(editor: editor, path: $path)
            } else {
                ProgressView()
            }
        }
        .task {
            guard editor == nil else { return }
            let id = deckID
            let decks = (try? context.fetch(FetchDescriptor<Deck>(predicate: #Predicate { $0.id == id }))) ?? []
            if let deck = decks.first {
                editor = DeckEditor(deck: deck, context: context, start: startSlide)
            } else {
                if !path.isEmpty { path.removeLast() }
            }
        }
    }
}

/// スライド作成画面: the slide in the middle, the page strip along the bottom, and glass controls on top.
struct EditorView: View {
    @Bindable var editor: DeckEditor
    @Binding var path: [SlidesRoute]

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @State private var textController = TextEditingController()
    @State private var sheet: EditorSheet?
    @State private var renaming = false
    @State private var playing = false
    /// The slide the player starts on.
    @State private var playStart = 0
    @State private var export: ExportRequest?
    @State private var showPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var importingImage = false
    @State private var selectAllOnEdit = false
    @State private var deletingDeck = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            topBar
            SlideCanvasView(editor: editor, textController: textController, showsGuides: editor.deck.showsGuides, selectAllOnEdit: $selectAllOnEdit)
                .background(Color(uiColor: .systemGroupedBackground))
                .overlay(alignment: .topLeading) {
                    if editor.multiSelecting {
                        Text("複数選択・\(editor.multiSelection.count)個")
                            .font(.system(size: 13, weight: .bold))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .frame(height: 32)
                            .glassEffect(.regular, in: .capsule)
                            .padding(10)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .animation(.snappy(duration: 0.2), value: editor.multiSelecting)
            if editor.editing != nil {
                TextAccessoryBar(controller: textController) {
                    sheet = .textFormat
                } done: {
                    finishTyping()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                ContextToolbar(editor: editor, open: { sheet = $0 }, paste: paste)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Color(uiColor: .systemGroupedBackground))
                PageStrip(editor: editor)
            }
        }
        .animation(.snappy(duration: 0.25), value: editor.editing != nil)
        .background(Color(uiColor: .systemGroupedBackground))
        // The controls are drawn here (always there), not in the navigation bar.
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
        }
        .sheet(isPresented: $renaming) {
            TitleInputView(mode: .rename, initial: editor.deck.title) { title in
                DeckActions.rename(editor.deck, to: title, context: context)
            }
            .presentationDetents([.large])
        }
        .fullScreenCover(isPresented: $playing) {
            PlayerView(slides: editor.slides, deck: editor.deckID, start: playStart) { index in
                editor.currentIndex = index
                // The player has already faded to black and turned back; it goes without a slide.
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) { playing = false }
            }
        }
        .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { return }
                    try editor.insertImage(data)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .fileImporter(isPresented: $importingImage, allowedContentTypes: [.image, .svg]) { result in
            Task {
                do {
                    let url = try result.get()
                    let scoped = url.startAccessingSecurityScopedResource()
                    let data = try Data(contentsOf: url)
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    // SVG is drawn to a picture first.
                    try editor.insertImage(try await ImageLoading.usableData(data))
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .deckExport($export)
        .alert("「\(editor.deck.title)」を削除", isPresented: $deletingDeck) {
            Button("キャンセル", role: .cancel) {}
            Button("削除", role: .destructive) {
                finishTyping()
                let deck = editor.deck
                if !path.isEmpty { path.removeLast() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { DeckActions.delete(deck, context: context) }
            }
        } message: {
            Text("この操作は取り消せません。")
        }
        .alert("エラー", isPresented: Binding(get: { errorMessage != nil || editor.saveError != nil }, set: { if !$0 { errorMessage = nil; editor.saveError = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? editor.saveError ?? "")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { editor.saveNow() }
        }
        .onDisappear { editor.saveNow() }
        .onChange(of: editor.editing) { old, new in
            // Typing ended some other way (another slide, undo): the text view lets go of the keyboard.
            if new == nil, old != nil { textController.finish() }
        }
        .sensoryFeedback(.selection, trigger: editor.selection)
        .sensoryFeedback(.selection, trigger: editor.multiSelection)
        .sensoryFeedback(.impact(weight: .medium), trigger: editor.multiSelecting) { _, new in new }
    }

    // MARK: Top bar

    /// Back at the left; at the right, 取り消し / やり直し and ＋ / ▶ / ⋯ as two glass pills.
    private var topBar: some View {
        HStack(spacing: 10) {
            barButton("chevron.left", label: "戻る") {
                finishTyping()
                editor.saveNow()
                if !path.isEmpty { path.removeLast() }
            }
            .glassEffect(.regular.interactive(), in: .circle)
            Spacer()
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    HStack(spacing: 0) {
                        barButton("arrow.uturn.backward", label: "取り消し") {
                            finishTyping()
                            editor.undo()
                        }
                        .disabled(!editor.canUndo)
                        .opacity(editor.canUndo ? 1 : 0.35)
                        barButton("arrow.uturn.forward", label: "やり直し") {
                            finishTyping()
                            editor.redo()
                        }
                        .disabled(!editor.canRedo)
                        .opacity(editor.canRedo ? 1 : 0.35)
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                    HStack(spacing: 0) {
                        barButton("plus", label: "挿入") {
                            finishTyping()
                            sheet = .insert
                        }
                        playButton
                        moreMenu
                    }
                    .glassEffect(.regular.interactive(), in: .capsule)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    private func barButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .accessibilityLabel(label)
    }

    /// A tap plays from the first slide; holding plays from the one on screen.
    private var playButton: some View {
        Image(systemName: "play.fill")
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .onTapGesture { play(from: 0) }
            .onLongPressGesture(minimumDuration: 0.45) { play(from: editor.currentIndex) }
            .accessibilityElement()
            .accessibilityLabel("再生")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { play(from: 0) }
            .accessibilityAction(named: "現在のスライドから再生") { play(from: editor.currentIndex) }
    }

    private var moreMenu: some View {
        Menu {
            DeckMenuItems(deck: editor.deck, actions: DeckMenuActions(
                rename: { renaming = true },
                toggleGuides: { editor.toggleGuides() },
                showDetails: {
                    editor.saveNow()
                    sheet = .details
                },
                export: startExport,
                exportCurrent: { format in
                    finishTyping()
                    editor.saveNow()
                    export = ExportRequest(
                        title: editor.deck.title, deckID: editor.deckID, slide: editor.current,
                        number: editor.currentIndex + 1, format: format
                    )
                },
                toggleFavorite: { editor.toggleFavorite() },
                delete: { deletingDeck = true }
            ))
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .tint(.primary)
        .accessibilityLabel("その他")
    }

    /// Opens the player without a slide-up: it turns the screen itself, behind black.
    private func play(from index: Int) {
        finishTyping()
        editor.saveNow()
        playStart = index
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { playing = true }
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: EditorSheet) -> some View {
        let selected = editor.selection
        switch sheet {
        case .insert:
            InsertSheet(
                insertText: insertText,
                insertImageFromPhotos: { showPhotos = true },
                insertImageFromFiles: { importingImage = true },
                insertImageData: { try editor.insertImage($0) },
                insertShape: insertShape,
                insertLine: insertLine,
                insertTable: insertTable
            )
            .presentationDetents([.medium, .large])
        case .textFormat:
            if let selected {
                TextFormatSheet(formatter: TextFormatter(editor: editor, controller: textController, elementID: selected))
                    .formatSheet()
            }
        case .textColor:
            if let selected {
                TextColorSheet(formatter: TextFormatter(editor: editor, controller: textController, elementID: selected))
                    .formatSheet()
            }
        case .shapeFill, .shapeStroke, .shapeEffects:
            if let selected {
                ShapeFormatSheet(editor: editor, elementID: selected, tab: sheet == .shapeFill ? .fill : sheet == .shapeStroke ? .stroke : .effects)
                    .formatSheet()
            }
        case .lineFormat:
            if let selected {
                LineFormatSheet(editor: editor, elementID: selected)
                    .formatSheet()
            }
        case .imageCrop:
            if let selected {
                ImageCropSheet(editor: editor, elementID: selected)
                    .formatSheet()
            }
        case .tableSize:
            if let selected {
                TableSizeSheet(editor: editor, elementID: selected)
                    .presentationDetents([.medium, .large])
            }
        case .tableFormat:
            if let selected {
                TableFormatSheet(editor: editor, elementID: selected, formatter: TextFormatter(editor: editor, controller: textController, elementID: selected))
                    .formatSheet()
            }
        case .animation:
            if let selected {
                AnimationSheet(editor: editor, elementID: selected)
                    .presentationDetents([.medium, .large])
            }
        case .background:
            BackgroundSheet(editor: editor)
                .formatSheet()
        case .transition:
            TransitionSheet(editor: editor)
                .presentationDetents([.medium, .large])
        case .groupFormat:
            GroupFormatSheet(editor: editor)
                .formatSheet()
        case .groupAnimation:
            GroupAnimationSheet(editor: editor)
                .presentationDetents([.medium, .large])
        case .details:
            DeckDetailsSheet(deck: editor.deck)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: Inserting

    private func insertText() {
        editor.insert(SlideElement(
            frame: SlideRect(x: 0, y: 0, width: 900, height: 140),
            content: .text(TextBoxElement(text: .plain("テキスト", size: 56)))
        ))
        if let id = editor.selection {
            selectAllOnEdit = true
            editor.editing = .text(id)
        }
    }

    private func insertShape(_ kind: ShapeKind) {
        let size: CGSize = switch kind {
        case .arrow: CGSize(width: 520, height: 300)
        case .rect, .roundRect: CGSize(width: 520, height: 360)
        default: CGSize(width: 400, height: 400)
        }
        editor.insert(SlideElement(
            frame: SlideRect(x: 0, y: 0, width: Double(size.width), height: Double(size.height)),
            content: .shape(ShapeElement(kind: kind))
        ))
    }

    private func insertLine(startArrow: Bool, endArrow: Bool) {
        var element = SlideElement(
            frame: SlideRect(x: 0, y: 0, width: 0, height: 0),
            content: .line(LineElement(start: SlidePoint(x: 710, y: 540), end: SlidePoint(x: 1210, y: 540), startArrow: startArrow, endArrow: endArrow))
        )
        element.syncLineFrame()
        editor.insert(element)
    }

    private func insertTable(rows: Int, columns: Int) {
        let width = min(Double(columns) * 280, 1600)
        let height = min(Double(rows) * 110, 860)
        editor.insert(SlideElement(
            frame: SlideRect(x: 0, y: 0, width: width, height: height),
            content: .table(.make(rows: rows, columns: columns))
        ))
    }

    private func paste() {
        Task {
            do {
                try await editor.paste()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startExport(_ format: ExportFormat) {
        finishTyping()
        editor.saveNow()
        export = ExportRequest(deck: editor.deck, format: format)
    }

    private func finishTyping() {
        guard editor.editing != nil else { return }
        textController.finish()
        editor.editing = nil
    }
}
