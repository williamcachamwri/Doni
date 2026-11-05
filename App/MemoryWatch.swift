import Foundation
import MachO

/// What this process is holding, in the two numbers that mean something to a streaming app.
///
/// The resident size is what the listener feels as heat and what iOS answers by killing the app, and
/// the footprint is what the system's own memory-pressure warning is measured against. Asked once per
/// song rather than once per second, because the question worth answering is whether the number
/// climbs as songs go by — a stream that leaks shows it there, and nowhere else.
///
/// `task_vm_info`'s `phys_footprint` is the number Xcode's gauge and the jetsam killer use;
/// `resident_size` is the dirty pages, which is usually a little larger and is the one that makes
/// the two of them disagree.
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

    /// Bytes of the app's own container that are cache, asked of the system rather than counted.
    ///
    /// iOS hands back a number the process may use before it is told to stop, which is the only
    /// quota a backgrounded player can plan against.
    static func available() -> Int64 {
        Int64(os_proc_available_memory())
    }

    /// One line, in megabytes, for the log a person reads when a queue is suspected of eating the
    /// phone.
    static func note(_ what: String, track: String? = nil) {
        let now = read()
        let name = track.map { " \($0)" } ?? ""
        print("memory \(what) resident=\(megabytes(now.resident))MB footprint=\(megabytes(now.footprint))MB"
            + " available=\(megabytes(available()))MB\(name)")
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
