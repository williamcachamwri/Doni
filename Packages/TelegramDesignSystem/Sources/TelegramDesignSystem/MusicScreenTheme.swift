import SwiftUI

/// The music app's own numbers, transcribed from MeloX — the reference the user pointed at on
/// 2026-11-04. Every value cites the file and line that states it. Doni's floor is iOS 26, so the
/// APIs the reference leans on (`.tabViewBottomAccessory`, `matchedTransitionSource`,
/// `GlassEffectContainer`, `MeshGradient`) are the ones Doni uses too; where a value is marked
/// "Doni's own" it is a number the reference never states, not a workaround.
///
/// The Telegram-derived chrome the earlier milestones measured (`TelegramBarMetrics`,
/// `TelegramHeaderMetrics`, `TelegramLibraryMetrics`) keeps its own numbers; these govern the
/// music screens.

/// MeloX's global accent, `.tint(.red)` (`MeloXApp.swift:95`). Doni forces the dark scheme, so
/// the system red that resolves there is `#ff453a`.
public enum MusicTint {
    /// The `0xRRGGBB` the accent is built from, kept separate so its bytes are checkable without
    /// resolving a colour through an environment.
    public static let accentRGB: UInt32 = 0xff453a
    public static let accent = Color(rgb: accentRGB)
}

/// A cover as MeloX draws one: a 10 pt clip, a quarter-tint placeholder, and an image that fades
/// in rather than pops. `ArtworkImage.swift`.
public enum MusicArtworkMetrics {
    /// `var cornerRadius: CGFloat = 10` (`ArtworkImage.swift:7`) — the default every card uses.
    public static let radius: CGFloat = 10
    /// `Color.secondary.opacity(0.12)` under the placeholder and the spinner
    /// (`ArtworkImage.swift:60`, `:68`).
    public static let placeholderFill: Double = 0.12
    /// `Image(systemName: "music.note").font(.title2)` on that placeholder (`:69-70`).
    public static let placeholderGlyph = Font.title2
    /// `.easeOut(duration: 0.18)` on the transaction an image loads through (`:46`).
    public static let loadFade = Animation.easeOut(duration: 0.18)
    /// The widest a cover is drawn anywhere in the app: MeloX's playlist hero is
    /// `min(width × 0.68, 300)` (`PlaylistDetailContent.swift:191-193`) and the player's own cover
    /// is about as wide as the screen, which on an iPhone is the same number. Surfaces that hold
    /// only the artwork object — the player, the lock screen — ask for a cover at this width.
    public static let heroSide: CGFloat = 300
}

/// The home feed's vertical rhythm and the cards that fill it. `HomeRecommendedView.swift`,
/// `HomeRecommendationSections.swift`, `MediaCardView.swift`.
public enum MusicFeedMetrics {
    /// `LazyVStack(alignment: .leading, spacing: 32)` — the gap between feed sections
    /// (`HomeRecommendedView.swift:101`).
    public static let sectionSpacing: CGFloat = 32
    /// `.padding(.top, 8)` / `.padding(.bottom, 28)` on that stack (`:139-140`).
    public static let feedTop: CGFloat = 8
    public static let feedBottom: CGFloat = 28
    /// The strip's own gutter: `padding(.horizontal, 16)` on the header row and
    /// `contentMargins(.horizontal, 16, for: .scrollContent)` on the shelf
    /// (`HomeRecommendationSections.swift:102`, `:109`).
    public static let gutter: CGFloat = 16
    /// `VStack(alignment: .leading, spacing: 14)` — header to shelf (`:85`).
    public static let headerToShelf: CGFloat = 14
    /// `LazyHStack(alignment: .top, spacing: 14)` — card to card (`:105`).
    public static let shelfSpacing: CGFloat = 14
    /// `.frame(width: 166)` on a playlist card, artwork included (`:72-76`, `HomeComponents.swift:110-112`).
    public static let playlistCard: CGFloat = 166
    /// `.frame(width: 154)` on a song card (`HomeRecommendationSections.swift:123-125`).
    public static let songCard: CGFloat = 154
    /// `var artworkSize: CGFloat = 160` (`MediaCardView.swift:8`).
    public static let cardArtwork: CGFloat = 160
    /// `VStack(alignment: .leading, spacing: 8)` under a card's artwork (`MediaCardView.swift:11`).
    public static let cardTextGap: CGFloat = 8

