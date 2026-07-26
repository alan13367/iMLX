import Foundation

/// Memory characteristics of the machine the app is running on.
///
/// Inference tuning has to behave very differently on a jetsam-constrained iPhone and on a Mac
/// with tens of gigabytes of unified memory. Every headroom threshold and budget used by the
/// inference layer is derived from this profile instead of being hardcoded for mobile.
nonisolated struct HostMemoryProfile: Equatable, Sendable {
    enum PlatformClass: String, Equatable, Sendable {
        case mobile
        case desktop
    }

    static let megabyte: UInt64 = 1024 * 1024
    static let gigabyte: UInt64 = 1024 * 1024 * 1024

    let platformClass: PlatformClass
    let physicalMemoryBytes: UInt64

    init(platformClass: PlatformClass, physicalMemoryBytes: UInt64) {
        self.platformClass = platformClass
        self.physicalMemoryBytes = max(physicalMemoryBytes, 2 * Self.gigabyte)
    }

    static var current: HostMemoryProfile {
        #if os(macOS)
        HostMemoryProfile(
            platformClass: .desktop,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
        #else
        HostMemoryProfile(
            platformClass: .mobile,
            physicalMemoryBytes: ProcessInfo.processInfo.physicalMemory
        )
        #endif
    }

    var isDesktopClass: Bool {
        platformClass == .desktop
    }

    var physicalMemoryGB: Int {
        Int(physicalMemoryBytes / Self.gigabyte)
    }

    /// Headroom below which throughput should be traded for survival.
    var severeHeadroomBytes: UInt64 {
        switch platformClass {
        case .mobile:
            return 512 * Self.megabyte
        case .desktop:
            return max(Self.gigabyte, physicalMemoryBytes / 16)
        }
    }

    /// Headroom below which the host is treated as memory constrained.
    var constrainedHeadroomBytes: UInt64 {
        switch platformClass {
        case .mobile:
            return 1_200 * Self.megabyte
        case .desktop:
            return max(2 * Self.gigabyte, physicalMemoryBytes / 8)
        }
    }

    /// Headroom above which the largest buffer budgets are safe to use.
    var abundantHeadroomBytes: UInt64 {
        switch platformClass {
        case .mobile:
            return 2_000 * Self.megabyte
        case .desktop:
            return max(4 * Self.gigabyte, physicalMemoryBytes / 4)
        }
    }

    /// Headroom below which cached MLX buffers should be released after a run.
    var cacheReclaimHeadroomBytes: UInt64 {
        switch platformClass {
        case .mobile:
            return 768 * Self.megabyte
        case .desktop:
            return max(3 * Self.gigabyte / 2, physicalMemoryBytes / 12)
        }
    }

    /// Ceiling for MLX allocations before it starts waiting on scheduled work.
    ///
    /// This is deliberately larger than ``usableMemoryEstimateBytes``: that value answers "how big
    /// a model fits", while this one is a back-pressure limit that should sit near what the OS
    /// actually tolerates. On iOS that is roughly what the increased-memory entitlement grants.
    var inferenceMemoryLimitBytes: UInt64 {
        switch platformClass {
        case .mobile:
            return physicalMemoryBytes / 10 * 7
        case .desktop:
            return physicalMemoryBytes / 4 * 3
        }
    }

    /// Memory the app can realistically dedicate to model weights and activations.
    var usableMemoryEstimateBytes: UInt64 {
        switch platformClass {
        case .mobile:
            let reserved: UInt64
            switch physicalMemoryGB {
            case 20...: reserved = 6 * Self.gigabyte
            case 14...: reserved = 5 * Self.gigabyte
            case 10...: reserved = 4 * Self.gigabyte
            default: reserved = 3 * Self.gigabyte
            }
            return max(physicalMemoryBytes - min(physicalMemoryBytes, reserved), 2 * Self.gigabyte)
        case .desktop:
            return physicalMemoryBytes / 4 * 3
        }
    }

    /// Rotating KV window used once a conversation outgrows what the host can hold.
    ///
    /// `nil` means the host has enough memory to keep the full cache, which is preferable
    /// because a rotating window silently drops the oldest context.
    var kvWindowTokenLimit: Int? {
        switch platformClass {
        case .mobile:
            return physicalMemoryGB < 7 ? 4_096 : 8_192
        case .desktop:
            switch physicalMemoryGB {
            case ...9: return 16_384
            case ...17: return 32_768
            default: return nil
            }
        }
    }

    /// Cache offset at which 8-bit KV quantization starts paying for itself.
    var quantizedKVStartTokens: Int {
        isDesktopClass ? 4_096 : 1_024
    }
}
