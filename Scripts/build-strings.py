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
import unicodedata

ROOT = pathlib.Path(__file__).resolve().parent.parent
TABLE = ROOT / "Scripts" / "strings.txt"
L10N = ROOT / "Packages" / "DoniLyrics" / "Sources" / "DoniLyrics" / "Seam" / "L10n.swift"
OUTPUT = ROOT / "App" / "Localizable.xcstrings"
LANGUAGES = ("zh-Hans", "es", "ru", "fr", "ar")

# Every Swift file either shell can say a word in. The desktop's views live in `Mac/`, in
# subdirectories, and a gate that only read `App/` and `UI/` would let a Mac string fall back to
# Vietnamese in Beijing without ever mentioning it.
SOURCES = (
    sorted((ROOT / "App").glob("*.swift"))
    + sorted((ROOT / "UI").glob("*.swift"))
    + sorted((ROOT / "Mac").rglob("*.swift"))
)

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
    # A language's own name is written in its own script — that is the whole idea behind the
    # picker, and transliterating it would make the list unreadable to the one reader who needs it.
    "Tiếng Việt", "Español", "Français", "Русский", "简体中文", "العربية",
    # A caption key that is part of a format rather than a word the interface says: the app writes
    # `Tiêu đề:` into Saved Messages (`App/CloudMusic.swift`) and reads the same word back out
    # (`TdTrack.captionValue`). Translating one half would leave the other looking for a line that
    # is no longer there, so the spelling belongs to the format.
    "Tiêu đề: \\(name)", "Thể hiện: \\(artist)",
}


def is_vietnamese(text: str) -> bool:
    """Whether a literal is words the app says, not words it read from somewhere.

    Normalised first, because Vietnamese precomposes its tone marks. A class of letters would have
    to list `ế ề ể ễ ệ ổ ự ỳ` each, and the first version of this check listed only the base
    letters — so `Text("Tiếp theo")` looked like English to it and went untranslated behind a green
    build.
    """
    nfd = unicodedata.normalize("NFD", text)
    return any(unicodedata.combining(c) for c in nfd) or "đ" in nfd or "Đ" in nfd


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
    literal = re.compile(r'"((?:[^"\\\n]|\\.)*)"')
    missing: set[str] = set()
    unanswerable: set[str] = set()
    for source in SOURCES:
        for match in literal.finditer(strip_comments(source.read_text(encoding="utf-8"))):
            text = match.group(1)
            if not is_vietnamese(text) or text in keys or text in NOT_TRANSLATED:
                continue
            (unanswerable if "\\(" in text else missing).add(text)
    return sorted(missing), sorted(unanswerable)


# Expressions whose words came from outside this app: a song's name, a channel's, a person's, a
# duration, a byte count. They are rendered with `Text(_ String)` on purpose — a name is not in the
# catalog and must come back exactly as it arrived.
DATA_EXPRESSIONS = {
    "channel.title", "list.name", "playlist.name", "track.displayTitle", "track.displayPerformer",
    "row.track.displayTitle", "song.displayTitle", "artist.name", "account.name", "country.name",
    "country.dialCode", "option.name", "language.nativeName", "runs", "text", "headline", "value",
    "subtitle", "chipText", "message", "failure", "joinedFailure", "statusLine", "waitingLine",
    # An alert's sentence is resolved when the alert is built (`UpdateAlert`), so this renders text
    # that has already been looked up; looking it up again would translate a translation.
    "shown.message",
}


RENDER_ALLOWLIST = {
    # A song's name, a playlist's, an artist's; the status line, which is built through
    # `localized()` already; and a language's own name, which is written in its own script.
    # Matched on the whole line on purpose: edit the line and the exemption stops applying, so the
    # gate asks again instead of trusting a name that could mean anything.
    "HomeFeed.swift": ["Text(title)"],
    "PlaylistsView.swift": ["Text(name)"],
    "SearchView.swift": ["Text(title)"],
    "SettingsView.swift": ["Text(option.nativeName)"],
    "LibraryView.swift": ["Text(indexer.statusLine)"],
    # The sidebar's footer line is assembled from `localized(_:)` calls one level up, so it is already
    # the translated sentence; looking it up a second time would translate a translation.
    "DesktopSidebar.swift": ["Text(loadingMessage)"],
    # The desktop's placeholder panes print the library's own numbers, resolved one level up, and a
    # route's title is a playlist's name or a channel's — somebody's word, never a catalog key.
    "DesktopRootView.swift": ["Text(countLine)", "navigationTitle(title)"],
}


def unlocalized_renders() -> list[str]:
    """`Text(someVariable)` that is neither a data field nor wrapped in a key.

    This is the bug the catalog cannot see: the string is translated, the row is still Vietnamese,
    because `Text(_ String)` never looks anything up. Every one of these was found by a screenshot
    rather than by the build until this check existed.
    """
    call = re.compile(
        r'\b(Text|Label|Button|Tab|navigationTitle|accessibilityLabel|accessibilityHint)\('
        r'\s*([A-Za-z_][\w.]*)\s*[,)\]]')
    found = []
    for source in SOURCES:
        # Real line numbers: the comment lines are skipped rather than stripped first, or the
        # report points at the wrong line and the next reader stops trusting it.
        for number, line in enumerate(source.read_text(encoding="utf-8").splitlines(), 1):
            if line.lstrip().startswith(("//", "/*", "*")):
                continue
            for match in call.finditer(line):
                if "LocalizedStringKey(" in line or "localized(" in line:
                    continue
                if match.group(2) in DATA_EXPRESSIONS:
                    continue
                site = f"{match.group(1)}({match.group(2)})"
                if site in line and any(site in allowed for allowed in
                                        RENDER_ALLOWLIST.get(source.name, [])):
                    continue
                found.append(f"{source.name}:{number} {site}")
    return sorted(found)


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
    renders = unlocalized_renders()
    for row in renders:
        print(f"   UNLOCALIZED RENDER: {row}")
    broken = placeholder_mismatches(strings)
    for row in broken:
        print(f"   PLACEHOLDER LOST: {row}")
    return 1 if missing or unanswerable or unknown or broken or renders else 0


if __name__ == "__main__":
    if "--all" in sys.argv:
        # The rows a translation pass still owes, which is the whole point of keeping the table in
        # one file: adding a string to the app makes it show up here until it is answered.
        keys = {row[0] for row in read_table()} | set(read_l10n())
        missing, unanswerable = coverage(keys)
        print("\n".join(missing))
        for text in unanswerable:
            print(f"INTERPOLATED: {text}")
        raise SystemExit(1 if missing or unanswerable or unlocalized_renders() else 0)
    raise SystemExit(main())
