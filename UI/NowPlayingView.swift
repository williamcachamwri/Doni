import AVFoundation
import DoniLyrics
import Support
import SwiftUI
import TelegramDesignSystem
import TdSession

/// The player's panel, page for page as MeloX builds it.
/// The reference's portrait shell is a 34 pt handle over a page stack with the controls hung on its
/// bottom edge as a 341 pt overlay — a 62 pt utility band and a 279 pt core of progress, transport,
/// volume and page selector — and the cover is sized from whatever height that leaves
/// (`NowPlayingView.swift:317-329`, `NowPlayingBottomControls.swift:4-6`,
/// `NowPlayingArtworkPage.swift:39-50`). Every number here is that file's.
/// Doni adds only what a Telegram library forces: the cover comes through TDLib rather than an HTTP
/// URL, and the volume bar moves `AVAudioPlayer`'s own volume instead of the reference's `MPVolumeView`.
struct NowPlayingView: View {
    @ObservedObject var session: TelegramSession
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library
    /// The words are a page of this panel: the panel only asks for them for the song it shows, and
    /// deciding which line is being sung is the lyrics screen's own, finer than a tick of this timer.
    @ObservedObject private var lyrics = Lyrics.shared
    /// The panel is presented by a zoom from the strip's cover, so the shell owns that transition
    /// source and this view only has to be the destination (`ContentView.swift:105-110`).
    let close: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver

