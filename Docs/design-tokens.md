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

Doni is a dark app: the reference the whole shell is measured against is Telegram iOS 26 in dark
mode, so the dark palette is extracted in full rather than one token at a time. `DefaultDarkPresentationTheme.swift`
is the file; line numbers below are its own.

| Token | Value | Source |
|---|---|---|
| accent, `list.itemAccent`, `rootNav.accentText`, `navigationSearchBar.accentColor`, `chatList.checkmark` | **`#ffffff`** — in Telegram's *plain* dark theme the accent is white, not blue | `:344`, `:373`, `:420`, `:494` |
| `#3e88f7` | only the colour-customised dark variant is blue, and only when the user picked a colour | `:7` |
| chatList.background / itemBackground | `#000000` — the list is true black, so a row has no card and no fill | `:480`, `:482` |
| chatList.pinnedItemBackground | `#1c1c1d` | `:483` |
| chatList.itemHighlighted / itemSelected | `#121212` / `#191919` | `:484`, `:486` |
| chatList.title, authorName, messageHighlightedText | `#ffffff` | `:487`, `:490`, `:492` |
| chatList.dateText, messageText, muteIcon, sectionHeaderText | `#8d8e93` | `:489`, `:491`, `:498`, `:508` |
| chatList.itemSeparator | `#545458` @ **0.55** — the same value `rootNav` and `rootTabBar` use, so one hairline colour runs through the shell | `:481`, `:347`, `:361` |
| chatList.unreadBadgeActive background / text | **`#ffffff` / `#000000`** — an unread bubble in dark is a white pill with black digits | `:499`, `:500` |
| chatList.unreadBadgeInactive background / text | `#666666` / `#000000` | `:501`, `:502` |
| message.mediaActiveControl / mediaInactiveControl | `#ffffff` / `#ffffff` @ 0.4 | `:559`, `:595` |
| message.mediaControlInnerBackground | `#262628` | `:559` |
| message.textHighlight | `#f5c038` (a *bubble* colour; the chat list has no matched-run tint at all) | `:559` |
| rootNav button / primaryText / secondaryText | `#ffffff` / `#ffffff` / `#ffffff` @ 0.5 | `:339`, `:341`, `:342` |
| rootNav.blurredBackground | `#1d1d1d` @ **0.9** — the bar is a blur over black, which is what makes content read through it | `:345` |
| rootNav.opaqueBackground | `#1d1d1d` mixed 10 % with black → `#1a1a1a` | `:346` |
| rootTabBar icon / selected icon / text | `#ffffff` for all three; selection is carried by weight and the glass capsule, not by colour | `:362-365` |
| navigationSearchBar background | `#1c1c1d`; field fill `#ffffff` @ 0.1; placeholder, icon and clear `#8f8f8f` | `:372`, `:374`, `:376-378` |
| list.plainBackground / modalPlainBackground | `#000000` / `#1c1c1d` — a pushed screen is a lighter black than the list it came from | `:415`, `:416` |
| list.itemPrimaryText / itemSecondaryText / itemDisabledText | `#ffffff` / `#98989e` / `#8f8f8f` | `:417-419` |
| list.itemDestructive | `#eb5545` | `:422` |
| list.itemPlaceholderText | `#4d4d4d` | `:423` |
| list.itemBlocksBackground / modalBlocksBackground | `#1c1c1d` / `#1c1c1d` | `:413`, `:414`, `:424` |
| chatList.regularSearchBarColor / pinnedSearchBarColor | `#272728` | `:505`, `:506` |
| online dot | `#4cc91f` | `:514` |
| switch frame / handle / positive | `#39393d` / `#121212` / `#08a723` | `:405`, `:406`, `:408` |

**Correction to a day-only assumption.** The library row first shipped the state bubble in
`mediaActiveControl #0088ff` / `mediaInactiveControl #cacaca`
(`DefaultDayPresentationTheme.swift:632-633`). Those are the day values. In dark — the mode this app
is measured in — the same two controls are **white and white at 0.4**, and the unread badge Telegram
draws beside them is a white pill with black digits. The row's dark state bubble is therefore white,
and the blue stays only where Telegram itself keeps blue: nothing.


## Metrics

Extracted per screen, in the screen sections below — row height, insets, corner radius and hairline
widths are quoted from the component files that draw them, never from eyeballing a screenshot. The
login screens and the chat list have theirs; the player and overlay screens get theirs when they are
built.

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

### Navigation bar, and the way back to the number

| Value | What | Source |
|---|---|---|
| `separatorColor .clear`, `opaqueBackgroundColor .clear`, `edgeEffectColor .clear` | the sequence's bar is transparent: no fill, no hairline, only the back chevron is drawn | `AuthorizationSequenceController.swift:84` |
| `statusBarHeight` (wide) / `navigationBarHeight` (≤ 320 pt) | `insets.top` of the code screen. The wide layout leaves the bar zone to the 100×100 `IntroMessage` sticker (`:591`, item at `:650`); the compact one pushes the content below the bar | `AuthorizationSequenceCodeEntryControllerNode.swift:534`, `:655` |
| `44.0` | the bar's own content height Doni reserves under the status bar | iOS standard; Doni has no sticker art, so it uses the compact rule wherever the chevron shows |
| `#0088ff`, disabled `#d0d0d0` | back arrow colour | `Display/Source/NavigationBackButtonNode.swift:34`, `:40` |
| `4.0` arrow→label spacing, label `systemFont(17)`, hit slop `16` vertical / `10` horizontal | the rest of the back button | `:20`, `:7`, `:57` |
| alert, no title, generic action first and default action second; the default one runs `back()` | tapping the chevron does not go back immediately — it asks first | `AuthorizationSequenceCodeEntryController.swift:67-89` |
| `.phoneEntry(countryCode: default, number: "")` | what `back()` actually does: the engine is put back on the phone step with an empty number | `AuthorizationSequenceController.swift:379-386` |

**Doni's difference, forced by TDLib.** There is no cancel-authentication request at all —
`td_api.tl` offers only `logOut` (`:12292`), `close` (`:12295`) and `destroy` (`:12299`), none of
which leaves the session waiting for a phone number. Going back is therefore a UI move: the code
screen flies off, the number screen comes back with the number it was left with (Telegram clears
it), and picking a different number sends `setAuthenticationPhoneNumber`, which
`AuthManager.cpp:638-648` accepts from `WaitCode`, `WaitPassword`, `WaitRegistration`,
`WaitEmailAddress` and `WaitEmailCode` as long as no query is in flight — it answers with a fresh
`authorizationStateWaitCode` for the new number (`:1117-1120`, and `update_state` always sends the
update, `:1690-1693`).

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

`kCAMediaTimingFunctionSpring` is **not one curve**. `CAAnimationUtils.swift:119-204` routes a
0.5 s animation through a real `CASpringAnimation` and *every other duration* through a fixed
bezier, so the 0.3 s hand-over below is a bezier even though the call site says "spring".

| Value | What | Source |
|---|---|---|
| `0.5 s` spring: `mass 3, stiffness 1000, damping 500` (pre-26) / `mass 1, stiffness 555.027, damping 47.118` (iOS 26) | the whole sequence sliding up by its own height when it is presented | `AuthorizationSequenceController.swift:1407`, `UIKitUtils.m:53-77` |
| ζ = 47.118 / 2√555.027 = **1.000**, ω₀ = √555.027 = 23.559 rad/s → `response 0.2667 s, dampingFraction 1.0` | the same spring in SwiftUI's parameters | derived from the two lines above |
| `0.2 s`, `easeInEaseOut` | and sliding back down when it is dismissed | `:1416` |
| `0.3 s` alpha 0 → 1 | the first screen fading in | `:1367` |
| bezier `(0.380, 0.700, 0.125, 1.000)` | what "spring" means for any duration ≠ 0.5 s, i.e. every hand-over | `CAAnimationUtils.swift:186` |
| `easeInEaseOut` = `(0.42, 0.0, 0.58, 1.0)` | the default of `animateAlpha` / `animateScale` / `animatePosition` | `:397`, `:401`, `:421` |