    /// `MediaCardGridLayout`'s three inputs for a grid instead of a shelf: 16 pt of padding, a 145
    /// pt minimum column, 16 pt of spacing (`MediaCardGridLayout.swift:9-11`).
    public static let gridPadding: CGFloat = 16
    public static let gridMinimumItem: CGFloat = 145
    public static let gridSpacing: CGFloat = 16
}

/// The row of gradient tiles at the head of the feed. `HomeQuickActionsView.swift`,
/// `HomeComponents.swift`.
public enum MusicQuickActionMetrics {
    /// `@ScaledMetric(relativeTo: .body) compactCardWidth = 230.0` (`:101`) and
    /// `compactCardHeight = 132.0` (`HomeComponents.swift:11`).
    public static let compactWidth: CGFloat = 230
    public static let compactHeight: CGFloat = 132
    /// `min(length * 0.86, 340)` for the full-size tile (`HomeQuickActionsView.swift:135`).
    public static let standardWidthRatio: CGFloat = 0.86
    public static let standardWidthMax: CGFloat = 340
    /// `LazyHStack(spacing: 16)` and its `contentMargins(.horizontal, 16, …)` (`:108`, `:144`).
    public static let gap: CGFloat = 16
    /// `.clipShape(.rect(cornerRadius: 14))` on both tile shapes (`HomeComponents.swift:53`, `:93`).
    public static let radius: CGFloat = 14
    /// `.padding(14)` inside a compact tile (`:43`).
    public static let padding: CGFloat = 14
    /// `Spacer(minLength: 8)` between the glyph and the words (`:31`).
    public static let glyphToTitle: CGFloat = 8
    /// The compact tile's own `VStack(spacing: 4)` (`HomeComponents.swift:26`).
    public static let textSpacing: CGFloat = 4
    /// The watermark: `.system(size: 72, weight: .semibold)` at 0.24 white (`:79-81`).
    public static let watermarkGlyph: CGFloat = 72
    public static let watermarkOpacity: Double = 0.24
    /// The title laid over the gradient keeps 18 pt of tile edge (`:90`), and the gradient box is
    /// 1.48 wide to the inch with 8 pt under the copy (`:92-94`).
    public static let overlayTitlePadding: CGFloat = 18
    public static let overlayAspectRatio: CGFloat = 1.48
    public static let copyToTile: CGFloat = 8
    /// `LinearGradient(colors:from:.topLeading,to:.bottomTrailing)` on each pair below (`:47-52`).
    public static let gradientPairs: [(from: Color, to: Color)] = [
        (.pink, .red),
        (.orange, .red),
        (.pink, .purple),
        (.indigo, .purple),
        (.cyan, .blue),
        (.mint, .teal)
    ]
}

/// The strip of player that rides above the tab bar. `MiniPlayerView.swift`.
public enum MusicMiniPlayerMetrics {
    /// `artworkSize = 40` at rest, 30 when the accessory collapses inline (`:110-112`), and
    /// `cornerRadius: 6` on it (`:17`).
    public static let art: CGFloat = 40
    public static let artInline: CGFloat = 30
    public static let artRadius: CGFloat = 6
    /// `HStack(spacing: isInline ? 8 : 10)` (`:14`, `:16`) and the 1 pt between the two lines of
    /// text (`:24`).
    public static let spacing: CGFloat = 10
    public static let spacingInline: CGFloat = 8
    public static let textSpacing: CGFloat = 1
    /// Both bar buttons are `.frame(width: 36, height: 36).contentShape(.circle)` (`:47`, `:68`, `:85`).
    public static let button: CGFloat = 36
    /// `.padding(.horizontal, 12).padding(.vertical, 6)` around the row, and
    /// `isInline ? 8 : 12` / `isInline ? 3 : 6` on each of them (`:92-93`).
    public static let horizontalPadding: CGFloat = 12
    public static let verticalPadding: CGFloat = 6
    public static let horizontalPaddingInline: CGFloat = 8
    public static let verticalPaddingInline: CGFloat = 3
    /// `.font(.title3.weight(.semibold))` on both bar glyphs (`:53`, `:84`).
    public static let glyph = Font.title3.weight(.semibold)
    /// The row's own height — Doni's own, the number the kit's bar measured and MeloX leaves to
    /// its accessory container: artwork plus both vertical pads.
    public static var height: CGFloat { art + 2 * verticalPadding }
    /// `DragGesture(minimumDistance: 28)` for the horizontal next/previous flick (`:115`).
    public static let swipeDistance: CGFloat = 28
}

