import SwiftData
import UIKit
import XCTest
@testable import SlidesFeature

final class ModelTests: XCTestCase {
    func testSlideRoundTripsThroughJSON() throws {
        var slide = SlideLayout.titleBody.make()
        slide.background = .gradient(.default)
        slide.elements.append(SlideElement(
            frame: SlideRect(x: 10, y: 20, width: 300, height: 200), rotation: 15, opacity: 0.5,
            content: .shape(ShapeElement(kind: .star, fill: .gradient(.default), stroke: Stroke(color: .black, width: 4, dash: .dash), shadow: ShadowStyle()))
        ))
        slide.elements.append(SlideElement(frame: SlideRect(x: 0, y: 0, width: 600, height: 300), content: .table(.make(rows: 2, columns: 3))))
        slide.animations.append(ElementAnimation(elementID: slide.elements[0].id, category: .exit, effect: .slideIn, start: .afterPrevious, angle: 180))
        slide.transition = SlideTransition(kind: .push, duration: 0.8, angle: 270)
        let decoded = try XCTUnwrap(SlideContent.decode(slide.encoded()))
        XCTAssertEqual(decoded, slide)
    }

    func testOlderDecksStillDecode() throws {
        let element = UUID()
        let json = """
        {"id":"\(UUID().uuidString)","background":{"solid":{"_0":{"r":1,"g":1,"b":1,"a":1}}},"elements":[],
         "transition":{"kind":"pushRight","duration":0.7},
         "animations":[{"id":"\(UUID().uuidString)","elementID":"\(element.uuidString)","category":"entrance","effect":"slideFromTop","start":"onTap","duration":0.5,"delay":0}]}
        """
        let slide = try JSONDecoder().decode(SlideContent.self, from: Data(json.utf8))
        XCTAssertEqual(slide.transition.kind, .push)
        XCTAssertEqual(slide.transition.angle, 180)
        XCTAssertEqual(slide.animations.first?.effect, .slideIn)
        XCTAssertEqual(slide.animations.first?.angle, 270)
    }

    func testCopiesGetNewIDsAndKeepAnimationsOnTheirElements() {
        var slide = SlideLayout.titleSubtitle.make()
        let target = slide.elements[1].id
        slide.animations = [ElementAnimation(elementID: target)]
        let copy = slide.withNewIDs()
        XCTAssertNotEqual(copy.id, slide.id)
        XCTAssertTrue(Set(copy.elements.map(\.id)).isDisjoint(with: Set(slide.elements.map(\.id))))
        XCTAssertEqual(copy.animations.first?.elementID, copy.elements[1].id)
    }

    func testTableResizeKeepsCells() {
        var table = TableElement.make(rows: 2, columns: 2)
        table.cells[1][1].text = .plain("残る", size: 20)
        table.resize(rows: 3, columns: 1)
        XCTAssertEqual(table.rows, 3)
        XCTAssertEqual(table.columns, 1)
        table.resize(rows: 3, columns: 2)
        XCTAssertEqual(table.cells[1][1].text.plainText, "")
        XCTAssertEqual(table.rowHeights.count, 3)
    }

    func testCompactingJoinsRunsWithTheSameFormat() {
        let run = TextRun(text: "あ", size: 30)
        let text = RichText(runs: [run, run.with("い"), run.with(""), TextRun(text: "う", size: 30, bold: true)]).compacted()
        XCTAssertEqual(text.runs.map(\.text), ["あい", "う"])
    }

    func testRichTextSurvivesEditing() {
        var text = RichText.plain("見出し", size: 80, bold: true, color: .brand, hAlign: .center)
        text.runs.append(TextRun(text: "本文", font: "Georgia", size: 40, italic: true, underline: true))
        let attributed = RichTextConverter.attributed(text)
        let back = RichTextConverter.richText(from: attributed, base: text, scale: 1)
        XCTAssertEqual(back.plainText, "見出し本文")
        XCTAssertEqual(back.runs.count, 2)
        XCTAssertEqual(back.runs[0].bold, true)
        XCTAssertEqual(back.runs[1].font, "Georgia")
        XCTAssertEqual(back.runs[1].underline, true)
        XCTAssertEqual(back.hAlign, .center)
    }
}

final class SearchTests: XCTestCase {
    func testNormalizationFoldsCaseWidthAndKana() {
        XCTAssertEqual(SlidesSearch.normalize("ＡＢＣ"), SlidesSearch.normalize("abc"))
        XCTAssertEqual(SlidesSearch.normalize("すらいど"), SlidesSearch.normalize("スライド"))
        XCTAssertEqual(SlidesSearch.normalize("ｽﾗｲﾄﾞ"), SlidesSearch.normalize("スライド"))
        XCTAssertEqual(SlidesSearch.normalize("Keynote"), "keynote")
    }

