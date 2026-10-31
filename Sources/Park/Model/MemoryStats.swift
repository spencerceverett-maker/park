import Darwin
import Foundation

/// System memory in the same terms Activity Monitor uses for "Memory Used".
struct MemoryStats: Equatable {
    var used: UInt64
    var total: UInt64

    var fraction: Double { total == 0 ? 0 : min(1, Double(used) / Double(total)) }

    static func current() -> MemoryStats {
        let total = ProcessInfo.processInfo.physicalMemory
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return MemoryStats(used: 0, total: total) }
        let page = UInt64(vm_kernel_page_size)
        // App memory + wired + compressed, matching Activity Monitor.
        let app = UInt64(stats.internal_page_count) - UInt64(stats.purgeable_count)
        let used = (app + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)) * page
        return MemoryStats(used: min(used, total), total: total)
    }

    /// Physical footprint of a process, the number Activity Monitor shows in its Memory column.
    static func footprint(of pid: pid_t) -> UInt64 {
        var info = rusage_info_v2()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        return result == 0 ? info.ri_phys_footprint : 0
    }
}

enum ByteText {
    /// Always one decimal, without a unit: "12.4".
    static func gigabytes(_ bytes: UInt64) -> String {
        String(format: "%.1f", Double(bytes) / 1_073_741_824)
    }

    static func short(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / 1_073_741_824
        if gb >= 1 { return String(format: gb >= 10 ? "%.0f GB" : "%.1f GB", gb) }
        let mb = Double(bytes) / 1_048_576
        return String(format: "%.0f MB", max(1, mb))
    }
}
