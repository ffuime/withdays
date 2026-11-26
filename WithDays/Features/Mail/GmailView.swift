import SwiftUI

/// Gmail inside WithDays (reading only): the search bar on top (sidebar · search · account), the mail below.
/// Swipe left to bin, right for read / unread and the star; hold a mail to select several.
struct GmailView: View {
    var onClose: () -> Void

    @State private var store = GmailStore.shared
    @State private var toasts = ToastCenter()
    @State private var sidebar = false
    /// How far the finger has dragged the sidebar (opening from the left edge, or closing it).
    @State private var sidebarDrag: CGFloat = 0
    @State private var showAccounts = false
    @State private var selecting = false
    @State private var selection = Set<String>()
    @State private var opened: GmailMessage?
    @State private var searchText = GmailStore.shared.search
    @FocusState private var searchFocused: Bool
    @Namespace private var bar

    static let red = Color(red: 0.92, green: 0.26, blue: 0.21)

    private var selected: [GmailMessage] { store.messages.filter { selection.contains($0.id) } }

    /// What the list depends on: a change reloads it.
    private var listKey: String { "\(store.folder.rawValue)|\(store.currentEmail ?? "")|\(searchText)|\(store.accounts.count)" }

    var body: some View {
        NavigationStack {
            content
                .toolbar(.hidden, for: .navigationBar)
                .safeAreaInset(edge: .top, spacing: 0) { header }
                .navigationDestination(item: $opened) { message in
                    GmailMessageView(message: message) { delete([$0]) }
                }
        }
        .overlay { sidebarLayer }
        .overlay(alignment: .bottom) {
            if let toast = toasts.current {
                UndoToastView(toast: toast) { toasts.performUndo() }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                    .id(toast.id)
            }
        }
        .sheet(isPresented: $showAccounts) { GmailAccountsSheet() }
        .task(id: listKey) {
            // Typing: wait for a pause before searching.
            if searchText != store.search { try? await Task.sleep(for: .milliseconds(400)) }
            guard !Task.isCancelled else { return }
            store.search = searchText
            await store.reload()
        }
        .onChange(of: store.folder) { _, _ in endSelection() }
        .alert("Gmail", isPresented: Binding(
            get: { store.errorMessage != nil && !showAccounts },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .sensoryFeedback(.selection, trigger: selection)
        .sensoryFeedback(.impact(weight: .medium), trigger: selecting) { _, new in new }
    }

    // MARK: List

    @ViewBuilder
    private var content: some View {
        if store.accounts.isEmpty {
            ContentUnavailableView {
                Label("Gmail にログイン", systemImage: "envelope")
            } description: {
                Text("Google アカウントを追加すると、受信トレイのメールを読めます。")
            } actions: {
                Button("アカウントを追加") { showAccounts = true }
                    .buttonStyle(.glassProminent)
                    .tint(Self.red)
            }
        } else {
            List {
                VStack(alignment: .leading, spacing: 2) {
                    Text(store.folder.title)
                        .font(.title2.weight(.bold))
                    if store.folder != .allInboxes, let email = store.currentEmail {
                        Text(email)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 6, trailing: 20))

                ForEach(store.messages) { message in
                    row(message)
                }
                if store.canLoadMore, !store.messages.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .listRowSeparator(.hidden)
                        .task { await store.loadMore() }
                }
            }
            .listStyle(.plain)
            .refreshable { await store.reload() }
            .scrollDismissesKeyboard(.immediately)
            .overlay {
                if store.messages.isEmpty {
                    if store.loading {
                        ProgressView()
                    } else if !searchText.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                    } else {
                        ContentUnavailableView(store.folder == .trash ? "ごみ箱は空です" : "メールはありません",
                                               systemImage: store.folder.symbol)
                    }
                }
            }
        }
    }

