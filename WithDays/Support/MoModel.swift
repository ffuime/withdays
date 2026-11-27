import SwiftUI

/// Mo (household budget): expenses and income, each with its own categories.
enum MoKind: String, Codable, CaseIterable {
    case expense, income

    var label: String { self == .expense ? "支出" : "収入" }
    /// Red for money going out, green for money coming in (as on the web app).
    var color: Color { self == .expense ? .moExpense : .moIncome }
}

struct MoCategory: Codable, Equatable, Hashable, Identifiable {
    var label: String
    /// An SF Symbol name.
    var icon: String

    var id: String { label }
}

struct MoRecord: Codable, Equatable, Identifiable {
    var id: String
    var amount: Int
    var kind: MoKind
    /// The category is copied in, so records keep their name and icon after it's renamed away or deleted.
    var category: String
    var icon: String
    var memo: String
    var date: Date
}

struct MoState: Codable, Equatable {
    var records: [MoRecord] = []
    var expenseCategories: [MoCategory] = MoState.defaultCategories(.expense)
    var incomeCategories: [MoCategory] = MoState.defaultCategories(.income)

    static func defaultCategories(_ kind: MoKind) -> [MoCategory] {
        switch kind {
        case .expense:
            [
                MoCategory(label: "食事", icon: "fork.knife"),
                MoCategory(label: "日用品", icon: "basket"),
                MoCategory(label: "趣味", icon: "face.smiling"),
                MoCategory(label: "その他", icon: "ellipsis"),
            ]
        case .income:
            [
                MoCategory(label: "給与", icon: "banknote"),
                MoCategory(label: "臨時収入", icon: "gift"),
                MoCategory(label: "その他", icon: "ellipsis"),
            ]
        }
    }
}

/// Saved as one JSON file in the App Group container (or the app's own documents without one).
enum MoData {
    private static var url: URL {
        let base = AppGroup.identifier.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) }
            ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appending(path: "mo.json")
    }

    static func load() -> MoState {
        guard let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(MoState.self, from: data) else {
            return MoState()
        }
        return state
    }

    static func save(_ state: MoState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func newID() -> String {
        "record-\(UUID().uuidString)"
    }
}

