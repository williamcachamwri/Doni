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

Extracted per screen, in the screen sections below — row height, insets, corner radius and hairline
widths are quoted from the component files that draw them, never from eyeballing a screenshot. The
login screens have theirs; the chat list, player and overlay screens get theirs when they are built.

## Typography

Extracted per screen below. Sizes and weights are the literals in each component's `Font.regular(…)`
/ `Font.semibold(…)` call, so the weight name is Telegram's own (`Font.light(30.0)` is a real weight,
not an approximation of one).

## Motion

Extracted per screen below, from each component's animation call sites.

## Palette — day, `list.*` (the theme the login screens read)

The authorization screens do not use a chat or nav theme: they read `theme.list.*`, whose day
values sit in one block of `DefaultDayPresentationTheme.swift`.

| Token | Value | Source |
|---|---|---|
| list.plainBackground | `#ffffff` | `DefaultDayPresentationTheme.swift:475` |
| list.itemPrimaryText | `#000000` | `:477` |
| list.itemSecondaryText | `#8e8e93` | `:478` |
| list.itemDisabledText | `#8e8e93` | `:479` |
| list.itemAccent | `#0088ff` | `:480` (same literal as `accent`, `:56`) |
| list.itemDestructive | `#ff3b30` | `:482` |
| list.itemPlaceholderText | `#c8c8ce` | `:483` |
| list.itemHighlightedBackground | `#e5e5ea` | `:486` |
| list.itemPlainSeparator | `#c8c7cc` | `:488` |
| list.checkFill | `#0088ff` | `:505-506` |
| list.checkForeground | `#ffffff` | `:508` |

`SolidRoundedButtonTheme(theme:)` — the filled button every authorization screen ends with —
resolves to exactly those two check colours, plus a disabled pair computed as
`plainBackground mixedWith itemDisabledText @ 0.15` (= `#eeeeee`: 255·0.85 + 142·0.15 ≈ 238 per
channel) and `itemDisabledText` itself: `PresentationDataUtils/Sources/SolidRoundedButtonNode.swift:7-9`.

## Login (authorization sequence)

Source of these numbers is `submodules/AuthorizationUI/Sources/` (the module Telegram actually
uses to log in), plus `submodules/CodeInputView/Sources/CodeInputView.swift` for the digit boxes.
Paths below are relative to `submodules/`.

**Background: flat, not a gradient.** `AuthorizationSequenceController.swift:128` sets
`view.backgroundColor = theme.list.plainBackgroundColor` → `#ffffff`.
`PresentationThemePasscode` (`#46739e → #2a5982`, `DefaultDayPresentationTheme.swift:408`) belongs
to the device passcode lock and is **not** referenced anywhere in `AuthorizationUI/Sources/` —
grep for `.passcode` there returns nothing. Assuming the blue gradient here would be wrong.

### Layout, shared by all four screens

| Value | What | Source |
|---|---|---|
| `24.0` | horizontal inset of the content band | `AuthorizationUI/Sources/AuthorizationSequencePhoneEntryControllerNode.swift:42`, `…CodeEntryControllerNode.swift:524`, `…PasswordEntryControllerNode.swift:182` |
| `50.0` / `25.0` | primary button height / corner radius (`50.0 * 0.5`, a capsule) | `…PhoneEntryControllerNode.swift:425`, `…CodeEntryControllerNode.swift:254`, `…PasswordEntryControllerNode.swift:111` |
| `24.0` | gap between the button and the top of the keyboard / safe area (`y = height − inset − buttonHeight − 24`) | `…PhoneEntryControllerNode.swift:668-671` |
| `statusBarHeight ?? 20.0` | top inset | `…PhoneEntryControllerNode.swift:601` |
| `18.0` | slack above the title (`titleInset`, when width > 320) | `…PhoneEntryControllerNode.swift:606` |
| `80.0` / `10.0` | room left under the item stack (width > 320 / not) | `…PhoneEntryControllerNode.swift:607` |
| — | the item stack is centred in the band; each node's frame is measured to its text, so headings read as centred without a `.center` paragraph style | `AuthorizationUtils/Sources/AuthorizationLayout.swift` |

### Phone number (`AuthorizationSequencePhoneEntryControllerNode.swift`)

| Value | What | Source |
|---|---|---|
| `Font.light(30.0)`, `#000000` | title while the keyboard is closed | `:405` |
| `Font.bold(28.0)`, `#000000` | title once the keyboard is up — Telegram swaps the font, not just the position | `:609` |
| `Font.regular(17.0)`, `#000000`, centred | subtitle | `:419` (`lineSpacing 0.1` at `:414`) |
| `18.0` | gap title → subtitle | `:638` |
| `30.0` | gap subtitle → input block | `:639` |
| `115.0` | whole input block height | `:639` |
| `67.0` | country button frame height — it overhangs the row it sits in by `10.0`, because its bottom rule is drawn at `height − arrowSize` and the chevron dips to `height` | `:246`, `:45`, `:50-56` |
| `57.0` | number row frame height | `:247` |
| `57.0` + `58.0` | the two visible rows: the country rule lands at y ≈ 57 and the number rule at y ≈ 115, so the block reads as two ~equal rows | derived from `:246-247` with the block at `:639` |
| `71.0` at `x = 18.0` / number at `x = 107.0`, width `w − 96 − 8 − 24` | dial-code and number fields | `:253-254` |
| `Font.regular(20.0)`, `#0088ff` | country name | `:160` |
| `Font.regular(20.0)`, `#c8c8ce` | placeholder | `:164` |
| `Font(regular 20, monospacedNumbers)` | the `+84 (___) ___ ____` lookup mask | `:222` |
| `10.0` | width of the chevron drawn in the country row | `:45` |
| `left 40.0 / bottom 10.0` | content insets of the country button | `:130` |
| `#c8c7cc`, `UIScreenPixel` stroke | field rules: top line, bottom line, vertical divider | `:48`, `:66`, `:78-80` |

