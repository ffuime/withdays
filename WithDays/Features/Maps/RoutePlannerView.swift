import SwiftUI

/// The route FAB's screen: pick where to start (the current location at first) and where to go,
/// from the current location, the 「照準地」, 「よく使う項目」, history or a search.
struct RoutePlannerView: View {
    let aim: GeoPoint
    var onRoute: (RouteEndpoint, RouteEndpoint) -> Void
    var onClose: () -> Void

    private enum Field {
        case origin, destination
    }

    @Environment(MapsStore.self) private var store
    @State private var origin: RouteEndpoint? = .currentLocation
    @State private var destination: RouteEndpoint?
    @State private var editing: Field = .destination
    @State private var query = ""
    @State private var results: [MapPlace] = []
    @State private var searching = false
    @State private var searchError: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("経路")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("閉じる")
                    }
                }
        }
        .onAppear { focused = true }
    }

    private var content: some View {
        VStack(spacing: 0) {
            endpoints
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(editing == .origin ? "出発地を検索" : "目的地を検索", text: $query)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit(search)
                if searching { ProgressView() }
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .glassEffect(.regular, in: .capsule)
            .padding(.horizontal, 16)

            candidates

            Button {
                guard let origin, let destination else { return }
                onRoute(origin, destination)
            } label: {
                Label("経路を検索", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
            }
            .buttonStyle(.glassProminent)
            .disabled(origin == nil || destination == nil || origin == destination)
            .padding(16)
        }
    }

    // MARK: Parts

    private var endpoints: some View {
        HStack(spacing: 10) {
            VStack(spacing: 8) {
                endpointRow(.origin, label: "出発", value: origin, color: .green)
                endpointRow(.destination, label: "到着", value: destination, color: .red)
            }
            Button {
                let start = origin
                origin = destination
                destination = start
            } label: {
                Image(systemName: "arrow.up.arrow.down")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
        }
    }

    private func endpointRow(_ field: Field, label: String, value: RouteEndpoint?, color: Color) -> some View {
        Button {
            editing = field
            focused = true
        } label: {
            HStack(spacing: 10) {
                Circle().fill(color).frame(width: 10, height: 10)
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(value?.name ?? "選択してください")
                    .foregroundStyle(value == nil ? Color.secondary : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(editing == field ? Color.brand : Color.secondary.opacity(0.3), lineWidth: editing == field ? 2 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var candidates: some View {
        List {
            if let searchError {
                Text(searchError)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            if !results.isEmpty {
                Section("検索結果") {
                    ForEach(results) { place in
                        candidate(place.name, detail: place.address, symbol: "mappin.circle.fill") {
                            pick(.point(name: place.name, location: place.location))
                        }
                    }
                }
            }
            Section {
                candidate("現在地", symbol: "location.fill") { pick(.currentLocation) }
                candidate("地図の照準地", symbol: "scope") { pick(.point(name: "地図の照準地", location: aim)) }
            }
            if !store.saved.isEmpty {
                Section("よく使う項目") {
                    ForEach(store.saved) { place in
                        candidate(place.name, detail: place.address, symbol: "star.fill") {
                            pick(.point(name: place.name, location: place.location))
                        }
                    }
                }
            }
            let places = store.history.filter { $0.kind == .place && $0.location != nil }
            if !places.isEmpty {
                Section("履歴") {
                    ForEach(places) { entry in
                        candidate(entry.text, detail: entry.address, symbol: "clock") {
                            if let location = entry.location { pick(.point(name: entry.text, location: location)) }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
    }

    private func candidate(_ title: String, detail: String? = nil, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.brand)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).foregroundStyle(.primary).lineLimit(1)
                    if let detail {
                        Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private func pick(_ endpoint: RouteEndpoint) {
        switch editing {
        case .origin: origin = endpoint
        case .destination: destination = endpoint
        }
        query = ""
        results = []
        searchError = nil
        // Next, the end still missing; with both set, the keyboard goes away for 「経路を検索」.
        if destination == nil {
            editing = .destination
        } else if origin == nil {
            editing = .origin
        } else {
            focused = false
        }
    }

    private func search() {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        searching = true
        searchError = nil
        Task {
            do {
                results = try await AppleMapsService.search(text, near: aim)
                if results.isEmpty { searchError = "「\(text)」は見つかりませんでした" }
            } catch {
                searchError = error.localizedDescription
            }
            searching = false
        }
    }
}
