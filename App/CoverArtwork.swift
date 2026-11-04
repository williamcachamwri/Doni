import AVFoundation
import CryptoKit
import Foundation
import ImageIO
import Support
import TdSession
import UIKit

/// The cover art a surface shows, decoded at the size that surface actually draws.
///
/// There are three covers to choose between, and the old pipeline looked at only the worst-served
/// one of them:
///
/// * **The song's own tags.** A downloaded MP3 or M4A carries its album cover inside it, usually far
///   bigger than anything the server thumbed for it, and that is the artwork Telegram's own player
///   shows. It needs no download, so it is the first thing asked for on any track the phone already
///   holds.
/// * **TDLib's cover file** (`TdTrack.coverFileId`): a real thumbnail on the server, 320 px on the
///   measured channel's 112 audios that have one, or a generated 600 px cover on those that do not.
/// * **The `minithumbnail` the message carries**: 40×30 (`td_api.tl:361`), a few hundred bytes of
///   JPEG. It is a placeholder, not artwork, and it is what made the whole list look smeared — a 40
///   px tile drawn across a 166 pt shelf card is a 12× upscale.
///
/// The third is therefore only allowed on the smallest tier: rows, bubbles and the strip are drawn
/// from arm's length and forgive it, while a card or a hero is not, and shows Telegram's gradient
/// until something real arrives.
///
/// Three levels hold the result, because none of them alone survives a phone. `NSCache` is process
/// memory, and iOS empties it as soon as a backgrounded app is asked for room back — which is why
/// every cover used to be missing on the way out of Now Playing. The last screens' tiles are
/// therefore *also* held in a plain byte-capped dictionary, which is the one thing here the system
/// cannot take back on its own. Underneath both sits a directory of the cover's **own bytes**: the
/// tag's JPEG, the server's thumbnail, copied once and then decoded at whatever tier a surface next
/// asks for. Nothing is re-encoded, so the quality is the channel's rather than a copy of a copy,
/// and nothing is re-fetched, so the second time a cover appears it costs one ImageIO read instead of
/// one round trip.
@MainActor
final class CoverArtwork: ObservableObject {
    /// The pixel sides a cover is decoded at, smallest first. A surface takes the smallest tier
    /// that still covers its own pixels — 60 pt rows and the 40 pt strip land in the first, the
    /// 154/166 pt cards in the second, and anything hero-sized in the last.
    static let tiers = [192, 512, 768]

    /// The tier the 40×30 minithumbnail is allowed to fill. Past it the upscale is the blur the
    /// user is reporting, and the gradient is the better picture.
    private static let miniCeiling = tiers[0]

    /// The tier a surface of this point size is drawn at. Three is this app's own screen scale:
    /// Doni is a portrait iPhone and `UIScreen.main.scale` is on its way out of the SDK.
    static func pixels(forSide points: CGFloat) -> Int {
        let needed = Int((points * 3).rounded(.up))
        return tiers.first { $0 >= needed } ?? tiers[tiers.count - 1]
    }

    /// Bumped whenever a tile can be drawn, so the list re-reads the cache.
    @Published private(set) var revision = 0

    /// One cache for the app: the list, the cards, the mini player and the lock screen all want
    /// the same cover, though not at the same size.
    static let shared = CoverArtwork()

    /// Kept so the surfaces that hold only this object — the player, the hero — can order a cover
    /// of their own, at their own size, instead of living off whatever a row fetched.
    var downloader: TdFileDownloader?

    private let cache = NSCache<NSString, UIImage>()

    /// The last few dozen tiles, held outside `NSCache` where the system cannot take them back.
    ///
    /// This is the whole of the "artwork vanishes when I leave and come back" complaint. `NSCache`
    /// is the app's own memory and iOS empties it the moment a suspended app is asked for room —
    /// which is precisely the moment the user is about to look at again, so the list, the strip and
    /// Now Playing all went back to the flat gradient while the phone was in the pocket, and every
    /// cover had to be decoded again before anything could be drawn. The same `UIImage`s are kept
    /// alive here for the covers the last screens actually wore, and because it is a hard cap rather
    /// than a limit the OS may ignore, the byte budget below is what keeps this from ever being the
    /// reason the app is killed.
    private var pinned: [NSString: UIImage] = [:]

