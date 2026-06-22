import Darwin
import Foundation
import OSLog
import UIKit

nonisolated enum LLMProfiler {
    static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "iMLX",
        category: "LocalLLMProfiling"
    )

    struct Timer: Sendable {
        private let clock: ContinuousClock
        private let start: ContinuousClock.Instant

        init() {
            let clock = ContinuousClock()
            self.clock = clock
            self.start = clock.now
        }

        func elapsedSeconds() -> TimeInterval {
            Self.seconds(from: start.duration(to: clock.now))
        }

        private static func seconds(from duration: Duration) -> TimeInterval {
            let components = duration.components
            return TimeInterval(components.seconds) + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
        }
    }

    @discardableResult
    static func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    static func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    static func emitEvent(_ name: StaticString) {
        signposter.emitEvent(name)
    }

    static func availableMemoryBytes() -> UInt64? {
        #if os(iOS)
        let available = os_proc_available_memory()
        guard available != 0 else { return nil }
        return UInt64(available)
        #else
        return nil
        #endif
    }

    static func devicePhysicalMemoryGB() -> Int {
        Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024))
    }

    static func currentMemoryFootprintBytes() -> UInt64? {
        var vmInfo = task_vm_info_data_t()
        var vmCount = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        let vmResult = withUnsafeMutablePointer(to: &vmInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &vmCount)
            }
        }
        if vmResult == KERN_SUCCESS {
            return UInt64(vmInfo.phys_footprint)
        }

        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        return UInt64(info.resident_size)
    }

    static func thermalStateDescription() -> String {
        switch ProcessInfo.processInfo.thermalState {
        case .nominal:
            return "nominal"
        case .fair:
            return "fair"
        case .serious:
            return "serious"
        case .critical:
            return "critical"
        @unknown default:
            return "unknown"
        }
    }

    /// Battery percentage is intentionally captured as a coarse contextual signal only.
    /// Public iOS APIs do not provide joule-level energy usage for a single inference run.
    @MainActor
    static func coarseBatteryLevel() -> Double? {
        let device = UIDevice.current
        let wasMonitoring = device.isBatteryMonitoringEnabled
        if !wasMonitoring {
            device.isBatteryMonitoringEnabled = true
        }
        defer {
            if !wasMonitoring {
                device.isBatteryMonitoringEnabled = false
            }
        }

        let level = device.batteryLevel
        guard level >= 0 else { return nil }
        return Double(level)
    }

    static func deviceModelIdentifier() -> String? {
        var systemInfo = utsname()
        guard uname(&systemInfo) == 0 else { return nil }

        let identifier = Mirror(reflecting: systemInfo.machine).children.reduce(into: "") { result, element in
            guard let value = element.value as? Int8, value != 0 else {
                return
            }
            result.append(Character(UnicodeScalar(UInt8(value))))
        }
        return identifier.isEmpty ? nil : identifier
    }

    static func errorInfo(from error: Error) -> LLMExecutionErrorInfo {
        let nsError = error as NSError
        return LLMExecutionErrorInfo(
            message: error.localizedDescription,
            domain: nsError.domain,
            code: nsError.code
        )
    }
}
