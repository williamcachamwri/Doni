import AVFoundation
import Support
import SwiftUI
import TelegramDesignSystem
import TdSession

/// Which page the panel is on. MeloX has three (`NowPlayingMotionSpec.swift:3-7`) and so is Doni:
/// the cover, the words and the queue — the words because lrclib has them whether Telegram does or
/// not.
enum NowPlayingPage: Equatable {
    case artwork, lyrics, queue
}

/// The player's panel, page for page as MeloX builds it.
///
/// The reference's portrait shell is a 34 pt handle over a page stack with the controls hung on its
/// bottom edge as a 341 pt overlay — a 62 pt utility band and a 279 pt core of progress, transport,
/// volume and page selector — and the cover is sized from whatever height that leaves
/// (`NowPlayingView.swift:317-329`, `NowPlayingBottomControls.swift:4-6`,
/// `NowPlayingArtworkPage.swift:39-50`). Every number here is that file's, transcribed.
///
/// What Doni adds is only what a Telegram library forces: the cover is fetched through TDLib rather
/// than an HTTP URL, the volume bar moves `AVAudioPlayer`'s own volume instead of the
/// `MPVolumeView` the reference had to settle for, and the verbs inside the ⋯ disc are Doni's.
struct NowPlayingView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library
    /// The words are a page of this panel. The panel's job stops at asking for them for the song it
    /// is showing; reading the player's clock and deciding which line is being sung is the screen's
    /// own, and it does both far more finely than a tick of this timer could.
    @ObservedObject private var lyrics = Lyrics.shared
    /// The panel is presented by a zoom from the strip's cover, so the shell owns that transition
    /// source and this view only has to be the destination (`ContentView.swift:105-110`).
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var page = NowPlayingPage.artwork
    /// The panel's own offset while a drag down is in progress; zero when it rests.
    @State private var panOffset: CGFloat = 0

    var body: some View {
        ZStack {
            backdrop
            if let track = player.current {
                content(track)
            }
        }
        .offset(y: max(0, panOffset))
        .gesture(pan)
        .preferredColorScheme(.dark)
        .task(id: player.current?.uniqueId) {
            // The panel wants a cover the size of the screen, which is a tier no row ever asked
            // for; without this order the hero and the blurred backdrop are drawn from the 192 px
            // a row fetched.
            if let track = player.current {
                await artwork.load(track: track, via: session.covers(),
                                   side: MusicArtworkMetrics.heroSide)
                lyrics.load(track)
            }
        }
    }

    /// The reference's blurred-artwork style: the cover scaled 1.35 under a 90 pt blur, a 0.10 veil
    /// over the pair, and a wash that darkens toward the controls so white text stays legible
    /// (`NowPlayingBackground.swift:34-56`, `:113-173`). A new song's wash dissolves over the 0.8 s
    /// curve the reference gives its artwork image (`NowPlayingAppleMusicBackground.swift:128-153`).
    private var backdrop: some View {
        GeometryReader { edge in
            ZStack {
                Color.black
                if let track = player.current,
                   let image = artwork.image(for: track,
                                             side: MusicArtworkMetrics.heroSide) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: edge.size.width, height: edge.size.height)
                        .clipped()
                        .scaleEffect(MusicNowPlayingMetrics.backdropScale)
                        .blur(radius: MusicNowPlayingMetrics.backdropBlur)
                        .transition(.opacity)
                        // The reference keys the wash by its artwork
                        // (`NowPlayingAppleMusicBackground.swift:153`), and so must this: without an
                        // identity the new cover is the same view with different pixels, which is a
                        // swap and not a cross-fade, and no curve can fix that.
                        .id(track.uniqueId)
                }
                Color.black.opacity(MusicNowPlayingMetrics.veilOpacity)
                LinearGradient(colors: MusicNowPlayingMetrics.legibilityStops.map {
                    Color.black.opacity($0)
                }, startPoint: .top, endPoint: .bottom)
            }
            .frame(width: edge.size.width, height: edge.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
        .animation(reduceMotion ? nil : MusicNowPlayingMetrics.washCrossFade,
                   value: player.current?.uniqueId)
    }

    private func content(_ track: any Playable) -> some View {
        VStack(spacing: 0) {
            handle
            ZStack(alignment: .top) {
                switch page {
                case .artwork:
                    ArtworkPage(track: track, player: player, artwork: artwork, library: library)
                        .transition(pageTransition(for: .artwork))
                case .lyrics:
                    LyricsPage(track: track, session: session, player: player,
                               artwork: artwork, library: library, lyrics: lyrics)
                        .transition(pageTransition(for: .lyrics))
                case .queue:
                    NowPlayingQueuePage(track: track, session: session, player: player,
                                        artwork: artwork, library: library)
                        .transition(pageTransition(for: .queue))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                BottomControls(player: player, page: $page)
            }
        }
        .padding(.horizontal, MusicNowPlayingMetrics.horizontal)
        .safeAreaPadding(.bottom, 3)
        .animation(reduceMotion ? nil : MusicMotion.pageSelection, value: page)
    }

    /// The reference's 34 pt box with a 60 × 5 capsule 8 into it, which dismisses on a tap
    /// (`NowPlayingView.swift:465-484`).
    private var handle: some View {
        ZStack(alignment: .top) {
            Capsule()
                .fill(Color.white.opacity(MusicNowPlayingMetrics.gripOpacity))
                .frame(width: MusicNowPlayingMetrics.gripWidth,
                       height: MusicNowPlayingMetrics.gripHeight)
                .padding(.top, MusicNowPlayingMetrics.gripTop)
        }
        .frame(maxWidth: .infinity)
        .frame(height: MusicNowPlayingMetrics.gripBox)
        .contentShape(.rect)
        .onTapGesture(perform: close)
        .accessibilityElement()
        .accessibilityLabel("Đóng")
        .accessibilityHint("Thu nhỏ về thanh dưới cùng")
        .accessibilityAction { close() }
    }

    /// The artwork page is the only one that travels, and it travels from above; the queue page's
    /// own travel is stated as 0, which leaves it the opacity half
    /// (`NowPlayingPageTransition.swift:38-53`, `NowPlayingMotionSpec.swift:525-527`).
    private func pageTransition(for destination: NowPlayingPage) -> AnyTransition {
        if reduceMotion { return .opacity }
        switch destination {
        case .artwork:
            return .asymmetric(
                insertion: .offset(y: MusicMotion.artworkTravel)
                    .combined(with: .opacity)
                    .animation(MusicMotion.pageIncoming),
                removal: .offset(y: MusicMotion.artworkTravel)
                    .combined(with: .opacity)
                    .animation(MusicMotion.pageOutgoing)
            )
        case .queue, .lyrics:
            // Neither of them travels: they are columns of text, and a page of words that slides
            // in reads as a page of words being pushed around.
            return .opacity.animation(MusicMotion.pageSelection)
        }
    }

    /// The panel follows the finger down one to one and past 120 pt it goes; otherwise it springs
    /// home. The system's own zoom puts the strip back.
    private var pan: some Gesture {
        DragGesture(minimumDistance: 15)
            .onChanged { value in
                let translation = value.translation
                guard translation.height > 0,
                      translation.height > abs(translation.width) else { return }
                panOffset = translation.height
            }
            .onEnded { value in
                let translation = value.translation
                if translation.height > 120, translation.height > abs(translation.width) {
                    close()
                } else {
                    withAnimation(.spring(response: 0.4, dampingFraction: 1.0)) {
                        panOffset = 0
                    }
                }
            }
    }
}

