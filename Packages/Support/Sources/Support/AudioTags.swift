import AVFoundation
import Foundation

/// What an audio file says about itself.
///
/// A Telegram post brings its title and artist in the schema (`td_api.tl:583` has both, and a bot
/// that posts a bare file puts them in the caption). A file the user picks out of the Files app
/// brings nothing until its container is opened, and this is the one read that gets them: the same
/// `APIC`/`©nam` pass the cover is read through, resolved without decoding any audio.
public struct AudioTags: Equatable, Sendable {
    public var title: String
    public var performer: String

    public init(title: String = "", performer: String = "") {
        self.title = title
        self.performer = performer
    }

    /// A song with nothing written in it. The caller falls back to the file's own name the way a
    /// captionless channel post does, so an empty answer is a normal one rather than a failure.
    public var isEmpty: Bool { title.isEmpty && performer.isEmpty }

    /// The tags of a file on the device, or empty when the container has none — or will not open,
    /// which is the same answer as far as a row is concerned.
    public static func read(path: String) async -> AudioTags {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let items = try? await asset.load(.commonMetadata) else { return AudioTags() }
        return AudioTags(title: await text(.commonIdentifierTitle, in: items),
                         performer: await text(.commonIdentifierArtist, in: items))
    }

    /// The first item carrying this identifier, asked for its string.
    ///
    /// `load(.stringValue)` rather than reading `item.value`: the property accessors were deprecated
    /// in iOS 16, and an item whose metadata has not been resolved yet answers nil through them.
    private static func text(_ identifier: AVMetadataIdentifier,
                             in items: [AVMetadataItem]) async -> String {
        guard let item = AVMetadataItem.metadataItems(
            from: items, filteredByIdentifier: identifier
        ).first else { return "" }
        return (try? await item.load(.stringValue)) ?? ""
    }
}
