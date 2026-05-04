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

    func testResolvedDecisionRecoversRemindersBriefForOverdueRequest() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.resolvedDecision(
            plannedDecision: .none,
            userMessage: "Show me my overdue reminders",
            context: emptyContext,
            tools: [remindersBriefTool],
            preferThinkingFallback: false
        )

        XCTAssertEqual(
            decision,
            .call(ToolCallRequest(toolName: "reminders_brief", arguments: ["range": "overdue"]))
        )
    }

    func testResolvedDecisionDoesNotConfuseRemindMeToWithMemory() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.resolvedDecision(
            plannedDecision: .none,
            userMessage: "Please remind me of our trip to Paris",
            context: emptyContext,
            tools: [remindersCreateTool],
            preferThinkingFallback: false
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
            description: "Reads incomplete reminders for a bounded range.",
            argumentSchema: [
                ToolArgument(
                    name: "range",
                    type: "string",
                    required: true,
                    description: "One of today, tomorrow, this_week, next_7_days, overdue."
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
