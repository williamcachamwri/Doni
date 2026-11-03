import Foundation
import ImageIO
import TdSession
import UIKit

/// The cover art a row shows, at the size the row actually draws.
///
/// `minithumbnail` is 40×30 and that is why the list looked blurred: a 54 pt tile on a 3× screen
/// wants 162 pixels, and Telegram sends a 600×600 `external_album_covers` entry for every track in
/// the channel (`td_api.tl:583`). So the sharp file is asked for by id, pulled through TDLib at
/// cover priority, and downsampled on a background thread before it is ever handed to a layer.
@MainActor
final class CoverArtwork: ObservableObject {
    /// 54 pt at @3x — `TelegramLibraryMetrics.artSide` times the scale the tile is drawn on.
    static let pixelSide = 162

    /// Bumped whenever a tile can be drawn, so the list re-reads the cache.
    @Published private(set) var revision = 0

    /// One cache for the app: the list, the mini player and the lock screen all want the same
    /// 162 px bitmap for the same cover.
    static let shared = CoverArtwork()

    private let cache = NSCache<NSNumber, UIImage>()
    private var miniDecoded: [String: UIImage] = [:]

    init() {
        // A 162 px square is about 105 KB; 240 of them is the whole library at 25 MB, and a
        // screenful is twenty rows.
        cache.countLimit = 240
    }

    /// The tile's content, best first: the downloaded cover, then the inline minithumbnail,
    /// then nothing, which is where the gradient takes over.
    func image(for track: TdTrack) -> UIImage? {
        if let id = track.coverFileId, let sharp = cache.object(forKey: NSNumber(value: id)) {
            return sharp
        }
        return miniImage(for: track)
    }

    /// Whether this row is showing the sharp cover, which is what tells the view whether to
    /// cross-fade at all.
    func isSharp(for track: TdTrack) -> Bool {
        guard let id = track.coverFileId else { return false }
        return cache.object(forKey: NSNumber(value: id)) != nil
    }

    /// Asks TDLib for the cover and decodes it off the main thread. Called from a row's
    /// `.task`, so scrolling past a track is what orders the fetches and a row that disappears
    /// cancels its own.
    func load(track: TdTrack, via downloader: TdFileDownloader?) async {
        guard let coverFileId = track.coverFileId,
              cache.object(forKey: NSNumber(value: coverFileId)) == nil
        else { return }
        guard let path = await downloader?.path(fileId: coverFileId,
                                                priority: TdFileDownloader.coverPriority)
        else { return }
        let side = Self.pixelSide
        let image = await Task.detached(priority: .userInitiated) {
            Self.downsampled(path: path, side: side)
        }.value
        guard !Task.isCancelled, let image else { return }
        cache.setObject(image, forKey: NSNumber(value: coverFileId))
        revision += 1
    }

    /// The 40×30 JPEG the message itself carried (`td_api.tl:361`), decoded once per track. It is
    /// soft at 54 pt, which is exactly why it is the fallback and not the plan.
    private func miniImage(for track: TdTrack) -> UIImage? {
        guard let data = track.miniArtwork else { return nil }
        if let held = miniDecoded[track.uniqueId] { return held }
        guard let image = UIImage(data: data) else { return nil }
        miniDecoded[track.uniqueId] = image
        return image
    }

    /// Decoding a 600×600 cover whole costs more memory and time than a row can justify, so
    /// ImageIO scales it while reading: `kCGImageSourceThumbnailMaxPixelSize` with
    /// `CreateThumbnailFromImageAlways` gives a real 162 px bitmap rather than a layer that is
    /// told to draw small.
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