/// The playlist list, its hero, and the two sheets that hang off it.
public enum MusicPlaylistMetrics {
    /// `HStack(spacing: 12)` with a 54 pt cover at `cornerRadius: 7`
    /// (`LibraryPlaylistsView.swift:155-157`).
    public static let rowSpacing: CGFloat = 12
    public static let rowArt: CGFloat = 54
    public static let rowArtRadius: CGFloat = 7
    /// `VStack(alignment: .leading, spacing: 4)` for the name and the count (`:158`).
    public static let rowTextGap: CGFloat = 4

    /// The detail hero: artwork at `cornerRadius: 12` under a `black 0.18 / r18 / y10` shadow,
    /// then 24 pt to a centred `title2.bold()`, 8 pt to the `title3` subtitle, 7 pt to the
    /// `subheadline.weight(.medium)` count, 17 pt to the action row, 26 pt above and 22 below
    /// (`PlaylistDetailContent.swift:190-226`).
    public static let heroArtRadius: CGFloat = 12
    public static let heroShadowOpacity: Double = 0.18
    public static let heroShadowRadius: CGFloat = 18
    public static let heroShadowY: CGFloat = 10
    public static let heroTop: CGFloat = 26
    public static let heroArtToTitle: CGFloat = 24
    public static let heroTitleToSubtitle: CGFloat = 8
    public static let heroSubtitleToCount: CGFloat = 7
    public static let heroToActions: CGFloat = 17
    public static let heroBottom: CGFloat = 22
    public static let heroSidePadding: CGFloat = 24

    /// `GlassEffectContainer(spacing: 14)` around the action row, whose secondary buttons are a
    /// 30 pt glyph in a 30 pt box and whose play button is a `title3.bold()` (`:328-329`, `:343-344`, `:374`).
    public static let actionGap: CGFloat = 14
    public static let actionGlyph: CGFloat = 30

    /// The create-playlist sheet's own box on the sizes MeloX gives it
    /// (`PlaylistCreationSheet.swift:49`).
    public static let creationFieldWidth: CGFloat = 420

    /// Add-to-playlist rows: 52 pt cover at radius 7, 12 pt to the text, 3 pt between its lines
    /// (`AddToPlaylistSheet.swift:86-90`).
    public static let addArt: CGFloat = 52
    public static let addArtRadius: CGFloat = 7
    public static let addRowSpacing: CGFloat = 12
    public static let addTextGap: CGFloat = 3

    /// A track list row: 40 pt wide index column holding a 32 pt circle, 48 pt cover at radius 6,
    /// 12 pt between its parts, 20 pt of leading and 8 pt of trailing padding, 11 pt vertical
    /// without artwork and 8 with (`PlaylistTrackList.swift:89-101`, `:223-232`, `:254-269`).
    public static let trackRowGap: CGFloat = 12
    public static let trackIndexWidth: CGFloat = 40
    public static let trackIndexCircle: CGFloat = 32
    public static let trackArt: CGFloat = 48
    public static let trackArtRadius: CGFloat = 6
    public static let trackRowLeading: CGFloat = 20
    public static let trackRowTrailing: CGFloat = 8
    public static let trackRowVertical: CGFloat = 11
    public static let trackRowVerticalWithArt: CGFloat = 8
    public static let trackTextGap: CGFloat = 3
}

/// The up-next page inside the player. `NowPlayingQueuePage.swift`.
public enum MusicQueueMetrics {
    /// `Text(…).font(.title2.bold())` for the "Next up" heading (`:53`).
    public static let headingFont = Font.title2.bold()
    /// The four mode pills: `.frame(height: 44)` inside `.rect(cornerRadius: 22)`
    /// (`:289`, `:297`).
    public static let pillHeight: CGFloat = 44
    public static let pillRadius: CGFloat = 22
    /// A queued row: 48 pt cover at radius 6 (`:343`).
    public static let rowArt: CGFloat = 48
    public static let rowArtRadius: CGFloat = 6
}

