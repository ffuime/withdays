#!/usr/bin/env python3
"""Keykie's trending-words dictionary.

Takes the Japanese Wikipedia's most-read articles of a day (Wikimedia Pageviews API), keeps the ones that
suddenly rose against the days before, gives each a reading and writes trending.json / trending.csv.

Readings, best first:
  1. Wikidata's "name in kana" (P1814)
  2. The article's lead: 「表記（よみ、…）」
  3. Sudachi's reading of the title (needs sudachipy + sudachidict_core)

Usage: python build_trending.py [--date YYYY-MM-DD] [--out trending/trending.json]
"""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import os
import re
import statistics
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

PAGEVIEWS = "https://wikimedia.org/api/rest_v1/metrics/pageviews/top/ja.wikipedia/all-access/{y}/{m:02d}/{d:02d}"
WIKIDATA = "https://www.wikidata.org/w/api.php"
SUMMARY = "https://ja.wikipedia.org/api/rest_v1/page/summary/{title}"
USER_AGENT = os.environ.get("TRENDING_USER_AGENT", "KeykieTrending/1.0 (keyboard dictionary builder)")

# Pages that are not words.
EXCLUDED_PREFIXES = (
    "特別:", "Special:", "Wikipedia:", "WP:", "ファイル:", "File:", "Category:", "Portal:", "ノート:", "利用者:",
    "Help:", "ヘルプ:", "Template:", "プロジェクト:", "MediaWiki:",
)
EXCLUDED_TITLES = {"メインページ", "-", "検索", "Main_Page", "AV女優", "AV男優", "アダルトビデオ"}
# Occupations left out (Wikidata P106): pornographic actor. The top list is full of them, and they make poor candidates.
EXCLUDED_OCCUPATIONS = {"Q488111"}

HIRAGANA = re.compile(r"^[ぁ-ゖー]+$")
KATAKANA_OR_HIRAGANA = re.compile(r"^[ぁ-ゖァ-ヺー・\s　]+$")


# ---- Text helpers ---------------------------------------------------------------------------------

def to_hiragana(text: str) -> str:
    """カタカナ → ひらがな (ー stays)."""
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in text)


def clean_reading(text: str) -> str | None:
    """A usable reading: ひらがな and ー only, after dropping spaces and ・. None when it isn't one."""
    reading = to_hiragana(re.sub(r"[\s　・=＝]", "", text))
    return reading if reading and HIRAGANA.match(reading) and len(reading) <= 40 else None


def word_from_title(title: str) -> str | None:
    """The word an article title stands for: 「ラブ_(テレビドラマ)」→「ラブ」. None for pages that are not words."""
    if title in EXCLUDED_TITLES or title.startswith(EXCLUDED_PREFIXES):
        return None
    word = title.replace("_", " ")
    word = re.sub(r"\s*\((.*?)\)$", "", word).strip()
    if not word or "一覧" in word or len(word) > 30:
        return None
    if re.fullmatch(r"[\d\s年月日\-–.]+", word):
        return None
    return word


def reading_from_extract(word: str, extract: str) -> str | None:
    """「表記（ひょうき、英: …）は…」 → ひょうき. The reading comes right after the word's own parenthesis."""
    if not extract:
        return None
    head = extract.strip()[: len(word) + 80]
    match = re.match(r"^\s*" + re.escape(word) + r"\s*[（(]([^）)、,，;；/／]+)", head)
    if not match:
        return None
    candidate = match.group(1)
    if not KATAKANA_OR_HIRAGANA.match(candidate):
        return None
    return clean_reading(candidate)


def spike_score(today: int, history: list[int]) -> float:
    """How suddenly an article rose: today's views over the usual (median of the days before, plus a floor)."""
    usual = statistics.median(history) if history else 0
    return today / (usual + 1500)


# ---- Network ----------------------------------------------------------------------------------------

def get_json(url: str, retries: int = 3) -> dict | None:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    for attempt in range(retries):
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            if error.code == 404:
                return None
            if attempt == retries - 1:
                raise
        except urllib.error.URLError:
            if attempt == retries - 1:
                raise
        time.sleep(2 * (attempt + 1))
    return None


def top_articles(day: dt.date) -> dict[str, int]:
    data = get_json(PAGEVIEWS.format(y=day.year, m=day.month, d=day.day))
    if not data:
        return {}
    return {item["article"]: int(item["views"]) for item in data["items"][0]["articles"]}


def wikidata_info(titles: list[str]) -> dict[str, dict]:
    """Title → {"kana": reading or None, "human": bool}, 50 titles a request."""
    info: dict[str, dict] = {}
    for start in range(0, len(titles), 50):
        batch = titles[start:start + 50]
        query = urllib.parse.urlencode({
            "action": "wbgetentities", "sites": "jawiki", "titles": "|".join(batch),
            "props": "claims|sitelinks", "sitefilter": "jawiki", "format": "json",
        })
        data = get_json(f"{WIKIDATA}?{query}") or {}
        for entity in data.get("entities", {}).values():
            title = entity.get("sitelinks", {}).get("jawiki", {}).get("title")
            if not title:
                continue
            claims = entity.get("claims", {})
            kana = None
            for claim in claims.get("P1814", []):
                value = claim.get("mainsnak", {}).get("datavalue", {}).get("value")
                if isinstance(value, str) and clean_reading(value):
                    kana = clean_reading(value)
                    break
            def ids(prop: str) -> set:
                return {
                    claim.get("mainsnak", {}).get("datavalue", {}).get("value", {}).get("id")
                    for claim in claims.get(prop, [])
                }
            info[title.replace(" ", "_")] = {
                "kana": kana,
                "human": "Q5" in ids("P31"),
                "excluded": bool(ids("P106") & EXCLUDED_OCCUPATIONS),
            }
    return info


