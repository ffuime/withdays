"""Tests for build_trending (no network: the parts that only work on text)."""
import datetime as dt
import json

import build_trending as bt


def test_to_hiragana():
    assert bt.to_hiragana("カタカナー") == "かたかなー"
    assert bt.to_hiragana("ヴァイオリン") == "ゔぁいおりん"


def test_clean_reading():
    assert bt.clean_reading("ミセス・グリーンアップル") == "みせすぐりーんあっぷる"
    assert bt.clean_reading("おお たに しょうへい") == "おおたにしょうへい"
    assert bt.clean_reading("abc") is None
    assert bt.clean_reading("") is None
    assert bt.clean_reading("漢字") is None


def test_word_from_title():
    assert bt.word_from_title("ラブ_(テレビドラマ)") == "ラブ"
    assert bt.word_from_title("大谷翔平") == "大谷翔平"
    assert bt.word_from_title("メインページ") is None
    assert bt.word_from_title("特別:検索") is None
    assert bt.word_from_title("日本の市の人口順位一覧") is None
    assert bt.word_from_title("2026年") is None
    assert bt.word_from_title("Category:日本") is None


def test_reading_from_extract():
    extract = "大谷翔平（おおたに しょうへい、1994年7月5日 - ）は、岩手県出身のプロ野球選手。"
    assert bt.reading_from_extract("大谷翔平", extract) == "おおたにしょうへい"
    assert bt.reading_from_extract("東京", "東京（とうきょう）は日本の首都。") == "とうきょう"
    # The parenthesis is not a reading.
    assert bt.reading_from_extract("NHK", "NHK（英: Japan Broadcasting Corporation）は") is None
    # A different word comes first.
    assert bt.reading_from_extract("東京", "日本の首都、東京（とうきょう）") is None
    assert bt.reading_from_extract("東京", "") is None


def test_spike_score():
    assert bt.spike_score(30000, [1000, 1200, 900]) > bt.spike_score(30000, [25000, 28000, 30000])
    assert bt.spike_score(0, []) == 0


def test_merge_keeps_recent_and_drops_old():
    day = dt.date(2026, 11, 28)
    previous = [
        {"reading": "ふるい", "word": "古い", "pos": "固有名詞", "date": "2026-10-01"},
        {"reading": "きのう", "word": "昨日の", "pos": "固有名詞", "date": "2026-11-27"},
        {"reading": "おなじ", "word": "同じ", "pos": "固有名詞", "date": "2026-11-20"},
    ]
    new = [{"reading": "おなじ", "word": "同じ", "pos": "人名"}, {"reading": "あたらしい", "word": "新しい", "pos": "固有名詞"}]
    merged = bt.merge(previous, new, day, keep_days=30, limit=100)
    words = {word["word"]: word for word in merged}
    assert "古い" not in words
    assert words["同じ"]["date"] == "2026-11-28"
    assert words["同じ"]["pos"] == "人名"
    assert "昨日の" in words
    assert merged[0]["date"] == "2026-11-28"


def test_merge_limit():
    day = dt.date(2026, 11, 28)
    new = [{"reading": f"あ{i}", "word": f"w{i}", "pos": "固有名詞"} for i in range(10)]
    assert len(bt.merge([], new, day, keep_days=30, limit=3)) == 3


def test_write(tmp_path):
    out = tmp_path / "trending.json"
    words = [{"reading": "てすと", "word": "テスト", "pos": "固有名詞", "date": "2026-11-28"}]
    bt.write(words, dt.date(2026, 11, 28), out)
    data = json.loads(out.read_text(encoding="utf-8"))
    assert data["updated"] == "2026-11-28"
    assert data["words"][0]["word"] == "テスト"
    csv_text = out.with_suffix(".csv").read_text(encoding="utf-8")
    assert csv_text.splitlines()[0] == "読み,表記,品詞"
    assert "てすと,テスト,固有名詞" in csv_text


def test_give_readings_without_network(monkeypatch):
    monkeypatch.setattr(bt, "wikidata_info", lambda titles: {
        "大谷翔平": {"kana": "おおたにしょうへい", "human": True},
        "除外さん": {"kana": "じょがいさん", "human": True, "excluded": True},
    })
    monkeypatch.setattr(bt, "summary_extract", lambda title: "")
    monkeypatch.setattr(bt.SudachiReader, "read", lambda self, word: None)
    words = bt.give_readings(["大谷翔平", "ポケモン", "Xyz123", "除外さん"])
    assert {"reading": "おおたにしょうへい", "word": "大谷翔平", "pos": "人名"} in words
    assert any(word["word"] == "ポケモン" and word["reading"] == "ぽけもん" for word in words)
    assert all(word["word"] != "Xyz123" for word in words)
    assert all(word["word"] != "除外さん" for word in words)
    assert bt.word_from_title("AV女優") is None
