import XCTest
@testable import iMLX

final class InferenceOptimizationPolicyTests: XCTestCase {
    private let mobileHost = HostMemoryProfile(
        platformClass: .mobile,
        physicalMemoryBytes: 8 * HostMemoryProfile.gigabyte
    )
    private let desktopHost = HostMemoryProfile(
        platformClass: .desktop,
        physicalMemoryBytes: 32 * HostMemoryProfile.gigabyte
    )

    func testUsesDefaultPrefillForShortHighHeadroomMobileRuns() {
        let plan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 600,
            contextMediaAttachmentCount: 0,
            maxTokens: 128,
            availableMemoryBytes: 2_000 * HostMemoryProfile.megabyte,
            host: mobileHost
        )

        XCTAssertEqual(plan.prefillStepSize, 512)
        XCTAssertNil(plan.maxKVSize)
        XCTAssertEqual(plan.mlxCacheLimitBytes, 64 * Int(HostMemoryProfile.megabyte))
        XCTAssertFalse(plan.shouldClearCacheBeforeGeneration)
    }

    func testKVCacheShapeIsStableAcrossConversationGrowth() {
        // The reusable prefix session is keyed on KV cache shape, so a conversation that grows past
        // any internal threshold must not silently change these fields and force a re-prefill.
        let shortTurn = InferenceOptimizationPolicy.plan(
            contextTextBytes: 600,
            contextMediaAttachmentCount: 0,
            maxTokens: 4_096,
            availableMemoryBytes: 2_000 * HostMemoryProfile.megabyte,
            host: mobileHost
        )
        let longTurn = InferenceOptimizationPolicy.plan(
            contextTextBytes: 9_000,
            contextMediaAttachmentCount: 0,
            maxTokens: 4_096,
            availableMemoryBytes: 2_000 * HostMemoryProfile.megabyte,
            host: mobileHost
        )
        let longTurnUnderPressure = InferenceOptimizationPolicy.plan(
            contextTextBytes: 9_000,
            contextMediaAttachmentCount: 0,
            maxTokens: 4_096,
            availableMemoryBytes: 400 * HostMemoryProfile.megabyte,
            host: mobileHost
        )

        XCTAssertEqual(shortTurn.kvBits, 8)
        XCTAssertEqual(shortTurn.quantizedKVStart, 1_024)
        XCTAssertEqual(shortTurn.kvBits, longTurn.kvBits)
        XCTAssertEqual(shortTurn.quantizedKVStart, longTurn.quantizedKVStart)
        XCTAssertEqual(shortTurn.maxKVSize, longTurn.maxKVSize)
        XCTAssertEqual(longTurn.kvBits, longTurnUnderPressure.kvBits)
        XCTAssertEqual(longTurn.quantizedKVStart, longTurnUnderPressure.quantizedKVStart)
        XCTAssertEqual(longTurn.maxKVSize, longTurnUnderPressure.maxKVSize)
    }

    func testDesktopDelaysKVQuantizationAndSkipsWindowingOnLargeMemory() {
        let plan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 60_000,
            contextMediaAttachmentCount: 0,
            maxTokens: 4_096,
            availableMemoryBytes: 12 * HostMemoryProfile.gigabyte,
            host: desktopHost
        )

        XCTAssertEqual(plan.kvBits, 8)
        XCTAssertEqual(plan.quantizedKVStart, 4_096)
        XCTAssertNil(plan.maxKVSize)
    }

    func testBoundsKVWindowOnceConversationOutgrowsHost() {
        let plan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 30_000,
            contextMediaAttachmentCount: 0,
            maxTokens: 1_024,
            availableMemoryBytes: 2_000 * HostMemoryProfile.megabyte,
            host: mobileHost
        )

        XCTAssertEqual(plan.maxKVSize, 8_192)
    }

    func testReducesPrefillForMediaAndMemoryPressureButNotVisionCapabilityAlone() {
        let mediaPlan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 600,
            contextMediaAttachmentCount: 1,
            maxTokens: 128,
            availableMemoryBytes: 2_000 * HostMemoryProfile.megabyte,
            supportsVision: true,
            host: mobileHost
        )
        let textOnlyVisionModelPlan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 600,
            contextMediaAttachmentCount: 0,
            maxTokens: 128,
            availableMemoryBytes: 2_000 * HostMemoryProfile.megabyte,
            supportsVision: true,
            host: mobileHost
        )
        let severePressurePlan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 600,
            contextMediaAttachmentCount: 0,
            maxTokens: 128,
            availableMemoryBytes: 400 * HostMemoryProfile.megabyte,
            host: mobileHost
        )

        XCTAssertEqual(mediaPlan.prefillStepSize, 256)
        XCTAssertEqual(mediaPlan.visionInputSize, 512)
        XCTAssertNil(mediaPlan.kvBits)
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
            availableMemoryBytes: 700 * HostMemoryProfile.megabyte,
            allowsKVQuantization: false,
            host: mobileHost
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
        let mobilePlan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 900,
            contextMediaAttachmentCount: 0,
            maxTokens: 512,
            availableMemoryBytes: 2_000 * HostMemoryProfile.megabyte,
            modelIdentifier: "qwen3.5-4b-4bit",
            host: mobileHost
        )
        let desktopPlan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 900,
            contextMediaAttachmentCount: 0,
            maxTokens: 512,
            availableMemoryBytes: 12 * HostMemoryProfile.gigabyte,
            modelIdentifier: "qwen3.5-4b-4bit",
            host: desktopHost
        )

        XCTAssertEqual(mobilePlan.prefillStepSize, 1_024)
        XCTAssertEqual(desktopPlan.prefillStepSize, 4_096)
    }

    func testDesktopUsesLargerBuffersAndPrefillThanMobile() {
        let desktopPlan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 600,
            contextMediaAttachmentCount: 0,
            maxTokens: 512,
            availableMemoryBytes: 12 * HostMemoryProfile.gigabyte,
            host: desktopHost
        )
        let mobilePlan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 600,
            contextMediaAttachmentCount: 0,
            maxTokens: 512,
            availableMemoryBytes: 2_000 * HostMemoryProfile.megabyte,
            host: mobileHost
        )

        XCTAssertEqual(desktopPlan.prefillStepSize, 2_048)
        XCTAssertEqual(desktopPlan.visionInputSize, 768)
        // 32 GB / 16 = 2 GB, clamped to the 1.5 GB ceiling.
        XCTAssertEqual(desktopPlan.mlxCacheLimitBytes, 1_536 * Int(HostMemoryProfile.megabyte))
        XCTAssertGreaterThan(desktopPlan.mlxCacheLimitBytes, mobilePlan.mlxCacheLimitBytes)
    }

    func testDesktopStillProtectsItselfUnderRealMemoryPressure() {
        let plan = InferenceOptimizationPolicy.plan(
            contextTextBytes: 600,
            contextMediaAttachmentCount: 0,
            maxTokens: 512,
            availableMemoryBytes: HostMemoryProfile.gigabyte,
            host: desktopHost
        )

        XCTAssertEqual(plan.prefillStepSize, 512)
        XCTAssertEqual(plan.mlxCacheLimitBytes, 64 * Int(HostMemoryProfile.megabyte))
        XCTAssertTrue(plan.shouldClearCacheBeforeGeneration)
    }

    func testCacheReclamationScalesWithHostMemory() {
        XCTAssertTrue(
            InferenceOptimizationPolicy.shouldReclaimCache(
                availableMemoryBytes: 700 * HostMemoryProfile.megabyte,
                host: mobileHost
            )
        )
        XCTAssertFalse(
            InferenceOptimizationPolicy.shouldReclaimCache(
                availableMemoryBytes: 1_000 * HostMemoryProfile.megabyte,
                host: mobileHost
            )
        )
        XCTAssertFalse(
            InferenceOptimizationPolicy.shouldReclaimCache(
                availableMemoryBytes: nil,
                host: mobileHost
            )
        )
        // The same absolute headroom that is comfortable on a phone is tight on a 32 GB Mac.
        XCTAssertTrue(
            InferenceOptimizationPolicy.shouldReclaimCache(
                availableMemoryBytes: 2 * HostMemoryProfile.gigabyte,
                host: desktopHost
            )
        )
    }

    func testMemoryLimitLeavesHeadroomWithoutStarvingLargeModels() {
        let mobileLimit = InferenceOptimizationPolicy.memoryLimitBytes(host: mobileHost)
        let desktopLimit = InferenceOptimizationPolicy.memoryLimitBytes(host: desktopHost)

        XCTAssertLessThan(UInt64(mobileLimit), mobileHost.physicalMemoryBytes)
        XCTAssertLessThan(UInt64(desktopLimit), desktopHost.physicalMemoryBytes)
        // The allocation ceiling has to sit above the size of a model the device is allowed to
        // load, otherwise MLX would throttle itself on every run.
        XCTAssertGreaterThan(UInt64(mobileLimit), mobileHost.usableMemoryEstimateBytes)
        XCTAssertGreaterThan(UInt64(desktopLimit), 0)
    }

    func testSmallPhoneMemoryLimitStaysAboveItsModelBudget() {
        let smallPhone = HostMemoryProfile(
            platformClass: .mobile,
            physicalMemoryBytes: 6 * HostMemoryProfile.gigabyte
        )

        XCTAssertGreaterThan(
            UInt64(InferenceOptimizationPolicy.memoryLimitBytes(host: smallPhone)),
            smallPhone.usableMemoryEstimateBytes
        )
    }
}
