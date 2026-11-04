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

/// The colours a screen wears when it opens on top of a cover, read off that cover.
/// `ArtworkAccentColorProvider.swift`.
public enum MusicArtworkPalette {
    /// `maximumDimension > 160` … `scale = 160 / maximumDimension` (`:175-185`) — the picture is
    /// shrunk to this before anything is read from it, so both the average and the blur work on a
    /// thumbnail rather than the whole file.
    public static let sourceMaxSide: CGFloat = 160
    /// `filter.radius = 18` on the Gaussian that softens the backdrop (`:191-196`).
    public static let blurRadius: CGFloat = 18
    /// `countLimit = 80`, `totalCostLimit = 12 * 1_024 * 1_024`, cost `width * height * 4`
    /// (`:48-66`).
    public static let cacheCount: Int = 80
    public static let cacheBytes: Int = 12 * 1_024 * 1_024

    /// `luminance < 0.52` decides whether the whole interface goes light or dark (`:276-277`).
    public static let darkLuminanceThreshold: Double = 0.52
    /// The background: `source * 0.38 + 0.055 * 0.62` dark, `source * 0.30 + 0.94 * 0.70` light
    /// (`:280-284`).
    public static let darkMix: Double = 0.38
    public static let darkLift: Double = 0.055
    public static let lightMix: Double = 0.30
    public static let lightLift: Double = 0.94
    /// `SIMD3(repeating: prefersDarkAppearance ? 0.16 : 0.88)` when there is nothing to read
    /// (`:10-18`).
    public static let fallbackDark: Double = 0.16
    public static let fallbackLight: Double = 0.88
    /// `x * 0.2126 + y * 0.7152 + z * 0.0722` (`:323-325`).
    public static let luminanceRed: Double = 0.2126
    public static let luminanceGreen: Double = 0.7152
    public static let luminanceBlue: Double = 0.0722

    /// The cover, blurred, over the background at `opacity(0.22)`
    /// (`PlaylistDetailContent.swift:463-472`).
    public static let backdropOpacity: Double = 0.22
    /// The wash that keeps the text legible over it — black `0.08 / 0.24 / 0.40` in the dark
    /// palette, white `0.06 / 0.16 / 0.30` in the light one (`:476-486`).
    public static let darkWash: [Double] = [0.08, 0.24, 0.40]
    public static let lightWash: [Double] = [0.06, 0.16, 0.30]
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

/// The Home tab's second segment, which is the reference's discover screen embedded under the
/// picker rather than standing on its own (`ExploreView.swift`, `ExplorePlaylistComponents.swift`).
public enum MusicExploreMetrics {
    /// `LazyVStack(alignment: .leading, spacing: 26)` — chips to content (`ExploreView.swift:45`).
    public static let sectionSpacing: CGFloat = 26
    /// `.padding(.horizontal)` and `.padding(.bottom, 28)` on that stack (`:54-55`).
    public static let gutter: CGFloat = 16
    public static let bottom: CGFloat = 28
    /// `LazyHStack(spacing: 8)` of `.borderedProminent` capsule chips, `.small`, the selected one in
    /// the accent and the rest on `Color.secondary.opacity(0.14)`
    /// (`ExplorePlaylistComponents.swift:10-19`).
    public static let chipGap: CGFloat = 8
    public static let chipIdleInk: Double = 0.14
    /// The hero: artwork at `aspectRatio: 1.55` and `cornerRadius: 22` under a gradient that runs
    /// clear to `black.opacity(0.78)`, its copy padded 20 with 6 pt between the lines
    /// (`:44-81`, `ArtworkImage.swift` through `:45-49`).
    public static let heroAspect: CGFloat = 1.55
    public static let heroRadius: CGFloat = 22
    public static let heroScrim: Double = 0.78
    public static let heroPadding: CGFloat = 20
    public static let heroTextGap: CGFloat = 6
    public static let heroBadgeInk: Double = 0.78
    public static let heroMetaInk: Double = 0.76
    public static let heroMetaGap: CGFloat = 8
    /// `GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 16)` and the 22 pt between its rows
    /// (`ExploreView.swift:21-23`, `:102`).
    public static let columnMin: CGFloat = 148
    public static let columnMax: CGFloat = 220
    public static let columnSpacing: CGFloat = 16
    public static let rowSpacing: CGFloat = 22
    /// The heading over the grid: `.title2.bold()` and a `.caption` secondary count on the baseline,
    /// 16 pt above the grid (`:90-100`).
    public static let headingGap: CGFloat = 16
    /// A grid card: artwork at `cornerRadius: 12`, 8 pt to two lines of words
    /// (`ExplorePlaylistComponents.swift:103-125`).
    public static let cardRadius: CGFloat = 12
    public static let cardTextGap: CGFloat = 8
    /// The play-count pill: `.caption2.weight(.semibold)` white on `black.opacity(0.48)` in a
    /// capsule, 7 × 5 of padding, 8 pt from the artwork's corner (`:105-114`).
    public static let pillHorizontal: CGFloat = 7
    public static let pillVertical: CGFloat = 5
    public static let pillInk: Double = 0.48
    public static let pillMargin: CGFloat = 8
    /// The column's own width is only known once the grid has laid out, so a card asks the cache at
    /// 168 pt — the middle of the reference's `148…220` range minus what a 16 pt gutter and a second
    /// column take off a 402 pt screen — and draws it into whatever width the column turned out to
    /// be. 168 pt is 504 px, which is the 512 tier rather than the 768 one, and a grid of sixty of
    /// them is the difference between a feed that fits in the cache and one that pushes its own rows
    /// out of it.
    public static let cardAsk: CGFloat = 168
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
    /// The hero's side is `min(container × 0.68, 300)` — the factor and the cap both stated by
    /// `PlaylistDetailContent.swift:191-193`.
    public static let heroWidthFactor: CGFloat = 0.68
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

