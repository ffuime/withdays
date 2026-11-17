import CoreLocation
import SwiftUI

/// Maps: Google's map with a search bar on top, the route button bottom right (with 「現在地に戻す」 splitting
/// out of it when the map's middle leaves the current location), and results or a route in a glass panel below.
struct MapsView: View {
    var onCalendar: () -> Void

    @AppStorage(SettingsKey.mapsAPIKey) private var apiKey = ""
    @State private var setup: GoogleMapsSetup.State?

    var body: some View {
        Group {
            switch setup {
            case nil:
                Color(.systemBackground)
            case .missing:
                MapsKeyView(onCalendar: onCalendar)
            case .ready, .needsRelaunch:
                MapsMainView(onCalendar: onCalendar)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { setup = GoogleMapsSetup.prepare() }
        .onChange(of: apiKey) { setup = GoogleMapsSetup.prepare() }
    }
}

// MARK: - Key entry

/// Shown until a Google API key is entered.
private struct MapsKeyView: View {
    var onCalendar: () -> Void
    @State private var key = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                MapsCircleButton(symbol: "calendar", action: onCalendar)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            ContentUnavailableView {
                Label("Google の API キーが必要です", systemImage: "map")
            } description: {
                Text("Maps は Google Maps Platform（Maps SDK for iOS・Places API (New)・Routes API）を使います。Google Cloud で作った API キーを入力してください。あとから設定でも変えられます。")
            } actions: {
                VStack(spacing: 12) {
                    SecureField("API キー", text: $key)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .glassEffect(.regular, in: .capsule)
                    Button("保存") {
                        UserDefaults.standard.set(key.trimmingCharacters(in: .whitespacesAndNewlines), forKey: SettingsKey.mapsAPIKey)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 24)
            }
        }
        .background(Color(.systemBackground))
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
    /// How far the panel reaches up from the bottom of the screen, as it moves.
    @State private var panelTop: CGFloat = 0
    /// The map's bottom padding, set when the panel settles so the map doesn't slide while it's dragged.
    @State private var mapBottom: CGFloat = 0
    @State private var pendingPoint: GeoPoint?
    @State private var pointName = ""
    @Namespace private var glass
    @Namespace private var searchSpace

    private static let barHeight: CGFloat = 50

    private var showsPanel: Bool { model.route != nil || model.showingResults }
    private var panelDetent: PanelDetent { model.route != nil ? model.routeDetent : model.resultsDetent }

    var body: some View {
        GeometryReader { geo in
            let top = geo.safeAreaInsets.top
            let bottom = geo.safeAreaInsets.bottom
            let screenHeight = geo.size.height + top + bottom
            let mapTop = top + 8 + Self.barHeight + 8
            ZStack(alignment: .top) {
                mapLayer(top: mapTop)
                    .ignoresSafeArea()
                crosshair(top: mapTop, screenHeight: screenHeight)
                    .ignoresSafeArea()
                panelLayer(available: screenHeight - mapTop, bottom: bottom)
                    .ignoresSafeArea(edges: .bottom)
                buttons(bottom: bottom)
                    .ignoresSafeArea(edges: .bottom)
                searchBar
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                if searchOpen { searchScreen }
                if plannerOpen {
                    RoutePlannerView(
                        aim: model.aim,
                        onRoute: { origin, destination in
                            withAnimation(.snappy) { plannerOpen = false }
                            model.startRoute(from: origin, to: destination)
                        },
                        onClose: { withAnimation(.snappy) { plannerOpen = false } }
                    )
                    .background(Color(.systemBackground))
                    .transition(.move(edge: .bottom))
                }
            }
            .onChange(of: settleKey, initial: true) { _, _ in settleMap(screenHeight: screenHeight) }
        }
        .ignoresSafeArea(.keyboard)
        .animation(.snappy(duration: 0.3), value: showsPanel)
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: model.awayFromUser)
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
        GoogleMapView(
            places: model.route == nil ? model.results : [],
            selectedID: model.selectedID,
            route: routeOverlay,
            userLocation: model.userLocation,
            padding: UIEdgeInsets(top: top, left: 0, bottom: mapBottom, right: 0),
            command: model.command,
            initialCamera: model.aim,
            initialZoom: model.zoom,
            onCameraChange: { _, away in
                if away != model.awayFromUser { model.awayFromUser = away }
            },
            onCameraIdle: { target, zoom in model.cameraStopped(at: target, zoom: zoom) },
            onLongPress: { point in
                pointName = ""
                pendingPoint = point
            },
            onMarkerTap: { id in
                guard let place = model.results.first(where: { $0.id == id }) else { return }
                model.select(place, store: store)
                if model.resultsDetent == .collapsed { withAnimation(.snappy) { model.resultsDetent = .half } }
            }
        )
    }

    private var routeOverlay: MapRouteOverlay? {
        guard let route = model.route, let origin = route.originPoint, let destination = route.destinationPoint,
              let result = route.result else { return nil }
        return MapRouteOverlay(encodedPolyline: result.encodedPolyline, origin: origin, destination: destination)
    }

    /// A small cross on the 「照準地」: the middle of the map left between the search bar and the panel.
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

    /// When the panel settles, after its animation, the map's padding follows (up to half the screen).
    private var settleKey: String { "\(showsPanel)-\(panelDetent)" }

    private func settleMap(screenHeight: CGFloat) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            mapBottom = showsPanel ? min(panelTop, screenHeight * 0.5) : 0
        }
    }

    // MARK: Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            MapsCircleButton(symbol: "calendar", size: Self.barHeight, action: onCalendar)
            ZStack {
                if !searchOpen {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        Text(model.resultsTitle ?? "場所やジャンルを検索")
                            .foregroundStyle(model.resultsTitle == nil ? Color.secondary : Color.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        if model.showingResults || model.route != nil {
                            Button {
                                withAnimation(.snappy) {
                                    model.closeRoute()
                                    model.closeResults()
                                }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: Self.barHeight)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .matchedGeometryEffect(id: "search", in: searchSpace)
                    .contentShape(Capsule())
                    .onTapGesture(perform: openSearch)
                }
            }
            .frame(height: Self.barHeight)
        }
    }

    private var searchScreen: some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(Color(.systemBackground))
                .matchedGeometryEffect(id: "search", in: searchSpace)
                .ignoresSafeArea()
            MapsSearchScreen(
                text: $searchText,
                onSearch: { text in
                    closeSearch()
                    model.search(text, store: store)
                },
                onPickSaved: { place in
                    closeSearch()
                    model.show(place.asPlace, store: store)
                },
                onPickHistory: { entry in
                    closeSearch()
                    switch entry.kind {
                    case .query:
                        searchText = entry.text
                        model.search(entry.text, store: store)
                    case .place:
                        let place = MapPlace(
                            id: entry.placeID ?? "point-\(entry.id.uuidString)",
                            name: entry.text,
                            address: entry.address,
                            location: entry.location ?? model.aim
                        )
                        model.show(place, store: store)
                    }
                },
                onCancel: closeSearch
            )
            .transition(.opacity)
        }
        .zIndex(1)
    }

    private func openSearch() {
        searchText = model.resultsTitle ?? ""
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { searchOpen = true }
    }

    private func closeSearch() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) { searchOpen = false }
    }

    // MARK: Buttons

    /// The route button, with 「現在地に戻す」 splitting up out of it while the map's middle is off the current location.
    private func buttons(bottom: CGFloat) -> some View {
        let hidden = showsPanel && panelDetent == .large
        let lift = showsPanel ? panelTop + 12 : max(bottom, 20) + 12
        return GlassEffectContainer(spacing: 14) {
            VStack(spacing: 14) {
                if model.awayFromUser, model.userLocation != nil {
                    Image(systemName: "location.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Color.brand)
                        .frame(width: 56, height: 56)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .glassEffectID("recenter", in: glass)
                        .contentShape(Circle())
                        .onTapGesture { model.backToUser() }
                        .transition(.asymmetric(
                            insertion: .offset(y: 70).combined(with: .scale(scale: 0.6)),
                            removal: .offset(y: 70).combined(with: .scale(scale: 0.6)).combined(with: .opacity)
                        ))
                        .accessibilityLabel("現在地に戻す")
                }
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .glassEffect(.regular.tint(Color.brand).interactive(), in: .circle)
                    .glassEffectID("route", in: glass)
                    .contentShape(Circle())
                    .onTapGesture { withAnimation(.snappy) { plannerOpen = true } }
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

    // MARK: Panel

    @ViewBuilder
    private func panelLayer(available: CGFloat, bottom: CGFloat) -> some View {
        if model.route != nil {
            MapsPanel(
                detent: $model.routeDetent,
                available: available,
                bottomInset: bottom,
                onHeight: { panelTop = $0 }
            ) {
                MapsRouteHeader(model: model)
            } content: {
                MapsRouteContent(model: model)
            }
            .transition(.move(edge: .bottom))
        } else if model.showingResults {
            MapsPanel(
                detent: $model.resultsDetent,
                available: available,
                bottomInset: bottom,
                onHeight: { panelTop = $0 }
            ) {
                MapsResultsHeader(model: model)
            } content: {
                MapsResultsList(model: model)
            }
            .transition(.move(edge: .bottom))
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

// MARK: - Results

private struct MapsResultsHeader: View {
    @Bindable var model: MapsScreenModel

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.resultsTitle ?? "")
                    .font(.system(size: 18, weight: .bold))
                    .lineLimit(1)
                // Collapsed, only the search word shows.
                if model.resultsDetent != .collapsed {
                    Group {
                        if model.searching {
                            Text("検索中…")
                        } else if model.results.count > 1 {
                            Text("\(model.results.count)件・照準地から近い順")
                        }
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            MapsCircleButton(symbol: "xmark", size: 34) {
                withAnimation(.snappy) { model.closeResults() }
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 6)
    }
}

private struct MapsResultsList: View {
    @Bindable var model: MapsScreenModel
    @Environment(MapsStore.self) private var store

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if model.searching {
                        ProgressView().padding(24)
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
            Button {
                model.startRoute(from: .currentLocation, to: .point(name: place.name, location: place.location))
            } label: {
                Label("ここへの経路", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .padding(.horizontal, 4)
            }
            .buttonStyle(.glassProminent)
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
                    store.save(SavedPlace(name: place.name, location: place.location, placeID: place.googleID, address: place.address))
                } label: {
                    Label("よく使う項目に追加", systemImage: "star")
                }
            }
        }
    }
}

// MARK: - Route

private struct MapsRouteHeader: View {
    @Bindable var model: MapsScreenModel

    var body: some View {
        if let route = model.route {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(route.destination.name)
                            .font(.system(size: 18, weight: .bold))
                            .lineLimit(1)
                        Text("\(route.origin.name)から・\(route.mode.label)")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    MapsCircleButton(symbol: "xmark", size: 34) {
                        withAnimation(.snappy) { model.closeRoute() }
                    }
                }
                if let result = route.result {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(MapsFormat.duration(result.durationSeconds))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Color.brand)
                        Text(MapsFormat.distance(Double(result.distanceMeters)))
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Text("\(MapsFormat.clockTime(Date().addingTimeInterval(TimeInterval(result.durationSeconds)))) 着")
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
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
    }
}

private struct MapsRouteContent: View {
    @Bindable var model: MapsScreenModel

    var body: some View {
        VStack(spacing: 8) {
            Picker("移動手段", selection: Binding(get: { model.route?.mode ?? .walk }, set: { model.changeMode($0) })) {
                ForEach(TravelMode.allCases) { mode in
                    Image(systemName: mode.symbol)
                        .accessibilityLabel(mode.label)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.route?.result?.steps ?? []) { step in
                        stepRow(step)
                        Divider().padding(.leading, 56)
                    }
                    if model.route?.mode == .transit, model.route?.error != nil {
                        Text("日本では Google の公共交通の経路が返らない区間があります。徒歩や車を試してください。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(20)
                    }
                }
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private func stepRow(_ step: RouteStep) -> some View {
        if let transit = step.transit {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Color(hex: transit.color) ?? Color.brand, in: .circle)
                VStack(alignment: .leading, spacing: 4) {
                    Text(transit.lineName)
                        .font(.system(size: 15, weight: .semibold))
                    if let headsign = transit.headsign {
                        Text("\(headsign)行き").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                    stopLine(transit.departureStop, time: transit.departureTime, suffix: "発")
                    stopLine(transit.arrivalStop, time: transit.arrivalTime, suffix: "着")
                    if let count = transit.stopCount {
                        Text("\(count)駅").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: symbol(for: step.travelMode))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.brand)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(step.instruction ?? "進む")
                        .font(.system(size: 14))
                    let amount = [
                        step.distanceMeters.map { MapsFormat.distance(Double($0)) },
                        step.durationSeconds.map { MapsFormat.duration($0) },
                    ].compactMap { $0 }.joined(separator: "・")
                    if !amount.isEmpty {
                        Text(amount).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func stopLine(_ name: String?, time: Date?, suffix: String) -> some View {
        if name != nil || time != nil {
            HStack(spacing: 6) {
                if let time {
                    Text(MapsFormat.clockTime(time)).monospacedDigit().fontWeight(.semibold)
                }
                Text("\(name ?? "")\(suffix)")
            }
            .font(.system(size: 13))
        }
    }

    private func symbol(for travelMode: String) -> String {
        switch travelMode {
        case "DRIVE": "car.fill"
        case "BICYCLE": "bicycle"
        default: "figure.walk"
        }
    }
}

// MARK: - Parts

/// A round glass button with a symbol.
struct MapsCircleButton: View {
    let symbol: String
    var size: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size * 0.38, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: size, height: size)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
    }
}