    @MainActor
    func testMatchesTitleThenBodyThenImageText() throws {
        let container = try ModelContainer(
            for: Deck.self, SlidePage.self, ImageTextEntry.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let deck = Deck(title: "会議資料")
        context.insert(deck)
        var first = SlideContent()
        first.elements = [SlideElement(frame: SlideRect(x: 0, y: 0, width: 100, height: 100), content: .text(TextBoxElement(text: .plain("売上の推移", size: 40))))]
        var second = SlideContent()
        second.elements = [SlideElement(frame: SlideRect(x: 0, y: 0, width: 100, height: 100), content: .image(ImageElement(asset: "photo.jpg")))]
        for (index, slide) in [first, second].enumerated() {
            let page = SlidePage(slide, order: index)
            context.insert(page)
            page.deck = deck
        }
        try context.save()
        let images = [ImageTextEntry.key(deck: deck.id, asset: "photo.jpg"): SlidesSearch.normalize("ホワイトボード")]
        XCTAssertEqual(SlidesSearch.match(deck, query: "かいぎ", imageText: images), nil)
        XCTAssertEqual(SlidesSearch.match(deck, query: "会議", imageText: images), .title)
        XCTAssertEqual(SlidesSearch.match(deck, query: "うりあげ", imageText: images), nil)
        XCTAssertEqual(SlidesSearch.match(deck, query: "売上", imageText: images), .body(slide: 1))
        XCTAssertEqual(SlidesSearch.match(deck, query: "ほわいと", imageText: images), .image(slide: 2))
        XCTAssertEqual(SlidesSearch.Match.body(slide: 4).caption, "スライド4の本文に一致")
    }
}

final class HistoryTests: XCTestCase {
    func testUndoRedo() {
        var history = EditHistory<Int>(limit: 100)
        history.record(0)
        history.record(1)
        XCTAssertEqual(history.undo(from: 2), 1)
        XCTAssertEqual(history.undo(from: 1), 0)
        XCTAssertNil(history.undo(from: 0))
        XCTAssertEqual(history.redo(from: 0), 1)
        XCTAssertTrue(history.canRedo)
        history.record(1)
        XCTAssertFalse(history.canRedo)
    }

    func testCoalescingWithinTheWindowMakesOneStep() {
        var history = EditHistory<Int>(limit: 100)
        let start = Date()
        history.record(0, coalesce: "typing", now: start)
        history.record(1, coalesce: "typing", now: start.addingTimeInterval(0.5))
        history.record(2, coalesce: "typing", now: start.addingTimeInterval(0.9))
        XCTAssertEqual(history.undoStack, [0])
        history.record(3, coalesce: "typing", now: start.addingTimeInterval(3))
        XCTAssertEqual(history.undoStack, [0, 3])
    }

    func testLimitDropsTheOldestSteps() {
        var history = EditHistory<Int>(limit: 100)
        for value in 0..<150 { history.record(value) }
        XCTAssertEqual(history.undoStack.count, 100)
        XCTAssertEqual(history.undoStack.first, 50)
    }
}

final class PPTXTests: XCTestCase {
    private var deck = UUID()

    override func tearDown() {
        SlidesFiles.deleteAssets(of: deck)
        super.tearDown()
    }

    private func sampleSlides() throws -> [SlideContent] {
        deck = UUID()
        let png = UIGraphicsImageRenderer(size: CGSize(width: 40, height: 20)).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
        }
        let stored = try SlidesFiles.storeImage(png, deck: deck)
        var first = SlideLayout.titleSubtitle.make()
        first.transition = SlideTransition(kind: .fade)
        first.animations = [
            ElementAnimation(elementID: first.elements[0].id, effect: .fade, start: .withPrevious),
            ElementAnimation(elementID: first.elements[1].id, effect: .slideIn, start: .onTap),
        ]
        var second = SlideContent(background: .gradient(.default))
        var line = SlideElement(frame: SlideRect(x: 0, y: 0, width: 0, height: 0), content: .line(LineElement(start: SlidePoint(x: 900, y: 100), end: SlidePoint(x: 100, y: 500), endArrow: true)))
        line.syncLineFrame()
        second.elements = [
            SlideElement(frame: SlideRect(x: 100, y: 100, width: 400, height: 300), rotation: 30, content: .shape(ShapeElement(kind: .roundRect, fill: .gradient(.default), stroke: Stroke(color: .black, width: 4), shadow: ShadowStyle()))),
            line,
            SlideElement(frame: SlideRect(x: 600, y: 500, width: 800, height: 300), content: .table(.make(rows: 2, columns: 3))),
            SlideElement(frame: SlideRect(x: 1200, y: 100, width: 400, height: 300), content: .image(ImageElement(asset: stored.name, mode: .fill, crop: CropInsets(left: 0.1), cornerRadius: 20))),
            SlideElement(frame: SlideRect(x: 100, y: 800, width: 900, height: 120), content: .text(TextBoxElement(text: .plain("記号 <&> \"引用\"\n二行目", size: 40)))),
        ]
        second.animations = [ElementAnimation(elementID: second.elements[0].id, category: .exit, effect: .zoom)]
        return [first, second]
    }

