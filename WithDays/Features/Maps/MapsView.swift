import CoreLocation
import MapKit
import SwiftUI

/// Maps: Apple's map under the standard search field and navigation bar, the route button bottom right
/// (with 「現在地に戻す」 splitting out of it when the map's middle leaves the current location),
/// and results, a route or a place in standard sheets.
struct MapsView: View {
    var onCalendar: () -> Void

    var body: some View {
        MapsMainView(onCalendar: onCalendar)
    }
}

/// A place opened in Apple's place card.
struct MapsPlaceCard: Identifiable {
    let id = UUID()
    let item: MKMapItem
    let place: MapPlace
}

private enum MapsSheet: Identifiable {
    case results, route, planner
    case place(MapsPlaceCard)

    var id: String {
        switch self {
        case .results: "results"
        case .route: "route"
        case .planner: "planner"
        case .place(let card): "place-\(card.id.uuidString)"
        }
    }
}

// MARK: - Map screen

private struct MapsMainView: View {
    var onCalendar: () -> Void

    @Environment(MapsStore.self) private var store
    @State private var model = MapsScreenModel()
    @State private var searchOpen = false
    @State private var searchText = ""
    @State private var plannerOpen = false
    @State private var card: MapsPlaceCard?
    /// The sheet last put on screen, to tell which one a swipe closed.
    @State private var lastShown: String?
    /// Where the results or route sheet's top is on screen, as it moves.
    @State private var sheetTop: CGFloat?
    /// The map's bottom padding, set when the sheet settles so the map doesn't slide while it's dragged.
    @State private var mapBottom: CGFloat = 0
    @State private var showRecenter = false
    @State private var pendingPoint: GeoPoint?
    @State private var pointName = ""
    @Namespace private var glass

    private static let routeSize: CGFloat = 72
    private static let recenterSize: CGFloat = 56
    private static let buttonGap: CGFloat = 16

    private var currentSheet: MapsSheet? {
        if searchOpen { return nil }
        if let card { return .place(card) }
        if plannerOpen { return .planner }
        if model.route != nil { return .route }
        if model.showingResults { return .results }
        return nil
    }

    /// The results or the route is up, with the map still usable around it.
    private var panelShown: Bool {
        switch currentSheet {
        case .results, .route: true
        default: false
        }
    }

    private var panelDetent: PresentationDetent { model.route != nil ? model.routeDetent : model.resultsDetent }

