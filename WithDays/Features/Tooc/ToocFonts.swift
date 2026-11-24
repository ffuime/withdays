import CoreText
import SwiftUI

// MARK: - The fonts

/// A Japanese font from Google Fonts that tooc can use. It's downloaded when chosen and kept on this device.
struct ToocFontChoice: Identifiable, Hashable {
    let id: String
    /// The family as Google Fonts names it (also the name it's registered under).
    let family: String
    let label: String

    static let all: [ToocFontChoice] = [
        .init(id: "notosansjp", family: "Noto Sans JP", label: "Noto Sans JP"),
        .init(id: "mplusrounded1c", family: "M PLUS Rounded 1c", label: "M PLUS Rounded 1c"),
        .init(id: "zenmarugothic", family: "Zen Maru Gothic", label: "Zen Maru Gothic"),
        .init(id: "kosugimaru", family: "Kosugi Maru", label: "Kosugi Maru"),
        .init(id: "bizudpgothic", family: "BIZ UDPGothic", label: "BIZ UDPGothic"),
        .init(id: "notoserifjp", family: "Noto Serif JP", label: "Noto Serif JP"),
        .init(id: "shipporimincho", family: "Shippori Mincho", label: "Shippori Mincho"),
        .init(id: "kleeone", family: "Klee One", label: "Klee One"),
        .init(id: "yuseimagic", family: "Yusei Magic", label: "Yusei Magic"),
        .init(id: "dotgothic16", family: "DotGothic16", label: "DotGothic16"),
    ]

    static func find(_ id: String?) -> ToocFontChoice? { all.first { $0.id == id } }
}

/// The fonts on this device: downloads them from Google Fonts, keeps them, and registers them for tooc each launch.
@MainActor @Observable
final class ToocFontLibrary {
    static let shared = ToocFontLibrary()

    /// Downloaded and ready (font id → the family name the files registered under).
    private(set) var ready: [String: String] = [:]
    private(set) var downloading: Set<String> = []

    private static var folder: URL {
        let url = URL.applicationSupportDirectory.appending(path: "ToocFonts", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private init() {
        for choice in ToocFontChoice.all {
            let files = Self.files(of: choice.id)
            guard !files.isEmpty else { continue }
            ready[choice.id] = Self.register(files) ?? choice.family
        }
    }

    /// The family to draw with, if that font is on this device.
    func family(_ id: String?) -> String? {
        guard let id else { return nil }
        return ready[id]
    }

    /// Fetches the font's regular and bold files (where it has them) and keeps them.
    func download(_ choice: ToocFontChoice) async throws {
        guard ready[choice.id] == nil, !downloading.contains(choice.id) else { return }
        downloading.insert(choice.id)
        defer { downloading.remove(choice.id) }

        let query = choice.family.replacingOccurrences(of: " ", with: "+")
        guard let cssURL = URL(string: "https://fonts.googleapis.com/css2?family=\(query):wght@400;700") else { return }
        var request = URLRequest(url: cssURL)
        // Without a browser's name, Google Fonts answers with whole TrueType files (not split web fonts).
        request.setValue("WithDays", forHTTPHeaderField: "User-Agent")
        let (cssData, _) = try await URLSession.shared.data(for: request)
        let css = String(decoding: cssData, as: UTF8.self)
        let addresses = Self.fontAddresses(in: css)
        guard !addresses.isEmpty else { throw ToocError("フォントが見つかりませんでした。") }

        var saved: [URL] = []
        for (weight, address) in addresses {
            let (data, response) = try await URLSession.shared.data(from: address)
            guard (response as? HTTPURLResponse)?.statusCode == 200, !data.isEmpty else {
                throw ToocError("フォントをダウンロードできませんでした。")
            }
            let file = Self.folder.appending(path: "\(choice.id)-\(weight).ttf")
            try data.write(to: file, options: .atomic)
            saved.append(file)
        }
        ready[choice.id] = Self.register(saved) ?? choice.family
    }

    /// Takes a font off this device.
    func remove(_ id: String) {
        let files = Self.files(of: id)
        CTFontManagerUnregisterFontURLs(files as CFArray, .process, nil)
        for file in files { try? FileManager.default.removeItem(at: file) }
        ready[id] = nil
    }

    private static func files(of id: String) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.filter { $0.hasPrefix(id + "-") && $0.hasSuffix(".ttf") }
            .sorted()
            .map { folder.appending(path: $0) }
    }

    /// Registers the files for this run of the app, and gives back their family name.
    private static func register(_ files: [URL]) -> String? {
        CTFontManagerRegisterFontURLs(files as CFArray, .process, true, nil)
        for file in files {
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor],
               let family = descriptors.first.flatMap({ CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String }) {
                return family
            }
        }
        return nil
    }

    /// The `font-weight` and `src: url(…)` pairs in Google Fonts' CSS.
    private static func fontAddresses(in css: String) -> [(Int, URL)] {
        css.components(separatedBy: "@font-face").compactMap { block in
            guard let start = block.range(of: "url("), let end = block.range(of: ")", range: start.upperBound..<block.endIndex),
                  let url = URL(string: String(block[start.upperBound..<end.lowerBound])) else { return nil }
            var weight = 400
            if let w = block.range(of: "font-weight:") {
                let digits = block[w.upperBound...].drop { $0 == " " }.prefix { $0.isNumber }
                weight = Int(digits) ?? 400
            }
            return (weight, url)
        }
    }
}

