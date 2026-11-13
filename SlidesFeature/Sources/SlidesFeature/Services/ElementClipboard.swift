import UIKit
import UniformTypeIdentifiers

/// Copying elements through the system pasteboard: the element itself for Slides, plus its text or a picture
/// of it for other apps. Pasting takes Slides elements, images and text from anywhere.
@MainActor
enum ElementClipboard {
    static let type = "com.ffuime.withdays.slides.element"

    struct Payload: Codable {
        var element: SlideElement
        /// The deck its images are in.
        var deck: UUID
    }

    /// What's on the pasteboard, without reading it (so iOS doesn't ask to allow pasting).
    static var canPaste: Bool {
        let board = UIPasteboard.general
        return board.contains(pasteboardTypes: [type]) || board.hasImages || board.hasStrings
    }

    static func copy(_ element: SlideElement, deck: UUID) {
        var item: [String: Any] = [:]
        if let data = try? JSONEncoder().encode(Payload(element: element, deck: deck)) {
            item[type] = data
        }
        switch element.content {
        case .text(let box):
            item[UTType.utf8PlainText.identifier] = box.text.plainText
        case .table(let table):
            item[UTType.utf8PlainText.identifier] = table.cells.map { $0.map(\.text.plainText).joined(separator: "\t") }.joined(separator: "\n")
        case .image(let image):
            if let data = try? Data(contentsOf: SlidesFiles.asset(image.asset, deck: deck)) {
                item[image.asset.hasSuffix(".png") ? UTType.png.identifier : UTType.jpeg.identifier] = data
            }
        default:
            if let png = SlideRenderer.image(of: element, deck: deck).pngData() {
                item[UTType.png.identifier] = png
            }
        }
        UIPasteboard.general.setItems([item])
    }

    enum Content {
        case element(Payload)
        case image(Data)
        case text(String)
    }

    /// The pasteboard's content, most specific first.
    static func read() -> Content? {
        let board = UIPasteboard.general
        if let data = board.data(forPasteboardType: type), let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            return .element(payload)
        }
        for kind in [UTType.png, .jpeg, .heic, .gif, .webP, .svg, .image] {
            if let data = board.data(forPasteboardType: kind.identifier) { return .image(data) }
        }
        if let image = board.image, let png = image.pngData() { return .image(png) }
        if let string = board.string, !string.isEmpty { return .text(string) }
        return nil
    }
}
