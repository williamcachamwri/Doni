import Foundation
import Testing
@testable import Support

@Test("parts that touch are one stretch of bytes")
func rangesMerge() {
    var ready = AudioReadyRanges()
    ready.mark(AudioByteRange(offset: 64, count: 64))
    ready.mark(AudioByteRange(offset: 128, count: 64))
    ready.mark(AudioByteRange(offset: 192, count: 64))
    // 64…256 is contiguous, so the three parts are one span and a reader gets all of them at once.
    #expect(ready.spans.count == 1)
    #expect(ready.contiguous(at: 64) == 192)
    #expect(ready.totalBytes == 192)
}

@Test("a hole stops a read at the hole")
func rangesStopAtHoles() {
    var ready = AudioReadyRanges()
    ready.mark(AudioByteRange(offset: 0, count: 100))
    ready.mark(AudioByteRange(offset: 200, count: 100))
    #expect(ready.contiguous(at: 50) == 50)
    #expect(ready.contiguous(at: 150) == 0)
    #expect(ready.contiguous(at: 200) == 100)
    #expect(ready.firstGap(before: 300) == 100)
    #expect(ready.firstGap(before: 100) == nil)
}

@Test("a short read marks only the bytes that came back")
func shortReadsAreHonest() {
    var ready = AudioReadyRanges()
    ready.markRead(AudioByteRange(offset: 0, count: 1024), returned: 20)
    #expect(ready.totalBytes == 20)
}

@Test("a window is asked once and kept until half of it is listened to")
func windowHysteresis() {
    var policy = AudioWindowPolicy(leadBytes: 1 << 20)
    let bytesPerSecond = 40_000.0
    // One megabyte of lead is twenty-six seconds of this song, so the first window is still half
    // whole ten seconds in and must not be re-asked — a re-ask cancels the parts that were arriving.
    let first = policy.window(atSeconds: 0, bytesPerSecond: bytesPerSecond, fileBytes: 15_000_000)
    #expect(first?.offset == 0)
    #expect(first?.count == 1 << 20)
    #expect(policy.window(atSeconds: 5, bytesPerSecond: bytesPerSecond, fileBytes: 15_000_000) == nil)
    #expect(policy.window(atSeconds: 10, bytesPerSecond: bytesPerSecond, fileBytes: 15_000_000) == nil)

    let moved = policy.window(atSeconds: 20, bytesPerSecond: bytesPerSecond, fileBytes: 15_000_000)
    #expect(moved != nil)
    // On the part grid, and a part behind the playhead so a scrub back costs no round trip.
    #expect(moved!.offset % AudioWindowPolicy.partBytes == 0)
    #expect(moved!.offset <= Int64(20 * bytesPerSecond))
    #expect(moved!.end > Int64(20 * bytesPerSecond))
}

@Test("a seek away from the window asks for the place the user jumped to")
func windowFollowsSeeks() {
    var policy = AudioWindowPolicy(leadBytes: 1 << 20)
    // An hour-long set: the byte the playhead lands on is far past the first window, which is the
    // whole difference between this and waiting for the front of the file to arrive.
    let set: Int64 = 140_000_000
    _ = policy.window(atSeconds: 10, bytesPerSecond: 40_000, fileBytes: set)
    let jumped = policy.window(atSeconds: 900, bytesPerSecond: 40_000, fileBytes: set)
    #expect(jumped?.offset == 35_913_728)
    #expect(jumped?.count == 1 << 20)
    // Backwards is the same ask: the window does not cover where the sound is now.
    let back = policy.window(atSeconds: 90, bytesPerSecond: 40_000, fileBytes: set)
    #expect(back != nil)
    #expect((back?.offset ?? set) < 4_000_000)
}

@Test("a window never reaches past the end of the file")
func windowClampsToTheFile() {
    var policy = AudioWindowPolicy(leadBytes: 1 << 20)
    let last = policy.window(atSeconds: 370, bytesPerSecond: 40_000, fileBytes: 15_000_000)
    #expect(last?.end ?? 0 <= 15_000_000)
    #expect(policy.window(atSeconds: 9_999, bytesPerSecond: 40_000, fileBytes: 15_000_000)?
        .end ?? 0 <= 15_000_000)
}

