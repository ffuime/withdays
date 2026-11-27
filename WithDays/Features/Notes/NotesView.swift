import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Notes: handwritten notes in folders. ＋ makes a note or a folder, or brings in a PDF, an image or a scan;
/// holding a note or a folder shows what can be done with it. The calendar button goes back to Cal.
struct NotesView: View {
    var onCalendar: () -> Void

    @Environment(NotesStore.self) private var notes

    /// The folder being looked into; nil at the top.
    @State private var folder: NoteFolder?
    @State private var open: NoteRef?
    /// A note to open once the sheet or picker that made it has gone.
    @State private var openNext: String?
    @State private var showSetup = false
    @State private var importingPDF = false
    @State private var showPhotos = false
    @State private var photo: PhotosPickerItem?
    @State private var showScanner = false
    @State private var prompt: NamePrompt?
    @State private var promptText = ""
    @State private var deletingFolder: NoteFolder?
    @State private var deletingNote: Note?
    @State private var share: NoteShare?
    @State private var errorMessage: String?
    /// Searching every note by its name and the text read from its pages.
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    struct NoteRef: Identifiable {
        let id: String
        /// The page to open on.
        var page = 0
    }

    /// A name being asked for: a new folder, or renaming a folder / a note.
    struct NamePrompt: Identifiable {
        enum Target {
            case newFolder, folder(String), note(String)
        }

