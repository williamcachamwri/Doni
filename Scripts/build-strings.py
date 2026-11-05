#!/usr/bin/env python3
"""Builds App/Localizable.xcstrings from Scripts/strings.txt.

The catalog is keyed by the Vietnamese source text, which is what makes the whole thing cost nothing
in Swift: `Text("Trang chủ")` is already a `LocalizedStringKey`, and the app's development language is
already `vi` (`project.yml:10`), so the literal is the key and an untranslated string falls back to
Vietnamese rather than to nothing.

Two kinds of row live in `strings.txt`, separated by `|`:

    <key>|<zh>|<es>|<ru>|<fr>|<ar>

`key` is the Vietnamese text the code already says, except for the lyrics screen's dotted keys
(`ui.lyrics.empty`), whose Vietnamese lives in `Seam/L10n.swift` and is read from there — that file
stays the one source for what the ported views say.

The catalog is generated rather than hand-written because it is JSON with six languages per entry and
one misplaced brace costs a build. Run `python3 Scripts/build-strings.py` after editing the table.
"""

from __future__ import annotations

import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
TABLE = ROOT / "Scripts" / "strings.txt"
L10N = ROOT / "Packages" / "DoniLyrics" / "Sources" / "DoniLyrics" / "Seam" / "L10n.swift"
OUTPUT = ROOT / "App" / "Localizable.xcstrings"
LANGUAGES = ("zh-Hans", "es", "ru", "fr", "ar")

# The Vietnamese values the copied lyrics views ask for by key.
ENTRY = re.compile(r'^\s*"(ui\.[a-z0-9_.]+)":\s*$|^\s*"(ui\.[a-z0-9_.]+)":\s*"((?:[^"\\]|\\.)*)",?\s*$')


def read_l10n() -> dict[str, str]:
    """The dotted keys and their Vietnamese, joined across a wrapped line."""
    found: dict[str, str] = {}
    text = L10N.read_text(encoding="utf-8").split("private static let strings")[1]
    key = value = None
    for raw in text.splitlines():
        match = ENTRY.match(raw)
        if match:
            if key and value is not None:
                found[key] = value
            key = match.group(1) or match.group(2)
            value = match.group(3)
            if value is None:
                value = ""
            continue
        if key is not None and raw.strip().startswith('"'):
            piece = raw.strip().rstrip(",")
            if piece.startswith('"'):
                value = (value or "") + piece[1:-1] if not value else value + piece[1:-1]
    if key and value:
        found[key] = value
    return found


