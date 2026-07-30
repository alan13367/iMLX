import XCTest
@testable import iMLX

final class StreamingMarkdownAccumulatorTests: XCTestCase {
    func testSourceCursorExtractsOnlyAppendedUTF8AndRejectsReplacement() {
        var cursor = StreamingSourceCursor()

        XCTAssertEqual(cursor.consume("Hello"), "Hello")
        XCTAssertEqual(cursor.consume("Hello 🌍"), " 🌍")
        XCTAssertNil(cursor.consume("Hallo 🌍"))

        cursor = StreamingSourceCursor(source: "Hallo 🌍")
        XCTAssertEqual(cursor.consume("Hallo 🌍!"), "!")
    }

    func testArbitraryTokenBoundariesAlwaysReconstructOriginalMarkdown() {
        let markdown = """
        # Heading

        A paragraph with **bold**, _italic_, `code`, and a [link](https://example.com).

        - First
          - Nested
        - Last

        > A quote
        >
        > Continued

        | Name | Value |
        | --- | ---: |
        | A | B |

        ```swift
        let blankLine = true

        print(blankLine)
        ```
        """

        var accumulator = StreamingMarkdownAccumulator()
        var prefix = ""
        for character in markdown {
            prefix.append(character)
            let snapshot = accumulator.consume(appending: String(character))
            XCTAssertEqual(snapshot.reconstructedSource, prefix)
        }
    }

    func testParagraphAndTableFinalizeAtBlankLineBoundaries() {
        var accumulator = StreamingMarkdownAccumulator()

        let paragraph = accumulator.consume(appending: "Paragraph.\n\n")
        XCTAssertEqual(paragraph.completedSegments.map(\.source), ["Paragraph.\n\n"])
        XCTAssertEqual(paragraph.activeTail, "")

        let table = accumulator.consume(appending: "| A | B |\n| --- | --- |\n| 1 | 2 |\n\n")
        XCTAssertEqual(table.completedSegments.count, 2)
        if table.completedSegments.count == 2 {
            XCTAssertEqual(
                table.completedSegments[1].source,
                "| A | B |\n| --- | --- |\n| 1 | 2 |\n\n"
            )
        }
        XCTAssertEqual(table.activeTailKind, .inline)
    }

    func testHeadingsAndThematicBreaksFinalizeAfterCompletedLine() {
        var accumulator = StreamingMarkdownAccumulator()

        var snapshot = accumulator.consume(appending: "# Heading\n")
        XCTAssertEqual(snapshot.completedSegments.map(\.source), ["# Heading\n"])

        snapshot = accumulator.consume(appending: "---\n")
        XCTAssertEqual(snapshot.completedSegments.map(\.source), ["# Heading\n", "---\n"])

        snapshot = accumulator.consume(appending: "Setext\n===\n")
        XCTAssertEqual(snapshot.completedSegments.last?.source, "Setext\n===\n")
    }

    func testLooseNestedListWaitsForLookaheadBeforeFinalizing() {
        var accumulator = StreamingMarkdownAccumulator()

        var snapshot = accumulator.consume(appending: "- First\n  - Nested\n\n")
        XCTAssertTrue(snapshot.completedSegments.isEmpty)
        XCTAssertEqual(snapshot.activeTailKind, .list)

        snapshot = accumulator.consume(appending: "- Second\n")
        XCTAssertTrue(snapshot.completedSegments.isEmpty)

        snapshot = accumulator.consume(appending: "\nNext paragraph")
        XCTAssertEqual(
            snapshot.completedSegments.map(\.source),
            ["- First\n  - Nested\n\n- Second\n\n"]
        )
        XCTAssertEqual(snapshot.activeTail, "Next paragraph")
        XCTAssertEqual(snapshot.activeTailKind, .inline)
    }

    func testBlockQuoteWaitsForLookaheadBeforeFinalizing() {
        var accumulator = StreamingMarkdownAccumulator()

        var snapshot = accumulator.consume(appending: "> First\n>\n")
        XCTAssertTrue(snapshot.completedSegments.isEmpty)
        XCTAssertEqual(snapshot.activeTailKind, .blockQuote)

        snapshot = accumulator.consume(appending: "> Second\n\nFollowing")
        XCTAssertEqual(
            snapshot.completedSegments.map(\.source),
            ["> First\n>\n> Second\n\n"]
        )
        XCTAssertEqual(snapshot.activeTail, "Following")
    }

