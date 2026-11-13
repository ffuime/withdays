import Foundation
import UIKit

/// Writes a PowerPoint file (OOXML) for a deck: 16:9, backgrounds, text with its formatting, preset shapes,
/// gradients, strokes, lines with arrowheads, images (cropped), tables, transitions and animations as far as
/// PowerPoint has them. Fonts go by name (files can't be embedded). An element that can't be written as itself
/// goes in as a picture of it.
enum PPTXExporter {
    /// EMU per slide point: 1920 slide points span PowerPoint's 13.333 in (12,192,000 EMU).
    static let emu = 6350.0
    static let slideWidth = 12_192_000
    static let slideHeight = 6_858_000

    static func export(title: String, slides: [SlideContent], deck: UUID) throws -> URL {
        let url = try SlidesFiles.exportFolder().appending(path: SlidesFiles.fileName(title, ext: "pptx"))
        try write(title: title, slides: slides, deck: deck, to: url)
        return url
    }

    static func write(title: String, slides: [SlideContent], deck: UUID, to url: URL) throws {
        let zip = try ZipWriter(url: url)
        var media = MediaStore(deck: deck)
        try zip.addText("[Content_Types].xml", contentTypes(slides: slides.count))
        try zip.addText("_rels/.rels", rootRels)
        try zip.addText("docProps/app.xml", appProps(slides: slides.count))
        try zip.addText("docProps/core.xml", coreProps(title: title))
        try zip.addText("ppt/presentation.xml", presentation(slides: slides.count))
        try zip.addText("ppt/_rels/presentation.xml.rels", presentationRels(slides: slides.count))
        try zip.addText("ppt/presProps.xml", presProps)
        try zip.addText("ppt/viewProps.xml", viewProps)
        try zip.addText("ppt/tableStyles.xml", tableStyles)
        try zip.addText("ppt/theme/theme1.xml", theme)
        try zip.addText("ppt/slideMasters/slideMaster1.xml", slideMaster)
        try zip.addText("ppt/slideMasters/_rels/slideMaster1.xml.rels", slideMasterRels)
        try zip.addText("ppt/slideLayouts/slideLayout1.xml", slideLayout)
        try zip.addText("ppt/slideLayouts/_rels/slideLayout1.xml.rels", slideLayoutRels)
        for (index, slide) in slides.enumerated() {
            try autoreleasepool {
                var writer = SlideWriter(deck: deck, media: media)
                let xml = writer.slideXML(slide)
                media = writer.media
                try zip.addText("ppt/slides/slide\(index + 1).xml", xml)
                try zip.addText("ppt/slides/_rels/slide\(index + 1).xml.rels", writer.relsXML())
                // Pictures are written once, as each slide first uses them, and let go of.
                for (path, data) in media.takePending() {
                    try zip.add("ppt/media/\(path)", data)
                }
            }
        }
        try zip.finish()
    }

    // MARK: Package parts

    static let header = #"<?xml version="1.0" encoding="UTF-8" standalone="yes"?>"#
    static let ns = #"xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main""#

    static func contentTypes(slides: Int) -> String {
        let slideOverrides = (1...max(slides, 1)).prefix(slides).map {
            #"<Override PartName="/ppt/slides/slide\#($0).xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>"#
        }.joined()
        return header + #"<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">"#
            + #"<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>"#
            + #"<Default Extension="xml" ContentType="application/xml"/>"#
            + #"<Default Extension="png" ContentType="image/png"/>"#
            + #"<Default Extension="jpg" ContentType="image/jpeg"/>"#
            + #"<Default Extension="jpeg" ContentType="image/jpeg"/>"#
            + #"<Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/>"#
            + #"<Override PartName="/ppt/presProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presProps+xml"/>"#
            + #"<Override PartName="/ppt/viewProps.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.viewProps+xml"/>"#
            + #"<Override PartName="/ppt/tableStyles.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.tableStyles+xml"/>"#
            + #"<Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>"#
            + #"<Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/>"#
            + #"<Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/>"#
            + #"<Override PartName="/docProps/app.xml" ContentType="application/vnd.openxmlformats-officedocument.extended-properties+xml"/>"#
            + #"<Override PartName="/docProps/core.xml" ContentType="application/vnd.openxmlformats-package.core-properties+xml"/>"#
            + slideOverrides
            + "</Types>"
    }

    static let rootRels = header
        + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        + #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="ppt/presentation.xml"/>"#
        + #"<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties" Target="docProps/core.xml"/>"#
        + #"<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/extended-properties" Target="docProps/app.xml"/>"#
        + "</Relationships>"

    static func appProps(slides: Int) -> String {
        header + #"<Properties xmlns="http://schemas.openxmlformats.org/officeDocument/2006/extended-properties"><Application>Slides</Application><Slides>\#(slides)</Slides></Properties>"#
    }

    static func coreProps(title: String) -> String {
        let date = ISO8601DateFormatter().string(from: .now)
        return header
            + #"<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:dcterms="http://purl.org/dc/terms/" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">"#
            + "<dc:title>\(escape(title))</dc:title>"
            + #"<dcterms:created xsi:type="dcterms:W3CDTF">\#(date)</dcterms:created>"#
            + #"<dcterms:modified xsi:type="dcterms:W3CDTF">\#(date)</dcterms:modified>"#
            + "</cp:coreProperties>"
    }