/// The cover page: the artwork at whatever height the controls leave, and the title block under it
/// (`NowPlayingArtworkPage.swift`).
///
/// The size is the reference's own expression, `max(1, min(width + 16, max(170, height − 279 − 92)))`
/// (`:39-50`), and on a phone the height term is the one that binds — which is why the cover in the
/// reference's screenshot is about two thirds of the screen rather than all of it.
private struct ArtworkPage: View {
    let track: any Playable
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce: CGFloat = 1

    /// Paused shrinks the cover to 0.74 (`NowPlayingArtworkPage.swift:33-35`, `:51-57`).
    private var isExpanded: Bool { player.isPlaying }

    var body: some View {
        GeometryReader { edge in
            let side = max(1, min(edge.size.width + MusicNowPlayingMetrics.artworkSideLeeway,
                                  max(MusicNowPlayingMetrics.artworkMin,
                                      edge.size.height
                                          - MusicNowPlayingMetrics.coreHeight
                                          - MusicNowPlayingMetrics.artworkReserve)))
            let shown = side * (isExpanded ? 1 : MusicNowPlayingMetrics.pausedArtworkScale)
            VStack(spacing: 0) {
                Spacer(minLength: MusicNowPlayingMetrics.artworkTopSpacer)

                ZStack {
                    TelegramTrackGradient.linear(track.messageId)
                    if let image = artwork.image(for: track,
                                                 side: MusicArtworkMetrics.heroSide) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .transition(.opacity)
                            .id(track.uniqueId)
                    }
                }
                .frame(width: shown, height: shown)
                .clipShape(RoundedRectangle(cornerRadius: MusicNowPlayingMetrics.artworkRadius,
                                            style: .continuous))
                .scaleEffect(bounce)
                .shadow(color: .black.opacity(player.isPlaying
                                                ? MusicNowPlayingMetrics.playingShadowOpacity
                                                : MusicNowPlayingMetrics.pausedShadowOpacity),
                        radius: player.isPlaying ? MusicNowPlayingMetrics.playingShadowRadius
                                                 : MusicNowPlayingMetrics.pausedShadowRadius,
                        y: player.isPlaying ? MusicNowPlayingMetrics.playingShadowY
                                            : MusicNowPlayingMetrics.pausedShadowY)
                .frame(width: side, height: side)
                .animation(reduceMotion ? nil : MusicMotion.artworkResize, value: isExpanded)
                .animation(reduceMotion ? nil : MusicMotion.artworkShadow, value: player.isPlaying)
                // Two fades, because a cover arrives two ways: a song the phone already has the art
                // for swaps identities, and one it does not inserts the picture when the bytes land.
                // The reference gets both from one mechanism — Nuke empties its own image while the
                // new URL loads, so the placeholder is always re-inserted — and Doni needs the
                // second key because its cache is a disk tier the row has usually already warmed
                // (`ArtworkImage.swift:14-16`, `:45-55`).
                .animation(reduceMotion ? nil : MusicArtworkMetrics.loadFade, value: track.uniqueId)
                .animation(reduceMotion ? nil : MusicArtworkMetrics.loadFade,
                           value: artwork.revision)
                .accessibilityElement()
                .accessibilityLabel(track.displayTitle)
                .task(id: player.isPlaying) { await bounceIn() }

                Spacer(minLength: MusicNowPlayingMetrics.artworkBottomSpacer)

                HStack(spacing: MusicNowPlayingMetrics.titleGap) {
                    VStack(alignment: .leading, spacing: MusicNowPlayingMetrics.titleSpacing) {
                        Text(track.displayTitle)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(track.displayPerformer.isEmpty ? "Doni" : track.displayPerformer)
                            .font(.title3)
                            .foregroundStyle(.white.opacity(MusicNowPlayingMetrics.artistOpacity))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    SongActions(track: track, player: player, artwork: artwork, library: library)
                }
                .padding(.bottom, MusicNowPlayingMetrics.coreHeight)
            }
            .frame(width: edge.size.width, height: edge.size.height)
        }
    }

