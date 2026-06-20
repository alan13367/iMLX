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
        XCTAssertFalse(plan.shouldClearCacheBeforeGeneration)
    }

    func testQuantizesKVForLongGenerationBudget() {
        let plan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 3_000,
            contextMediaAttachmentCount: 0,
            maxTokens: 1_024,
            availableMemoryBytes: 2_000 * 1024 * 1024
        )

        XCTAssertEqual(plan.kvBits, 8)
        XCTAssertEqual(plan.kvGroupSize, 64)
        XCTAssertEqual(plan.quantizedKVStart, 512)
    }

    func testReducesPrefillForVisionAndMemoryPressure() {
        let visionPlan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 600,
            contextMediaAttachmentCount: 1,
            maxTokens: 128,
            availableMemoryBytes: 2_000 * 1024 * 1024
        )
        let severePressurePlan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 600,
            contextMediaAttachmentCount: 0,
            maxTokens: 128,
            availableMemoryBytes: 400 * 1024 * 1024
        )

        XCTAssertEqual(visionPlan.prefillStepSize, 256)
        XCTAssertEqual(severePressurePlan.prefillStepSize, 128)
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
