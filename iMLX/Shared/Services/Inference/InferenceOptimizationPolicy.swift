import Foundation

nonisolated struct InferenceOptimizationPlan: Equatable, Sendable {
    let prefillStepSize: Int
    let maxKVSize: Int?
    let kvBits: Int?
    let kvGroupSize: Int
    let quantizedKVStart: Int
    let mlxCacheLimitBytes: Int
    let visionInputSize: Int
    let shouldClearCacheBeforeGeneration: Bool
}

/// Tuning policy for a single generation.
///
/// Fields split into two groups. KV cache shape (`maxKVSize`, `kvBits`, `kvGroupSize`,
/// `quantizedKVStart`) must stay stable for the lifetime of a conversation, because changing it
/// invalidates the reusable prefix session and forces a full re-prefill. Those fields are derived
/// only from the host and the model, never from fluctuating live memory readings. Everything else
/// (prefill chunking, buffer cache size, cache reclamation) is safe to adapt per run.
nonisolated enum InferenceOptimizationPolicy {
    private struct PrefillLadder {
        let severe: Int
        let constrained: Int
        let standard: Int
        let large: Int
    }

    private enum ModelClass {
        case hybrid
        case gemma4
        case standard
    }

    private static let mobilePrefillLadder = PrefillLadder(
        severe: 128,
        constrained: 256,
        standard: 512,
        large: 1_024
    )
    private static let desktopPrefillLadder = PrefillLadder(
        severe: 512,
        constrained: 1_024,
        standard: 2_048,
        large: 4_096
    )

    private static let largePromptPrefillThreshold = 2_048

    static func plan(
        contextTextBytes: Int,
        contextMediaAttachmentCount: Int,
        maxTokens: Int,
        availableMemoryBytes: UInt64?,
        modelIdentifier: String? = nil,
        modelName: String? = nil,
        estimatedModelSizeGB: Double? = nil,
        supportsVision: Bool = false,
        allowsKVQuantization: Bool = true,
        host: HostMemoryProfile = .current
    ) -> InferenceOptimizationPlan {
        let availableMemory = availableMemoryBytes ?? .max
        let estimatedPromptTokens = max(1, (max(0, contextTextBytes) + 2) / 3)
        let hasMedia = contextMediaAttachmentCount > 0
        let isSeverelyConstrained = availableMemory < host.severeHeadroomBytes
        let isMemoryConstrained = availableMemory < host.constrainedHeadroomBytes
        let modelClass = modelClass(modelIdentifier: modelIdentifier, modelName: modelName)

        let ladder = host.isDesktopClass ? desktopPrefillLadder : mobilePrefillLadder
        let prefillStepSize: Int
        if isSeverelyConstrained {
            prefillStepSize = ladder.severe
        } else if hasMedia || isMemoryConstrained {
            // Only pay the smaller vision/memory prefill chunk when this turn actually needs it.
            // A vision-capable model on a text-only turn should still use the faster path.
            prefillStepSize = ladder.constrained
        } else if modelClass == .hybrid || estimatedPromptTokens >= largePromptPrefillThreshold {
            prefillStepSize = ladder.large
        } else {
            prefillStepSize = ladder.standard
        }

        // Quantization is requested for every eligible model rather than being switched on once a
        // conversation grows. `quantizedKVStart` already delays the conversion until the cache is
        // large enough to be worth compressing, so this costs nothing on short turns and keeps the
        // prefix session valid as the conversation grows.
        let shouldQuantizeKVCache = allowsKVQuantization && !supportsVision
        let quantizedKVStart = shouldQuantizeKVCache ? host.quantizedKVStartTokens : 0

        // A rotating window drops the oldest context, so it is only used when the conversation
        // genuinely outgrows the host. Prompt size grows monotonically within a conversation,
        // which keeps this from flipping back and forth between turns.
        let maxKVSize = host.kvWindowTokenLimit.flatMap { limit in
            estimatedPromptTokens > limit ? limit : nil
        }

        return InferenceOptimizationPlan(
            prefillStepSize: prefillStepSize,
            maxKVSize: maxKVSize,
            kvBits: shouldQuantizeKVCache ? 8 : nil,
            kvGroupSize: 64,
            quantizedKVStart: quantizedKVStart,
            mlxCacheLimitBytes: cacheLimitBytes(
                host: host,
                isSeverelyConstrained: isSeverelyConstrained,
                isMemoryConstrained: isMemoryConstrained,
                availableMemoryBytes: availableMemory,
                estimatedModelSizeGB: estimatedModelSizeGB,
                supportsVision: supportsVision
            ),
            visionInputSize: visionInputSize(host: host, isMemoryConstrained: isMemoryConstrained),
            shouldClearCacheBeforeGeneration: isSeverelyConstrained
        )
    }

    /// Buffer cache used before a plan is available, for example while loading a model.
    static func defaultCacheLimitBytes(host: HostMemoryProfile = .current) -> Int {
        host.isDesktopClass
            ? clampedDesktopCacheLimitBytes(host: host)
            : 20 * Int(HostMemoryProfile.megabyte)
    }

    /// Ceiling MLX applies to its own allocations before waiting on scheduled work.
    ///
    /// MLX otherwise defaults to 1.5x the recommended Metal working set, which can exceed what
    /// jetsam tolerates on an iPhone even with the increased memory entitlement.
    static func memoryLimitBytes(host: HostMemoryProfile = .current) -> Int {
        Int(clamping: host.inferenceMemoryLimitBytes)
    }

    static func shouldReclaimCache(
        availableMemoryBytes: UInt64?,
        host: HostMemoryProfile = .current
    ) -> Bool {
        guard let availableMemoryBytes else { return false }
        return availableMemoryBytes < host.cacheReclaimHeadroomBytes
    }

    static func allowsKVQuantization(
        modelIdentifier: String?,
        modelName: String?,
        supportsVision: Bool
    ) -> Bool {
        guard !supportsVision else { return false }
        // Gemma 4 text KV quantization has been unreliable in practice.
        return modelClass(modelIdentifier: modelIdentifier, modelName: modelName) != .gemma4
    }

    static func shouldClearCacheBetweenSpeechStages(
        availableMemoryBytes: UInt64?,
        host: HostMemoryProfile = .current
    ) -> Bool {
        guard let availableMemoryBytes else { return true }
        return availableMemoryBytes < host.constrainedHeadroomBytes
    }

    private static func cacheLimitBytes(
        host: HostMemoryProfile,
        isSeverelyConstrained: Bool,
        isMemoryConstrained: Bool,
        availableMemoryBytes: UInt64,
        estimatedModelSizeGB: Double?,
        supportsVision: Bool
    ) -> Int {
        let megabyte = Int(HostMemoryProfile.megabyte)

        if host.isDesktopClass {
            if isSeverelyConstrained { return 64 * megabyte }
            if isMemoryConstrained { return 256 * megabyte }
            return clampedDesktopCacheLimitBytes(host: host)
        }

        if isSeverelyConstrained { return 8 * megabyte }
        if isMemoryConstrained { return 20 * megabyte }
        if supportsVision || (estimatedModelSizeGB ?? 0) >= 3 { return 32 * megabyte }
        if availableMemoryBytes >= host.abundantHeadroomBytes { return 64 * megabyte }
        return 32 * megabyte
    }

    /// A desktop-sized buffer pool. MLX recycles evaluation buffers up to this limit, so the tiny
    /// mobile budgets force constant allocate/free churn on machines that can spare gigabytes.
    private static func clampedDesktopCacheLimitBytes(host: HostMemoryProfile) -> Int {
        let megabyte = Int(HostMemoryProfile.megabyte)
        let scaled = Int(clamping: host.physicalMemoryBytes / 16)
        return min(max(scaled, 384 * megabyte), 1_536 * megabyte)
    }

    private static func visionInputSize(host: HostMemoryProfile, isMemoryConstrained: Bool) -> Int {
        if host.isDesktopClass {
            return isMemoryConstrained ? 512 : 768
        }
        return isMemoryConstrained ? 384 : 512
    }

    private static func modelClass(modelIdentifier: String?, modelName: String?) -> ModelClass {
        let identity = [modelIdentifier, modelName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        if identity.contains("qwen3.5") || identity.contains("qwen35")
            || identity.contains("qwen3_5") || identity.contains("lfm")
        {
            return .hybrid
        }
        if identity.contains("gemma4") || identity.contains("gemma-4")
            || identity.contains("gemma 4") || identity.contains("gemma_4")
        {
            return .gemma4
        }
        return .standard
    }
}
