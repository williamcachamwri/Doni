#!/usr/bin/env python3
"""Transcribe the lyrics half of the reference's AppSettings into DoniLyrics.

The reference keeps every preference in one 2 097-line class. Only the lyrics keys are
reachable from the copied lyrics screens, and they have to carry the reference's own
defaults, key names, clamps and persisted types or the screen would open at a different
size than the reference does. So this reads the reference file and lifts the lyrics
members out of it verbatim: the `default…`/`…Range` constants, the `Key` entries, the
observed properties with their `didSet`, and the statements that initialise them.
"""
import re

SRC = "/tmp/MeloX/MeloX/Core/Settings/Application/AppSettings.swift"
OUT = "/Users/wica/Desktop/Doni/Packages/DoniLyrics/Sources/DoniLyrics/Seam/AppSettings.swift"

KEEP = re.compile(r"lyrics|Lyrics|wordByWord|WordByWord")
DROP = re.compile(r"LiveActivity|liveActivity|Notification|notification|Floating|floating"
                  r"|Style|style|AMLL|QQMusic|Source|RefreshRate|skyline|Skyline|textPV"
                  r"|SystemNowPlaying|systemNowPlaying")
# Built by hand at the bottom of the generated class.
SUBOBJECTS = {"appleMusicLyrics", "lyricsInterlude"}
CONTINUE = tuple("=(,?&|+-*/:<.")
# A statement also runs on when the next line opens with an operator, which is how the
# reference wraps `x = defaults.object(forKey: K) as? Double ?? Self.defaultX`.
PREFIX = re.compile(r"^\s*(\?\?|\|\||&&|\?|\.|\+|-|\*|:|,)")

lines = open(SRC, encoding="utf-8").read().split("\n")

BRACKETS = (("(", ")"), ("{", "}"), ("[", "]"))


def stmt(start):
    """The lines of the statement that begins at `start`."""
    running = {c: 0 for c, _ in BRACKETS}
    for i in range(start, len(lines)):
        line = lines[i]
        for c, o in BRACKETS:
            running[c] += line.count(c) - line.count(o)
        balanced = all(v == 0 for v in running.values())
        ends_open = line.rstrip().endswith(CONTINUE)
        nxt = lines[i + 1] if i + 1 < len(lines) else ""
        if balanced and not ends_open and not PREFIX.match(nxt):
            return lines[start:i + 1]
    return lines[start:]


def gather(predicate, indent, lo=0, hi=None):
    """Statements at `indent` whose first line matches `predicate` -> [(name, lines)]."""
    found, i = [], lo
    hi = hi if hi is not None else len(lines)
    while i < hi:
        if lines[i].startswith(indent):
            m = predicate(lines[i])
            if m:
                body = stmt(i)
                found.append((m.group(1), body))
                i += len(body)
                continue
        i += 1
    return found


key_start = next(i for i, l in enumerate(lines) if l.strip() == "private enum Key {")
keys = []
i = key_start + 1
while i < len(lines) and lines[i] != "    }":
    m = re.match(r"\s+static let (\w+)[ =]", lines[i])
    if m and KEEP.search(m.group(1)) and not DROP.search(m.group(1)):
        body = stmt(i)
        keys.append((m.group(1), body))
        i += len(body)
        continue
    i += 1

# A constant whose type name wraps onto its own line has no `=` on the first line, so
# match the declaration and let the statement reader find where it ends.
statics = gather(lambda l: re.match(r"    static (?:let|var) (\w+)\b", l), "    ")
statics = [(n, b) for n, b in statics if KEEP.search(n) and not DROP.search(n)]

props = gather(lambda l: re.match(r"    var (\w+):", l), "    ")
props = [(n, b) for n, b in props if KEEP.search(n) and not DROP.search(n)]

# Computed helpers are functions here, and the copied views call them through the
# settings object — `settings.effectiveLyricsAdvanceTime(for:)` and friends.
funcs = gather(lambda l: re.match(r"    (?:private )?func (\w+)[(<]", l), "    ")
funcs = [(n, b) for n, b in funcs if KEEP.search(n) and not DROP.search(n)]
props += funcs

init_start = next(i for i, l in enumerate(lines) if l.startswith("    init(defaults:"))
init_end = next(i for i in range(init_start, len(lines)) if lines[i] == "    }")
init_stmts = gather(
    # An assignment, whether the value starts on the same line or the next one — the
    # reference wraps `x =\n    defaults.object(forKey: …)`.
    lambda l: re.match(r"        (?:let |var |self\.)?(\w+)(?: : [^=]+)? (?:=(?!=).+|=\s*$)", l),
    "        ", init_start + 1, init_end,
)
init_body = {}
for name, body in init_stmts:
    init_body.setdefault(name, body)

queue = [n for n, _ in init_stmts
         if KEEP.search(n) and not DROP.search(n) and n not in SUBOBJECTS]
# Written by hand above the gathered statements.
KNOWN = {"defaults"} | SUBOBJECTS
taken = set()
while queue:
    name = queue.pop()
    if name in taken or name not in init_body or name in KNOWN:
        continue
    taken.add(name)
    body = init_body[name]
    for other in init_body:
        if other not in taken and re.search(rf"\b{re.escape(other)}\b", "\n".join(body)):
            queue.append(other)

ordered = [(n, b) for n, b in init_stmts if n in taken]

out = [
    "import Foundation",
    "import Observation",
    "",
    "/// The lyrics half of the reference's settings object, lifted out with its defaults,",
    "/// its UserDefaults keys and its clamps intact. Each of those numbers is what the copied",
    "/// renderer reads to decide how big, how bright and how fast a line is, so they are the",
    "/// reference's numbers rather than approximations of them.",
    "@MainActor",
    "@Observable",
    "public final class AppSettings {",
    "    private enum Key {",
]
for _, body in keys:
    out.extend("    " + l for l in body)
out += ["    }", ""]
for _, body in statics:
    out.extend(body)
    out.append("")
for _, body in props:
    out.extend(body)
    out.append("")
out += [
    "    private let defaults: UserDefaults",
    "    let appleMusicLyrics: AppleMusicLyricsPreferences",
    "    let lyricsInterlude: LyricsInterludePreferences",
    "",
    "    public init(defaults: UserDefaults = .standard) {",
    "        self.defaults = defaults",
    "        appleMusicLyrics = AppleMusicLyricsPreferences(defaults: defaults)",
    "        lyricsInterlude = LyricsInterludePreferences(defaults: defaults)",
]
for _, body in ordered:
    out.extend(body)
out += ["    }", "}"]

open(OUT, "w", encoding="utf-8").write("\n".join(out) + "\n")

# A stored property lifted out without its initialiser is a class that does not compile, and
# the two are easy to desynchronise when the reference wraps an assignment onto its own line.
declared = {n for n, b in props if any("didSet" in l for l in b)}
assigned = {n for n, _ in ordered}
uninitialised = sorted(declared - assigned)
if uninitialised:
    raise SystemExit(f"no initialiser found for: {uninitialised}")

print(f"keys={len(keys)} statics={len(statics)} props={len(props)} inits={len(ordered)}")
