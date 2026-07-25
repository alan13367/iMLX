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

nonisolated enum InferenceOptimizationPolicy {
    static let defaultMLXCacheLimitBytes = 20 * 1024 * 1024

    private enum ModelClass {
        case hybrid
        case gemma4
        case standard
    }

    private static let severeMemoryHeadroomBytes: UInt64 = 512 * 1024 * 1024
    private static let constrainedMemoryHeadroomBytes: UInt64 = 1_200 * 1024 * 1024
    private static let highMemoryHeadroomBytes: UInt64 = 2_000 * 1024 * 1024
    private static let cacheReclaimHeadroomBytes: UInt64 = 768 * 1024 * 1024
    private static let kvQuantizationPromptTokenThreshold = 1_280
    private static let extendedGenerationTokenThreshold = 6_000
    /// Assumed generation use when deciding whether a large maxTokens budget warrants KV quant.
    private static let likelyGenerationTokenCap = 2_048
    private static let kvQuantizationActiveCacheTokenThreshold = 3_072

    static func plan(
        contextTextBytes: Int,
        contextMediaAttachmentCount: Int,
        maxTokens: Int,
        availableMemoryBytes: UInt64?,
        modelIdentifier: String? = nil,
        modelName: String? = nil,
        estimatedModelSizeGB: Double? = nil,
        supportsVision: Bool = false,
        allowsKVQuantization: Bool = true
    ) -> InferenceOptimizationPlan {
        let availableMemory = availableMemoryBytes ?? .max
        let estimatedPromptTokens = max(1, (max(0, contextTextBytes) + 2) / 3)
        let hasMedia = contextMediaAttachmentCount > 0
        let isMemoryConstrained = availableMemory < constrainedMemoryHeadroomBytes
        let modelClass = modelClass(modelIdentifier: modelIdentifier, modelName: modelName)
        let estimatedActiveCacheTokens =
            estimatedPromptTokens + min(max(0, maxTokens), likelyGenerationTokenCap)

        let prefillStepSize: Int
        if availableMemory < severeMemoryHeadroomBytes {
            prefillStepSize = 128
        } else if hasMedia || isMemoryConstrained {
            // Only pay the smaller vision/memory prefill chunk when this turn actually needs it.
            // A vision-capable model on a text-only turn should still use the faster path.
            prefillStepSize = 256
        } else if modelClass == .hybrid || estimatedPromptTokens >= 2_048 {
            prefillStepSize = 1_024
        } else {
            prefillStepSize = 512
        }

        let shouldQuantizeKVCache = allowsKVQuantization
            && !supportsVision
            && (isMemoryConstrained
                || estimatedPromptTokens >= kvQuantizationPromptTokenThreshold
                || estimatedActiveCacheTokens >= kvQuantizationActiveCacheTokenThreshold
                || maxTokens >= extendedGenerationTokenThreshold)
        let quantizedKVStart = shouldQuantizeKVCache
            ? (isMemoryConstrained ? 512 : 1_024)
            : 0

        let maxKVSize: Int?
        if availableMemory < severeMemoryHeadroomBytes && estimatedPromptTokens > 2_048 {
            maxKVSize = 2_048
        } else if isMemoryConstrained && estimatedPromptTokens > 4_096 {
            maxKVSize = 4_096
        } else {
            maxKVSize = nil
        }

        let mlxCacheLimitBytes: Int
        if availableMemory < severeMemoryHeadroomBytes {
            mlxCacheLimitBytes = 8 * 1024 * 1024
        } else if isMemoryConstrained {
            mlxCacheLimitBytes = defaultMLXCacheLimitBytes
        } else if supportsVision || (estimatedModelSizeGB ?? 0) >= 3 {
            mlxCacheLimitBytes = 32 * 1024 * 1024
        } else if availableMemory >= highMemoryHeadroomBytes {
            mlxCacheLimitBytes = 64 * 1024 * 1024
        } else {
            mlxCacheLimitBytes = 32 * 1024 * 1024
        }

        return InferenceOptimizationPlan(
            prefillStepSize: prefillStepSize,
            maxKVSize: maxKVSize,
            kvBits: shouldQuantizeKVCache ? 8 : nil,
            kvGroupSize: 64,
            quantizedKVStart: quantizedKVStart,
            mlxCacheLimitBytes: mlxCacheLimitBytes,
            visionInputSize: isMemoryConstrained ? 384 : 512,
            shouldClearCacheBeforeGeneration: availableMemory < severeMemoryHeadroomBytes
        )
    }

    static func shouldReclaimCache(availableMemoryBytes: UInt64?) -> Bool {
        guard let availableMemoryBytes else { return false }
        return availableMemoryBytes < cacheReclaimHeadroomBytes
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

    static func shouldClearCacheBetweenSpeechStages(availableMemoryBytes: UInt64?) -> Bool {
        guard let availableMemoryBytes else { return true }
        return availableMemoryBytes < constrainedMemoryHeadroomBytes
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
