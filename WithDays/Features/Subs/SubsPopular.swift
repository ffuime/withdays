import SwiftUI

struct SubsPreset: Identifiable, Hashable {
    let name: String
    let price: Int
    var cycle = SubsCycle.monthly
    let category: String
    let symbol: String
    let tint: UInt32
    /// Its App Store app, for the icon. Services without an app of their own (iCloud+ and such) keep the symbol.
    var appID: Int?

    var id: String { name }
}

/// 人気サービスから追加: well-known services with their usual price (2026年11月), filled in with one tap.
struct SubsPopularView: View {
    var onPick: (SubsPreset) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var apps: [Int: SubsStoreApp] = [:]

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
                                SubsRemoteIcon(url: preset.appID.flatMap { apps[$0]?.small }, size: 34) {
                                    SubsSymbolIcon(symbol: preset.symbol, tint: preset.tint, size: 34)
                                }
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
                Text("料金は2026年11月時点の目安です。プランや支払い方法（アプリ内課金など）で変わるので、追加したあと実際の金額に直してください。")
            }
        }
        .searchable(text: $query, prompt: "サービスを検索")
        .navigationTitle("人気サービス")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            apps = await SubsAppStore.lookup(Self.presets.compactMap(\.appID))
        }
    }

    static let presets: [SubsPreset] = [
        // 動画
        SubsPreset(name: "Netflix 広告つきスタンダード", price: 990, category: "動画", symbol: "play.rectangle.fill", tint: 0xE50914, appID: 363590051),
        SubsPreset(name: "Netflix スタンダード", price: 1790, category: "動画", symbol: "play.rectangle.fill", tint: 0xE50914, appID: 363590051),
        SubsPreset(name: "Netflix プレミアム", price: 2590, category: "動画", symbol: "play.rectangle.fill", tint: 0xE50914, appID: 363590051),
        SubsPreset(name: "Amazon プライム", price: 600, category: "動画", symbol: "shippingbox.fill", tint: 0x00A8E1, appID: 545519333),
        SubsPreset(name: "Amazon プライム（年）", price: 5900, cycle: SubsCycle(unit: .year), category: "動画", symbol: "shippingbox.fill", tint: 0x00A8E1, appID: 545519333),
        SubsPreset(name: "Disney+ スタンダード", price: 1250, category: "動画", symbol: "sparkles", tint: 0x113CCF, appID: 1446075923),
        SubsPreset(name: "Disney+ プレミアム", price: 1670, category: "動画", symbol: "sparkles", tint: 0x113CCF, appID: 1446075923),
        SubsPreset(name: "U-NEXT", price: 2189, category: "動画", symbol: "play.tv.fill", tint: 0x111111, appID: 882477693),
        SubsPreset(name: "Hulu", price: 1320, category: "動画", symbol: "tv.fill", tint: 0x1CE783, appID: 549416492),
        SubsPreset(name: "ABEMA プレミアム", price: 1180, category: "動画", symbol: "tv.fill", tint: 0x3A3A3C, appID: 1074866833),
        SubsPreset(name: "ABEMA 広告つきプレミアム", price: 680, category: "動画", symbol: "tv.fill", tint: 0x3A3A3C, appID: 1074866833),
        SubsPreset(name: "DAZN", price: 4200, category: "動画", symbol: "sportscourt.fill", tint: 0x111111, appID: 1129523589),
        SubsPreset(name: "YouTube Premium", price: 1280, category: "動画", symbol: "play.rectangle.fill", tint: 0xFF0000, appID: 544007664),
        SubsPreset(name: "Apple TV", price: 1000, category: "動画", symbol: "appletv.fill", tint: 0x000000, appID: 1174078549),
        SubsPreset(name: "dアニメストア", price: 550, category: "動画", symbol: "film.fill", tint: 0xF15A24, appID: 728214964),
        SubsPreset(name: "Lemino プレミアム", price: 990, category: "動画", symbol: "film.fill", tint: 0x6E3AE6, appID: 1641218070),
        SubsPreset(name: "TELASA", price: 618, category: "動画", symbol: "film.fill", tint: 0xF15A24, appID: 561854152),
        SubsPreset(name: "FOD プレミアム", price: 976, category: "動画", symbol: "film.fill", tint: 0x00A0E9, appID: 945241274),
        SubsPreset(name: "ニコニコプレミアム", price: 790, category: "動画", symbol: "play.rectangle.fill", tint: 0x252525, appID: 307764057),
        SubsPreset(name: "Crunchyroll", price: 1140, category: "動画", symbol: "play.rectangle.fill", tint: 0xF47521, appID: 1529194791),
        // 音楽
        SubsPreset(name: "Spotify Premium", price: 1080, category: "音楽", symbol: "music.note", tint: 0x1DB954, appID: 324684580),
        SubsPreset(name: "Apple Music", price: 1180, category: "音楽", symbol: "music.note", tint: 0xFA243C, appID: 1108187390),
        SubsPreset(name: "Amazon Music Unlimited", price: 1180, category: "音楽", symbol: "music.note", tint: 0x25D1DA, appID: 510855668),
        SubsPreset(name: "YouTube Music Premium", price: 1080, category: "音楽", symbol: "music.note", tint: 0xFF0000, appID: 1017492454),
        SubsPreset(name: "LINE MUSIC", price: 980, category: "音楽", symbol: "music.note", tint: 0x06C755, appID: 966142320),
        SubsPreset(name: "AWA", price: 980, category: "音楽", symbol: "music.note", tint: 0x111111, appID: 980578855),
        SubsPreset(name: "Audible", price: 1500, category: "音楽", symbol: "headphones", tint: 0xF7991C, appID: 379693831),
        // ゲーム
        SubsPreset(name: "Nintendo Switch Online", price: 400, category: "ゲーム", symbol: "gamecontroller.fill", tint: 0xE60012, appID: 1234806557),
        SubsPreset(name: "Nintendo Switch Online（年）", price: 3000, cycle: SubsCycle(unit: .year), category: "ゲーム", symbol: "gamecontroller.fill", tint: 0xE60012, appID: 1234806557),
        SubsPreset(name: "PlayStation Plus エッセンシャル", price: 850, category: "ゲーム", symbol: "gamecontroller.fill", tint: 0x003791, appID: 410896080),
        SubsPreset(name: "Xbox Game Pass Ultimate", price: 1450, category: "ゲーム", symbol: "gamecontroller.fill", tint: 0x107C10, appID: 736179781),
        SubsPreset(name: "Apple Arcade", price: 800, category: "ゲーム", symbol: "gamecontroller.fill", tint: 0xFA243C),
        // ツール
        SubsPreset(name: "ChatGPT Plus", price: 3000, category: "ツール", symbol: "sparkles", tint: 0x10A37F, appID: 6448311069),
        SubsPreset(name: "Claude Pro", price: 3000, category: "ツール", symbol: "sparkles", tint: 0xD97757, appID: 6473753684),
        SubsPreset(name: "Google AI Pro", price: 2900, category: "ツール", symbol: "sparkles", tint: 0x4285F4, appID: 6477489729),
        SubsPreset(name: "Microsoft 365 Personal", price: 2130, category: "ツール", symbol: "doc.text.fill", tint: 0xD83B01, appID: 541164041),
        SubsPreset(name: "Microsoft 365 Personal（年）", price: 21300, cycle: SubsCycle(unit: .year), category: "ツール", symbol: "doc.text.fill", tint: 0xD83B01, appID: 541164041),
        SubsPreset(name: "Adobe Creative Cloud Pro", price: 9080, category: "ツール", symbol: "paintbrush.fill", tint: 0xDA1F26),
        SubsPreset(name: "Adobe Photoshop", price: 3280, category: "ツール", symbol: "paintbrush.fill", tint: 0x31A8FF, appID: 1457771281),
        SubsPreset(name: "Canva Pro", price: 1180, category: "ツール", symbol: "paintbrush.fill", tint: 0x00C4CC, appID: 897446215),
        SubsPreset(name: "Notion Plus", price: 1650, category: "ツール", symbol: "doc.text.fill", tint: 0x000000, appID: 1232780281),
        SubsPreset(name: "Goodnotes", price: 1350, cycle: SubsCycle(unit: .year), category: "ツール", symbol: "pencil.and.scribble", tint: 0x2E6BE6, appID: 1444383602),
        SubsPreset(name: "1Password", price: 500, category: "ツール", symbol: "lock.shield.fill", tint: 0x0572EC, appID: 1511601750),
        SubsPreset(name: "NordVPN", price: 1790, category: "ツール", symbol: "lock.shield.fill", tint: 0x4687FF, appID: 905953485),
        SubsPreset(name: "LYPプレミアム", price: 650, category: "ツール", symbol: "star.fill", tint: 0x06C755, appID: 443904275),
        SubsPreset(name: "X Premium", price: 980, category: "ツール", symbol: "bubble.left.fill", tint: 0x000000, appID: 333903271),
        // クラウド
        SubsPreset(name: "iCloud+ 50GB", price: 150, category: "クラウド", symbol: "icloud.fill", tint: 0x3693F3),
        SubsPreset(name: "iCloud+ 200GB", price: 450, category: "クラウド", symbol: "icloud.fill", tint: 0x3693F3),
        SubsPreset(name: "iCloud+ 2TB", price: 1500, category: "クラウド", symbol: "icloud.fill", tint: 0x3693F3),
        SubsPreset(name: "Apple One 個人", price: 1200, category: "クラウド", symbol: "apple.logo", tint: 0x000000),
        SubsPreset(name: "Google One 100GB", price: 250, category: "クラウド", symbol: "icloud.fill", tint: 0x4285F4, appID: 1451784328),
        SubsPreset(name: "Google One 2TB", price: 1300, category: "クラウド", symbol: "icloud.fill", tint: 0x4285F4, appID: 1451784328),
        SubsPreset(name: "Dropbox Plus", price: 1500, category: "クラウド", symbol: "externaldrive.fill", tint: 0x0061FF, appID: 327630330),
        SubsPreset(name: "Amazon Photos", price: 250, category: "クラウド", symbol: "photo.fill", tint: 0x00A8E1, appID: 621574163),
        // ニュース
        SubsPreset(name: "日経電子版", price: 4277, category: "ニュース", symbol: "newspaper.fill", tint: 0x0B2C5F, appID: 396855834),
        SubsPreset(name: "朝日新聞デジタル", price: 1980, category: "ニュース", symbol: "newspaper.fill", tint: 0xD12F2F, appID: 429622552),
        SubsPreset(name: "NewsPicks", price: 1700, category: "ニュース", symbol: "newspaper.fill", tint: 0x111111, appID: 640956497),
        SubsPreset(name: "Kindle Unlimited", price: 980, category: "ニュース", symbol: "book.fill", tint: 0x232F3E, appID: 302584613),
        SubsPreset(name: "dマガジン", price: 580, category: "ニュース", symbol: "magazine.fill", tint: 0xCC0033, appID: 859681456),
        SubsPreset(name: "楽天マガジン", price: 572, category: "ニュース", symbol: "magazine.fill", tint: 0xBF0000, appID: 1136986870),
        SubsPreset(name: "少年ジャンプ+", price: 980, category: "ニュース", symbol: "book.fill", tint: 0xE60012, appID: 875750302),
        // ヘルスケア
        SubsPreset(name: "Apple Fitness+", price: 980, category: "ヘルスケア", symbol: "figure.run", tint: 0x9BF00B, appID: 1208224953),
        SubsPreset(name: "あすけん プレミアム", price: 480, category: "ヘルスケア", symbol: "fork.knife", tint: 0x6AB04C, appID: 687287242),
        SubsPreset(name: "Calm", price: 1600, category: "ヘルスケア", symbol: "leaf.fill", tint: 0x3E7BE6, appID: 571800810),
        SubsPreset(name: "Strava", price: 1000, category: "ヘルスケア", symbol: "figure.run", tint: 0xFC4C02, appID: 426826309),
        SubsPreset(name: "chocoZAP", price: 3278, category: "ヘルスケア", symbol: "dumbbell.fill", tint: 0x5A3A2C, appID: 1613682287),
        // 教育
        SubsPreset(name: "Duolingo Super", price: 1300, category: "教育", symbol: "graduationcap.fill", tint: 0x58CC02, appID: 570060128),
        SubsPreset(name: "スタディサプリ", price: 2178, category: "教育", symbol: "graduationcap.fill", tint: 0x00A0E9, appID: 1059640427),
        SubsPreset(name: "Udemy パーソナルプラン", price: 2000, category: "教育", symbol: "graduationcap.fill", tint: 0xA435F0, appID: 562413829),
        SubsPreset(name: "スピーク", price: 2900, category: "教育", symbol: "mic.fill", tint: 0x2B6CF6, appID: 1286609883),
        // その他
        SubsPreset(name: "Uber One", price: 498, category: "その他", symbol: "car.fill", tint: 0x000000, appID: 1058959277),
        SubsPreset(name: "Wolt+", price: 498, category: "その他", symbol: "bicycle", tint: 0x00C2E8, appID: 943905271),
        SubsPreset(name: "楽天モバイル", price: 3278, category: "その他", symbol: "phone.fill", tint: 0xBF0000, appID: 1473535769),
        SubsPreset(name: "Discord Nitro", price: 1050, category: "その他", symbol: "bubble.left.and.bubble.right.fill", tint: 0x5865F2, appID: 985746746),
        SubsPreset(name: "Tinder Plus", price: 1800, category: "その他", symbol: "heart.fill", tint: 0xFD5068, appID: 547702041),
    ]
}
