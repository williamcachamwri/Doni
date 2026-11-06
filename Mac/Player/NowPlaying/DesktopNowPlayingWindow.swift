import SwiftUI
import TelegramDesignSystem

/// The full-window player.
///
/// The geometry is the reference's own file (`DesktopNowPlayingLayout.swift`, copied byte for byte):
/// the player column is centred in the window's first half, the panel starts at the exact horizontal
/// midpoint, and the cover, its top inset and the transport width all grow on one `heightProgress`
/// curve that stops at 768 points and only keeps growing past it in genuinely large windows.
///
/// What the reference does with a drag between the two pages — an 832-line reverse-motion coordinator —
/// is not here yet. The two pages are reached by the buttons in the panel's header, and they crossfade.
struct DesktopNowPlayingWindow: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var player: Player
    @EnvironmentObject private var artwork: CoverArtwork
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isActive: Bool
    let isRenderingActive: Bool

    @State private var page: DesktopInspector = .lyrics

    /// Doni's own, and the one place the port disagrees with the reference: Apple Music puts the sung
    /// line exactly on the artwork's centre (`DesktopNowPlayingLayout.swift:38-55`), and in a window
    /// this wide that reads as sitting too high. The line is dropped this fraction of the column's
    /// height below the artwork — about 36 pt in a 600-pt window, 54 pt in a 900-pt one.
    private static let focusDrop: CGFloat = 0.06

    var body: some View {
        GeometryReader { proxy in
            let layout = DesktopNowPlayingLayout(viewport: proxy.size)

            content(in: proxy, layout: layout)
                .frame(width: proxy.size.width, height: proxy.size.height,
                       alignment: .topLeading)
                .clipped()
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: DesktopMainWindowMetrics.minimumContentWidth,
               minHeight: DesktopMainWindowMetrics.minimumContentHeight)
        // The dark appearance from their common root.
        .environment(\.colorScheme, .dark)
        // The hero asks for its own cover rather than borrowing the row's tier: the phone's Now Playing
        // does the same before it asks for the words (`UI/NowPlayingView.swift:57-59`), and a 300-point
        // surface drawn from a 96-pixel tile is the mushy-cover bug this app has already fixed twice.
        .task(id: player.current?.uniqueId) {
            guard let track = player.current else { return }
            await artwork.load(track: track, via: model.session.covers(),
                               side: MusicArtworkMetrics.heroSide)
        }
    }

    private func content(in proxy: GeometryProxy,
                         layout: DesktopNowPlayingLayout) -> some View {
        let panelWidth = max(proxy.size.width - layout.panelLeading - layout.trailing, 1)

        return ZStack(alignment: .topLeading) {
            DesktopNowPlayingColumn(layout: layout, tint: .white, isActive: isActive)
                .frame(width: layout.playerWidth, height: layout.contentHeight, alignment: .top)
                .offset(x: layout.leading, y: layout.chromeHeight)

            panel(width: panelWidth, layout: layout)
                .frame(width: panelWidth, height: layout.contentHeight, alignment: .top)
                .offset(x: layout.panelLeading, y: layout.chromeHeight)
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
    }

    /// The right half: the column, with the two page buttons floating at its bottom-right corner the way
    /// the reference puts them. No header — but the 40 points of room the reference leaves between the
    /// chrome and the words are here, because `hostedContentMinY` is `chromeHeight + lyricsTopPadding`
    /// and a column that starts at the chrome itself puts the sung line too high (`DesktopNowPlaying
    /// Layout.swift:8-10`, measured off Apple Music at 1239 × 600: the lyrics container begins at y=88).
    private func panel(width: CGFloat, layout: DesktopNowPlayingLayout) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                switch page {
                case .lyrics:
                    DesktopLyricsPane(isActive: isActive && isRenderingActive,
                                      compact: false,
                                      focusAnchorOffset: layout.lyricsFocusAnchorOffset
                                          + layout.lyricsViewportHeight * Self.focusDrop)
                case .queue:
                    DesktopQueuePane(presentation: .nowPlaying)
                }
            }
            .padding(.top, DesktopNowPlayingLayout.lyricsTopPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            HStack(spacing: 8) {
                pageButton(.lyrics, systemImage: "text.quote")
                pageButton(.queue, systemImage: "list.bullet")
            }
            .padding(.trailing, 18)
            .padding(.bottom, 14)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: page)
    }

    private func pageButton(_ destination: DesktopInspector, systemImage: String) -> some View {
        let isSelected = page == destination

        return Button {
            page = destination
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 28, height: 28)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .modifier(DesktopNowPlayingCircularGlass())
        .foregroundStyle(isSelected ? MusicTint.accent : Color.white)
        .help(LocalizedStringKey(destination.title))
        .accessibilityLabel(Text(localized(destination.title)))
    }
}
