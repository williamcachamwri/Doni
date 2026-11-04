import Foundation
import ImageIO
import TdSession
import UIKit

/// The cover art a surface shows, decoded at the size that surface actually draws.
///
/// `minithumbnail` is 40×30, and a 60 pt tile on a 3× screen wants 180 pixels — which is why the
/// list used to look soft. Telegram sends a ~600×600 `external_album_covers` entry for every track
/// in the channel (`td_api.tl:583`), so the sharp file is asked for by id and pulled through TDLib
/// at cover priority.
///
/// It is then decoded at one of three pixel tiers rather than at one size for the whole app: the
/// same bitmap read as a 60 pt row and as a 166 pt shelf card needs 180 px once and 500 px the
/// other time, and the single 180 px tile every surface used to share is the reason the feed
/// looked blurred.
@MainActor
final class CoverArtwork: ObservableObject {
    /// The pixel sides a cover is decoded at, smallest first. A surface takes the smallest tier
    /// that still covers its own pixels — 60 pt rows and the 40 pt strip land in the first, the
    /// 154/166 pt cards in the second, and anything hero-sized in the last, which is also about
    /// the size Telegram's own cover is, so nothing is invented past it.
    static let tiers = [192, 512, 768]

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
    private var miniDecoded: [String: UIImage] = [:]

    init() {
        // Costed by bytes, not by count: a 192 px tile is 147 KB and a 768 px hero is 2.3 MB, and
        // a flat count would either starve the list or let a handful of heroes walk past the
        // process's memory. 64 MB is a couple of hundred rows and a roomful of cards.
        cache.totalCostLimit = 64 * 1024 * 1024
    }

    /// The tile's content, best first: the downloaded cover, then the inline minithumbnail,
    /// then nothing, which is where the gradient takes over.
    func image(for track: any Playable, side points: CGFloat = 60) -> UIImage? {
        sharp(for: track, side: points) ?? mini(for: track)
    }

    /// The downloaded cover alone, so a row can cross-fade it over the minithumbnail it already
    /// has on screen instead of swapping one image for another under a finger.
    func sharp(for track: any Playable, side points: CGFloat = 60) -> UIImage? {
        guard let id = track.coverFileId else { return nil }
        return atLeast(id, than: Self.pixels(forSide: points)) ?? largest(id)
    }

    /// The 40×30 the message carried, which is what a row shows until the sharp file lands.
    func mini(for track: any Playable) -> UIImage? {
        guard let data = track.miniArtwork else { return nil }
        if let held = miniDecoded[track.uniqueId] { return held }
        guard let image = UIImage(data: data) else { return nil }
        miniDecoded[track.uniqueId] = image
        return image
    }

    /// Whether this row is showing the sharp cover, which is what tells the view whether to
    /// cross-fade at all.
    func isSharp(for track: any Playable, side points: CGFloat = 60) -> Bool {
        sharp(for: track, side: points) != nil
    }

    /// Asks TDLib for the cover and decodes it off the main thread. Called from a row's `.task`,
    /// so scrolling past a track is what orders the fetches and a row that disappears cancels its
    /// own. `via` wins over the attached downloader, because a row already holds the session's.
    func load(track: any Playable, via: TdFileDownloader? = nil,
              side points: CGFloat = 60) async {
        guard let coverFileId = track.coverFileId else { return }
        let pixels = Self.pixels(forSide: points)
        guard atLeast(coverFileId, than: pixels) == nil else { return }
        guard let path = await (via ?? downloader)?.path(
            fileId: coverFileId, priority: TdFileDownloader.coverPriority
        ) else { return }
        let image = await Task.detached(priority: .userInitiated) {
            Self.downsampled(path: path, side: pixels)
        }.value
        guard !Task.isCancelled, let image else { return }
        cache.setObject(image, forKey: Self.key(fileId: coverFileId, pixels: pixels),
                        cost: Self.bytes(of: image))
        revision += 1
    }

    /// This cover at the asked-for tier or the first bigger one already on the device. A 512 px
    /// card draws a 60 pt row perfectly, so a second decode would buy nothing but memory.
    private func atLeast(_ fileId: Int, than pixels: Int) -> UIImage? {
        for tier in Self.tiers where tier >= pixels {
            if let image = cache.object(forKey: Self.key(fileId: fileId, pixels: tier)) {
                return image
            }
        }
        return nil
    }

    /// The biggest cover this file has, however small: what a surface falls back to when the tier
    /// it wants was never asked for, since one scaled a little still beats the 40×30 in the message.
    private func largest(_ fileId: Int) -> UIImage? {
        for tier in Self.tiers.reversed() {
            if let image = cache.object(forKey: Self.key(fileId: fileId, pixels: tier)) {
                return image
            }
        }
        return nil
    }

    private static func key(fileId: Int, pixels: Int) -> NSString {
        "\(fileId):\(pixels)" as NSString
    }

    private static func bytes(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }

    /// Decoding a 600×600 cover whole costs more memory and time than a row can justify, so
    /// ImageIO scales it while reading: `kCGImageSourceThumbnailMaxPixelSize` with
    /// `CreateThumbnailFromImageAlways` gives a real bitmap at the tier asked for rather than a
    /// layer that is told to draw small.
    private nonisolated static func downsampled(path: String, side: Int) -> UIImage? {
        let url = URL(fileURLWithPath: path)
        let read: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, read as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: side
        ]
        guard let image = CGImageSourceCreateImageAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: image)
    }
}
