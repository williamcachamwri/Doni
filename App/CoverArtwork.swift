import AVFoundation
import CryptoKit
import Foundation
import ImageIO
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
/// Two levels hold the result, because one does not survive a phone. `NSCache` is process memory, and
/// iOS empties it as soon as a backgrounded app is asked for room back — which is why every cover
/// used to be missing on the way out of Now Playing. Underneath it sits a directory of the cover's
/// **own bytes**: the tag's JPEG, the server's thumbnail, copied once and then decoded at whatever
/// tier a surface next asks for. Nothing is re-encoded, so the quality is the channel's rather than a
/// copy of a copy, and nothing is re-fetched, so the second time a cover appears it costs one ImageIO
/// read instead of one round trip.
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

    /// The surfaces that have asked since the app was last in front, oldest first. Coming back from
    /// the background refills exactly these: a SwiftUI `.task` that is still on screen does not run
    /// again, so without this a row would go on drawing a gradient over a cache the system emptied.
    private var recent: [(track: any Playable, points: CGFloat)] = []

    /// The re-warm, held so the singleton keeps its observer alive.
    private var foreground: Task<Void, Never>?

    /// How many asks are worth remembering. A flick through a thousand-row list is not a request to
    /// hold a thousand rows; the last screens the user actually looked at are what matter.
    private static let recentLimit = 40

    init() {
        // Costed by bytes, not by count: a 192 px tile is 147 KB and a 768 px hero is 2.3 MB, and a
        // flat count would either starve the list or let a handful of heroes walk past the
        // process's memory. 64 MB is a couple of hundred rows and a roomful of cards.
        cache.totalCostLimit = 64 * 1024 * 1024
        foreground = Task { [weak self] in
            for await _ in NotificationCenter.default.notifications(
                named: UIApplication.didBecomeActiveNotification
            ) {
                await self?.rewind()
            }
        }
        // The directory outlives the process, so it is the one thing here that needs a budget of its
        // own: `Library/Caches` is only pruned when the system feels like it.
        Task.detached(priority: .utility) { Self.trimSources() }
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
        if let held = cache.object(forKey: key) { return held }
        guard let image = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(image, forKey: key, cost: Self.bytes(of: image))
        return image
    }

    /// A cover at this surface's own size, or the biggest one the phone holds for it: the art read
    /// out of the song, then the file TDLib fetched.
    func sharp(for track: any Playable, side points: CGFloat = 60) -> UIImage? {
        let pixels = Self.pixels(forSide: points)
        if let embedded = fileArt(of: track, pixels: pixels) { return embedded }
        guard let id = track.coverFileId else { return nil }
        return atLeast(id, than: pixels) ?? largest(id)
    }

    /// The 40×30 the message carried, which is what a row shows until the sharp file lands — and
    /// only on a surface small enough that four pixels of tile is still four pixels of cover.
    func mini(for track: any Playable, side points: CGFloat = 60) -> UIImage? {
        guard Self.pixels(forSide: points) <= Self.miniCeiling else { return nil }
        let key = Self.miniKey(uniqueId: track.uniqueId)
        if let held = cache.object(forKey: key) { return held }
        guard let data = track.miniArtwork, let image = UIImage(data: data) else { return nil }
        cache.setObject(image, forKey: key, cost: Self.bytes(of: image))
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
        guard let coverFileId = track.coverFileId else { return }
        // A surface already filled by the tags has no reason to fetch a server thumbnail over it,
        // and one that holds the tier it asked for has nothing left to order.
        if fileArt(of: track, pixels: pixels) != nil { return }
        guard atLeast(coverFileId, than: pixels) == nil else { return }
        let source = Self.coverSource(fileId: coverFileId)
        if let tile = await tile(from: source, pixels: pixels) {
            put(tile, forKey: Self.coverKey(fileId: coverFileId, pixels: pixels))
            return
        }
        guard let path = await (via ?? downloader)?.path(
            fileId: coverFileId, priority: TdFileDownloader.coverPriority
        ) else { return }
        let image = await Task.detached(priority: .userInitiated) {
            let tile = Self.downsampled(path: path, side: pixels)
            Self.keep(path: path, as: source)
            return tile
        }.value
        guard !Task.isCancelled, let image else { return }
        put(image, forKey: Self.coverKey(fileId: coverFileId, pixels: pixels))
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
    /// The asks are read from a copy and left in place, not taken and cleared: `fill` does not book,
    /// so the queue keeps saying what was on screen rather than being reordered by the re-warm itself,
    /// and a row that asks while this loop is running cannot mutate the array being walked.
    private func rewind() async {
        for entry in recent.reversed() {
            await fill(track: entry.track, via: nil, points: entry.points)
        }
    }

    /// A tile decoded off the bytes kept on the phone. Nothing on disk is not a failure, it is the
    /// caller's cue to go to the network.
    private func tile(from source: URL, pixels: Int) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            guard let bytes = Self.read(source) else { return nil }
            return Self.downsampled(data: bytes, side: pixels)
        }.value
    }

    /// Writing a tile into memory and telling every surface that reads the cache.
    private func put(_ image: UIImage, forKey key: NSString) {
        cache.setObject(image, forKey: key, cost: Self.bytes(of: image))
        revision += 1
    }

    /// The cover read out of the song itself, if this surface's tier of it is already on the phone.
    private func fileArt(of track: any Playable, pixels: Int) -> UIImage? {
        cache.object(forKey: Self.fileKey(uniqueId: track.uniqueId, pixels: pixels))
    }

    /// This cover at the asked-for tier or the first bigger one already on the device. A 512 px
    /// card draws a 60 pt row perfectly, so a second decode would buy nothing but memory.
    private func atLeast(_ fileId: Int, than pixels: Int) -> UIImage? {
        for tier in Self.tiers where tier >= pixels {
            if let image = cache.object(forKey: Self.coverKey(fileId: fileId, pixels: tier)) {
                return image
            }
        }
        return nil
    }

    /// The biggest cover this file has, however small: what a surface falls back to when the tier
    /// it wants was never asked for, since one scaled a little still beats starting from scratch.
    private func largest(_ fileId: Int) -> UIImage? {
        for tier in Self.tiers.reversed() {
            if let image = cache.object(forKey: Self.coverKey(fileId: fileId, pixels: tier)) {
                return image
            }
        }
        return nil
    }

    private static func coverKey(fileId: Int, pixels: Int) -> NSString {
        "c:\(fileId):\(pixels)" as NSString
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
    private nonisolated static var sourceDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Doni/Cover Sources", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A file per cover, named for a hash of the cache key: a key carries a colon and, for a
    /// playlist's own picture, a whole path, and neither belongs in a filename. The source is keyed
    /// without a tier, because the bytes answer every tier.
    private nonisolated static func coverSource(fileId: Int) -> URL {
        sourceURL("c:\(fileId)")
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
