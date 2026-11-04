import SwiftUI
import Support
import TelegramDesignSystem

/// The words of the song, sung along with.
///
/// MeloX's skyline column, and Apple Music's before it: the line being sung is the biggest and the
/// only sharp thing on screen, the lines it has passed keep their size and lose their focus, and
/// the whole column is held about a third of the way down so the line being sung sits where the
/// eye already is. Nothing is a list row — there are no separators, no chevrons and no cells, and
/// the column is allowed to run past both edges of the screen because a song's words are not a
/// table.
struct LyricsView: View {
    @ObservedObject var lyrics: Lyrics
    @ObservedObject var prefs: LyricsPreferences
    /// Where the song goes when a line is tapped.
    let seek: (TimeInterval) -> Void
    let close: () -> Void

    /// While the finger is on the column the song keeps playing, but the column does not move under
    /// it — the two would fight, and the scroll always loses.
    @State private var dragging = false

    private var lines: [LyricLine] { lyrics.text.lines }

    /// Numbered the way the scroll needs them numbered: the position is the id the column scrolls
    /// to, and it is also what says which line is being sung.
    private var rows: [(index: Int, line: LyricLine)] {
        lines.enumerated().map { ($0.offset, $0.element) }
    }

    var body: some View {
        ZStack(alignment: .top) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Button(action: close) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 32, height: 32)
                        .background(.ultraThinMaterial, in: .circle)
                }
                .accessibilityLabel("Đóng lời bài hát")
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var content: some View {
        switch lyrics.text {
        case .synced:
            column
        case .plain(let words):
            block(words)
        case .none:
            missing
        }
    }

    // MARK: The column

    /// Broken into three functions on purpose: a `ScrollView` carrying two closures that each bind
    /// a proxy and an optional is more than the type checker will solve in one expression.
    private var column: some View {
        GeometryReader { edge in
            ScrollViewReader { scroll in
                scroller(scroll, edge.size.height)
            }
        }
    }

    private func scroller(_ scroll: ScrollViewProxy, _ height: CGFloat) -> some View {
        ScrollView { columnBody(height) }
            .scrollIndicators(.hidden)
            .onScrollPhaseChange(observeDrag)
            .onChange(of: lyrics.index) { _, active in follow(scroll, active) }
    }

    /// The finger, the tracking it drives, and the deceleration after it. Not `.animating`, which is
    /// what this view's own scroll produces — counting it would switch auto-following off every time
    /// auto-following worked.
    private func observeDrag(_ previous: ScrollPhase, _ phase: ScrollPhase) {
        // Everything the user is doing to the column, and neither of the two states that are not:
        // idle, and `.animating`, which is what this view's own scroll produces — counting that
        // would switch auto-following off every time auto-following worked.
        dragging = phase != .idle && phase != .animating
    }

    private func follow(_ scroll: ScrollViewProxy, _ active: Int?) {
        guard prefs.autoFollow, !dragging, let active else { return }
        withAnimation(.easeOut(duration: MusicLyricsMetrics.timeFade)) {
            scroll.scrollTo(active, anchor: .center)
        }
    }

    /// The lines themselves. Its own function because the alignment is a conditional and a
    /// conditional inside a `VStack(alignment:)` inside a `ScrollView` inside a `GeometryReader` is
    /// more than the type checker will agree to solve in one breath.
    ///
    /// The focus band is made of padding rather than of an offset, so the first line can be scrolled
    /// up to it and the last one down to it, and neither is stuck.
    private func columnBody(_ height: CGFloat) -> some View {
        let alignment: HorizontalAlignment = prefs.centred ? .center : .leading
        return VStack(alignment: alignment, spacing: MusicLyricsMetrics.lineSpacing) {
            ForEach(rows, id: \.index) { row in
                lineView(row.line, active: row.index == lyrics.index)
                    .id(row.index)
                    .onTapGesture { tap(row.line) }
            }
        }
        .padding(.horizontal, MusicLyricsMetrics.sidePadding)
        .padding(.top, height * MusicLyricsMetrics.focusAnchor)
        .padding(.bottom, height * MusicLyricsMetrics.tailFraction)
    }

    private func tap(_ line: LyricLine) {
        guard prefs.tapToSeek else { return }
        // The stamp as the file wrote it, not as the screen shifted it: the offset is a correction
        // to what is *shown*, and a tap should land where the words actually are.
        seek(line.start)
    }

    private func lineView(_ line: LyricLine, active: Bool) -> some View {
        Text(line.text)
            .font(.system(size: active
                          ? MusicLyricsMetrics.activeFont * prefs.scale
                          : MusicLyricsMetrics.inactiveFont * prefs.scale,
                          weight: active ? .bold : .semibold))
            .foregroundStyle(.white.opacity(active ? 1 : MusicLyricsMetrics.inactiveOpacity))
            .multilineTextAlignment(prefs.centred ? .center : .leading)
            .blur(radius: active || !prefs.blurInactive ? 0 : MusicLyricsMetrics.inactiveBlur)
            // The line being sung arrives rather than appearing: a scale step is what reads as
            // "this one now", and it is the only thing on the screen that moves.
            .scaleEffect(active ? 1 : 0.98)
            .animation(.easeOut(duration: MusicLyricsMetrics.timeFade), value: active)
            .contentShape(.rect)
            .accessibilityAddTraits(active ? .isSelected : [])
    }

    // MARK: The other two answers

    /// Words with no timestamps. Not highlighted, not scrolled, not pretended to be in sync — the
    /// screen says so in the same breath.
    private func block(_ words: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Không có dòng nào được gắn thời gian cho bài này.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                Text(words)
                    .font(.system(size: MusicLyricsMetrics.inactiveFont * prefs.scale))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineSpacing(8)
            }
            .padding(.horizontal, MusicLyricsMetrics.sidePadding)
            .padding(.top, 96)
            .frame(maxWidth: .infinity, alignment: prefs.centred ? .center : .leading)
        }
    }

    private var missing: some View {
        VStack(spacing: 12) {
            if lyrics.isLoading {
                ProgressView()
                    .tint(.white)
                Text("Đang tìm lời bài hát…")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            } else {
                Text("Chưa có lời cho bài này")
                    .font(.title3.weight(.semibold))
                Text(LyricsPreferences.shared.networkAllowed
                     ? "Doni đã hỏi lrclib theo tên bài, ca sĩ và thời lượng mà không thấy gì."
                     : "Tải lời bài hát đang tắt trong Cài đặt.")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 40)
        .offset(y: -40)
    }
}
