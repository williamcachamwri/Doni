import Foundation

/// The container names AVFoundation has to be told, keyed by the extension a Telegram file carries.
///
/// A resource loader is not a URL the player will probe: answering the content-information request
/// without a type gets -11850 "the server is not correctly configured", which reads like a broken
/// network and is really a missing string. So the list is deliberately short and says nothing about a
/// format iOS cannot decode — an answer here is a promise that `AVPlayer` can play the bytes.
public enum AudioContentType {
    /// The uniform type identifier for an extension, `nil` when the container is not one
    /// AVFoundation opens. `nil` is not "try it": the caller has to put the song on the whole-file
    /// path instead, because a format nobody can decode cannot be streamed by ranges either.
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
        uti(forMIMEType: mimeType) != nil || uti(forExtension: (fileName as NSString).pathExtension) != nil
    }
}
