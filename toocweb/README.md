# tooc web

tooc の Web 版です。iOS 版と同じ Firebase プロジェクト（fftooc）を使い、トーク・友だち・じぶん・プロフィール・写真・ファイル・位置情報・リアクション・投票・日程調整・あみだくじ・送信予約・アカウント切り替え・設定まで、iOS 版と同じデータでやりとりできます。

ビルドは不要な静的サイトです（HTML / CSS / JavaScript。Firebase の JavaScript SDK と QR コードのライブラリは CDN から読み込みます）。

```
toocweb/
  _redirects          ffui.me/tooc/@ID を Web 版に渡す（Cloudflare Pages）
  tooc/
    index.html
    style.css
    app.js
    config.js         Firebase の Web アプリの設定（要記入）
```

## 1. Firebase に Web アプリを登録する

1. Firebase コンソール → fftooc → プロジェクトの設定 → 「マイアプリ」で「ウェブ」（`</>`）を追加します（名前は「tooc web」など。Hosting は不要）。
2. 表示される `firebaseConfig` の値を `tooc/config.js` に書き写します（`apiKey`・`messagingSenderId`・`appId` など）。この値は公開されても問題のない識別子です。
3. Authentication → 設定 → 「承認済みドメイン」に `ffui.me` を追加します。

## 2. Cloudflare Pages に置く

- **ffui.me をこの Pages プロジェクトで公開する場合**：Pages の「ビルド出力ディレクトリ」を `toocweb` にします（ビルドコマンドなし）。`https://ffui.me/tooc/` で開けます。
- **ffui.me にすでに別のサイトがある場合**：そのサイトの公開フォルダに `tooc/` フォルダをそのまま入れ、`_redirects` の2行をそのサイトの `_redirects` に足してください。

## 3. QR コード

iOS 版・Web 版の MyQR は `https://ffui.me/tooc/@toocID` を指します。

- アプリを入れている人がそのページを開くと「tooc（アプリ）で開く」から `withdays://tooc?add=ID` で iOS 版の友だち検索が開きます。
- ログインしている Web 版ではそのまま友だち検索が開きます。
