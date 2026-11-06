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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isActive: Bool
    let isRenderingActive: Bool

    @State private var page: DesktopInspector = .lyrics

    var body: some View {
        GeometryReader { proxy in
            let layout = DesktopNowPlayingLayout(viewport: proxy.size)

            ZStack(alignment: .topLeading) {
                content(in: proxy, layout: layout)

                chrome
                    .frame(width: proxy.size.width, height: proxy.size.height,
                           alignment: .topLeading)
                    .zIndex(100)
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: DesktopMainWindowMetrics.minimumContentWidth,
               minHeight: DesktopMainWindowMetrics.minimumContentHeight)
        // The backdrop is a sibling of the white content, so both inherit the player's dark appearance
        // from their common root (`DesktopRootView.swift:169-171`).
        .environment(\.colorScheme, .dark)
    }

    private func content(in proxy: GeometryProxy,
                         layout: DesktopNowPlayingLayout) -> some View {
        let panelWidth = max(proxy.size.width - layout.panelLeading - layout.trailing, 1)

        return ZStack(alignment: .topLeading) {
            DesktopNowPlayingColumn(layout: layout, tint: .white, isActive: isActive)
                .frame(width: layout.playerWidth, height: layout.contentHeight, alignment: .top)
                .offset(x: layout.leading, y: layout.chromeHeight)

            panel(width: panelWidth)
                .frame(width: panelWidth, height: layout.contentHeight, alignment: .top)
                .offset(x: layout.panelLeading, y: layout.chromeHeight)
        }
        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
    }

    private func panel(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                pageButton(.lyrics)
                pageButton(.queue)
                Spacer()
            }
            .padding(.top, DesktopNowPlayingLayout.lyricsTopPadding)
            .padding(.trailing, 32)

            Group {
                switch page {
                case .lyrics:
                    DesktopLyricsPane(isActive: isActive && isRenderingActive)
                case .queue:
                    DesktopQueuePane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: page)
    }

    private func pageButton(_ destination: DesktopInspector) -> some View {
        let isSelected = page == destination

        return Button {
            page = destination
        } label: {
            Text(LocalizedStringKey(destination.title))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
                .padding(.horizontal, 12)
                .frame(height: 30)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .background(isSelected ? Color.white.opacity(0.14) : Color.clear, in: .capsule)
    }

    /// The row that lives where the window's titlebar is: exit on the left, volume on the right. The
    /// reference installs these as real titlebar accessories when the window is not full-screen and
    /// draws them in content when it is (`DesktopRootView.swift:156-167`); drawing them in content is
    /// the half that works either way, and the accessory installer comes with the mini player.
    private var chrome: some View {
        HStack(alignment: .top) {
            DesktopNowPlayingWindowControls(
                close: { model.ui.isNowPlayingPresented = false },
                openMiniPlayer: nil
            )

            Spacer()

            DesktopNowPlayingVolumeControl()
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
    }
}