Hand-over between two screens — the outgoing screen is snapshotted in two pieces and thrown off
the top while the incoming one fades up behind it (`AuthorizationSequencePhoneEntryControllerNode.swift:544-569`):

| Piece | What it does |
|---|---|
| field block | alpha 1 → 0 in `0.2 s`; position additive 0 → **−100** in `0.3 s` (bezier above); scale 1 → **0.3** in `0.4 s` |
| text block (title + notice) | alpha 1 → 0 in `0.2 s`; position 0 → **−140** in `0.3 s` |
| incoming nodes | alpha 0 → 1 in `0.3 s` each; the sticker scales 0.3 → 1.0 in `0.3 s` |
| the proceed button | **not** part of either snapshot — it is one shared node whose frame morphs |

Code boxes (`CodeInputView.swift`, driven from `AuthorizationSequenceCodeEntryControllerNode.swift`):

| Value | What | Source |
|---|---|---|
| alpha 0 → 1 in `0.25 s`, scaleY 0.01 → 1 in `0.25 s` from a bottom anchor, position spring from `+0.35·h` over `0.4 s` (`mass 5, stiffness 900, damping 70` → response 0.468 s, ζ 0.522) | a digit entering its box | `CodeInputView.swift:82-86`, `UIKitUtils.m:86-90`, `CAAnimationUtils.swift:338` |
| alpha 1 → 0 in `0.2 s` while it falls `h/2` | a digit being deleted (`:90-95`) | `:91-94` |
| border colour cross-fade `0.15 s` **linear** | inactive → active → failed → succeeded | `:72` |
| `inactiveBorder #c8c7cc`, `activeBorder #0088ff`, `failedBorder #ff3b30`, `succeedBorder #00c900` | the four border colours — `succeedBorder` is `itemDisclosureActions.constructive.fillColor` | `CodeEntryControllerNode.swift:635-638`, `DefaultDayPresentationTheme.swift:500` |
| wrong code: `animateError()` then shake `amplitude −30, 0.5 s, count 6, decay` → keyframes `0, −30, +15, −10, +7.5, −6, +5, 0`, evenly spaced, linear | the boxes throw sideways and decay | `CodeEntryControllerNode.swift:952-953`, `ShakeAnimation.swift:9-39` |
| word / phrase field: `addShakeAnimation()` with the helper's defaults → `amplitude 3, 0.3 s, count 4`, no decay = `0, +3, −3, +3, −3, 0` | the same gesture, gentler | `:919`, `:945` |
| red borders held for **0.85 s**, *then* the text is cleared | a rejected code is not emptied immediately | `CodeInputView.swift:190-201` |
| scale keyframes `1.0 → 1.1 → 1.0` over `0.4 s` | an accepted code pulses once | `CodeEntryControllerNode.swift:1003-1004` |
| error text `regular(13) #ff3b30`, centred, `field.maxY + 11`, or `+ 24` when the screen is wider than 320 pt | the line under the field | `:958`, `:967` |
| `0.15 s` `.easeInOut` | relayout when the code state changes | `:947` |

## Chat list — the clothing the library wears

`ChatListItem.swift` is the reference's chat-list cell: 3 900 lines of layout, but the geometry a
row is made of is six numbers and one formula. Every value below is at the default
`itemListBaseFontSize` / `baseDisplaySize` of **17**; Telegram scales each font by
`floor(base × n / 17)`, so at 17 the literals are the sizes themselves.

### The cell

| Value | What | Source |
|---|---|---|
| `Font.semibold(16)` | title (peer name) | `ChatListItem.swift:2289` |
| `Font.regular(15)` | last-message preview | `:2290` |
| `Font.regular(14)` | timestamp | `:2292` |
| `Font.with(size: 12, weight: .semibold, traits: [.monospacedNumbers])` | unread badge | `:2293` |
| `min(60, floor(base × 60/17))` → **60** | avatar diameter | `:2027`, `:2559` |
| `16.0` (`useCommunityViewLayout` → 10.0) | avatar left edge inset | `:2560` |
| `edge + 8.0 + diameter` → **84** | text left inset | `:2567` |
| `width − 84 − rightInset − 18.0` | text width, before the timestamp is subtracted | `:3673`, `:3849` |
| `contentRect.maxX − dateWidth`, `y = contentRect.minY + 2.0` | timestamp frame — its right edge lands **16** from the screen edge | `:4556` |
| `floor((itemHeight − 60) / 2)` | avatar is vertically centred → `y = 4` at the height below | `:4208` |
| `8 × 2 + 1 − 21 + title + 3 × measure − 1 − 3` | row height | `:4042-4051` |
| `1.0 / UIScreen.main.scale` | separator thickness — one *physical* pixel | `:928` |
| separator left `= leftInset + 2.0` (i.e. the text column), right `= rightInset + 16.0`; full width when the row is the last of a section or a pinned one that lost its neighbour | rule placement | `:5378-5394` |
| `top: firstWithHeader ? 29 : 0` | the only cell inset: 29 pt under a section header | `:2152-2154` |

The height formula counts **four** line boxes: the title plus three `measureLayout` lines, and
`measureLayout` is laid out with `titleFont` (`:4038`), so all four are the same height `L`. Substituting
`titleSpacing = −1`, `authorSpacing = −3`: `itemHeight = 17 − 21 + 4L − 4 = 4L − 8`. `L` is the line
height of `semibold(16)`, measured on this machine from the same San Francisco metrics iOS uses:
`ascender 15.469 + descender 3.375 + leading 0 = 18.84` → pixel-ceil **19**. So `4 × 19 − 8 = 68`.

Text anchors follow from the same block (`rawContentRect.origin.y = 8` at `:4054`, since `layoutOffset`
is `0.0` at `:3671`): the title sits **8** from the top of the row, and the preview at
`contentRect.minY + titleHeight − 2` = **25** (`:4766`). They are not centred as a pair — with the
avatar centred at 4…64, the title's line box straddles the avatar's upper third, which is what a
Telegram row looks like. A sender name (`authorLayout`) would be inserted at the same 25 with the
preview pushed to `25 + authorHeight − 3`.

### The row Telegram actually uses for audio

A music file is not a peer, and `ChatMessageInteractiveFileNode.swift` is the reference's audio and
document row, so the library's content column is that node's, inside the chat list's chrome:

| Value | What | Source |
|---|---|---|
| `progressDiameter = 44.0` | the play / download circle | `:858` |
| `Font.regular(16)` | file title | `:578` |
| `Font.with(size: 13, traits: [.monospacedNumbers])` | size line | `:579` |
| `Font.regular(11)` | duration line (voice notes) | `:580` |
| `constrained.width − 44.0 − 8.0` | the circle plus an 8 pt gap, i.e. the text column starts 8 after the button | `:744` |
| `x = 57, y = 1, height = 18`, width `boundingWidth − 60` | waveform frame | `:1279-1280` |
| `sampleWidth 2.0`, `distance 2.0`, `peakHeight 18.0` | one bar every 4 pt | `AudioWaveformComponent.swift:524-531` |
| title `#0b8bed`, description `#999999` | *inside a bubble* only — a list row keeps `chatList.title` `#000000` | `DefaultDayPresentationTheme.swift:636-637` |
| `mediaActiveControlColor #0088ff`, `mediaInactiveControlColor #cacaca` | played / unplayed, active / inactive button | `:632-633` |

### Avatars

Telegram has no letter avatars: a peer with no photo gets a white silhouette drawn on the gradient by
`generateAvatarImage(size:icon:iconScale:color:customColors:)` (`PeerAvatar.swift:495-540`), the icon
centred at `floor((size − iconSize) / 2)` and scaled by `size / 60`.

