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

    func testLinksPhoneNumbers() {
        let input = "Phone: +34 628 72 83 29"

        XCTAssertEqual(
            MarkdownSanitizer.linkingPhoneNumbers(from: input),
            "Phone: [+34 628 72 83 29](tel:+34628728329)"
        )
    }

    func testKeepsExistingPhoneLinksUnchanged() {
        let input = "Phone: [+34 628 72 83 29](tel:+34628728329)"

        XCTAssertEqual(MarkdownSanitizer.linkingPhoneNumbers(from: input), input)
    }

    func testPhoneLinkingKeepsCodeFencesUnchanged() {
        let input = """
        ```text
        Phone: +34 628 72 83 29
        ```
        """

        XCTAssertEqual(MarkdownSanitizer.linkingPhoneNumbers(from: input), input)
    }

    func testPhoneLinkingKeepsInlineCodeUnchanged() {
        let input = "Use `+34 628 72 83 29` as sample text."

        XCTAssertEqual(MarkdownSanitizer.linkingPhoneNumbers(from: input), input)
    }
}