@Test("a rebuffer buys ahead further and a comfortable buffer stops buying so much")
func leadAdapts() {
    var policy = AudioWindowPolicy()
    #expect(policy.leadBytes == AudioWindowPolicy.minimumLeadBytes)
    policy.noteRebuffer()
    #expect(policy.leadBytes == 2 << 20)
    policy.noteRebuffer()
    policy.noteRebuffer()
    policy.noteRebuffer()
    #expect(policy.leadBytes == AudioWindowPolicy.maximumLeadBytes)
    policy.noteRebuffer()
    #expect(policy.leadBytes == AudioWindowPolicy.maximumLeadBytes)

    // One good moment is not permission to halve the plan: it has to be twice as good as it needs.
    policy.noteComfortable(aheadBytes: policy.leadBytes)
    #expect(policy.leadBytes == AudioWindowPolicy.maximumLeadBytes)
    policy.noteComfortable(aheadBytes: policy.leadBytes * 3)
    #expect(policy.leadBytes == 6 << 20)
    while policy.leadBytes > AudioWindowPolicy.minimumLeadBytes {
        policy.noteComfortable(aheadBytes: policy.leadBytes * 3)
    }
    #expect(policy.leadBytes == AudioWindowPolicy.minimumLeadBytes)
    // A lead that has run out is not trusted to still cover the playhead.
    policy.noteRebuffer()
    _ = policy.window(atSeconds: 0, bytesPerSecond: 40_000, fileBytes: 15_000_000)
    policy.noteRebuffer()
    #expect(policy.window(atSeconds: 0, bytesPerSecond: 40_000, fileBytes: 15_000_000) != nil)
}

@Test("a start asks for the head, and for a container that hides its metadata, the tail too")
func headAndTail() {
    let mp3 = AudioWindowPolicy.head(for: 15_000_000, includingTail: false)
    #expect(mp3.count == 1)
    #expect(mp3[0].offset == 0)
    #expect(mp3[0].count == AudioWindowPolicy.headBytes)

    let m4a = AudioWindowPolicy.head(for: 15_000_000, includingTail: true)
    #expect(m4a.count == 2)
    #expect(m4a[1].end == 15_000_000)
    #expect(m4a[1].count == AudioWindowPolicy.tailBytes)

    // A file shorter than the head is the head, and no tail window overlapping it.
    #expect(AudioWindowPolicy.head(for: 40_000, includingTail: true).count == 1)
    #expect(AudioWindowPolicy.head(for: 40_000, includingTail: true)[0].count == 40_000)
    #expect(AudioWindowPolicy.head(for: 0, includingTail: true).isEmpty)
}

@Test("a prefetch holds a song's head, not the song")
func prefetchIsBounded() {
    #expect(AudioWindowPolicy.prefetch(for: 140_000_000).count == AudioWindowPolicy.headBytes)
    #expect(AudioWindowPolicy.prefetch(for: 100_000).count == 100_000)
}

@Test("a sweep gives back what nobody is going to listen to again soon")
func evictionsChooseByRecency() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let rows = [
        AudioCacheRow(uniqueId: "whole-old", bytes: 5_000_000, isComplete: true,
                      lastPlayedAt: now.addingTimeInterval(-86_400)),
        AudioCacheRow(uniqueId: "half-new", bytes: 4_000_000, isComplete: false,
                      lastPlayedAt: now),
        AudioCacheRow(uniqueId: "whole-new", bytes: 3_000_000, isComplete: true, lastPlayedAt: now),
        AudioCacheRow(uniqueId: "never", bytes: 2_000_000, isComplete: true, lastPlayedAt: nil)
    ]
    // 14 MB in the library against a 10 MB quota: the song that was fetched and never opened goes,
    // then the oldest listen, and that is enough — the two rows listened to today stay on the phone
    // whether or not one of them is only half there.
    let victims = AudioCachePolicy.evictions(rows, quotaBytes: 10_000_000)
    #expect(victims.first == "never")
    #expect(victims.count == 2)
    #expect(victims.contains("whole-old"))
    #expect(!victims.contains("half-new"))
    #expect(!victims.contains("whole-new"))
    #expect(AudioCachePolicy.evictions(rows, quotaBytes: 20_000_000).isEmpty)
}

@Test("the song under the playhead is never a victim")
func currentSongSurvives() {
    let rows = [
        AudioCacheRow(uniqueId: "playing", bytes: 9_000_000, isComplete: false,
                      lastPlayedAt: nil, isCurrent: true),
        AudioCacheRow(uniqueId: "other", bytes: 9_000_000, isComplete: false, lastPlayedAt: nil)
    ]
    // The quota cannot be met without the current song: the sweep takes what it can and leaves the
    // song making noise, rather than emptying the file under the player's own feet.
    let victims = AudioCachePolicy.evictions(rows, quotaBytes: 1_000)
    #expect(victims == ["other"])
}

@Test("two sweeps of the same library agree")
func evictionIsDeterministic() {
    let rows = (0..<6).map {
        AudioCacheRow(uniqueId: "u\($0)", bytes: 1_000_000, isComplete: false, lastPlayedAt: nil)
    }
    let shuffled = Array(rows.reversed())
    #expect(AudioCachePolicy.evictions(rows, quotaBytes: 3_000_000)
        == AudioCachePolicy.evictions(shuffled, quotaBytes: 3_000_000))
}