    /// The detail's scroll clearance. The reference ends its list 32 below the content
    /// (`PlaylistDetailContent.swift:88`), which is enough inside its own tab but not on a pushed
    /// Doni screen: the floating bar does not inset a pushed scroll view, so the last row lands
    /// under it. Doni adds the 88 the reference reserves under its settings list for that same bar
    /// (`SettingsView.swift:27-32`, `MusicSettingsMetrics.contentBottom`).
    public static let detailBottom: CGFloat = 32 + 88

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

    /// The detail's own row, which is not the library's: an index number where a playlist has no
    /// artwork, the name alone, and an ellipsis menu. `PlaylistTrackList.swift:86-284`.
    public static let listRowOuterGap: CGFloat = 4
    /// `HStack(spacing: 12)` inside that row's button (`:89`).
    public static let listRowGap: CGFloat = 12
    public static let listRowTextGap: CGFloat = 3
    /// The current row's own mark: a 32 pt circle stroked 1.5 pt at `primary` 0.60, in the same
    /// 40 pt column the number sits in (`:256-270`).
    public static let listIndexColumn: CGFloat = 40
    public static let listMarkCircle: CGFloat = 32
    public static let listMarkStroke: CGFloat = 1.5
    public static let listMarkInk: Double = 0.60
    /// The menu's hit box, 42 × 44 around a `.body.weight(.semibold)` ellipsis (`:222-225`).
    public static let listMenuWidth: CGFloat = 42
    public static let listMenuHeight: CGFloat = 44
    /// The rule between rows: `primary` at 0.12, inset 66 pt from the leading edge where the number
    /// column ends and 20 from the trailing (`:31-39`).
    public static let listDividerInset: CGFloat = 66
    public static let listDividerTrailing: CGFloat = 20
    public static let listDividerInk: Double = 0.12
    /// A row's own background — the accent at 0.16 when something has just been located in the list,
    /// `primary` at 0.10 while the player is holding it (`:233-236`).
    public static let listRowHighlight: Double = 0.16
    public static let listRowCurrent: Double = 0.10
}

/// The search tab: the discovery screen an empty field wears and the rows a filled one does.
/// `SearchDiscoveryView.swift`, `SearchView.swift` and the row it borrows,
/// `Shared/Media/TrackRowView.swift:17-58`.
public enum MusicSearchMetrics {
    /// The discovery stack breaks 28 between its sections and takes 8 vertically (`:18`, `:36`).
    public static let sectionSpacing: CGFloat = 28
    public static let verticalPadding: CGFloat = 8
    /// A heading is `.title2.bold()` with 14 down to its content (`:21-23`, `:59-61`).
    public static let headingToContent: CGFloat = 14
    /// The shelf under a heading: 172 pt cards, 14 apart, 16 inside the scroll edges, no indicators
    /// (`:64-82`).
    public static let shelfCard: CGFloat = 172
    public static let shelfGap: CGFloat = 14
    public static let shelfMargin: CGFloat = 16
    /// The tile grid is two flexible columns 12 apart inside the default horizontal padding
    /// (`:11-14`, `:25-34`).
    public static let gridColumns: Int = 2
    public static let gridSpacing: CGFloat = 12
    /// A tile: 1.55 aspect, r14, 14 of padding, a 60 pt bold watermark at white 0.22 turned −8°, and
    /// a `.title3.bold()` label that may shrink to 0.75 (`:120-145`).
    public static let tileAspect: CGFloat = 1.55
    public static let tileRadius: CGFloat = 14
    public static let tilePadding: CGFloat = 14
    public static let tileGlyph: CGFloat = 60
    public static let tileGlyphInk: Double = 0.22
    public static let tileGlyphRotation: Double = -8
    public static let tileLabelMinScale: CGFloat = 0.75
    /// The song row is the shared track row with artwork on: art 44 r6, 12 to the text, 3 between the
    /// two lines, at least 8 before the duration, which is `.caption.monospacedDigit()` (`:17-58`).
    public static let songArt: CGFloat = 44
    public static let songArtRadius: CGFloat = 6
    public static let songGap: CGFloat = 12
    public static let songTextGap: CGFloat = 3
    public static let songTrailingGap: CGFloat = 8
    /// A media row — artist or playlist: art 54 at r7, or a circle for an artist, 12 to the text and
    /// 4 between its lines (`SearchView.swift:386-408`).
    public static let mediaArt: CGFloat = 54
    public static let mediaArtRadius: CGFloat = 7
    public static let mediaGap: CGFloat = 12
    public static let mediaTextGap: CGFloat = 4
    /// The swipe-to-favourite action wears the reference's pink (`SearchView.swift:165`).
    public static let favoriteInk: Color = .pink
}

/// The up-next page inside the player. `NowPlayingQueuePage.swift`.
public enum MusicQueueMetrics {
    /// `Text(…).font(.title2.bold())` for the "Next up" heading (`:53`).
    public static let headingFont = Font.title2.bold()
    /// The mode pills: `.frame(height: 44)` inside `.rect(cornerRadius: 22)`
    /// (`:289`, `:297`).
    public static let pillHeight: CGFloat = 44
    public static let pillRadius: CGFloat = 22
    /// A queued row: 48 pt cover at radius 6 (`:343`).
    public static let rowArt: CGFloat = 48
    public static let rowArtRadius: CGFloat = 6

