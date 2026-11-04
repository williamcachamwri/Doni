import AVFoundation
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

    init() {
        // Costed by bytes, not by count: a 192 px tile is 147 KB and a 768 px hero is 2.3 MB, and a
        // flat count would either starve the list or let a handful of heroes walk past the
        // process's memory. 64 MB is a couple of hundred rows and a roomful of cards.
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    /// The tile's content, best first: a cover that can fill this surface, then the inline
    /// minithumbnail where it is small enough to still be worth showing, then nothing — which is
    /// where the gradient takes over.
    func image(for track: any Playable, side points: CGFloat = 60) -> UIImage? {
        sharp(for: track, side: points) ?? mini(for: track, side: points)
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

    /// Orders whatever this track still needs, at this surface's size, and stops as soon as the
    /// surface is filled. Called from a row's `.task`, so scrolling past a track is what orders the
    /// fetches and a row that disappears cancels its own. `via` wins over the attached downloader,
    /// because a row already holds the session's.
    func load(track: any Playable, via: TdFileDownloader? = nil,
              side points: CGFloat = 60) async {
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
        guard let path = await (via ?? downloader)?.path(
            fileId: coverFileId, priority: TdFileDownloader.coverPriority
        ) else { return }
        let image = await Task.detached(priority: .userInitiated) {
            Self.downsampled(path: path, side: pixels)
        }.value
        guard !Task.isCancelled, let image else { return }
        cache.setObject(image, forKey: Self.coverKey(fileId: coverFileId, pixels: pixels),
                        cost: Self.bytes(of: image))
        revision += 1
    }

    /// The cover inside the audio file, decoded off the main thread and written into the same cache
    /// the fetched covers use, so every surface that wants this song's art gets it for one read.
    private func loadFileArt(of track: any Playable, pixels: Int) async {
        guard let path = track.localPath else { return }
        let image = await Task.detached(priority: .userInitiated) {
            await Self.embeddedCover(path: path, side: pixels)
        }.value
        guard !Task.isCancelled, let image else { return }
        cache.setObject(image, forKey: Self.fileKey(uniqueId: track.uniqueId, pixels: pixels),
                        cost: Self.bytes(of: image))
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
    private nonisolated static func embeddedCover(path: String, side: Int) async -> UIImage? {
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
        return downsampled(data: data, side: side)
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
