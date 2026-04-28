import XCTest
@testable import iMLX

final class MarkdownSanitizerTests: XCTestCase {
    func testRemovesRemoteMarkdownImage() {
        let input = "Before ![Chart](https://example.com/chart.png) after"

        XCTAssertEqual(
            MarkdownSanitizer.removingRemoteImages(from: input),
            "Before [Image: Chart] after"
        )
    }

    func testKeepsNormalLinks() {
        let input = "Read [the docs](https://example.com/docs)."

        XCTAssertEqual(MarkdownSanitizer.removingRemoteImages(from: input), input)
    }

    func testKeepsCodeFencesUnchanged() {
        let input = """
        ```swift
        let sample = "![Image](https://example.com/image.png)"
        ```
        """

        XCTAssertEqual(MarkdownSanitizer.removingRemoteImages(from: input), input)
    }

    func testKeepsTablesUnchanged() {
        let input = """
        | Name | Value |
        | --- | --- |
        | A | B |
        """

        XCTAssertEqual(MarkdownSanitizer.removingRemoteImages(from: input), input)
    }

    func testKeepsPlainTextUnchanged() {
        let input = "Just a local answer with no markdown image."

        XCTAssertEqual(MarkdownSanitizer.removingRemoteImages(from: input), input)
    }
}
