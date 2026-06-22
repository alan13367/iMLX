import XCTest
@testable import iMLX

final class GroundingTextTests: XCTestCase {
    func testNormalizeWhitespaceCollapsesAndTrims() {
        XCTAssertEqual(
            GroundingText.normalizeWhitespace("  hello \n\t world  "),
            "hello world"
        )
    }

    func testLexicalSimilarityUsesQueryCoverage() {
        XCTAssertEqual(
            GroundingText.lexicalSimilarity(
                query: "Barcelona yellow warning",
                text: "A yellow heat warning applies to Barcelona."
            ),
            1,
            accuracy: 0.0001
        )
    }

    func testCosineSimilarityRejectsInvalidAndNegativeScores() {
        XCTAssertEqual(GroundingText.cosineSimilarity([1, 0], [1, 0]), 1, accuracy: 0.0001)
        XCTAssertEqual(GroundingText.cosineSimilarity([1], [1, 2]), 0)
        XCTAssertEqual(GroundingText.cosineSimilarity([1, 0], [-1, 0]), 0)
    }

    func testExcerptPreservesConfiguredFormatting() {
        XCTAssertEqual(
            GroundingText.excerpt(
                from: "one   two three",
                maximumCharacters: 7,
                suffix: "…"
            ),
            "one two…"
        )
        XCTAssertEqual(
            GroundingText.excerpt(
                from: "one   two",
                maximumCharacters: 5,
                normalizingWhitespace: false
            ),
            "one..."
        )
    }
}
