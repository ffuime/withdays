import SwiftUI

/// App icons from the App Store (Japan). iOS doesn't let apps list what's installed, so icons are found by searching.
struct SubsStoreApp: Decodable, Identifiable, Hashable {
    let trackId: Int
    let trackName: String
    let artworkUrl100: String?
    let artworkUrl512: String?

    var id: Int { trackId }
    var small: URL? { (artworkUrl100 ?? artworkUrl512).flatMap(URL.init(string:)) }
    var large: URL? { (artworkUrl512 ?? artworkUrl100).flatMap(URL.init(string:)) }
}

enum SubsAppStore {
    private struct Results: Decodable { let results: [SubsStoreApp] }

    private static func fetch(_ path: String, _ items: [URLQueryItem]) async -> [SubsStoreApp] {
        var components = URLComponents(string: "https://itunes.apple.com/" + path)!
        components.queryItems = items + [URLQueryItem(name: "country", value: "jp")]
        guard let url = components.url,
              let response = try? await URLSession.shared.data(from: url),
              let results = try? JSONDecoder().decode(Results.self, from: response.0)
        else { return [] }
        return results.results
    }

    static func search(_ term: String) async -> [SubsStoreApp] {
        await fetch("search", [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: "30"),
        ])
    }

    @MainActor private static var known: [Int: SubsStoreApp] = [:]

    /// Many apps in one request; remembered for the rest of the session.
    @MainActor
    static func lookup(_ ids: [Int]) async -> [Int: SubsStoreApp] {
        let missing = Set(ids).subtracting(known.keys)
        if !missing.isEmpty {
            let found = await fetch("lookup", [URLQueryItem(name: "id", value: missing.map(String.init).joined(separator: ","))])
            for app in found { known[app.trackId] = app }
        }
        return known.filter { ids.contains($0.key) }
    }

    /// The icon, made small for saving with the subscription.
    static func icon(_ app: SubsStoreApp) async -> Data? {
        guard let url = app.large, let image = try? await URLSession.shared.data(from: url) else { return nil }
        return SubsImages.small(image.0)
    }

    @MainActor
    static func icon(id: Int) async -> Data? {
        guard let app = await lookup([id])[id] else { return nil }
        return await icon(app)
    }
}

/// An App Store icon, rounded like on the home screen.
struct SubsRemoteIcon<Placeholder: View>: View {
    let url: URL?
    var size: CGFloat = 40
    @ViewBuilder var placeholder: Placeholder

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
    }
}

/// App Storeから選ぶ: search by name and take that app's icon.
struct SubsAppIconPicker: View {
    var initial: String
    var onPick: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [SubsStoreApp] = []
    @State private var searching = false
    @State private var saving: Int?

    var body: some View {
        NavigationStack {
            List(results) { app in
                Button {
                    take(app)
                } label: {
                    HStack(spacing: 12) {
                        SubsRemoteIcon(url: app.small, size: 44) {
                            RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemFill))
                        }
                        Text(app.trackName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        if saving == app.id { ProgressView() }
                    }
                }
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .overlay {
                if searching && results.isEmpty {
                    ProgressView()
                } else if results.isEmpty {
                    ContentUnavailableView("アプリ名で検索", systemImage: "magnifyingglass",
                                           description: Text("App Store のアイコンを使えます。"))
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "アプリ名")
            .task(id: query) {
                let term = query.trimmingCharacters(in: .whitespaces)
                guard !term.isEmpty else { results = []; return }
                // Wait for the typing to settle.
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                searching = true
                let found = await SubsAppStore.search(term)
                guard !Task.isCancelled else { return }
                results = found
                searching = false
            }
            .navigationTitle("App Storeから選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
            }
            .onAppear { if query.isEmpty { query = initial } }
        }
    }

    private func take(_ app: SubsStoreApp) {
        saving = app.id
        Task {
            if let data = await SubsAppStore.icon(app) {
                onPick(data)
                dismiss()
            }
            saving = nil
        }
    }
}
