#if os(iOS)
import SwiftUI

/// Renders the supplemental transliteration stream only. The primary lyric is
/// owned by `SynchronizedLyricText`, keeping its wrapping and animation tree
/// stable when pronunciation is shown or hidden.
public struct LyricRubyText: View {
    public let rows: [LyricRubyRow]
    public let romanizationFontSize: CGFloat
    public let fontWeight: LyricsFontWeight
    public let primaryColor: Color
    public let romanizationOpacity: Double
    public let staticRomanizationOpacity: Double
    public let alignment: SynchronizedLyricTextAlignment
    /// Extra height Apple reserves after each Core Text visual line. The
    /// parent owns the separate primary-to-transliteration spacing.
    public let lineHeightAdjustment: CGFloat
    public let playbackTime: TimeInterval
    public let rendererStyle: LyricGlowTextRenderer.Style
    public let appliesTimingEffects: Bool
    public let timingEffectsStrength: Double

    public var body: some View {
        VStack(
            alignment: alignment.horizontalAlignment,
            spacing: max(lineHeightAdjustment, 0)
        ) {
            ForEach(rows) { row in
                romanizationView(for: row)
                    .frame(
                        width: row.width,
                        alignment: .leading
                    )
                    .frame(
                        maxWidth: .infinity,
                        alignment: alignment.frameAlignment
                    )
            }
        }
        .accessibilityHidden(true)
    }

    private func romanizationView(
        for row: LyricRubyRow
    ) -> some View {
        row.romanizationText
            .font(
                .system(
                    size: romanizationFontSize,
                    weight: fontWeight.swiftUIWeight
                )
            )
            .foregroundStyle(
                primaryColor.opacity(
                    appliesTimingEffects && row.hasTimedContent
                        ? romanizationOpacity
                        : staticRomanizationOpacity
                )
            )
            .fixedSize()
            .textRenderer(
                LyricRomanizationTextRenderer(
                    playbackTime: playbackTime,
                    unplayedOpacity:
                        rendererStyle.unplayedOpacity,
                    focusOpacityEndpoints:
                        rendererStyle.focusOpacityEndpoints,
                    revealFeatherWidth:
                        rendererStyle
                            .lineProgressionGradientFeather,
                    lineFinishProgressAnimationDuration:
                        rendererStyle
                            .lineFinishProgressAnimationDuration,
                    trailingVisualOverflow:
                        row.romanizationTrailingVisualOverflow,
                    appliesTimingEffects:
                        appliesTimingEffects
                            && row.hasTimedContent,
                    timingEffectsStrength:
                        timingEffectsStrength
                )
            )
            .transaction { $0.animation = nil }
            .frame(
                width: row.width,
                alignment: .leading
            )
    }
}
#endif
