import XCTest
@testable import iMLX

final class ParsedAssistantContentTests: XCTestCase {
    func testParsesTaggedThinkingAndStripsAnswerHeading() {
        let parsed = ParsedAssistantContent("<think>\nCheck the constraint.\n</think>\n\nFinal answer: I can draft the email, but I cannot send it.")

        XCTAssertEqual(parsed.thinking, "Check the constraint.")
        XCTAssertEqual(parsed.response, "I can draft the email, but I cannot send it.")
        XCTAssertEqual(parsed.copyableText, "I can draft the email, but I cannot send it.")
    }

    func testParsesTrailingClosingTagWithoutOpeningTag() {
        let parsed = ParsedAssistantContent("I should confirm constraints first.\n</think>\nAnswer: Use read_url for one pasted public URL.")

        XCTAssertEqual(parsed.thinking, "I should confirm constraints first.")
        XCTAssertEqual(parsed.response, "Use read_url for one pasted public URL.")
    }

    func testStreamingInferenceSplitsReasoningFromAnswerLine() {
        let parsed = ParsedAssistantContent("Intent: satisfy request\nConstraints: stay local\n\nFinal answer: Keep web search optional.", isStreaming: true)

        XCTAssertEqual(parsed.thinking, "Intent: satisfy request\nConstraints: stay local")
        XCTAssertEqual(parsed.response, "Keep web search optional.")
    }

    func testParsesChannelMarkerAsThinkingBoundary() {
        let parsed = ParsedAssistantContent("Review constraints.\n<channel|>That depends on your goal.", isStreaming: true)

        XCTAssertEqual(parsed.thinking, "Review constraints.")
        XCTAssertEqual(parsed.response, "That depends on your goal.")
        XCTAssertEqual(parsed.copyableText, "That depends on your goal.")
    }

    func testPlainChannelTagStaysInResponse() {
        let content = "Here is the feed:\n<channel><title>Local updates</title></channel>"
        let parsed = ParsedAssistantContent(content, isStreaming: true)

        XCTAssertNil(parsed.thinking)
        XCTAssertEqual(parsed.response, content)
        XCTAssertEqual(parsed.copyableText, content)
    }

    func testRemovesStreamingCursorMarker() {
        let parsed = ParsedAssistantContent("Working on it▊")

        XCTAssertNil(parsed.thinking)
        XCTAssertEqual(parsed.response, "Working on it")
        XCTAssertEqual(parsed.copyableText, "Working on it")
    }
}