def read_table() -> list[tuple[str, dict[str, str]]]:
    rows: list[tuple[str, dict[str, str]]] = []
    for number, raw in enumerate(TABLE.read_text(encoding="utf-8").splitlines(), start=1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = [cell.strip() for cell in line.split("|")]
        if len(parts) != 1 + len(LANGUAGES):
            raise SystemExit(
                f"strings.txt:{number}: expected {1 + len(LANGUAGES)} columns, got {len(parts)}: {line[:60]}")
        rows.append((parts[0], dict(zip(LANGUAGES, parts[1:]))))
    return rows


# Strings the table deliberately does not answer. Search keywords are typed by the user in either
# language already — translating them would take the English words away from someone searching in
# English — and a song title in a doc comment is not interface text at all.
NOT_TRANSLATED = {
    "cloud chưa tải chờ download telegram", "dung lượng bộ nhớ cache storage disk",
    "kênh channel nhạc", "ngôn ngữ", "thư viện nhạc bài hát index", "tài khoản",
    "tải offline file", "hồ sơ", "đăng xuất", "Tình yêu", "n bài",
}


def strip_comments(text: str) -> str:
    """Source without comment lines, because a doc comment naming a song is not interface text.

    Whole lines only: cutting at the first `//` anywhere would eat the `//` of a link pasted into a
    real string.
    """
    return "\n".join(
        line for line in text.splitlines()
        if not line.lstrip().startswith(("//", "/*", "*"))
    )


def coverage(keys: set[str]) -> tuple[list[str], list[str]]:
    """What the table still owes: whole literals with no row, and literals that cannot have one.

    The second list is the important half. `Text("A \\(x) B")` *is* a localized key, but the key
    SwiftUI builds depends on the Swift type of `x`, so no table row can name it — such a string has
    to be rewritten through `localized("A %@ B", x)` first. Counting them as answered would be the
    same lie as not counting them.
    """
    viet = re.compile(r"[àáảãạăâêôơưđÀÁẢÃẠĂÂÊÔƠƯĐ]")
    literal = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
    missing: set[str] = set()
    unanswerable: set[str] = set()
    for source in sorted((ROOT / "App").glob("*.swift")) + sorted((ROOT / "UI").glob("*.swift")):
        for match in literal.finditer(strip_comments(source.read_text(encoding="utf-8"))):
            text = match.group(1)
            if not viet.search(text) or text in keys or text in NOT_TRANSLATED:
                continue
            (unanswerable if "\\(" in text else missing).add(text)
    return sorted(missing), sorted(unanswerable)


def placeholder_mismatches(strings: dict) -> list[str]:
    """Rows whose translations lost a `%@` the source has.

    A translation that drops a placeholder does not fail — it prints a sentence with the number or
    the name missing, which is worse than Vietnamese. Three of them were caught this way on the
    first full pass, so the count is checked rather than trusted.
    """
    bad = []
    for key, entry in strings.items():
        if "%@" not in key:
            continue
        want = key.count("%@")
        for language, unit in entry.get("localizations", {}).items():
            if unit["stringUnit"]["value"].count("%@") != want:
                bad.append(f"{key[:48]} [{language}]")
    return sorted(bad)


def main() -> int:
    l10n = read_l10n()
    rows = read_table()
    strings: dict[str, dict] = {}
    for key, translations in rows:
        entry: dict[str, dict] = {"extractionState": "manual"}
        localizations: dict[str, dict] = {}
        if key in l10n:
            localizations["vi"] = {"stringUnit": {"state": "translated", "value": l10n[key]}}
        for language, text in translations.items():
            if text:
                localizations[language] = {"stringUnit": {"state": "translated", "value": text}}
        if localizations:
            entry["localizations"] = localizations
        strings[key] = entry

    unknown = sorted(key for key in l10n if key not in strings)
    if unknown:
        print(f"!! {len(unknown)} lyrics keys have no row in strings.txt:")
        for key in unknown:
            print(f"   {key}")

    OUTPUT.write_text(json.dumps(
        {"sourceLanguage": "vi", "strings": strings, "version": "1.0"},
        ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {OUTPUT.name}: {len(strings)} keys, {len(l10n)} lyrics keys, "
          f"{len(unknown)} of them untranslated")
    missing, unanswerable = coverage(set(strings))
    print(f"app strings still falling back to Vietnamese: {len(missing)} of {len(strings)}")
    for text in missing[:12]:
        print(f"   {text[:72]}")
    if len(missing) > 12:
        print(f"   … and {len(missing) - 12} more (python3 Scripts/build-strings.py --all)")
    for text in unanswerable:
        print(f"   INTERPOLATED, rewrite as localized(\"…\", x): {text[:60]}")
    broken = placeholder_mismatches(strings)
    for row in broken:
        print(f"   PLACEHOLDER LOST: {row}")
    return 1 if missing or unanswerable or unknown or broken else 0


if __name__ == "__main__":
    if "--all" in sys.argv:
        # The rows a translation pass still owes, which is the whole point of keeping the table in
        # one file: adding a string to the app makes it show up here until it is answered.
        keys = {row[0] for row in read_table()} | set(read_l10n())
        missing, unanswerable = coverage(keys)
        print("\n".join(missing))
        for text in unanswerable:
            print(f"INTERPOLATED: {text}")
        raise SystemExit(1 if missing or unanswerable else 0)
    raise SystemExit(main())
