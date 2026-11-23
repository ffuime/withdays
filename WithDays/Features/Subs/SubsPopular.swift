import SwiftUI

struct SubsPreset: Identifiable, Hashable {
    let name: String
    let price: Int
    var cycle = SubsCycle.monthly
    let category: String
    let symbol: String
    let tint: UInt32
    /// The App Store search for its icon, when the name alone finds something else.
    var search: String?

    var id: String { name }
}

/// 人気サービスから追加: well-known services with a usual price, filled in with one tap.
struct SubsPopularView: View {
    var onPick: (SubsPreset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var groups: [(category: String, presets: [SubsPreset])] {
        let found = query.isEmpty ? Self.presets : Self.presets.filter {
            $0.name.localizedCaseInsensitiveContains(query) || $0.category.contains(query)
        }
        return SubsData.defaultCategories.compactMap { category in
            let list = found.filter { $0.category == category }
            return list.isEmpty ? nil : (category, list)
        }
    }

    var body: some View {
        List {
            ForEach(groups, id: \.category) { group in
                Section(group.category) {
                    ForEach(group.presets) { preset in
                        Button {
                            onPick(preset)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                SubsSymbolIcon(symbol: preset.symbol, tint: preset.tint, size: 34)
                                Text(preset.name)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.primary)
                                Spacer(minLength: 8)
                                SubsPriceText(price: preset.price, suffix: preset.cycle.suffix, size: 15)
                            }
                        }
                    }
                }
            }
            Section {
            } footer: {
                Text("料金は目安です。プランや時期で変わるので、追加したあと実際の金額に直してください。アイコンは App Store から取得します。")
            }
        }
        .searchable(text: $query, prompt: "サービスを検索")
        .navigationTitle("人気サービス")
        .navigationBarTitleDisplayMode(.inline)
    }

    static let presets: [SubsPreset] = [
        // 動画
        SubsPreset(name: "Netflix スタンダード", price: 1590, category: "動画", symbol: "play.rectangle.fill", tint: 0xE50914, search: "Netflix"),
        SubsPreset(name: "Netflix 広告つき", price: 890, category: "動画", symbol: "play.rectangle.fill", tint: 0xE50914, search: "Netflix"),
        SubsPreset(name: "Netflix プレミアム", price: 2290, category: "動画", symbol: "play.rectangle.fill", tint: 0xE50914, search: "Netflix"),
        SubsPreset(name: "Amazon プライム", price: 600, category: "動画", symbol: "shippingbox.fill", tint: 0x00A8E1, search: "Amazon Prime Video"),
        SubsPreset(name: "Amazon プライム（年）", price: 5900, cycle: SubsCycle(unit: .year), category: "動画", symbol: "shippingbox.fill", tint: 0x00A8E1, search: "Amazon Prime Video"),
        SubsPreset(name: "Disney+", price: 1140, category: "動画", symbol: "sparkles", tint: 0x113CCF, search: "Disney+"),
        SubsPreset(name: "U-NEXT", price: 2189, category: "動画", symbol: "play.tv.fill", tint: 0x111111, search: "U-NEXT"),
        SubsPreset(name: "Hulu", price: 1026, category: "動画", symbol: "tv.fill", tint: 0x1CE783, search: "Hulu"),
        SubsPreset(name: "ABEMA プレミアム", price: 1080, category: "動画", symbol: "tv.fill", tint: 0x3A3A3C, search: "ABEMA"),
        SubsPreset(name: "DAZN", price: 4200, category: "動画", symbol: "sportscourt.fill", tint: 0x111111, search: "DAZN"),
        SubsPreset(name: "YouTube Premium", price: 1280, category: "動画", symbol: "play.rectangle.fill", tint: 0xFF0000, search: "YouTube"),
        SubsPreset(name: "Apple TV+", price: 1000, category: "動画", symbol: "appletv.fill", tint: 0x000000, search: "Apple TV"),
        SubsPreset(name: "dアニメストア", price: 550, category: "動画", symbol: "film.fill", tint: 0xF15A24, search: "dアニメストア"),
        SubsPreset(name: "Lemino プレミアム", price: 990, category: "動画", symbol: "film.fill", tint: 0x6E3AE6, search: "Lemino"),
        SubsPreset(name: "TELASA", price: 618, category: "動画", symbol: "film.fill", tint: 0xF15A24, search: "TELASA"),
        SubsPreset(name: "FOD プレミアム", price: 976, category: "動画", symbol: "film.fill", tint: 0x00A0E9, search: "FOD"),
        SubsPreset(name: "ニコニコプレミアム", price: 790, category: "動画", symbol: "play.rectangle.fill", tint: 0x252525, search: "ニコニコ動画"),
        SubsPreset(name: "Crunchyroll", price: 1140, category: "動画", symbol: "play.rectangle.fill", tint: 0xF47521, search: "Crunchyroll"),
        // 音楽
        SubsPreset(name: "Spotify Premium", price: 1080, category: "音楽", symbol: "music.note", tint: 0x1DB954, search: "Spotify"),
        SubsPreset(name: "Apple Music", price: 1080, category: "音楽", symbol: "music.note", tint: 0xFA243C, search: "Apple Music"),
        SubsPreset(name: "Amazon Music Unlimited", price: 1080, category: "音楽", symbol: "music.note", tint: 0x25D1DA, search: "Amazon Music"),
        SubsPreset(name: "YouTube Music Premium", price: 1080, category: "音楽", symbol: "music.note", tint: 0xFF0000, search: "YouTube Music"),
        SubsPreset(name: "LINE MUSIC", price: 980, category: "音楽", symbol: "music.note", tint: 0x06C755, search: "LINE MUSIC"),
        SubsPreset(name: "AWA", price: 980, category: "音楽", symbol: "music.note", tint: 0x111111, search: "AWA"),
        SubsPreset(name: "Audible", price: 1500, category: "音楽", symbol: "headphones", tint: 0xF7991C, search: "Audible"),
        // ゲーム
        SubsPreset(name: "Nintendo Switch Online", price: 306, category: "ゲーム", symbol: "gamecontroller.fill", tint: 0xE60012, search: "Nintendo Switch Online"),
        SubsPreset(name: "Nintendo Switch Online（年）", price: 2400, cycle: SubsCycle(unit: .year), category: "ゲーム", symbol: "gamecontroller.fill", tint: 0xE60012, search: "Nintendo Switch Online"),
        SubsPreset(name: "PlayStation Plus エッセンシャル", price: 850, category: "ゲーム", symbol: "gamecontroller.fill", tint: 0x003791, search: "PlayStation App"),
        SubsPreset(name: "Xbox Game Pass Ultimate", price: 1450, category: "ゲーム", symbol: "gamecontroller.fill", tint: 0x107C10, search: "Xbox"),
        SubsPreset(name: "Apple Arcade", price: 800, category: "ゲーム", symbol: "gamecontroller.fill", tint: 0xFA243C, search: "Apple Arcade"),
        // ツール
        SubsPreset(name: "ChatGPT Plus", price: 3000, category: "ツール", symbol: "sparkles", tint: 0x10A37F, search: "ChatGPT"),
        SubsPreset(name: "Claude Pro", price: 3000, category: "ツール", symbol: "sparkles", tint: 0xD97757, search: "Claude by Anthropic"),
        SubsPreset(name: "Gemini（Google AI Pro）", price: 2900, category: "ツール", symbol: "sparkles", tint: 0x4285F4, search: "Google Gemini"),
        SubsPreset(name: "Microsoft 365 Personal", price: 1490, category: "ツール", symbol: "doc.text.fill", tint: 0xD83B01, search: "Microsoft 365"),
        SubsPreset(name: "Microsoft 365 Personal（年）", price: 14900, cycle: SubsCycle(unit: .year), category: "ツール", symbol: "doc.text.fill", tint: 0xD83B01, search: "Microsoft 365"),
        SubsPreset(name: "Adobe Creative Cloud", price: 7780, category: "ツール", symbol: "paintbrush.fill", tint: 0xDA1F26, search: "Adobe Creative Cloud"),
        SubsPreset(name: "Adobe Photoshop", price: 3280, category: "ツール", symbol: "paintbrush.fill", tint: 0x31A8FF, search: "Photoshop"),
        SubsPreset(name: "Canva Pro", price: 1180, category: "ツール", symbol: "paintbrush.fill", tint: 0x00C4CC, search: "Canva"),
        SubsPreset(name: "Notion Plus", price: 1650, category: "ツール", symbol: "doc.text.fill", tint: 0x000000, search: "Notion"),
        SubsPreset(name: "GoodNotes", price: 1350, cycle: SubsCycle(unit: .year), category: "ツール", symbol: "pencil.and.scribble", tint: 0x2E6BE6, search: "Goodnotes"),
        SubsPreset(name: "1Password", price: 500, category: "ツール", symbol: "lock.shield.fill", tint: 0x0572EC, search: "1Password"),
        SubsPreset(name: "NordVPN", price: 1790, category: "ツール", symbol: "lock.shield.fill", tint: 0x4687FF, search: "NordVPN"),
        SubsPreset(name: "LINEヤフー LYPプレミアム", price: 650, category: "ツール", symbol: "star.fill", tint: 0x06C755, search: "LINE"),
        SubsPreset(name: "X Premium", price: 980, category: "ツール", symbol: "bubble.left.fill", tint: 0x000000, search: "X"),
        // クラウド
        SubsPreset(name: "iCloud+ 50GB", price: 150, category: "クラウド", symbol: "icloud.fill", tint: 0x3693F3, search: "iCloud"),
        SubsPreset(name: "iCloud+ 200GB", price: 450, category: "クラウド", symbol: "icloud.fill", tint: 0x3693F3, search: "iCloud"),
        SubsPreset(name: "iCloud+ 2TB", price: 1500, category: "クラウド", symbol: "icloud.fill", tint: 0x3693F3, search: "iCloud"),
        SubsPreset(name: "Apple One 個人", price: 1200, category: "クラウド", symbol: "apple.logo", tint: 0x000000, search: "Apple One"),
        SubsPreset(name: "Google One 100GB", price: 250, category: "クラウド", symbol: "icloud.fill", tint: 0x4285F4, search: "Google One"),
        SubsPreset(name: "Google One 2TB", price: 1300, category: "クラウド", symbol: "icloud.fill", tint: 0x4285F4, search: "Google One"),
        SubsPreset(name: "Dropbox Plus", price: 1500, category: "クラウド", symbol: "externaldrive.fill", tint: 0x0061FF, search: "Dropbox"),
        SubsPreset(name: "Amazon Photos", price: 250, category: "クラウド", symbol: "photo.fill", tint: 0x00A8E1, search: "Amazon Photos"),
        // ニュース
        SubsPreset(name: "日経電子版", price: 4277, category: "ニュース", symbol: "newspaper.fill", tint: 0x0B2C5F, search: "日経電子版"),
        SubsPreset(name: "朝日新聞デジタル", price: 1980, category: "ニュース", symbol: "newspaper.fill", tint: 0xD12F2F, search: "朝日新聞デジタル"),
        SubsPreset(name: "NewsPicks", price: 1700, category: "ニュース", symbol: "newspaper.fill", tint: 0x111111, search: "NewsPicks"),
        SubsPreset(name: "Kindle Unlimited", price: 980, category: "ニュース", symbol: "book.fill", tint: 0x232F3E, search: "Kindle"),
        SubsPreset(name: "dマガジン", price: 580, category: "ニュース", symbol: "magazine.fill", tint: 0xCC0033, search: "dマガジン"),
        SubsPreset(name: "楽天マガジン", price: 572, category: "ニュース", symbol: "magazine.fill", tint: 0xBF0000, search: "楽天マガジン"),
        SubsPreset(name: "少年ジャンプ+", price: 980, category: "ニュース", symbol: "book.fill", tint: 0xE60012, search: "少年ジャンプ+"),
        // ヘルスケア
        SubsPreset(name: "Apple Fitness+", price: 980, category: "ヘルスケア", symbol: "figure.run", tint: 0x9BF00B, search: "Apple Fitness"),
        SubsPreset(name: "あすけん プレミアム", price: 480, category: "ヘルスケア", symbol: "fork.knife", tint: 0x6AB04C, search: "あすけん"),
        SubsPreset(name: "Calm", price: 1600, category: "ヘルスケア", symbol: "leaf.fill", tint: 0x3E7BE6, search: "Calm"),
        SubsPreset(name: "Strava", price: 1000, category: "ヘルスケア", symbol: "figure.run", tint: 0xFC4C02, search: "Strava"),
        SubsPreset(name: "chocoZAP", price: 3278, category: "ヘルスケア", symbol: "dumbbell.fill", tint: 0x5A3A2C, search: "chocoZAP"),
        // 教育
        SubsPreset(name: "Duolingo Super", price: 1300, category: "教育", symbol: "graduationcap.fill", tint: 0x58CC02, search: "Duolingo"),
        SubsPreset(name: "スタディサプリ", price: 2178, category: "教育", symbol: "graduationcap.fill", tint: 0x00A0E9, search: "スタディサプリ"),
        SubsPreset(name: "Udemy パーソナルプラン", price: 2000, category: "教育", symbol: "graduationcap.fill", tint: 0xA435F0, search: "Udemy"),
        SubsPreset(name: "スピーク", price: 2900, category: "教育", symbol: "mic.fill", tint: 0x2B6CF6, search: "Speak"),
        // その他
        SubsPreset(name: "Uber One", price: 498, category: "その他", symbol: "car.fill", tint: 0x000000, search: "Uber Eats"),
        SubsPreset(name: "Wolt+", price: 498, category: "その他", symbol: "bicycle", tint: 0x00C2E8, search: "Wolt"),
        SubsPreset(name: "楽天モバイル", price: 3278, category: "その他", symbol: "phone.fill", tint: 0xBF0000, search: "my 楽天モバイル"),
        SubsPreset(name: "Discord Nitro", price: 1050, category: "その他", symbol: "bubble.left.and.bubble.right.fill", tint: 0x5865F2, search: "Discord"),
        SubsPreset(name: "Tinder Plus", price: 1800, category: "その他", symbol: "heart.fill", tint: 0xFD5068, search: "Tinder"),
    ]
}
