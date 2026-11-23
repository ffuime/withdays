import FamilyControls
import PhotosUI
import SwiftUI

/// サブスク追加 / 編集.
struct SubsEditor: View {
    let isNew: Bool
    var onSave: (Sub) -> Void

    @Environment(SubsStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var sub: Sub
    @State private var priceText: String
    /// Once 次回更新日 is set by hand, changing 登録日 or the cycle leaves it alone.
    @State private var renewalTouched: Bool
    @State private var newCategory = ""
    @State private var askingCategory = false
    @State private var choosingSymbol = false
    @State private var photo: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var fetchingIcon = false
    @State private var choosingApp = false
    @State private var picking = false
    @State private var selection = FamilyActivitySelection(includeEntireCategory: false)
    @State private var problem: String?

    init(sub: Sub, isNew: Bool, onSave: @escaping (Sub) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _sub = State(initialValue: sub)
        _priceText = State(initialValue: sub.price > 0 ? "\(sub.price)" : "")
        _renewalTouched = State(initialValue: !isNew)
    }

    private var canSave: Bool {
        !sub.name.trimmingCharacters(in: .whitespaces).isEmpty && Int(priceText) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                basics
                dates
                screenTime
                trial
                Section("メモ") {
                    TextField("メモ", text: $sub.memo, axis: .vertical)
                        .lineLimit(3...10)
                }
            }
            .navigationTitle(isNew ? "サブスク追加" : "サブスク編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("キャンセル")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .buttonStyle(.glassProminent)
                        .tint(.blue)
                        .disabled(!canSave)
                        .accessibilityLabel("保存")
                }
            }
            .onChange(of: sub.cycle) { _, _ in followRenewal() }
            .onChange(of: sub.startDate) { _, _ in followRenewal() }
            .sheet(isPresented: $choosingSymbol) {
                SubsSymbolPicker(symbol: $sub.symbol, tint: $sub.tint) { sub.image = nil }
            }
            .sheet(isPresented: $choosingApp) {
                SubsAppIconPicker(initial: sub.name) { sub.image = $0 }
            }
            .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
            .onChange(of: photo) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let small = SubsImages.small(data) {
                        sub.image = small
                    }
                    photo = nil
                }
            }
            .familyActivityPicker(isPresented: $picking, selection: $selection)
            .onChange(of: selection) { _, new in
                if let token = new.applicationTokens.first {
                    sub.appToken = SubsScreenTime.encode(token)
                }
            }
            .alert("新しいカテゴリ", isPresented: $askingCategory) {
                TextField("カテゴリ名", text: $newCategory)
                Button("キャンセル", role: .cancel) { newCategory = "" }
                Button("追加") {
                    let name = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        store.addCategory(name)
                        sub.category = name
                    }
                    newCategory = ""
                }
            }
            .alert("スクリーンタイム", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(problem ?? "")
            }
        }
    }

    // MARK: Sections

    private var basics: some View {
        Section("基本情報") {
            NavigationLink {
                SubsPopularView(onPick: apply)
            } label: {
                Label("人気サービスから追加", systemImage: "star")
            }

            HStack(spacing: 14) {
                Menu {
                    Button("記号と色を選ぶ", systemImage: "square.grid.2x2") { choosingSymbol = true }
                    Button("写真を選ぶ", systemImage: "photo") { choosingPhoto = true }
                    Button("App Storeから選ぶ", systemImage: "app.badge") { choosingApp = true }
                    if sub.image != nil {
                        Button("画像を外す", systemImage: "xmark.circle", role: .destructive) { sub.image = nil }
                    }
                } label: {
                    SubsIconView(sub: sub, size: 52)
                        .overlay {
                            if fetchingIcon {
                                ProgressView()
                                    .frame(width: 52, height: 52)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                }
                .accessibilityLabel("アイコン")
                TextField("サービス名", text: $sub.name)
                    .font(.system(size: 17, weight: .semibold))
            }

            HStack(spacing: 4) {
                Text("¥")
                    .foregroundStyle(.secondary)
                TextField("金額", text: $priceText)
                    .keyboardType(.numberPad)
                    .onChange(of: priceText) { _, new in
                        let digits = new.filter(\.isNumber)
                        if digits != new { priceText = digits }
                        sub.price = Int(digits) ?? 0
                    }
            }
            .font(SubsFormat.number(17, .medium))

            LabeledContent("請求サイクル") {
                Menu {
                    Button("週間") { sub.cycle = SubsCycle(unit: .week) }
                    Button("月間") { sub.cycle = .monthly }
                    Button("年間") { sub.cycle = SubsCycle(unit: .year) }
                    Divider()
                    Menu("週間カスタム") {
                        ForEach(2...10, id: \.self) { n in Button("\(n)週間") { sub.cycle = SubsCycle(unit: .week, count: n) } }
                    }
                    Menu("月間カスタム") {
                        ForEach(2...11, id: \.self) { n in Button("\(n)か月") { sub.cycle = SubsCycle(unit: .month, count: n) } }
                    }
                    Menu("年間カスタム") {
                        ForEach(2...10, id: \.self) { n in Button("\(n)年") { sub.cycle = SubsCycle(unit: .year, count: n) } }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(sub.cycle.label)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
            }

            Picker("カテゴリ", selection: Binding(
                get: { sub.category },
                set: { value in
                    if value == Self.newCategoryTag { askingCategory = true } else { sub.category = value }
                }
            )) {
                ForEach(categoryChoices, id: \.self) { Text($0).tag($0) }
                Divider()
                Text("新規作成").tag(Self.newCategoryTag)
            }
        }
    }

    private static let newCategoryTag = "\u{1}new"

    /// The store's categories, plus this one's if it came from somewhere else.
    private var categoryChoices: [String] {
        store.categories.contains(sub.category) ? store.categories : store.categories + [sub.category]
    }

    private var dates: some View {
        Section("更新日") {
            DatePicker("登録日", selection: $sub.startDate, displayedComponents: .date)
            DatePicker("次回更新日", selection: Binding(
                get: { sub.anchor },
                set: { sub.anchor = CalendarMath.startOfDay($0); renewalTouched = true }
            ), displayedComponents: .date)
        }
    }

    private var screenTime: some View {
        Section {
            if let token = SubsScreenTime.token(sub.appToken) {
                HStack {
                    if SubsScreenTime.approved {
                        Label(token)
                    } else {
                        Text("アプリを連携済み")
                    }
                    Spacer()
                    Button("解除", role: .destructive) { sub.appToken = nil }
                        .buttonStyle(.borderless)
                }
                Button("アプリを選び直す") { connect() }
            } else {
                Button {
                    connect()
                } label: {
                    Label("スクリーンタイムと連携", systemImage: "hourglass")
                }
            }
        } header: {
            Text("スクリーンタイム")
        } footer: {
            Text("このサブスクのアプリを選ぶと、アプリのアイコンを表示し、詳細画面に今月の利用時間と1時間あたりの料金が出ます。")
        }
    }

    private var trial: some View {
        Section("無料トライアル") {
            Toggle("無料トライアル中", isOn: $sub.trial)
            if sub.trial {
                DatePicker("終了日", selection: $sub.trialEnd, displayedComponents: .date)
            }
        }
    }

    // MARK: Actions

    private func followRenewal() {
        guard !renewalTouched else { return }
        sub.anchor = Sub.firstRenewal(from: CalendarMath.startOfDay(sub.startDate), cycle: sub.cycle)
    }

    private func apply(_ preset: SubsPreset) {
        sub.name = preset.name
        priceText = "\(preset.price)"
        sub.price = preset.price
        sub.cycle = preset.cycle
        sub.category = preset.category
        sub.symbol = preset.symbol
        sub.tint = preset.tint
        sub.image = nil
        followRenewal()
        fetchingIcon = true
        Task {
            if let id = preset.appID, let data = await SubsAppStore.icon(id: id) {
                sub.image = data
            }
            fetchingIcon = false
        }
    }

    private func connect() {
        Task {
            do {
                try await SubsScreenTime.authorize()
                picking = true
            } catch {
                problem = "スクリーンタイムと連携できませんでした。このWithDaysではスクリーンタイムが使えないかもしれません。（\(error.localizedDescription)）"
            }
        }
    }

    private func save() {
        sub.name = sub.name.trimmingCharacters(in: .whitespacesAndNewlines)
        sub.price = Int(priceText) ?? 0
        sub.startDate = CalendarMath.startOfDay(sub.startDate)
        sub.trialEnd = CalendarMath.startOfDay(sub.trialEnd)
        onSave(sub)
        dismiss()
    }
}

// MARK: Pictures

enum SubsImages {
    /// A square, 160pt picture for the icon.
    static func small(_ data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let side: CGFloat = 160
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let scale = max(side / image.size.width, side / image.size.height)
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rendered = UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in
            image.draw(in: CGRect(x: (side - size.width) / 2, y: (side - size.height) / 2, width: size.width, height: size.height))
        }
        return rendered.pngData()
    }
}

// MARK: Symbol and color

struct SubsSymbolPicker: View {
    @Binding var symbol: String
    @Binding var tint: UInt32
    var onPick: () -> Void

    @Environment(\.dismiss) private var dismiss

    static let symbols = [
        "play.rectangle.fill", "tv.fill", "film.fill", "music.note", "headphones", "radio.fill",
        "gamecontroller.fill", "book.fill", "newspaper.fill", "magazine.fill", "books.vertical.fill", "graduationcap.fill",
        "icloud.fill", "externaldrive.fill", "lock.shield.fill", "wifi", "phone.fill", "envelope.fill",
        "sparkles", "brain.head.profile", "paintbrush.fill", "camera.fill", "photo.fill", "doc.text.fill",
        "heart.fill", "figure.run", "dumbbell.fill", "fork.knife", "cart.fill", "bag.fill",
        "car.fill", "bicycle", "airplane", "house.fill", "pawprint.fill", "gift.fill",
        "star.fill", "bolt.fill", "globe", "creditcard.fill", "person.2.fill", "app.fill",
    ]

    static let tints: [UInt32] = [
        0xE50914, 0xFF6B35, 0xF4B400, 0x1DB954, 0x00A8E1, 0x065A8C,
        0x113CCF, 0x6E3AE6, 0xC13584, 0x8E8E93, 0x3A3A3C, 0x000000,
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                        ForEach(Self.tints, id: \.self) { color in
                            Circle()
                                .fill(Color(uiColor: UIColor(hex: color)))
                                .frame(width: 36, height: 36)
                                .overlay {
                                    if color == tint {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }
                                .onTapGesture { tint = color }
                        }
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                        ForEach(Self.symbols, id: \.self) { name in
                            SubsSymbolIcon(symbol: name, tint: tint, size: 46)
                                .overlay {
                                    if name == symbol {
                                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                                            .stroke(Color.primary, lineWidth: 2.5)
                                            .padding(-4)
                                    }
                                }
                                .onTapGesture { symbol = name }
                        }
                    }
                }
                .padding(20)
            }
            .navigationTitle("アイコン")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onPick()
                        dismiss()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .buttonStyle(.glassProminent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
