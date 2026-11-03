# Design tokens

Values are **read out of** the Telegram-iOS reference checkout (GPL-2.0) and recorded here as
facts: hex numbers, point sizes, durations. No source file, class, asset or translation of that
code is copied into this app, which is written from scratch in SwiftUI. The checkout lives at
`~/Library/Caches/Doni/Telegram-iOS-DesignReference` (outside this repo, refreshed by
`make reference`) and is pinned by head commit so a quoted `file:line` stays checkable.

Reference head: `279f89e` (2026-10-28).

Each screen adds its own section *before* it is built. Nothing here is guessed: every row has a
`file:line` that can be re-opened.

## Palette — day

| Token | Value | Source |
|---|---|---|
| accent | `#0088ff` | `DefaultDayPresentationTheme.swift:56` |
| chatList.background | `#ffffff` | `DefaultDayPresentationTheme.swift:540` |
| chatList.itemBackground | `#ffffff` | `:542` |
| chatList.pinnedItemBackground | `#f7f7f7` | `:543` |
| chatList.itemHighlighted | `#e5e5ea` | `:544` (tap highlight) |
| chatList.itemSelected | `#e9f0fa` | `:546` |
| chatList.title | `#000000` | `:547` |
| chatList.secretTitle | `#00b12c` | `:548` |
| chatList.dateText | `#8e8e93` | `:549` |
| chatList.authorName | `#000000` | `:550` |
| chatList.messageText | `#8e8e93` | `:551` |
| chatList.messageHighlightedText | `#000000` | `:552` |
| chatList.messageDraftText | `#dd4b39` | `:553` |
| chatList.pendingIndicator | `#8e8e93` | `:555` |
| chatList.checkmark | `#0088ff` (day) / `#21c004` (dark) | `:554` |
| chatList.itemSeparator | `#c8c7cc` | `:541` |
| rootNav.primaryText | `#000000` | `:415` |
| rootNav.secondaryText | `#787878` | `:416` |
| rootNav.control | `#7e8791` | `:417` |
| rootNav.blurredBackground | `#f2f2f2` @ 0.9 | `:419` |
| rootNav.opaqueBackground | `#f7f7f7` mixed with white @ 0.14 | `:420` |
| rootNav.separator | `#c8c7cc` | `:421` |
| rootNav.badge | `#ff3b30` | `:422` |
| rootTabBar.separator | `#b2b2b2` | `:435` |
| rootTabBar.icon | `#959595` | `:436` |
| rootTabBar.selectedIcon | `#0088ff` | `:437` |
| rootTabBar.text | `#000000` @ 0.8 | `:438` |
| searchBar.background | `#ffffff` | `:446` |
| searchBar.inputFill | `#000000` @ 0.06 | `:448` |
| searchBar.inputText | `#000000` | `:449` |
| searchBar.placeholder | `#8e8e93` | `:450` |
| searchBar.icon | `#8e8e93` | `:451` |

## Palette — dark

| Token | Value | Source |
|---|---|---|
| accent | `#3e88f7` | `DefaultDarkPresentationTheme.swift:7` |

Dark palette is extended per screen as it is built; the day values above are not mirrored by
assumption.

## Metrics

Not yet extracted. Row height, insets, corner radius and 1 pt hairline widths are quoted here from
the component files that draw them (list rows from `submodules/Display/Source/ListView*`, overlay
player from `submodules/TelegramUI/Sources/OverlayAudioPlayerController*.swift`) at the moment each
screen is built, never from eyeballing a screenshot.

## Typography

Not yet extracted. Sizes and weights come from `ChatPresentationData.swift` (chat list) and the
component files per screen.

## Motion

Not yet extracted. Durations and curves come from each component's animation call sites per screen.

## Known traps found while extracting

- `UIColor(rgb:)` takes a `UInt32` literal, alpha-less; `UIColor(rgb: 0xf2f2f2, alpha: 0.9)` is a
  *blurred* background, so it must be composited over the blurred material, not flattened to an
  opaque colour, or the nav bar will read one shade too light.
- `opaqueBackgroundColor` is computed (`0xf7f7f7` mixed with white at 0.14 → `#f8f8f8`, since
  247·0.86 + 255·0.14 = 248), so the literal in the file is not the final colour. Re-derive mixed
  values instead of copying the input.
- `separatorColor` at 1 pt is a *hairline*: Telegram draws `1.0 / scale`, and a plain 1 pt line is
  visibly heavier on @3x.
