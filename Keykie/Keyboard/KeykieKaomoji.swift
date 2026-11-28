/// Kaomoji, offered as candidates for their readings. A fixed list, kept apart from the trending words.
enum KeykieKaomoji {
    static let smiles = ["(^^)", "(*^^*)", "(^_^)", "(≧▽≦)", "(^▽^)", "(*´▽`*)", "(๑˃̵ᴗ˂̵)", "٩(ˊᗜˋ*)و", "(｡•̀ᴗ-)✧", "ヽ(*^ω^*)ﾉ"]
    static let cries = ["(T_T)", "(;_;)", "(´；ω；`)", "(ｉДｉ)", "( ;∀;)", "(つд⊂)", "。･ﾟ･(ﾉД`)･ﾟ･。"]
    static let angry = ["(`ε´)", "(#^ω^)", "(｀・ω・´)", "(╬ Ò﹏Ó)", "ヽ(`Д´)ﾉ", "(-_-メ)"]
    static let surprised = ["(ﾟДﾟ)", "Σ(ﾟдﾟ)", "(°_°)", "(⊙_⊙)", "Σ(・□・;)", "(　ﾟдﾟ)"]
    static let sad = ["(´・ω・`)", "(´-ω-`)", "(・_・;)", "(´；ω；`)", "(._.)", "orz"]
    static let shy = ["(〃ω〃)", "(*/ω＼*)", "(//∇//)", "(*ノωノ)", "(〃▽〃)"]
    static let smug = ["( ･´ｰ･｀)", "(￣ー￣)", "( ´_ゝ`)", "(｀・ω・´)ｷﾘｯ", "( ̄▽ ̄)"]
    static let hearts = ["(♡˙︶˙♡)", "(*˘︶˘*).｡.:*♡", "( ´ ▽ ` )ﾉ♡", "(灬♥ω♥灬)", "♡(ˊ艸ˋ)"]
    static let thanks = ["(*- -)(*_ _)ペコリ", "m(_ _)m", "(人´∀`)", "(o_ _)o", "ｍ(＿　＿)ｍ"]
    static let sorry = ["m(_ _)m", "(>_<)", "(´・ω・`)ゴメン", "(_ _)", "<(_ _)>"]
    static let sleepy = ["(-_-)zzz", "(´～`)", "(｡-ω-)zzz", "(_ _).｡o○", "(￣ρ￣)..zzZZ"]
    static let cats = ["(=^・^=)", "(=^・ω・^=)", "ฅ^•ﻌ•^ฅ", "(^・ω・^ )", "=^_^="]
    static let bears = ["ʕ•ᴥ•ʔ", "ʕ ·ᴥ·ʔ", "ʕ•̀ω•́ʔ✧", "ʕ⁎̯͡⁎ʔ"]
    static let yay = ["＼(^o^)／", "ヽ(=´▽`=)ﾉ", "٩( ᐛ )و", "(ﾉ≧∀≦)ﾉ", "ヾ(＾∇＾)"]
    static let peace = ["(^_-)-☆", "v(^_^)v", "(｀・ω・)v", "✌︎('ω'✌︎ )"]
    static let shrug = ["┐(´д`)┌", "¯\\_(ツ)_/¯", "┐(￣ヘ￣)┌", "ヽ(´ー`)ﾉ"]
    static let think = ["(・・?", "(｡ŏ﹏ŏ)", "(´・ω・`)?", "(・∀・)?"]
    static let wave = ["(・ω・)ノ", "(^^)/", "ヾ(・ω・*)", "(*・ω・)ﾉ", "( ´ ▽ ` )ﾉ"]

    /// Reading → faces. Readings in ひらがな.
    static let all: [(String, [String])] = [
        ("かお", smiles + cries + surprised + sad + shy + yay),
        ("かおもじ", smiles + cries + angry + surprised + sad + shy + smug + hearts + yay),
        ("わらい", smiles + yay),
        ("えがお", smiles),
        ("にこにこ", smiles),
        ("うれしい", smiles + yay),
        ("なき", cries),
        ("なく", cries),
        ("かなしい", cries + sad),
        ("おこ", angry),
        ("おこる", angry),
        ("いかり", angry),
        ("びっくり", surprised),
        ("おどろき", surprised),
        ("しょぼん", sad),
        ("がっかり", sad),
        ("てれ", shy),
        ("はずかしい", shy),
        ("どや", smug),
        ("はーと", hearts),
        ("すき", hearts),
        ("ありがとう", thanks),
        ("よろしく", thanks),
        ("ごめん", sorry),
        ("すみません", sorry),
        ("おやすみ", sleepy),
        ("ねむい", sleepy),
        ("ねこ", cats),
        ("くま", bears),
        ("やった", yay),
        ("ばんざい", yay),
        ("いえーい", yay + peace),
        ("ぴーす", peace),
        ("やれやれ", shrug),
        ("はて", think),
        ("はてな", think),
        ("やあ", wave),
        ("ばいばい", wave),
    ]
}
