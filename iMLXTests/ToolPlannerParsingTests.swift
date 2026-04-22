import XCTest
@testable import iMLX

final class ToolPlannerParsingTests: XCTestCase {
    func testParsesNoneDecisionFromRawJSON() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"none"}"#,
            tools: [webSearchTool],
            context: emptyContext
        )

        XCTAssertEqual(decision, .none)
    }

    func testParsesToolDecisionFromFencedJSONBlock() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: """
            Sure, here's the result:
            ```json
            {"tool":"web_search","args":{"query":"FC Barcelona next match 2026"}}
            ```
            """,
            tools: [webSearchTool],
            context: emptyContext
        )

        XCTAssertEqual(
            decision,
            .call(
                ToolCallRequest(
                    toolName: "web_search",
                    arguments: ["query": "FC Barcelona next match 2026"]
                )
            )
        )
    }

    func testParsesBalancedJSONFragmentInsideWrapperText() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: #"Planner output -> {"tool":"web_search","args":{"query":"Barcelona next game"}} <- done"#,
            tools: [webSearchTool],
            context: emptyContext
        )

        XCTAssertEqual(
            decision,
            .call(
                ToolCallRequest(
                    toolName: "web_search",
                    arguments: ["query": "Barcelona next game"]
                )
            )
        )
    }

    func testRecoversWebSearchDecisionFromPlannerProse() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: """
            The user is asking about the weather in Barcelona for today. This is a request for current, live information that I cannot answer from my training data. I need to use the web_search tool to get the current weather information. I should search for the weather in Barcelona for today.
            """,
            userMessage: "What is the weather for today in Barcelona?",
            tools: [webSearchTool],
            context: emptyContext
        )

        XCTAssertEqual(
            decision,
            .call(
                ToolCallRequest(
                    toolName: "web_search",
                    arguments: ["query": "the weather in Barcelona for today"]
                )
            )
        )
    }

    func testRecoversWebSearchDecisionUsingUserMessageWhenProseLacksQuery() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: "I need to use the web_search tool to answer this question with current information.",
            userMessage: "Weather in Barcelona today",
            tools: [webSearchTool],
            context: emptyContext
        )

        XCTAssertEqual(
            decision,
            .call(
                ToolCallRequest(
                    toolName: "web_search",
                    arguments: ["query": "Weather in Barcelona today"]
                )
            )
        )
    }

    func testParsesReadURLDecisionUsingDetectedURLContext() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Summarize this link https://example.com/article",
            attachedImages: [],
            detectedPublicURLs: [URL(string: "https://example.com/article")!]
        )

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"read_url","args":{}}"#,
            userMessage: context.latestUserMessage,
            tools: [readURLTool],
            context: context
        )

        XCTAssertEqual(
            decision,
            .call(
                ToolCallRequest(
                    toolName: "read_url",
                    arguments: ["url": "https://example.com/article"]
                )
            )
        )
    }

    func testParsesOCRDecisionWithEmptyArgs() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"ocr_image_text","args":{}}"#,
            tools: [ocrTool],
            context: emptyContext
        )

        XCTAssertEqual(
            decision,
            .call(
                ToolCallRequest(
                    toolName: "ocr_image_text",
                    arguments: [:]
                )
            )
        )
    }

    func testHeuristicFallbackForLatestNewsRequest() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.heuristicFallbackDecision(
            userMessage: "What are the latest News in Spain?",
            tools: [webSearchTool]
        )

        XCTAssertEqual(
            decision,
            .call(
                ToolCallRequest(
                    toolName: "web_search",
                    arguments: ["query": "latest news Spain"]
                )
            )
        )
    }

    func testHeuristicFallbackForWeatherRequest() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.heuristicFallbackDecision(
            userMessage: "What is the weather in Barcelona for today?",
            tools: [webSearchTool]
        )

        XCTAssertEqual(
            decision,
            .call(
                ToolCallRequest(
                    toolName: "web_search",
                    arguments: ["query": "weather Barcelona today"]
                )
            )
        )
    }

    func testHeuristicFallbackDoesNotTriggerForSimpleMath() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.heuristicFallbackDecision(
            userMessage: "What's 2+2?",
            tools: [webSearchTool]
        )

        XCTAssertNil(decision)
    }

    func testInvalidToolNameFailsClosed() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"calculator","args":{"expression":"2+2"}}"#,
            tools: [webSearchTool],
            context: emptyContext
        )

        XCTAssertEqual(decision, .none)
    }

    func testMissingRequiredArgumentsFailClosed() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"web_search","args":{}}"#,
            tools: [webSearchTool],
            context: emptyContext
        )

        XCTAssertEqual(decision, .none)
    }

    func testQueryLengthIsClamped() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let oversizedQuery = String(repeating: "q", count: Constants.ToolCalling.maxQueryLength + 25)

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"web_search","args":{"query":"\#(oversizedQuery)"}}"#,
            tools: [webSearchTool],
            context: emptyContext
        )

        guard case .call(let request) = decision else {
            return XCTFail("Expected a tool call decision")
        }

        XCTAssertEqual(request.arguments["query"]?.count, Constants.ToolCalling.maxQueryLength)
    }

    private var webSearchTool: ToolDefinition {
        ToolDefinition(
            name: "web_search",
            description: "Searches the live web for current information and returns grounded excerpts.",
            argumentSchema: [
                ToolArgument(
                    name: "query",
                    type: "string",
                    required: true,
                    description: "A short, specific search engine query."
                )
            ]
        )
    }

    private var readURLTool: ToolDefinition {
        ToolDefinition(
            name: "read_url",
            description: "Reads the exact public URL found in the latest user message and returns grounded excerpts from that page.",
            argumentSchema: [
                ToolArgument(
                    name: "url",
                    type: "string",
                    required: false,
                    description: "The exact public http or https URL to read."
                )
            ]
        )
    }

    private var ocrTool: ToolDefinition {
        ToolDefinition(
            name: "ocr_image_text",
            description: "Extracts visible text from images attached on the latest user message.",
            argumentSchema: []
        )
    }

    private var emptyContext: ToolInputContext {
        ToolInputContext(
            latestUserMessage: "",
            attachedImages: [],
            detectedPublicURLs: []
        )
    }
}