    /// `HStack(spacing: 14)` of pills in a row `.frame(height: 60)` with `.padding(.vertical, 8)`
    /// (`:225-232`, `:100-107`).
    public static let pillGap: CGFloat = 14
    public static let pillRowHeight: CGFloat = 60
    public static let pillRowPadding: CGFloat = 8
    /// `.font(.title3.weight(.semibold))` on white 0.12, and black 0.62 ink on white 0.7 when the
    /// mode is on (`:283-299`).
    public static let pillGlyph = Font.title3.weight(.semibold)
    public static let pillIdleFill: Double = 0.12
    public static let pillIdleInk: Double = 0.86
    public static let pillOnFill: Double = 0.7
    public static let pillOnInk: Double = 0.62
    /// A mode change animates on `.smooth(duration: 0.34)` (`:307-325`).
    public static let pillToggle = Animation.smooth(duration: 0.34)

    /// The heading's own 14 above and 10 below (`:52-58`).
    public static let headingTop: CGFloat = 14
    public static let headingBottom: CGFloat = 10

    /// A row: `HStack(spacing: 12)`, the name in `.body` over the artist in `.subheadline` at
    /// white 0.58, 2 pt apart, with 4 pt of row inset above and below (`:331-378`).
    public static let rowGap: CGFloat = 12
    public static let rowTextGap: CGFloat = 2
    public static let rowArtistOpacity: Double = 0.58
    public static let rowInset: CGFloat = 4
    /// A drag that lands a row somewhere else animates at `.smooth(duration: 0.28)` (`:212-222`).
    public static let reorder = Animation.smooth(duration: 0.28)

