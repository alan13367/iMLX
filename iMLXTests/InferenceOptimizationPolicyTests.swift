import XCTest
@testable import iMLX

final class InferenceOptimizationPolicyTests: XCTestCase {
    func testUsesDefaultPrefillAndUnquantizedKVForShortHighHeadroomRuns() {
        let plan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 600,
            contextMediaAttachmentCount: 0,
            maxTokens: 128,
            availableMemoryBytes: 2_000 * 1024 * 1024
        )

        XCTAssertEqual(plan.prefillStepSize, 512)
        XCTAssertNil(plan.kvBits)
        XCTAssertNil(plan.maxKVSize)
        XCTAssertEqual(plan.mlxCacheLimitBytes, 64 * 1024 * 1024)
        XCTAssertFalse(plan.shouldClearCacheBeforeGeneration)
    }

    func testDoesNotQuantizeKVForUnusedStandardGenerationBudget() {
        let plan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 3_000,
            contextMediaAttachmentCount: 0,
            maxTokens: 4_096,
            availableMemoryBytes: 2_000 * 1024 * 1024
        )

        // Short prompts should not pay KV quant just because maxTokens is large.
        XCTAssertNil(plan.kvBits)
    }

    func testQuantizesKVWhenLikelyActiveCacheIsLarge() {
        let plan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 3_600,
            contextMediaAttachmentCount: 0,
            maxTokens: 4_096,
            availableMemoryBytes: 2_000 * 1024 * 1024
        )

        // ~1200 prompt tokens + capped 2048 generation tokens crosses the active-cache threshold.
        XCTAssertEqual(plan.kvBits, 8)
        XCTAssertEqual(plan.quantizedKVStart, 1_024)
    }

    func testQuantizesKVForLongPrompt() {
        let plan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 4_500,
            contextMediaAttachmentCount: 0,
            maxTokens: 1_024,
            availableMemoryBytes: 2_000 * 1024 * 1024
        )

        XCTAssertEqual(plan.kvBits, 8)
        XCTAssertEqual(plan.kvGroupSize, 64)
        XCTAssertEqual(plan.quantizedKVStart, 1_024)
    }

    func testReducesPrefillForMediaAndMemoryPressureButNotVisionCapabilityAlone() {
        let mediaPlan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 600,
            contextMediaAttachmentCount: 1,
            maxTokens: 128,
            availableMemoryBytes: 2_000 * 1024 * 1024,
            supportsVision: true
        )
        let textOnlyVisionModelPlan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 600,
            contextMediaAttachmentCount: 0,
            maxTokens: 128,
            availableMemoryBytes: 2_000 * 1024 * 1024,
            supportsVision: true
        )
        let severePressurePlan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 600,
            contextMediaAttachmentCount: 0,
            maxTokens: 128,
            availableMemoryBytes: 400 * 1024 * 1024
        )

        XCTAssertEqual(mediaPlan.prefillStepSize, 256)
        XCTAssertEqual(mediaPlan.visionInputSize, 512)
        XCTAssertEqual(textOnlyVisionModelPlan.prefillStepSize, 512)
        XCTAssertEqual(severePressurePlan.prefillStepSize, 128)
        XCTAssertEqual(severePressurePlan.visionInputSize, 384)
        XCTAssertTrue(severePressurePlan.shouldClearCacheBeforeGeneration)
        XCTAssertEqual(severePressurePlan.kvBits, 8)
    }

    func testCanDisableKVQuantizationForModelFamiliesThatDoNotSupportItReliably() {
        let plan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 6_000,
            contextMediaAttachmentCount: 0,
            maxTokens: 4_096,
            availableMemoryBytes: 700 * 1024 * 1024,
            allowsKVQuantization: false
        )

        XCTAssertNil(plan.kvBits)
        XCTAssertEqual(plan.quantizedKVStart, 0)
    }

    func testDisablesKVQuantizationForVisionAndGemma4Models() {
        XCTAssertFalse(
            InferenceOptimizationPolicy.allowsKVQuantization(
                modelIdentifier: "gemma4-e2b-it-4bit",
                modelName: "Gemma 4 E2B",
                supportsVision: false
            )
        )
        XCTAssertFalse(
            InferenceOptimizationPolicy.allowsKVQuantization(
                modelIdentifier: "qwen3-vl-4bit",
                modelName: "Qwen3 VL",
                supportsVision: true
            )
        )
        XCTAssertTrue(
            InferenceOptimizationPolicy.allowsKVQuantization(
                modelIdentifier: "qwen3-4b-4bit",
                modelName: "Qwen3 4B",
                supportsVision: false
            )
        )
    }

    func testUsesPipelinedLargePrefillForHybridModels() {
        let plan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 900,
            contextMediaAttachmentCount: 0,
            maxTokens: 512,
            availableMemoryBytes: 2_000 * 1024 * 1024,
            modelIdentifier: "qwen3.5-4b-4bit"
        )

        XCTAssertEqual(plan.prefillStepSize, 1_024)
    }

    func testBoundsVeryLongContextWhenMemoryIsConstrained() {
        let plan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 15_000,
            contextMediaAttachmentCount: 0,
            maxTokens: 1_024,
            availableMemoryBytes: 400 * 1024 * 1024
        )

        XCTAssertEqual(plan.maxKVSize, 2_048)
        XCTAssertEqual(plan.mlxCacheLimitBytes, 8 * 1024 * 1024)
    }

    func testCacheReclamationOnlyTriggersAtLowHeadroom() {
        XCTAssertTrue(
            InferenceOptimizationPolicy.shouldReclaimCache(
                availableMemoryBytes: 700 * 1024 * 1024
            )
        )
        XCTAssertFalse(
            InferenceOptimizationPolicy.shouldReclaimCache(
                availableMemoryBytes: 1_000 * 1024 * 1024
            )
        )
        XCTAssertFalse(
            InferenceOptimizationPolicy.shouldReclaimCache(availableMemoryBytes: nil)
        )
    }
}