/// The settings cards. `SettingsHomeComponents.swift`, `SettingsView.swift`.
public enum MusicSettingsMetrics {
    /// `VStack(spacing: 32)` down the screen and `.padding(.horizontal, 16)` around it, 14 above
    /// and 88 below (`SettingsView.swift:27-32`).
    public static let sectionSpacing: CGFloat = 32
    public static let sidePadding: CGFloat = 16
    public static let contentTop: CGFloat = 14
    public static let contentBottom: CGFloat = 88
    /// `VStack(alignment: .leading, spacing: 10)` under each card's header (`:23`).
    public static let headerToCard: CGFloat = 10
    /// The header is a `.headline` in `.secondary` with 14 pt of side padding (`:24-27`).
    public static let headerPadding: CGFloat = 14
    /// `Divider().padding(.leading, 58)` between rows (`:32-33`).
    public static let dividerLeading: CGFloat = 58
    /// `RoundedRectangle(cornerRadius: 26, style: .continuous)` filled with the grouped
    /// secondary background (`:39-50`).
    public static let cardRadius: CGFloat = 26
    /// `HStack(spacing: 14)` with a `title3.weight(.medium)` icon 30 pt wide (`:58-62`).
    public static let rowIconGap: CGFloat = 14
    public static let rowIconWidth: CGFloat = 30
    /// Title to subtitle, 3 pt (`:64`).
    public static let rowTextGap: CGFloat = 3
    /// `.padding(.horizontal, 18).padding(.vertical, 13)` inside a `minHeight: 68` row (`:85-87`).
    public static let rowPaddingH: CGFloat = 18
    public static let rowPaddingV: CGFloat = 13
    public static let rowMinHeight: CGFloat = 68
    /// The chevron is a `.caption.weight(.semibold)` in `.tertiary` (`:81-83`).
    public static let chevronFont = Font.caption.weight(.semibold)
}

/// The player's own portrait geometry. Every control sits inside a fixed 279 pt core plus a 62 pt
/// utility band, and the artwork is sized from what the remaining height leaves.
/// `NowPlayingView.swift`, `NowPlayingBottomControls.swift`, `NowPlayingControls.swift`,
/// `NowPlayingArtworkPage.swift`, `NowPlayingPortraitArtwork.swift`.
public enum MusicNowPlayingMetrics {
    /// `portraitHorizontalPadding: CGFloat = 32` (`NowPlayingView.swift:5`).
    public static let horizontal: CGFloat = 32

    /// The drag-down handle: a 60 × 5 capsule at 0.52 white, 8 pt inside a 34 pt box
    /// (`NowPlayingView.swift:465-473`).
    public static let gripWidth: CGFloat = 60
    public static let gripHeight: CGFloat = 5
    public static let gripOpacity: Double = 0.52
    public static let gripTop: CGFloat = 8
    public static let gripBox: CGFloat = 34

    /// Artwork: `min(pageWidth + 16, max(170, pageHeight − 279 − 92))`, radius 12, shrinking to
    /// 0.74 while paused (`NowPlayingArtworkPage.swift:4`, `:39-50`, `:66`).
    public static let artworkRadius: CGFloat = 12
    public static let artworkMin: CGFloat = 170
    public static let artworkSideLeeway: CGFloat = 16
    public static let artworkReserve: CGFloat = 92
    public static let pausedArtworkScale: CGFloat = 0.74
    /// `black 0.34 / r26 / y15` while playing, `0.18 / r14 / y8` while paused, none on any other
    /// page (`NowPlayingPortraitArtwork.swift:45-58`).
    public static let playingShadowOpacity: Double = 0.34
    public static let playingShadowRadius: CGFloat = 26
    public static let playingShadowY: CGFloat = 15
    public static let pausedShadowOpacity: Double = 0.18
    public static let pausedShadowRadius: CGFloat = 14
    public static let pausedShadowY: CGFloat = 8

    /// The bottom overlay: `utilityHeight 62 + coreHeight 279` (`NowPlayingBottomControls.swift:4-6`).
    public static let utilityHeight: CGFloat = 62
    public static let coreHeight: CGFloat = 279
    public static var overlayHeight: CGFloat { utilityHeight + coreHeight }
    /// And the gaps the core's four layers are separated by (`:36-59`).
    public static let progressToTransport: CGFloat = 19
    public static let transportToVolume: CGFloat = 31
    public static let volumeToSelector: CGFloat = 3

    /// Progress: a 52 pt block, thumb hidden, `.tint(.white)`, and `caption2.monospacedDigit()`
    /// times at 0.5 white (`NowPlayingControls.swift:11-19`, `:49-52`).
    public static let progressHeight: CGFloat = 52
    /// The quality chip that sits over those times: 9 × 4 padding, radius 7, 0.12 white, a 9 pt
    /// semibold waveform (`:99-105`, `:151-160`).
    public static let chipPaddingH: CGFloat = 9
    public static let chipPaddingV: CGFloat = 4
    public static let chipRadius: CGFloat = 7
    public static let chipFill: Double = 0.12
    public static let chipGlyph: CGFloat = 9

