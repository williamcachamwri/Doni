import SwiftUI
import TelegramDesignSystem

/// Every number the reference's bar is built from (`DesktopBottomPlayerMetrics.swift:3-12`), kept as
/// the measurements they are: 700 × 54, a 148-point transport cluster, and 70 points of reserved
/// content height — 100 when the bar has grown a problem line above the player.
enum DesktopBottomPlayerMetrics {
    static let outerWidth: CGFloat = 700
    static let outerHeight: CGFloat = 54
    static let horizontalInset: CGFloat = 9
    static let transportWidth: CGFloat = 148
    static let clusterSpacing: CGFloat = 9
    static let trailingControlSpacing: CGFloat = 1
    static let regularGlobalInsetHeight: CGFloat = 70
    static let issueGlobalInsetHeight: CGFloat = 100
    /// The bar's own corner: `.glassEffect(.regular, in: .rect(cornerRadius: 27))` on a 54-point-high
    /// surface, so the two ends are semicircles (`DesktopBottomPlayer.swift:66`).
    static let cornerRadius: CGFloat = 27
}

/// The motion bank the bar plays from (`DesktopPlayerMotion.swift`), with the springs the reference
/// measured off Apple Music 1.6.6.
enum DesktopPlayerMotion {
    /// How long the full-window player's content waits after the layer starts mounting before it is
    /// asked to render: the page has to be on screen before anything is worth drawing into it.
    static let nowPlayingContentDelay: Duration = .milliseconds(300)
    static let playbackSymbolSpeed = 2.0
    static let artworkHover = Animation.spring(duration: 0.26, bounce: 0.12)
    static let artworkRest = Animation.smooth(duration: 0.18)
    static let progressExpand = Animation.smooth(duration: 0.13)
    static let progressCollapse = Animation.smooth(duration: 0.17)
    static let progressPress = Animation.spring(duration: 0.20, bounce: 0.12)
    /// Music uses one 0.25-second animation for both directions of the volume area.
    static let volumeExpand = Animation.easeInOut(duration: 0.25)
    static let volumeCollapse = Animation.easeInOut(duration: 0.25)
    static let nowPlayingPresentation = Animation.spring(duration: 0.30, bounce: 0.02)

    static func progress(expanded: Bool) -> Animation {
        expanded ? progressExpand : progressCollapse
    }

    static func volume(expanded: Bool) -> Animation {
        expanded ? volumeExpand : volumeCollapse
    }
}

/// The bar, mounted once — in the selected tab's content space, so a hidden tab does not keep a second
/// player tree alive (`DesktopBottomPlayer.swift:6-29`).
struct DesktopTabBottomPlayer: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var player: Player

    var body: some View {
        if player.current != nil {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                DesktopBottomPlayer()
                    .frame(width: DesktopBottomPlayerMetrics.outerWidth)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, 24)
            .padding(.trailing, 24 + reservedTrailingWidth)
            .padding(.bottom, 10)
        }
    }

    /// The bar shrinks away from the inspector rather than under it, the way the reference reserves the
    /// panel's 258 points out of the bar's own trailing inset.
    private var reservedTrailingWidth: CGFloat {
        model.ui.inspector == nil
            ? 0
            : DesktopMainWindowMetrics.playerSidePanelWidth
    }
}

/// Reserves the rows' bottom space for the one bar the shell draws, so the last row of a list is never
/// behind it (`DesktopBottomPlayer.swift:32-48`).
///
/// The three views of the bar read the player through `@EnvironmentObject` rather than through the
/// model: `Player` is an `ObservableObject`, so a published change invalidates the views that hold it,
/// and a view that only reached it as `model.player` would keep drawing the state of the moment it was
/// built — a bar that never appears when a song starts.
struct DesktopTabBottomPlayerInset: View {
    @EnvironmentObject private var player: Player

    var body: some View {
        if player.current != nil {
            Color.clear
                .frame(height: player.playbackProblem == nil
                    ? DesktopBottomPlayerMetrics.regularGlobalInsetHeight
                    : DesktopBottomPlayerMetrics.issueGlobalInsetHeight)
                .accessibilityHidden(true)
        }
    }
}