The fields have **no box**: no fill, no corner radius, `0.0`. Telegram draws a hairline above the
country row, a hairline below each row and a short vertical rule at the right of the dial code
(`:44-86`). The `IntroPhone` Lottie sticker (`:397`, node `100×100` at `:627`) is an asset and is
not reproduced here.

### Code entry (`AuthorizationSequenceCodeEntryControllerNode.swift`)

| Value | What | Source |
|---|---|---|
| `Font.semibold(28.0)`, `#000000` | title (all code variants) | `:542-565` |
| `Font.semibold(40.0)` | title when nothing was sent yet | `:568` |
| `Font.regular(17.0)`, `#000000`, centred | "code sent to …" line | `:427` |
| digit boxes `51.0` tall, `floor(24·51/28) = 43.0` wide | normal width | `CodeInputView/Sources/CodeInputView.swift:326`, `:341` |
| `44.0` / `floor(24·44/28) = 37.0` | compact width (≤ 320 pt, or ≤ 375 pt with more than 5 digits) | `…CodeEntryControllerNode.swift:645`; `CodeInputView.swift:326`, `:341` |
| `15.0` | gap between boxes (no prefix), and the box corner radius | `CodeInputView.swift:342`; radius at `:97` (`height == 28 ? 12 : 15`) |
| `floor(13·h/28)` → `23` (`20` compact), monospaced | digit font size | `CodeInputView.swift:327`, `:103-105` |
| `1.0 + UIScreenPixel` | box border width | `CodeInputView.swift:70` |
| `#c8c7cc` idle / `#0088ff` active / `#ff3b30` failed | box borders; digits `#000000` | `…CodeEntryControllerNode.swift:635-639` |
| `w − 28.0` | width the box row is laid out in | `:643` |
| `30.0` (max `100.0`) | gap subtitle → boxes | `:666`, `:688` |
| `50.0` (max `120.0`) | gap boxes → "send via …" line | `:668` |
| `Font.regular(17.0)`, `#0088ff`, centred | resend / other-option link | `:237` |
| `Font.regular(13.0)`, `#ff3b30`, centred, `11.0` under the boxes | error line | `:958`, `:950` |
| `Font.regular(13.0)`, `#8e8e93` | word/phrase hint | `:859` |
| `Font.regular(20.0)`, height `44.0`, width `w − 88.0` | free-text field for an SMS word or phrase | `:198`, `:712` |

### Password (`AuthorizationSequencePasswordEntryControllerNode.swift`)

| Value | What | Source |
|---|---|---|
| `Font.semibold(28.0)`, `#000000` | title | `:72`, `:200` |
| `Font.regular(17.0)`, `#000000`, centred | subtitle | `:81` |
| `Font.regular(20.0)`, height `44.0`, width `w − 80.0` | secure field | `:101`, `:215` |
| `#c8c8ce` placeholder (the hint is shown *as* the placeholder) | | `:159` |
| `#c8c7cc`, `1 px`, width `w − 48.0`, radius `0.0` | the field's only decoration is its bottom rule | `:98`, `:216` |
| `Font.regular(16.0)`, `#0088ff` / `#ff3b30` | "forgot" / "reset account" | `:88`, `:94` |

### Motion

| Value | What | Source |
|---|---|---|
| `0.5 s`, `kCAMediaTimingFunctionSpring` | the screen slides up into place | `AuthorizationSequenceController.swift:1407` |
| `0.2 s`, `easeInEaseOut` | and slides back down when it is dismissed | `:1416` |
| `0.3 s` alpha 0 → 1 | fade of the first screen's content | `:1367` |
| `0.2 s` fade, `0.3 s` spring (−100 y, additive), `0.4 s` scale 1 → 0.3 | the snapshot of the phone screen as it hands over to the code screen | `AuthorizationSequencePhoneEntryControllerNode.swift:544-549` |
| `0.3 s` alpha on each incoming node; `0.3 s` scale 0.3 → 1.0 on the sticker | the code/phone screens appearing | `:565-569` |
| `0.15 s`, `.easeInOut` | relayout when the code state changes | `AuthorizationSequenceCodeEntryControllerNode.swift:947` |
| shake `amplitude −30.0`, `0.5 s`, `count 6`, decaying | wrong code | `:953` |

## Known traps found while extracting

- `UIColor(rgb:)` takes a `UInt32` literal, alpha-less; `UIColor(rgb: 0xf2f2f2, alpha: 0.9)` is a
  *blurred* background, so it must be composited over the blurred material, not flattened to an
  opaque colour, or the nav bar will read one shade too light.
- `opaqueBackgroundColor` is computed (`0xf7f7f7` mixed with white at 0.14 → `#f8f8f8`, since
  247·0.86 + 255·0.14 = 248), so the literal in the file is not the final colour. Re-derive mixed
  values instead of copying the input.
- `separatorColor` at 1 pt is a *hairline*: Telegram draws `1.0 / scale`, and a plain 1 pt line is
  visibly heavier on @3x.
