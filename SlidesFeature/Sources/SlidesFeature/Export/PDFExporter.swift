import UIKit

/// One 1920×1080 pt page per slide, drawn with the same renderer as the screen: text and shapes stay vector,
/// images go in at their own resolution, and Core Graphics embeds the fonts used.
enum PDFExporter {
    static func export(title: String, slides: [SlideContent], deck: UUID) throws -> URL {
        let url = try SlidesFiles.exportFolder().appending(path: SlidesFiles.fileName(title, ext: "pdf"))
        let bounds = CGRect(origin: .zero, size: SlideContent.size)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title, kCGPDFContextCreator as String: "Slides"]
        let renderer = UIGraphicsPDFRenderer(bounds: bounds, format: format)
        try renderer.writePDF(to: url) { context in
            for slide in slides {
                autoreleasepool {
                    context.beginPage()
                    SlideRenderer.draw(slide, deck: deck, in: context.cgContext)
                }
            }
        }
        return url
    }
}

/// One slide as a 1920×1080 picture, its images at full resolution.
enum PNGExporter {
    static func export(title: String, slide: SlideContent, deck: UUID) throws -> URL {
        let url = try SlidesFiles.exportFolder().appending(path: SlidesFiles.fileName(title, ext: "png"))
        let image = SlideRenderer.image(of: slide, deck: deck, width: 1920, scale: 1, preview: false)
        guard let data = image.pngData() else { throw SlidesFiles.Failure(message: "画像を書き出せませんでした。") }
        try data.write(to: url, options: .atomic)
        return url
    }
}
