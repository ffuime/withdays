# 流行語辞書（trending）

Keykie の流行語辞書を作るスクリプトです。GitHub Actions（`.github/workflows/trending.yml`）が毎日 10:30（日本時間）に実行し、`trending.json` と `trending.csv` を更新して `main` に commit します。この commit では IPA のビルドは走りません（`build.yml` の `paths-ignore`）。

## しくみ

1. **急上昇の記事**：Wikimedia Pageviews API で日本語版 Wikipedia の前日の閲覧数上位（最大1000件）を取り、その前7日の中央値と比べて急に伸びた記事を選びます（`spike_score`）。特別ページ・メインページ・一覧記事・年月日だけの記事は除きます
2. **表記**：記事名から「(テレビドラマ)」のような括弧を外したもの
3. **読み**（上ほど優先）
   - Wikidata の「仮名表記」（P1814）
   - 記事冒頭の「表記（よみ、…）」
   - Sudachi（`sudachipy` + `sudachidict_core`）の読み
   - 読みが付かない語は入れません
4. **品詞**：Wikidata で人（Q5）なら「人名」、ほかは「固有名詞」。職業がポルノ俳優（P106 = Q488111）の人は除きます
5. **残す期間**：新しい語を先頭に、30日たった語は消えます（最大3000語）

## 出力

```json
{
 "updated": "2026-11-27",
 "source": "Wikimedia Pageviews API (ja.wikipedia), Wikidata, Wikipedia",
 "words": [
  {"reading": "おおたにしょうへい", "word": "大谷翔平", "pos": "人名", "date": "2026-11-27"}
 ]
}
```

`trending.csv` は同じ内容の `読み,表記,品詞`。Keykie はどちらの形式も読めます（設定 › 辞書 › 更新URL）。

## 手元で動かす

```bash
pip install -r trending/requirements.txt
```

```bash
python trending/build_trending.py --date 2026-11-27 --out /tmp/trending.json
```

```bash
cd trending && python -m pytest -q
```

オプション：`--history`（比べる日数、7）、`--limit`（1日に足す語数、150）、`--keep`（残す日数、30）、`--max`（最大語数、3000）。

Wikimedia の API はわかりやすい User-Agent を求めています。必要なら環境変数 `TRENDING_USER_AGENT` で連絡先を入れてください。

## 注意

- 閲覧数の上位には、そのときどきの話題の人名が多く入ります。辞書に入れたくない語が混ざることがあります
- Sudachi が入っていない環境では、Wikidata と記事冒頭で読みが取れる語だけになります