// MARK: - Drawing with it

extension EnvironmentValues {
    /// The family tooc's text is drawn in; nil for the system font.
    @Entry var toocFontFamily: String? = nil
}

/// A font in tooc: like SwiftUI's `Font`, but drawn in the chosen Google font when there is one.
struct ToocFont {
    private enum Base {
        case style(Font.TextStyle)
        case size(CGFloat)
    }

    private var base: Base
    private var weight: Font.Weight?
    private var design: Font.Design?

    private init(_ base: Base, weight: Font.Weight? = nil, design: Font.Design? = nil) {
        self.base = base
        self.weight = weight
        self.design = design
    }

    static let largeTitle = ToocFont(.style(.largeTitle))
    static let title = ToocFont(.style(.title))
    static let title2 = ToocFont(.style(.title2))
    static let title3 = ToocFont(.style(.title3))
    static let headline = ToocFont(.style(.headline))
    static let body = ToocFont(.style(.body))
    static let callout = ToocFont(.style(.callout))
    static let subheadline = ToocFont(.style(.subheadline))
    static let footnote = ToocFont(.style(.footnote))
    static let caption = ToocFont(.style(.caption))
    static let caption2 = ToocFont(.style(.caption2))

    static func system(size: CGFloat, weight: Font.Weight? = nil, design: Font.Design? = nil) -> ToocFont {
        ToocFont(.size(size), weight: weight, design: design)
    }

    func weight(_ weight: Font.Weight) -> ToocFont {
        var font = self
        font.weight = weight
        return font
    }

    func bold() -> ToocFont { weight(.bold) }

    func resolved(_ family: String?) -> Font {
        switch base {
        case .style(let style):
            let weight = weight ?? (style == .headline ? .semibold : nil)
            guard let family, design == nil else {
                var font = Font.system(style, design: design)
                if let weight { font = font.weight(weight) }
                return font
            }
            let font = Font.custom(family, size: Self.size(of: style), relativeTo: style)
            return weight.map { font.weight($0) } ?? font
        case .size(let size):
            guard let family, design == nil else { return .system(size: size, weight: weight ?? .regular, design: design) }
            let font = Font.custom(family, fixedSize: size)
            return weight.map { font.weight($0) } ?? font
        }
    }

    /// Each style's size at the default text size; it grows and shrinks with the system's text size.
    private static func size(of style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}

private struct ToocFontModifier: ViewModifier {
    let font: ToocFont
    @Environment(\.toocFontFamily) private var family

    func body(content: Content) -> some View {
        content.font(font.resolved(family))
    }
}

extension View {
    /// Sets the font, in the Google font chosen in tooc's settings when there is one.
    func toocFont(_ font: ToocFont) -> some View { modifier(ToocFontModifier(font: font)) }
}

// MARK: - Choosing

/// 設定 › トーク › フォント: the system font, or one of the Google fonts (downloaded on the spot).
struct ToocFontSettingsView: View {
    @Environment(ToocStore.self) private var store
    @State private var library = ToocFontLibrary.shared
    @State private var failure: String?

    private var chosen: String? { store.settings.font }

    var body: some View {
        List {
            Section {
                row(id: nil, label: "システム標準", family: nil)
            }
            Section {
                ForEach(ToocFontChoice.all) { choice in
                    row(id: choice.id, label: choice.label, family: library.family(choice.id))
                        .swipeActions(edge: .trailing) {
                            if library.family(choice.id) != nil, chosen != choice.id {
                                Button("削除", systemImage: "trash", role: .destructive) { library.remove(choice.id) }
                            }
                        }
                }
            } header: {
                Text("Google Fonts")
            } footer: {
                Text("選ぶとダウンロードされ、この端末に残ります。使わなくなったフォントは左にスワイプして削除できます。")
            }
        }
        .navigationTitle("フォント")
        .navigationBarTitleDisplayMode(.inline)
        .alert("ダウンロードできませんでした", isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func row(id: String?, label: String, family: String?) -> some View {
        Button {
            choose(id)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(label)
                        .font(family.map { .custom($0, size: 17) } ?? .body)
                        .foregroundStyle(.primary)
                    Text("あいうえお 漢字 tooc 123")
                        .font(family.map { .custom($0, size: 14) } ?? .subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let id, library.downloading.contains(id) {
                    ProgressView()
                } else if chosen == id {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(store.theme.accent)
                } else if id != nil, family == nil {
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("ダウンロード")
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func choose(_ id: String?) {
        guard let id, let choice = ToocFontChoice.find(id) else {
            withAnimation(.snappy) { store.settings.font = nil }
            return
        }
        if library.family(id) != nil {
            withAnimation(.snappy) { store.settings.font = id }
            return
        }
        Task {
            do {
                try await library.download(choice)
                withAnimation(.snappy) { store.settings.font = id }
            } catch {
                failure = (error as? ToocError)?.message ?? error.localizedDescription
            }
        }
    }
}