    private var sheetBinding: Binding<MapsSheet?> {
        Binding {
            currentSheet
        } set: { new in
            // Only a swipe on the planner or a place card closes a sheet; results and routes stay until ✕.
            guard new == nil else { return }
            if lastShown == "planner" {
                plannerOpen = false
            } else if lastShown?.hasPrefix("place") == true {
                card = nil
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            let bottom = geo.safeAreaInsets.bottom
            let screenHeight = geo.size.height + top + bottom
            ZStack {
                mapLayer(top: top)
                    .ignoresSafeArea()
                crosshair(top: top, screenHeight: screenHeight)
                    .ignoresSafeArea()
                buttons(bottom: bottom, screenHeight: screenHeight)
                    .ignoresSafeArea(edges: .bottom)
                if searchOpen {
                    MapsSearchScreen(
                        onPickSaved: { place in
                            closeSearch()
                            model.show(place.asPlace, store: store)
                        },
                        onPickHistory: pickHistory
                    )
                    .background(Color(.systemBackground).ignoresSafeArea())
                    .transition(.opacity)
                }
            }
            .onChange(of: settleKey, initial: true) { _, _ in settleMap(screenHeight: screenHeight) }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onCalendar) {
                    Image(systemName: "calendar")
                }
                .accessibilityLabel("カレンダー")
            }
        }
        .searchable(
            text: $searchText,
            isPresented: $searchOpen,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "場所やジャンルを検索"
        )
        .onSubmit(of: .search) { search(searchText) }
        .animation(.snappy(duration: 0.25), value: searchOpen)
        .sheet(item: sheetBinding) { sheet in
            sheetContent(sheet)
                .onAppear { lastShown = sheet.id }
        }
        .onChange(of: model.awayFromUser, initial: true) { _, away in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) {
                showRecenter = away && model.userLocation != nil
            }
        }
        .task { await trackLocation() }
        .errorAlert($model.errorMessage)
        .alert(
            "よく使う項目に追加",
            isPresented: Binding(get: { pendingPoint != nil }, set: { if !$0 { pendingPoint = nil } })
        ) {
            TextField("名前", text: $pointName)
            Button("追加") {
                guard let point = pendingPoint else { return }
                let name = pointName.trimmingCharacters(in: .whitespaces)
                store.save(SavedPlace(name: name.isEmpty ? "保存した地点" : name, location: point))
            }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("長押しした地点に名前を付けて保存します")
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: pendingPoint) { _, new in new != nil }
    }

    // MARK: Map

    private func mapLayer(top: CGFloat) -> some View {
        AppleMapView(
            places: model.route == nil ? model.results : [],
            selectedID: model.selectedID,
            route: routeOverlay,
            userLocation: model.userLocation,
            padding: UIEdgeInsets(top: top, left: 0, bottom: mapBottom, right: 0),
            command: model.command,
            initialCenter: model.cameraCenter,
            initialMeters: model.meters,
            onCameraChange: { _, away in
                if away != model.awayFromUser { model.awayFromUser = away }
            },
            onCameraIdle: { stop in model.cameraStopped(stop) },
            onLongPress: { point in
                pointName = ""
                pendingPoint = point
            },
            onMarkerTap: { id in
                guard let place = model.results.first(where: { $0.id == id }) else { return }
                model.select(place, store: store)
                if model.resultsDetent == .mapsSmall { model.resultsDetent = .medium }
            },
            onFeatureTap: { feature in
                Task {
                    guard let item = await AppleMapsService.mapItem(for: feature) else { return }
                    let place = AppleMapsService.place(for: item)
                    store.recordPlace(place)
                    card = MapsPlaceCard(item: item, place: place)
                }
            }
        )
    }

    private var routeOverlay: MapRouteOverlay? {
        guard let route = model.route, let origin = route.originPoint, let destination = route.destinationPoint,
              let result = route.result else { return nil }
        return MapRouteOverlay(path: result.path, origin: origin, destination: destination)
    }

    /// A small cross on the 「照準地」: the middle of the map left between the search field and the sheet.
    private func crosshair(top: CGFloat, screenHeight: CGFloat) -> some View {
        GeometryReader { geo in
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(.primary.opacity(0.6))
                .position(x: geo.size.width / 2, y: (top + screenHeight - mapBottom) / 2)
        }
        .allowsHitTesting(false)
        .animation(.snappy, value: mapBottom)
    }

    /// When the sheet settles, after its animation, the map's padding follows (up to half the screen).
    private var settleKey: String { "\(currentSheet?.id ?? "none")-\(panelDetent)-\(sheetTop == nil)" }

    private func settleMap(screenHeight: CGFloat) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(400))
            if panelShown, let sheetTop {
                mapBottom = min(max(screenHeight - sheetTop, 0), screenHeight * 0.5)
            } else if currentSheet == nil {
                mapBottom = 0
            }
        }
    }

    // MARK: Search

    private func search(_ text: String) {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        closeSearch()
        card = nil
        plannerOpen = false
        model.search(query, store: store)
        // Closing the search field can empty it; it keeps showing the word searched for.
        Task { @MainActor in searchText = query }
    }

    private func pickHistory(_ entry: MapsHistoryEntry) {
        switch entry.kind {
        case .query:
            search(entry.text)
        case .place:
            closeSearch()
            let place = MapPlace(
                id: entry.placeID ?? "point-\(entry.id.uuidString)",
                name: entry.text,
                address: entry.address,
                location: entry.location ?? model.aim
            )
            model.show(place, store: store)
            Task { @MainActor in searchText = entry.text }
        }
    }

    private func closeSearch() {
        searchOpen = false
    }

    private func closeResults() {
        model.closeRoute()
        model.closeResults()
        searchText = ""
        sheetTop = nil
    }

    // MARK: Buttons

    /// The route button, with 「現在地に戻す」 splitting up out of it while the map's middle is off the current location.
    private func buttons(bottom: CGFloat, screenHeight: CGFloat) -> some View {
        let hidden = searchOpen || plannerOpen || card != nil || (panelShown && panelDetent == .large)
        let lift: CGFloat = if panelShown, let sheetTop {
            max(screenHeight - sheetTop, 0) + 14
        } else {
            max(bottom, 20) + 14
        }
        // From the route button's middle to 「現在地に戻す」's.
        let split = (Self.routeSize + Self.recenterSize) / 2 + Self.buttonGap
        return GlassEffectContainer(spacing: 12) {
            VStack(spacing: Self.buttonGap) {
                if showRecenter {
                    Button {
                        model.backToUser()
                    } label: {
                        Image(systemName: "location.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.brand)
                            .frame(width: Self.recenterSize, height: Self.recenterSize)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("recenter", in: glass)
                    // It grows out of the route button and sinks back into it, still joined while they're close.
                    .transition(.offset(y: split).combined(with: .scale(scale: 0.45)))
                    .accessibilityLabel("現在地に戻す")
                }
                Button {
                    plannerOpen = true
                } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 30, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: Self.routeSize, height: Self.routeSize)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.tint(Color.brand).interactive(), in: .circle)
                .glassEffectID("route", in: glass)
                .accessibilityLabel("経路検索")
            }
        }
        .padding(.trailing, 16)
        .padding(.bottom, lift)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
        .animation(.snappy(duration: 0.25), value: hidden)
    }

    // MARK: Sheets

    @ViewBuilder
    private func sheetContent(_ sheet: MapsSheet) -> some View {
        switch sheet {
        case .results:
            NavigationStack {
                MapsResultsList(model: model, onDetail: openCard)
                    .navigationTitle(model.resultsTitle ?? "")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: closeResults) { Image(systemName: "xmark") }
                                .accessibilityLabel("閉じる")
                        }
                    }
            }
            .modifier(MapsPanelSheet(detent: $model.resultsDetent, top: $sheetTop))
        case .route:
            NavigationStack {
                MapsRouteContent(model: model)
                    .navigationTitle(model.route?.destination.name ?? "経路")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button {
                                model.closeRoute()
                                if !model.showingResults { closeResults() }
                            } label: {
                                Image(systemName: "xmark")
                            }
                            .accessibilityLabel("閉じる")
                        }
                    }
            }
            .modifier(MapsPanelSheet(detent: $model.routeDetent, top: $sheetTop))
        case .planner:
            RoutePlannerView(
                aim: model.aim,
                onRoute: { origin, destination in
                    plannerOpen = false
                    model.startRoute(from: origin, to: destination)
                },
                onClose: { plannerOpen = false }
            )
            .presentationDetents([.large])
        case .place(let card):
            MapsPlaceCardView(
                card: card,
                onRoute: {
                    self.card = nil
                    model.startRoute(from: .currentLocation, to: .point(name: card.place.name, location: card.place.location))
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    private func openCard(_ place: MapPlace) {
        Task {
            let item = await AppleMapsService.mapItem(for: place)
            card = MapsPlaceCard(item: item, place: place)
        }
    }

    // MARK: Location

    private func trackLocation() async {
        // Holding the session asks for permission the first time and keeps updates coming while Maps is open.
        let session = CLServiceSession(authorization: .whenInUse)
        defer { session.invalidate() }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location {
                    model.userMoved(to: GeoPoint(location.coordinate))
                }
            }
        } catch {}
    }
}

