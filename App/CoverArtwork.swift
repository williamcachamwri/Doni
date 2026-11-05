import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import Support
import TdSession
import UIKit

/// The cover art a surface shows, decoded at the size that surface actually draws. There are three covers
/// to choose between, and the old pipeline looked at only the worst-served one of them:
///
/// * **The song's own tags.** A downloaded MP3 or M4A carries its album cover inside it, usually far bigger
///   than anything the server thumbed, and that is the artwork Telegram's own player shows. No download
///   needed, so it is asked for first on any track the phone holds.
/// * **TDLib's cover file** (`TdTrack.coverFileId`): a real server thumbnail — 320 px on the measured
///   channel's 112 audios that have one — or a generated 600 px cover on those that do not.
/// * **The `minithumbnail` the message carries**: 40×30 (`td_api.tl:361`), a few hundred bytes of JPEG. A
///   placeholder, not artwork, and what made the whole list look smeared: a 40 px tile across a 166 pt
///   shelf card is a 12× upscale.
///
/// The third is therefore allowed only on the smallest tier — rows, bubbles and the strip are read at
/// arm's length and forgive it, while a card or a hero shows Telegram's gradient until something real
/// arrives. Three levels hold the result because none alone survives a phone: `NSCache` is process memory
/// and iOS empties it as soon as a backgrounded app is asked for room (which is why every cover used to be
/// missing on the way out of Now Playing), so the last screens' tiles also live in a byte-capped
/// dictionary the system cannot take back; underneath both sits a directory of the cover's **own bytes**,
/// decoded at whatever tier a surface next asks for. Nothing is re-encoded, so quality stays the channel's
/// rather than a copy of a copy, and nothing is re-fetched, so a cover's second appearance costs one
/// ImageIO read instead of a round trip.
@MainActor
final class CoverArtwork: ObservableObject {
    /// The pixel sides a cover is decoded at, smallest first. A surface takes the smallest tier that still
    /// covers its own pixels: 60 pt rows and the 40 pt strip land in the first, the 154/166 pt cards in the
    /// second, anything hero-sized in the last.
    static let tiers = [192, 512, 768]

    /// The most pixels the 40×30 minithumbnail may fill. It used to be the whole first tier — 192, a 4.8×
    /// upscale of a 40 px source, which is exactly the smear reported on search rows: the picture had
    /// arrived and was not worth looking at while the sharp one was coming. At 96 px it stays what it is for,
    /// a placeholder for the 24-32 pt marks, and anything bigger waits for something real.
    private static let miniCeiling = 96

    /// The pixels a surface of this point size actually wants, before it is rounded up to a tier. Three is
    /// this app's own screen scale: Doni is a portrait iPhone and `UIScreen.main.scale` is leaving the SDK.
    static func neededPixels(forSide points: CGFloat) -> Int {
        Int((points * 3).rounded(.up))
    }

    /// The tier a surface of this point size is drawn at.
    static func pixels(forSide points: CGFloat) -> Int {
        let needed = neededPixels(forSide: points)
        return tiers.first { $0 >= needed } ?? tiers[tiers.count - 1]
    }

    /// Bumped whenever a tile can be drawn, so the list re-reads the cache.
    @Published private(set) var revision = 0

    /// One cache for the app: the list, the cards, the mini player and the lock screen all want the same
    /// cover, though not at the same size.
    static let shared = CoverArtwork()

    /// Kept so the surfaces that hold only this object — the player, the hero — can order a cover of their
    /// own, at their own size, instead of living off whatever a row fetched.
    var downloader: TdFileDownloader?

    private let cache = NSCache<NSString, UIImage>()

    /// The last few dozen tiles, held outside `NSCache` where the system cannot take them back: `NSCache` is
    /// the app's own memory and iOS empties it the moment a suspended app is asked for room, which is
    /// precisely the moment the user is about to look again — so the list, the strip and Now Playing went
    /// back to the flat gradient and every cover had to be decoded again. It is a hard cap rather than a
    /// limit the OS may ignore, so the byte budget below is what keeps this from being why the app is killed.
    private var pinned: [NSString: UIImage] = [:]

    /// The pinned keys, oldest first: a dictionary has no order, and the set must drop what was looked at
    /// longest ago rather than an arbitrary member of it.
    private var pinnedOrder: [NSString] = []

    private var pinnedBytes = 0

    /// The surfaces that have asked since the app was last in front, oldest first. Coming back from the
    /// background refills exactly these: a SwiftUI `.task` still on screen does not run again, so without
    /// this a row would go on drawing a gradient over a cache the system emptied.
    private var recent: [(track: any Playable, points: CGFloat)] = []

    /// Sources the phone holds but ImageIO cannot turn into a picture. Without this the self-healing read
    /// would retry one forever: it exists, so it is asked for; it decodes to nothing, so the next frame asks
    /// again.
    private var unreadableSources: Set<NSString> = []

    /// Tiles whose fetch came back with nothing, and how many more times the cache will ask. This is what a
    /// channel's newest posts run into: their cover is a thumbnail Telegram generates on its side
    /// (`FileManager.cpp:4361`) and the first ask answers a file with no bytes yet, because TDLib has not
    /// made it. Without a second try the row keeps its placeholder for the whole session — a row's `.task`
    /// runs once per song and the foreground refill only replays what was on screen.
    private var retries: [NSString: Int] = [:]