| Value | What | Source |
|---|---|---|
| `#ff516a→#ff885e`, `#ffa85c→#ffcd6a`, `#665fff→#82b1ff`, `#54cb68→#a0de7e`, `#4acccd→#00fcfd`, `#2a9ef1→#72d5fd`, `#d669ed→#e0a2f3` | the seven day gradients, red / orange / purple / green / cyan / blue / violet | `AvatarNode.swift:322-330` |
| `locations = [1.0, 0.0]`, start `(0,0)` → end `(0,h)` | vertical, **first colour at the bottom**: the lighter stop is on top | `AvatarNode.swift:1007-1017`, `PeerAvatar.swift:513-527` |
| radius `= side / 2` (`.round`); `.roundedRect` is `floor(width × 0.25)` | chat-list avatars are circles | `ChatListItem.swift:2039-2045`, `AvatarNode.swift:980-985` |

### What the channel actually sends

Every choice the row makes is a choice about data, so the data is measured first. These numbers come
from one full walk of the real channel — 172 messages, 168 of them `messageAudio`. The dump itself is
kept outside the repo: it is message content, and the brief says the app never writes message content
to a file anyone else can read.

| Fact | What it decides | Source |
|---|---|---|
| `audio.album_cover_minithumbnail` on **112/168** — 40×30 (57 of them) or 40×22 (55), 716–850 JPEG bytes, inline | the list shows real cover art without asking for a file, because TDLib serialises `bytes` as base64 inside the message | `td_api.tl:583`, `:361` |
| `album_cover_thumbnail` on the same 112 — 320×240 (57) or 320×180 (55) JPEG, as a `File`; `external_album_covers` on **168/168**, two entries each: 100×100 *and* 600×600, `expected_size` 0 on every one of them | the sharp tile is the **widest `external_album_covers` entry**, fetched for every track rather than only the 112 that carry `album_cover_thumbnail` — see the cover pipeline | `td_api.tl:583`, `:393` |
| a document's `minithumbnail` is the file icon Telegram draws for it | documents get the gradient tile; their minithumbnail is never read as artwork | `td_api.tl:594` |
| the covers come in two shapes — 40×30 over 4:3 (320×240) and 40×22 over 16:9 (320×180) | the square tile fills and crops the sides of a 16:9 cover; letterboxing it would leave white bars in an icon column that Telegram never shows | measured |
| `performer` on 168/168, tag `title` on 168/168 | the preview line is the artist's name; nobody has to parse a caption to say who sang | `td_api.tl:583` |
| tag titles are 14–71 characters, mean 51, and **93 of 168 end in "…"** | the cut is the posting bot's, not the row's — see the repair rule | measured |
| 166 of 168 captions are four lines, mean 142 characters: `Tiêu đề:` (108) *or* `Bài hát:` (59) with `Thể hiện:` (59), then `Kênh:` (108), then `Thể loại:` (156) or `Thời lượng: 1:11:37  Loại: Youtube` (11), then `Nguồn: @…bot` (167) | the whole name does exist, in the same message; and `Thời lượng` equals the tag `duration` in all 11 that carry it, so duration still comes from the tag alone | measured, `td_api.tl:583` |
| no `waveform` key anywhere in the audio objects | the row cannot draw Telegram's waveform, so it does not pretend to | measured, `td_api.tl:583` |
| mime `audio/mpeg` 117 + `audio/mp4` 51; `file_name` `.mp3` 107 + `.m4a` 51 + absent 10 | the extension column has to fall back to mime, and a bare file name is not proof of anything | measured |

**The repair rule.** A tag title ending in "…" is replaced by the caption's `Tiêu đề:` / `Bài hát:`
value only when that value *starts with* the cut title, compared with case, diacritics, width and runs
of space folded away (`TdTrack.fullTitle`). 89 of the 93 cuts repair; the four that do not — two where
the tag has an emoji the caption does not, one reworded, one with no name line — keep the bot's "…"
rather than show a name the channel never sent. The repair happens in the decoder, so search, the
store and Now Playing all read one whole name, and the longest repaired name is 100 characters: the
row's own middle truncation is what cuts it, not the data. A caption that is cut as well keeps its own
ellipsis — the list never claims a name it does not have.

### The library row Doni wears

Chrome from `### The cell`, content column from `### The row Telegram actually uses for audio`. The
icon column holds art rather than the 44 pt play control because 44 pt is too small a square for a
cover, and Telegram itself puts a 54 pt picture there.

| Value | What | Source |
|---|---|---|
| `floor(base × 54/17)` → **54** | the icon column's side — Telegram's own scaled target, so the tile is neither invented nor borrowed | `ChatListItem.swift:4212` |
| `floor((68 − 54) / 2)` → **7** | the tile is centred in the cell exactly as the avatar is | `:4208` |
| `floor(54 × 0.25)` → **13** | clipping is `.roundedRect`, not a circle: a square cover keeps its corners | `PeerAvatar.swift:209` |
| black at `0.3 / 4` over the art | Telegram's scrim over album art is 0.3, drawn under the controls (`ChatMessageInteractiveFileNode.swift:1815`); nothing sits on this tile, so a quarter of it evens a bright cover without muddying it | ratio is Doni's |
| `84 − 16 − 54` → **14** | the gap after the tile, chosen so the text column still starts at `textLeftInset` 84 and the rule still begins where the text does | `ChatListItem.swift:2567`, `:5378` |
| seven gradient pairs, `abs(messageId) % 7`, lighter stop on top | a coverless track gets colour the way a photoless peer does, and it is stable because a message id is | `AvatarNode.swift:322-330`, `PeerAvatar.swift:407-414`, `:426` |
| **20**, and a bubble holding no count is a square of that side | the unread-bubble slot carries download state instead of a number | `ChatListItem.swift:2578`, `ChatListBadgeNode.swift:89`, `:94` |
| `mediaActiveControl` played / `mediaInactiveControl` not | in dark both are **white**, the idle one at 40 % — `#0088ff` / `#cacaca` are the day values and Doni is a dark app | `DefaultDarkPresentationTheme.swift:559`, `:595` |
| title one line `.middle`, preview one line `.end` | a song's name matters at both ends, the way the audio row cuts it (`ChatMessageInteractiveFileNode.swift:751`), while a preview line is cut the way the chat list cuts its own (`ChatListItem.swift:3824`) | both cited |
| tabular digits in the duration column | `m:ss` and `h:mm:ss` line up down the column, as Telegram's bar title and its file sizes do | `ChatTitleView.swift:26`, `ChatMessageInteractiveFileNode.swift:579` |
| **12** pt heart, in the highlight, left of the duration | Doni's own: the chat list has no keep-mark in a row. 12 because it shares that line with `regular(14)` and a mark taller than the number beside it reads as the column's subject. It is the only way a library row can say "already kept" | `TelegramLibraryMetrics.favoriteMark` |
| the duration slot showing `1:20–4:05` instead | the same column, on a heart row that holds a slice — the list hands the row its headline, since a marked part of a song is the more useful number than its whole length | Doni's own, `TrackRow.headline` |
| long-press a row to keep or un-keep it | not a new gesture: the chat list's own row menu is built by `chatContextMenuItems`, and its destructive entries are drawn in the menu's destructive colour | `ChatContextMenus.swift:83`, `ChatListController.swift:1026`, `:1257` |
| clear button scaled `0.2 → 1.0`, not faded | Telegram scales the pill's clear button when it appears and goes | `SearchBarNode.swift:1647` |

**Doni's own, not copied from a line.** Colouring the matched run inside a title: Telegram's chat list
*filters* rows for a query and never tints runs (`ChatListUI` has no such call), so the accent half of
`HighlightedText` is Doni's — but the colour it uses is Telegram's `accent #0088ff`
(`DefaultDayPresentationTheme.swift:56`). Also Doni's own: the "Thử lại" capsule, the spinner ring, `—`
where a duration is missing, and `performer · size` as the preview line. The two glyphs inside the
tiles (18 pt note, 9 pt play / download arrow) are measured off renders, because Telegram's equivalents
are native assets (`Media/Message Audio Play`), not point sizes in a file.

### The cover pipeline

