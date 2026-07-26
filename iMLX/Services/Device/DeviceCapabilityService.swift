import Foundation

nonisolated enum DeviceTier: Int, Comparable {
    case tier8GB = 8
    case tier12GB = 12
    case tier16GB = 16
    case tier24GB = 24

    static func < (lhs: DeviceTier, rhs: DeviceTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var displayName: String {
        switch self {
        case .tier8GB, .tier12GB, .tier16GB:
            String(format: String.appLocalized("device.tier.gb"), Int64(rawValue))
        case .tier24GB:
            String(format: String.appLocalized("device.tier.gb_plus"), Int64(rawValue))
        }
    }
}

nonisolated final class DeviceCapabilityService {
    let physicalMemoryGB: Int
    let tier: DeviceTier
    let usableMemoryEstimateGB: Int

    init(hostMemoryProfile: HostMemoryProfile = .current) {
        let physicalGB = hostMemoryProfile.physicalMemoryGB
        self.physicalMemoryGB = physicalGB
        self.usableMemoryEstimateGB = Int(
            hostMemoryProfile.usableMemoryEstimateBytes / HostMemoryProfile.gigabyte
        )

        if physicalGB >= 20 {
            self.tier = .tier24GB
        } else if physicalGB >= 14 {
            self.tier = .tier16GB
        } else if physicalGB >= 10 {
            self.tier = .tier12GB
        } else {
            self.tier = .tier8GB
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
        guard let available = SystemMemory.availableBytes() else { return 0 }
        return available / (1024 * 1024)
    }

    func compatibleModels(from registry: [ModelInfo]) -> [ModelInfo] {
        registry.filter { canRunModel($0) }
    }
}
