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
| `album_cover_thumbnail` on the same 112 — 320×240 (57) or 320×180 (55) JPEG, as a `File`; `external_album_covers` on **168/168**, two entries each: 100×100 *and* 600×600 | hi-res art exists for every track and is a *fetch*, so it belongs to playback (M3) and Now Playing, not to a list that has to scroll at 120 Hz | `td_api.tl:583`, `:286` |
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
| `mediaActiveControl #0088ff` played / `mediaInactiveControl #cacaca` not | the bubble's two colours — the same pair Telegram puts on a media button | `DefaultDayPresentationTheme.swift:632-633` |
| title one line `.middle`, preview one line `.end` | a song's name matters at both ends, the way the audio row cuts it (`ChatMessageInteractiveFileNode.swift:751`), while a preview line is cut the way the chat list cuts its own (`ChatListItem.swift:3824`) | both cited |
| tabular digits in the duration column | `m:ss` and `h:mm:ss` line up down the column, as Telegram's bar title and its file sizes do | `ChatTitleView.swift:26`, `ChatMessageInteractiveFileNode.swift:579` |
| clear button scaled `0.2 → 1.0`, not faded | Telegram scales the pill's clear button when it appears and goes | `SearchBarNode.swift:1647` |

**Doni's own, not copied from a line.** Colouring the matched run inside a title: Telegram's chat list
*filters* rows for a query and never tints runs (`ChatListUI` has no such call), so the accent half of
`HighlightedText` is Doni's — but the colour it uses is Telegram's `accent #0088ff`
(`DefaultDayPresentationTheme.swift:56`). Also Doni's own: the "Thử lại" capsule, the spinner ring, `—`
where a duration is missing, and `performer · size` as the preview line. The two glyphs inside the
tiles (18 pt note, 9 pt play / download arrow) are measured off renders, because Telegram's equivalents
are native assets (`Media/Message Audio Play`), not point sizes in a file.



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
