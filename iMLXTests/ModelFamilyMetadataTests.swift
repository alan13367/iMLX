import XCTest
@testable import iMLX

final class ModelFamilyMetadataTests: XCTestCase {
    func testModelFamilySortOrdersAreUnique() {
        let allFamilies = ModelInfo.ModelFamily.allCases
        let sortOrders = allFamilies.map(\.sortOrder)

        XCTAssertEqual(Set(sortOrders).count, allFamilies.count)
    }

    func testModelFamilyCopyIsPopulated() {
        for family in ModelInfo.ModelFamily.allCases {
            XCTAssertFalse(family.displayName.isEmpty)
            XCTAssertFalse(family.familyDescription.isEmpty)
            XCTAssertFalse(family.logoName.isEmpty)
        }
    }

    func testQwenFamiliesShareQwenLogo() {
        XCTAssertEqual(ModelInfo.ModelFamily.qwen3.logoName, "qwen_logo")
        XCTAssertEqual(ModelInfo.ModelFamily.qwen35.logoName, "qwen_logo")
        XCTAssertEqual(ModelInfo.ModelFamily.qwen2vl.logoName, "qwen_logo")
    }
}
