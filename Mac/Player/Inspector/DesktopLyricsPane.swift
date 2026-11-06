import DoniLyrics
import SwiftUI
import TelegramDesignSystem

/// The words, in the panel's compact form: one line per row, the line being sung at full strength and
/// the rest held back, the list keeping the current line in view on its own, and a tap moving the song
/// to wherever the finger landed.
///
/// This is not the reference's full-screen lyric renderer — that is a 2,700-line scroll view with
/// per-syllable timing, blur and depth, and it comes with the player corpus. What is taken here is its
/// inspector behaviour: `DesktopPlaybackPositionedLyricsView(compact: true, allowsLyricBlur: false)`,
/// which is the same list without the effects a 258-point column could not show anyway.
struct DesktopLyricsPane: View {
    @EnvironmentObject private var lyrics: Lyrics
    @EnvironmentObject private var player: Player
    let isActive: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { row, line in
                        DesktopLyricRow(line: line, isSinging: row == activeRow)
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
                    proxy.scrollTo(row, anchor: .center)
                }
            }
        }
        .task(id: player.current?.uniqueId) {
            guard let track = player.current else { return }
            lyrics.load(track)
        }
    }

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

/// One line. Its own view because the two states differ in three modifiers, and a SwiftUI expression
/// that picks them inline stops type-checking inside a `ForEach`.
struct DesktopLyricRow: View {
    let line: LyricLine
    let isSinging: Bool

    var body: some View {
        Text(line.text)
            .font(.system(size: isSinging ? 17 : 15, weight: isSinging ? .semibold : .regular))
            .foregroundStyle(isSinging ? Color.primary : Color.primary.opacity(0.45))
            .fixedSize(horizontal: false, vertical: true)
    }
}