    static func presentation(slides: Int) -> String {
        let ids = (0..<slides).map { #"<p:sldId id="\#(256 + $0)" r:id="rId\#($0 + 10)"/>"# }.joined()
        return header + "<p:presentation \(ns) saveSubsetFonts=\"1\">"
            + #"<p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst>"#
            + "<p:sldIdLst>\(ids)</p:sldIdLst>"
            + #"<p:sldSz cx="\#(slideWidth)" cy="\#(slideHeight)"/><p:notesSz cx="6858000" cy="9144000"/>"#
            + "</p:presentation>"
    }

    static func presentationRels(slides: Int) -> String {
        let slideRels = (0..<slides).map {
            #"<Relationship Id="rId\#($0 + 10)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" Target="slides/slide\#($0 + 1).xml"/>"#
        }.joined()
        return header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
            + #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="slideMasters/slideMaster1.xml"/>"#
            + #"<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="theme/theme1.xml"/>"#
            + #"<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/presProps" Target="presProps.xml"/>"#
            + #"<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/viewProps" Target="viewProps.xml"/>"#
            + #"<Relationship Id="rId5" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/tableStyles" Target="tableStyles.xml"/>"#
            + slideRels + "</Relationships>"
    }

    static let presProps = header + "<p:presentationPr \(ns)/>"
    static let viewProps = header + "<p:viewPr \(ns)><p:gridSpacing cx=\"76200\" cy=\"76200\"/></p:viewPr>"
    static let tableStyles = header + #"<a:tblStyleLst xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" def="{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"/>"#

    static let emptyTree = #"<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>"#

    static let slideMaster = header + "<p:sldMaster \(ns)>"
        + #"<p:cSld><p:bg><p:bgRef idx="1001"><a:schemeClr val="bg1"/></p:bgRef></p:bg><p:spTree>\#(emptyTree)</p:spTree></p:cSld>"#
        + #"<p:clrMap bg1="lt1" tx1="dk1" bg2="lt2" tx2="dk2" accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" hlink="hlink" folHlink="folHlink"/>"#
        + #"<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="rId1"/></p:sldLayoutIdLst>"#
        + #"<p:txStyles><p:titleStyle><a:lvl1pPr><a:defRPr sz="4400"/></a:lvl1pPr></p:titleStyle><p:bodyStyle><a:lvl1pPr><a:defRPr sz="1800"/></a:lvl1pPr></p:bodyStyle><p:otherStyle><a:lvl1pPr><a:defRPr sz="1800"/></a:lvl1pPr></p:otherStyle></p:txStyles>"#
        + "</p:sldMaster>"

    static let slideMasterRels = header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        + #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>"#
        + #"<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/theme" Target="../theme/theme1.xml"/>"#
        + "</Relationships>"

    static let slideLayout = header + "<p:sldLayout \(ns) type=\"blank\" preserve=\"1\">"
        + #"<p:cSld name="Blank"><p:spTree>\#(emptyTree)</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"#
        + "</p:sldLayout>"

    static let slideLayoutRels = header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        + #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideMaster" Target="../slideMasters/slideMaster1.xml"/>"#
        + "</Relationships>"

    static let theme: String = {
        func solid(_ hex: String) -> String { #"<a:solidFill><a:srgbClr val="\#(hex)"/></a:solidFill>"# }
        let colors = [("dk1", "000000"), ("lt1", "FFFFFF"), ("dk2", "1F2937"), ("lt2", "F3F4F6"), ("accent1", "02B9B9"),
                      ("accent2", "2563EB"), ("accent3", "F5A524"), ("accent4", "E5484D"), ("accent5", "30A46C"),
                      ("accent6", "8E4EC6"), ("hlink", "2563EB"), ("folHlink", "8E4EC6")]
            .map { "<a:\($0.0)><a:srgbClr val=\"\($0.1)\"/></a:\($0.0)>" }.joined()
        let fonts = #"<a:latin typeface="Helvetica Neue"/><a:ea typeface="Hiragino Sans"/><a:cs typeface=""/>"#
        let line = #"<a:ln w="9525">\#(solid("000000"))</a:ln>"#
        return header + #"<a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Slides">"#
            + #"<a:themeElements><a:clrScheme name="Slides">\#(colors)</a:clrScheme>"#
            + #"<a:fontScheme name="Slides"><a:majorFont>\#(fonts)</a:majorFont><a:minorFont>\#(fonts)</a:minorFont></a:fontScheme>"#
            + #"<a:fmtScheme name="Slides"><a:fillStyleLst>\#(solid("FFFFFF"))\#(solid("F3F4F6"))\#(solid("E5E7EB"))</a:fillStyleLst>"#
            + "<a:lnStyleLst>\(line)\(line)\(line)</a:lnStyleLst>"
            + "<a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst>"
            + #"<a:bgFillStyleLst>\#(solid("FFFFFF"))\#(solid("F3F4F6"))\#(solid("E5E7EB"))</a:bgFillStyleLst></a:fmtScheme>"#
            + "</a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>"
    }()

    static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&apos;"
            default:
                // Characters XML 1.0 doesn't allow are dropped.
                let value = scalar.value
                if value == 0x9 || value == 0xA || value == 0xD || (value >= 0x20 && value != 0xFFFE && value != 0xFFFF) {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
    }
}

/// The pictures in the package: each asset once, written out as the slide that first uses it is done.
struct MediaStore {
    let deck: UUID
    private var names: [String: String] = [:]
    private var pending: [(String, Data)] = []

    init(deck: UUID) {
        self.deck = deck
    }

    /// The media file name for an asset, or nil when its file is gone.
    mutating func name(for asset: String) -> String? {
        if let name = names[asset] { return name }
        guard let data = try? Data(contentsOf: SlidesFiles.asset(asset, deck: deck)) else { return nil }
        let ext = (asset as NSString).pathExtension.lowercased() == "png" ? "png" : "jpg"
        let name = "image\(names.count + 1).\(ext)"
        names[asset] = name
        pending.append((name, data))
        return name
    }

    /// A picture made during export (an element drawn as a bitmap).
    mutating func add(png data: Data) -> String {
        let name = "image\(names.count + 1).png"
        names["generated-\(UUID().uuidString)"] = name
        pending.append((name, data))
        return name
    }

    mutating func takePending() -> [(String, Data)] {
        defer { pending = [] }
        return pending
    }
}

/// One slide's XML and its relationships.
struct SlideWriter {
    let deck: UUID
    var media: MediaStore
    private var rels: [(id: String, target: String)] = []
    private var nextShapeID = 2
    private var shapeIDs: [UUID: Int] = [:]

    init(deck: UUID, media: MediaStore) {
        self.deck = deck
        self.media = media
    }

    private typealias X = PPTXExporter

    func relsXML() -> String {
        var xml = X.header + #"<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">"#
        xml += #"<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slideLayout" Target="../slideLayouts/slideLayout1.xml"/>"#
        for rel in rels {
            xml += #"<Relationship Id="\#(rel.id)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/\#(rel.target)"/>"#
        }
        return xml + "</Relationships>"
    }

    private mutating func relationship(for mediaName: String) -> String {
        if let existing = rels.first(where: { $0.target == mediaName }) { return existing.id }
        let id = "rId\(rels.count + 2)"
        rels.append((id, mediaName))
        return id
    }

    mutating func slideXML(_ slide: SlideContent) -> String {
        var tree = ""
        for element in slide.elements {
            tree += elementXML(element)
        }
        return X.header + "<p:sld \(X.ns)><p:cSld>"
            + backgroundXML(slide.background)
            + "<p:spTree>\(X.emptyTree)\(tree)</p:spTree></p:cSld>"
            + "<p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr>"
            + transitionXML(slide.transition)
            + timingXML(slide)
            + "</p:sld>"
    }

    // MARK: Units

    private func e(_ value: Double) -> Int { Int((value * X.emu).rounded()) }

    private func xfrm(_ rect: CGRect, rotation: Double, flipH: Bool = false, flipV: Bool = false, tag: String = "a:xfrm") -> String {
        var attributes = ""
        let rot = Int((rotation * 60000).rounded()) % 21_600_000
        if rot != 0 { attributes += " rot=\"\(rot < 0 ? rot + 21_600_000 : rot)\"" }
        if flipH { attributes += " flipH=\"1\"" }
        if flipV { attributes += " flipV=\"1\"" }
        return "<\(tag)\(attributes)><a:off x=\"\(e(Double(rect.minX)))\" y=\"\(e(Double(rect.minY)))\"/><a:ext cx=\"\(max(e(Double(rect.width)), 1))\" cy=\"\(max(e(Double(rect.height)), 1))\"/></\(tag)>"
    }

    private func color(_ color: RGBA, opacity: Double = 1) -> String {
        let alpha = Int((min(max(color.a * opacity, 0), 1) * 100_000).rounded())
        return alpha >= 100_000
            ? "<a:srgbClr val=\"\(color.hexString)\"/>"
            : "<a:srgbClr val=\"\(color.hexString)\"><a:alpha val=\"\(alpha)\"/></a:srgbClr>"
    }

    private func solid(_ rgba: RGBA, opacity: Double = 1) -> String {
        "<a:solidFill>\(color(rgba, opacity: opacity))</a:solidFill>"
    }

    private func gradient(_ gradient: LinearGradientFill, opacity: Double) -> String {
        let stops = gradient.sortedStops.map {
            "<a:gs pos=\"\(Int((min(max($0.location, 0), 1) * 100_000).rounded()))\">\(color($0.color, opacity: opacity))</a:gs>"
        }.joined()
        var angle = gradient.angle.truncatingRemainder(dividingBy: 360)
        if angle < 0 { angle += 360 }
        return "<a:gradFill rotWithShape=\"1\"><a:gsLst>\(stops)</a:gsLst><a:lin ang=\"\(Int((angle * 60000).rounded()))\" scaled=\"0\"/></a:gradFill>"
    }

    /// An image filling a box: cut to the box's shape (fill) or fitted inside it (fit).
    private mutating func blipFill(_ ref: ImageRef, box: CGSize, opacity: Double, tag: String = "a:blipFill") -> String? {
        guard let name = media.name(for: ref.asset) else { return nil }
        let rel = relationship(for: name)
        let alpha = opacity < 0.999 ? "<a:alphaModFix amt=\"\(Int((opacity * 100_000).rounded()))\"/>" : ""
        var placement = "<a:stretch><a:fillRect/></a:stretch>"
        var source = ""
        if let pixels = SlideAssets.pixelSize(ref.asset, deck: deck), pixels.width > 0, pixels.height > 0, box.width > 0, box.height > 0 {
            let imageAspect = Double(pixels.width / pixels.height)
            let boxAspect = Double(box.width / box.height)
            if ref.mode == .stretch {
                // As it is, stretched to the box.
            } else if ref.mode == .fill {
                var cut = CropInsets()
                if imageAspect > boxAspect {
                    let keep = boxAspect / imageAspect
                    cut.left = (1 - keep) / 2
                    cut.right = cut.left
                } else {
                    let keep = imageAspect / boxAspect
                    cut.top = (1 - keep) / 2
                    cut.bottom = cut.top
                }
                source = srcRect(cut)
            } else {
                var inset = CropInsets()
                if imageAspect > boxAspect {
                    inset.top = (1 - boxAspect / imageAspect) / 2
                    inset.bottom = inset.top
                } else {
                    inset.left = (1 - imageAspect / boxAspect) / 2
                    inset.right = inset.left
                }
                placement = "<a:stretch><a:fillRect l=\"\(pct(inset.left))\" t=\"\(pct(inset.top))\" r=\"\(pct(inset.right))\" b=\"\(pct(inset.bottom))\"/></a:stretch>"
            }
        }
        return "<\(tag) rotWithShape=\"1\"><a:blip r:embed=\"\(rel)\">\(alpha)</a:blip>\(source)\(placement)</\(tag)>"
    }

    private func pct(_ fraction: Double) -> Int { Int((fraction * 100_000).rounded()) }

    private func srcRect(_ crop: CropInsets) -> String {
        guard !crop.isEmpty else { return "" }
        return "<a:srcRect l=\"\(pct(crop.left))\" t=\"\(pct(crop.top))\" r=\"\(pct(crop.right))\" b=\"\(pct(crop.bottom))\"/>"
    }

    private mutating func fillXML(_ fill: Fill, box: CGSize, opacity: Double) -> String {
        switch fill {
        case .none: return "<a:noFill/>"
        case .solid(let rgba): return solid(rgba, opacity: opacity)
        case .gradient(let value): return gradient(value, opacity: opacity)
        case .image(let ref): return blipFill(ref, box: box, opacity: opacity) ?? "<a:noFill/>"
        }
    }

    private func lineXML(_ stroke: Stroke?, opacity: Double, head: Bool = false, tail: Bool = false) -> String {
        guard let stroke, stroke.width > 0 else { return "<a:ln><a:noFill/></a:ln>" }
        let dash: String = switch stroke.dash {
        case .solid: ""
        case .dash: "<a:prstDash val=\"dash\"/>"
        case .dot: "<a:prstDash val=\"sysDot\"/>"
        }
        let headEnd = head ? "<a:headEnd type=\"triangle\" w=\"med\" len=\"med\"/>" : ""
        let tailEnd = tail ? "<a:tailEnd type=\"triangle\" w=\"med\" len=\"med\"/>" : ""
        let cap = stroke.dash == .dot ? " cap=\"rnd\"" : ""
        return "<a:ln w=\"\(e(stroke.width))\"\(cap)>\(solid(stroke.color, opacity: opacity))\(dash)<a:round/>\(headEnd)\(tailEnd)</a:ln>"
    }

    // MARK: Slide parts

    private mutating func backgroundXML(_ background: SlideBackground) -> String {
        let fill: String
        switch background {
        case .solid(let rgba): fill = solid(rgba)
        case .gradient(let value): fill = gradient(value, opacity: 1)
        case .image(let ref): fill = blipFill(ref, box: SlideContent.size, opacity: 1) ?? solid(.white)
        }
        return "<p:bg><p:bgPr>\(fill)<a:effectLst/></p:bgPr></p:bg>"
    }

    /// PowerPoint's direction for a side the slide comes from: it moves away from that side.
    static func direction(_ angle: Double) -> String {
        var normalized = angle.truncatingRemainder(dividingBy: 360)
        if normalized < 0 { normalized += 360 }
        switch Int((normalized / 90).rounded()) % 4 {
        case 0: return "l"
        case 1: return "u"
        case 2: return "r"
        default: return "d"
        }
    }

    private func transitionXML(_ transition: SlideTransition) -> String {
        let effect: String
        switch transition.kind {
        case .none: return ""
        case .fade: effect = "<p:fade/>"
        case .push: effect = "<p:push dir=\"\(Self.direction(transition.angle))\"/>"
        case .cover: effect = "<p:cover dir=\"\(Self.direction(transition.angle))\"/>"
        case .zoom: effect = "<p:zoom dir=\"\(transition.zoomOut ? "out" : "in")\"/>"
        }
        let speed = transition.duration < 0.4 ? "fast" : transition.duration < 0.9 ? "med" : "slow"
        return "<p:transition spd=\"\(speed)\">\(effect)</p:transition>"
    }

    // MARK: Elements

    private mutating func shapeID(for element: SlideElement) -> Int {
        let id = nextShapeID
        nextShapeID += 1
        shapeIDs[element.id] = id
        return id
    }

    private mutating func elementXML(_ element: SlideElement) -> String {
        let id = shapeID(for: element)
        let frame = element.frame.cg
        switch element.content {
        case .text(let box):
            return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"Text \(id)\"/><p:cNvSpPr txBox=\"1\"/><p:nvPr/></p:nvSpPr>"
                + "<p:spPr>\(xfrm(frame, rotation: element.rotation))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom><a:noFill/></p:spPr>"
                + textBody(box.text, opacity: element.opacity, inset: 0, tag: "p:txBody")
                + "</p:sp>"
        case .shape(let shape):
            let geometry = presetGeometry(shape, size: frame.size)
            let fill = fillXML(shape.fill, box: frame.size, opacity: element.opacity)
            var effects = "<a:effectLst/>"
            if let shadow = shape.shadow {
                let distance = hypot(shadow.x, shadow.y)
                var direction = atan2(shadow.y, shadow.x) * 180 / .pi
                if direction < 0 { direction += 360 }
                effects = "<a:effectLst><a:outerShdw blurRad=\"\(e(shadow.blur))\" dist=\"\(e(distance))\" dir=\"\(Int((direction * 60000).rounded()))\" algn=\"ctr\" rotWithShape=\"0\">\(color(shadow.color, opacity: element.opacity))</a:outerShdw></a:effectLst>"
            }
            return "<p:sp><p:nvSpPr><p:cNvPr id=\"\(id)\" name=\"Shape \(id)\"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>"
                + "<p:spPr>\(xfrm(frame, rotation: element.rotation))\(geometry)\(fill)\(lineXML(shape.stroke, opacity: element.opacity))\(effects)</p:spPr>"
                + "</p:sp>"
        case .line(let line):
            let start = line.start.cg
            let end = line.end.cg
            let rect = CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y))
            return "<p:cxnSp><p:nvCxnSpPr><p:cNvPr id=\"\(id)\" name=\"Line \(id)\"/><p:cNvCxnSpPr/><p:nvPr/></p:nvCxnSpPr>"
                + "<p:spPr>\(xfrm(rect, rotation: 0, flipH: end.x < start.x, flipV: end.y < start.y))<a:prstGeom prst=\"line\"><a:avLst/></a:prstGeom>"
                + lineXML(line.stroke, opacity: element.opacity, head: line.startArrow, tail: line.endArrow)
                + "</p:spPr></p:cxnSp>"
        case .image(let image):
            return pictureXML(image, element: element, id: id) ?? rasterized(element, id: id)
        case .table(let table):
            return tableXML(table, element: element, id: id)
        }
    }

