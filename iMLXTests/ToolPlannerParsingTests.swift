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
        let context = ToolInputContext(
            latestUserMessage: "Read this screenshot",
            attachedImages: [ChatAttachmentImage(data: Data([0x01]))],
            detectedPublicURLs: []
        )

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"ocr_image_text","args":{}}"#,
            tools: [ocrTool],
            context: context
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

    func testResolvedDecisionPrefersReadURLOverPlannerWebSearchWhenSingleURLIsPresent() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Summarize https://example.com/article",
            attachedImages: [],
            detectedPublicURLs: [URL(string: "https://example.com/article")!]
        )

        let decision = service.resolvedDecision(
            plannedDecision: .call(
                ToolCallRequest(
                    toolName: "web_search",
                    arguments: ["query": "example article summary"]
                )
            ),
            userMessage: context.latestUserMessage,
            context: context,
            tools: [readURLTool, webSearchTool],
            preferThinkingFallback: false
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

    func testResolvedDecisionForcesOCRForTextFocusedImageRequestWhenPlannerReturnsNone() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "What does this screenshot say?",
            attachedImages: [ChatAttachmentImage(data: Data([0x01]))],
            detectedPublicURLs: []
        )

        let decision = service.resolvedDecision(
            plannedDecision: .none,
            userMessage: context.latestUserMessage,
            context: context,
            tools: [ocrTool],
            preferThinkingFallback: false
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

    func testResolvedDecisionForcesDocumentSynthesisForNewlyAttachedDocument() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Please summarize this",
            attachedImages: [],
            attachedDocuments: [sampleDocument],
            hasNewlyAttachedDocuments: true,
            detectedPublicURLs: []
        )

        let decision = service.resolvedDecision(
            plannedDecision: .call(
                ToolCallRequest(
                    toolName: "calendar_brief",
                    arguments: ["range": "today"]
                )
            ),
            userMessage: context.latestUserMessage,
            context: context,
            tools: [documentTool, calendarTool],
            preferThinkingFallback: false
        )

        XCTAssertEqual(
            decision,
            .call(
                ToolCallRequest(
                    toolName: "document_synthesize",
                    arguments: ["query": "Please summarize this"]
                )
            )
        )
    }

    func testResolvedDecisionKeepsReadURLPrecedenceOverDocumentSynthesis() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Summarize this PDF and this link https://example.com",
            attachedImages: [],
            attachedDocuments: [sampleDocument],
            hasNewlyAttachedDocuments: true,
            detectedPublicURLs: [URL(string: "https://example.com")!]
        )

        let decision = service.resolvedDecision(
            plannedDecision: .none,
            userMessage: context.latestUserMessage,
            context: context,
            tools: [readURLTool, documentTool],
            preferThinkingFallback: false
        )

        XCTAssertEqual(
            decision,
            .call(
                ToolCallRequest(
                    toolName: "read_url",
                    arguments: ["url": "https://example.com"]
                )
            )
        )
    }

    func testResolvedDecisionDoesNotForceDocumentSynthesisForUnrelatedTurn() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "What is the capital of France?",
            attachedImages: [],
            attachedDocuments: [sampleDocument],
            detectedPublicURLs: []
        )

        let decision = service.resolvedDecision(
            plannedDecision: .none,
            userMessage: context.latestUserMessage,
            context: context,
            tools: [documentTool],
            preferThinkingFallback: false
        )

        XCTAssertEqual(decision, .none)
    }

    func testResolvedDecisionRecoversCalendarBriefForScheduleRequest() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.resolvedDecision(
            plannedDecision: .none,
            userMessage: "What is on my calendar tomorrow?",
            context: emptyContext,
            tools: [calendarTool],
            preferThinkingFallback: false
        )

        XCTAssertEqual(
            decision,
            .call(
                ToolCallRequest(
                    toolName: "calendar_brief",
                    arguments: ["range": "tomorrow"]
                )
            )
        )
    }

    func testThinkingFallbackDoesNotTriggerWithoutEligibleWebSearchTool() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.resolvedDecision(
            plannedDecision: .none,
            userMessage: "What are the latest news in Spain?",
            context: emptyContext,
            tools: [ocrTool],
            preferThinkingFallback: true
        )

        XCTAssertEqual(decision, .none)
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
            ],
            metadata: ToolMetadata(
                requiresWebAccessToggle: true,
                executionClass: .network
            )
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
            ],
            metadata: ToolMetadata(
                requiresWebAccessToggle: true,
                requiresSinglePublicURL: true,
                executionClass: .network
            )
        )
    }

    private var ocrTool: ToolDefinition {
        ToolDefinition(
            name: "ocr_image_text",
            description: "Extracts visible text from images attached on the latest user message.",
            argumentSchema: [],
            metadata: ToolMetadata(
                requiresAttachedImages: true,
                executionClass: .local
            )
        )
    }

    private var documentTool: ToolDefinition {
        ToolDefinition(
            name: "document_synthesize",
            description: "Retrieves bounded excerpts from attached conversation documents.",
            argumentSchema: [
                ToolArgument(
                    name: "query",
                    type: "string",
                    required: true,
                    description: "Document query."
                )
            ],
            metadata: ToolMetadata(
                requiresAttachedDocuments: true,
                executionClass: .local
            )
        )
    }

    private var calendarTool: ToolDefinition {
        ToolDefinition(
            name: "calendar_brief",
            description: "Reads local calendar events for a bounded date range.",
            argumentSchema: [
                ToolArgument(
                    name: "range",
                    type: "string",
                    required: true,
                    description: "One of today, tomorrow, this_week, next_7_days."
                )
            ],
            metadata: ToolMetadata(executionClass: .local)
        )
    }

    private var emptyContext: ToolInputContext {
        ToolInputContext(
            latestUserMessage: "",
            attachedImages: [],
            detectedPublicURLs: []
        )
    }

    private var sampleDocument: ConversationDocumentReference {
        ConversationDocumentReference(
            id: "doc-1",
            displayName: "Sample",
            kind: .pdf,
            importedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
