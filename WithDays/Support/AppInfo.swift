import Foundation

enum AppInfo {
    static let name = "WithDays"
    static let summary = "WithDays は、Appleのカレンダーの予定をそのまま読み書きする月表示のカレンダーです。iPhone や Mac のカレンダーと自動で同期されます。"
    static let repositoryURL = URL(string: "https://github.com/ffuime/withdays")!

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "–"
    }

    struct Release: Identifiable {
        let version: String
        let date: String
        let notes: [String]

        var id: String { version }
    }

    /// Newest first. Add an entry here with each release.
    static let changelog: [Release] = [
        Release(version: "2.0.0", date: "2026.11.15", notes: [
            "ホーム画面：iPhoneのようなホーム画面から各アプリを開く（6×4・Dock・ページ）",
            "ホーム画面：長押しで並べ替え、重ねてフォルダ、壁紙を写真から",
            "下端から上にスワイプでホーム画面へ",
        ]),
        Release(version: "1.9.0", date: "2026.11.14", notes: [
            "Slides：長押しで複数選択（範囲で囲んで選択）、まとめて移動・整列・書式・削除",
            "Slides：複数の要素に同じアニメーションを同時に",
            "Slides：選択中の要素だけを移動、画像の書き出しは写真に保存",
        ]),
        Release(version: "1.8.0", date: "2026.11.14", notes: [
            "Slides：コピー・貼り付け（他のアプリの画像や文字も）、画像のドラッグ＆ドロップ",
            "Slides：アニメーション「移動」（前のスライドの同じ要素から動く）",
            "Slides：このスライドだけを画像 / PDFで書き出し、背景をすべてのスライドに適用",
        ]),
        Release(version: "1.7.4", date: "2026.11.14", notes: [
            "Slides：角で縦横比を保って拡大縮小、画像を伸ばせるように",
            "Slides：文字入力をスライドと同じ見た目で",
        ]),
        Release(version: "1.7.3", date: "2026.11.13", notes: [
            "Slides：トランジション・アニメーションの方向、ズームイン / アウト",
            "Slides：画像をリンクから挿入（SVG対応）",
        ]),
        Release(version: "1.7.2", date: "2026.11.13", notes: [
            "Slides：文字の縁取りと影、なめらかな拡大",
            "Slides：トランジションで前のスライドが残るように、戻るときは逆向きに",
        ]),
        Release(version: "1.7.1", date: "2026.11.13", notes: [
            "Slides：吸着、スライドの表示の拡大、フォントのウェイト",
            "Slides：プレースホルダー、お気に入りの☆、▶長押しで現在のスライドから再生",
        ]),
        Release(version: "1.7.0", date: "2026.11.13", notes: [
            "Slides：スライド作成（テキスト・画像・シェイプ・ライン・テーブル）",
            "Slides：再生（トランジション・アニメーション）、PDF / PowerPoint 書き出し",
            "Slides：タイトル・本文・画像内の文字で検索",
        ]),
        Release(version: "1.6.2", date: "2026.11.12", notes: [
            "Notes：テープを一時的にすべて隠す",
            "Notes：より細い線、より大きな拡大",
        ]),
        Release(version: "1.6.1", date: "2026.11.12", notes: [
            "Notes：テキストボックスのフォント",
            "Notes：線やテープの端をつまんで長さ・向きを調整",
        ]),
        Release(version: "1.6.0", date: "2026.11.11", notes: [
            "Notes：選択ツール（移動・拡大縮小・重ね順・色変え・カット）",
            "Notes：文字認識（ページの文字をコピー、検索、手書きをテキストに）",
            "Notes：ページ一覧、2本指 / 3本指タップで取り消し / やり直し",
            "Notes：折れ線にも補正、テープとテキストも取り消せる",
        ]),
        Release(version: "1.5.1", date: "2026.11.11", notes: [
            "Notes：書類のスキャン、マスキングテープ、テキストボックス",
            "Notes：太さ・色を無段階に、プリセット保存（長押し）",
            "Notes：長押しで直線、ツールバーを端へ移動",
        ]),
        Release(version: "1.5.0", date: "2026.11.11", notes: [
            "Notes：手書きノート（フォルダ・用紙・蛍光ペン・投げ縄）",
            "Notes：PDF / 画像の取り込みと書き出し",
        ]),
        Release(version: "1.4.1", date: "2026.11.03", notes: [
            "＋ボタン長押しのメニューにTdを追加、各ロゴを刷新",
            "Mo：＋ボタンをダブルタップで支出 / 収入を切り替え",
            "Go：電車の検索は駅までの徒歩を待たず今の時刻から",
        ]),
        Release(version: "1.4.0", date: "2026.11.03", notes: [
            "Mo：家計簿（入力・統計・カレンダー）",
            "＋ボタン長押しでMo / Goを選んで開く",
        ]),
        Release(version: "1.3.2", date: "2026.11.02", notes: [
            "カレンダーの編集（右スワイプ）",
            "Go：長押しでプリセット、上下スワイプで画面の明るさ",
        ]),
        Release(version: "1.3.1", date: "2026.11.01", notes: [
            "Go：＋ボタン長押しで、駅までの経路から乗る電車の発車時刻をプリセットに",
        ]),
        Release(version: "1.3.0", date: "2026.11.01", notes: [
            "Go：次の目標時刻までのカウントダウン（＋ボタン長押しで開く）",
            "Goのロック画面ウィジェット（タップでGoを開く）",
            "Go表示中は自動ロックしない",
        ]),
        Release(version: "1.2.2", date: "2026.10.27", notes: [
            "過去の予定を薄く表示する設定",
            "移動・複製・ToDo削除の取り消し",
        ]),
        Release(version: "1.2.1", date: "2026.10.25", notes: [
            "日付・ToDoカテゴリを横スワイプで切り替え",
            "新しいアイコン",
        ]),
        Release(version: "1.2.0", date: "2026.10.24", notes: [
            "ToDo（Appleのリマインダーと同期）とToDoウィジェット",
            "カレンダー上で予定を移動・複製",
            "削除の取り消し",
        ]),
        Release(version: "1.1.0", date: "2026.10.24", notes: [
            "今週の予定ウィジェット",
        ]),
        Release(version: "1.0.0", date: "2026.10.23", notes: [
            "はじめてのリリース",
        ]),
    ]
}