    private func row(_ message: GmailMessage) -> some View {
        GmailRow(message: message,
                 selecting: selecting,
                 selected: selection.contains(message.id),
                 showAccount: store.folder == .allInboxes && store.accounts.count > 1)
            .contentShape(Rectangle())
            .onTapGesture {
                if selecting {
                    toggle(message)
                } else {
                    searchFocused = false
                    opened = message
                }
            }
            .onLongPressGesture(minimumDuration: 0.4) {
                guard !selecting else { return }
                searchFocused = false
                withAnimation(.snappy) {
                    selecting = true
                    selection = [message.id]
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .listRowBackground(selection.contains(message.id) ? Self.red.opacity(0.1) : Color.clear)
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                if !selecting {
                    Button(role: .destructive) {
                        delete([message])
                    } label: {
                        if store.folder == .trash {
                            Label("戻す", systemImage: "tray.and.arrow.up.fill")
                        } else {
                            Label("削除", systemImage: "trash.fill")
                        }
                    }
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if !selecting {
                    Button {
                        store.setRead([message], read: message.unread)
                    } label: {
                        Label(message.unread ? "既読" : "未読",
                              systemImage: message.unread ? "envelope.open.fill" : "envelope.badge.fill")
                    }
                    .tint(.blue)
                    Button {
                        store.setStarred([message], starred: !message.starred)
                    } label: {
                        Label(message.starred ? "スターを外す" : "スター",
                              systemImage: message.starred ? "star.slash.fill" : "star.fill")
                    }
                    .tint(.yellow)
                }
            }
    }

    // MARK: Search bar

    private var header: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 10) {
                if selecting {
                    Button {
                        endSelection()
                    } label: {
                        Image(systemName: "chevron.backward")
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 50, height: 50)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .glassEffectID("lead", in: bar)
                    .accessibilityLabel("選択をやめる")
                    Text("\(selection.count)件選択")
                        .font(.headline)
                        .contentTransition(.numericText())
                        .transition(.opacity)
                    Spacer(minLength: 8)
                    selectionPill
                } else {
                    searchField
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 4)
            .padding(.bottom, 8)
        }
        .animation(.snappy(duration: 0.3), value: selecting)
    }

    private var searchField: some View {
        HStack(spacing: 2) {
            Button {
                searchFocused = false
                setSidebar(true)
            } label: {
                Image(systemName: "sidebar.squares.left")
                    .font(.system(size: 19, weight: .medium))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("サイドバー")
            TextField("メールを検索", text: $searchText)
                .focused($searchFocused)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 30, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("検索をクリア")
            }
            Button {
                searchFocused = false
                showAccounts = true
            } label: {
                GmailAccountAvatar(account: store.current, size: 34)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("アカウント")
        }
        .padding(.horizontal, 6)
        .frame(height: 54)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("field", in: bar)
        .transition(.opacity)
    }

    private var selectionPill: some View {
        let targets = selected
        let allStarred = !targets.isEmpty && targets.allSatisfy(\.starred)
        let allRead = !targets.isEmpty && targets.allSatisfy { !$0.unread }
        return HStack(spacing: 0) {
            pillButton(allStarred ? "スターを外す" : "スターを付ける", allStarred ? "star.slash" : "star") {
                store.setStarred(targets, starred: !allStarred)
            }
            pillButton(allRead ? "未読にする" : "既読にする", allRead ? "envelope.badge" : "envelope.open") {
                store.setRead(targets, read: !allRead)
            }
            pillButton(store.folder == .trash ? "戻す" : "削除", store.folder == .trash ? "tray.and.arrow.up" : "trash") {
                delete(targets)
                endSelection()
            }
        }
        .disabled(targets.isEmpty)
        .padding(.horizontal, 4)
        .frame(height: 54)
        .glassEffect(.regular.interactive(), in: .capsule)
        .glassEffectID("field", in: bar)
    }

    private func pillButton(_ title: String, _ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: Sidebar

    private static let sidebarWidth: CGFloat = 304

    /// How much of the sidebar is out (0 … its width), following the finger while dragging.
    private var sidebarShown: CGFloat {
        let width = Self.sidebarWidth
        return sidebar ? max(0, width + min(0, sidebarDrag)) : max(0, min(width, sidebarDrag))
    }

    private func setSidebar(_ open: Bool) {
        withAnimation(.snappy(duration: 0.3)) {
            sidebar = open
            sidebarDrag = 0
        }
    }

    /// From the left edge: the sidebar comes out under the finger.
    private var openDrag: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                searchFocused = false
                sidebarDrag = max(0, value.translation.width)
            }
            .onEnded { value in
                setSidebar(value.predictedEndTranslation.width > Self.sidebarWidth / 2)
            }
    }