    private func presetGeometry(_ shape: ShapeElement, size: CGSize) -> String {
        let short = Double(max(min(size.width, size.height), 1))
        switch shape.kind {
        case .rect: return "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>"
        case .roundRect:
            let adj = Int((min(shape.cornerRadius / short, 0.5) * 100_000).rounded())
            return "<a:prstGeom prst=\"roundRect\"><a:avLst><a:gd name=\"adj\" fmla=\"val \(adj)\"/></a:avLst></a:prstGeom>"
        case .ellipse: return "<a:prstGeom prst=\"ellipse\"><a:avLst/></a:prstGeom>"
        case .triangle: return "<a:prstGeom prst=\"triangle\"><a:avLst/></a:prstGeom>"
        case .star: return "<a:prstGeom prst=\"star5\"><a:avLst/></a:prstGeom>"
        case .arrow:
            let head = Int((0.4 * Double(size.width) / short * 100_000).rounded())
            return "<a:prstGeom prst=\"rightArrow\"><a:avLst><a:gd name=\"adj1\" fmla=\"val 50000\"/><a:gd name=\"adj2\" fmla=\"val \(head)\"/></a:avLst></a:prstGeom>"
        }
    }

    /// The image cut by its crop, fitted or filling its frame, with rounded corners when it has them.
    private mutating func pictureXML(_ image: ImageElement, element: SlideElement, id: Int) -> String? {
        guard let name = media.name(for: image.asset), let pixels = SlideAssets.pixelSize(image.asset, deck: deck) else { return nil }
        let rel = relationship(for: name)
        let frame = element.frame.cg
        var crop = image.crop
        let visibleWidth = Double(pixels.width) * max(0.01, 1 - crop.left - crop.right)
        let visibleHeight = Double(pixels.height) * max(0.01, 1 - crop.top - crop.bottom)
        let imageAspect = visibleWidth / visibleHeight
        let boxAspect = Double(frame.width / max(frame.height, 1))
        var placed = frame
        if image.mode == .stretch {
            // Stretched to the frame: the picture as it is, no extra cut.
        } else if image.mode == .fill {
            // Cut a little more from the long sides so the picture keeps its shape in the frame.
            if imageAspect > boxAspect {
                let extra = (1 - boxAspect / imageAspect) * (1 - crop.left - crop.right) / 2
                crop.left += extra
                crop.right += extra
            } else {
                let extra = (1 - imageAspect / boxAspect) * (1 - crop.top - crop.bottom) / 2
                crop.top += extra
                crop.bottom += extra
            }
        } else {
            let width = imageAspect > boxAspect ? Double(frame.width) : Double(frame.height) * imageAspect
            let height = imageAspect > boxAspect ? Double(frame.width) / imageAspect : Double(frame.height)
            placed = CGRect(x: Double(frame.midX) - width / 2, y: Double(frame.midY) - height / 2, width: width, height: height)
        }
        let alpha = element.opacity < 0.999 ? "<a:alphaModFix amt=\"\(pct(element.opacity))\"/>" : ""
        let short = Double(max(min(placed.width, placed.height), 1))
        let geometry = image.cornerRadius > 0
            ? "<a:prstGeom prst=\"roundRect\"><a:avLst><a:gd name=\"adj\" fmla=\"val \(Int((min(image.cornerRadius / short, 0.5) * 100_000).rounded()))\"/></a:avLst></a:prstGeom>"
            : "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom>"
        return "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"Picture \(id)\"/><p:cNvPicPr><a:picLocks noChangeAspect=\"1\"/></p:cNvPicPr><p:nvPr/></p:nvPicPr>"
            + "<p:blipFill><a:blip r:embed=\"\(rel)\">\(alpha)</a:blip>\(srcRect(crop))<a:stretch><a:fillRect/></a:stretch></p:blipFill>"
            + "<p:spPr>\(xfrm(placed, rotation: element.rotation))\(geometry)</p:spPr></p:pic>"
    }

