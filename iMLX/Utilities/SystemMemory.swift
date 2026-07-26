import Darwin
import Foundation

nonisolated enum SystemMemory {
    static func availableBytes() -> UInt64? {
        #if os(iOS)
        let available = os_proc_available_memory()
        guard available != 0 else { return nil }
        return UInt64(available)
        #elseif os(macOS)
        guard let statistics = hostVMStatistics() else { return nil }

        // macOS deliberately keeps free pages low and parks reclaimable memory in the file
        // cache, purgeable pools, and the compressor. Counting only free + inactive pages
        // therefore reports a fraction of the real headroom. This mirrors how Activity
        // Monitor derives "Memory Used": app memory + wired + compressed, with everything
        // else treated as reclaimable under pressure.
        let pageSize = UInt64(vm_kernel_page_size)
        let internalPages = UInt64(statistics.internal_page_count)
        let purgeablePages = UInt64(statistics.purgeable_count)
        let appPages = internalPages > purgeablePages ? internalPages - purgeablePages : internalPages
        let usedPages = appPages
            + UInt64(statistics.wire_count)
            + UInt64(statistics.compressor_page_count)
        let usedBytes = usedPages * pageSize
        let physicalBytes = ProcessInfo.processInfo.physicalMemory
        guard usedBytes < physicalBytes else { return nil }
        return physicalBytes - usedBytes
        #else
        return nil
        #endif
    }

    #if os(macOS)
    private static func hostVMStatistics() -> vm_statistics64? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride
        )
        let result = withUnsafeMutablePointer(to: &statistics) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(
                    mach_host_self(),
                    HOST_VM_INFO64,
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return statistics
    }
    #endif
}
