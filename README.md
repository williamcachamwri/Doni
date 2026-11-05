<p align="center">
  <img src="Docs/doni-icon.png" width="128" alt="The Doni app icon: a white paper plane over faded music notes on a red gradient">
</p>

# Doni

[English](README.md) · [Tiếng Việt](Docs/i18n/README.vi.md) · [中文](Docs/i18n/README.zh.md) ·
[Español](Docs/i18n/README.es.md) · [Français](Docs/i18n/README.fr.md) · [Русский](Docs/i18n/README.ru.md) ·
[العربية](Docs/i18n/README.ar.md)

A music player for iPhone that plays the songs you already keep on Telegram: the channels you
subscribe to, and Saved Messages as your own library. There is no server behind it, no account to
register, and nothing is reported anywhere.

<table>
  <tr>
    <td><img src="Docs/screenshots/home.jpg" alt="Home: recently played, newest and liked shelves" width="220"></td>
    <td><img src="Docs/screenshots/now-playing.jpg" alt="Now Playing with cover art" width="220"></td>
    <td><img src="Docs/screenshots/lock-screen.jpg" alt="Lock screen showing the lyric line" width="220"></td>
    <td><img src="Docs/screenshots/playlist.jpg" alt="A playlist" width="220"></td>
  </tr>
  <tr>
    <td align="center">The home feed.</td>
    <td align="center">Now Playing.</td>
    <td align="center">The line being sung, on the lock screen.</td>
    <td align="center">A list you made.</td>
  </tr>
</table>

## What it does

- **Starts at once, plays while it downloads.** A song is fetched in byte ranges around the playhead,
  so scrubbing to 3:40 asks for the part near 3:40 instead of the whole file.
- **Remembers what it took.** The ranges stay on the phone and survive being killed from the app
  switcher. A song you finished is playable with no network; a half-heard one resumes where it was.
- **Cloud Music is Saved Messages.** Uploading a file sends it to your own chat and then drops the
  phone's copy. Delete it in Telegram and it leaves this app too.
- **Lyrics with timing**, from lrclib, NetEase, AMLL and QQ Music. The line being sung replaces the
  song title on the lock screen and in the Dynamic Island.
- **Covers from wherever they exist**: the file's own tag, Telegram's thumbnail, or asked for again a
  few times when Telegram has not generated one yet.
- **A cache with a ceiling.** The quota is yours to set (2 GiB by default) and the least-heard songs
  are given back first. The song under the playhead is never a victim.
- Six languages in the interface; the strings in the code are Vietnamese.

## Why Telegram, and not a backend of my own

Because the library is already there. Every song is a message that carries a file, and every file has
a `file_unique_id` that means the same bytes in every database on every device — so "is this the same
song" and "where did I stop listening" are questions the protocol answers instead of a server I would
have to run, pay for and read the privacy of.

TDLib does the network: login, retries, downloads, the file cache, the CDN redirects. Doni does the
parts nobody else decides for it.

## How the streaming actually works

This is the part worth reading if you came to check whether it is real streaming.

- `downloadFile` takes an offset and a limit, but the limit does not bound the fetch — TDLib keeps
  going until it is cancelled, so the app cancels each window itself once it has enough.
- `getFileDownloadedPrefixSize` answers how many bytes are ready at *any* offset. That is the ready
  bitmask, not a done-or-not flag, and it is what makes a partial file useful.
- Parts are 64 KiB. A window sits a few megabytes ahead of the playhead and moves when about half of
  it has been consumed.
- AVFoundation asks for bytes through `AVAssetResourceLoaderDelegate`. It opens a file with a 2-byte
  probe and rejects an answer longer than what it asked for, so every response is bounded to the
  request.
- Bytes outside the ready window are garbage. Nothing is handed to the decoder that TDLib has not
  confirmed, which is why a song that loses its network stops rather than playing noise.

## Build it

Needs iOS 26 on the phone, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen), CMake, Python 3,
and a Telegram `api_id` / `api_hash` from [my.telegram.org](https://my.telegram.org).

```sh
make vendor       # builds TDLib and OpenSSL into a local XCFramework (~20 min, first run)
make project      # generates Doni.xcodeproj from project.yml
cp Config/Tdlib.example.xcconfig Config/Tdlib.xcconfig
# put your api_id, api_hash and team id in it — that file is gitignored and stays yours
make build        # compile gate: warnings are errors
make device       # compile and sign for your iPhone
make install      # and put it on the cable
```

`make check` runs the build, the package tests, the language gate and the release-notes gate.

## Release it

One version, two numbers, both in `project.yml` and both bumped together:

| | |
|---|---|
| `MARKETING_VERSION` | what the About screen shows and what the tag must say — `1.0.0` |
| `CURRENT_PROJECT_VERSION` | the build number, carrying the same version in its digits: `90 \| major \| minor \| patch`, so `9010000` is 1.0.0 |

Release notes are written once, in [`RELEASE_NOTES.md`](RELEASE_NOTES.md), in two languages with the
same number of lines. `make notes` turns that into the JSON the app bundles and the markdown the
release body uses; `make check` fails when the two have drifted apart.

```sh
make notes                        # RELEASE_NOTES.md → the JSON in the app + the release body
make release                      # builds here, tags the version, pushes, opens the release
```

`make release` is the short path: it runs `Scripts/build-unsigned-ipa.sh`, moves the tag onto the
commit being released, pushes both, and attaches the IPA to the release. It publishes from the
machine that already has TDLib compiled, because the macOS runner queue costs more time than the
build does and the artefact is unsigned either way.

The workflow is still there, run by hand from the Actions tab. It builds the same script on a clean
checkout, which is the question CI is actually good for: *does this build somewhere else?*

## Limits, honestly

- Signed with a free personal team: up to 3 devices, and the certificate dies after 7 days.
- The IPA built by CI is unsigned. Nobody can install it without re-signing it with their own team.
- No CarPlay yet: the audio entitlement needs a paid Apple developer account and Apple's approval.
- Lyrics come from public sources. A song nobody has typed out has no words, and the app says so
  instead of showing a blank page.
- Update checking tells you a newer version exists and opens the release page. It cannot install it.

## Licence and credit

GPL-3.0 ([LICENSE](LICENSE)) — parts of the interface, including the lyrics screen, were taken from
[MeloX](https://github.com/youshen2/MeloX), which is GPLv3.

- **TDLib** — Boost Software License 1.0. The Telegram library; compiled from a pinned tag into `Vendor/`.
- **OpenSSL** — Apache-2.0, so TDLib can speak TLS.
- **SQLite** — the library, playlists and hearts live in one file.
- **Telegram-iOS** — GPL-2.0. Used only to measure spacing and colour. No code from it is in this repo.

Doni is not affiliated with or authorised by Telegram or any music service. It opens files that are
already inside your own account.

## Contact

Telegram: [@w1lliamcachamwri](https://t.me/w1lliamcachamwri) · Repository:
[github.com/williamcachamwri/Doni](https://github.com/williamcachamwri/Doni)
