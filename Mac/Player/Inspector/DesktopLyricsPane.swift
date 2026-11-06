import SwiftUI
import TelegramDesignSystem

/// The words in two forms, because the reference draws them in two forms.
///
/// `compact` is the 258-point inspector column: a plain list, the sung line at full strength, the rest
/// held back, tap to seek. The full-window player gets `AppleMusicLyricsView` — the column the phone
/// already uses, with its focus cascade, per-line glow and interlude dots — because that renderer sizes
/// its type from a viewport the width of a page, and in a 258-point column it lays itself out as though
/// it still had one.
///
/// The split is the reference's own: `DesktopPlaybackPositionedLyricsView(compact: true,
/// allowsLyricBlur: false)` for the panel and `compact: false` for the player
/// (`DesktopPlayerInspector.swift:11-18`, `DesktopRootView` of the player column).
struct DesktopLyricsPane: View {
    @EnvironmentObject private var lyrics: Lyrics
    @EnvironmentObject private var player: Player
    let isActive: Bool
    var compact = true
    /// The sung line's centre, from the top of the column — the artwork's centre in the full-window
    /// player, and nothing in the panel, where the reference's compact column centres on its own.
    var focusAnchorOffset: CGFloat? = nil

    var body: some View {
        Group {
            if compact {
                list
            } else {
                LyricsView(player: player, lyrics: lyrics, isActive: isActive,
                           focusAnchorOffset: focusAnchorOffset)
            }
        }
        .task(id: player.current?.uniqueId) {
            guard let track = player.current else { return }
            lyrics.load(track)
        }
    }

    private var list: some View {
        GeometryReader { box in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { row, line in
                            Text(line.text)
                                .font(.system(size: row == activeRow ? 17 : 15,
                                              weight: row == activeRow ? .semibold : .regular))
                                .foregroundStyle(row == activeRow
                                    ? Color.primary : Color.primary.opacity(0.45))
                                .fixedSize(horizontal: false, vertical: true)
                                .id(row)
                                .contentShape(.rect)
                                .onTapGesture { player.seek(to: line.time + timingOffset) }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 20)
                    .padding(.bottom, 120)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollContentBackground(.hidden)
                .overlay {
                    if lyrics.lines.isEmpty {
                        state
                    }
                }
                .onChange(of: activeRow) { _, row in
                    guard isActive, let row else { return }
                    withAnimation(.easeOut(duration: 0.24)) {
                        proxy.scrollTo(row, anchor: focusAnchor(viewportHeight: box.size.height))
                    }
                }
            }
        }
    }

    /// Where the reference's panel puts the sung line: `AppSettings.defaultLyricsFocusPosition` is
    /// `0.25` (`AppSettings.swift:76`), and `DesktopLyricsScrollView` scrolls the focused row to
    /// `viewportHeight * focusPosition` — a quarter of the column down, not the middle of it.
    ///
    /// `scrollTo(anchor:)` aligns the same unit point of the row and of the viewport, so the row's top
    /// lands at `a * (viewport - rowHeight)` and its centre a row-height lower. Solving that for the
    /// centre being at a quarter of the viewport is the expression below.
    private func focusAnchor(viewportHeight: CGFloat) -> UnitPoint {
        let rowHeight: CGFloat = 22
        guard viewportHeight > rowHeight else { return UnitPoint(x: 0.5, y: 0.25) }
        let fraction = (Self.focusPosition * viewportHeight - rowHeight / 2) / (viewportHeight - rowHeight)
        return UnitPoint(x: 0.5, y: min(max(fraction, 0), 1))
    }

    private static let focusPosition: CGFloat = 0.25

    /// The listener's own correction to the file's timings, which the phone's renderer honours too.
    private var timingOffset: TimeInterval { LyricsPreferences.shared.offset }

    /// The line being sung: the last one that starts at or before the clock.
    ///
    /// A lyric with no timings at all is a wall of text and gets treated as one — every line starts at
    /// zero, so the first would be "singing" forever and the list would never move.
    private var activeRow: Int? {
        guard lyrics.lines.contains(where: { $0.time > 0 }) else { return nil }
        let clock = player.elapsed + timingOffset
        var found: Int?
        for (row, line) in lyrics.lines.enumerated() where line.time <= clock {
            found = row
        }
        return found
    }

    @ViewBuilder private var state: some View {
        if lyrics.isLoading {
            ProgressView()
        } else if let failure = lyrics.errorMessage {
            Text(localized(failure))
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "text.quote")
                    .font(.system(size: 22))
                    .foregroundStyle(.tertiary)
                Text("Chưa có lời cho bài này.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }
}
