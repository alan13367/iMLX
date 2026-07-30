import XCTest
import Textual
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

    func testNormalizesParenthesizedInlineLaTeXDelimiters() {
        XCTAssertEqual(
            MarkdownSanitizer.normalizingLaTeXDelimiters(
                from: #"Euler wrote \(e^{i\pi} + 1 = 0\)."#
            ),
            #"Euler wrote $e^{i\pi} + 1 = 0$."#
        )
    }

    func testNormalizesBracketedDisplayLaTeXDelimiters() {
        let input = """
        \\[
        \\int_0^1 x^2\\,dx = \\frac{1}{3}
        \\]
        """

        XCTAssertEqual(
            MarkdownSanitizer.normalizingLaTeXDelimiters(from: input),
            """
            $$
            \\int_0^1 x^2\\,dx = \\frac{1}{3}
            $$
            """
        )
    }

    func testKeepsLaTeXDelimitersInsideCodeUnchanged() {
        let input = """
        `\\(inline sample\\)`

        ```text
        \\[
        x^2
        \\]
        ```
        """

        XCTAssertEqual(MarkdownSanitizer.normalizingLaTeXDelimiters(from: input), input)
    }

    func testCodeFenceMustCloseWithMatchingMarkerAndLength() {
        let input = """
        ````text
        \\(inside long fence\\)
        ```
        \\[still inside long fence\\]
        ````
        \\(outside fence\\)
        """

        XCTAssertEqual(
            MarkdownSanitizer.normalizingLaTeXDelimiters(from: input),
            """
            ````text
            \\(inside long fence\\)
            ```
            \\[still inside long fence\\]
            ````
            $outside fence$
            """
        )
    }

    func testTildeFenceProtectsSanitizers() {
        let input = """
        ~~~text
        \\(math\\) ![Image](https://example.com/image.png) +34 628 72 83 29
        ~~~
        """

        XCTAssertEqual(MarkdownSanitizer.preparingForRendering(input), input)
        XCTAssertEqual(MarkdownSanitizer.linkingPhoneNumbers(from: input), input)
    }

    func testKeepsExistingDollarMathDelimitersUnchanged() {
        let input = "Inline $x^2$ and block $$E = mc^2$$."

        XCTAssertEqual(MarkdownSanitizer.normalizingLaTeXDelimiters(from: input), input)
    }

    func testTextualMathExtensionCreatesInlineAndBlockAttachments() throws {
        let markdown = MarkdownSanitizer.preparingForRendering(
            #"Inline \(x^2\) and block \[E = mc^2\]."#
        )
        let parser = AttributedStringMarkdownParser(
            baseURL: nil,
            syntaxExtensions: [.math]
        )

        let attributed = try parser.attributedString(for: markdown)
        let attachmentCount = attributed.characters.filter { $0 == "\u{FFFC}" }.count

        XCTAssertEqual(attachmentCount, 2)
    }
}