/// The results and route sheets: three heights, the map usable behind the lower two, closed only with ✕.
private struct MapsPanelSheet: ViewModifier {
    @Binding var detent: PresentationDetent
    @Binding var top: CGFloat?

    func body(content: Content) -> some View {
        content
            .presentationDetents([.mapsSmall, .medium, .large], selection: $detent)
            .presentationBackgroundInteraction(.enabled(upThrough: .medium))
            .interactiveDismissDisabled()
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { top = $0 }
    }
}

// MARK: - Place card

/// Apple's own place card (hours, phone, website, photos…), with a route there and 「よく使う項目」 below.
private struct MapsPlaceCardView: View {
    let card: MapsPlaceCard
    var onRoute: () -> Void

    @Environment(MapsStore.self) private var store

    var body: some View {
        MapItemDetail(item: card.item)
            .ignoresSafeArea(edges: .bottom)
            .safeAreaInset(edge: .bottom) {
                HStack(spacing: 12) {
                    Button(action: onRoute) {
                        Label("ここへの経路", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    if !store.isSaved(card.place) {
                        Button {
                            store.save(SavedPlace(
                                name: card.place.name, location: card.place.location,
                                placeID: card.place.appleID, address: card.place.address
                            ))
                        } label: {
                            Image(systemName: "star")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .buttonStyle(.glass)
                        .buttonBorderShape(.circle)
                        .controlSize(.large)
                        .accessibilityLabel("よく使う項目に追加")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
    }
}

private struct MapItemDetail: UIViewControllerRepresentable {
    let item: MKMapItem

    func makeUIViewController(context: Context) -> MKMapItemDetailViewController {
        MKMapItemDetailViewController(mapItem: item, displaysMap: false)
    }

    func updateUIViewController(_ controller: MKMapItemDetailViewController, context: Context) {}
}

// MARK: - Results

private struct MapsResultsList: View {
    @Bindable var model: MapsScreenModel
    var onDetail: (MapPlace) -> Void
    @Environment(MapsStore.self) private var store

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.searching {
                        ProgressView().padding(24)
                    } else if model.results.count > 1 {
                        Text("\(model.results.count)件・照準地から近い順")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 4)
                    }
                    if let error = model.resultsError {
                        Text(error)
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                            .padding(24)
                    }
                    ForEach(model.results) { place in
                        row(place)
                            .id(place.id)
                        Divider().padding(.leading, 20)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.snappy) { proxy.scrollTo(id, anchor: .top) }
            }
        }
    }

    private func row(_ place: MapPlace) -> some View {
        let selected = place.id == model.selectedID
        return VStack(alignment: .leading, spacing: 5) {
            Text(place.name)
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(2)
            let detail = [place.category, place.address].compactMap { $0 }.joined(separator: "・")
            if !detail.isEmpty {
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text("照準地から \(MapsFormat.distance(place.location.distance(to: model.aim)))")
                .font(.system(size: 13))
                .monospacedDigit()
            if let status = place.openStatus {
                HStack(spacing: 6) {
                    Text(status.label)
                        .fontWeight(.semibold)
                        .foregroundStyle(status.color)
                    if let detail = status.detail {
                        Text(detail).foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: 13))
            }
            HStack(spacing: 10) {
                Button {
                    model.startRoute(from: .currentLocation, to: .point(name: place.name, location: place.location))
                } label: {
                    Label("ここへの経路", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 4)
                }
                .buttonStyle(.glassProminent)
                Button {
                    onDetail(place)
                } label: {
                    Label("詳細", systemImage: "info.circle")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.glass)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(selected ? Color.brand.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { model.select(place, store: store) }
        .contextMenu {
            if !store.isSaved(place) {
                Button {
                    store.save(SavedPlace(name: place.name, location: place.location, placeID: place.appleID, address: place.address))
                } label: {
                    Label("よく使う項目に追加", systemImage: "star")
                }
            }
        }
    }
}

// MARK: - Route

private struct MapsRouteContent: View {
    @Bindable var model: MapsScreenModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                summary
                    .padding(.horizontal, 20)
                Picker("移動手段", selection: Binding(get: { model.route?.mode ?? .walk }, set: { model.changeMode($0) })) {
                    ForEach(TravelMode.allCases) { mode in
                        Image(systemName: mode.symbol)
                            .accessibilityLabel(mode.label)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)

                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.route?.result?.steps ?? []) { step in
                        stepRow(step)
                        Divider().padding(.leading, 56)
                    }
                }
                if let route = model.route, route.mode == .transit || route.error != nil {
                    VStack(alignment: .leading, spacing: 10) {
                        if route.mode == .transit {
                            Text("電車・バスは所要時間だけを表示しています。乗り換えや路線は Apple マップで確かめられます。")
                        }
                        if let origin = route.originPoint, let destination = route.destinationPoint {
                            Button {
                                AppleMapsService.openInMaps(
                                    from: origin, originName: route.origin.name,
                                    to: destination, destinationName: route.destination.name,
                                    mode: route.mode
                                )
                            } label: {
                                Label("Apple マップで開く", systemImage: "map")
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .buttonStyle(.glass)
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
    }

    @ViewBuilder
    private var summary: some View {
        if let route = model.route {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(route.origin.name)から・\(route.mode.label)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let result = route.result {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(MapsFormat.duration(result.durationSeconds))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.brand)
                        Text(MapsFormat.distance(Double(result.distanceMeters)))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text("\(MapsFormat.clockTime(result.arrival ?? Date().addingTimeInterval(TimeInterval(result.durationSeconds)))) 着")
                            .foregroundStyle(.secondary)
                    }
                    .font(.system(size: 14))
                    .monospacedDigit()
                } else if route.loading {
                    ProgressView()
                } else if let error = route.error {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func stepRow(_ step: RouteStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: model.route?.mode.symbol ?? "figure.walk")
                .font(.system(size: 15))
                .foregroundStyle(Color.brand)
                .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(step.instruction)
                    .font(.system(size: 14))
                if let meters = step.distanceMeters, meters > 0 {
                    Text(MapsFormat.distance(Double(meters)))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}