    /// The beat a play starts: 1.055 over 0.17 s ease-out, held 170 ms, home on a 0.42 s spring
    /// with 0.24 bounce (`NowPlayingPortraitArtwork.swift:60-80`).
    private func bounceIn() async {
        bounce = 1
        guard player.isPlaying, !reduceMotion else { return }
        await Task.yield()
        withAnimation(MusicMotion.bounceRise) { bounce = MusicMotion.bounceScale }
        do {
            try await Task.sleep(for: .milliseconds(Int(MusicMotion.bounceHold * 1000)))
        } catch {
            return
        }
        withAnimation(MusicMotion.bounceSettle) { bounce = 1 }
    }
}

/// The ⋯ disc, and everything a song answers to from the panel: keep it, queue it, list it, share
/// the file, and cut a slice of it.
///
/// MeloX puts the same pair of discs in this corner — a star on white 0.13 and an ellipsis on 0.15,
/// 10 apart (`NowPlayingSongActions.swift:15`, `:46-58`, `:215-221`) — and hides the star on the
/// artwork page (`NowPlayingArtworkPage.swift:149-152`), so Doni's artwork page has the ellipsis
/// alone and the star is the first verb inside it.
///
/// Listing is the one verb the reference does differently: its menu holds a single "add to" button
/// that opens a picker (`NowPlayingSongActions.swift:107-114`, `AddToPlaylistSheet.swift`), and
/// Doni does the same rather than threading every list into the menu. A screen with no lists still
/// has to answer the tap, so the picker carries the create button the reference gives it — with a
/// working empty state, which the reference's reload cannot be here.
struct SongActions: View {
    let track: any Playable
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    @State private var showsPlaylists = false

