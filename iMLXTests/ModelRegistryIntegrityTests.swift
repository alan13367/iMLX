import XCTest
@testable import iMLX

final class ModelRegistryIntegrityTests: XCTestCase {
    func testCuratedModelIDsAreUnique() {
        let models = Constants.ModelRegistry.curatedModels
        let ids = models.map(\.id)

        XCTAssertEqual(Set(ids).count, models.count)
    }

    func testCuratedModelsHaveValidRepositoryIdentifiers() {
        for model in Constants.ModelRegistry.curatedModels {
            XCTAssertFalse(model.huggingFaceId.isEmpty)
            XCTAssertTrue(model.huggingFaceId.contains("/"), "Expected org/repo format for \(model.id)")
        }
    }

    func testCuratedModelsHavePositiveSizeAndMemoryRequirements() {
        for model in Constants.ModelRegistry.curatedModels {
            XCTAssertGreaterThan(model.estimatedSizeGB, 0)
            XCTAssertGreaterThan(model.minDeviceRAM, 0)
        }
    }

    func testLFM25BenchmarkQuantizationsAreAvailable() {
        let modelsByID = Dictionary(
            uniqueKeysWithValues: Constants.ModelRegistry.curatedModels.map { ($0.id, $0) }
        )

        XCTAssertEqual(modelsByID["lfm2.5-350m-bf16"]?.huggingFaceId, "LiquidAI/LFM2.5-350M-MLX-bf16")
        XCTAssertEqual(modelsByID["lfm2.5-350m-8bit"]?.huggingFaceId, "LiquidAI/LFM2.5-350M-MLX-8bit")
        XCTAssertEqual(modelsByID["lfm2.5-350m-6bit"]?.huggingFaceId, "LiquidAI/LFM2.5-350M-MLX-6bit")
        XCTAssertEqual(modelsByID["lfm2.5-350m-5bit"]?.huggingFaceId, "LiquidAI/LFM2.5-350M-MLX-5bit")
        XCTAssertEqual(modelsByID["lfm2.5-350m-4bit"]?.huggingFaceId, "LiquidAI/LFM2.5-350M-MLX-4bit")
    }
}