    /// The element as a picture of itself, for anything that can't be written as it is.
    private mutating func rasterized(_ element: SlideElement, id: Int) -> String {
        guard let png = SlideRenderer.image(of: element, deck: deck).pngData() else { return "" }
        let rel = relationship(for: media.add(png: png))
        let padding = Double(SlideRenderer.padding(for: element))
        let frame = element.frame.cg.insetBy(dx: -padding, dy: -padding)
        let alpha = element.opacity < 0.999 ? "<a:alphaModFix amt=\"\(pct(element.opacity))\"/>" : ""
        return "<p:pic><p:nvPicPr><p:cNvPr id=\"\(id)\" name=\"Picture \(id)\"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>"
            + "<p:blipFill><a:blip r:embed=\"\(rel)\">\(alpha)</a:blip><a:stretch><a:fillRect/></a:stretch></p:blipFill>"
            + "<p:spPr>\(xfrm(frame, rotation: element.rotation))<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></p:spPr></p:pic>"
    }

    private func tableXML(_ table: TableElement, element: SlideElement, id: Int) -> String {
        let frame = element.frame.cg
        let columns = (0..<table.columns).map { column in
            "<a:gridCol w=\"\(e(Double(table.cellRect(row: 0, column: column, in: frame.size).width)))\"/>"
        }.joined()
        let border = { (tag: String) -> String in
            table.borderWidth > 0
                ? "<a:\(tag) w=\"\(self.e(table.borderWidth))\">\(self.solid(table.borderColor, opacity: element.opacity))</a:\(tag)>"
                : "<a:\(tag) w=\"0\"><a:noFill/></a:\(tag)>"
        }
        let inset = e(Double(SlideRenderer.cellInset))
        var rows = ""
        for row in 0..<table.rows {
            let height = e(Double(table.cellRect(row: row, column: 0, in: frame.size).height))
            var cells = ""
            for column in 0..<table.columns {
                let cell = table.cells[row][column]
                let anchor = anchorValue(cell.text.vAlign)
                let fill = cell.fill.map { solid($0, opacity: element.opacity) } ?? "<a:noFill/>"
                cells += "<a:tc>" + textBody(cell.text, opacity: element.opacity, inset: nil, tag: "a:txBody")
                    + "<a:tcPr marL=\"\(inset)\" marR=\"\(inset)\" marT=\"\(inset)\" marB=\"\(inset)\" anchor=\"\(anchor)\">"
                    + border("lnL") + border("lnR") + border("lnT") + border("lnB") + fill
                    + "</a:tcPr></a:tc>"
            }
            rows += "<a:tr h=\"\(height)\">\(cells)</a:tr>"
        }
        return "<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id=\"\(id)\" name=\"Table \(id)\"/><p:cNvGraphicFramePr><a:graphicFrameLocks noGrp=\"1\"/></p:cNvGraphicFramePr><p:nvPr/></p:nvGraphicFramePr>"
            + xfrm(frame, rotation: 0, tag: "p:xfrm")
            + "<a:graphic><a:graphicData uri=\"http://schemas.openxmlformats.org/drawingml/2006/table\"><a:tbl><a:tblPr/><a:tblGrid>\(columns)</a:tblGrid>\(rows)</a:tbl></a:graphicData></a:graphic>"
            + "</p:graphicFrame>"
    }