    /// Pushing the open sidebar back to the left.
    private var closeDrag: some Gesture {
        DragGesture(minimumDistance: 12, coordinateSpace: .global)
            .onChanged { value in
                sidebarDrag = min(0, value.translation.width)
            }
            .onEnded { value in
                setSidebar(value.predictedEndTranslation.width > -Self.sidebarWidth / 2)
            }
    }

    private var sidebarLayer: some View {
        let shown = sidebarShown
        let width = Self.sidebarWidth
        return ZStack(alignment: .leading) {
            Color.black.opacity(0.3 * shown / width)
                .ignoresSafeArea()
                .allowsHitTesting(sidebar)
                .onTapGesture { setSidebar(false) }
                .gesture(closeDrag)

            GmailSidebar(store: store) { folder in
                store.folder = folder
                setSidebar(false)
            } onClose: {
                setSidebar(false)
                onClose()
            }
            // Fully off screen (shadow too) when closed.
            .offset(x: shown > 0 ? shown - width : -width - 40)
            .allowsHitTesting(sidebar)
            .accessibilityHidden(!sidebar)
            .gesture(closeDrag)

            // The strip along the left edge that pulls the sidebar out (not inside a mail, where
            // the edge swipe goes back, nor while selecting).
            if !sidebar && opened == nil && !selecting {
                Color.clear
                    .frame(width: 18)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .gesture(openDrag)
                    .accessibilityHidden(true)
            }
        }
    }

    // MARK: Actions

    private func toggle(_ message: GmailMessage) {
        withAnimation(.snappy(duration: 0.2)) {
            if selection.contains(message.id) { selection.remove(message.id) } else { selection.insert(message.id) }
        }
    }

    private func endSelection() {
        withAnimation(.snappy) {
            selecting = false
            selection = []
        }
    }

    /// To the bin (out of it in ごみ箱), with 元に戻す.
    private func delete(_ targets: [GmailMessage]) {
        guard !targets.isEmpty else { return }
        let restoring = store.folder == .trash
        let moved = store.trash(targets)
        let count = moved.count > 1 ? "\(moved.count)件を" : ""
        toasts.show(restoring ? "\(count)受信トレイに戻しました" : "\(count)ごみ箱に移動しました") {
            store.undoTrash(moved)
        }
    }
}

// MARK: Row

