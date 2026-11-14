import SwiftUI

/// The home screen, after the iPhone's: pages of 6 × 4 icons that scroll sideways with dots, a glass Dock of four,
/// and folders. Holding an icon (or empty space) starts 編集: icons jiggle and can be carried to another place,
/// another page (hold at the edge), the Dock, or onto another icon to make a folder. A tap opens an app or a folder.
struct SpringboardView: View {
    @Bindable var board: Springboard
    /// Opens an app, zooming from its icon (in screen points).
    var launch: (SpringApp, CGRect) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @State private var folderName = ""
    @FocusState private var editingFolderName: Bool

    /// The space beside the grid on each side.
    private let inset: CGFloat = 14

    var body: some View {
        ZStack {
            wallpaper
            VStack(spacing: 0) {
                topBar
                pages
                pageDots
                dock
            }
            folderLayer
            carried
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: board.editing) { _, new in new }
        .sensoryFeedback(.impact(weight: .light), trigger: board.drag?.merge) { _, new in new != nil }
        .sensoryFeedback(.selection, trigger: board.page)
    }

    // MARK: Wallpaper

    @ViewBuilder
    private var wallpaper: some View {
        GeometryReader { geo in
            if let image = board.wallpaper {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            } else {
                let colors: [UInt32] = colorScheme == .dark
                    ? [0x1B4A73, 0x0C2742, 0x050F1C]
                    : [0x9BD3F2, 0x3F8FC9, 0x0B4C7A]
                ZStack {
                    LinearGradient(colors: colors.map { Color(uiColor: UIColor(hex: $0)) }, startPoint: .top, endPoint: .bottom)
                    RadialGradient(
                        colors: [Color.white.opacity(colorScheme == .dark ? 0.08 : 0.28), .clear],
                        center: UnitPoint(x: 0.2, y: 0.15), startRadius: 0, endRadius: geo.size.width * 0.9
                    )
                }
            }
        }
        .ignoresSafeArea()
        // The whole screen, past the safe area.
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { board.screen = $0 }
        .contentShape(Rectangle())
        .onTapGesture { if board.editing { board.endEditing() } }
        .onLongPressGesture(minimumDuration: 0.5) { board.startEditing() }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Spacer()
            if board.editing {
                Button("完了") { board.endEditing() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 18)
                    .frame(height: 36)
                    .glassEffect(.regular.interactive(), in: .capsule)
                    .transition(.scale(scale: 0.7).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
    }

    // MARK: Pages

    private var pages: some View {
        GeometryReader { geo in
            let count = board.shownLayout.pages.count
            ScrollView(.horizontal) {
                HStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { page in
                        pageView(page, size: geo.size)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .id(page)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollPosition(id: $board.page)
            .scrollIndicators(.hidden)
            .scrollDisabled(board.drag != nil)
            .scrollClipDisabled()
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            board.gridFrame = frame.insetBy(dx: inset, dy: 0)
            // Icons fill about two thirds of their column, as on the iPhone.
            board.iconSize = min(64, (frame.width - inset * 2) / CGFloat(SpringLayout.columns) * 0.68)
        }
    }

    private func pageView(_ page: Int, size: CGSize) -> some View {
        let grid = board.pageGrid(in: CGRect(x: inset, y: 0, width: size.width - inset * 2, height: size.height))
        let entries = board.entries(in: .page(page))
        return ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { if board.editing { board.endEditing() } }
                .onLongPressGesture(minimumDuration: 0.5) { board.startEditing() }
            ForEach(slots(entries, in: .page(page)), id: \.id) { slot in
                let cell = grid.cellRect(slot.index)
                iconCell(slot.item, in: .page(page), index: slot.index, labeled: true)
                    .opacity(slot.carried ? 0 : 1)
                    .position(x: cell.midX, y: cell.midY)
            }
        }
    }

    private var pageDots: some View {
        let count = board.shownLayout.pages.count
        return HStack(spacing: 9) {
            ForEach(0..<count, id: \.self) { page in
                Circle()
                    .fill(Color.white.opacity(page == board.currentPage ? 0.95 : 0.4))
                    .frame(width: 7, height: 7)
                    .onTapGesture { withAnimation(.snappy) { board.page = page } }
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 26)
        .glassEffect(.regular, in: .capsule)
        .opacity(count > 1 ? 1 : 0)
        .animation(.snappy(duration: 0.2), value: board.currentPage)
        .frame(height: 40)
    }

    // MARK: Dock

    private var dock: some View {
        let entries = board.entries(in: .dock)
        let height = board.iconSize + 26
        return GeometryReader { geo in
            let grid = board.dockGrid(in: CGRect(x: 6, y: 0, width: geo.size.width - 12, height: geo.size.height), slots: max(entries.count, 1))
            ZStack(alignment: .topLeading) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { if board.editing { board.endEditing() } }
                    .onLongPressGesture(minimumDuration: 0.5) { board.startEditing() }
                ForEach(slots(entries, in: .dock), id: \.id) { slot in
                    let cell = grid.cellRect(slot.index)
                    iconCell(slot.item, in: .dock, index: slot.index, labeled: false)
                        .opacity(slot.carried ? 0 : 1)
                        .position(x: cell.midX, y: cell.midY)
                }
            }
        }
        .frame(height: height)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            board.dockFrame = frame.insetBy(dx: 6, dy: 0)
        }
        .background {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(Color.clear)
                .glassEffect(.regular, in: .rect(cornerRadius: 34, style: .continuous))
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    // MARK: Icons

    /// An icon with its label. A tap opens it; holding starts 編集 and, moving, carries it.
    private func iconCell(_ item: SpringItem, in container: SpringContainer, index: Int, labeled: Bool) -> some View {
        let size = board.iconSize
        let merging = board.drag?.merge == item.id
        return VStack(spacing: 0) {
            SpringIconArt(item: item, size: size)
                .background {
                    if merging {
                        RoundedRectangle(cornerRadius: iconCornerRadius(size * 1.25), style: .continuous)
                            .fill(.ultraThinMaterial)
                            .frame(width: size * 1.25, height: size * 1.25)
                    }
                }
                .scaleEffect(merging ? 1.12 : 1)
            if labeled {
                Text(item.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                    .lineLimit(1)
                    .frame(width: size + 26, height: Springboard.labelHeight - 6)
                    .padding(.top, 6)
                    .opacity(board.editing && board.drag != nil ? 0.6 : 1)
            }
        }
        .frame(width: size + 26, height: size + (labeled ? Springboard.labelHeight : 0))
        .modifier(Jiggle(active: board.editing, seed: Double(abs(item.id.hashValue % 628)) / 100))
        .contentShape(Rectangle())
        .onTapGesture { tap(item, in: container, index: index) }
        .gesture(press(item, in: container, index: index))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(.isButton)
    }

    /// The icons to draw and where. The carried icon stays (unseen) where it was, so its touch carries on.
    private func slots(_ entries: [SpringEntry], in container: SpringContainer) -> [SpringSlot] {
        var slots: [SpringSlot] = entries.enumerated().compactMap { index, entry in
            if case .item(let item) = entry { return SpringSlot(index: index, item: item, carried: false) }
            return nil
        }
        if let drag = board.drag, drag.source == container, !slots.contains(where: { $0.item.id == drag.item.id }) {
            slots.append(SpringSlot(index: 0, item: drag.item, carried: true))
        }
        return slots
    }

    private func globalIconRect(in container: SpringContainer, index: Int) -> CGRect {
        switch container {
        case .page: board.pageGrid(in: board.gridFrame).iconRect(index)
        case .dock: board.dockGrid(in: board.dockFrame, slots: max(board.entries(in: .dock).count, 1)).iconRect(index)
        case .folder: board.folderGrid(in: board.folderGridFrame).iconRect(index)
        }
    }

    private func tap(_ item: SpringItem, in container: SpringContainer, index: Int) {
        guard board.drag == nil else { return }
        switch item {
        case .folder(let folder):
            folderName = folder.name
            withAnimation(.spring(duration: 0.4, bounce: 0.15)) { board.openFolder = folder.id }
        case .app(let app):
            if board.editing { return }
            launch(app, globalIconRect(in: container, index: index))
        }
    }

    /// Holding picks the icon up (starting 編集); moving carries it.
    private func press(_ item: SpringItem, in container: SpringContainer, index: Int) -> some Gesture {
        LongPressGesture(minimumDuration: 0.35)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                board.startEditing()
                guard let drag else { return }
                if board.drag == nil {
                    let moved = hypot(drag.translation.width, drag.translation.height)
                    guard moved > 4 else { return }
                    let icon = globalIconRect(in: container, index: index)
                    editingFolderName = false
                    board.beginDrag(item, from: container, at: index, finger: drag.startLocation, iconCenter: CGPoint(x: icon.midX, y: icon.midY))
                }
                board.moveDrag(to: drag.location)
            }
            .onEnded { _ in
                board.endDrag()
            }
    }

    /// The icon in the hand, over everything.
    @ViewBuilder
    private var carried: some View {
        if let drag = board.drag {
            GeometryReader { geo in
                let origin = geo.frame(in: .global).origin
                SpringIconArt(item: drag.item, size: board.iconSize)
                    .scaleEffect(drag.merge == nil ? 1.12 : 0.9)
                    .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
                    .position(
                        x: drag.location.x + drag.grab.width - origin.x,
                        y: drag.location.y + drag.grab.height - origin.y
                    )
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .transition(.identity)
        }
    }

    // MARK: Folder

    @ViewBuilder
    private var folderLayer: some View {
        if let id = board.openFolder, let folder = board.shownLayout.folder(id) ?? board.layout.folder(id) {
            let anchor = folderAnchor(id)
            ZStack {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .ignoresSafeArea()
                    .onTapGesture { closeFolder() }
                    .transition(.opacity)
                VStack(spacing: 22) {
                    Group {
                        if board.editing {
                            TextField("フォルダ名", text: $folderName)
                                .focused($editingFolderName)
                                .submitLabel(.done)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                                .frame(height: 50)
                                .glassEffect(.regular.interactive(), in: .capsule)
                                .onChange(of: folderName) { _, name in board.renameFolder(id, to: name) }
                        } else {
                            Text(folder.name)
                                .foregroundStyle(.primary)
                        }
                    }
                    .font(.system(size: 30, weight: .bold))
                    .lineLimit(1)
                    .padding(.horizontal, 40)
                    folderPanel(id)
                }
                .transition(.scale(scale: 0.2, anchor: anchor).combined(with: .opacity))
            }
            .opacity(board.folderSetAside ? 0 : 1)
        }
    }

    private func folderPanel(_ id: UUID) -> some View {
        let side = min(board.screen.width - 56, 340)
        let padding: CGFloat = 18
        let entries = board.entries(in: .folder(id))
        let grid = board.folderGrid(in: CGRect(x: padding, y: padding, width: side - padding * 2, height: side - padding * 2))
        return ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
            ForEach(slots(entries, in: .folder(id)), id: \.id) { slot in
                let cell = grid.cellRect(slot.index)
                iconCell(slot.item, in: .folder(id), index: slot.index, labeled: true)
                    .opacity(slot.carried ? 0 : 1)
                    .position(x: cell.midX, y: cell.midY)
            }
        }
        .frame(width: side, height: side)
        .glassEffect(.regular, in: .rect(cornerRadius: 40, style: .continuous))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame in
            board.folderPanelFrame = frame
            board.folderGridFrame = frame.insetBy(dx: padding, dy: padding)
        }
    }

    /// The folder grows out of (and back into) its icon.
    private func folderAnchor(_ id: UUID) -> UnitPoint {
        guard board.screen.width > 0,
              let place = board.layout.place(of: board.layout.folder(id)?.apps.first ?? .cal) else { return .center }
        let rect = place.container == .dock
            ? board.dockGrid(in: board.dockFrame, slots: board.layout.dock.count).iconRect(place.index)
            : board.pageGrid(in: board.gridFrame).iconRect(place.index)
        return UnitPoint(
            x: (rect.midX - board.screen.minX) / board.screen.width,
            y: (rect.midY - board.screen.minY) / board.screen.height
        )
    }

    private func closeFolder() {
        editingFolderName = false
        withAnimation(.spring(duration: 0.35, bounce: 0.1)) { board.openFolder = nil }
    }
}

/// An icon drawn in a container, at a cell.
struct SpringSlot: Identifiable {
    let index: Int
    let item: SpringItem
    let carried: Bool

    var id: String { item.id }
}

/// 編集 mode's jiggle: a quick, small rock, out of step from icon to icon.
struct Jiggle: ViewModifier {
    let active: Bool
    let seed: Double

    func body(content: Content) -> some View {
        // One structure either way (paused when still), so a touch in progress isn't lost when 編集 starts.
        TimelineView(.animation(paused: !active)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            content
                .rotationEffect(.degrees(active ? sin(time * 2 * .pi * 3.4 + seed) * 1.6 : 0))
                .offset(y: active ? cos(time * 2 * .pi * 3.4 + seed) * 0.5 : 0)
        }
    }
}