    var body: some View {
        Menu {
            let kept = library.isFavorite(track.uniqueId)
            Button {
                library.toggleFavorite(track)
            } label: {
                Label(kept ? "Bỏ yêu thích" : "Yêu thích",
                      systemImage: kept ? "star.fill" : "star")
            }
            Button {
                player.playNext(track)
            } label: {
                Label("Nghe tiếp theo", systemImage: "text.badge.plus")
            }
            Divider()
            Button {
                showsPlaylists = true
            } label: {
                Label("Thêm vào danh sách", systemImage: "plus.circle")
            }
            Divider()
            cutButtons
            if let path = track.localPath {
                Divider()
                ShareLink(item: URL(fileURLWithPath: path)) {
                    Label("Chia sẻ tệp", systemImage: "square.and.arrow.up")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: MusicNowPlayingMetrics.actionDisc,
                       height: MusicNowPlayingMetrics.actionDisc)
                .background(Color.white.opacity(MusicNowPlayingMetrics.menuDiscFill), in: .circle)
                .contentShape(.circle)
        }
        .tint(.white)
        .menuOrder(.fixed)
        .accessibilityLabel("Khác")
        .sheet(isPresented: $showsPlaylists) {
            AddToPlaylistSheet(track: track, artwork: artwork, library: library)
        }
    }

    /// A cut is a three-step choice — mark, reach the end, keep or let go — which a menu states
    /// better than a toggle does. Keeping one writes it into the favourite, which is where Doni
    /// stores the slice the loop plays back.
    @ViewBuilder
    private var cutButtons: some View {
        if player.markIn != nil {
            Button("Kết thúc cắt tại \(clock(player.elapsed))") {
                player.markEnd()
            }
        } else if player.segment == nil {
            Button("Bắt đầu cắt tại \(clock(player.elapsed))") {
                player.markStart()
            }
        }
        if let segment = player.segment {
            Button("Giữ đoạn \(clock(segment.lowerBound)) – \(clock(segment.upperBound))") {
                library.setSegment(Int(segment.lowerBound)...Int(segment.upperBound),
                                   uniqueId: track.uniqueId)
            }
            Button("Bỏ cắt", role: .destructive) {
                player.clearCut()
            }
        }
    }

    private func clock(_ seconds: TimeInterval) -> String {
        MediaClock.duration(Int(seconds.rounded())) ?? "0:00"
    }
}

/// The bottom overlay: the reference's empty 62 pt utility band over its 279 pt core
/// (`NowPlayingBottomControls.swift:18-67`).
///
/// The utility band only ever holds lyrics buttons, so Doni reserves it and draws nothing in it —
/// the number is part of the overlay the reference's geometry is stated against.
private struct BottomControls: View {
    @ObservedObject var player: Player
    @Binding var page: NowPlayingPage

    var body: some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(height: MusicNowPlayingMetrics.utilityHeight, alignment: .top)
            VStack(spacing: 0) {
                ProgressRow(player: player)
                gap(MusicNowPlayingMetrics.progressToTransport)
                TransportRow(player: player)
                gap(MusicNowPlayingMetrics.transportToVolume)
                VolumeRow(player: player)
                gap(MusicNowPlayingMetrics.volumeToSelector)
                SelectorRow(player: player, page: $page)
            }
            .frame(height: MusicNowPlayingMetrics.coreHeight)
        }
        .frame(height: MusicNowPlayingMetrics.overlayHeight)
    }

    private func gap(_ height: CGFloat) -> some View {
        Color.clear.frame(height: height)
    }
}