struct GmailRow: View {
    let message: GmailMessage
    let selecting: Bool
    let selected: Bool
    let showAccount: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if selecting {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? GmailView.red : Color.secondary)
                    .frame(height: 42)
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            GmailAvatar(name: message.fromName, address: message.fromAddress, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(message.fromName)
                        .font(.system(size: 16, weight: message.unread ? .bold : .regular))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(GmailDate.list(message.date))
                        .font(.system(size: 12, weight: message.unread ? .semibold : .regular))
                        .foregroundStyle(message.unread ? Color.primary : Color.secondary)
                        .monospacedDigit()
                }
                Text(message.subject.isEmpty ? "（件名なし）" : message.subject)
                    .font(.system(size: 15, weight: message.unread ? .semibold : .regular))
                    .lineLimit(1)
                HStack(alignment: .top, spacing: 6) {
                    Text(message.snippet)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if message.starred {
                        Image(systemName: "star.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.yellow)
                            .accessibilityLabel("スター付き")
                    }
                }
                if showAccount {
                    Text(message.account)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

/// The sender's initial on a colour of their own.
struct GmailAvatar: View {
    let name: String
    let address: String
    var size: CGFloat = 42

    private static let palette: [Color] = [
        Color(red: 0.26, green: 0.52, blue: 0.96), Color(red: 0.92, green: 0.26, blue: 0.21),
        Color(red: 0.20, green: 0.66, blue: 0.33), Color(red: 0.98, green: 0.62, blue: 0.0),
        Color(red: 0.61, green: 0.35, blue: 0.85), Color(red: 0.0, green: 0.62, blue: 0.70),
        Color(red: 0.91, green: 0.36, blue: 0.58), Color(red: 0.47, green: 0.53, blue: 0.60),
    ]

    var body: some View {
        let seed = address.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFFFF }
        let initial = name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "?"
        Circle()
            .fill(Self.palette[seed % Self.palette.count].gradient)
            .frame(width: size, height: size)
            .overlay {
                Text(initial)
                    .font(.system(size: size * 0.44, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .accessibilityHidden(true)
    }
}

/// A Google account's photo (its initial until it loads).
struct GmailAccountAvatar: View {
    let account: GmailAccount?
    var size: CGFloat = 34

    var body: some View {
        if let account {
            AsyncImage(url: account.picture) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                GmailAvatar(name: account.name, address: account.email, size: size)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle")
                .font(.system(size: size * 0.8))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        }
    }
}

enum GmailDate {
    /// Today: the time. This year: date and time. Before: the date.
    static func list(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.month(.defaultDigits).day()) + " "
                + date.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        }
        return date.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }

    static func full(_ date: Date) -> String {
        date.formatted(.dateTime.year().month().day().weekday(.abbreviated).hour().minute())
    }
}

// MARK: Sidebar

struct GmailSidebar: View {
    let store: GmailStore
    var onPick: (GmailFolder) -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image("GmailMark")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34)
                Text("Gmail")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Gmail")

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    item(.allInboxes)
                    divider
                    item(.primary)
                    item(.social)
                    item(.promotions)
                    item(.updates)
                    divider
                    item(.starred)
                    divider
                    item(.trash)
                }
                .padding(.horizontal, 10)
            }
            .scrollBounceBehavior(.basedOnSize)

            Divider().padding(.horizontal, 20)
            Button(action: onClose) {
                Label("WithDaysへ戻る", systemImage: "rectangle.portrait.and.arrow.forward")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .frame(height: 56)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 8)
        }
        .frame(width: 304)
        .frame(maxHeight: .infinity)
        .background {
            UnevenRoundedRectangle(bottomTrailingRadius: 28, topTrailingRadius: 28, style: .continuous)
                .fill(Color(uiColor: .systemBackground))
                .shadow(color: .black.opacity(0.18), radius: 20, x: 4)
                .ignoresSafeArea()
        }
    }

    private var divider: some View {
        Divider().padding(.vertical, 6).padding(.horizontal, 14)
    }

    private func item(_ folder: GmailFolder) -> some View {
        let current = store.folder == folder
        return Button {
            onPick(folder)
        } label: {
            HStack(spacing: 16) {
                Image(systemName: folder.symbol)
                    .font(.system(size: 17))
                    .frame(width: 26)
                Text(folder.title)
                    .font(.system(size: 16, weight: current ? .semibold : .regular))
                Spacer(minLength: 8)
                if let count = store.unread[folder], count > 0 {
                    Text(count > 999 ? "999+" : "\(count)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                }
            }
            .foregroundStyle(current ? GmailView.red : Color.primary)
            .padding(.horizontal, 14)
            .frame(height: 50)
            .background(current ? GmailView.red.opacity(0.13) : Color.clear, in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
