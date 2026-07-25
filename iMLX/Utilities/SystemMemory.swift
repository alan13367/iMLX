import Darwin
import Foundation

nonisolated enum SystemMemory {
    static func availableBytes() -> UInt64? {
        #if os(iOS)
        let available = os_proc_available_memory()
        guard available != 0 else { return nil }
        return UInt64(available)
        #elseif os(macOS)
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
        // speculative_count is already included in free_count per Darwin vm_statistics.h.
        let reusablePages = UInt64(statistics.free_count) + UInt64(statistics.inactive_count)
        return reusablePages * UInt64(vm_kernel_page_size)
        #else
        return nil
        #endif
    }
}