/// The scrubber and its two times, with the cut in the chip between them
/// (`NowPlayingControls.swift:4-63`).
///
/// MeloX's centre chip is a playback-quality menu; a Telegram file has one quality, so the same chip
/// carries the cut — where it stands, and the buttons that finish or drop it.
private struct ProgressRow: View {
    @ObservedObject var player: Player

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the finger is holding the slider, which is not where the song is. The value goes to
    /// the player once, on release, so a drag across a three-minute file is one seek and not
    /// several hundred.
    @State private var scrubbing = false
    @State private var scrubSeconds: TimeInterval = 0

    private var total: TimeInterval {
        max(player.duration, Double(player.current?.duration ?? 0), 1)
    }

    var body: some View {
        VStack(spacing: MusicNowPlayingMetrics.progressLabelGap) {
            Slider(
                value: Binding(
                    get: { scrubbing ? scrubSeconds : min(player.elapsed, total) },
                    set: { scrubSeconds = min(max($0, 0), total) }
                ),
                in: 0...total,
                onEditingChanged: { editing in
                    scrubbing = editing
                    if !editing { player.seek(to: scrubSeconds) }
                }
            )
            .sliderThumbVisibility(.hidden)
            .tint(.white)
            .accessibilityLabel("Tiến trình")

            HStack {
                Text(clock(player.elapsed))
                Spacer()
                Text("−\(clock(max(total - player.elapsed, 0)))")
            }
            .overlay {
                if player.segment != nil || player.markIn != nil {
                    cutChip
                        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: cutStateKey)
                }
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white.opacity(MusicNowPlayingMetrics.progressLabelOpacity))
        }
        .frame(height: MusicNowPlayingMetrics.progressHeight)
    }

    /// What the chip is holding, so a change of cut state — and only that — animates it.
    private var cutStateKey: String {
        if let segment = player.segment { return "\(segment)" }
        return "marking-\(Int(player.markIn ?? -1))"
    }

    /// The chip is the cut's read-out and its way out at the same time: whatever it is saying, one
    /// tap drops it. Marking and keeping live in the ⋯ disc, which is where the verbs are.
    private var cutChip: some View {
        Menu {
            Button("Bỏ cắt", role: .destructive) {
                player.clearCut()
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "waveform")
                    .font(.system(size: MusicNowPlayingMetrics.chipGlyph, weight: .semibold))
                Text(chipText)
            }
            .padding(.horizontal, MusicNowPlayingMetrics.chipPaddingH)
            .padding(.vertical, MusicNowPlayingMetrics.chipPaddingV)
            .background(Color.white.opacity(MusicNowPlayingMetrics.chipFill),
                        in: .rect(cornerRadius: MusicNowPlayingMetrics.chipRadius))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .tint(.white)
        .accessibilityLabel("Đoạn đang phát")
    }

    private var chipText: String {
        if let segment = player.segment {
            return "\(clock(segment.lowerBound)) – \(clock(segment.upperBound))"
        }
        return "cắt từ \(clock(player.markIn ?? 0))"
    }

    private func clock(_ seconds: TimeInterval) -> String {
        MediaClock.duration(Int(seconds.rounded())) ?? "0:00"
    }
}

