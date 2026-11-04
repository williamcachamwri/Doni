import AVFoundation
import CoreMedia
import Foundation

/// How long a song is, in whole seconds.
///
/// Telegram only says it when the post is a `messageAudio` (`td_api.tl:583` has `duration`). The
/// same song posted as a `messageDocument` (`:594`) arrives with a name, a mime type and a size and
/// nothing else — the schema has no duration there, and TDLib does not read the container to fill
/// one in. So the app measures, from the file, once the phone has it whole.
///
/// A measurement is written into the store and kept: the walk that re-reads the channel sends a
/// `NULL` duration for a document row, and the upsert's `COALESCE` leaves the number the app
/// measured alone.
public enum AudioDuration {
    /// The length of a file that is on the device.
    ///
    /// `AVURLAsset` rather than a hand-rolled parse: the file is whole here, so the answer is the
    /// container's own, and Apple's readers already know a 32-bit `mvhd` from a 64-bit one. The
    /// metadata is resolved without loading the audio, so this is a header read and not a decode.
    public static func seconds(ofPath path: String) async -> Int? {
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let time = try? await asset.load(.duration) else { return nil }
        return rounded(time)
    }

    /// Seconds, of a duration AVFoundation is confident about.
    ///
    /// Every answer that is not a number of seconds arrives here as a `CMTime` whose seconds value
    /// is NaN (an invalid time) or infinity (an indefinite one — a stream AVFoundation cannot
    /// measure), so the one check that matters is on the number rather than on the `CMTime`'s flags.
    private static func rounded(_ time: CMTime) -> Int? {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds > 0.5 else { return nil }
        return Int(seconds.rounded())
    }
}