    /// Transport: `backward`/`play`/`forward` at 34/48/34 `.medium` in 64 pt circles, in an 82 pt
    /// row (`:197`, `:224`, `:248`, `:286`, `:313`).
    public static let transportCircle: CGFloat = 64
    public static let transportRowHeight: CGFloat = 82
    public static let transportSkipGlyph: CGFloat = 34
    public static let transportPlayGlyph: CGFloat = 48

    /// Volume: 42 pt row, 32 pt slider, 10 pt to each speaker glyph, 0.62 white (`:324-337`).
    public static let volumeHeight: CGFloat = 42
    public static let volumeSliderHeight: CGFloat = 32
    public static let volumeGlyphGap: CGFloat = 10
    public static let volumeOpacity: Double = 0.62

    /// Page selector: a 50 pt row inset 32, 44 pt circular buttons at `.title3` in 0.72 white, a
    /// selected button swapped to a 0.68 white disc with 0.68 black ink, and a 15 pt badge with a
    /// 7 pt glyph offset (3, 1) (`:451-453`, `:480-512`).
    public static let selectorHeight: CGFloat = 50
    public static let selectorButton: CGFloat = 44
    public static let selectorOpacity: Double = 0.72
    public static let selectorDiscFill: Double = 0.68
    public static let selectorDiscInk: Double = 0.68
    public static let badgeSize: CGFloat = 15
    public static let badgeGlyph: CGFloat = 7
    public static let badgeOffset: CGSize = CGSize(width: 3, height: 1)

    /// The title line: `title3.weight(.semibold)` over a `title3` artist at 0.64 white, 2 pt
    /// apart, 8 pt to the badges and 14 pt to the action group
    /// (`NowPlayingArtworkPage.swift:130-153`).
    public static let titleSpacing: CGFloat = 2
    public static let titleToBadges: CGFloat = 8
    public static let artistOpacity: Double = 0.64
    public static let titleToActions: CGFloat = 14

    /// The pinned song header on the other two pages: 72 pt, artwork radius 12, entering from
    /// 40 pt below (`NowPlayingSongHeader.swift:43`, `:104`; `NowPlayingMotionSpec.swift:528`).
    public static let songHeaderHeight: CGFloat = 72
    public static let songHeaderArtRadius: CGFloat = 12
    public static let songHeaderTravel: CGFloat = 40

    /// The backdrop MeloX blurs when it has no Metal field: the artwork scaled 1.35 under a 90 pt
    /// blur (`NowPlayingBackground.swift:127-128`, `AppSettings.swift:2007`).
    public static let backdropScale: CGFloat = 1.35
    public static let backdropBlur: CGFloat = 90
}

/// MeloX's motion, at the values `NowPlayingMotionSpec.appleMusic26` states. `.smooth` and
/// `.interpolatingSpring` are both iOS 17, so these port unchanged.
public enum MusicMotion {
    /// `Spring(mass: 1, stiffness: 350, damping: 40)` is overdamped — 40 against a critical
    /// 2√350 ≈ 37.4 — so it never crosses its target and settles when the slow root's term falls
    /// under the 0.001 epsilon: −ln(0.001/1.91421) ÷ 12.9289 ≈ 0.5845 s. `NowPlayingMotionSpec.swift:202-211`
    /// asks the OS for exactly this, through an `allowOverDamping:` initialiser iOS 17 does not
    /// have, so Doni carries the number instead of the call.
    public static let pageSpringSettling: TimeInterval = 0.5845

    /// `interpolatingSpring(mass: 1, stiffness: 350, damping: 40)` — the page's spatial curve
    /// (`:442-450`).
    public static let pageSpring = Animation.interpolatingSpring(mass: 1, stiffness: 350, damping: 40,
                                                                initialVelocity: 0)
    /// `timingCurve(0.42, 0, 0.58, 1)` — the opacity curve on every page cross-fade (`:451-459`).
    public static func fade(_ duration: TimeInterval, _ delay: TimeInterval = 0) -> Animation {
        var animation = Animation.timingCurve(0.42, 0, 0.58, 1, duration: duration)
        if delay > 0 { animation = animation.delay(delay) }
        return animation
    }