/// Backward, play, forward — 34, 48, 34 at `.medium`, each on a 64 pt stop in an 82 pt row
/// (`NowPlayingControls.swift:199-314`).
private struct TransportRow: View {
    @ObservedObject var player: Player

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            step("backward.fill", MusicNowPlayingMetrics.transportSkipGlyph,
                 enabled: player.hasPrevious, label: "Bài trước", action: player.previous)
            Spacer(minLength: 0)
            if player.isFetchingFile {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .frame(width: MusicNowPlayingMetrics.transportCircle,
                           height: MusicNowPlayingMetrics.transportCircle)
            } else {
                Button(action: player.toggle) {
                    Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                        .font(MusicNowPlayingMetrics.transportGlyph(
                            MusicNowPlayingMetrics.transportPlayGlyph))
                        .contentTransition(reduceMotion ? .identity
                            : .symbolEffect(.replace.downUp.wholeSymbol, options: .speed(1.6)))
                        .frame(width: MusicNowPlayingMetrics.transportCircle,
                               height: MusicNowPlayingMetrics.transportCircle)
                        .contentShape(.circle)
                }
                .buttonStyle(PlayerTransportButtonStyle(reducesMotion: reduceMotion))
                .accessibilityLabel(player.isPlaying ? "Tạm dừng" : "Phát")
            }
            Spacer(minLength: 0)
            step("forward.fill", MusicNowPlayingMetrics.transportSkipGlyph,
                 enabled: player.hasNext, label: "Bài tiếp theo", action: player.next)
        }
        .frame(height: MusicNowPlayingMetrics.transportRowHeight)
        .animation(reduceMotion ? nil : MusicMotion.symbolSwap, value: player.isPlaying)
    }

    private func step(_ system: String, _ size: CGFloat, enabled: Bool,
                      label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: system)
                .font(MusicNowPlayingMetrics.transportGlyph(size))
                .foregroundStyle(enabled ? .white : Color.white.opacity(0.3))
                .frame(width: MusicNowPlayingMetrics.transportCircle,
                       height: MusicNowPlayingMetrics.transportCircle)
                .contentShape(.circle)
        }
        .buttonStyle(PlayerTransportButtonStyle(reducesMotion: reduceMotion))
        .disabled(!enabled)
        .accessibilityLabel(label)
    }
}

/// The volume row, which in Doni moves sound: `AVAudioPlayer` has a real per-player volume, so the
/// reference's `MPVolumeView` workaround is not needed.
///
/// Same 42 pt row, same 32 pt slider, same two speaker glyphs 10 apart on white 0.62
/// (`NowPlayingControls.swift:317-361`).
private struct VolumeRow: View {
    @ObservedObject var player: Player

    var body: some View {
        HStack(spacing: MusicNowPlayingMetrics.volumeGlyphGap) {
            Image(systemName: "speaker.fill")
                .font(MusicNowPlayingMetrics.volumeGlyphLow)
            Slider(value: $player.volume, in: 0...1)
                .tint(.white)
                .frame(maxWidth: .infinity)
                .frame(height: MusicNowPlayingMetrics.volumeSliderHeight)
                .layoutPriority(1)
            Image(systemName: "speaker.wave.3.fill")
                .font(MusicNowPlayingMetrics.volumeGlyphHigh)
        }
        .foregroundStyle(.white.opacity(MusicNowPlayingMetrics.volumeOpacity))
        .frame(height: MusicNowPlayingMetrics.volumeHeight)
    }
}

