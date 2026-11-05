import Foundation

/// The container names AVFoundation has to be told, keyed by the extension a Telegram file carries.
///
/// A resource loader is not a URL the player probes: answering content-information without a type gets
/// -11850 "the server is not correctly configured", which reads like a broken network and is really a
/// missing string. The list says nothing about a format iOS cannot decode — an answer here is a promise
/// that `AVPlayer` can play the bytes.
public enum AudioContentType {
    /// The uniform type identifier for an extension, `nil` when AVFoundation cannot open the container.
    /// `nil` is not "try it": a format nobody can decode cannot be streamed by ranges either, so the
    /// caller takes the whole-file path.
    public static func uti(forExtension extension_: String) -> String? {
        switch extension_.lowercased() {
        case "mp3": return "public.mp3"
        case "m4a": return "com.apple.m4a-audio"
        case "mp4": return "public.mpeg-4"
        case "aac": return "public.aac-audio"
        case "wav": return "com.microsoft.waveform-audio"
        case "aif", "aiff", "aifc": return "public.aiff-audio"
        case "flac": return "public.flac-audio"
        case "caf": return "com.apple.core-audio-format"
        // OGG Vorbis and Opus are not decodable by AVFoundation at all, on any OS version, so they
        // are named here only so that the answer is known rather than guessed at by a caller.
        case "ogg", "oga", "opus": return nil
        default: return nil
        }
    }

    /// The same question asked of a mime type, which is what a Telegram audio object carries.
    public static func uti(forMIMEType mimeType: String) -> String? {
        switch mimeType.lowercased() {
        case "audio/mpeg", "audio/mp3": return uti(forExtension: "mp3")
        case "audio/mp4", "audio/m4a", "audio/x-m4a": return uti(forExtension: "m4a")
        case "audio/aac", "audio/x-aac": return uti(forExtension: "aac")
        case "audio/wav", "audio/x-wav", "audio/wave": return uti(forExtension: "wav")
        case "audio/aiff", "audio/x-aiff": return uti(forExtension: "aiff")
        case "audio/flac", "audio/x-flac": return uti(forExtension: "flac")
        case "audio/ogg", "audio/opus", "application/ogg": return nil
        default: return nil
        }
    }

    /// Whether these bytes can be streamed at all, before any of the machinery is switched on.
    public static func isStreamable(mimeType: String, fileName: String) -> Bool {
        resolve(mimeType: mimeType, fileName: fileName) != nil
    }

    /// The container of a song, from whichever of the two the row actually carries.
    ///
    /// The mime type first, because a channel's `messageAudio` so often has no file name at all: a gate
    /// looking only at the extension called every one of those "not streamable" and went back to
    /// downloading the whole file. The extension is the fallback, and what a document post carries when
    /// its mime type is the meaningless `application/octet-stream`. Both come back because the player
    /// needs the type for content information and a name for the URL it loads.
    public static func resolve(mimeType: String, fileName: String) -> (uti: String, ext: String)? {
        if let uti = uti(forMIMEType: mimeType), let ext = `extension`(forMIMEType: mimeType) {
            return (uti, ext)
        }
        let named = (fileName as NSString).pathExtension.lowercased()
        if let uti = uti(forExtension: named) {
            return (uti, named)
        }
        return nil
    }

    /// The name a stream's URL should carry for this mime type. `nil` for a type AVFoundation cannot
    /// open, so a caller never builds a URL for a song it cannot play.
    private static func `extension`(forMIMEType mimeType: String) -> String? {
        switch mimeType.lowercased() {
        case "audio/mpeg", "audio/mp3": return "mp3"
        case "audio/mp4", "audio/m4a", "audio/x-m4a": return "m4a"
        case "audio/aac", "audio/x-aac": return "aac"
        case "audio/wav", "audio/x-wav", "audio/wave": return "wav"
        case "audio/aiff", "audio/x-aiff": return "aiff"
        case "audio/flac", "audio/x-flac": return "flac"
        default: return nil
        }
    }
}
