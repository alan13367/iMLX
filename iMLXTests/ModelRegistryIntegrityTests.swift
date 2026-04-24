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
}
