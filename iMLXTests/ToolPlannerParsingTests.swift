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

    func testPlannerOutcomeDistinguishesValidNoneFromUnusableOutput() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let validNone = service.parsePlannerOutcome(
            from: #"{"tool":"none"}"#,
            tools: [webSearchTool],
            context: emptyContext
        )
        let unusable = service.parsePlannerOutcome(
            from: "I am not sure which tool to use.",
            tools: [webSearchTool],
            context: emptyContext
        )

        XCTAssertEqual(validNone, .decision(.none))
        XCTAssertEqual(unusable, .unusable)
    }

    func testPlannerAcceptsNormalizedToolNameAndArgumentsKey() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let outcome = service.parsePlannerOutcome(
            from: #"{"tool":"WEB SEARCH","arguments":{"query":"Barcelona weather warnings"}}"#,
            tools: [webSearchTool],
            context: emptyContext
        )

        XCTAssertEqual(
            outcome,
            .decision(
                .call(
                    ToolCallRequest(
                        toolName: "web_search",
                        arguments: ["query": "Barcelona weather warnings"]
                    )
                )
            )
        )
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

    func testProseRecoveryHonorsExplicitToolNegation() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Read https://example.com/article",
            attachedImages: [],
            detectedPublicURLs: [URL(string: "https://example.com/article")!]
        )

        let outcome = service.parsePlannerOutcome(
            from: "Do not use web_search. I should use the read_url tool.",
            userMessage: context.latestUserMessage,
            tools: [webSearchTool, readURLTool],
            context: context
        )

        XCTAssertEqual(
            outcome,
            .decision(
                .call(
                    ToolCallRequest(
                        toolName: "read_url",
                        arguments: ["url": "https://example.com/article"]
                    )
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
                    arguments: ["query": "What are the latest News in Spain"]
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
                    arguments: ["query": "What is the weather in Barcelona for today"]
                )
            )
        )
    }

    func testHeuristicFallbackPreservesLocationAfterWeatherTimeframe() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.heuristicFallbackDecision(
            userMessage: "What is the weather forecast for tomorrow in Barcelona?",
            tools: [webSearchTool]
        )

        XCTAssertEqual(
            decision,
            .call(
                ToolCallRequest(
                    toolName: "web_search",
                    arguments: ["query": "What is the weather forecast for tomorrow in Barcelona"]
                )
            )
        )
    }

    func testPreflightPreservesLocationAfterWeatherTimeframe() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let message = "What is the weather forecast for tomorrow in Barcelona?"
        let context = ToolInputContext(
            latestUserMessage: message,
            attachedImages: [],
            detectedPublicURLs: []
        )

        let decision = service.preflightDecision(
            userMessage: message,
            context: context,
            tools: [webSearchTool]
        )

        XCTAssertEqual(
            decision,
            .skip(
                .call(
                    ToolCallRequest(
                        toolName: "web_search",
                        arguments: ["query": "What is the weather forecast for tomorrow in Barcelona"]
                    )
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

    func testPreflightSkipsPlannerForSimpleMath() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "What's 2+2?",
            context: emptyContext,
            tools: [webSearchTool]
        )

        XCTAssertEqual(decision, .skip(.none))
    }

    func testPreflightSkipsPlannerForCreativeWritingRequest() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Can you write a poem about summer?",
            context: emptyContext,
            tools: [webSearchTool]
        )

        XCTAssertEqual(decision, .skip(.none))
    }

    func testHeuristicFallbackDoesNotTriggerForPersonalTodayMessage() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.heuristicFallbackDecision(
            userMessage: "I feel anxious today",
            tools: [webSearchTool]
        )

        XCTAssertNil(decision)
    }

    func testPreflightForPersonalTodayMessageDoesNotForceWebSearch() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "I feel anxious today",
            context: emptyContext,
            tools: [webSearchTool]
        )

        XCTAssertEqual(decision, .skip(.none))
    }

    func testPreflightForBroadSwiftQuestionUsesPlannerInsteadOfForcedWebSearch() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "What is the difference between let and var in Swift?",
            context: emptyContext,
            tools: [webSearchTool]
        )

        XCTAssertEqual(decision, .deliberate)
    }

    func testPreflightStillForcesClearLiveDataWebSearch() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "What is the weather in Barcelona for today?",
            context: emptyContext,
            tools: [webSearchTool]
        )

        XCTAssertEqual(
            decision,
            .skip(
                .call(
                    ToolCallRequest(
                        toolName: "web_search",
                        arguments: ["query": "What is the weather in Barcelona for today"]
                    )
                )
            )
        )
    }

    func testPreflightForExplicitWebSearchExtractsQuery() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Please search the web for Swift 6 concurrency updates.",
            context: emptyContext,
            tools: [webSearchTool]
        )

        XCTAssertEqual(
            decision,
            .skip(
                .call(
                    ToolCallRequest(
                        toolName: "web_search",
                        arguments: ["query": "Swift 6 concurrency updates"]
                    )
                )
            )
        )
    }

    func testExplicitWebSearchTakesPrecedenceOverLocalCalendarKeywords() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Search the web for upcoming events in Barcelona",
            context: emptyContext,
            tools: [calendarTool, webSearchTool]
        )

        XCTAssertEqual(
            decision,
            .skip(
                .call(
                    ToolCallRequest(
                        toolName: "web_search",
                        arguments: ["query": "upcoming events in Barcelona"]
                    )
                )
            )
        )
    }

    func testPreflightReadsSingleURLOnlyForPageReadingIntent() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let url = URL(string: "https://example.com/article")!
        let context = ToolInputContext(
            latestUserMessage: "Please summarize this article https://example.com/article",
            attachedImages: [],
            detectedPublicURLs: [url]
        )

        let decision = service.preflightDecision(
            userMessage: context.latestUserMessage,
            context: context,
            tools: [readURLTool, webSearchTool]
        )

        XCTAssertEqual(
            decision,
            .skip(
                .call(
                    ToolCallRequest(
                        toolName: "read_url",
                        arguments: ["url": url.absoluteString]
                    )
                )
            )
        )
    }

    func testPreflightDoesNotReadURLForNonReadingIntent() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Remember this link https://example.com/article",
            attachedImages: [],
            detectedPublicURLs: [URL(string: "https://example.com/article")!]
        )

        let decision = service.preflightDecision(
            userMessage: context.latestUserMessage,
            context: context,
            tools: [readURLTool]
        )

        XCTAssertEqual(decision, .deliberate)
    }

    func testPreflightUsesWebSearchWhenURLIsSearchSubject() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Search the web for discussions about https://example.com/article",
            attachedImages: [],
            detectedPublicURLs: [URL(string: "https://example.com/article")!]
        )

        let decision = service.preflightDecision(
            userMessage: context.latestUserMessage,
            context: context,
            tools: [readURLTool, webSearchTool]
        )

        XCTAssertEqual(
            decision,
            .skip(
                .call(
                    ToolCallRequest(
                        toolName: "web_search",
                        arguments: ["query": "discussions about https://example.com/article"]
                    )
                )
            )
        )
    }

    func testPreflightRejectsMultipleURLsForClarification() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Compare https://example.com and https://openai.com",
            attachedImages: [],
            detectedPublicURLs: [
                URL(string: "https://example.com")!,
                URL(string: "https://openai.com")!
            ]
        )

        let decision = service.preflightDecision(
            userMessage: context.latestUserMessage,
            context: context,
            tools: [webSearchTool]
        )

        XCTAssertEqual(decision, .skip(.none))
    }

    func testConceptualMarketQuestionUsesPlannerInsteadOfForcedSearch() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Why do exchange rates fluctuate?",
            context: emptyContext,
            tools: [webSearchTool]
        )

        XCTAssertEqual(decision, .deliberate)
    }

    func testTerseWeatherLookupForcesSearchWithoutLosingLocation() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Weather Barcelona",
            context: emptyContext,
            tools: [webSearchTool]
        )

        XCTAssertEqual(
            decision,
            .skip(
                .call(
                    ToolCallRequest(
                        toolName: "web_search",
                        arguments: ["query": "Weather Barcelona"]
                    )
                )
            )
        )
    }

    func testConceptualWeatherQuestionUsesPlannerInsteadOfForcedSearch() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "How do weather patterns work?",
            context: emptyContext,
            tools: [webSearchTool]
        )

        XCTAssertEqual(decision, .deliberate)
    }

    func testWeatherWarningWithTimeframeForcesSearch() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Any yellow warning tomorrow in Barcelona?",
            context: emptyContext,
            tools: [webSearchTool]
        )

        XCTAssertEqual(
            decision,
            .skip(
                .call(
                    ToolCallRequest(
                        toolName: "web_search",
                        arguments: ["query": "Any yellow warning tomorrow in Barcelona"]
                    )
                )
            )
        )
    }

    func testShortWebFollowUpUsesPlannerEvenWithoutQuestionMark() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let history = [
            ChatMessage(role: .user, content: "What is the weather tomorrow in Barcelona?"),
            ChatMessage(
                role: .assistant,
                content: "It will be hot.",
                toolTrace: ToolCallTrace(
                    toolName: "web_search",
                    displayInput: "What is the weather tomorrow in Barcelona",
                    status: .success,
                    durationSeconds: 0.2,
                    success: true,
                    sourceCount: 2
                )
            )
        ]

        let decision = service.preflightDecision(
            userMessage: "Yellow warning",
            context: emptyContext,
            tools: [webSearchTool],
            history: history
        )

        XCTAssertEqual(decision, .deliberate)
    }

    func testResolvedDecisionPrefersReadURLOverPlannerWebSearchWhenSingleURLIsPresent() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Summarize https://example.com/article",
            attachedImages: [],
            detectedPublicURLs: [URL(string: "https://example.com/article")!]
        )

        let decision = service.resolvedDecision(
            plannerOutcome: .decision(
                .call(
                    ToolCallRequest(
                        toolName: "web_search",
                        arguments: ["query": "example article summary"]
                    )
                )
            ),
            userMessage: context.latestUserMessage,
            context: context,
            tools: [readURLTool, webSearchTool]
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

    func testResolvedDecisionRecoversOCRForTextFocusedImageRequestWhenPlannerIsUnusable() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "What does this screenshot say?",
            attachedImages: [ChatAttachmentImage(data: Data([0x01]))],
            detectedPublicURLs: []
        )

        let decision = service.resolvedDecision(
            plannerOutcome: .unusable,
            userMessage: context.latestUserMessage,
            context: context,
            tools: [ocrTool]
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
            plannerOutcome: .decision(
                .call(
                    ToolCallRequest(
                        toolName: "calendar_brief",
                        arguments: ["range": "today"]
                    )
                )
            ),
            userMessage: context.latestUserMessage,
            context: context,
            tools: [documentTool, calendarTool]
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

    func testNewlyAttachedDocumentDoesNotOverrideExplicitTimerRequest() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let message = "Set a timer for 10 minutes"
        let context = ToolInputContext(
            latestUserMessage: message,
            attachedImages: [],
            attachedDocuments: [sampleDocument],
            hasNewlyAttachedDocuments: true,
            detectedPublicURLs: []
        )

        let decision = service.preflightDecision(
            userMessage: message,
            context: context,
            tools: [documentTool, timerCreateTool]
        )

        XCTAssertEqual(
            decision,
            .skip(
                .call(
                    ToolCallRequest(
                        toolName: "timer_create",
                        arguments: ["duration": "600"]
                    )
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
            plannerOutcome: .unusable,
            userMessage: context.latestUserMessage,
            context: context,
            tools: [readURLTool, documentTool]
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
            plannerOutcome: .decision(.none),
            userMessage: context.latestUserMessage,
            context: context,
            tools: [documentTool]
        )

        XCTAssertEqual(decision, .none)
    }

    func testResolvedDecisionRecoversCalendarBriefWhenPlannerIsUnusable() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.resolvedDecision(
            plannerOutcome: .unusable,
            userMessage: "What is on my calendar tomorrow?",
            context: emptyContext,
            tools: [calendarTool]
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

    func testResolvedDecisionRespectsValidNoneInsteadOfApplyingCalendarFallback() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.resolvedDecision(
            plannerOutcome: .decision(.none),
            userMessage: "What is on my calendar tomorrow?",
            context: emptyContext,
            tools: [calendarTool]
        )

        XCTAssertEqual(decision, .none)
    }

    func testResolvedDecisionRecoversContextualWebFollowUpWhenPlannerIsUnusable() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let history = [
            ChatMessage(role: .user, content: "What is the weather tomorrow in Barcelona?"),
            ChatMessage(
                role: .assistant,
                content: "It will be hot.",
                toolTrace: ToolCallTrace(
                    toolName: "web_search",
                    displayInput: "What is the weather tomorrow in Barcelona",
                    status: .success,
                    durationSeconds: 0.2,
                    success: true,
                    sourceCount: 2
                )
            )
        ]

        let decision = service.resolvedDecision(
            plannerOutcome: .unusable,
            userMessage: "Yellow warning",
            context: emptyContext,
            tools: [webSearchTool],
            history: history
        )

        guard case .call(let request) = decision else {
            return XCTFail("Expected contextual web search fallback")
        }
        XCTAssertEqual(request.toolName, "web_search")
        XCTAssertTrue(request.arguments["query"]?.contains("Barcelona") == true)
        XCTAssertTrue(request.arguments["query"]?.contains("Yellow warning") == true)
    }

    func testUnusablePlannerDoesNotTriggerWebFallbackWithoutEligibleTool() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.resolvedDecision(
            plannerOutcome: .unusable,
            userMessage: "What are the latest news in Spain?",
            context: emptyContext,
            tools: [ocrTool]
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
        let oversizedQuery = "Barcelona weather " + String(repeating: "detail ", count: 30) + "yellow warning tomorrow"

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"web_search","args":{"query":"\#(oversizedQuery)"}}"#,
            tools: [webSearchTool],
            context: emptyContext
        )

        guard case .call(let request) = decision else {
            return XCTFail("Expected a tool call decision")
        }

        XCTAssertEqual(request.arguments["query"]?.count, Constants.ToolCalling.maxQueryLength)
        XCTAssertTrue(request.arguments["query"]?.hasPrefix("Barcelona weather") == true)
        XCTAssertTrue(request.arguments["query"]?.hasSuffix("yellow warning tomorrow") == true)
    }

    func testParsesCurrentDateTimeDecisionWithEmptyArgs() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"current_datetime","args":{}}"#,
            tools: [currentDateTimeTool],
            context: emptyContext
        )

        XCTAssertEqual(
            decision,
            .call(ToolCallRequest(toolName: "current_datetime", arguments: [:]))
        )
    }

    func testParsesRemindersBriefDecision() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"reminders_brief","args":{"range":"tomorrow"}}"#,
            tools: [remindersBriefTool],
            context: emptyContext
        )

        XCTAssertEqual(
            decision,
            .call(ToolCallRequest(toolName: "reminders_brief", arguments: ["range": "tomorrow"]))
        )
    }

    func testParsesRemindersCreateDecisionWithTitleAndDue() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"reminders_create","args":{"title":"Buy milk","due":"tomorrow"}}"#,
            tools: [remindersCreateTool],
            context: emptyContext
        )

        guard case .call(let request) = decision else {
            return XCTFail("Expected a tool call decision")
        }

        XCTAssertEqual(request.toolName, "reminders_create")
        XCTAssertEqual(request.arguments["title"], "Buy milk")
        XCTAssertNotNil(request.arguments["due"])
        XCTAssertTrue(request.arguments["due"]!.contains("T"))
    }

    func testResolvedDecisionRecoversRemindersBriefWhenPlannerIsUnusable() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.resolvedDecision(
            plannerOutcome: .unusable,
            userMessage: "Show me my overdue reminders",
            context: emptyContext,
            tools: [remindersBriefTool]
        )

        XCTAssertEqual(
            decision,
            .call(ToolCallRequest(toolName: "reminders_brief", arguments: ["range": "overdue"]))
        )
    }

    func testPreflightReminderBriefWithoutDateUsesAllRange() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "What reminders I have?",
            context: emptyContext,
            tools: [remindersBriefTool]
        )

        XCTAssertEqual(
            decision,
            .skip(.call(ToolCallRequest(toolName: "reminders_brief", arguments: ["range": "all"])))
        )
    }

    func testPreflightReminderBriefWithTodayKeepsTodayRange() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "What reminders do I have today?",
            context: emptyContext,
            tools: [remindersBriefTool]
        )

        XCTAssertEqual(
            decision,
            .skip(.call(ToolCallRequest(toolName: "reminders_brief", arguments: ["range": "today"])))
        )
    }

    func testPreflightReminderBriefRangeFollowUpUsesPreviousReminderTool() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let history = [
            ChatMessage(role: .user, content: "What reminders do I have?"),
            ChatMessage(
                role: .assistant,
                content: "Here are your reminders.",
                toolTrace: ToolCallTrace(
                    toolName: "reminders_brief",
                    displayInput: "all",
                    status: .success,
                    durationSeconds: 0.1,
                    success: true,
                    sourceCount: 3
                )
            )
        ]

        let decision = service.preflightDecision(
            userMessage: "And for tomorrow?",
            context: emptyContext,
            tools: [remindersBriefTool],
            history: history
        )

        XCTAssertEqual(
            decision,
            .skip(.call(ToolCallRequest(toolName: "reminders_brief", arguments: ["range": "tomorrow"])))
        )
    }

    func testPreflightReminderBriefUpcomingFollowUpUsesNextSevenDays() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let history = [
            ChatMessage(role: .user, content: "What reminders do I have?"),
            ChatMessage(
                role: .assistant,
                content: "Here are your reminders.",
                toolTrace: ToolCallTrace(
                    toolName: "reminders_brief",
                    displayInput: "all",
                    status: .success,
                    durationSeconds: 0.1,
                    success: true,
                    sourceCount: 5
                )
            )
        ]

        let decision = service.preflightDecision(
            userMessage: "And any upcoming?",
            context: emptyContext,
            tools: [remindersBriefTool],
            history: history
        )

        XCTAssertEqual(
            decision,
            .skip(.call(ToolCallRequest(toolName: "reminders_brief", arguments: ["range": "next_7_days"])))
        )
    }

    func testPreflightCalendarBriefUpcomingFollowUpUsesNextSevenDays() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let history = [
            ChatMessage(role: .user, content: "What events do I have?"),
            ChatMessage(
                role: .assistant,
                content: "Here are your events.",
                toolTrace: ToolCallTrace(
                    toolName: "calendar_brief",
                    displayInput: "today",
                    status: .success,
                    durationSeconds: 0.1,
                    success: true,
                    sourceCount: 2
                )
            )
        ]

        let decision = service.preflightDecision(
            userMessage: "And any upcoming?",
            context: emptyContext,
            tools: [calendarTool],
            history: history
        )

        XCTAssertEqual(
            decision,
            .skip(.call(ToolCallRequest(toolName: "calendar_brief", arguments: ["range": "next_7_days"])))
        )
    }

    func testPreflightCalendarBriefRecognizesSingularUpcomingEvent() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Any upcoming event?",
            context: emptyContext,
            tools: [calendarTool]
        )

        XCTAssertEqual(
            decision,
            .skip(.call(ToolCallRequest(toolName: "calendar_brief", arguments: ["range": "next_7_days"])))
        )
    }

    func testCalendarHeuristicDoesNotHijackProgrammingEventQuestion() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "What is an event loop?",
            context: emptyContext,
            tools: [calendarTool]
        )

        XCTAssertEqual(decision, .skip(.none))
    }

    func testCalendarHeuristicDoesNotHijackConceptualCalendarQuestion() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "What is a calendar?",
            context: emptyContext,
            tools: [calendarTool]
        )

        XCTAssertEqual(decision, .skip(.none))
    }

    func testCalendarCreateAdjacentButIncompleteRequestUsesPlanner() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "How do I schedule a meeting?",
            context: emptyContext,
            tools: [calendarTool, calendarCreateTool]
        )

        XCTAssertEqual(decision, .deliberate)
    }

    func testReminderHeuristicDoesNotHijackGenericTaskQuestion() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Explain task decomposition",
            context: emptyContext,
            tools: [remindersBriefTool]
        )

        XCTAssertEqual(decision, .skip(.none))
    }

    func testPreflightRangeFollowUpDoesNotReuseUnrelatedTool() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let history = [
            ChatMessage(role: .user, content: "Search Marc in my contacts"),
            ChatMessage(
                role: .assistant,
                content: "I found Marc.",
                toolTrace: ToolCallTrace(
                    toolName: "contacts_lookup",
                    displayInput: "Marc",
                    status: .success,
                    durationSeconds: 0.1,
                    success: true,
                    sourceCount: 1
                )
            )
        ]

        let decision = service.preflightDecision(
            userMessage: "And for tomorrow?",
            context: emptyContext,
            tools: [remindersBriefTool],
            history: history
        )

        XCTAssertEqual(decision, .skip(.none))
    }

    func testResolvedDecisionDoesNotConfuseRemindMeToWithMemory() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.resolvedDecision(
            plannerOutcome: .decision(.none),
            userMessage: "Please remind me of our trip to Paris",
            context: emptyContext,
            tools: [remindersCreateTool]
        )

        XCTAssertEqual(decision, .none)
    }

    func testPreflightReminderCreateExtractsDueDateFromTail() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Remind me to call mom tomorrow",
            context: emptyContext,
            tools: [remindersCreateTool]
        )

        guard case .skip(.call(let request)) = decision else {
            return XCTFail("Expected preflight to create a reminder")
        }

        XCTAssertEqual(request.toolName, "reminders_create")
        XCTAssertEqual(request.arguments["title"], "call mom")
        XCTAssertNotNil(request.arguments["due"])
        XCTAssertTrue(request.arguments["due"]?.contains("T") == true)
    }

    func testReminderCreationTakesPrecedenceOverCalendarKeywordsInTitle() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Remind me to prepare for the meeting tomorrow",
            context: emptyContext,
            tools: [calendarTool, calendarCreateTool, remindersCreateTool]
        )

        guard case .skip(.call(let request)) = decision else {
            return XCTFail("Expected reminder creation")
        }
        XCTAssertEqual(request.toolName, "reminders_create")
        XCTAssertEqual(request.arguments["title"], "prepare for the meeting")
        XCTAssertNotNil(request.arguments["due"])
    }

    func testPreflightReminderCreateExtractsRelativeDueDateFromTail() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Remind me to check the oven in 20 minutes",
            context: emptyContext,
            tools: [remindersCreateTool]
        )

        guard case .skip(.call(let request)) = decision else {
            return XCTFail("Expected preflight to create a reminder")
        }

        XCTAssertEqual(request.toolName, "reminders_create")
        XCTAssertEqual(request.arguments["title"], "check the oven")
        XCTAssertNotNil(request.arguments["due"])
        XCTAssertTrue(request.arguments["due"]?.contains("T") == true)
    }

    func testIncompleteReminderRequestUsesPlanner() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Now remind me for next Tuesday to wake up",
            context: emptyContext,
            tools: [remindersCreateTool]
        )

        XCTAssertEqual(decision, .deliberate)
    }

    func testReminderWithNamedDayButNoTimeUsesPlanner() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Remind me to wake up next Tuesday",
            context: emptyContext,
            tools: [remindersCreateTool]
        )

        XCTAssertEqual(decision, .deliberate)
    }

    func testReminderWithNamedDayAndTimeCreatesReminder() throws {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Remind me to wake up next Tuesday at 5 am",
            context: emptyContext,
            tools: [remindersCreateTool]
        )

        guard case .skip(.call(let request)) = decision,
              let due = request.arguments["due"],
              let dueDate = ISO8601DateFormatter().date(from: due) else {
            return XCTFail("Expected preflight to create a dated reminder")
        }

        let components = Calendar.current.dateComponents([.weekday, .hour, .minute], from: dueDate)
        XCTAssertEqual(request.arguments["title"], "wake up")
        XCTAssertEqual(components.weekday, 3)
        XCTAssertEqual(components.hour, 5)
        XCTAssertEqual(components.minute, 0)
    }

    func testReminderClarificationAnswerUsesPlanner() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let history = [
            ChatMessage(role: .user, content: "Now remind me for next Tuesday to wake up"),
            ChatMessage(
                role: .assistant,
                content: "I can set a reminder for you. What time next Tuesday should I remind you?"
            )
        ]

        let decision = service.preflightDecision(
            userMessage: "5 am",
            context: emptyContext,
            tools: [remindersCreateTool],
            history: history
        )

        XCTAssertEqual(decision, .deliberate)
    }

    func testReminderClarificationAnswerRecoversWhenPlannerReturnsNone() throws {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let history = [
            ChatMessage(role: .user, content: "Now remind me for next Tuesday to wake up"),
            ChatMessage(
                role: .assistant,
                content: "I can set a reminder for you. Could you tell me what time next Tuesday?"
            )
        ]

        let decision = service.resolvedDecision(
            plannerOutcome: .decision(.none),
            userMessage: "5 am",
            context: emptyContext,
            tools: [remindersCreateTool],
            history: history
        )

        guard case .call(let request) = decision,
              let due = request.arguments["due"],
              let dueDate = ISO8601DateFormatter().date(from: due) else {
            return XCTFail("Expected the pending reminder to be completed")
        }

        let components = Calendar.current.dateComponents([.weekday, .hour, .minute], from: dueDate)
        XCTAssertEqual(request.toolName, "reminders_create")
        XCTAssertEqual(request.arguments["title"], "wake up")
        XCTAssertEqual(components.weekday, 3)
        XCTAssertEqual(components.hour, 5)
        XCTAssertEqual(components.minute, 0)
        XCTAssertGreaterThan(dueDate, Date())
    }

    func testPlannerReminderDecisionAcceptsNamedWeekdayWithTime() throws {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"reminders_create","args":{"title":"wake up","due":"next Tuesday at 5 am"}}"#,
            tools: [remindersCreateTool],
            context: emptyContext
        )

        guard case .call(let request) = decision,
              let due = request.arguments["due"],
              let dueDate = ISO8601DateFormatter().date(from: due) else {
            return XCTFail("Expected a reminders_create call")
        }

        let components = Calendar.current.dateComponents([.weekday, .hour, .minute], from: dueDate)
        XCTAssertEqual(request.arguments["title"], "wake up")
        XCTAssertEqual(components.weekday, 3)
        XCTAssertEqual(components.hour, 5)
        XCTAssertEqual(components.minute, 0)
    }

    func testUnrelatedConversationalAnswerDoesNotUsePlanner() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let history = [
            ChatMessage(role: .user, content: "What is your favorite color?"),
            ChatMessage(role: .assistant, content: "Probably blue. What about yours?")
        ]

        let decision = service.preflightDecision(
            userMessage: "Green",
            context: emptyContext,
            tools: [remindersCreateTool],
            history: history
        )

        XCTAssertEqual(decision, .skip(.none))
    }

    func testPreflightTimezoneRequestUsesCurrentDateTime() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "What timezone am I in?",
            context: emptyContext,
            tools: [currentDateTimeTool]
        )

        XCTAssertEqual(
            decision,
            .skip(.call(ToolCallRequest(toolName: "current_datetime", arguments: [:])))
        )
    }

    func testParsesCalendarCreateDecisionWithDuration() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"calendar_create","args":{"title":"Project review","start":"2026-05-03T10:00","end_or_duration":"30 minutes","location":"Office"}}"#,
            tools: [calendarCreateTool],
            context: emptyContext
        )

        guard case .call(let request) = decision else {
            return XCTFail("Expected a calendar_create call")
        }

        XCTAssertEqual(request.toolName, "calendar_create")
        XCTAssertEqual(request.arguments["title"], "Project review")
        XCTAssertEqual(request.arguments["location"], "Office")
        XCTAssertTrue(request.arguments["start"]?.contains("T") == true)
        XCTAssertTrue(request.arguments["end_or_duration"]?.contains("T") == true)
    }

    func testCalendarCreatePrefersExplicitWeekdayFromUserMessage() throws {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Create a meeting for next Thursday at 15:00 pm with Marc",
            attachedImages: [],
            detectedPublicURLs: []
        )

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"calendar_create","args":{"title":"Meeting with Marc","start":"tomorrow 15:00","end_or_duration":"1 hour"}}"#,
            tools: [calendarCreateTool],
            context: context
        )

        guard case .call(let request) = decision,
              let startRaw = request.arguments["start"],
              let startDate = ISO8601DateFormatter().date(from: startRaw) else {
            return XCTFail("Expected a calendar_create call with an ISO start")
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: startDate)
        XCTAssertEqual(components.weekday, 5)
        XCTAssertEqual(components.hour, 15)
        XCTAssertEqual(components.minute, 0)
        XCTAssertNotEqual(calendar.startOfDay(for: startDate), calendar.startOfDay(for: Date().addingTimeInterval(86_400)))
    }

    func testInvalidCalendarCreateMissingConcreteTimeFailsClosed() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"calendar_create","args":{"title":"Lunch","start":"tomorrow","end_or_duration":"1 hour"}}"#,
            tools: [calendarCreateTool],
            context: emptyContext
        )

        XCTAssertEqual(decision, .none)
    }

    func testPreflightScheduleMeetingWithExplicitWeekdayCreatesEvent() throws {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let message = "Schedule a meeting for next Wednesday at 16:00 pm with Marc"
        let context = ToolInputContext(
            latestUserMessage: message,
            attachedImages: [],
            detectedPublicURLs: []
        )

        let decision = service.preflightDecision(
            userMessage: message,
            context: context,
            tools: [calendarTool, calendarCreateTool]
        )

        guard case .skip(.call(let request)) = decision,
              let startRaw = request.arguments["start"],
              let endRaw = request.arguments["end_or_duration"],
              let startDate = ISO8601DateFormatter().date(from: startRaw),
              let endDate = ISO8601DateFormatter().date(from: endRaw) else {
            return XCTFail("Expected preflight to create a calendar event with ISO dates")
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: startDate)
        XCTAssertEqual(request.toolName, "calendar_create")
        XCTAssertEqual(request.arguments["title"], "Meeting with Marc")
        XCTAssertEqual(components.weekday, 4)
        XCTAssertEqual(components.hour, 16)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(endDate.timeIntervalSince(startDate), 3_600)
    }

    func testPreflightScheduleMeetingWithParticipantBeforeTimeCreatesEvent() throws {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let message = "Schedule a meeting for next Friday with Alex at 18:00 pm"
        let context = ToolInputContext(
            latestUserMessage: message,
            attachedImages: [],
            detectedPublicURLs: []
        )

        let decision = service.preflightDecision(
            userMessage: message,
            context: context,
            tools: [calendarTool, calendarCreateTool]
        )

        guard case .skip(.call(let request)) = decision,
              let startRaw = request.arguments["start"],
              let endRaw = request.arguments["end_or_duration"],
              let startDate = ISO8601DateFormatter().date(from: startRaw),
              let endDate = ISO8601DateFormatter().date(from: endRaw) else {
            return XCTFail("Expected preflight to create a calendar event with ISO dates")
        }

        let calendar = Calendar.current
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: startDate)
        XCTAssertEqual(request.toolName, "calendar_create")
        XCTAssertEqual(request.arguments["title"], "Meeting with Alex")
        XCTAssertEqual(components.weekday, 6)
        XCTAssertEqual(components.hour, 18)
        XCTAssertEqual(components.minute, 0)
        XCTAssertEqual(endDate.timeIntervalSince(startDate), 3_600)
    }

    func testPreflightTimerCreateNormalizesDuration() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Set a timer for 10 minutes",
            context: emptyContext,
            tools: [timerCreateTool]
        )

        XCTAssertEqual(
            decision,
            .skip(.call(ToolCallRequest(toolName: "timer_create", arguments: ["duration": "600"])))
        )
    }

    func testPreflightTimerCreateAcceptsDurationBeforeTimer() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Put a 5 minute timer",
            context: emptyContext,
            tools: [timerCreateTool]
        )

        XCTAssertEqual(
            decision,
            .skip(.call(ToolCallRequest(toolName: "timer_create", arguments: ["duration": "300"])))
        )
    }

    func testParsesContactsLookupDecision() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"contacts_lookup","args":{"query":"Alice Appleseed"}}"#,
            tools: [contactsLookupTool],
            context: emptyContext
        )

        XCTAssertEqual(
            decision,
            .call(ToolCallRequest(toolName: "contacts_lookup", arguments: ["query": "Alice Appleseed"]))
        )
    }

    func testPreflightContactsLookupExtractsQuery() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Look up Alice Appleseed in my contacts",
            context: emptyContext,
            tools: [contactsLookupTool]
        )

        XCTAssertEqual(
            decision,
            .skip(.call(ToolCallRequest(toolName: "contacts_lookup", arguments: ["query": "Alice Appleseed"])))
        )
    }

    func testPreflightContactsLookupAcceptsSearchWithoutFor() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Search Marc in my contacts",
            context: emptyContext,
            tools: [contactsLookupTool]
        )

        XCTAssertEqual(
            decision,
            .skip(.call(ToolCallRequest(toolName: "contacts_lookup", arguments: ["query": "Marc"])))
        )
    }

    func testPreflightContactsLookupExtractsWhatIsContactQuery() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "What is Mami contact",
            context: emptyContext,
            tools: [contactsLookupTool]
        )

        XCTAssertEqual(
            decision,
            .skip(.call(ToolCallRequest(toolName: "contacts_lookup", arguments: ["query": "Mami"])))
        )
    }

    func testPreflightContactsLookupExtractsCurlyPossessivePhoneQuery() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "What is Ivana’s phone number?",
            context: emptyContext,
            tools: [contactsLookupTool]
        )

        XCTAssertEqual(
            decision,
            .skip(.call(ToolCallRequest(toolName: "contacts_lookup", arguments: ["query": "Ivana"])))
        )
    }

    func testPreflightContactsLookupExtractsContactExistenceQuery() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.preflightDecision(
            userMessage: "Do I have Ivana as contact in my phone?",
            context: emptyContext,
            tools: [contactsLookupTool]
        )

        XCTAssertEqual(
            decision,
            .skip(.call(ToolCallRequest(toolName: "contacts_lookup", arguments: ["query": "Ivana"])))
        )
    }

    func testInvalidDueArgumentFailsClosedForRemindersCreate() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.parsePlannerDecision(
            from: #"{"tool":"reminders_create","args":{"title":"Buy milk","due":"someday maybe"}}"#,
            tools: [remindersCreateTool],
            context: emptyContext
        )

        XCTAssertEqual(decision, .none)
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

    private var currentDateTimeTool: ToolDefinition {
        ToolDefinition(
            name: "current_datetime",
            description: "Returns the device's current local date and time.",
            argumentSchema: [],
            metadata: ToolMetadata(executionClass: .local)
        )
    }

    private var calendarCreateTool: ToolDefinition {
        ToolDefinition(
            name: "calendar_create",
            description: "Creates one calendar event.",
            argumentSchema: [
                ToolArgument(name: "title", type: "string", required: true, description: "Event title."),
                ToolArgument(name: "start", type: "string", required: true, description: "Start datetime."),
                ToolArgument(name: "end_or_duration", type: "string", required: true, description: "End datetime or duration."),
                ToolArgument(name: "location", type: "string", required: false, description: "Location."),
                ToolArgument(name: "notes", type: "string", required: false, description: "Notes."),
                ToolArgument(name: "alert_minutes_before", type: "string", required: false, description: "Alert offset.")
            ],
            metadata: ToolMetadata(executionClass: .local)
        )
    }

    private var remindersBriefTool: ToolDefinition {
        ToolDefinition(
            name: "reminders_brief",
            description: "Reads incomplete reminders.",
            argumentSchema: [
                ToolArgument(
                    name: "range",
                    type: "string",
                    required: true,
                    description: "One of all, today, tomorrow, this_week, next_7_days, overdue."
                )
            ],
            metadata: ToolMetadata(executionClass: .local)
        )
    }

    private var remindersCreateTool: ToolDefinition {
        ToolDefinition(
            name: "reminders_create",
            description: "Creates a reminder with optional due date and notes.",
            argumentSchema: [
                ToolArgument(
                    name: "title",
                    type: "string",
                    required: true,
                    description: "Reminder title."
                ),
                ToolArgument(
                    name: "due",
                    type: "string",
                    required: false,
                    description: "Optional due date expression."
                ),
                ToolArgument(
                    name: "notes",
                    type: "string",
                    required: false,
                    description: "Optional notes."
                )
            ],
            metadata: ToolMetadata(executionClass: .local)
        )
    }

    private var timerCreateTool: ToolDefinition {
        ToolDefinition(
            name: "timer_create",
            description: "Creates a timer.",
            argumentSchema: [
                ToolArgument(name: "duration", type: "string", required: true, description: "Duration."),
                ToolArgument(name: "title", type: "string", required: false, description: "Timer title.")
            ],
            metadata: ToolMetadata(executionClass: .local)
        )
    }

    private var contactsLookupTool: ToolDefinition {
        ToolDefinition(
            name: "contacts_lookup",
            description: "Looks up local contacts.",
            argumentSchema: [
                ToolArgument(name: "query", type: "string", required: true, description: "Contact name.")
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
