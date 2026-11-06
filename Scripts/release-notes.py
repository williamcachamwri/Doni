#!/usr/bin/env python3
"""Turns RELEASE_NOTES.md into the JSON the app reads and the markdown a GitHub release body uses.

The file is the only place release notes are written. Two things come out of it:

    App/Generated/ReleaseNotes.json   bundled with the app, shown on the Release notes screen
    build/ReleaseNotes.md             the bilingual body of the GitHub release

Both are generated and the JSON is committed, because XcodeGen globs the sources when it makes the
project: a file a build phase writes first would not be in the resources phase of that same build.
`make notes` regenerates them and `make check` runs this file with --check, which fails when the
committed JSON no longer matches the markdown — the same arrangement Scripts/build-strings.py uses
for the language table.

Structure accepted, in MeloX's shape (`MeloX/.github/scripts/release_notes.py`):

    ## iOS
    ### Tiếng Việt
    - entry
    ### English
    - entry
"""

from __future__ import annotations

import json
import pathlib
import re
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
NOTES = ROOT / "RELEASE_NOTES.md"
JSON_OUTPUT = ROOT / "App" / "Generated" / "ReleaseNotes.json"
MD_OUTPUT = ROOT / "build" / "ReleaseNotes.md"
SCHEMA_VERSION = 1
# The two languages the app can show notes in. Vietnamese is the key language of the whole app
# (`project.yml: developmentLanguage: vi`), English is what a GitHub reader gets.
LANGUAGES = ("vi", "en")
HEADINGS = {"vi": "Tiếng Việt", "en": "English"}

PLATFORM = re.compile(r"^##\s+(?P<name>.+?)\s*$")
LANGUAGE = re.compile(r"^###\s+(?P<name>.+?)\s*$")
BULLET = re.compile(r"^-\s+(?P<text>.+?)\s*$")


def fail(message: str) -> "NoReturn":  # type: ignore[valid-type]
    sys.exit(f"release notes: {message}")


def version() -> tuple[str, str]:
    """The marketing version and the build number, out of `project.yml`.

    Read rather than passed: one number in one file is the only way the About screen, the JSON and
    the tag a release is cut under cannot disagree.
    """
    text = (ROOT / "project.yml").read_text(encoding="utf-8")
    match = re.search(r'MARKETING_VERSION:\s*"?([0-9.]+)"?', text)
    if not match:
        fail("project.yml has no MARKETING_VERSION")
    build = re.search(r'CURRENT_PROJECT_VERSION:\s*"?(\d+)"?', text)
    if not build:
        fail("project.yml has no CURRENT_PROJECT_VERSION")
    return match.group(1), build.group(1)


def parse(text: str) -> dict[str, dict[str, list[str]]]:
    """`{platform: {language: [entry, …]}}`, checked as it is read."""
    found: dict[str, dict[str, list[str]]] = {}
    platform = language = None
    for number, raw in enumerate(text.splitlines(), start=1):
        if (match := PLATFORM.match(raw)) and not raw.startswith("###"):
            platform, language = match.group("name").strip(), None
            found.setdefault(platform, {})
            continue
        if match := LANGUAGE.match(raw):
            if platform is None:
                fail(f"line {number}: a language section outside a platform")
            name = match.group("name").strip()
            language = next((code for code, heading in HEADINGS.items() if heading == name), None)
            if language is None:
                fail(f"line {number}: unknown language section {name!r}")
            found[platform].setdefault(language, [])
            continue
        if match := BULLET.match(raw):
            if platform is None or language is None:
                fail(f"line {number}: an entry outside a language section")
            found[platform][language].append(match.group("text"))
    for name, languages in found.items():
        missing = [code for code in LANGUAGES if code not in languages]
        if missing:
            fail(f"{name} has no entries for {', '.join(missing)}")
        counts = {code: len(languages[code]) for code in LANGUAGES}
        if len(set(counts.values())) > 1:
            fail(f"{name} is out of step: {counts}")
        if not counts[LANGUAGES[0]]:
            fail(f"{name} has no entries at all")
    if not found:
        fail("no platform section found")
    return found


def revision() -> str:
    short = subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--short", "HEAD"],
                           capture_output=True, text=True)
    return short.stdout.strip() or "unknown"


def markdown(markers: dict[str, dict[str, list[str]]]) -> str:
    """The release body: both languages of every platform, as the app shows them."""
    out = ["## What's New / 更新内容", ""]
    for platform, languages in markers.items():
        out.append(f"### {platform}")
        for code in LANGUAGES:
            out.append(f"#### {HEADINGS[code]}")
            out += [f"- {entry}" for entry in languages[code]]
            out.append("")
    return "\n".join(out).rstrip() + "\n"


def main(argv: list[str]) -> int:
    check = "--check" in argv
    platform_arg = next((a for a in argv if a.startswith("--platform=")), None)
    if not NOTES.exists():
        fail(f"{NOTES.name} is missing")
    short, build = version()
    markers = parse(NOTES.read_text(encoding="utf-8"))
    platforms = list(markers)
    if platform_arg:
        target = platform_arg.split("=", 1)[1].lower()
        if target not in [p.lower() for p in platforms]:
            fail(f"unknown platform {target!r}; have {platforms}")
        platforms = [p for p in platforms if p.lower() == target]
    payload = {
        "schemaVersion": SCHEMA_VERSION,
        "platform": platforms[0].lower(),
        "version": short,
        "buildNumber": build,
        "sourceRevision": revision(),
        "localizedEntries": {
            code: markers[platforms[0]][code] for code in LANGUAGES
        },
    }
    rendered = json.dumps(payload, ensure_ascii=False, indent=2) + "\n"
    json_output = JSON_OUTPUT.with_name(f"ReleaseNotes-{platforms[0].lower()}.json")
    if check:
        current = json_output.read_text(encoding="utf-8") if json_output.exists() else ""
        if current != rendered:
            fail(f"{json_output.relative_to(ROOT)} is stale — run `make notes`")
        return 0
    json_output.parent.mkdir(parents=True, exist_ok=True)
    json_output.write_text(rendered, encoding="utf-8")
    MD_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    MD_OUTPUT.write_text(markdown(markers), encoding="utf-8")
    entries = len(payload["localizedEntries"]["vi"])
    print(f"wrote {json_output.relative_to(ROOT)}: {short} ({build}), "
          f"{entries} entries in {len(LANGUAGES)} languages for {payload['platform']}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
