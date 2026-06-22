import XCTest
@testable import iMLX

final class DocumentCSVParserTests: XCTestCase {
    func testQuotedCommaRemainsInsideField() {
        XCTAssertEqual(
            DocumentCSVParser.fields(in: #"name,"city, country",age"#),
            ["name", "city, country", "age"]
        )
    }

    func testPairRetainsExtraHeadersAndValues() {
        let missingValue = DocumentCSVParser.pair(
            headers: ["name", "city"],
            values: ["Alan"]
        )
        XCTAssertEqual(missingValue.map(\.header), ["name", "city"])
        XCTAssertEqual(missingValue.map(\.value), ["Alan", ""])

        let missingHeader = DocumentCSVParser.pair(
            headers: ["name"],
            values: ["Alan", "Madrid"]
        )
        XCTAssertEqual(missingHeader.map(\.header), ["name", ""])
        XCTAssertEqual(missingHeader.map(\.value), ["Alan", "Madrid"])
    }
}