    /// The pinned keys, oldest first — a dictionary has no order, and the set needs to drop what was
    /// looked at longest ago rather than an arbitrary member of it.
    private var pinnedOrder: [NSString] = []

    private var pinnedBytes = 0

    /// The surfaces that have asked since the app was last in front, oldest first. Coming back from
    /// the background refills exactly these: a SwiftUI `.task` that is still on screen does not run
    /// again, so without this a row would go on drawing a gradient over a cache the system emptied.
    private var recent: [(track: any Playable, points: CGFloat)] = []

    /// Asks waiting for the pool, the one the user is looking at first.
    private var queued: [Ask] = []

    /// Whether a pool is already working through `queued`. Starting a second one would only put
    /// more workers on the same list, and the width below is the point of the exercise.
    private var draining = false

    /// Tiles whose bytes are on their way. A row, a shelf card and the Now Playing hero all want the
    /// same picture at different sizes, and before this each of them opened its own download of the
    /// same file and its own decode of the same bytes.
    private var inFlight: Set<NSString> = []

    /// One surface's ask, which is what the pool carries.
    private struct Ask {
        let track: any Playable
        let via: TdFileDownloader?
        let points: CGFloat
    }

    /// How many covers are worked on at once.
    ///
    /// TDLib queues its own downloads and a cover is tens of kilobytes, so this is not a limit on
    /// the network — it is a limit on how many decodes and how many file waits the app puts on the
    /// phone at a time. Six is enough to fill a screen at once, and it is far below the number of
    /// rows that ask, so the queue in front of it is what does the ordering.
    private static let fetchWidth = 6

    /// The re-warms, held so the singleton keeps both of its observers alive.
    private var foreground: [Task<Void, Never>] = []

    /// Whether a refill is already on the way. Coming back fires `willEnterForeground` and then
    /// `didBecomeActive` a frame apart, and the second would otherwise start the same decodes again
    /// while the first is still running.
    private var refilling = false

    /// How many asks are worth remembering. A flick through a thousand-row list is not a request to
    /// hold a thousand rows; the last screens the user actually looked at are what matter.
    private static let recentLimit = 40

    /// 8 MB of pinned tiles. A 192 px row tile is 147 KB, so this is some fifty-five of them — the
    /// four screens a phone can be looking at at once — and a 768 px hero is 2.3 MB of it, so the
    /// byte cap, not the count, is what decides.
    private static let pinnedBudget = 8 * 1024 * 1024