/// The row of three 44 pt discs at the very bottom.
///
/// MeloX spends it on pages (`NowPlayingControls.swift:400-518`). Doni has two pages and two modes
/// worth reaching without opening the queue, so the slots carry shuffle, repeat and the queue
/// itself — the same controls the queue page's pills state, in the same chrome: 0.72 white at rest,
/// a 0.68 white disc with 0.68 black ink when on, and the queue button wearing the mode badge while
/// it is not the page shown.
private struct SelectorRow: View {
    @ObservedObject var player: Player
    @Binding var page: NowPlayingPage

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            // The bubble first, where the reference puts its lyrics control: it is the one page
            // that is about the song rather than about the playing of it.
            mode(system: "text.bubble", on: page == .lyrics, label: "Lời bài hát") {
                withAnimation(reduceMotion ? nil : MusicMotion.pageSelection) {
                    page = page == .lyrics ? .artwork : .lyrics
                }
            }
            Spacer()
            mode(system: "shuffle", on: player.isShuffled,
                 label: player.isShuffled ? "Tắt phát ngẫu nhiên" : "Phát ngẫu nhiên") {
                withAnimation(reduceMotion ? nil : MusicQueueMetrics.pillToggle) {
                    player.setShuffled(!player.isShuffled)
                }
            }
            Spacer()
            mode(system: player.repeatSystemImage, on: player.repeatMode != .off,
                 label: repeatLabel) {
                withAnimation(reduceMotion ? nil : MusicQueueMetrics.pillToggle) {
                    player.cycleRepeatMode()
                }
            }
            Spacer()
            mode(system: "list.bullet", on: page == .queue, label: "Hàng chờ",
                 badge: page == .queue ? nil : player.queueModeBadgeSystemImage) {
                withAnimation(reduceMotion ? nil : MusicMotion.pageSelection) {
                    page = page == .queue ? .artwork : .queue
                }
            }
        }
        .padding(.horizontal, MusicNowPlayingMetrics.horizontal)
        .foregroundStyle(.white.opacity(MusicNowPlayingMetrics.selectorOpacity))
        .frame(height: MusicNowPlayingMetrics.selectorHeight)
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .off: return "Lặp lại toàn bộ"
        case .all: return "Lặp lại một bài"
        case .one: return "Tắt lặp lại"
        }
    }

    private func mode(system: String, on: Bool, label: String, badge: String? = nil,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: system)
                    .symbolVariant(on ? .fill : .none)
                    .font(.title3)
                    .frame(width: MusicNowPlayingMetrics.selectorButton,
                           height: MusicNowPlayingMetrics.selectorButton)
                    .foregroundStyle(on ? .black.opacity(MusicNowPlayingMetrics.selectorDiscInk)
                                        : .white.opacity(MusicNowPlayingMetrics.selectorOpacity))
                    .background(Color.white.opacity(on ? MusicNowPlayingMetrics.selectorDiscFill
                                                        : 0), in: .circle)

                if let badge {
                    Image(systemName: badge)
                        .font(.system(size: MusicNowPlayingMetrics.badgeGlyph, weight: .bold))
                        .foregroundStyle(.black.opacity(0.74))
                        .frame(width: MusicNowPlayingMetrics.badgeSize,
                               height: MusicNowPlayingMetrics.badgeSize)
                        .background(Color.white.opacity(0.82), in: .circle)
                        .offset(MusicNowPlayingMetrics.badgeOffset)
                }
            }
            .frame(width: MusicNowPlayingMetrics.selectorButton,
                   height: MusicNowPlayingMetrics.selectorButton)
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The reference's press state: the glyph to 0.8 while the finger is down, and a 0.1 white disc
/// expanding from 0.86 over 0.18 s, both released over 0.4 s
/// (`NowPlayingTransportButtonStyle.swift:59-132`).
struct PlayerTransportButtonStyle: ButtonStyle {
    let reducesMotion: Bool

    func makeBody(configuration: Configuration) -> some View {
        Body(label: configuration.label, isPressed: configuration.isPressed,
             reducesMotion: reducesMotion)
    }

    private struct Body<Label: View>: View {
        let label: Label
        let isPressed: Bool
        let reducesMotion: Bool

        @State private var iconScale: CGFloat = 1
        @State private var highlightScale = MusicMotion.pressedHighlightScale
        @State private var highlightOpacity = 0.0

        var body: some View {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(MusicMotion.highlightOpacity))
                    .scaleEffect(highlightScale)
                    .opacity(highlightOpacity)
                label
                    .scaleEffect(iconScale)
            }
            .contentShape(.circle)
            .onAppear { update(to: isPressed, animated: false) }
            .onChange(of: isPressed) { _, pressed in update(to: pressed, animated: true) }
        }

        private func update(to pressed: Bool, animated: Bool) {
            guard animated, !reducesMotion else {
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    iconScale = pressed && !reducesMotion ? MusicMotion.pressedIconScale : 1
                    highlightScale = pressed ? MusicMotion.pressedHighlightScale : 1
                    highlightOpacity = pressed ? 1 : 0
                }
                return
            }
            if pressed {
                // The disc starts small and unanimated, so it grows from there rather than fading
                // in at full size.
                var transaction = Transaction(animation: nil)
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    highlightScale = MusicMotion.pressedHighlightScale
                }
                withAnimation(MusicMotion.press) {
                    iconScale = MusicMotion.pressedIconScale
                    highlightOpacity = 1
                }
            } else {
                withAnimation(MusicMotion.release) { iconScale = 1 }
                withAnimation(MusicMotion.highlightExpansion) { highlightScale = 1 }
                withAnimation(.easeIn(duration: 0.4)) { highlightOpacity = 0 }
            }
        }
    }
}

#Preview {
    NowPlayingView(session: TelegramSession(), player: Player(), artwork: CoverArtwork.shared,
                   library: Library.shared, close: {})
}