def summary_extract(title: str) -> str:
    data = get_json(SUMMARY.format(title=urllib.parse.quote(title, safe="")))
    return (data or {}).get("extract", "")


class SudachiReader:
    """Readings from Sudachi, when it is installed."""

    def __init__(self) -> None:
        try:
            from sudachipy import dictionary, tokenizer  # type: ignore
            self.tokenizer = dictionary.Dictionary().create()
            self.mode = tokenizer.Tokenizer.SplitMode.C
        except Exception:  # noqa: BLE001 - missing or broken: just no Sudachi readings
            self.tokenizer = None

    def read(self, word: str) -> str | None:
        if self.tokenizer is None:
            return None
        parts = []
        for morpheme in self.tokenizer.tokenize(word, self.mode):
            surface = morpheme.surface()
            if surface.isspace():
                continue
            reading = morpheme.reading_form()
            # Sudachi gives the surface back for unknown words; letters and digits have no kana reading.
            if not reading or (reading == surface and not KATAKANA_OR_HIRAGANA.match(surface)):
                return None
            parts.append(reading)
        return clean_reading("".join(parts)) if parts else None


# ---- Building ------------------------------------------------------------------------------------------

def rising(day: dt.date, history_days: int, limit: int) -> list[tuple[str, int, float]]:
    """(title, views, score) of the day's articles that rose the most, biggest first."""
    today = top_articles(day)
    if not today:
        return []
    history = [top_articles(day - dt.timedelta(days=offset)) for offset in range(1, history_days + 1)]
    scored = []
    for title, views in today.items():
        if word_from_title(title) is None or views < 2000:
            continue
        past = [days.get(title, 0) for days in history]
        score = spike_score(views, past)
        if score >= 1.5:
            scored.append((title, views, score))
    scored.sort(key=lambda item: item[2], reverse=True)
    return scored[:limit]


def give_readings(titles: list[str], use_summary: bool = True) -> list[dict]:
    info = wikidata_info(titles)
    sudachi = SudachiReader()
    words = []
    for title in titles:
        word = word_from_title(title)
        if word is None:
            continue
        details = info.get(title, {})
        if details.get("excluded"):
            continue
        reading = None
        if KATAKANA_OR_HIRAGANA.match(word):
            reading = clean_reading(word)
        reading = reading or details.get("kana")
        if reading is None and use_summary:
            reading = reading_from_extract(word, summary_extract(title))
        reading = reading or sudachi.read(word)
        if reading is None:
            continue
        words.append({"reading": reading, "word": word, "pos": "人名" if details.get("human") else "固有名詞"})
    return words


def merge(previous: list[dict], new: list[dict], day: dt.date, keep_days: int, limit: int) -> list[dict]:
    """New words first; older ones stay until they are keep_days old."""
    cutoff = (day - dt.timedelta(days=keep_days)).isoformat()
    merged: dict[tuple[str, str], dict] = {}
    for word in new:
        merged[(word["reading"], word["word"])] = {**word, "date": day.isoformat()}
    for word in previous:
        key = (word.get("reading", ""), word.get("word", ""))
        if key in merged or not all(key) or word.get("date", "") < cutoff:
            continue
        merged[key] = word
    ordered = sorted(merged.values(), key=lambda word: word.get("date", ""), reverse=True)
    return ordered[:limit]


def write(words: list[dict], day: dt.date, out: Path) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    payload = {
        "updated": day.isoformat(),
        "source": "Wikimedia Pageviews API (ja.wikipedia), Wikidata, Wikipedia",
        "words": words,
    }
    out.write_text(json.dumps(payload, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    with out.with_suffix(".csv").open("w", encoding="utf-8", newline="") as file:
        writer = csv.writer(file)
        writer.writerow(["読み", "表記", "品詞"])
        for word in words:
            writer.writerow([word["reading"], word["word"], word["pos"]])


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--date", help="the day to read (default: yesterday, UTC)")
    parser.add_argument("--out", default=str(Path(__file__).with_name("trending.json")))
    parser.add_argument("--history", type=int, default=7, help="days to compare against")
    parser.add_argument("--limit", type=int, default=150, help="new words per day")
    parser.add_argument("--keep", type=int, default=30, help="days a word stays")
    parser.add_argument("--max", type=int, default=3000, help="words in the file at most")
    args = parser.parse_args(argv)

    day = dt.date.fromisoformat(args.date) if args.date else dt.datetime.now(dt.timezone.utc).date() - dt.timedelta(days=1)
    found = rising(day, args.history, args.limit)
    if not found:
        # The day's numbers are published with a delay: try the day before.
        day -= dt.timedelta(days=1)
        found = rising(day, args.history, args.limit)
    if not found:
        print(f"No pageview data for {day}", file=sys.stderr)
        return 1

    new = give_readings([title for title, _, _ in found])
    out = Path(args.out)
    previous = []
    if out.exists():
        try:
            previous = json.loads(out.read_text(encoding="utf-8")).get("words", [])
        except (ValueError, AttributeError):
            previous = []
    words = merge(previous, new, day, args.keep, args.max)
    write(words, day, out)
    print(f"{day}: {len(found)} rising, {len(new)} with readings, {len(words)} in {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