    /// Page selection 0.30, direct lyrics↔queue 0.44, outgoing 0.24, incoming 0.22 + 0.07
    /// (`:414-430`).
    public static let pageSelection = Animation.smooth(duration: 0.30)
    public static let pageDirectAlternate = Animation.smooth(duration: 0.44)
    public static let pageOutgoing = Animation.smooth(duration: 0.24)
    public static let pageIncoming = Animation.smooth(duration: 0.22).delay(0.07)
    /// The pinned song header comes in at 0.40 + 0.08, a delayed resident at 0.34 + 0.11, and a
    /// paused/playing artwork resize at 0.48 (`:431-440`, `:516-519`).
    public static let songHeaderIncoming = Animation.smooth(duration: 0.40).delay(0.08)
    public static let delayedResidentEntrance = Animation.smooth(duration: 0.34).delay(0.11)
    public static let artworkResize = Animation.smooth(duration: 0.48)
    /// `easeInOut(0.3)` on the shadow a play state changes (`NowPlayingPortraitArtwork.swift:31`).
    public static let artworkShadow = Animation.easeInOut(duration: 0.3)

    /// How far a page is pushed back while another comes forward: 0.92 for a direct alternate,
    /// 0.90 for the page being presented (`:520-522`).
    public static let alternateContentScale: CGFloat = 0.92
    public static let presentationScale: CGFloat = 0.90
    /// The settlement horizons the coordinator waits out (`:531-533`).
    public static let settleStandard: TimeInterval = 0.50
    public static let settleDirectAlternate: TimeInterval = 0.46
    public static let settleHiddenQueue: TimeInterval = 0.42

    /// Core and utility bands show and hide at 0.34 and 0.24, the utility hide delayed 0.10, and
    /// every layer inside the core moves on its own 0.24 with the stagger below (`:536-553`).
    public static let coreShow = Animation.smooth(duration: 0.34)
    public static let coreHide = Animation.smooth(duration: 0.34)
    public static let utilityShow = Animation.smooth(duration: 0.24)
    public static let utilityHide = Animation.smooth(duration: 0.24).delay(0.10)
    public static let utilityHiddenOffset: CGFloat = 64
    public static let utilityHiddenScale: CGFloat = 0.82

    /// The four core layers rise from these offsets, shown in this order at 25 ms apart and hidden
    /// in reverse (`:556-575`).
    public static let progressHiddenOffset: CGFloat = 180
    public static let transportHiddenOffset: CGFloat = 165
    public static let volumeHiddenOffset: CGFloat = 148
    public static let selectorHiddenOffset: CGFloat = 128
    public static let layerShowDelays: [TimeInterval] = [0.025, 0.05, 0.075, 0.10]
    public static let layerHideDelays: [TimeInterval] = [0.075, 0.05, 0.025, 0.0]

    /// A pressed transport button: the glyph to 0.8 on a 0.16 s ease-in-out, the 0.1 white disc
    /// expanding from 0.86 over 0.18 s, both released over 0.4 s
    /// (`NowPlayingTransportButtonStyle.swift:127-132`).
    public static let pressedIconScale: CGFloat = 0.8
    public static let pressedHighlightScale: CGFloat = 0.86
    public static let highlightOpacity: Double = 0.1
    public static let press = Animation.easeInOut(duration: 0.16)
    public static let release = Animation.easeInOut(duration: 0.4)
    public static let highlightExpansion = Animation.easeOut(duration: 0.18)

    /// The play/pause glyph swap: `.replace.downUp.wholeSymbol` at 1.6× speed inside a
    /// `.snappy(0.2)` (`MiniPlayerView.swift:54-67`).
    public static let symbolSwap = Animation.snappy(duration: 0.2, extraBounce: 0)

    /// The artwork bounce on the beat a play starts: to 1.055 over 0.17 s ease-out, held 170 ms,
    /// then home on a 0.42 s spring with 0.24 bounce (`NowPlayingPortraitArtwork.swift:67-79`).
    public static let bounceScale: CGFloat = 1.055
    public static let bounceRise = Animation.easeOut(duration: 0.17)
    public static let bounceHold: TimeInterval = 0.17
    public static let bounceSettle = Animation.spring(duration: 0.42, bounce: 0.24)

    /// The interface strip reappearing hides after five seconds of no touch
    /// (`AppSettings.swift:2013`, whose default the range 3…15 clamps).
    public static let autoHide: TimeInterval = 5.0
}