    /// The blank row that reserves the pinned header's space is the header plus 60 — the pills' own
    /// band — so pinning the overlay never resizes the list (`:44-49`).
    public static let headerReserveExtra: CGFloat = 60
    /// An empty queue's placeholder gets 24 pt of row inset top and bottom (`:67-74`).
    public static let emptyRowInset: CGFloat = 24
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

    /// The navigation bar's mark: a 28 pt image clipped at 7, 8 pt from a `.headline`
    /// (`SettingsHomeComponents.swift:5-14`).
    public static let logoSide: CGFloat = 28
    public static let logoRadius: CGFloat = 7
    public static let logoGap: CGFloat = 8

    /// The account card: `HStack(spacing: 16)` with a 60 pt avatar on `.quaternary` in a circle,
    /// 5 pt between a `.title3.weight(.semibold)` name held to one line and a `.subheadline`
    /// `.secondary` held to two (`SettingsAccountSection.swift:64-76`, `:114-115`, `:213-214`),
    /// inside 18 × 16 of padding on a 100 pt minimum height at radius 28 (`:142-151`).
    public static let accountGap: CGFloat = 16
    public static let accountAvatar: CGFloat = 60
    public static let accountTextGap: CGFloat = 5
    public static let accountPaddingH: CGFloat = 18
    public static let accountPaddingV: CGFloat = 16
    public static let accountMinHeight: CGFloat = 100
    public static let accountRadius: CGFloat = 28

    /// The sign-out card is the account section's own, which — unlike the reset card — has no
    /// header and no footnote: 14 between a 30 pt glyph and a `.body.weight(.medium)` title,
    /// 18 × 14 of padding, 60 pt tall, and the whole label in `.red`
    /// (`SettingsAccountSection.swift:166-184`).
    public static let logoutPaddingV: CGFloat = 14
    public static let logoutMinHeight: CGFloat = 60
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

    /// The title line: `title3.weight(.semibold)` over a `title3` artist at 0.64 white, 2 pt apart
    /// (`NowPlayingArtworkPage.swift:130-153`). The row's own gaps are `titleGap` and `badgeGap`.
    public static let titleSpacing: CGFloat = 2
    public static let artistOpacity: Double = 0.64

    /// The pinned song header on the other two pages: 72 pt, artwork radius 12, entering from
    /// 40 pt below (`NowPlayingSongHeader.swift:43`, `:104`; `NowPlayingMotionSpec.swift:528`).
    public static let songHeaderHeight: CGFloat = 72
    public static let songHeaderArtRadius: CGFloat = 12
    public static let songHeaderTravel: CGFloat = 40
    /// The header's own row is `HStack(spacing: 12)` — tighter than the artwork page's title row
    /// because its art is 72 rather than the page's screen width (`NowPlayingSongHeader.swift:66`).
    public static let songHeaderGap: CGFloat = 12

    /// The backdrop MeloX blurs when it has no Metal field: the artwork scaled 1.35 under a 90 pt
    /// blur (`NowPlayingBackground.swift:127-128`, `AppSettings.swift:2007`).
    public static let backdropScale: CGFloat = 1.35
    public static let backdropBlur: CGFloat = 90
    /// The same style's own veil and legibility wash — black 0.10 over the whole screen, then a
    /// vertical gradient that darkens toward the controls (`NowPlayingBackground.swift:142-173`).
    public static let veilOpacity: Double = 0.10
    public static let legibilityStops: [Double] = [0.04, 0.12, 0.48]
    /// The wash a new song's artwork brings in: `timingCurve(0, 0, 0.3, 1, duration: 0.8)` carried by
    /// the image's own load transaction, with `.transition(.opacity)` and the view keyed by
    /// `.id(artworkURL)` so the old wash is removed and the new one inserted rather than swapped in
    /// place (`NowPlayingAppleMusicBackground.swift:128-153`). The id is the load-bearing half: a
    /// cross-fade needs an insertion, and a view that only changes its pixels has none.
    /// A background *style* change — a switch Doni does not offer — cross-fades at 0.55
    /// (`NowPlayingBackground.swift:58-63`), so it is not the number the wash needs.
    public static let washCrossFade = Animation.timingCurve(0, 0, 0.3, 1, duration: 0.8)