/// The floating glass bar.
///
/// The surface is the system's, not a material chosen to look like it: on macOS 26 the whole cluster is
/// one `GlassEffectContainer` with `.glassEffect(.regular, in: .rect(cornerRadius: 27))` over it, which
/// is what makes the bar refract the list scrolling behind it and the buttons inside it share one piece
/// of glass. Under 26 there is no such thing, so the fallback is the closest drawable — a regular
/// material with a 0.65 pt white edge at 0.42, which is what the reference draws
/// (`DesktopBottomPlayer.swift:70-78`).
struct DesktopBottomPlayer: View {
    @Environment(DesktopAppModel.self) private var model
    @EnvironmentObject private var player: Player
    @State private var isVolumeExpanded = false

    var body: some View {
        surfacedPlayer
            .shadow(color: .black.opacity(0.10), radius: 14, y: 7)
    }

    @ViewBuilder private var surfacedPlayer: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                playerContent.glassEffect(
                    .regular,
                    in: .rect(cornerRadius: DesktopBottomPlayerMetrics.cornerRadius)
                )
            }
        } else {
            playerContent
                .background(
                    .regularMaterial,
                    in: .rect(cornerRadius: DesktopBottomPlayerMetrics.cornerRadius,
                             style: .continuous)
                )
                .overlay {
                    RoundedRectangle(
                        cornerRadius: DesktopBottomPlayerMetrics.cornerRadius,
                        style: .continuous
                    )
                    .stroke(.white.opacity(0.42), lineWidth: 0.65)
                }
        }
    }

    private var playerContent: some View {
        VStack(spacing: 0) {
            if let problem = player.playbackProblem {
                HStack(spacing: 8) {
                    Label(localized(problem.message), systemImage: problem.symbol)
                        .font(.caption)
                    Spacer()
                    Button("Thử lại") { player.retry() }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
            }

            HStack(spacing: 0) {
                DesktopPlaybackControls()
                    .frame(width: DesktopBottomPlayerMetrics.transportWidth)

                Color.clear.frame(width: DesktopBottomPlayerMetrics.clusterSpacing)

                if let track = player.current {
                    DesktopBottomMetadataSlot(track: track)
                        .frame(maxWidth: .infinity)
                }

                Color.clear.frame(width: DesktopBottomPlayerMetrics.clusterSpacing)

                // The two doors into the panel, and they fold away the moment the volume opens — the
                // reference gives the capsule the space they were using (`DesktopBottomPlayer.swift:118-140`).
                if !isVolumeExpanded {
                    inspectorButton(.lyrics, systemImage: "text.quote",
                                    title: localized("Lời bài hát"))

                    Color.clear.frame(width: DesktopBottomPlayerMetrics.trailingControlSpacing)

                    inspectorButton(.queue, systemImage: "list.bullet",
                                    title: localized("Hàng đợi"))

                    Color.clear.frame(width: DesktopBottomPlayerMetrics.trailingControlSpacing)
                }

                DesktopVolumeControl(isExpanded: $isVolumeExpanded)
            }
            .padding(.horizontal, DesktopBottomPlayerMetrics.horizontalInset)
            .frame(
                width: DesktopBottomPlayerMetrics.outerWidth,
                height: DesktopBottomPlayerMetrics.outerHeight
            )
        }
    }

    /// A panel button that is only a button when it is not the panel on screen: the reference draws the
    /// selected one in the app's red and leaves the other in the text's own colour.
    private func inspectorButton(_ destination: DesktopInspector, systemImage: String,
                                 title: String) -> some View {
        let isSelected = model.ui.inspector == destination

        return Button {
            model.ui.toggleInspector(destination)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isSelected ? MusicTint.accent : Color.primary)
                .frame(width: 36, height: 36)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(Text(title))
        .accessibilityValue(isSelected ? localized("Đang chọn") : localized("Chưa chọn"))
    }
}