    func testPackageHasItsPartsAndWellFormedXML() throws {
        let slides = try sampleSlides()
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).pptx")
        defer { try? FileManager.default.removeItem(at: url) }
        try PPTXExporter.write(title: "テスト", slides: slides, deck: deck, to: url)

        let entries = ZipReader.entries(try Data(contentsOf: url))
        let required = [
            "[Content_Types].xml", "_rels/.rels", "ppt/presentation.xml", "ppt/_rels/presentation.xml.rels",
            "ppt/slideMasters/slideMaster1.xml", "ppt/slideLayouts/slideLayout1.xml", "ppt/theme/theme1.xml",
            "ppt/slides/slide1.xml", "ppt/slides/slide2.xml", "ppt/slides/_rels/slide2.xml.rels",
        ]
        for part in required {
            XCTAssertNotNil(entries[part], "missing \(part)")
        }
        XCTAssertTrue(entries.keys.contains { $0.hasPrefix("ppt/media/") }, "the picture is in the package")

        for (name, data) in entries where name.hasSuffix(".xml") || name.hasSuffix(".rels") {
            let parser = XMLParser(data: data)
            XCTAssertTrue(parser.parse(), "\(name) is not well-formed: \(parser.parserError?.localizedDescription ?? "")")
        }

        let types = String(decoding: try XCTUnwrap(entries["[Content_Types].xml"]), as: UTF8.self)
        XCTAssertTrue(types.contains("/ppt/slides/slide2.xml"))
        let second = String(decoding: try XCTUnwrap(entries["ppt/slides/slide2.xml"]), as: UTF8.self)
        XCTAssertTrue(second.contains("a:gradFill"))
        XCTAssertTrue(second.contains("a:tbl"))
        XCTAssertTrue(second.contains("a:tailEnd"))
        XCTAssertTrue(second.contains("p:timing"))
        let rels = String(decoding: try XCTUnwrap(entries["ppt/slides/_rels/slide2.xml.rels"]), as: UTF8.self)
        XCTAssertTrue(rels.contains("../media/"))
    }

    func testPDFHasAPagePerSlide() throws {
        let slides = try sampleSlides()
        let url = try PDFExporter.export(title: "テスト/資料", slides: slides, deck: deck)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertEqual(url.lastPathComponent, "テスト_資料.pdf")
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        XCTAssertEqual(document.numberOfPages, 2)
        let box = try XCTUnwrap(document.page(at: 1)?.getBoxRect(.mediaBox))
        XCTAssertEqual(box.size, CGSize(width: 1920, height: 1080))
    }
}

final class SnappingTests: XCTestCase {
    private func box(_ x: Double, _ y: Double) -> SlideElement {
        SlideElement(frame: SlideRect(x: x, y: y, width: 100, height: 100), content: .shape(ShapeElement(kind: .rect)))
    }

    func testElementsMovedTogetherDoNotSnapToEachOther() {
        let a = box(300, 300)
        let b = box(500, 300)
        var slide = SlideContent()
        slide.elements = [a, b]
        let snapper = Snapper(slide: slide, excluding: [a.id, b.id], guides: false, threshold: 8)
        // The pair's box (300...600) moved 3 pt: nothing of its own pulls it, so it stays where it was put.
        let moved = snapper.snapBounds(CGRect(x: 303, y: 303, width: 300, height: 100))
        XCTAssertEqual(moved.dx, 0)
        XCTAssertEqual(moved.dy, 0)
        XCTAssertTrue(moved.lines.isEmpty)
    }

    func testABoxSnapsToTheSlideMiddle() {
        let snapper = Snapper(slide: SlideContent(), excluding: [], guides: false, threshold: 8)
        // Middle at 965 → 960.
        let moved = snapper.snapBounds(CGRect(x: 915, y: 100, width: 100, height: 100))
        XCTAssertEqual(moved.dx, -5, accuracy: 0.001)
        XCTAssertEqual(moved.lines, [SnapLine(vertical: true, position: 960)])
    }
}
