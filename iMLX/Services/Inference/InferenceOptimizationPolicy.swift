import Foundation

nonisolated struct InferenceOptimizationPlan: Equatable, Sendable {
    let prefillStepSize: Int
    let kvBits: Int?
    let kvGroupSize: Int
    let quantizedKVStart: Int
    let shouldClearCacheBeforeGeneration: Bool
}

nonisolated enum InferenceOptimizationPolicy {
    static let mlxCacheLimitBytes = 20 * 1024 * 1024

    private static let severeMemoryHeadroomBytes: UInt64 = 512 * 1024 * 1024
    private static let constrainedMemoryHeadroomBytes: UInt64 = 1_200 * 1024 * 1024
    private static let cacheReclaimHeadroomBytes: UInt64 = 768 * 1024 * 1024
    private static let kvQuantizationTokenThreshold = 1_536

    static func plan(
        contextTextBytes: Int,
        contextMediaAttachmentCount: Int,
        maxTokens: Int,
        availableMemoryBytes: UInt64?,
        allowsKVQuantization: Bool = true
    ) -> InferenceOptimizationPlan {
        let availableMemory = availableMemoryBytes ?? .max
        let estimatedPromptTokens = max(1, (max(0, contextTextBytes) + 2) / 3)
        let estimatedPeakCacheTokens = estimatedPromptTokens + max(0, maxTokens)
        let isMemoryConstrained = availableMemory < constrainedMemoryHeadroomBytes

        let prefillStepSize: Int
        if availableMemory < severeMemoryHeadroomBytes {
            prefillStepSize = 128
        } else if contextMediaAttachmentCount > 0 || isMemoryConstrained {
            prefillStepSize = 256
        } else {
            prefillStepSize = 512
        }

        let shouldQuantizeKVCache = allowsKVQuantization
            && (isMemoryConstrained || estimatedPeakCacheTokens >= kvQuantizationTokenThreshold)

        return InferenceOptimizationPlan(
            prefillStepSize: prefillStepSize,
            kvBits: shouldQuantizeKVCache ? 8 : nil,
            kvGroupSize: 64,
            quantizedKVStart: shouldQuantizeKVCache ? 512 : 0,
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
        let normalizedIdentity = [modelIdentifier, modelName]
            .compactMap { $0?.lowercased() }
            .joined(separator: " ")
        return !normalizedIdentity.contains("gemma4")
            && !normalizedIdentity.contains("gemma-4")
            && !normalizedIdentity.contains("gemma_4")
    }
}
