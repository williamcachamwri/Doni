import Foundation
import Testing
@testable import Support

/// A tree the test builds and throws away: two files at the top and one in a folder under them.
private func makeTree() throws -> (URL, [Int64]) {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("doni-disk-\(UUID().uuidString)", isDirectory: true)
    let nested = directory.appendingPathComponent("deep", isDirectory: true)
    try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

    var sizes: [Int64] = []
    for (place, name, kilobytes) in [(directory, "one.bin", 8), (directory, "two.bin", 12),
                                     (nested, "three.bin", 4)] {
        let url = place.appendingPathComponent(name)
        try Data(count: Int(kilobytes) * 1024).write(to: url)
        sizes.append(Int64(kilobytes) * 1024)
    }
    return (directory, sizes)
}

@Suite("DiskUsage")
struct DiskUsageTests {
    @Test("a directory is worth what its files are worth, folder included")
    func walksWholeTree() throws {
        let (directory, sizes) = try makeTree()
        defer { try? FileManager.default.removeItem(at: directory) }

        let counted = DiskUsage.bytes(at: directory)
        // Allocated rather than logical bytes, so the floor is the sum of what was written and the
        // two numbers only ever part by a filesystem block.
        #expect(counted >= sizes.reduce(0, +))
        let each = sizes.reduce(Int64(0)) { $0 + $1 }
        #expect(counted - each < 3 * 4096, "the walk should not be inventing whole files")

        // The file itself answers on its own, which is what lets the same call serve both jobs.
        let single = directory.appendingPathComponent("one.bin")
        #expect(DiskUsage.bytes(at: single) >= sizes[0])
    }

    @Test("a path that is not there is nothing, and clearing it is nothing")
    func missingPathsAreQuiet() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("doni-disk-\(UUID().uuidString)", isDirectory: true)
        #expect(DiskUsage.bytes(at: directory) == 0)
        #expect(DiskUsage.clear(directory) == 0)
    }

    @Test("clearing says how much room it made and leaves nothing behind")
    func clearReportsTheRoomItMade() throws {
        let (directory, sizes) = try makeTree()
        let before = DiskUsage.bytes(at: directory)
        let freed = DiskUsage.clear(directory)

        #expect(freed == before)
        #expect(before >= sizes.reduce(0, +))
        #expect(DiskUsage.bytes(at: directory) == 0)
    }

    @Test("the volume says what it holds and what is free")
    func deviceCapacityHasTwoNumbers() {
        let capacity = DiskUsage.deviceCapacity()
        #expect((capacity.total ?? 0) > 0)
        #expect((capacity.available ?? 0) > 0)
    }
}