        let title: String
        let target: Target
        let id = UUID()
    }

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16, alignment: .top)]

    var body: some View {
        withImports
            .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }), presenting: prompt) { prompt in
                TextField("名前", text: $promptText)
                Button("キャンセル", role: .cancel) {}
                Button("OK") { apply(prompt) }
            }
            .confirmationDialog(
                "「\(deletingFolder?.name ?? "")」とその中のノートを削除します",
                isPresented: Binding(get: { deletingFolder != nil }, set: { if !$0 { deletingFolder = nil } }),
                titleVisibility: .visible,
                presenting: deletingFolder
            ) { target in
                Button("削除", role: .destructive) {
                    if folder?.id == target.id { folder = nil }
                    notes.deleteFolder(target.id)
                }
            }
            .confirmationDialog(
                "「\(deletingNote?.name ?? "")」を削除します",
                isPresented: Binding(get: { deletingNote != nil }, set: { if !$0 { deletingNote = nil } }),
                titleVisibility: .visible,
                presenting: deletingNote
            ) { target in
                Button("削除", role: .destructive) { notes.delete(target.id) }
            }
            .sheet(item: $share) { item in
                ActivityView(items: [item.url])
                    .presentationDetents([.medium, .large])
            }
            .errorAlert($errorMessage)
    }

    /// The grid with its bar; apart from the sheets so each part type-checks quickly.
    private var library: some View {
        let list = notes.notes(in: folder?.id)
        let finding = searching && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let found = finding ? notes.search(query) : []
        return ScrollView {
            if searching {
                searchField
            }
            LazyVGrid(columns: columns, spacing: 20) {
                if finding {
                    ForEach(found, id: \.note.id) { noteCell($0.note, page: $0.page) }
                } else {
                    if folder == nil {
                        ForEach(notes.folders) { folderCell($0) }
                    }
                    ForEach(list) { noteCell($0) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 100)
        }
        .overlay {
            if finding {
                if found.isEmpty {
                    ContentUnavailableView("見つかりませんでした", systemImage: "magnifyingglass")
                }
            } else if !searching, list.isEmpty, folder != nil || notes.folders.isEmpty {
                ContentUnavailableView("ノートがありません", systemImage: "pencil.and.scribble", description: Text("＋から作成できます"))
            }
        }
        .overlay(alignment: .bottomTrailing) { addButton }
        .animation(.snappy, value: searching)
        // Pages are read in the background so they can be searched; again after a note has been open.
        .task { await notes.readPages() }
        .onChange(of: open?.id) { _, new in
            if new == nil { Task { await notes.readPages() } }
        }
        .animation(.snappy, value: folder)
        .animation(.snappy, value: notes.state.notes)
        .animation(.snappy, value: notes.state.folders)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                WithDaysBackButton(action: onCalendar)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    folder = nil
                } label: {
                    HStack(spacing: 6) {
                        if folder != nil {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text(folder?.name ?? "Notes")
                            .font(.system(size: 20, weight: .bold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.brand)
                    .fixedSize()
                }
                .allowsHitTesting(folder != nil)
            }
            .sharedBackgroundVisibility(.hidden)
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    searching.toggle()
                    if searching {
                        searchFocused = true
                    } else {
                        query = ""
                    }
                } label: {
                    Image(systemName: searching ? "xmark" : "magnifyingglass")
                        .contentTransition(.symbolEffect(.replace))
                }
            }
        }
    }

    /// Finds notes by name, and by the text in their pages (print, handwriting, text boxes).
    private var searchField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("ノート名・ページ内の文字", text: $query)
                    .font(.system(size: 16))
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                if !query.isEmpty {
                    Button { query = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            if let reading = notes.reading {
                Text("ページの文字を認識中 \(reading.done) / \(reading.total)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .padding(.horizontal, 14)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// Making and bringing in notes; the new note opens once its sheet or picker has closed.
    private var withImports: some View {
        library
            .fullScreenCover(item: $open) { ref in
                NoteEditorView(noteID: ref.id, startPage: ref.page)
            }
            .sheet(isPresented: $showSetup, onDismiss: openPending) {
                NoteSetupSheet { name, paper in
                    openNext = notes.addNote(name: name, folder: folder?.id, paper: paper).id
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            .fileImporter(isPresented: $importingPDF, allowedContentTypes: [.pdf]) { result in
                do {
                    openNext = try notes.importPDF(from: try result.get(), folder: folder?.id).id
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: openPending)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            .fullScreenCover(isPresented: $showScanner, onDismiss: openPending) {
                DocumentScanner(onFinish: scanned)
                    .ignoresSafeArea()
            }
            .photosPicker(isPresented: $showPhotos, selection: $photo, matching: .images)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                photo = nil
                Task {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                            throw NotesStore.Failure(message: "画像を読み込めませんでした")
                        }
                        openNext = try notes.importImages([image], name: "画像", folder: folder?.id).id
                        try? await Task.sleep(for: .milliseconds(500))
                        openPending()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
    }

    /// Scanned pages become a new note.
    private func scanned(_ images: [UIImage]) {
        showScanner = false
        guard !images.isEmpty else { return }
        do {
            openNext = try notes.importImages(images, name: "スキャン", folder: folder?.id).id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func openPending() {
        guard let id = openNext else { return }
        openNext = nil
        open = NoteRef(id: id)
    }

    // MARK: Cells

    private func folderCell(_ item: NoteFolder) -> some View {
        let count = notes.notes(in: item.id).count
        return Button {
            folder = item
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.brand.opacity(0.1))
                    .aspectRatio(NotePage.a4.width / NotePage.a4.height, contentMode: .fit)
                    .overlay {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.brand)
                    }
                caption(item.name, "\(count)件")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("名前を変更", systemImage: "pencil") {
                promptText = item.name
                prompt = NamePrompt(title: "フォルダの名前", target: .folder(item.id))
            }
            Button("削除", systemImage: "trash", role: .destructive) { deletingFolder = item }
        }
    }

    /// `page` is where the search found its text; the note opens there.
    private func noteCell(_ note: Note, page: Int? = nil) -> some View {
        let detail = page.map { "\($0 + 1)ページ目に一致" }
            ?? "\(note.updated.formatted(.dateTime.month().day().hour().minute()))・\(note.pages.count)ページ"
        return Button {
            open = NoteRef(id: note.id, page: page ?? 0)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                NoteThumbnail(note: note)
                caption(note.name, detail)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("名前を変更", systemImage: "pencil") {
                promptText = note.name
                prompt = NamePrompt(title: "ノートの名前", target: .note(note.id))
            }
            if !notes.folders.isEmpty {
                Menu("移動", systemImage: "folder") {
                    if note.folder != nil {
                        Button("フォルダの外へ") { notes.move(note.id, to: nil) }
                    }
                    ForEach(notes.folders.filter { $0.id != note.folder }) { target in
                        Button(target.name) { notes.move(note.id, to: target.id) }
                    }
                }
            }
            Button("PDFで書き出し", systemImage: "square.and.arrow.up") {
                do {
                    share = NoteShare(url: try notes.exportPDF(note))
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
            Button("削除", systemImage: "trash", role: .destructive) { deletingNote = note }
        }
    }

    private func caption(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Text(detail)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var addButton: some View {
        Menu {
            Button("新規ノート", systemImage: "square.and.pencil") { showSetup = true }
            if folder == nil {
                Button("新規フォルダ", systemImage: "folder.badge.plus") {
                    promptText = ""
                    prompt = NamePrompt(title: "新規フォルダ", target: .newFolder)
                }
            }
            Divider()
            Button("PDFを取り込む", systemImage: "doc") { importingPDF = true }
            Button("画像を取り込む", systemImage: "photo") { showPhotos = true }
            if DocumentScanner.isSupported {
                Button("書類をスキャン", systemImage: "doc.viewfinder") { showScanner = true }
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 26.4, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .padding(20)
    }

    private func apply(_ prompt: NamePrompt) {
        let name = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        switch prompt.target {
        case .newFolder: notes.addFolder(name: name)
        case .folder(let id):
            notes.renameFolder(id, to: name)
            if folder?.id == id { folder?.name = name }
        case .note(let id): notes.rename(id, to: name)
        }
    }
}

/// The note's first page, as it looks with its handwriting.
private struct NoteThumbnail: View {
    let note: Note

    @Environment(NotesStore.self) private var notes

    var body: some View {
        let size = note.pages.first?.size ?? NotePage.a4
        Color.white
            .aspectRatio(size.width / size.height, contentMode: .fit)
            .overlay {
                if let image = notes.thumbnail(of: note) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.12), lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 6, y: 3)
    }
}

/// A new note's name and paper.
struct NoteSetupSheet: View {
    var onCreate: (String, NotePaper) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var paper = NotePaper.ruled

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("新規ノート")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(Color.brand)
            TextField("ノート", text: $name)
                .font(.system(size: 17))
                .padding(.horizontal, 14)
                .frame(height: 44)
                .background(Capsule().fill(Color.primary.opacity(0.05)))
            HStack(spacing: 12) {
                ForEach(NotePaper.allCases) { item in
                    Button { paper = item } label: {
                        VStack(spacing: 6) {
                            NotePaperPreview(paper: item)
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(paper == item ? Color.brand : Color.primary.opacity(0.15), lineWidth: paper == item ? 2.5 : 1))
                            Text(item.label)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(paper == item ? Color.brand : Color.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            Button {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                dismiss()
                onCreate(trimmed.isEmpty ? "ノート" : trimmed, paper)
            } label: {
                Text("作成")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 32)
            }
            .buttonStyle(.glassProminent)
            Spacer(minLength: 0)
        }
        .padding(24)
        .sensoryFeedback(.selection, trigger: paper)
    }
}

/// A corner of the paper, close enough to see its ruling.
private struct NotePaperPreview: View {
    let paper: NotePaper

    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            let line = GraphicsContext.Shading.color(Color(red: 0.70, green: 0.76, blue: 0.84))
            let step: CGFloat = 12
            switch paper {
            case .plain:
                break
            case .ruled:
                for y in stride(from: step * 1.5, to: size.height, by: step) {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.8)), with: line)
                }
            case .grid:
                for y in stride(from: step, to: size.height, by: step) {
                    context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 0.8)), with: line)
                }
                for x in stride(from: step, to: size.width, by: step) {
                    context.fill(Path(CGRect(x: x, y: 0, width: 0.8, height: size.height)), with: line)
                }
            case .dot:
                for y in stride(from: step, to: size.height, by: step) {
                    for x in stride(from: step, to: size.width, by: step) {
                        context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: line)
                    }
                }
            }
        }
        .aspectRatio(NotePage.a4.width / NotePage.a4.height, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