    /// How many extra asks a missing cover gets, and how long between them: three tries over a minute is
    /// longer than Telegram's generation takes for the posts this app has measured, and short enough that a
    /// song with no cover stops asking before the user notices.
    private static let coverRetries = 3
    private static let coverRetryDelay = Duration.seconds(20)

    /// Asks waiting for the pool, the one the user is looking at first.
    private var queued: [Ask] = []

    /// Whether a pool is already working through `queued`: starting a second one would only put more workers
    /// on the same list.
    private var draining = false

    /// Tiles whose bytes are on their way. A row, a shelf card and the Now Playing hero all want the same
    /// picture at different sizes, and before this each opened its own download of the same file and its own
    /// decode of the same bytes.
    private var inFlight: Set<NSString> = []

    /// The container reads already happening, one per song. `inFlight` is keyed by the tile — a song at 192
    /// and the same song at 768 are two tiles — which is the wrong key for the expensive half, opening the
    /// song itself: two tiers asking at once were two `AVURLAsset` walks of the same 140 MB, both writing
    /// the same source file.
    private var fileArtReads: [NSString: Task<Bool, Never>] = [:]

    /// One surface's ask, which is what the pool carries.
    private struct Ask {
        let track: any Playable
        let via: TdFileDownloader?
        let points: CGFloat
    }

    /// How many covers are worked on at once. TDLib queues its own downloads and a cover is tens of
    /// kilobytes, so this bounds decodes and file waits, not the network: six fills a screen at once and is
    /// far below the number of rows that ask, so the queue in front of it does the ordering.
    private static let fetchWidth = 6

    /// How many asks the queue may hold. A channel of a thousand songs is not an order for a thousand
    /// covers: rows ask when they are reached, so the queue only has to stay ahead of the finger, and an
    /// unbounded one would spend the download queue on screens the user may never open.
    private static let queueLimit = 150

    /// The re-warms, held so the singleton keeps both of its observers alive.
    private var foreground: [Task<Void, Never>] = []

    /// Whether a refill is already on the way: coming back fires `willEnterForeground` and then
    /// `didBecomeActive` a frame apart, and the second would start the same decodes again.
    private var refilling = false

    /// How many asks are worth remembering — a flick through a thousand-row list is not a request to hold a
    /// thousand rows. The count has to cover a whole home screen: three shelves of cards, the quick-action
    /// tiles and the strip each ask at their own `points`, and `recent` keys on the pair, so one song at
    /// 154 pt and at 60 pt is two entries. Forty was enough when only visible surfaces asked.
    private static let recentLimit = 80

    /// 16 MB of pinned tiles: a 192 px row tile is 147 KB and a 768 px hero is 2.3 MB, so the byte cap and
    /// not the count decides. It was 8 MB, which held eight of the 512 px shelf cards the home feed draws —
    /// the feed has three shelves on screen at once, so a flick back to a strip visible two seconds ago was
    /// still a gradient.
    private static let pinnedBudget = 16 * 1024 * 1024

