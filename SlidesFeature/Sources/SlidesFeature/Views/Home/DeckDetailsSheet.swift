import Photos
import SwiftUI

/// 詳細: a large thumbnail and the deck's facts.
struct DeckDetailsSheet: View {
    let deck: Deck

    @State private var fileSize: Int64?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let first = deck.sortedPages.first {
                        SlideThumbnail(data: first.data, deck: deck.id, width: 340, cornerRadius: 12)
                            .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
                            .listRowBackground(Color.clear)
                    }
                }
                Section {
                    row("タイトル", deck.title)
                    row("枚数", "\(deck.pages.count)")
                    row("ファイルサイズ", fileSize.map(SlidesFormat.bytes) ?? "…")
                    row("スライドサイズ", "16:9（1920×1080）")
                    row("作成日", SlidesFormat.date.string(from: deck.createdAt))
                    row("最終更新日", SlidesFormat.date.string(from: deck.updatedAt))
                }
            }
            .navigationTitle("詳細")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            let id = deck.id
            let data = deck.pages.reduce(Int64(0)) { $0 + Int64($1.data.count) }
            let assets = await Task.detached { SlidesFiles.folderSize(SlidesFiles.assets(id)) }.value
            fileSize = data + assets
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        LabeledContent(title) {
            Text(value)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
    }
}

enum ExportFormat {
    case pdf, pptx, png
}

/// A deck to export, as a snapshot taken on the main thread.
struct ExportRequest: Identifiable {
    let id = UUID()
    let title: String
    let deckID: UUID
    let slides: [SlideContent]
    let format: ExportFormat

    @MainActor
    init(deck: Deck, format: ExportFormat) {
        title = deck.title
        deckID = deck.id
        slides = deck.slides
        self.format = format
    }

    /// One slide alone (このスライドのみ), named after the deck and its number.
    init(title: String, deckID: UUID, slide: SlideContent, number: Int, format: ExportFormat) {
        self.title = "\(title)（スライド\(number)）"
        self.deckID = deckID
        slides = [slide]
        self.format = format
    }
}

/// Exports in the background with a small progress panel, then shows the share sheet.
/// An image goes straight into the photo library instead.
struct DeckExportModifier: ViewModifier {
    @Binding var request: ExportRequest?

    @State private var running = false
    @State private var file: SharedFile?
    @State private var errorMessage: String?
    @State private var savedToPhotos = false

    func body(content: Content) -> some View {
        content
            .overlay {
                if running {
                    ProgressView("書き出し中…")
                        .padding(24)
                        .glassEffect(.regular, in: .rect(cornerRadius: 20))
                } else if savedToPhotos {
                    Label("写真に保存しました", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .glassEffect(.regular, in: .capsule)
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        .allowsHitTesting(false)
                }
            }
            .animation(.snappy(duration: 0.25), value: savedToPhotos)
            .sensoryFeedback(.success, trigger: savedToPhotos) { _, new in new }
            .onChange(of: request?.id) { _, id in
                guard id != nil, let job = request else { return }
                request = nil
                run(job)
            }
            .sheet(item: $file) { item in
                ShareSheet(items: [item.url])
                    .presentationDetents([.medium, .large])
            }
            .alert("書き出せませんでした", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func run(_ job: ExportRequest) {
        running = true
        Task.detached(priority: .userInitiated) {
            let result: Result<URL, Error>
            do {
                switch job.format {
                case .pdf: result = .success(try PDFExporter.export(title: job.title, slides: job.slides, deck: job.deckID))
                case .pptx: result = .success(try PPTXExporter.export(title: job.title, slides: job.slides, deck: job.deckID))
                case .png: result = .success(try PNGExporter.export(title: job.title, slide: job.slides.first ?? SlideContent(), deck: job.deckID))
                }
            } catch {
                result = .failure(error)
            }
            await MainActor.run {
                switch result {
                case .success(let url) where job.format == .png:
                    saveToPhotos(url)
                case .success(let url):
                    running = false
                    file = SharedFile(url: url)
                case .failure(let error):
                    running = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    /// Adds the picture to the photo library (asking for permission to add, the first time).
    private func saveToPhotos(_ url: URL) {
        Task {
            do {
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard status == .authorized || status == .limited else {
                    throw SlidesFiles.Failure(message: "写真への保存が許可されていません。設定アプリの「WithDays」→「写真」で許可してください。")
                }
                try await PHPhotoLibrary.shared().performChanges {
                    PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: nil)
                }
                running = false
                savedToPhotos = true
                try? await Task.sleep(for: .seconds(1.6))
                savedToPhotos = false
            } catch {
                running = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

extension View {
    func deckExport(_ request: Binding<ExportRequest?>) -> some View {
        modifier(DeckExportModifier(request: request))
    }
}