/// The category icons to choose from: SF Symbols in groups. The search matches the group or the symbol name.
enum MoIcons {
    struct Group: Identifiable {
        let title: String
        let symbols: [String]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "食事", symbols: [
            "fork.knife", "cup.and.saucer", "mug", "takeoutbag.and.cup.and.straw", "wineglass", "birthday.cake",
            "carrot", "fish", "frying.pan", "popcorn", "waterbottle", "leaf",
            "cup.and.heat.waves", "wineglass.fill", "fork.knife.circle", "flame.fill", "oven", "stove", "microwave",
            "refrigerator.fill", "takeoutbag.and.cup.and.straw.fill", "carrot.fill",
        ]),
        Group(title: "買い物", symbols: [
            "basket", "cart", "bag", "handbag", "gift", "giftcard", "shippingbox", "tag", "storefront", "barcode",
            "cart.fill", "bag.fill", "creditcard.and.123", "cube.box", "shippingbox.fill", "tag.fill", "gift.fill",
            "bag.circle", "hanger", "eyedropper",
        ]),
        Group(title: "交通", symbols: [
            "tram", "train.side.front.car", "bus", "car", "airplane", "bicycle", "scooter", "ferry", "fuelpump",
            "parkingsign", "figure.walk", "suitcase",
            "car.fill", "bus.fill", "tram.fill", "cablecar", "sailboat", "airplane.departure", "car.2",
            "bicycle.circle", "figure.outdoor.cycle", "road.lanes", "location", "ev.charger",
        ]),
        Group(title: "住まい", symbols: [
            "house", "building.2", "bed.double", "sofa", "lamp.desk", "washer", "refrigerator", "lightbulb", "bolt",
            "drop", "flame", "wifi", "wrench.and.screwdriver", "hammer", "trash",
            "house.fill", "key", "door.left.hand.open", "chair.lounge", "bathtub", "toilet", "fan",
            "air.conditioner.horizontal", "heater.vertical", "spigot", "paintbrush.pointed", "lightbulb.fill",
            "powerplug", "trash.fill",
        ]),
        Group(title: "通信・家電", symbols: [
            "iphone", "phone", "laptopcomputer", "desktopcomputer", "tv", "headphones", "camera", "printer",
            "gamecontroller", "applewatch",
            "ipad", "macbook", "airpods", "homepod", "appletv", "keyboard", "computermouse",
            "antenna.radiowaves.left.and.right", "simcard", "battery.100", "externaldrive", "speaker.wave.2",
        ]),
        Group(title: "健康・美容", symbols: [
            "cross.case", "pills", "stethoscope", "bandage", "heart", "dumbbell", "figure.run", "scissors", "comb",
            "shower", "sparkles", "eyeglasses",
            "heart.fill", "cross", "syringe", "facemask", "allergens", "brain", "lungs", "figure.yoga",
            "figure.pool.swim", "bed.double.fill", "mouth", "nose", "hands.sparkles", "drop.fill",
        ]),
        Group(title: "衣服", symbols: ["tshirt", "shoe", "crown", "backpack", "umbrella",
            "tshirt.fill", "jacket", "coat", "shoe.2", "hat.widebrim", "eyeglasses.circle", "sunglasses",
            "handbag.fill", "bag.badge.plus", "scissors.circle",
        ]),
        Group(title: "趣味・娯楽", symbols: [
            "face.smiling", "music.note", "film", "theatermasks", "ticket", "book", "books.vertical", "newspaper",
            "paintpalette", "guitars", "pianokeys", "puzzlepiece", "dice", "photo", "tennisball", "soccerball",
            "basketball", "binoculars", "beach.umbrella", "tent", "mountain.2", "globe.asia.australia", "map",
            "music.mic", "headphones.circle", "film.stack", "tv.fill", "gamecontroller.fill",
            "book.closed", "magazine", "camera.fill", "video", "figure.golf", "figure.skiing.downhill",
            "figure.hiking", "figure.fishing", "baseball", "football", "volleyball", "trophy", "flag.checkered",
            "party.popper", "balloon", "fireworks", "sparkles.tv", "camera.macro", "leaf.fill", "tree",
        ]),
        Group(title: "学び・仕事", symbols: [
            "graduationcap", "pencil", "studentdesk", "doc.text", "envelope", "briefcase", "calendar", "clock",
            "book.pages", "pencil.and.ruler", "ruler", "folder", "paperclip", "tray.full", "chart.bar",
            "list.clipboard", "building", "person.badge.key", "signature", "printer.fill",
        ]),
        Group(title: "人・ペット", symbols: [
            "person", "person.2", "figure.and.child.holdinghands", "heart.circle", "pawprint", "dog", "cat", "bird",
            "tortoise",
            "person.fill", "person.3", "figure.2.and.child.holdinghands", "baby.carriage", "teddybear",
            "figure.walk.motion", "pawprint.fill", "fish.fill", "hare", "ladybug", "ant", "cat.fill", "dog.fill",
        ]),
        Group(title: "お金", symbols: [
            "yensign", "yensign.circle", "banknote", "creditcard", "wallet.bifold", "building.columns",
            "chart.line.uptrend.xyaxis", "percent", "dollarsign.circle", "bitcoinsign.circle", "hand.thumbsup",
            "yensign.square", "banknote.fill", "creditcard.fill", "wallet.pass", "building.columns.fill", "chart.pie",
            "chart.line.downtrend.xyaxis", "arrow.up.arrow.down", "dollarsign", "eurosign.circle",
            "sterlingsign.circle", "giftcard.fill", "doc.text.fill", "receipt", "hand.raised", "heart.text.square",
            "shield.lefthalf.filled",
        ]),
        Group(title: "その他", symbols: [
            "ellipsis", "star", "flag", "bell", "gearshape", "sun.max", "snowflake", "cloud.rain", "smoke",
            "questionmark",
            "star.fill", "flag.fill", "bell.fill", "moon", "cloud.sun", "bolt.fill", "drop.triangle",
            "exclamationmark.triangle", "checkmark.seal", "infinity", "number", "circle.grid.2x2", "square.grid.2x2",
            "staroflife", "atom", "globe", "airtag", "lock", "wrench",
        ]),
    ]

    /// Groups trimmed to the symbols this system has, and to the search.
    static func filtered(_ query: String) -> [Group] {
        let text = query.trimmingCharacters(in: .whitespaces).lowercased()
        return groups.compactMap { group in
            let available = group.symbols.filter { UIImage(systemName: $0) != nil }
            let matching = text.isEmpty || group.title.contains(text) ? available : available.filter { $0.contains(text) }
            return matching.isEmpty ? nil : Group(title: group.title, symbols: matching)
        }
    }

    /// Names from the first build (a bundled icon set) map to symbols; anything unknown shows a tag.
    static func resolve(_ name: String) -> String {
        if UIImage(systemName: name) != nil { return name }
        let legacy = [
            "mo-meal": "fork.knife", "mo-daily": "basket", "mo-hobby": "face.smiling", "more": "ellipsis",
            "mo-salary": "banknote", "mo-bonus": "gift",
        ]
        return legacy[name] ?? "tag"
    }
}

extension Color {
    static let moExpense = Color(uiColor: UIColor(light: 0xDC2626, dark: 0xF05252))
    static let moIncome = Color(uiColor: UIColor(light: 0x16A34A, dark: 0x31C463))
}

/// A category icon.
struct MoIcon: View {
    let name: String
    var size: CGFloat = 24

    var body: some View {
        Image(systemName: MoIcons.resolve(name))
            .font(.system(size: size * 0.85, weight: .medium))
            .frame(width: size, height: size)
    }
}

enum MoFormat {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter
    }()

    /// 12,345
    static func amount(_ value: Int) -> String {
        formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private static let shortDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ja_JP")
        formatter.calendar = CalendarMath.calendar
        formatter.dateFormat = "M/d(E)"
        return formatter
    }()

    /// Axis labels: 3,000 / 1.2万.
    static func compact(_ value: Int) -> String {
        guard value >= 10_000 else { return amount(value) }
        let man = Double(value) / 10_000
        return man == man.rounded() ? "\(Int(man))万" : String(format: "%.1f万", man)
    }

    /// 11/26(水)
    static func shortDay(_ date: Date) -> String {
        shortDayFormatter.string(from: date)
    }

    /// Rounded system digits for amounts and the keypad.
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}
