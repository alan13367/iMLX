import Darwin
import Foundation

nonisolated enum SystemMemory {
    static func availableBytes() -> UInt64? {
        let available = os_proc_available_memory()
        guard available != 0 else { return nil }
        return UInt64(available)
    }
}