    // MARK: Text

    private func anchorValue(_ align: VAlign) -> String {
        switch align {
        case .top: "t"
        case .middle: "ctr"
        case .bottom: "b"
        }
    }

    /// `inset` nil leaves the margins to the table cell.
    private func textBody(_ text: RichText, opacity: Double, inset: Double?, tag: String) -> String {
        let margins = inset.map { " lIns=\"\(e($0))\" tIns=\"\(e($0))\" rIns=\"\(e($0))\" bIns=\"\(e($0))\"" } ?? ""
        let bodyPr = tag == "p:txBody"
            ? "<a:bodyPr wrap=\"square\"\(margins) anchor=\"\(anchorValue(text.vAlign))\" rtlCol=\"0\"><a:noAutofit/></a:bodyPr>"
            : "<a:bodyPr/>"
        let algn: String = switch text.hAlign {
        case .left: "l"
        case .center: "ctr"
        case .right: "r"
        case .justified: "just"
        }
        let paragraphProperties = "<a:pPr algn=\"\(algn)\"><a:lnSpc><a:spcPct val=\"\(Int((text.lineSpacing * 100_000).rounded()))\"/></a:lnSpc></a:pPr>"
        // Runs split into paragraphs at line breaks.
        var paragraphs: [[TextRun]] = [[]]
        for run in text.runs {
            let pieces = run.text.components(separatedBy: "\n")
            for (index, piece) in pieces.enumerated() {
                if index > 0 { paragraphs.append([]) }
                if !piece.isEmpty { paragraphs[paragraphs.count - 1].append(run.with(piece)) }
            }
        }
        let base = text.baseRun
        var xml = "<\(tag)>\(bodyPr)<a:lstStyle/>"
        for paragraph in paragraphs {
            xml += "<a:p>\(paragraphProperties)"
            for run in paragraph {
                xml += "<a:r>\(runProperties(run, text: text, opacity: opacity, tag: "a:rPr"))<a:t>\(X.escape(run.text))</a:t></a:r>"
            }
            xml += runProperties(paragraph.last ?? base, text: text, opacity: opacity, tag: "a:endParaRPr")
            xml += "</a:p>"
        }
        return xml + "</\(tag)>"
    }