    @State private var page = NowPlayingPage.artwork
    /// Where the artwork page's cover slot landed, in the page's own space. The cover is no longer
    /// drawn by the page, so this is how the panel knows where to put it (`NowPlayingView.swift:614-630`).
    @State private var artworkPageFrame: CGRect = .zero
    /// Whether the transport row is on screen while the words are. The reference drops it after a
    /// few seconds of reading and brings it back on a tap or a scroll (`NowPlayingView.swift:18`).
    @State private var showsLyricsControls = true
    /// Bumped to restart that wait, rather than a timer that would have to be cancelled by hand.
    @State private var lyricsControlsActivity = 0
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
            // The panel wants a cover the size of the screen, a tier no row ever asked for; without
            // this order the hero and the blurred backdrop are drawn from the 192 px a row fetched.
            if let track = player.current {
                await artwork.load(track: track, via: session.covers(),
                                   side: MusicArtworkMetrics.heroSide)
                lyrics.load(track)
            }
        }
        .task(id: lyricsControlsActivity) {
            guard hidesLyricsControlsApplies, showsLyricsControls, !voiceOver else { return }
            do {
                try await Task.sleep(
                    for: .seconds(Lyrics.settings.appleMusicLyricsInterfaceAutoHideDelay)
                )
            } catch {
                return
            }
            guard hidesLyricsControlsApplies else { return }
            withAnimation(NowPlayingInterfaceTransition.interfaceAnimation(
                isVisible: false, reducesMotion: reduceMotion)) {
                showsLyricsControls = false
            }
        }
        .onChange(of: page) { _, newPage in
            if newPage == .lyrics {
                registerLyricsControlsActivity()
            } else {
                cancelLyricsControlsAutoHide()
                showsLyricsControls = true
            }
        }
        .onChange(of: voiceOver) { _, spoken in
            guard hidesLyricsControlsApplies else { return }
            if spoken {
                cancelLyricsControlsAutoHide()
                showsLyricsControls = true
            } else {
                registerLyricsControlsActivity()
            }
        }
    }

    /// The words page, and only it: the reference hides nothing on the artwork page, where the
    /// controls are the content (`NowPlayingView.swift:412-416`).
    private var hidesLyricsControlsApplies: Bool { page == .lyrics }

    private var hidesLyricsControls: Bool { hidesLyricsControlsApplies && !showsLyricsControls }

    /// A touch on the words. It does not toggle — it says "I am still here", shows the controls if
    /// they had gone, and starts the wait again (`NowPlayingView.swift:966-981`).
    private func registerLyricsControlsActivity() {
        guard hidesLyricsControlsApplies else { return }
        lyricsControlsActivity &+= 1
        guard !showsLyricsControls else { return }
        withAnimation(NowPlayingInterfaceTransition.interfaceAnimation(
            isVisible: true, reducesMotion: reduceMotion)) {
            showsLyricsControls = true
        }
    }

    private func cancelLyricsControlsAutoHide() {
        lyricsControlsActivity &+= 1
    }

    /// The column's own report: it hides the interface when the finger scrolls past the reference's
    /// 200 pt, and asks for it back when the user reaches for the top (`NowPlayingView.swift:983-1000`,
    /// `AppSettings.swift:55-56`).
    private func setLyricsControlsVisible(_ visible: Bool) {
        guard hidesLyricsControlsApplies else { return }
        if visible {
            registerLyricsControlsActivity()
            return
        }
        guard showsLyricsControls, !voiceOver else { return }
        cancelLyricsControlsAutoHide()
        withAnimation(NowPlayingInterfaceTransition.interfaceAnimation(
            isVisible: false, reducesMotion: reduceMotion)) {
            showsLyricsControls = false
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
                        // identity the new cover is the same view with different pixels — a swap, not a
                        // cross-fade, which no curve can fix.
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
            pageContent(track)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    BottomControls(player: player, page: $page,
                                   isInterfaceHidden: hidesLyricsControls)
                        .allowsHitTesting(!hidesLyricsControls)
                        .accessibilityHidden(hidesLyricsControls)
                }
        }
        .padding(.horizontal, MusicNowPlayingMetrics.horizontal)
        .safeAreaPadding(.bottom, 3)
        .animation(reduceMotion ? nil : NowPlayingPageTransition.animation, value: page)
    }

    /// The reference's stack (`NowPlayingView.swift:486-559`): the page, then the song header over it
    /// when the page is not the cover's own, then the cover over everything. The cover is hoisted out
    /// of both pages because they want it at different sizes — the hero on the artwork page, a 72 pt
    /// thumb in the header — and one measured view travelling between them is what makes it move rather
    /// than be replaced.
    private func pageContent(_ track: any Playable) -> some View {
        ZStack(alignment: .top) {
            switch page {
            case .artwork:
                ArtworkPage(track: track, session: session, player: player, artwork: artwork,
                            library: library)
                    .transition(pageTransition(for: .artwork))
            case .lyrics:
                LyricsPage(player: player, lyrics: lyrics,
                           isInterfaceHidden: hidesLyricsControls,
                           onInterfaceInteraction: registerLyricsControlsActivity,
                           onInterfaceVisibilityChange: setLyricsControlsVisible)
                    .transition(pageTransition(for: .lyrics))
            case .queue:
                NowPlayingQueuePage(track: track, session: session, player: player,
                                    artwork: artwork, library: library)
                    .transition(pageTransition(for: .queue))
            }

            if page == .lyrics {
                SharedSongHeader(track: track, session: session, player: player,
                                 artwork: artwork, library: library)
                    .clipped()
                    .transition(NowPlayingPageTransition.songHeader(reducesMotion: reduceMotion))
            }
        }
        .background {
            // A copy of the artwork page that is never seen and never transitioned: the only instance
            // whose geometry is the settled layout. The visible page is drawn with its transition
            // offset while the switch runs, so measuring it would send the cover to where the page is
            // on its way in rather than where it will rest (`NowPlayingView.swift:586-612`).
            ArtworkPage(track: track, session: session, player: player, artwork: artwork,
                        library: library, onArtworkFrameChange: recordArtworkPageFrame)
                .hidden()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay {
            GeometryReader { _ in
                if artworkPageFrame.width > 0 {
                    PortraitArtwork(track: track, player: player, artwork: artwork,
                                    isArtworkPage: page == .artwork,
                                    side: portraitArtworkFrame.width)
                        .frame(width: portraitArtworkFrame.width,
                               height: portraitArtworkFrame.height)
                        .position(x: portraitArtworkFrame.midX
                                    + MusicNowPlayingMetrics.horizontal,
                                  y: portraitArtworkFrame.midY)
                        .animation(reduceMotion ? nil
                                                : NowPlayingPageTransition.artworkResizeAnimation,
                                   value: player.isPlaying)
                        .allowsHitTesting(false)
                }
            }
            // Clipped against the page so a travelling cover is cut off vertically by the panel, with
            // the horizontal margin given back so it can still be wider than the text
            // (`NowPlayingView.swift:543-556`).
            .clipped()
            .padding(.horizontal, -MusicNowPlayingMetrics.horizontal)
        }
        .coordinateSpace(name: NowPlayingPortraitCoordinateSpace.name)
    }

    /// Where the cover goes. On the artwork page it is the measured slot, shrunk in place while the
    /// song is paused; everywhere else it is the header's own 72 pt box
    /// (`NowPlayingView.swift:760-788`).
    private var portraitArtworkFrame: CGRect {
        guard page != .artwork else { return displayedArtworkPageFrame }
        return CGRect(x: 0, y: 0,
                      width: MusicNowPlayingMetrics.lyricsHeaderSide,
                      height: MusicNowPlayingMetrics.lyricsHeaderSide)
    }

    private var displayedArtworkPageFrame: CGRect {
        guard !player.isPlaying else { return artworkPageFrame }
        let scale = MusicNowPlayingMetrics.pausedArtworkScale
        return artworkPageFrame.insetBy(
            dx: artworkPageFrame.width * (1 - scale) / 2,
            dy: artworkPageFrame.height * (1 - scale) / 2
        )
    }

    /// The page's geometry is only trusted once the transition has settled: the artwork page enters
    /// with an offset and would report where it is on its way in (`NowPlayingView.swift:600-612`).
    private func recordArtworkPageFrame(_ frame: CGRect) {
        guard frame.width.isFinite, frame.height.isFinite,
              frame.minX.isFinite, frame.minY.isFinite,
              frame.width > 0, frame.height > 0 else { return }
        let tolerance: CGFloat = 0.5
        guard abs(artworkPageFrame.minX - frame.minX) > tolerance
                || abs(artworkPageFrame.minY - frame.minY) > tolerance
                || abs(artworkPageFrame.width - frame.width) > tolerance
                || abs(artworkPageFrame.height - frame.height) > tolerance else { return }
        artworkPageFrame = frame
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

    /// The reference's own page transitions: the artwork page travels by `artworkDetailsTravel`,
    /// the words fade in and travel out by `lyricsTravel`, the queue arrives in stages
    /// (`NowPlayingPageTransition.swift:22-54`).`entersFromHiddenQueue` is the queue's own
    /// handover and Doni has no hidden queue to come back from, so it is always false here.
    private func pageTransition(for destination: NowPlayingPage) -> AnyTransition {
        NowPlayingPageTransition.content(
            for: destination,
            entersFromHiddenQueue: false,
            reducesMotion: reduceMotion
        )
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
/// (`NowPlayingArtworkPage.swift`). The size is the reference's own expression
/// `max(1, min(width + 16, max(170, height − 279 − 92)))` (`:39-50`), and on a phone the height term
/// binds — which is why the reference's cover is about two thirds of the screen rather than all of it.
private struct ArtworkPage: View {
    let track: any Playable
    /// Passed down to the song's own menu, which is the one place a song is put into
    /// the account's cloud.
    var session: TelegramSession?
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library
    /// Where the cover slot landed. Only the hidden copy of the page is asked; the one the user
    /// sees is allowed to be mid-transition when it is measured.
    var onArtworkFrameChange: ((CGRect) -> Void)? = nil

    var body: some View {
        GeometryReader { edge in
            let side = max(1, min(edge.size.width + MusicNowPlayingMetrics.artworkSideLeeway,
                                  max(MusicNowPlayingMetrics.artworkMin,
                                      edge.size.height
                                          - MusicNowPlayingMetrics.coreHeight
                                          - MusicNowPlayingMetrics.artworkReserve)))
            VStack(spacing: 0) {
                Spacer(minLength: MusicNowPlayingMetrics.artworkTopSpacer)

                // The slot the cover flies out of. The picture itself is drawn by the panel, over
                // every page, so this only has to say where it would have been
                // (`NowPlayingArtworkPage.swift:86-104`).
                Color.clear
                    .frame(width: side, height: side)
                    .onGeometryChange(for: CGRect.self) { geometry in
                        geometry.frame(in: .named(NowPlayingPortraitCoordinateSpace.name))
                    } action: { frame in
                        onArtworkFrameChange?(frame)
                    }

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

                    SongActions(track: track, player: player, artwork: artwork, library: library,
                                session: session)
                }
                .padding(.bottom, MusicNowPlayingMetrics.coreHeight)
            }
            .frame(width: edge.size.width, height: edge.size.height)
        }
    }
}

/// The name the cover slot and the cover itself agree on, so the measurement one reports is in the
/// space the other is drawn in (`NowPlayingPortraitArtwork.swift:3-5`).
enum NowPlayingPortraitCoordinateSpace {
    static let name = "nowPlayingPortraitPageContent"
}

/// The one cover of the panel, wherever the page wants it
/// (`NowPlayingPortraitArtwork.swift:8-81`).
///
/// It carries the shadow and the play-start bounce only while it is on the artwork page: on the way
/// into the header it is a picture flying, and a flying picture that still casts the hero's
/// 26 pt shadow reads as two objects.
private struct PortraitArtwork: View {
    let track: any Playable
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    let isArtworkPage: Bool
    /// The box's own side, in points. The picture is cut to this square rather than measured against
    /// it, because `scaledToFill` sizes the *layout box*, not only the pixels: a cover wider than it
    /// is tall made the ZStack wider than the slot, and the `clipShape` below then cut the picture to
    /// that wider box — so a rectangular cover spilled over the song's own name.
    let side: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var bounce: CGFloat = 1

    var body: some View {
        ZStack {
            MissingArtwork(side: side)
            if let image = artwork.image(for: track, side: MusicArtworkMetrics.heroSide) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
                    .id(track.uniqueId)
            }
        }
        .frame(width: side, height: side)
        .scaleEffect(bounce)
        .shadow(color: .black.opacity(shadowOpacity), radius: shadowRadius, y: shadowY)
        .clipShape(RoundedRectangle(cornerRadius: MusicNowPlayingMetrics.artworkRadius,
                                    style: .continuous))
        .animation(reduceMotion ? nil : MusicMotion.artworkShadow, value: player.isPlaying)
        // Two fades, because a cover arrives two ways: a song the phone already has the art for
        // swaps identities, and one it does not inserts the picture when the bytes land.
        .animation(reduceMotion ? nil : MusicArtworkMetrics.loadFade, value: track.uniqueId)
        .animation(reduceMotion ? nil : MusicArtworkMetrics.loadFade, value: artwork.revision)
        .accessibilityElement()
        .accessibilityLabel(track.displayTitle)
        .task(id: shouldBounce) { await bounceIn() }
    }

    private var shouldBounce: Bool { isArtworkPage && player.isPlaying }

    private var shadowOpacity: Double {
        guard isArtworkPage else { return 0 }
        return player.isPlaying ? MusicNowPlayingMetrics.playingShadowOpacity
                                : MusicNowPlayingMetrics.pausedShadowOpacity
    }

    private var shadowRadius: CGFloat {
        guard isArtworkPage else { return 0 }
        return player.isPlaying ? MusicNowPlayingMetrics.playingShadowRadius
                                : MusicNowPlayingMetrics.pausedShadowRadius
    }

    private var shadowY: CGFloat {
        guard isArtworkPage else { return 0 }
        return player.isPlaying ? MusicNowPlayingMetrics.playingShadowY
                                : MusicNowPlayingMetrics.pausedShadowY
    }

    /// The beat a play starts: 1.055 over 0.17 s ease-out, held 170 ms, home on a 0.42 s spring
    /// with 0.24 bounce (`NowPlayingPortraitArtwork.swift:62-81`).
    private func bounceIn() async {
        bounce = 1
        guard shouldBounce, !reduceMotion else { return }
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

/// The header the words page and the queue page share (`NowPlayingSongHeader.swift:65-97`).
///
/// Its artwork slot is empty on purpose: the panel draws the cover there itself, which is what lets
/// the same picture be the hero on one page and this thumb on the other.
private struct SharedSongHeader: View {
    let track: any Playable
    /// Passed down to the song's own menu, which is the one place a song is put into
    /// the account's cloud.
    var session: TelegramSession?
    @ObservedObject var player: Player
    @ObservedObject var artwork: CoverArtwork
    @ObservedObject var library: Library

    var body: some View {
        HStack(spacing: MusicNowPlayingMetrics.lyricsHeaderGap) {
            Color.clear
                .frame(width: MusicNowPlayingMetrics.lyricsHeaderSide,
                       height: MusicNowPlayingMetrics.lyricsHeaderSide)

            VStack(alignment: .leading, spacing: MusicNowPlayingMetrics.titleSpacing) {
                Text(track.displayTitle)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(track.displayPerformer.isEmpty ? "Doni" : track.displayPerformer)
                    .font(.title3)
                    .foregroundStyle(.white.opacity(MusicNowPlayingMetrics.artistOpacity))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            SongActions(track: track, player: player, artwork: artwork, library: library,
                        session: session)
        }
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
    /// The session, for the one action that leaves the phone. Optional because the queue page has no
    /// reason to thread a session through three views to reach it: a song can be liked and queued
    /// from there, but it is put into the cloud from where it is actually playing.
    var session: TelegramSession?
    @StateObject private var cloud = CloudMusic()
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
            // Upload, not download: this app's cloud is the account's own chat, so keeping a song
            // means sending it there. It says so on the row, because "Download" on an app whose
            // library is Telegram is a word that means the opposite of what it looks like.
            if let session {
                Button {
                    let track = track
                    Task {
                        await cloud.publish(session, track)
                    }
                } label: {
                    Label(cloud.isBusy ? "Đang tải lên…" : "Lưu vào Cloud Music",
                          systemImage: cloud.isBusy ? "hourglass" : "icloud.and.arrow.up")
                }
                .disabled(cloud.isBusy)
                Divider()
            }
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
            Button(localized("Kết thúc cắt tại %@", clock(player.elapsed))) {
                player.markEnd()
            }
        } else if player.segment == nil {
            Button(localized("Bắt đầu cắt tại %@", clock(player.elapsed))) {
                player.markStart()
            }
        }
        if let segment = player.segment {
            Button(localized("Giữ đoạn %@ – %@", clock(segment.lowerBound), clock(segment.upperBound))) {
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
    let isInterfaceHidden: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            // The band above the progress row is where a stopped stream says why. It is the one
            // height in this layout that was already reserved for something other than the
            // reference's own measured rows, so the sentence costs no band its number.
            problemLine
                .frame(height: MusicNowPlayingMetrics.utilityHeight, alignment: .top)
            VStack(spacing: 0) {
                interfaceLayer(.progress) { ProgressRow(player: player) }
                gap(MusicNowPlayingMetrics.progressToTransport)
                interfaceLayer(.transport) { TransportRow(player: player) }
                gap(MusicNowPlayingMetrics.transportToVolume)
                interfaceLayer(.volume) { VolumeRow(player: player) }
                gap(MusicNowPlayingMetrics.volumeToSelector)
                interfaceLayer(.pageSelector) { SelectorRow(player: player, page: $page) }
            }
            .frame(height: MusicNowPlayingMetrics.coreHeight)
        }
        .frame(height: MusicNowPlayingMetrics.overlayHeight)
    }

    private func gap(_ height: CGFloat) -> some View {
        Color.clear.frame(height: height)
    }

    /// Why the song is not playing, in one line, with the one action that can fix it.
    ///
    /// Inline rather than a banner over the interface: the reason belongs under the play button the
    /// listener just pressed, not floating above the artwork they came to look at.
    @ViewBuilder
    private var problemLine: some View {
        if let problem = player.playbackProblem {
            HStack(spacing: 6) {
                Image(systemName: problem.symbol)
                    .font(.footnote)
                Text(localized(problem.message))
                    .font(.footnote)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button("Thử lại") { player.retry() }
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.plain)
            }
            .foregroundStyle(.white.opacity(MusicNowPlayingMetrics.progressLabelOpacity))
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .bottom)))
        } else {
            Color.clear
        }
    }

    /// Each band leaves on its own offset and its own curve, which is what makes the row dissolve
    /// in steps rather than as one block (`NowPlayingBottomControls.swift:68-90`).
    @ViewBuilder
    private func interfaceLayer<Content: View>(
        _ layer: NowPlayingInterfaceTransition.ControlLayer,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .offset(y: isInterfaceHidden
                     ? NowPlayingInterfaceTransition.hiddenOffset(for: layer)
                     : 0)
            .opacity(isInterfaceHidden ? 0 : 1)
            .animation(
                NowPlayingInterfaceTransition.controlAnimation(
                    for: layer,
                    isVisible: !isInterfaceHidden,
                    reducesMotion: reduceMotion
                ),
                value: isInterfaceHidden
            )
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
        return localized("cắt từ %@", clock(player.markIn ?? 0))
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
            if (player.isFetchingFile || player.isBuffering), player.playbackProblem == nil {
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
        .accessibilityLabel(LocalizedStringKey(label))
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
        .accessibilityLabel(LocalizedStringKey(label))
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

/// The three reasons a stream stops by itself are not the same sentence, and saying the wrong one
/// sends the listener to the wrong setting: the router, the Telegram post, or nothing at all.
private extension Player.PlaybackProblem {
    var symbol: String {
        switch self {
        case .offline: return "wifi.slash"
        case .stalled: return "exclamationmark.arrow.circlepath"
        case .gone: return "exclamationmark.triangle"
        }
    }

    var message: String {
        switch self {
        case .offline: return "Không có kết nối Internet"
        case .stalled: return "Không tải được phần còn lại của bài hát"
        case .gone: return "Bài hát này không còn trên Telegram"
        }
    }
}

#Preview {
    NowPlayingView(session: TelegramSession(), player: Player(), artwork: CoverArtwork.shared,
                   library: Library.shared, close: {})
}