    init() {
        // First, and on this thread: the read path takes the disk before the network, so a sweep that ran
        // later would let the first screens draw the bytes it is about to throw away.
        Self.discardUnverifiedSources()
        // Costed by bytes, not by count: a 192 px tile is 147 KB and a 768 px hero 2.3 MB, so a flat count
        // would either starve the list or let a handful of heroes walk past the process's memory.
        cache.totalCostLimit = 64 * 1024 * 1024
        // Two hooks rather than one: `willEnterForeground` is the earlier and lands before anything here is
        // drawn again, so covers are already decoding while the system's snapshot is still on screen;
        // `didBecomeActive` also fires on a cold launch and after a system dialog, where the first never does.
        foreground = [UIApplication.willEnterForegroundNotification,
                      UIApplication.didBecomeActiveNotification].map { name in
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    await self?.rewind()
                }
            }
        }
        Task.detached(priority: .utility) {
            Self.discardLegacySources()
            Self.discardNonImageSources()
        }
    }

    /// The tile's content, best first: a cover that can fill this surface, then the inline minithumbnail
    /// where it is small enough to be worth showing, then nothing — where the gradient takes over.
    /// "Nothing" is a promise this used to break: only the asking paths (`load`, `prefetch`, the foreground
    /// re-warm) knew how to turn bytes on the phone back into a tile, so a surface that merely read went
    /// flat and stayed flat. The read now heals itself off the disk, the only arrangement that does not
    /// depend on somebody having remembered to ask.
    func image(for track: any Playable, side points: CGFloat = 60) -> UIImage? {
        if let image = sharp(for: track, side: points) { return image }
        return mini(for: track, side: points)
    }

    /// A picture that is not a song's — the cover a user chose for a list — read from the file it was
    /// written to and kept in the same cache, because a list row redraws on every scroll. A path names one
    /// picture for its whole life: a new choice is a new file, so nothing here needs invalidating.
    func image(at path: String) -> UIImage? {
        let key = Self.pathKey(path)
        if let image = held(key) { return image }
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        hold(image, forKey: key)
        return image
    }

    /// A cover at this surface's own size, or the biggest the phone holds for it: the art read out of the
    /// song, then the file TDLib fetched. The song's own art is asked for at *this* tier or a bigger one and
    /// only then borrowed down — a 192 px tile is not the same promise on a 768 px hero — while a server
    /// thumbnail may be borrowed at any size, because the pipeline that fetches it already asks for the
    /// biggest version there is. A tier that is not held still books its own decode before anything is
    /// borrowed: returning the stopgap and stopping there is how a hero ends up permanently soft.
    func sharp(for track: any Playable, side points: CGFloat = 60) -> UIImage? {
        let pixels = Self.pixels(forSide: points)
        if let embedded = fileArtAtLeast(uniqueId: track.uniqueId, than: pixels) { return embedded }
        if let cover = Self.token(for: track),
           let image = atLeast(cover, than: pixels) ?? largest(cover) {
            return image
        }
        warm(track, at: points)
        return largestFileArt(uniqueId: track.uniqueId)
    }

    /// The 40×30 the message carried, which is what a row shows until the sharp file lands — and only on a
    /// surface small enough that four pixels of tile is still four pixels of cover.
    func mini(for track: any Playable, side points: CGFloat = 60) -> UIImage? {
        // Measured against what the surface wants, not the tier it will be drawn at: the smallest tier is
        // 192, so comparing a 96 px ceiling to it would switch the placeholder off even for the 24 pt marks
        // it was made for.
        guard Self.neededPixels(forSide: points) <= Self.miniCeiling else { return nil }
        let key = Self.miniKey(uniqueId: track.uniqueId)
        if let image = held(key) { return image }
        guard let data = track.miniArtwork, let image = UIImage(data: data) else { return nil }
        hold(image, forKey: key)
        return image
    }

    /// Turning a read miss into the decode the phone can already do, without touching the network. Called
    /// from `body`, so it has to be cheap on the way in and silent on the way out: one existence check per
    /// candidate and no task at all when the phone does not hold the bytes — otherwise a song with no cover
    /// would start a decode on every frame of a scroll, find nothing, and be asked again forever.
    /// The song's own art is no longer gated on `localPath`: that field belongs to the snapshot the row is
    /// holding, not to the phone, and a song that just finished downloading has its bytes filed under its
    /// `unique_id` while the list still shows the pre-download `TdTrack`. The file's own existence is the
    /// honest question, and the cheap one. One source per ask, best first: the two candidates are two
    /// decodes of the same tier, and the first that exists is by construction the better picture.
    private func warm(_ track: any Playable, at points: CGFloat) {
        let pixels = Self.pixels(forSide: points)
        var candidates: [(key: NSString, source: URL)] = [
            (Self.fileKey(uniqueId: track.uniqueId, pixels: pixels),
             Self.fileSource(uniqueId: track.uniqueId))
        ]
        if let cover = Self.token(for: track) {
            candidates.append((Self.coverKey(cover, pixels: pixels), Self.coverSource(cover)))
        }
        for (key, source) in candidates
            where !inFlight.contains(key) && !unreadableSources.contains(key) && Self.exists(source) {
            inFlight.insert(key)
            Task { await decode(source, forKey: key, pixels: pixels) }
            break
        }
    }

    /// The decode itself, and the booking it releases either way. `put` bumps the revision, which is what
    /// makes the row that asked come back with a picture instead of waiting for someone to scroll past it.
    private func decode(_ source: URL, forKey key: NSString, pixels: Int) async {
        defer { inFlight.remove(key) }
        guard !Task.isCancelled else { return }
        guard let image = await tile(from: source, pixels: pixels) else {
            // Bounded rather than exact: these are leftovers from before the writers checked, and the launch
            // sweep deletes them anyway.
            if unreadableSources.count < 512 { unreadableSources.insert(key) }
            return
        }
        put(image, forKey: key)
    }

    /// Whether this row is showing a real cover, which is what tells the view whether to cross-fade at all.
    func isSharp(for track: any Playable, side points: CGFloat = 60) -> Bool {
        sharp(for: track, side: points) != nil
    }

    /// The biggest picture this track has, however it was obtained — the 40×30 the message carried included,
    /// since nothing better exists for some posts. A surface that blurs a cover whole or averages its colour
    /// is not reading it for detail, so a small source still tells it the artwork's colour. Tiers are walked
    /// largest first because `sharp` already takes any server thumbnail it holds, while the art read out of
    /// the song is cached one tier at a time.
    func largest(for track: any Playable) -> UIImage? {
        for tier in Self.tiers.reversed() {
            if let image = sharp(for: track, side: CGFloat(tier) / 3) { return image }
        }
        if let image = mini(for: track) { return image }
        // Same promise as `image`: whatever the phone holds the bytes of, it can show — at the smallest tier,
        // which is all a colour or a blurred wash ever needed.
        warm(track, at: CGFloat(Self.tiers.first ?? 192) / 3)
        return nil
    }

    /// Orders whatever this track still needs, at this surface's size, and stops as soon as the surface is
    /// filled. Called from a row's `.task`, so scrolling past a track orders the fetches and a row that
    /// disappears cancels its own. `via` wins over the attached downloader: a row already holds the session's.
    func load(track: any Playable, via: TdFileDownloader? = nil,
              side points: CGFloat = 60) async {
        remember(track, at: points)
        await fill(track: track, via: via, points: points)
    }

    /// Ordering the covers of a whole page before its rows are drawn: a row asks when it appears, which is a
    /// round trip paid while the user is still looking at the gap. These go into the same queue the
    /// foreground refill uses, so a screen's worth of fetches runs side by side and the tiles are on the
    /// phone before the rows are.
    /// A prefetch is *not* a record of what the user looked at, so it does not touch `recent`: a channel walk
    /// orders a page at a time — a hundred songs the screen never showed — through a list whose whole job is
    /// to say which covers the foreground refill owes the user. They also go on the *back* of the queue: the
    /// asks already waiting are the ones a finger is looking at.
    func prefetch(_ tracks: [any Playable], via: TdFileDownloader?, side points: CGFloat) {
        let asks = tracks.map { Ask(track: $0, via: via, points: points) }
        guard !asks.isEmpty else { return }
        queued.removeAll { ask in
            ask.points == points && asks.contains { $0.track.uniqueId == ask.track.uniqueId }
        }
        queued.append(contentsOf: asks)
        if queued.count > Self.queueLimit { queued.removeLast(queued.count - Self.queueLimit) }
        Task { await drain() }
    }

    /// Working through the queue with at most `fetchWidth` covers in flight. Workers pull from the front
    /// rather than being handed a slice, so an ask that turns out already cached costs a dictionary read and
    /// frees its worker for the next one at once instead of leaving a seat empty for a download.
    private func drain() async {
        guard !draining, !queued.isEmpty else { return }
        draining = true
        defer { draining = false }
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<min(Self.fetchWidth, queued.count) {
                group.addTask { await self.takeOne() }
            }
        }
    }

    private func takeOne() async {
        while let ask = queued.first {
            queued.removeFirst()
            await fill(track: ask.track, via: ask.via, points: ask.points)
        }
    }

    /// Throwing away every cached picture — memory tiles, pinned tiles and the cover bytes on disk — and
    /// reporting the room that made. Everything here is recomputable: a song's art decodes out of its
    /// container again and a Telegram thumbnail is fetched again by the row that wants it, which is what makes
    /// this the safe half of the app's storage. The picture a user chose for a list is deliberately not in
    /// this directory: it came out of their own photo library and nothing else holds a copy.
    func clearCache() -> Int64 {
        cache.removeAllObjects()
        pinned.removeAll()
        pinnedOrder.removeAll()
        pinnedBytes = 0
        recent.removeAll()
        queued.removeAll()
        // Decodes already on their way would otherwise land their tiles back into the cache this call just
        // emptied, under keys of songs the library no longer holds.
        inFlight.removeAll()
        unreadableSources.removeAll()
        retries.removeAll()
        let freed = DiskUsage.clear(Self.sourceDirectory)
        revision += 1
        return freed
    }

    /// The work of an ask, without the booking: the foreground re-warm needs exactly this half, since its
    /// asks are already booked and booking them again would move them to the back of a queue whose whole
    /// purpose is to say which cover the user is looking at. The three steps run in cost order — the song on
    /// the phone, the bytes the phone already has, then the network — and every step asks for the tier it was
    /// given *or a bigger one*: a card holding the 512 px tile has nothing to learn from a 192 px decode, and
    /// ordering one anyway spends a worker on a picture the screen will not draw.
    private func fill(track: any Playable, via: TdFileDownloader?, points: CGFloat) async {
        let pixels = Self.pixels(forSide: points)
        // The song itself first: no network, and the biggest cover Telegram ever sent for it.
        if fileArtAtLeast(uniqueId: track.uniqueId, than: pixels) == nil {
            var path = track.localPath
            // TDLib is only asked when neither the row nor the cache knows: the source file being on the phone
            // already means the container was opened once, and asking again buys nothing.
            if path == nil, !Self.exists(Self.fileSource(uniqueId: track.uniqueId)) {
                path = await onDevicePath(for: track, via: via)
            }
            await loadFileArt(uniqueId: track.uniqueId, localPath: path, pixels: pixels)
        }
        // A surface filled by the tags has no reason to fetch a server thumbnail over it, and one holding the
        // tier it asked for — or a bigger one — has nothing left to order.
        guard fileArtAtLeast(uniqueId: track.uniqueId, than: pixels) == nil else { return }
        guard let cover = Self.token(for: track) else { return }
        guard atLeast(cover, than: pixels) == nil else { return }
        let key = Self.coverKey(cover, pixels: pixels)
        // One ask per tile: without this, a row, the card it is also drawn in and the hero the same song
        // opens each fetched and decoded the identical bytes.
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        if cover.persistent, let tile = await tile(from: Self.coverSource(cover), pixels: pixels) {
            put(tile, forKey: key)
            return
        }
        // A generated cover may not have a remote identity yet. Its message is then the proof that this row
        // belongs to this song; named covers are checked by `remote.unique_id` as well.
        guard let file = TdFile(cover: track) else { return }
        let source = Self.coverSource(cover)
        guard let path = await (via ?? downloader)?.path(
            file, priority: TdFileDownloader.coverPriority
        ) else { retry(track, via: via, points: points); return }
        let image = await Task.detached(priority: .userInitiated) {
            let tile = Self.downsampled(path: path, side: pixels)
            Self.keep(path: path, as: source)
            return tile
        }.value
        guard !Task.isCancelled, let image else { return }
        put(image, forKey: key)
    }

    /// Booking one more ask for a cover that was not ready, until its tries run out. The retry goes back
    /// through the queue rather than into a task of its own: the pool decides how many covers are fetched at
    /// once, and six of them plus a screenful of rows asking again at the same moment is how a retry becomes
    /// the reason the next cover is slow.
    private func retry(_ track: any Playable, via: TdFileDownloader?, points: CGFloat) {
        guard let cover = Self.token(for: track) else { return }
        let key = Self.coverKey(cover, pixels: Self.pixels(forSide: points))
        let left = retries[key] ?? Self.coverRetries
        guard left > 0 else { return }
        retries[key] = left - 1
        queued.append(Ask(track: track, via: via, points: points))
        Task { [weak self] in
            try? await Task.sleep(for: Self.coverRetryDelay)
            await self?.drain()
        }
    }

    /// Where TDLib says this song's own file is, when the row holding it does not know yet.
    /// The downloader checks the stored number and refreshes it from the song's message if TDLib
    /// has rebuilt its database. Imported songs have no client and already know their own path.
    private func onDevicePath(for track: any Playable, via: TdFileDownloader?) async -> String? {
        guard track.fileId != 0, let files = via ?? downloader else { return nil }
        return await files.readyPath(TdFile(audio: track))
    }

    /// The cover inside the audio file, decoded off the main thread and written into the same cache
    /// the fetched covers use, so every surface that wants this song's art gets it for one read.
    ///
    /// The tag's bytes are copied out on the first read because that read is the expensive one:
    /// `AVURLAsset` has to open the whole container to find `APIC` or `covr`, which costs tens of
    /// milliseconds and was being paid again for every tier the same song is drawn at — the row's
    /// 192, the card's 512, the hero's 768. After the copy those are ImageIO reads of a file this app
    /// already knows the size of.
    private func loadFileArt(uniqueId: String, localPath: String?, pixels: Int) async {
        let key = Self.fileKey(uniqueId: uniqueId, pixels: pixels)
        guard !inFlight.contains(key) else { return }
        let source = Self.fileSource(uniqueId: uniqueId)
        let present = Self.exists(source)
        guard present || localPath != nil else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        if present {
            // The bytes on the phone first: they are the cheap half, and they are already there.
            if let tile = await tile(from: source, pixels: pixels) {
                put(tile, forKey: key)
                return
            }
            // On the phone, and ImageIO made nothing out of it. Same rule as `decode`: without the
            // record, every frame asks again for a picture that cannot come out of those bytes, and
            // the row keeps its gradient with the file that should end it sitting right there.
            guard localPath != nil else {
                if unreadableSources.count < 512 { unreadableSources.insert(key) }
                return
            }
        }
        guard let localPath, await extracted(uniqueId: uniqueId, from: localPath) else { return }
        guard !Task.isCancelled, let tile = await tile(from: source, pixels: pixels) else { return }
        put(tile, forKey: key)
    }

    /// The song's own picture, copied out of its container and onto the phone once.
    ///
    /// Keyed by the song rather than by the tier, because the expensive half — `AVURLAsset` opening a
    /// hundred-and-forty-megabyte container to find one `APIC` frame — is the same work whichever size
    /// wants it. A row at 192 and the hero at 768 asking together used to be two of those reads racing
    /// to write the same file; now the second one waits on the first and then does its own cheap
    /// ImageIO read of the bytes it left behind.
    @discardableResult
    private func extracted(uniqueId: String, from path: String) async -> Bool {
        let marker = Self.fileSourceKey(uniqueId: uniqueId)
        if let running = fileArtReads[marker] { return await running.value }
        let source = Self.fileSource(uniqueId: uniqueId)
        let read = Task.detached(priority: .userInitiated) { () -> Bool in
            if Self.exists(source) { return true }
            guard let bytes = await Self.embeddedBytes(path: path) else { return false }
            Self.write(bytes, to: source)
            return Self.exists(source)
        }
        fileArtReads[marker] = read
        defer { fileArtReads[marker] = nil }
        return await read.value
    }

    /// Booking an ask so the foreground re-warm knows what was on screen.
    private func remember(_ track: any Playable, at points: CGFloat) {
        recent.removeAll { $0.track.uniqueId == track.uniqueId && $0.points == points }
        recent.append((track, points))
        if recent.count > Self.recentLimit { recent.removeFirst(recent.count - Self.recentLimit) }
    }

    /// Refilling every surface that is still on screen after the app came back. The memory cache may
    /// have been emptied while the process was suspended; the sources were not, so this is decodes
    /// rather than downloads, and each one bumps the revision the rows redraw from.
    ///
    /// Newest ask first, which is the whole point of the order: `remember` appends, so the last entry
    /// is the cover the user is looking at and the first is whatever was scrolled past longest ago.
    /// Walked the other way — as this was — the visible hero sat behind up to forty off-screen rows,
    /// each of which had to open its own song container or wait on TDLib before the picture the user
    /// is actually staring at was decoded. That is the flat gradient filling Now Playing for two
    /// seconds on the way out of the background, and this order is what removes it.
    ///
    /// The asks go into the pool rather than being awaited one after another, which is the other half
    /// of the same complaint: forty covers fetched in series is forty round trips end to end, and at
    /// six in flight the screen the user is on is answered in a seventh of the time. They are read
    /// from a copy and left in place, not taken and cleared, so a row that asks while the pool is
    /// running cannot mutate the record of what was on screen.
    ///
    /// One refill at a time. Coming back fires both observers a frame apart, and the second would
    /// otherwise queue the same forty covers while the first is still working through them.
    private func rewind() async {
        guard !refilling else { return }
        refilling = true
        defer { refilling = false }
        queued.insert(contentsOf: recent.reversed().map {
            Ask(track: $0.track, via: nil, points: $0.points)
        }, at: 0)
        await drain()
    }

    /// A tile decoded off the bytes kept on the phone. Nothing on disk is not a failure, it is the
    /// caller's cue to go to the network.
    private func tile(from source: URL, pixels: Int) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let bytes = Self.read(source) else { return nil }
            return Self.downsampled(data: bytes, side: pixels)
        }.value
    }

    /// Writing a tile into both memory tiers and telling every surface that reads them.
    private func put(_ image: UIImage, forKey key: NSString) {
        hold(image, forKey: key)
        revision += 1
    }

    /// Writing a tile into both memory tiers, quietly.
    ///
    /// The quiet half is what `mini` and a playlist's own picture use: those are reads made inside a
    /// view's `body`, and a `revision` bump from there is a view updating itself mid-update.
    private func hold(_ image: UIImage, forKey key: NSString) {
        cache.setObject(image, forKey: key, cost: Self.bytes(of: image))
        pin(image, forKey: key)
    }

    /// Keeping this tile alive past the point the system takes `NSCache` back, and dropping the
    /// oldest pins once the budget is gone.
    ///
    /// The order is the order the covers were drawn, so what goes is what the user stopped looking at
    /// first, and a tile written twice moves to the back rather than being paid for twice. The cap is
    /// checked before anything is stored: a lone 768 px hero costs 2.3 MB and must not be rejected
    /// for that, but a tile bigger than the whole budget would empty the set and then be dropped
    /// itself, so it is not pinned at all.
    private func pin(_ image: UIImage, forKey key: NSString) {
        let cost = Self.bytes(of: image)
        guard cost > 0, cost <= Self.pinnedBudget else { return }
        if let previous = pinned[key] { pinnedBytes -= Self.bytes(of: previous) }
        pinnedOrder.removeAll { $0 == key }
        pinnedOrder.append(key)
        pinned[key] = image
        pinnedBytes += cost
        while pinnedBytes > Self.pinnedBudget, let oldest = pinnedOrder.first {
            pinnedOrder.removeFirst()
            if let dropped = pinned.removeValue(forKey: oldest) {
                pinnedBytes -= Self.bytes(of: dropped)
            }
        }
    }

    /// A tile still in memory: what `NSCache` holds, and if the system took that back while the app
    /// was in the pocket, what the pinned set is still holding.
    private func held(_ key: NSString) -> UIImage? {
        cache.object(forKey: key) ?? pinned[key]
    }

    /// The art read out of the song, at this tier or the first bigger one already decoded. A 512 px
    /// tile fills a 60 pt row and a 192 px one does not fill a hero, which is the whole difference
    /// between this and `largestFileArt`.
    private func fileArtAtLeast(uniqueId: String, than pixels: Int) -> UIImage? {
        for tier in Self.tiers where tier >= pixels {
            if let image = held(Self.fileKey(uniqueId: uniqueId, pixels: tier)) { return image }
        }
        return nil
    }

    /// The biggest art this song has in memory, however small: what a surface draws while the tier it
    /// asked for is still being decoded, because something real beats the gradient for a frame.
    private func largestFileArt(uniqueId: String) -> UIImage? {
        for tier in Self.tiers.reversed() {
            if let image = held(Self.fileKey(uniqueId: uniqueId, pixels: tier)) { return image }
        }
        return nil
    }

    /// This cover at the asked-for tier or the first bigger one already on the device. A 512 px
    /// card draws a 60 pt row perfectly, so a second decode would buy nothing but memory.
    private func atLeast(_ cover: CoverToken, than pixels: Int) -> UIImage? {
        for tier in Self.tiers where tier >= pixels {
            if let image = held(Self.coverKey(cover, pixels: tier)) {
                return image
            }
        }
        return nil
    }

    /// The biggest cover this file has, however small: what a surface falls back to when the tier
    /// it wants was never asked for, since one scaled a little still beats starting from scratch.
    private func largest(_ cover: CoverToken) -> UIImage? {
        for tier in Self.tiers.reversed() {
            if let image = held(Self.coverKey(cover, pixels: tier)) {
                return image
            }
        }
        return nil
    }

    /// What a cover is called in this cache, and whether the phone may keep it between launches.
    ///
    /// Three identities, best first. The cover's own `file_unique_id` is the exact one. When there is
    /// none — and for a `coverTypeGenerated` thumbnail there usually is none, because TDLib has not
    /// made the file yet and `fileRemoteUnknown` carries no identity — the song it was generated from
    /// is used instead: `TdTrack` refuses to exist without its own `remote.unique_id`, so every row
    /// has one, and a generated cover is derived from exactly that file. Filed under the song, the
    /// bytes can only ever be this song's picture, and they outlive the database rebuild that makes
    /// TDLib's row number worthless.
    ///
    /// That fallback is the whole of the "artwork goes back to a gradient when I leave the app and
    /// come back" complaint. Without an identity the token was `persistent: false`, which means no
    /// disk tier at all: the cover was decoded into memory, never written down, and had to be
    /// fetched from Telegram again on every relaunch — for most of a music channel's posts, which
    /// are exactly the ones whose covers are generated.
    private nonisolated static func token(for track: any Playable) -> CoverToken? {
        if let unique = track.coverUniqueId, !unique.isEmpty {
            return CoverToken(id: unique, persistent: true)
        }
        guard let fileId = track.coverFileId else { return nil }
        guard !track.uniqueId.isEmpty else {
            return CoverToken(id: "db:\(fileId)", persistent: false)
        }
        return CoverToken(id: "gen:\(track.uniqueId)", persistent: true)
    }

    private nonisolated static func coverKey(_ cover: CoverToken, pixels: Int) -> NSString {
        "c:\(cover.id):\(pixels)" as NSString
    }

    private static func pathKey(_ path: String) -> NSString {
        "p:\(path)" as NSString
    }

    private static func fileKey(uniqueId: String, pixels: Int) -> NSString {
        "a:\(uniqueId):\(pixels)" as NSString
    }

    /// The key of a song's own art with no tier on the end, which is what the source file is called
    /// by too: the bytes out of the container answer every size.
    private nonisolated static func fileSourceKey(uniqueId: String) -> NSString {
        "a:\(uniqueId)" as NSString
    }

    private static func miniKey(uniqueId: String) -> NSString {
        "m:\(uniqueId)" as NSString
    }

    private static func bytes(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    /// The `APIC` frame of an MP3 and the `covr` atom of an M4A are what Telegram's own player
    /// draws, and they are bigger than every thumbnail the server has: the bot uploaded the cover
    /// with the song. Read through `AVFoundation` rather than by hand, because the two formats the
    /// channel posts (`audio/mpeg` and `audio/mp4`) keep the picture in two different places.
    ///
    /// The bytes rather than a picture, because the bytes are what is worth keeping: one file then
    /// answers every tier, at the resolution the bot posted it.
    private nonisolated static func embeddedBytes(path: String) async -> Data? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        guard let item = AVMetadataItem.metadataItems(
            from: metadata, filteredByIdentifier: .commonIdentifierArtwork
        ).first else { return nil }
        // `load(.dataValue)` rather than reading `item.dataValue`: the property accessors were
        // deprecated in iOS 16, and here a deprecated read is a build failure. The value has to be
        // loaded asynchronously anyway — for an item whose metadata is not resolved yet the property
        // would answer nil.
        guard let data = try? await item.load(.dataValue) else { return nil }
        return data.isEmpty ? nil : data
    }

    // MARK: The sources on disk

    /// A cover's own bytes, kept between launches.
    ///
    /// Deliberately not in `Library/Caches` any more: that is the one place iOS is allowed to empty
    /// while the app is not running, and it is what made a trip to another app cost every picture in
    /// the library — the memory tiers were gone, and so was the disk tier that was supposed to answer
    /// for them, so each cover had to come back from Telegram. Application Support is left alone, and
    /// what the system gets instead is a directory excluded from the backup: every file in it is a
    /// copy of something the phone can fetch again.
    nonisolated static let sourceDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Doni/Cover Cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var excluded = url
        try? excluded.setResourceValues(values)
        return url
    }()

    /// Throwing away every cover byte this app has ever kept, once, on the first launch that knows
    /// how to check them.
    ///
    /// Each of those files was written by a pipeline that asked TDLib by row number and filed
    /// whatever came back under the song's own name, so any one of them may be a different song's
    /// picture, and nothing about the bytes says which. They are all recomputable — a tag art is read
    /// out of its container again and a Telegram thumbnail is fetched again by the row that wants it,
    /// which is the same price the cache already pays for a cover nobody has looked at yet — so the
    /// honest repair is to start the directory empty. The flag makes it once, because the files the
    /// verified pipeline writes after it are its own.
    ///
    /// The contents go rather than the directory: the directory carries the backup exclusion, and
    /// `Application Support/Doni/Covers` — the same name in a place this cache must never touch — is
    /// the pictures a user chose for their own lists, whose only copy is the file this app wrote.
    private nonisolated static func discardUnverifiedSources() {
        let settled = "local.doni.coverSources.verified"
        guard !UserDefaults.standard.bool(forKey: settled) else { return }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: sourceDirectory, includingPropertiesForKeys: nil
        )) ?? []
        for file in files { try? FileManager.default.removeItem(at: file) }
        UserDefaults.standard.set(true, forKey: settled)
    }

    /// The two cache directories this one replaced, both under `Library/Caches`: the first was named
    /// for a hash of TDLib's row number, so some of its files are the picture of a different song
    /// than the one that would now ask for them, and none can be found again under the new name; the
    /// second is where the bytes lived until they moved out of a directory the system empties on its
    /// own. Both are deleted on the way in rather than left to age out of the budget, because leaving
    /// them means leaving the wrongness, the space, or both.
    ///
    /// Not in here: `Application Support/Doni/Covers`, which is the same name in a directory this
    /// cache must never touch — those are the pictures a user chose for their own lists, and the only
    /// copy of each one is the file this app wrote.
    private nonisolated static func discardLegacySources() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        for name in ["Doni/Covers", "Doni/Cover Sources"] {
            try? FileManager.default.removeItem(
                at: caches.appendingPathComponent(name, isDirectory: true)
            )
        }
    }

    /// Throwing away the sources that were filed before the writers learned to check what they were
    /// storing. They cost the storage the cache is meant to save, and they poison the read path: a
    /// row that finds one of these on the phone asks for it again on every frame for a picture that
    /// cannot come out of it.
    private nonisolated static func discardNonImageSources() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: sourceDirectory, includingPropertiesForKeys: nil
        )) ?? []
        for file in files where !isImage(read(file) ?? Data()) {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// A file per cover, named for a hash of the cache key: a key carries a colon and, for a
    /// playlist's own picture, a whole path, and neither belongs in a filename. The source is keyed
    /// without a tier, because the bytes answer every tier.
    private nonisolated static func coverSource(_ cover: CoverToken) -> URL {
        sourceURL("c:\(cover.id)")
    }

    private nonisolated static func fileSource(uniqueId: String) -> URL {
        sourceURL("a:\(uniqueId)")
    }

    private nonisolated static func sourceURL(_ key: String) -> URL {
        let name = SHA256.hash(data: Data(key.utf8)).prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        return sourceDirectory.appendingPathComponent("\(name).img")
    }

    /// Whether the phone holds this cover's bytes. Cheaper than trying to read them, because the
    /// answer is needed on the read path rather than the decode.
    private nonisolated static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private nonisolated static func read(_ url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return data.isEmpty ? nil : data
    }

    /// Writing once, and only if these bytes are a picture.
    ///
    /// Both writers here take their bytes from something else's idea of artwork — the file TDLib
    /// fetched, and whatever the song's own metadata reported as `APIC` — and a real library turned
    /// up with a 3,6 MB MP3 filed as a cover. That is worse than filing nothing: a source that
    /// exists but decodes to no image makes every surface reading it try again on every frame and
    /// never show anything, which is the "this song's cover never comes" half of the complaint.
    private nonisolated static func write(_ data: Data, to url: URL) {
        guard isImage(data), !FileManager.default.fileExists(atPath: url.path) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Whether ImageIO finds at least one image in these bytes.
    private nonisolated static func isImage(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else { return false }
        return true
    }

    /// The same, from a file TDLib has already put on the phone. Copying it here is what makes the
    /// cover outlive TDLib's own pruning of the big caches.
    private nonisolated static func keep(path: String, as url: URL) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path),
                                   options: .mappedIfSafe) else { return }
        write(data, to: url)
    }

    private nonisolated static func downsampled(path: String, side: Int) -> UIImage? {
        let url = URL(fileURLWithPath: path)
        let read: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, read as CFDictionary) else {
            return nil
        }
        return downsampled(source: source, side: side)
    }

    private nonisolated static func downsampled(data: Data, side: Int) -> UIImage? {
        let read: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, read as CFDictionary) else {
            return nil
        }
        return downsampled(source: source, side: side)
    }

    /// Scaling while reading rather than after: `kCGImageSourceThumbnailMaxPixelSize` only means
    /// anything to `CGImageSourceCreateThumbnailAtIndex`, which is the call that used to be missing
    /// — the three keys were being handed to `CGImageSourceCreateImageAtIndex`, which ignores them
    /// and decoded every cover whole. A 1400 px tag cover read whole is about 7.8 MB of bitmap where
    /// the row only wanted 192 px — some 147 KB — and a scrolling list does that once per row.
    ///
    /// The tier is then clamped to the source's own longest side, because inventing pixels is the
    /// other half of the complaint: a 320 px thumbnail asked for at 512 comes back the same picture
    /// with more of it smeared.
    private nonisolated static func downsampled(source: CGImageSource, side: Int) -> UIImage? {
        guard CGImageSourceGetCount(source) > 0 else { return nil }
        let native = widestSide(of: source)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: native > 0 ? min(side, native) : side
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }

    /// The source's own longest side, in pixels — 0 when ImageIO will not say.
    private nonisolated static func widestSide(of source: CGImageSource) -> Int {
        guard let raw = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (raw[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (raw[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else { return 0 }
        return max(width, height)
    }
}

/// What one song's cover is called, and whether the phone may keep it between launches.
///
/// `cover_file_id` is TDLib's row number in whichever database made it (`td_api.tl:326`), so it
/// means a different file after the library has been rebuilt — while the pictures this app keeps in
/// its own cache directory outlive that rebuild by a long way. Filed under the number, one song is
/// handed another song's picture, which is the artwork mismatch being reported. `file_unique_id` is
/// MTProto's name for the same bytes in every database on every device, so it is what every memory
/// key and every source file here is built from.
///
/// A row whose cover has no identity of its own is filed under the song instead, because a
/// generated thumbnail is derived from that one file and the song's own `unique_id` is never
/// missing. Only a row with neither — which the store does not keep — falls back to the number, and
/// for it `persistent` is false: those bytes neither come off the disk nor go back to it.
private struct CoverToken: Equatable {
    let id: String
    let persistent: Bool
}
