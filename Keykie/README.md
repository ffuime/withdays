# Keykie

WithDays に入っている日本語キーボード（Keyboard Extension）です。12キーのフリック入力（Simeji と同じ並び）と、変換エンジン [AzooKeyKanaKanjiConverter](https://github.com/azooKey/AzooKeyKanaKanjiConverter)（MIT）を使います。個人利用向けで、WithDays.ipa をサイドロードすると一緒に入ります。

## 構成

| 場所 | 中身 |
| --- | --- |
| `Keykie/Keyboard/` | キーボード拡張だけのコード（`KeykieViewController` が本体。SwiftUI のボード、変換、ジェスチャー、クリップボード、絵文字） |
| `Keykie/Shared/` | WithDays とキーボードの両方に入るコード（設定キーと初期値、ユーザー辞書・定型文・流行語、クリップボード履歴、バックアップ） |
| `WithDays/Features/Keykie/` | ホストアプリ側の設定画面（設定 › キーボード › Keykie） |
| `trending/` | 流行語辞書を作るスクリプト（毎日 GitHub Actions で実行） |

### ターゲット（project.yml）

- **Keykie**（app-extension、`com.ffuime.withdays.keykie`）。WithDays に埋め込まれます。依存は `KanaKanjiConverterModuleWithDefaultDictionary`（0.11.2 に固定。0.x は小さい版でも API が変わるため）
- **WithDays** は `Keykie/Shared` をソースに含み、Keykie をターゲット依存に持ちます（変換エンジンはリンクしません）

### App Group

`group.com.ffuime.withdays`（WithDays・ウィジェットと同じ）。SideStore / AltStore で再署名されたときは `ALTAppGroups` の名前を使います（`KeykieGroup.identifier`）。

- 設定：グループの UserDefaults に `keykie.*` のキーで保存
- ファイル：グループのコンテナの `Keykie/` に `userdict.json`・`phrases.json`・`trending.json`・`clipboard.json`・`background.jpg`、学習データは `Keykie/Memory/`

### Info.plist（NSExtension）

```
NSExtensionPointIdentifier  com.apple.keyboard-service
NSExtensionPrincipalClass   $(PRODUCT_MODULE_NAME).KeykieViewController
NSExtensionAttributes
  IsASCIICapable      false
  PrefersRightToLeft  false
  PrimaryLanguage     ja-JP
  RequestsOpenAccess  true
```

## レイアウト

```
 [📋]  候補 / カーソル移動のスワイプ             [⌄]
 [Delete] [ あ ][ か ][ さ ] [  ⌫  ]
 [☆123 ]  [ た ][ な ][ は ] [ 空白 ]
 [ あ/A ] [ ま ][ や ][ ら ] [      ]
 [  😀  ] [小゛゜][ わ ][、。?!] [ 改行 ]
```

- **⌫**：カーソルの左を1文字。長押しで連続。左スワイプで行頭まで（行頭なら前の改行だけ）。確認（初期オフ）と「元に戻す」（初期オン）を設定で選べます
- **Delete**：カーソルの右を1文字（Windows と同じ）。`textDocumentProxy` には前方削除がないので、`adjustTextPosition(byCharacterOffset:)` で右へ動いてから `deleteBackward()` します。右スワイプで行末まで（初期オフ）
- **空白**：タップで半角、左スワイプで全角（初期値は設定で入れ替え可）。入力中は「変換」になり候補を順に選びます。カーソル移動を割り当てると、全角／半角は上スワイプになります
- **候補バー**：未入力のときは左右のスワイプでカーソル移動（← → キーはありません）。入力中は候補、右の ⊞ で全候補
- **⌄**：キーボードを閉じる（`dismissKeyboard()`）。指定の `chevron.bottom` は SF Symbols にないため `chevron.down` を使っています
- **😀** の長押し：次のキーボードへ
- 数字テンキーの記号（左／上／右／下）は 設定 › ジェスチャー › 数字キーのフリック記号 で変えられます
- 英字はテンキー（初期）か QWERTY、日本語はフリック（初期）かローマ字 QWERTY を選べます

## クリップボード履歴の制約

**iOS では、キーボードがバックグラウンドでクリップボード（UIPasteboard）を見張ることはできません。** Keykie が履歴に入れるのは次のときだけです。

- キーボードが表示されたとき（`viewWillAppear`）
- キーボードを出したままのアプリに戻ってきたとき（`NSExtensionHostWillEnterForeground`）

そのため、キーボードを開かずに何度もコピーすると、最後のもの以外は残りません。また、履歴にはフルアクセスが必要です。

除外について：

- パスワード管理アプリの多くは、コピーに `org.nspasteboard.ConcealedType` / `TransientType` の印を付けます。この印があるものは保存しません（初期オン）
- 文字列のルール（含む文字、または `/正規表現/`）で除外できます
- **コピー元のアプリでの除外はできません。** iOS はキーボードにコピー元のアプリを教えないためです

## メモリ

キーボード拡張は使えるメモリが小さい（約60MB）ため、

- 辞書は先読みせず、変換で必要になった部分だけ読み込みます（`preloadDictionary: false`）
- 変換は専用のキューで非同期に行い、キーの反応を止めません。古い要求の結果は捨てます
- 背景画像は幅900ptに縮めて読み込みます

## 流行語辞書

`trending/` のスクリプトが毎日 `trending/trending.json` を更新し、WithDays（起動時）とフルアクセスのある Keykie（表示時）が設定した頻度で取り込みます。詳しくは [trending/README.md](../trending/README.md)。顔文字は別の固定リスト（`KeykieKaomoji.swift`）で、「かお」「わらい」「ねこ」などの読みで候補に出ます。

## 動作確認

Windows ではビルドできないので、GitHub Actions のビルド（`Build IPA`）が最初のコンパイル確認になります。

1. `main` に push → Actions の Artifacts から `WithDays.ipa` を入れる
2. iPhone の 設定 › アプリ › WithDays › キーボード で Keykie をオン、フルアクセスを許可
3. WithDays › 設定 › キーボード › Keykie の「試し打ち」で確認する

| 段階 | 確かめること |
| --- | --- |
| 1 基本入力＋変換 | フリック・トグル入力・小゛゜、候補のタップで確定、空白で次の候補、改行で確定、全候補 |
| 2 ジェスチャー | ⌫ の長押し・左スワイプ（行頭／前の改行）と元に戻す、Delete の1文字・右スワイプ、候補バーと空白キーのカーソル移動、全角空白 |
| 3 クリップボード | 別アプリでコピー → キーボードを開く → 📋 に出る、タップで入力、左スワイプで削除、右スワイプでピン留め、全消去、定型文タブ |
| 4 絵文字 | カテゴリ、最近使った絵文字、🔍 で「ねこ」「cat」の検索 |
| 5 設定 | 各設定を変えてキーボードを開き直すと反映される、バックアップと復元、リセット |
| 6 スキン | スキンの切り替え、ダーク／ライト、カスタムの色、背景画像、角丸・影・枠線・高さ、片手モード |
| 7 流行語辞書 | 辞書 › 今すぐ更新 で語数が増える、その語が変換候補に出る |