    private func runProperties(_ run: TextRun, text: RichText, opacity: Double, tag: String) -> String {
        var attributes = " lang=\"ja-JP\" sz=\"\(max(100, Int((run.size * 50).rounded())))\""
        if run.bold { attributes += " b=\"1\"" }
        if run.italic { attributes += " i=\"1\"" }
        if run.underline { attributes += " u=\"sng\"" }
        if run.strike { attributes += " strike=\"sngStrike\"" }
        if text.charSpacing != 0 { attributes += " spc=\"\(Int((text.charSpacing * 50).rounded()))\"" }
        let face = X.escape(Self.typeface(run.font))
        let eastAsian = run.font.hasPrefix("System") ? "Hiragino Sans" : face
        var outline = ""
        if let stroke = text.outline, stroke.width > 0 {
            outline = "<a:ln w=\"\(e(stroke.width))\">\(solid(stroke.color, opacity: opacity))</a:ln>"
        }
        var effects = ""
        if let shadow = text.shadow {
            var direction = atan2(shadow.y, shadow.x) * 180 / .pi
            if direction < 0 { direction += 360 }
            effects = "<a:effectLst><a:outerShdw blurRad=\"\(e(shadow.blur))\" dist=\"\(e(hypot(shadow.x, shadow.y)))\" dir=\"\(Int((direction * 60000).rounded()))\" algn=\"ctr\" rotWithShape=\"0\">\(color(shadow.color, opacity: opacity))</a:outerShdw></a:effectLst>"
        }
        return "<\(tag)\(attributes) dirty=\"0\">\(outline)\(solid(run.color, opacity: opacity))\(effects)<a:latin typeface=\"\(face)\"/><a:ea typeface=\"\(eastAsian)\"/><a:cs typeface=\"\(face)\"/></\(tag)>"
    }