    func testFencedCodeDoesNotFinalizeAtInternalBlankLines() {
        var accumulator = StreamingMarkdownAccumulator()

        var snapshot = accumulator.consume(appending: "```swift\nlet value = 1\n\n")
        XCTAssertTrue(snapshot.completedSegments.isEmpty)
        XCTAssertEqual(snapshot.activeTailKind, .fencedCode)

        snapshot = accumulator.consume(appending: "print(value)\n```\n")
        XCTAssertEqual(snapshot.completedSegments.count, 1)
        XCTAssertEqual(
            snapshot.completedSegments[0].source,
            "```swift\nlet value = 1\n\nprint(value)\n```\n"
        )
        XCTAssertEqual(snapshot.activeTail, "")
    }

    func testDisplayMathFinalizesOnlyAfterClosingDelimiter() {
        var accumulator = StreamingMarkdownAccumulator()

        var snapshot = accumulator.consume(appending: "$$\n\\int_0^1 x^2\\,dx\n")
        XCTAssertTrue(snapshot.completedSegments.isEmpty)
        XCTAssertEqual(snapshot.activeTailKind, .displayMath)

        snapshot = accumulator.consume(appending: "$$\n")
        XCTAssertEqual(
            snapshot.completedSegments.map(\.source),
            ["$$\n\\int_0^1 x^2\\,dx\n$$\n"]
        )
        XCTAssertEqual(snapshot.activeTail, "")
    }

    func testBracketedDisplayMathIsRecognizedBeforeRenderNormalization() {
        var accumulator = StreamingMarkdownAccumulator()

        var snapshot = accumulator.consume(appending: "\\[\nx^2\n")
        XCTAssertEqual(snapshot.activeTailKind, .displayMath)

        snapshot = accumulator.consume(appending: "\\]\n")
        XCTAssertEqual(snapshot.completedSegments.map(\.source), ["\\[\nx^2\n\\]\n"])
    }

    func testIncompleteStructuralTailKindsRemainNonInline() {
        var accumulator = StreamingMarkdownAccumulator()
        XCTAssertEqual(
            accumulator.consume(appending: "```swi").activeTailKind,
            .fencedCode
        )

        var replacementAccumulator = StreamingMarkdownAccumulator()
        XCTAssertEqual(
            replacementAccumulator.consume(appending: "- item").activeTailKind,
            .list
        )

        var quoteAccumulator = StreamingMarkdownAccumulator()
        XCTAssertEqual(
            quoteAccumulator.consume(appending: "> quote").activeTailKind,
            .blockQuote
        )

        var headingAccumulator = StreamingMarkdownAccumulator()
        XCTAssertEqual(
            headingAccumulator.consume(appending: "## Heading").activeTailKind,
            .heading
        )
    }

    func testCommittedSegmentsKeepStableIdentityAndSource() throws {
        var accumulator = StreamingMarkdownAccumulator()

        let committed = accumulator.consume(appending: "First paragraph.\n\n")
        let original = try XCTUnwrap(committed.completedSegments.first)

        let updated = accumulator.consume(appending: "Second paragraph still streaming")
        XCTAssertEqual(updated.completedSegments.first, original)
        XCTAssertEqual(updated.completedSegments.count, 1)
    }

    func testNonPrefixReplacementResetsContentWithoutReusingSegmentIDs() throws {
        var accumulator = StreamingMarkdownAccumulator()

        let first = accumulator.consume(appending: "First.\n\n")
        let firstID = try XCTUnwrap(first.completedSegments.first?.id)

        let replacement = accumulator.reset(with: "Replacement.\n\n")
        XCTAssertEqual(replacement.resetGeneration, 1)
        XCTAssertEqual(replacement.reconstructedSource, "Replacement.\n\n")
        XCTAssertGreaterThan(
            try XCTUnwrap(replacement.completedSegments.first?.id),
            firstID
        )
    }

    func testStreamingSanitizationRemovesRemoteImagesFromActiveTail() {
        var accumulator = StreamingMarkdownAccumulator()
        let snapshot = accumulator.consume(
            appending: "Preview ![chart](https://example.com/chart.png)"
        )

        XCTAssertEqual(
            MarkdownSanitizer.removingRemoteImages(from: snapshot.activeTail),
            "Preview [Image: chart]"
        )
    }

    func testProcessedWorkGrowsOnlyByAppendedCharactersAndDoesNotReparseCommittedSegments() throws {
        var accumulator = StreamingMarkdownAccumulator()
        var source = "Stable paragraph.\n\n"
        var snapshot = accumulator.consume(appending: source)
        let stableSegment = try XCTUnwrap(snapshot.completedSegments.first)

        for index in 0..<2_000 {
            let appendedText = String(index % 10)
            source.append(appendedText)
            snapshot = accumulator.consume(appending: appendedText)
        }

        XCTAssertEqual(accumulator.processedCharacterCount, source.count)
        XCTAssertEqual(snapshot.completedSegments.first, stableSegment)
        XCTAssertEqual(snapshot.completedSegments.count, 1)
        XCTAssertEqual(snapshot.reconstructedSource, source)
    }
}