The blurry tile was the row's one real defect: a 40×30 minithumbnail scaled to 54 pt is a 4.5× upscale,
and it only exists on 112 of 168 tracks. The fix is measured in the same dump — `external_album_covers` is
on **168/168** with a 600×600 entry — so the list downloads instead of upscaling.

| Value | What | Source |
|---|---|---|
| widest of the two `external_album_covers` entries → 600×600 | the file to fetch, chosen by `width` rather than by position, because the pair's order is a habit of the posting bots and not a guarantee | `TdTrack.coverFileId`, `td_api.tl:583`, `:393` |
| `priority 1` for a cover, `16` for the song the user pressed play on | TDLib's priority is 1-32 and the higher wins; 168 covers must never queue ahead of audio | `td_api.tl:15001`, `TdFileDownloader.coverPriority` / `.audioPriority` |
| `synchronous: false` | the request answers with a `file` that is still in flight; the completion is a later `updateFile`, which is why `TdClient` mirrors those onto `files` | `td_api.tl:15001`, `:11596` |
| **20 s** patience | a file TDLib neither completes nor keeps talking about must not pin a row on its placeholder forever — the row falls back to the gradient | `TdFileDownloader.patience` |
| downsample to **162 px** | 54 pt at @3x is the largest the tile can ever be drawn; decoding 600×600 into memory 11× bigger for a list is the mistake this line exists to prevent | `ImageIO` `thumbnailPixelWidth`, `TelegramLibraryTheme.artSide` |
| tiers: sharp cover → minithumbnail → gradient | the row is never empty: art arrives when it arrives, and the gradient Telegram gives a photoless peer is the floor | measured, `AvatarNode.swift:322-330` |
| alpha `0 → 1` in **0.15 s** when the sharp cover lands | the chat list fades a badge's text in over exactly that, so a tile changing underneath a scrolling list is not a pop | `ChatListBadgeNode.swift:205` |
| 20 pt bubble on **every** row | chosen over hiding an idle bubble: a straight right-hand column scans better, and the column is Telegram's own second slot | `ChatListItem.swift:2578` |
| matched run in **`#3e88f7`**, not in the accent | dark Telegram's accent is white and so is the title, so a white highlight is invisible; `#3e88f7` is the colour the accent-customised dark theme uses | `DefaultDarkPresentationTheme.swift:7` |

**Why the second stream exists.** `TdClient.updates` has exactly one consumer — `TdLoginFlow.begin()` drains
it to read authorization states. A download watcher taking turns on that stream with the login loop would
quietly steal states, so `route()` copies every `updateFile`'s `file` onto `files`, and `TdFileDownloader` is
the only reader of that.


### Search bar (`SearchBarNode.swift`)

Telegram's `.modern` field, the one the chat list uses:

| Value | What | Source |
|---|---|---|
| `height 36.0`, `cornerDiameter 21.0` → radius `10.5` | the pill | `:859-870`, `:848-856`, `:1045` |
| `padding 10.0` | the field is inset 10 from each edge of the bar | `:872-883` |
| `Font.regular(17)` text, `Font.semibold(17)` Cancel in `theme.accent` | typing and the cancel word | `:839-846`, `:1122` |
| loupe at `field.minX + 5.0`, vertically centred minus one pixel; text at `field.minX + 24.0`; 27 pt reserved at the right for the clear button | inside the pill | `:1203-1205`, `:1195`, `:1200` |
| fill `#000000` @ 0.06, text `#000000`, placeholder and icon `#8e8e93`, clear `#7b7b81`, separator `#c8c7cc`, bar background `#ffffff` | `navigationSearchBar`, day | `DefaultDayPresentationTheme.swift:444-455` |

### Navigation bar title

| Value | What | Source |
|---|---|---|
| `Font.with(size: 17, weight: .semibold, traits: [.monospacedNumbers])` / `Font.regular(13)` | title / subtitle | `ChatTitleView.swift:26-27` |
| `#000000` / `#787878` | day colours | `DefaultDayPresentationTheme.swift:415-416` |

## Tab bar and the mini player

Doni's shell is four tabs with a strip of player above them, so both are measured against the
files that draw the real thing rather than invented. What Telegram does not have is marked as
Doni's own.

### Tab bar (`TabBarController.swift`, `TabBarNode.swift`)

| Value | What | Source |
|---|---|---|
| **49 pt** + the safe-area bottom inset; **34 pt** once there is a left inset | the band the bar occupies, which is what the list scrolls under | `TabBarController.swift:204-206` |
| **45 pt** tall per item, icon on top, label under it | the vertical layout every iPhone uses | `TabBarNode.swift:45` |
| `Font.medium(10.0)` | the label under an icon | `:20` |
| **4.0** between icon and label | the only gap in the item | `:35` |
| `Font.regular(13.0)`, item 34 tall, icon at `0.8` | the horizontal layout, for the wide classes only | `:20`, `:26-27`, `:41` |
| `1.0 / UIScreen.main.scale` | the separator, one physical pixel like every other rule in the app | `:18` |
| `Font.regular(13.0)` | the count badge that rides the icon | `:90` |
| icon, selected icon, text all `#ffffff` | dark carries selection by weight and by the glass capsule, never by colour | `DefaultDarkPresentationTheme.swift:362-365` |
| 24 pt glyph | Doni's own — the reference draws bundled PNGs whose box is not in the source, and SF Symbols have to be given one | |

### The music bar (`OverlayAudioPlayerControlsNode.swift`)

This is the panel Telegram slides up while audio plays. Doni's strip is a compressed version of
it, so every element inside the strip takes this file's number.

| Value | What | Source |
|---|---|---|
| **46 × 46**, corner radius **10** | the album art, 16 pt in from the edge and 18 pt down | `:855-857`, `:846`, `:849`, `:859` |
| `Font.semibold(17.0)` / `Font.regular(15.0)` | title / artist | `:111`, `:112` |
| `Font.medium(12.0)` | both timestamp labels | `:267`, `:270` |
| line **7.0**, `.round` cap, no handle | the scrubber: track `controlSecondaryColor` @ 0.5, filled `itemPrimaryTextColor`, buffered the same at 0.4 | `:266`, `:716` |
| 58 below the text origin | where the scrubber sits under the two lines | `:862` |
| **64 × 64** per button, play/pause glyph **76 × 76** | the control row | `:887`, `:899` |
| **190.0**, plus 8 when it is not the Saved-Music variant | the panel's own height, because it carries the scrubber and the buttons too | `:806`, `:820` |
| **64 pt** strip | Doni's own height: 46 of measured artwork plus 9 of padding above and below | |
| **2 pt** progress line | Doni's own — the strip is a way back to the player, not the player, so it takes the hairline weight the rest of the shell uses | |

### Now Playing (`UI/NowPlayingView.swift`)

The reference has no such screen: Telegram slides the 190 pt panel up over the chat instead. Doni
opens it full-screen, because the list is a scroll view of its own and a 190 pt sheet over a chat
list would cover three rows for no reason. The layout is therefore Doni's, and every element inside
it keeps the number above.

| Value | What | Source |
|---|---|---|
| 7 pt round-capped line, **no handle** | the scrubber, exactly as `:716` draws it | measured |
| **26** pt band around that line | `height: 10.0 + 8.0 * 2.0` is the frame the reference gives the scrubber, so the hit area is the frame it measured rather than one Doni picked | `:867` |
| side − 2 × 16, capped at **360** | the cover, 16 being the bar's own `sideInset` (`:846`); the cap is Doni's so a Max does not get a blurry square | measured inset, Doni's cap |
| corner **10** on that cover | the same corner the 46 pt strip art is drawn with (`:857`) | measured |
| `semibold(17)` / `regular(15)` / `medium(12)` | title / artist / both timestamps (`:111`, `:112`, `:267`, `:270`) | measured |
| **64 × 64** per transport button (`:887`), glyphs at 26 and 40 | the reference's glyphs are bundled PNGs in a 76 pt box (`:899`), which yields no point size for an SF Symbol, so the sizes are Doni's | box measured, sizes own |
| centre three spread over **320**, side buttons starting 12 pt outside the 16 pt inset | `buttonsWidth = min(width − insets − 2 × (sideInset + 60.0), 320.0)` (`:888`) and `x = leftInset + sideInset − 12.0` / its mirror (`:891`, `:892`). The reference's flanks are an order button and a looping one; Doni keeps the loop — as a cut, which is Doni's own behaviour — and spends the other slot on a heart at 24 pt | bands measured, glyph own |
| 20 pt caption line under the transport | Doni's own height, holding one `medium(12)` row (`:267`) whether or not a cut exists so marking one never moves the transport under the finger | |
| 44 pt bar, centred `semibold(17)` title, hairline under it | the nav bar every other screen in the app already wears | `ChatTitleView.swift:26`; the rule is `1.0 / scale`, as measured at `ChatListItem.swift:928` and `TabBarNode.swift:18` |