    /// The artwork page's own two spacers: 8 above the cover, 22 below it, and the title block
    /// pushed off the bottom by the 279 pt core (`NowPlayingArtworkPage.swift:60`, `:128`, `:155`).
    public static let artworkTopSpacer: CGFloat = 8
    public static let artworkBottomSpacer: CGFloat = 22

    /// The title row is `HStack(spacing: 14)` with the name and its badges `HStack(spacing: 8)`
    /// apart (`NowPlayingArtworkPage.swift:130-140`).
    public static let titleGap: CGFloat = 14
    public static let badgeGap: CGFloat = 8

    /// The header's action discs: 40 pt circles, 10 apart, the ellipsis on white 0.15
    /// (`NowPlayingSongActions.swift:15`, `:215-221`).
    public static let actionDisc: CGFloat = 40
    public static let actionDiscGap: CGFloat = 10
    public static let menuDiscFill: Double = 0.15
    /// The star MeloX only shows outside the artwork page is the same disc on white 0.13 (`:46-58`).
    public static let starDiscFill: Double = 0.13

    /// The progress block's two lines are 2 apart, and its times are white 0.5
    /// (`NowPlayingControls.swift:10`, `:49-50`).
    public static let progressLabelGap: CGFloat = 2
    public static let progressLabelOpacity: Double = 0.5

    /// The volume row's two speaker glyphs: `caption2` at the quiet end, `caption` at the loud
    /// (`NowPlayingControls.swift:325-334`).
    public static let volumeGlyphLow = Font.caption2
    public static let volumeGlyphHigh = Font.caption

    /// The transport's glyphs are `.system(size:weight:)` at 34/48/34 `.medium` (`:224`, `:248`,
    /// `:286`) — a weight, not the semibold the rest of the app uses.
    public static func transportGlyph(_ size: CGFloat) -> Font {
        .system(size: size, weight: .medium)
    }
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
    /// The artwork page is the only one that travels: 300 pt, in from above and out again above
    /// (`:527`, `NowPlayingPageTransition.swift:38-53`). The queue and lyrics pages state a travel
    /// of 0 (`:525-526`), so their transition is the opacity half of the same modifier.
    public static let artworkTravel: CGFloat = -300
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

/// The motion a pushed music screen carries, which is a different set of numbers from the player's
/// own: the reference leaves the zoom transition entirely to the system and animates only what the
/// artwork tells it to.
public enum MusicScreenMotion {
    /// `Duration.milliseconds(350)` — how long a detail waits after the navigation transition has
    /// been handed over before it changes the colours it is wearing, so the palette never swaps
    /// under the zoom (`MusicNavigationTransitions.swift:4`, used by `PlaylistDetailView.swift:657-666`).
    public static let settle: Duration = .milliseconds(350)
    /// `.easeOut(duration: 0.18)` on the `withAnimation` that installs a new palette and backdrop
    /// (`PlaylistDetailView.swift:302-304`, `:211-214`).
    public static let paletteFade = Animation.easeOut(duration: 0.18)
    /// `.easeInOut(duration: 0.2)` around a `.transition(.opacity)` while a list loads or fails
    /// (`PlaylistDetailContent.swift:170-172`).
    public static let contentSwap = Animation.easeInOut(duration: 0.2)
    /// `.easeInOut(duration: 0.15)` on a row's own selection state (`PlaylistTrackList.swift:311`).
    public static let rowToggle = Animation.easeInOut(duration: 0.15)
}

/// The storage screen's numbers, all of them MeloX's own
/// (`StorageManagementView.swift:68-124`, `:329-352`, `:386-418`).
public enum MusicStorageMetrics {
    /// The overview's glyph sits in a 34 pt box, 12 from the two lines beside it, which are 2 apart
    /// and 6 pt from the top and bottom of the row (`:71-99`).
    public static let glyphBox: CGFloat = 34
    public static let rowGap: CGFloat = 12
    public static let textGap: CGFloat = 2
    public static let rowVertical: CGFloat = 6
    /// 14 pt between the managed-size block and the device capacity bar (`:70`).
    public static let overviewGap: CGFloat = 14
    /// The smallest room between an operation row's words and its byte count, where a spinner takes
    /// the number's place while the work runs (`:405`).
    public static let valueFloor: CGFloat = 8
}
