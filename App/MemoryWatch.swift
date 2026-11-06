import Foundation
import MachO

/// What this process is holding, in the two numbers that mean something to a streaming app.
/// `task_vm_info`'s `phys_footprint` is what Xcode's gauge and the jetsam killer use; `resident_size`
/// counts dirty pages, is usually a little larger, and is why the two disagree. Asked once per song, not
/// per second: the question is whether the number climbs as songs go by, which is where a leak shows.
enum MemoryWatch {
    static func read() -> (resident: Int64, footprint: Int64) {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let made = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        guard made == KERN_SUCCESS else { return (0, 0) }
        return (Int64(task_info_resident_size()), Int64(info.phys_footprint))
    }

    /// The room the process may use before the system tells it to stop — the only quota a backgrounded
    /// player can plan against, and asked of the system rather than counted.
    ///
    /// `nil` on macOS: `os_proc_available_memory` is the iOS jetsam budget, and the desktop has no
    /// per-process footprint budget to ask. A Mac log line that printed a number in that field would be
    /// printing a different fact under the same name, so it prints none.
    static func available() -> Int64? {
        #if os(iOS) || os(tvOS)
        Int64(os_proc_available_memory())
        #else
        nil
        #endif
    }

    /// One line, in megabytes, for the log a person reads when a queue is suspected of eating the phone.
    static func note(_ what: String, track: String? = nil) {
        let now = read()
        let name = track.map { " \($0)" } ?? ""
        let room = available().map { " available=\(megabytes($0))MB" } ?? ""
        print("memory \(what) resident=\(megabytes(now.resident))MB footprint=\(megabytes(now.footprint))MB"
            + room + name)
    }

    private static func megabytes(_ bytes: Int64) -> Int {
        Int((Double(bytes) / 1_048_576).rounded())
    }
}

/// `task_info`'s resident size, which the C header exposes as a macro over the same struct.
private func task_info_resident_size() -> UInt64 {
    var info = task_basic_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_basic_info_data_t>.size / MemoryLayout<natural_t>.size)
    let made = withUnsafeMutablePointer(to: &info) { pointer -> kern_return_t in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_BASIC_INFO), $0, &count)
        }
    }
    return made == KERN_SUCCESS ? UInt64(info.resident_size) : 0
}
