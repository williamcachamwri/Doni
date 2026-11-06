import SwiftUI
import Support

struct LyricsShareSheet: View {
    let payload: LyricSharePayload
    let artwork: DoniImage?
    let onComplete: (Bool) -> Void

    var body: some View {
        SystemShareSheet(
            activityItems: activityItems,
            onComplete: onComplete
        )
    }

    private var activityItems: [Any] {
        #if os(iOS)
        [
            LyricShareURLActivityItemSource(
                payload: payload,
                artwork: artwork
            ),
            LyricShareTextActivityItemSource(payload: payload),
        ]
        #else
        // The song's link and the words themselves, plainly: the desktop's services read the item and
        // build their own preview, so the per-service shaping the phone needs has no counterpart here.
        [payload.songURL as NSURL, payload.originalLyricsText as NSString]
        #endif
    }
}