    /// A family name PowerPoint can look for.
    static func typeface(_ font: String) -> String {
        if font.hasPrefix("System") || font.isEmpty { return "Helvetica Neue" }
        return UIFont(name: font, size: 12)?.familyName ?? font
    }

    // MARK: Animations

    private func timingXML(_ slide: SlideContent) -> String {
        let plan = AnimationPlan(slide)
        guard !plan.auto.isEmpty || !plan.taps.isEmpty else { return "" }
        let ids = IDCounter(start: 2)
        var steps = ""
        let groups: [(items: [AnimationPlan.Timed], auto: Bool)] = (plan.auto.isEmpty ? [] : [(plan.auto, true)]) + plan.taps.map { ($0, false) }
        for group in groups {
            let outer = ids.next()
            let inner = ids.next()
            var effects = ""
            for (position, item) in group.items.enumerated() {
                guard let spid = shapeIDs[item.animation.elementID] else { continue }
                let nodeType: String = position == 0 && !group.auto
                    ? "clickEffect"
                    : (item.animation.start == .afterPrevious ? "afterEffect" : "withEffect")
                effects += effectXML(item.animation, spid: spid, delay: Int((item.start * 1000).rounded()), nodeType: nodeType, ids: ids)
            }
            let condition = group.auto
                ? "<p:cond delay=\"indefinite\"/><p:cond evt=\"onBegin\" delay=\"0\"><p:tn val=\"2\"/></p:cond>"
                : "<p:cond delay=\"indefinite\"/>"
            steps += "<p:par><p:cTn id=\"\(outer)\" fill=\"hold\"><p:stCondLst>\(condition)</p:stCondLst><p:childTnLst>"
                + "<p:par><p:cTn id=\"\(inner)\" fill=\"hold\"><p:stCondLst><p:cond delay=\"0\"/></p:stCondLst><p:childTnLst>\(effects)</p:childTnLst></p:cTn></p:par>"
                + "</p:childTnLst></p:cTn></p:par>"
        }
        return "<p:timing><p:tnLst><p:par><p:cTn id=\"1\" dur=\"indefinite\" restart=\"never\" nodeType=\"tmRoot\"><p:childTnLst>"
            + "<p:seq concurrent=\"1\" nextAc=\"seek\"><p:cTn id=\"2\" dur=\"indefinite\" nodeType=\"mainSeq\"><p:childTnLst>\(steps)</p:childTnLst></p:cTn>"
            + "<p:prevCondLst><p:cond evt=\"onPrev\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:prevCondLst>"
            + "<p:nextCondLst><p:cond evt=\"onNext\" delay=\"0\"><p:tgtEl><p:sldTgt/></p:tgtEl></p:cond></p:nextCondLst></p:seq>"
            + "</p:childTnLst></p:cTn></p:par></p:tnLst></p:timing>"
    }