### Playlists (`UI/PlaylistsView.swift`)

The reference has nothing like this screen. Its music player only has saved music on the server
(`TelegramCore/Sources/TelegramEngine/Peers/SavedMusic.swift`, `Peer Info/SavedMusic.imageset`), and
the tree carries no user-named playlist for audio — `git ls-tree` over the whole repository returns
`PeerMessagesMediaPlaylist` (a media browser section) and nothing else. So the *layout* is Doni's,
and it is built entirely out of numbers this file already measured:

| Value | What | Source |
|---|---|---|
| 68 / 16 / 84 / 54 / 13 / 7 / 10 / −2 / 1 px rule | the playlist row is the chat list's row with the icon column holding a gradient and a note glyph instead of a cover | `ChatListItem.swift:4042-4051`, `:2560`, `:2567`, `:4212`, `PeerAvatar.swift:209`, `:4208`, `:4054`, `:4766`, `:928` |
| `abs(id) % 7` gradient on the tile | the same seed and palette a coverless peer's avatar gets, seeded by the playlist's own id | `AvatarNode.swift:322-330`, `PeerAvatar.swift:407-414` |
| `music.note.list` at the tile's 18 pt | the glyph is Doni's (Telegram's is a bundled PDF, `Chat List/AudioIcon`), the size is the one already on a coverless tile | `TelegramLibraryMetrics.artGlyph` |
| 44 pt bar, `semibold(17)` title, `regular(13)` count, hairline | the bar every screen wears | `ChatTitleView.swift:26`, `:27` |
| 48 pt of title padding each side | not invented: the two flanking buttons are the 44 pt touch targets plus the 4 pt the library's bar already gives them | `Docs` above |
| a playlist's rows open through the stack, and each level hides the system bar to draw its own | Telegram's controller stack does exactly this — a pushed list replaces the bar rather than adding to it | behaviour, not numbers |
| flat verbs in the row menu, no submenu | Doni's own, and deliberate: a submenu is the one SwiftUI shape this project cannot verify without a simulator | |
| "N bài", "Chưa có danh sách nào", the `+` in the bar, `music.note.list` | Doni's own — no counterpart exists in the reference | |

### Motion (`ChatListBadgeNode.swift`)

Already recorded with the library row; `TelegramShellMotion` is that file's timing — 0.15 s alpha
in (`:205`), 0.15 s alpha out (`:161`), 0.12 s collapse (`:170`), 0.2 s entrance overshoot
(`:128`, `:134`) and the 8 pt slide (`:206`).

## Settings — the clothing the item list wears

`submodules/ItemListUI` is the module every real Telegram settings screen is built from. It is
now in `Scripts/fetch-design-reference.sh`'s path list, so these numbers are read off the same
checkout as everything else. The base sizes are not written as literals anywhere in the fetched
subset — `fontSize.itemListBaseFontSize` is passed through — but the module's own ratios fix them:
`/ 17.0 * 15.0` (`ItemListTextItem.swift:169`), `* 14.0 / 17.0` (`ItemListSwitchItem.swift:290`),
`* 15.0 / 17.0` (`ItemListDisclosureItem.swift:467`) say the row base is 17, and `* 12.0 / 13.0`,
`* 11.0 / 13.0` (`ItemListSectionHeaderItem.swift:188`, `:191`) say the header base is 13.

### The row

| Value | What | Source |
|---|---|---|
| `regular(17)` | a settings row's title — the same 17 the bar titles wear, but regular, because the row is not a heading | `ItemListActionItem.swift:159` |
| **15.0** above and below that title, so the row is text height + 30 | the glass vertical inset. Legacy is 11 (`:191`); Doni wears the glass number the way the app wears the glass bar | `:186-189`, `:200` |
| `y = floorToScreenPixels((height − textHeight) / 2) + 1.0` | the title's own placement — the +1 is in the source, not a rounding artefact | `:303` |
| **16** for the title, and **16** for the hairline's left end | `leftInset = 16.0 + params.leftInset`, `bottomStripeInset = 16.0 + params.leftInset` | `:237`, `:282` |
| in the plain style the rule runs from there to the edge; only the grouped card stops it **16** short | `bottomStripeNode.frame = (x: leftInset, width: params.width − leftInset)` for `.plain` (`:253`), and `params.width − rightInset − bottomStripeInset − separatorRightInset` with `separatorRightInset = 16.0` for the card (`:184`, `:298`) | Doni's rows are plain, so they take `:253` |
| `regular(15)` for the value at the right, **20** in from the edge | the disclosure row's right-hand text | `ItemListDisclosureItem.swift:467`, `:503` |
| `regular(14)` for the line under a title | a row's secondary text, scaled off the same base | `ItemListSwitchItem.swift:290` |
| **13** above and below a row that has that second line, with **1** between the two lines | `verticalInset = 13.0` the moment a label exists, and `titleSpacing = 1.0`; the row is `inset × 2 + title + 1 + label` (`:551`) — so a two-line row is not a one-line row plus a line | `ItemListDisclosureItem.swift:525-528`, `:546`, `:551` |
| **44** fixed for a row that holds a control | the switch row does not size on its text at all | `ItemListSwitchItem.swift:311`, `:316` |
| **43** of column, icon centred inside it | the icon band a settings title is pushed right by (`leftInset += 43.0`; `iconNode.frame.x = params.leftInset + floor((leftInset − params.leftInset − icon.width) / 2)`). Doni's rows have no icons, so its titles sit at 16 — the position the reference gives a row that sets `noInsets` (`:418`) | `ItemListDisclosureItem.swift:418-422`, `:607` |
| `itemDestructiveColor` | the colour a destructive row's text takes | `ItemListActionItem.swift:168-170` |

### The section header

| Value | What | Source |
|---|---|---|
| `regular(13)`, **15** in from the left | a header is *not* on the row's 16: the inset is 15 | `ItemListSectionHeaderItem.swift:180`, `:183` |
| band = text height **+ 13**, title pinned at **y = 7.0** | so a header is 7 above and 6 below its text — the numbers are the frame, not a guess at it | `:228`, `:252` |
| **24** above a header, **28** when another section already ended above it | the gap that separates sections | `:231`, `:233` |
| `sectionHeaderTextColor` = `#8d8e93` | dark's own header grey — the same value the chat list's date already carries, so Doni spends no new colour on it | `DefaultDarkPresentationTheme.swift:430`, `:205` in `TelegramPalette.swift` |
| an action in the header is `itemAccentColor` | the "clear everything" style verb, if a header ever gets one | `:204` |
| rows in a plain list get **22** between sections | the non-grouped rhythm, recorded because the grouped one is measured above and the two are not interchangeable | `ItemListItem.swift:84`, `:90` |

### Settings (`UI/SettingsView.swift`)

Telegram's settings screens set the card's side margin from their own caller
(`ListView`'s `params.leftInset` is `state.insets.left`, `ListView.swift:2316`, filled by
`additionalInsets` — `ItemListController.swift:138` — which no fetched module sets), so the
grouped card's margin is the one number here the reference does not give. Doni therefore keeps
the treatment the rest of the shell already wears: full-bleed rows on `chatListBackground`, an
inset hairline at 16, and no rounded card. That is Doni's own *choice*, made so the screen reads
as one app with the library rather than as two widgets, and every number inside it is measured.

| Value | What | Source |
|---|---|---|
| 44 pt bar, centred `semibold(17)`, 1 px rule | the bar on every other screen | `ChatTitleView.swift:26`, `ChatListItem.swift:928` |
| title 17 / value 15 / secondary 14 / header 13, insets 16 and 15, 15 pt of vertical padding (13 and a 1 pt line once a row has a second line), 20 pt for the value, 24 pt between sections | all five rows and both headers | the two tables above |
| full-bleed rows, no icons, no card | Doni's own, as just stated | |
| the counts, "Đăng xuất", the channel rows' `@username` line | Doni's own content — the app has one purpose, so its settings say what is on the phone rather than offering 30 sections | |
| logout wipes the library (`Library.wipe()`) before the session closes | Doni's own behaviour, and the reason the row exists at all: `file_id` is TDLib's per-database number (`td_api.tl:326`), so rows kept across a logout would point at nothing | `App/Library.swift` |

## The screenshot oracle — the scale and the materials Doni actually wears

The parity test is a photo: `IMG_2544` is the reference app's chat list on the user's phone, and
`IMG_2543` is Doni on the same phone. Both are 1170 × 2532 px, i.e. 390 × 844 pt @3x, so every number
below is `px / 3` read off the reference with `Scripts/probe.swift` (`box`, `vedges`, `hedges`, `bands`).
Two things come out of that photo that the source files alone cannot give: **which text scale the app
is really drawn at**, and **what the glass actually reads as** once it is over black.

**The scale is `baseDisplaySize` 14, not 17.** Every source number in the sections above is written at
17; the phone is not. Three independent measurements say so: the row pitch is 168 px = **56 pt** (at 17
it is 68), the avatar is 147 px = **49 pt** = `floor(14 × 60/17)`, and the ink heights are those of
`semibold(13)` / `regular(12)` — "Zalo" (ascender only) is 27 px = 9.0 pt, "macbook" 30 px = 10.0 pt,
and a 16 pt title would measure 11.7. So the whole list is Telegram's smallest text size, and Doni
copies the photo rather than the default: every font below is `floor(14 × n / 17)`.

**2026-11-04 — the user overruled the oracle's scale.** Seen on the device, the photo's `extraSmall`
list read as cramped, and the direction was "đẹp hơn, hiện đại hơn". So the list moved to the source's
own base 17 — the same expressions, evaluated at 17: the pitch is `4 × 20 − 8` = **72 pt**, the
artwork **60 pt**, the text column **86 pt**, the title `semibold(16)`, the preview `regular(15)`, the
timestamp `regular(14)`. The rows above keep the photo's numbers as measured; the app wears the
17-scale of them. The bar's band was overruled the same day — see "The bar, as photographed".

**The materials are Apple's, not a flattened colour.** The bar has no opaque band and no rule under it —
`hedges` across y 336…344 px finds nothing — and the band it does occupy reads `#1c1c1d`, which is both
what `glassEffect` composites to over black and what `chatList.pinnedItemBackground` (`:483`) is, so the
photo cannot separate the two; what it does say is that the bar and the pinned block are the same colour
and neither is a rule. The capsules are glass. Doni keeps the geometry Telegram measured and takes its
surfaces from HIG + Liquid Glass: real glass where the OS has it (`#available(iOS 26.0, *)`),
`.ultraThinMaterial` over the measured colour where it does not.

### The row, as photographed

| Value | What | Where |
|---|---|---|
| **56 pt** (168 px, four pitches measured) | row pitch, pinned and unpinned alike | `vedges`/separator rows at y 1181, 1349, 1517, 1685, 1853, 2021 |
| **49 pt** circle, left edge at **16 pt** | artwork column, vertically centred (3.5 pt above and below) | `hedges y=1265`: 48 → 195 px; `vedges x=121`: 1191 → 1338 px |
| **75 pt** | text column left edge — `avatarLeftInset = 24 + diameter` (`ChatListItem.swift:2574`) plus the 2 pt the content rect carries (`:4054`), *not* the 84 the 17-scale gives. The gap after a 49 pt tile at 16 is therefore 10 pt. | `hedges 1349` |
| `semibold(13)` `floor(14 × 16/17)` | title | `:2289` + ink 27–30 px |
| `regular(12)` `floor(14 × 15/17)` | preview line, `#8d8e93` | `:2290`, ink 26 px |
| `regular(11)` `floor(14 × 14/17)` | timestamp, `#8d8e93`, right edge at **372 pt** = 16 from the edge | `:2292`, `hedges 1230`: last ink 1117 px |
| `#000000` / `#1c1c1d` | list background / the pinned block's background | `box 15 1400`, `box 15 700` |
| `#545458` at 0.55, **1 px**, from **75 pt** to **374 pt** | the rule: it starts where the text does and stops 16 from the right edge. Over black it reads `#2e2e30`, over the pinned block `#3b3b3d` — the same token, two composites | `hedges 1349`, `hedges 1517` |
| 63 × 48 px = **21 × 16 pt**, pill, `#666666` fill, `#000000` digits, `semibold(9)` tabular (`floor(14 × 12/17)`, `:2294`) | the unread bubble slot: `badgeDiameter = floor(base × 20/17)` = 16 (`:2578`), content-width (`badgeWidth = max(16, text + 8)`, `ChatListBadgeNode.swift:89`), right edge at `contentRect.maxX` = `width − 16` because `params.rightInset` is zero, top at `contentRect.maxY − 16 − floor(4 × 14/17)` (`:4614-4625`) = **21.7 pt** below the row's top | `hedges 1440`: 1059 → 1122 px; `vedges 1112`: 1420 → 1457 px, and at `x=1080`: 1415 → 1463 px |
| `#eb5545` fill, white digits | a mention bubble — the same pill, the destructive colour | `box 150 2300` |
| `#38c4ed` fill, white digits | the fork's own accent on the active pill. Doni uses its own accent token here, so this hex is recorded as *theirs*, not as a target | `box 1030 2100` |

### The bar, as photographed

**2026-11-04 — the band became a pill.** Drawn literally, the full-bleed band read on the device as a
flat slab with hard edges, and the user rejected it. The bar is now a floating glass **pill**: the
measured 44 pt of controls wrapped in 4 pt of glass above and below (52 pt), 16 pt from the screen's
edges like the photo's capsules, 8 pt under the safe area, the first row 12 pt below it
(`TelegramBarMetrics.topClearance` = 72). The actions sit on the glass rather than in nested capsules,
because the pill itself is now the vessel the band was.

| Value | What | Where |
|---|---|---|
| `#1c1c1d`, and **no rule** | what the bar band reads over black, and the absence of a separator under it | `box 10 200 30 100`; `hedges 336/339/341/344` |
| glass starts **50.7 pt** down, the first row **113.7 pt** | the band is 63 pt of its own, i.e. **66.7 pt below the phone's 47 pt safe area** | `vedges 350 120 360`: #000000 → #161617 at 152 px; separators at 341 px |
| capsule **44 pt** tall, its top **10.3 pt** below the safe area, so its centreline is **32 pt** down | the row everything in the bar shares: the title ink centre is at 78.5 pt and the icon ink centre at 78.8, both against a 47 pt inset | `vedges 100`: 172 → 302 px; `bands 380 800 150 341`: 212→259 px |
| `semibold(22)`, centred, 16.0 pt of ink | the large title — the photo's bar title is *not* the literal `semibold(17)` the source sets (`DocumentPreviewController.swift:202`); its stems measure 7 px where the row's `semibold(13)` measures 4, and 13 × 7 ÷ 4 = 22.7 | `bands 380 800 150 341`: 212→259 px; `row 236` runs |
| leading capsule left edge **16 pt**, 12 pt of padding around the word | the text action ("Sửa") | `hedges 225`: 47→211 px |
| group capsule **116.7 pt** wide, 44 tall, right edge at **374 pt**, three items on a 38.9 pt pitch | the trailing icon group | `hedges 225`: 773→1123 px |
| icon ink 19.3 pt tall | the glyph size inside that group — Doni sizes an SF Symbol to land on it | `bands 780 1120 150 320`: 208→265 px |
| glass reads `#3e3e40` over the pinned block, rim `#686869` | what `glassEffect(.regular)` composites to on this screen — the fallback Doni must land near | `box`/`vedges` inside the capsules |

### The floating tab bar, as photographed

| Value | What | Where |
|---|---|---|
| **20 pt** from the left edge, the right edge and the bottom **of the screen** | the bar floats; nothing is full-bleed. The bottom margin is measured past the home indicator, so the glass sits inside the safe area rather than on top of it | `hedges 2380`: 60 px and 1110 px; `vedges 400`: the capsule ends at 2472 px = 824 pt of 844 |
| **67.3 pt** tall (2262 → 2472 px) | the band both the capsule and the circle share, bottom-aligned | `vedges 400`, `vedges 1014` |
| capsule 278 pt for three items → **92.7 pt** each | the item pitch inside the glass | `hedges 2380`: 60 → 894 px |
| separate **64 pt** circle, 8 pt after the capsule | search, as its own glass item rather than a field in the bar | `hedges 2380`: 918 → 1110 px; `vedges 1014`: 2280 → 2472 px |
| icon ink 19.3 pt tall, centre **25.1 pt** below the band's top; label centre **50.3 pt** | the item's two rows: a 24 pt glyph over a `medium(10)` label, both on centres rather than in a stack with a fixed gap | `bands 300 480 2270 2472`: 2320→2371, 2410→2435 px |
| selected item: glyph and label in the accent, and the glass behind it reads blue (`#304562` family) | selection is *tinted glass*, not a filled circle | `hedges 2320` |
| the list scrolls **under** the glass — a row is cut mid-height by the bar in the photo | the bar is an overlay, and the scroll content is inset instead of clipped | the last row of `IMG_2544` |
| loupe ink **21.0 pt** tall, centred in the circle | the glyph inside the 64 pt search circle — Doni sizes an SF Symbol to land on it, which wants `pointSize` 24 | `bands 918 1110 2280 2472`: 2344 → 2406 px |
| the capsule is **278 pt** because the margins and the circle take the rest | 390 − 2 × 20 − 64 − 8. Doni's four tabs share that same 278 pt, so its item is 69.5 rather than the measured 92.7 | `hedges 2380`: 60 → 894, 918 → 1110 px |

**Doni's own, in this section.** Four tabs in the photo's three-item capsule, so the pitch is
`278 / 4` and not the measured 92.7; the search circle opens its **own screen** (`UI/SearchView.swift`),
because a field under the bar would be a row the photo does not have — the library's list starts
12.7 pt below the band exactly as the reference's does; `play/pause` and the account menu in the
trailing group instead of Telegram's camera / add-contact / compose; a 60 pt *cover* in the column
the reference uses for an avatar (49 pt in the photo, 60 at the scale the user directed), circular
because the photo's column is circular; the download
bubble, which occupies the unread pill's slot with the pill's own metrics; a badge over the library
tab only while the channel is being read; and the mini player as a third floating capsule above the
bar with 8 pt between them, since the reference's music panel is full-bleed and this build's chrome
is not.

**The clearance the floating chrome needs.** A list that scrolls under the glass still has to end
above it, so the scroll content is inset by `TelegramFloatingBarMetrics.clearance(stripVisible:)` =
`20 + 67.3 (+ 64 + 8 when the strip is showing)` — 87.3 pt, or 159.3 with a song loaded. The shell
owns that number and hands it down through `\.telegramFloatingClearance`, because only the shell
knows whether the strip is up.

## MeloX — the music shell Doni now wears (2026-11-04)

The user replaced the oracle: *"lấy toàn bộ giao diện home, playlist, tạo playlist, settings, thêm
nhạc vào playlist, queue hàng chờ nhạc tiếp theo, tab bar và cả now playing và animation giao diện
của app… https://github.com/youshen2/MeloX"*. MeloX is SwiftUI, GPL-3.0, deployment target **iOS 26**,
and leans on system Liquid Glass. Doni stays on iOS 17, so these are *transcriptions* of its numbers
into Doni's own views — no file, type or asset is copied. Provenance is `file:line` in
`/tmp/MeloX/MeloX`, and the tokens live in `MusicScreenTheme.swift`.

**Global.** The accent is `.tint(.red)` (`App/MeloXApp.swift:95`); Doni forces the dark scheme, where
system red is `#ff453a` → `MusicTint.accent`.

| Token | Value | Source |
| --- | --- | --- |
| Cover radius (default) | 10 | `Shared/Media/ArtworkImage.swift:7` |
| Placeholder fill / glyph | `secondary` 0.12 / `.title2` `music.note` | `ArtworkImage.swift:60,68-70` |
| Image load fade | `easeOut(0.18)` | `ArtworkImage.swift:46` |
| Feed section gap / top / bottom | 32 / 8 / 28 | `Features/Home/HomeRecommendedView.swift:101,139-140` |
| Shelf gutter | 16 (both header padding and scroll content margin) | `HomeRecommendationSections.swift:102,109` |
| Header→shelf / card→card | 14 / 14 | `HomeRecommendationSections.swift:85,105` |
| Card artwork | 166 playlist · 154 song · 160 default | `HomeComponents.swift:110-112`, `HomeRecommendationSections.swift:123-125`, `MediaCardView.swift:8` |
| Card text gap | 8 | `MediaCardView.swift:11` |
| Grid | 16 padding · 145 min item · 16 spacing | `MediaCardGridLayout.swift:9-11` |
| Quick-action tile | 132 tall · ≤230 wide compact · `min(w×0.86, 340)` standard · r14 · p14 · gap 16 | `HomeQuickActionsView.swift:101,131-135,144`, `HomeComponents.swift:11,43,53` |
| Tile gradient | topLeading→bottomTrailing over pink/red, orange/red, pink/purple, indigo/purple, cyan/blue, mint/teal | `HomeQuickActionsView.swift:81-96`, `HomeComponents.swift:47-52` |
| Tile watermark | 72 `semibold` at white 0.24; overlay title `.title.bold()` with 18 padding; box aspect 1.48 | `HomeComponents.swift:79-94` |
| Mini player | art 40 (30 inline) r6 · gap 10 (8) · text gap 1 · buttons 36 circle · padding 12/6 | `MiniPlayerView.swift:14-30,47-93,110-112` |
| Mini player swipe | `DragGesture(minimumDistance: 28)`, horizontal-dominant | `MiniPlayerView.swift:115-123` |
| Playlist list row | art 54 r7 · gap 12 · text gap 4 · count `.caption` secondary | `LibraryPlaylistsView.swift:155-163` |
| Playlist hero | art r12, shadow black 0.18/r18/y10 · 26 top · 24 to `title2.bold()` · 8 to `title3` · 7 to `subheadline.weight(.medium)` · 17 to actions · 22 bottom · 24 sides | `PlaylistDetailContent.swift:190-226` |
| Hero action row | `GlassEffectContainer(spacing: 14)`, 30 pt glyphs, play at `title3.bold()` | `PlaylistDetailContent.swift:328-389` |
| Track row | 40 index column (32 circle) · art 48 r6 · gap 12 · leading 20 / trailing 8 · vertical 11 (8 with art) | `PlaylistTrackList.swift:89-101,223-232,254-269` |
| Add-to-playlist row | art 52 r7 · gap 12 · text gap 3 | `AddToPlaylistSheet.swift:86-95` |
| Queue pills | height 44 · radius 22 | `NowPlayingQueuePage.swift:289,297` |
| Queue row | art 48 r6, title `.body`, note `.subheadline` | `NowPlayingQueuePage.swift:343-351` |
| Settings card | r26 continuous, `secondarySystemGroupedBackground` · header `headline` secondary at 14 padding · card gap 10 · divider leading 58 | `SettingsHomeComponents.swift:23-50` |
| Settings row | minHeight 68 · icon `title3.medium` tinted, 30 wide · gap 14 · text gap 3 · title `body.semibold` · subtitle `caption` · chevron `caption.semibold` tertiary · padding 18/13 | `SettingsHomeComponents.swift:58-88` |
| Now playing padding | 32 horizontal | `NowPlayingView.swift:5` |
| Dismiss handle | capsule 60×5 white 0.52, 8 top, inside a 34 box | `NowPlayingView.swift:465-473` |
| Artwork | `min(w+16, max(170, h−279−92))`, r12, shrinks to 0.74 paused | `NowPlayingArtworkPage.swift:4,39-50,66` |
| Artwork shadow | playing 0.34/r26/y15 · paused 0.18/r14/y8 · none elsewhere | `NowPlayingPortraitArtwork.swift:45-58` |
| Bottom overlay | utility 62 + core 279 = 341 | `NowPlayingBottomControls.swift:4-6` |
| Core stack | progress 52 · 19 · transport 82 · 31 · volume 42 · 3 · selector 50 = 279 | `NowPlayingBottomControls.swift:36-59` |
| Transport | circles 64, glyphs 34/48/34 `.medium` | `NowPlayingControls.swift:197,224,248,286` |
| Progress block | thumb hidden, `.tint(.white)`, times `caption2.monospacedDigit()` white 0.5, chip 9/4 padding r7 white 0.12 with a 9 glyph | `NowPlayingControls.swift:11-52,99-105,151-160` |
| Volume | row 42 · slider 32 · glyph gap 10 · white 0.62 | `NowPlayingControls.swift:324-337` |
| Page selector | row 50 inset 32 · 44 circles at `.title3` white 0.72 · selected 0.68 white disc, 0.68 black ink · badge 15 with a 7 glyph at (3,1) | `NowPlayingControls.swift:451-512` |
| Title line | `title3.semibold` over `title3` artist at white 0.64, 2 apart, 8 to badges, 14 to actions | `NowPlayingArtworkPage.swift:130-153` |
| Song header (queue/lyrics) | 72 tall, art r12, enters from 40 below | `NowPlayingSongHeader.swift:43,104`, `NowPlayingMotionSpec.swift:528` |
| Backdrop | artwork at scale 1.35 under a 90 blur | `NowPlayingBackground.swift:127-128`, `AppSettings.swift:2007` |

**Motion bank** (`NowPlayingMotionSpec.appleMusic26`, all iOS 17-safe). Page transitions `.smooth`
0.30 selection / 0.44 direct alternate / 0.24 outgoing / 0.22+0.07 incoming / 0.40+0.08 song header /
0.34+0.11 delayed resident / 0.48 artwork resize. Spatial page curves are
`interpolatingSpring(mass 1, stiffness 350, damping 40)`; opacity curves are
`timingCurve(0.42, 0, 0.58, 1)` at 0.18 (lyrics) and 0.30±0.10 (queue). Content scales 0.92 alternate /
0.90 presenting. Core layers rise from 180/165/148/128 with show delays 0.025/0.05/0.075/0.10 and hide
delays 0.075/0.05/0.025/0 on a 0.24 `.smooth`; the utility band goes 64 down and 0.82. Transport press:
glyph 0.8 (`easeInOut 0.16`), disc from 0.86 (`easeOut 0.18`) at white 0.1, release `easeInOut 0.4`.
Play glyph swap `.symbolEffect(.replace.downUp.wholeSymbol, .speed(1.6))` inside `.snappy(0.2)`.
Artwork bounce: `easeOut(0.17)`→1.055, hold 170 ms, `spring(duration 0.42, bounce 0.24)` home.
Interface auto-hide 5 s.

**The overdamped spring has no iOS 17 call.** MeloX asks for its settlement horizon with
`Spring(mass: 1, stiffness: 350, damping: 40, allowOverDamping: true).settlingDuration(…)`. The
`allowOverDamping:` initialiser is newer than iOS 17, so Doni carries the evaluated number: damping 40
against a critical 2√350 ≈ 37.4 is overdamped, roots −12.9289 and −27.0711, y(0) = −1 with y′(0) = 0
gives A = −1.91421, and −ln(0.001 ÷ 1.91421) ÷ 12.9289 ≈ **0.5845 s** → `MusicMotion.pageSpringSettling`.

**API substitutions.** MeloX's chrome is iOS 26 system plumbing; Doni reproduces the *look* on iOS 17:

| MeloX | Doni |
| --- | --- |
| `TabView` + `.tabViewBottomAccessory { MiniPlayerView }` + `.tabBarMinimizeBehavior(.onScrollDown)` | hand-built `AMTabBar` + `MiniPlayerBar` in one floating chrome |
| `matchedTransitionSource` + `.navigationTransition(.zoom)` | the existing `matchedGeometryEffect` morph |
| `GlassEffectContainer`, `.buttonStyle(.glass)` / `.glassProminent` | `telegramGlass(_:fallback:)` |
| `MeshGradient` / Metal `layerEffect` backdrop | blurred-artwork backdrop at the same 1.35 / 90 numbers |
| `Picker(.segmented)` in the nav bar for home sections | Doni has one home feed; no picker |
| `Tab(role: .search)` | search is a real tab in the bar, last, with no separate circle |
| Nuke `LazyImage` thumbnails | `TrackCover` + `CoverArtwork` |

Two structural notes the transcription keeps. First, MeloX's queue is **not a sheet** — it is the third
page of the player's own `ZStack`, with the artwork pinned to a 72 pt header while it slides up. Second,
MeloX's home has no search field: search is a tab, and the tab bar carries `role: .search`.

## Known traps found while extracting

- An audio's fields are not on the `messageAudio` object: TDLib nests them under `audio`, so
  `content.audio.album_cover_minithumbnail` and `content.caption.text` are different depths. Reading
  the content object for either reports "absent" for all 168 — which is exactly how a first pass of the
  real dump came to claim the captions were empty. They are not: all 168 carry four lines of bot text,
  and the minithumbnails are on 112.
- `Docs/design-tokens.md` numbers come from counting the dump, not from reasoning about what a music
  channel *would* send. Both thumbnail families, the 93 cut titles and the 89 repairs were surprises.
- `UIColor(rgb:)` takes a `UInt32` literal, alpha-less; `UIColor(rgb: 0xf2f2f2, alpha: 0.9)` is a
  *blurred* background, so it must be composited over the blurred material, not flattened to an
  opaque colour, or the nav bar will read one shade too light.
- `opaqueBackgroundColor` is computed (`0xf7f7f7` mixed with white at 0.14 → `#f8f8f8`, since
  247·0.86 + 255·0.14 = 248), so the literal in the file is not the final colour. Re-derive mixed
  values instead of copying the input.
- `separatorColor` at 1 pt is a *hairline*: Telegram draws `1.0 / scale`, and a plain 1 pt line is
  visibly heavier on @3x.
- A photographed **pill's height is a trap for `vedges`**. The unread bubble first read 40 px = 13.3 pt,
  which is not any number in the source: the column was 10 px inside the pill's rounded right cap, where
  a circle of radius 8 pt is only 12.7 pt tall. Reading the fill's own top and bottom edges away from both
  the cap and the digits gives 1415 → 1463 px = **16 pt**, which is exactly `badgeDiameter =
  floor(14 × 20/17)`. Cross-check a measured radius against the source formula before writing it down.
- The same trap caught the bubble's **font**: its digits were first recorded as `semibold(11)`, but the
  ink measures 19–20 px (6.5 pt) and the source sets `badgeFont` to `semibold(floor(base × 12/17))` =
  `semibold(9)` (`ChatListItem.swift:2294`). Ink of 6.5 pt is what 9 pt digits look like.