    init() {
        // Costed by bytes, not by count: a 192 px tile is 147 KB and a 768 px hero is 2.3 MB, and a
        // flat count would either starve the list or let a handful of heroes walk past the
        // process's memory. 64 MB is a couple of hundred rows and a roomful of cards.
        cache.totalCostLimit = 64 * 1024 * 1024
        // Two hooks rather than one. `willEnterForeground` is the earlier of the pair and lands
        // before anything here is drawn again, so the covers are already decoding while the system's
        // snapshot is still on the screen; `didBecomeActive` is the one that also fires on a cold
        // launch and after a system dialog, where the first of the two never arrives.
        foreground = [UIApplication.willEnterForegroundNotification,
                      UIApplication.didBecomeActiveNotification].map { name in
            Task { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    await self?.rewind()
                }
            }
        }
        // The directory outlives the process, so it is the one thing here that needs a budget of its
        // own: `Library/Caches` is only pruned when the system feels like it.
        Task.detached(priority: .utility) {
            Self.discardLegacySources()
            Self.trimSources()
        }
    }

    /// The tile's content, best first: a cover that can fill this surface, then the inline
    /// minithumbnail where it is small enough to still be worth showing, then nothing — which is
    /// where the gradient takes over.
    func image(for track: any Playable, side points: CGFloat = 60) -> UIImage? {
        sharp(for: track, side: points) ?? mini(for: track, side: points)
    }

    /// A picture that is not a song's — the cover a user chose for a list — read from the file it was
    /// written to and kept in the same cache, because a list row redraws on every scroll and the
    /// decode is the part worth not doing twice. A path names one picture for its whole life: a new
    /// choice is a new file, so nothing here has to be invalidated.
    func image(at path: String) -> UIImage? {
        let key = Self.pathKey(path)
        if let image = held(key) { return image }
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        hold(image, forKey: key)
        return image
    }

    /// A cover at this surface's own size, or the biggest one the phone holds for it: the art read
    /// out of the song, then the file TDLib fetched.
    func sharp(for track: any Playable, side points: CGFloat = 60) -> UIImage? {
        let pixels = Self.pixels(forSide: points)
        if let embedded = fileArt(of: track, pixels: pixels) { return embedded }
        guard let cover = Self.token(for: track) else { return nil }
        return atLeast(cover, than: pixels) ?? largest(cover)
    }

    /// The 40×30 the message carried, which is what a row shows until the sharp file lands — and
    /// only on a surface small enough that four pixels of tile is still four pixels of cover.
    func mini(for track: any Playable, side points: CGFloat = 60) -> UIImage? {
        guard Self.pixels(forSide: points) <= Self.miniCeiling else { return nil }
        let key = Self.miniKey(uniqueId: track.uniqueId)
        if let image = held(key) { return image }
        guard let data = track.miniArtwork, let image = UIImage(data: data) else { return nil }
        hold(image, forKey: key)
        return image
    }

    /// Whether this row is showing a real cover, which is what tells the view whether to cross-fade
    /// at all.
    func isSharp(for track: any Playable, side points: CGFloat = 60) -> Bool {
        sharp(for: track, side: points) != nil
    }

    /// The biggest picture this track has, however it was obtained — the 40×30 the message carried
    /// included, since nothing better exists for some posts.
    ///
    /// A surface that blurs a cover whole or averages its colour is not reading it for detail, so
    /// a small source still tells it the artwork's colour, which is more than a gradient does. The
    /// tiers are walked largest first because `sharp` already takes any server thumbnail it holds,
    /// while the art read out of the song is cached one tier at a time.
    func largest(for track: any Playable) -> UIImage? {
        for tier in Self.tiers.reversed() {
            if let image = sharp(for: track, side: CGFloat(tier) / 3) { return image }
        }
        return mini(for: track)
    }

    /// Orders whatever this track still needs, at this surface's size, and stops as soon as the
    /// surface is filled. Called from a row's `.task`, so scrolling past a track is what orders the
    /// fetches and a row that disappears cancels its own. `via` wins over the attached downloader,
    /// because a row already holds the session's.
    func load(track: any Playable, via: TdFileDownloader? = nil,
              side points: CGFloat = 60) async {
        remember(track, at: points)
        await fill(track: track, via: via, points: points)
    }

    /// Ordering the covers of a whole page before its rows are drawn.
    ///
    /// A row asks when it appears, which is a round trip paid while the user is still looking at the
    /// gap. These go into the same queue the foreground refill uses, so a screen's worth of fetches
    /// runs side by side instead of one per row, and the tiles are on the phone before the rows are.
    /// An ask that is already answered costs one dictionary read, so warming a list a row has already
    /// reached is free.
    func prefetch(_ tracks: [any Playable], via: TdFileDownloader?, side points: CGFloat) {
        let asks = tracks.map { Ask(track: $0, via: via, points: points) }
        guard !asks.isEmpty else { return }
        queued.removeAll { ask in
            ask.points == points && asks.contains { $0.track.uniqueId == ask.track.uniqueId }
        }
        for ask in asks { remember(ask.track, at: points) }
        queued.insert(contentsOf: asks, at: 0)
        Task { await drain() }
    }

    /// Working through the queue with at most `fetchWidth` covers in flight.
    ///
    /// The workers pull from the front rather than being handed a slice of it, so an ask that turns
    /// out to be cached already costs a dictionary read and frees its worker for the next one at
    /// once, instead of leaving a seat empty for the length of a download.
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

    /// Throwing away every cached picture — the tiles in memory, the pinned ones, and the cover
    /// bytes on disk — and reporting the room that made.
    ///
    /// Everything here is recomputable: a song's own art is decoded out of its container again and a
    /// Telegram thumbnail is fetched again by the row that wants it. That is what makes this the safe
    /// half of the app's storage. The picture a user chose for a list is deliberately not in this
    /// directory: that file is theirs, it came out of their own photo library, and nothing else on
    /// the phone holds a copy.
    func clearCache() -> Int64 {
        cache.removeAllObjects()
        pinned.removeAll()
        pinnedOrder.removeAll()
        pinnedBytes = 0
        recent.removeAll()
        queued.removeAll()
        let freed = DiskUsage.clear(Self.sourceDirectory)
        revision += 1
        return freed
    }

    /// The work of an ask, without the booking. The foreground re-warm needs exactly this half: it is
    /// refilling asks that were already booked, and booking them again would move them to the back of
    /// a queue whose whole purpose is to say which cover the user is looking at.
    ///
    /// The three steps are in order of what they cost: the song on the phone, the bytes the phone has
    /// already fetched, and only then the network.
    private func fill(track: any Playable, via: TdFileDownloader?, points: CGFloat) async {
        let pixels = Self.pixels(forSide: points)
        // The song itself first: no network, and the biggest cover Telegram ever sent for it.
        if track.localPath != nil, fileArt(of: track, pixels: pixels) == nil {
            await loadFileArt(of: track, pixels: pixels)
        }
        guard let cover = Self.token(for: track) else { return }
        // A surface already filled by the tags has no reason to fetch a server thumbnail over it,
        // and one that holds the tier it asked for has nothing left to order.
        if fileArt(of: track, pixels: pixels) != nil { return }
        guard atLeast(cover, than: pixels) == nil else { return }
        let key = Self.coverKey(cover, pixels: pixels)
        // One ask per tile. Without this, a row, the card it is also drawn in and the hero the same
        // song opens each fetched and decoded the identical bytes.
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        if cover.persistent, let tile = await tile(from: Self.coverSource(cover), pixels: pixels) {
            put(tile, forKey: key)
            return
        }
        guard let fileId = track.coverFileId else { return }
        // `nil` when this cover only has a database row number to be called by: there is then no
        // safe name to file its bytes under, so it is fetched again next time rather than kept.
        let source: URL? = cover.persistent ? Self.coverSource(cover) : nil
        guard let path = await (via ?? downloader)?.path(
            fileId: fileId, priority: TdFileDownloader.coverPriority
        ) else { return }
        let image = await Task.detached(priority: .userInitiated) {
            let tile = Self.downsampled(path: path, side: pixels)
            if let source { Self.keep(path: path, as: source) }
            return tile
        }.value
        guard !Task.isCancelled, let image else { return }
        put(image, forKey: key)
    }

    /// The cover inside the audio file, decoded off the main thread and written into the same cache
    /// the fetched covers use, so every surface that wants this song's art gets it for one read.
    ///
    /// The tag's bytes are copied out on the first read because that read is the expensive one:
    /// `AVURLAsset` has to open the whole container to find `APIC` or `covr`, which costs tens of
    /// milliseconds and was being paid again for every tier the same song is drawn at — the row's
    /// 192, the card's 512, the hero's 768. After the copy those are ImageIO reads of a file this app
    /// already knows the size of.
    private func loadFileArt(of track: any Playable, pixels: Int) async {
        guard let path = track.localPath else { return }
        let key = Self.fileKey(uniqueId: track.uniqueId, pixels: pixels)
        // The container read is the expensive one, so it is asked for once per song per tier — a
        // shelf, a row and the hero of the same file are three surfaces and one `AVURLAsset`.
        guard !inFlight.contains(key) else { return }
        inFlight.insert(key)
        defer { inFlight.remove(key) }
        let source = Self.fileSource(uniqueId: track.uniqueId)
        if let tile = await tile(from: source, pixels: pixels) {
            put(tile, forKey: key)
            return
        }
        let image: UIImage? = await Task.detached(priority: .userInitiated) {
            guard let bytes = await Self.embeddedBytes(path: path) else { return nil }
            Self.write(bytes, to: source)
            return Self.downsampled(data: bytes, side: pixels)
        }.value
        guard !Task.isCancelled, let image else { return }
        put(image, forKey: key)
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

    /// The cover read out of the song itself, if this surface's tier of it is already on the phone.
    private func fileArt(of track: any Playable, pixels: Int) -> UIImage? {
        held(Self.fileKey(uniqueId: track.uniqueId, pixels: pixels))
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

    /// What a cover is called in this cache.
    private nonisolated static func token(for track: any Playable) -> CoverToken? {
        if let unique = track.coverUniqueId, !unique.isEmpty {
            return CoverToken(id: unique, persistent: true)
        }
        guard let fileId = track.coverFileId else { return nil }
        return CoverToken(id: "db:\(fileId)", persistent: false)
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

    /// A cover's own bytes, kept between launches. `Library/Caches` because that is exactly what this
    /// is: every file here can be fetched or read out of the song again, and the system is allowed to
    /// take the space back. Nothing is written outside the phone.
    nonisolated static var sourceDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Doni/Covers", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// The directory this cache used before covers were named for a `file_unique_id`.
    ///
    /// Its files were named for a hash of TDLib's row number, so two things are true of them: some
    /// are the picture of a different song than the one that would now ask for them, and none can be
    /// found again under the new name. They are deleted on the way in rather than left to age out of
    /// the budget, because leaving them means leaving both the wrongness and the space.
    private nonisolated static func discardLegacySources() {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        try? FileManager.default.removeItem(
            at: base.appendingPathComponent("Doni/Cover Sources", isDirectory: true)
        )
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

    private nonisolated static func read(_ url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        return data.isEmpty ? nil : data
    }

    /// Writing once: the file already there is the same bytes, and rewriting it would only move the
    /// date that `trimSources` prunes by.
    private nonisolated static func write(_ data: Data, to url: URL) {
        guard !data.isEmpty, !FileManager.default.fileExists(atPath: url.path) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// The same, from a file TDLib has already put on the phone. Copying it here is what makes the
    /// cover outlive TDLib's own pruning of the big caches.
    private nonisolated static func keep(path: String, as url: URL) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path),
                                   options: .mappedIfSafe) else { return }
        write(data, to: url)
    }

    /// 120 MB is a thousand covers' worth of originals. The oldest-written go first, which is roughly
    /// the order a listener stops needing them in.
    private nonisolated static let sourceBudget = 120 * 1024 * 1024

    private nonisolated static func trimSources() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: sourceDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
        )) ?? []
        var live: [(url: URL, bytes: Int, written: Date)] = []
        for file in files {
            let values = try? file.resourceValues(
                forKeys: [.fileSizeKey, .contentModificationDateKey]
            )
            live.append((file, values?.fileSize ?? 0, values?.contentModificationDate ?? .distantPast))
        }
        var kept = 0
        for entry in live.sorted(by: { $0.written > $1.written }) {
            if kept + entry.bytes > sourceBudget {
                try? FileManager.default.removeItem(at: entry.url)
            } else {
                kept += entry.bytes
            }
        }
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
/// A row indexed before the identity was recorded has only the number to go on. That still answers
/// inside this process, where the number is consistent, but `persistent` is false for it: those
/// bytes neither come off the disk nor go back to it. The next read of that channel records the
/// identity and the cover becomes storable again.
private struct CoverToken: Equatable {
    let id: String
    let persistent: Bool
}
