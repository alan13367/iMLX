import Foundation

enum DeviceTier: Int, Comparable {
    case tier8GB = 8
    case tier12GB = 12
    case tier16GB = 16
    case tier24GB = 24

    static func < (lhs: DeviceTier, rhs: DeviceTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .tier8GB: "\(rawValue)GB"
        case .tier12GB: "\(rawValue)GB"
        case .tier16GB: "\(rawValue)GB"
        case .tier24GB: "\(rawValue)GB+"
        }
    }
}

@Observable
final class DeviceCapabilityService {
    let physicalMemoryGB: Int
    let tier: DeviceTier
    let usableMemoryEstimateGB: Int

    init() {
        let physicalBytes = ProcessInfo.processInfo.physicalMemory
        let physicalGB = Int(physicalBytes / (1024 * 1024 * 1024))
        self.physicalMemoryGB = physicalGB

        if physicalGB >= 20 {
            self.tier = .tier24GB
            self.usableMemoryEstimateGB = physicalGB - 6
        } else if physicalGB >= 14 {
            self.tier = .tier16GB
            self.usableMemoryEstimateGB = physicalGB - 5
        } else if physicalGB >= 10 {
            self.tier = .tier12GB
            self.usableMemoryEstimateGB = physicalGB - 4
        } else {
            self.tier = .tier8GB
            self.usableMemoryEstimateGB = max(physicalGB - 3, 2)
        }
    }

    func canRunModel(_ model: ModelInfo) -> Bool {
        tier.rawValue >= model.minDeviceRAM
    }

    var currentMemoryUsageMB: UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }
        return info.resident_size / (1024 * 1024)
    }

    var availableMemoryMB: UInt64 {
        #if os(iOS)
        let available = os_proc_available_memory()
        guard available != 0 else { return 0 }
        return UInt64(available / (1024 * 1024))
        #else
        return 0
        #endif
    }

    func compatibleModels(from registry: [ModelInfo]) -> [ModelInfo] {
        registry.filter { canRunModel($0) }
    }
}