    private func effectXML(_ animation: ElementAnimation, spid: Int, delay: Int, nodeType: String, ids: IDCounter) -> String {
        let entrance = animation.category == .entrance
        let duration = max(1, Int((animation.duration * 1000).rounded()))
        let target = "<p:tgtEl><p:spTgt spid=\"\(spid)\"/></p:tgtEl>"
        func visibility(_ value: String, at time: Int) -> String {
            "<p:set><p:cBhvr><p:cTn id=\"\(ids.next())\" dur=\"1\" fill=\"hold\"><p:stCondLst><p:cond delay=\"\(time)\"/></p:stCondLst></p:cTn>\(target)<p:attrNameLst><p:attrName>style.visibility</p:attrName></p:attrNameLst></p:cBhvr><p:to><p:strVal val=\"\(value)\"/></p:to></p:set>"
        }
        func motion(_ attribute: String, from: String, to: String) -> String {
            "<p:anim calcmode=\"lin\" valueType=\"num\"><p:cBhvr additive=\"base\"><p:cTn id=\"\(ids.next())\" dur=\"\(duration)\" fill=\"hold\"/>\(target)<p:attrNameLst><p:attrName>\(attribute)</p:attrName></p:attrNameLst></p:cBhvr>"
                + "<p:tavLst><p:tav tm=\"0\"><p:val><p:strVal val=\"\(from)\"/></p:val></p:tav><p:tav tm=\"100000\"><p:val><p:strVal val=\"\(to)\"/></p:val></p:tav></p:tavLst></p:anim>"
        }
        let presetID: Int
        var subtype = 0
        var behaviors = ""
        if entrance { behaviors += visibility("visible", at: 0) }
        switch animation.effect {
        case .appear, .move:
            // PowerPoint has no move between slides as an element effect: it appears.
            presetID = 1
        case .fade:
            presetID = 10
            behaviors += "<p:animEffect transition=\"\(entrance ? "in" : "out")\" filter=\"fade\"><p:cBhvr><p:cTn id=\"\(ids.next())\" dur=\"\(duration)\"/>\(target)</p:cBhvr></p:animEffect>"
        case .slideIn:
            presetID = 2
            let side = Self.direction(animation.angle)
            let (attribute, outside, inside): (String, String, String) = switch side {
            case "d": ("ppt_y", "0-#ppt_h/2", "#ppt_y")
            case "u": ("ppt_y", "1+#ppt_h/2", "#ppt_y")
            case "r": ("ppt_x", "0-#ppt_w/2", "#ppt_x")
            default: ("ppt_x", "1+#ppt_w/2", "#ppt_x")
            }
            subtype = switch side {
            case "d": 1
            case "u": 4
            case "r": 8
            default: 2
            }
            behaviors += entrance ? motion(attribute, from: outside, to: inside) : motion(attribute, from: inside, to: outside)
        case .zoom:
            presetID = 53
            let small = "0"
            let bigWidth = "#ppt_w*2.5"
            let bigHeight = "#ppt_h*2.5"
            let fromWidth = animation.zoomOut ? bigWidth : small
            let fromHeight = animation.zoomOut ? bigHeight : small
            behaviors += entrance
                ? motion("ppt_w", from: fromWidth, to: "#ppt_w") + motion("ppt_h", from: fromHeight, to: "#ppt_h")
                : motion("ppt_w", from: "#ppt_w", to: animation.zoomOut ? small : bigWidth) + motion("ppt_h", from: "#ppt_h", to: animation.zoomOut ? small : bigHeight)
            behaviors += "<p:animEffect transition=\"\(entrance ? "in" : "out")\" filter=\"fade\"><p:cBhvr><p:cTn id=\"\(ids.next())\" dur=\"\(duration)\"/>\(target)</p:cBhvr></p:animEffect>"
        }
        if !entrance { behaviors += visibility("hidden", at: max(duration - 1, 0)) }
        let effectID = ids.next()
        return "<p:par><p:cTn id=\"\(effectID)\" presetID=\"\(presetID)\" presetClass=\"\(entrance ? "entr" : "exit")\" presetSubtype=\"\(subtype)\" fill=\"hold\" grpId=\"0\" nodeType=\"\(nodeType)\">"
            + "<p:stCondLst><p:cond delay=\"\(delay)\"/></p:stCondLst><p:childTnLst>\(behaviors)</p:childTnLst></p:cTn></p:par>"
    }
}

/// Numbers the timing nodes of a slide.
final class IDCounter {
    private var value: Int

    init(start: Int) {
        value = start
    }

    func next() -> Int {
        value += 1
        return value
    }
}
