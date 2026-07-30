import Foundation
import XCTest
@testable import iMLX

final class ToolTurnTests: XCTestCase {
    func testDesktopAllowsTwoCallsWhileMobileAllowsOne() {
        let desktop = ToolTurnPolicy(platformClass: .desktop)
        let mobile = ToolTurnPolicy(platformClass: .mobile)

        XCTAssertEqual(desktop.maxToolCallsPerTurn, 2)
        XCTAssertTrue(desktop.allowsAnotherCall(after: 1))
        XCTAssertFalse(desktop.allowsAnotherCall(after: 2))
        XCTAssertEqual(mobile.maxToolCallsPerTurn, 1)
        XCTAssertFalse(mobile.allowsAnotherCall(after: 1))
    }

    func testContinuationPromptIncludesCompletedResult() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let step = ToolTurnStep(
            call: ToolCallRequest(toolName: "current_datetime", arguments: [:]),
            result: result(toolName: "current_datetime", context: "Monday at 10:00")
        )

        let prompt = service.planningPrompt(
            userMessage: "What is on my calendar now?",
            history: [],
            tools: [readTool],
            context: emptyContext,
            completedSteps: [step]
        )

        XCTAssertTrue(prompt.contains("Current-turn completed tool calls:"))
        XCTAssertTrue(prompt.contains("current_datetime"))
        XCTAssertTrue(prompt.contains("Monday at 10:00"))
    }

    func testContinuationAcceptsDifferentValidatedCall() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let firstStep = ToolTurnStep(
            call: ToolCallRequest(toolName: "current_datetime", arguments: [:]),
            result: result(toolName: "current_datetime", context: "Monday")
        )

        let decision = service.resolvedContinuationDecision(
            plannerOutcome: .decision(.call(ToolCallRequest(toolName: "calendar_brief", arguments: ["range": "today"]))),
            originalUserMessage: "What time is it and what is on my calendar today?",
            context: emptyContext,
            tools: [readTool],
            completedSteps: [firstStep]
        )

        XCTAssertEqual(
            decision,
            .call(ToolCallRequest(toolName: "calendar_brief", arguments: ["range": "today"]))
        )
    }

    func testContinuationRejectsIdenticalRepeatedCall() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let request = ToolCallRequest(toolName: "calendar_brief", arguments: ["range": "today"])
        let firstStep = ToolTurnStep(
            call: request,
            result: result(toolName: "calendar_brief", context: "Noon meeting")
        )

        let decision = service.resolvedContinuationDecision(
            plannerOutcome: .decision(.call(request)),
            originalUserMessage: "What is on my calendar today?",
            context: emptyContext,
            tools: [readTool],
            completedSteps: [firstStep]
        )

        XCTAssertEqual(decision, .none)
    }

    func testMutationRequiresExplicitOriginalAuthorization() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let request = ToolCallRequest(toolName: "reminders_create", arguments: ["title": "Buy milk"])

        let rejected = service.validatedTurnDecision(
            .call(request),
            originalUserMessage: "How do I create a reminder?",
            context: emptyContext,
            tools: [mutationTool],
            completedSteps: []
        )
        let accepted = service.validatedTurnDecision(
            .call(request),
            originalUserMessage: "Remind me to buy milk",
            context: emptyContext,
            tools: [mutationTool],
            completedSteps: []
        )

        XCTAssertEqual(rejected, .none)
        XCTAssertEqual(accepted, .call(request))
        XCTAssertTrue(ToolTurnPolicy(platformClass: .desktop).shouldStop(after: mutationTool))
    }

    func testMisspelledReminderStillAuthorizesMutation() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let request = ToolCallRequest(
            toolName: "reminders_create",
            arguments: ["title": "brush my teeth"]
        )

        let decision = service.validatedTurnDecision(
            .call(request),
            originalUserMessage: "Set a remider to brush my teeth in 1 hour",
            context: emptyContext,
            tools: [mutationTool],
            completedSteps: []
        )

        XCTAssertEqual(decision, .call(request))
    }

    func testRelativeDueSurvivesValidationRoundTrip() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let reference = Date()
        guard case .success(let firstDue) = ToolDueDateParser.parse(
            "in 1 hour",
            referenceDate: reference,
            calendar: .current
        ) else {
            return XCTFail("Expected relative due to parse")
        }
        let firstISO = ToolDueDateParser.iso8601DueString(from: firstDue)

        guard case .success(let secondDue) = ToolDueDateParser.parse(
            firstISO,
            referenceDate: reference,
            calendar: .current
        ) else {
            return XCTFail("Expected ISO due to re-parse")
        }

        XCTAssertEqual(
            abs(secondDue.timeIntervalSince(firstDue)),
            0,
            accuracy: 1,
            "Re-validating an already-normalized ISO due must not shift the instant"
        )
        XCTAssertNotNil(ToolDueDateParser.parseISO8601DateTime(firstISO))
    }

    func testISODateTimeIsNotCollapsedToLocal2AM() {
        let raw = "2026-07-27T12:11:10+02:00"
        guard case .success(let date) = ToolDueDateParser.parse(
            raw,
            referenceDate: Date(),
            calendar: Calendar(identifier: .gregorian)
        ) else {
            return XCTFail("Expected datetime parse")
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 2 * 3600) ?? .current
        let components = calendar.dateComponents([.hour, .minute], from: date)
        XCTAssertEqual(components.hour, 12)
        XCTAssertEqual(components.minute, 11)
    }

    func testValidatedTurnDecisionPreservesNormalizedReminderDue() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let due = "2026-07-27T12:11:10+02:00"
        let request = ToolCallRequest(
            toolName: "reminders_create",
            arguments: ["title": "Brush teeth", "due": due]
        )

        let decision = service.validatedTurnDecision(
            .call(request),
            originalUserMessage: "Set a reminder to brush my teeth in 1 hour",
            context: emptyContext,
            tools: [mutationTool],
            completedSteps: []
        )

        guard case .call(let normalized) = decision else {
            return XCTFail("Expected validated reminders_create call")
        }
        guard let normalizedDue = normalized.arguments["due"],
              let originalDate = ToolDueDateParser.parseISO8601DateTime(due),
              let normalizedDate = ToolDueDateParser.parseISO8601DateTime(normalizedDue) else {
            return XCTFail("Expected round-trippable due values")
        }
        XCTAssertEqual(abs(normalizedDate.timeIntervalSince(originalDate)), 0, accuracy: 1)
    }

    func testPendingClarificationRetainsMutationAuthorization() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let history = [
            ChatMessage(role: .user, content: "Remind me to buy milk tomorrow"),
            ChatMessage(role: .assistant, content: "What time tomorrow should I remind you?")
        ]
        let request = ToolCallRequest(toolName: "reminders_create", arguments: ["title": "Buy milk"])

        let decision = service.validatedTurnDecision(
            .call(request),
            originalUserMessage: "5 pm",
            context: emptyContext,
            tools: [mutationTool],
            completedSteps: [],
            authorizationHistory: history
        )

        XCTAssertEqual(decision, .call(request))
    }

    func testUnusableContinuationRecoversPendingCalendarRead() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.resolvedContinuationDecision(
            plannerOutcome: .unusable,
            originalUserMessage: "What time is it, and what do I have on my calendar today?",
            context: emptyContext,
            tools: [readTool, currentDateTimeTool],
            completedSteps: [
                ToolTurnStep(
                    call: ToolCallRequest(toolName: "current_datetime", arguments: [:]),
                    result: result(toolName: "current_datetime", context: "Monday 12:00")
                )
            ]
        )

        XCTAssertEqual(
            decision,
            .call(ToolCallRequest(toolName: "calendar_brief", arguments: ["range": "today"]))
        )
    }

    func testUnusableContinuationEndsWhenNothingPending() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.resolvedContinuationDecision(
            plannerOutcome: .unusable,
            originalUserMessage: "Thanks",
            context: emptyContext,
            tools: [readTool],
            completedSteps: []
        )

        XCTAssertEqual(decision, .none)
    }

    func testPlannerNoneStillContinuesPendingDateTime() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.resolvedContinuationDecision(
            plannerOutcome: .decision(.none),
            originalUserMessage: "What time is it, and what do I have on my calendar today?",
            context: emptyContext,
            tools: [readTool, currentDateTimeTool],
            completedSteps: [
                ToolTurnStep(
                    call: ToolCallRequest(toolName: "calendar_brief", arguments: ["range": "today"]),
                    result: result(toolName: "calendar_brief", context: "No events")
                )
            ]
        )

        XCTAssertEqual(
            decision,
            .call(ToolCallRequest(toolName: "current_datetime", arguments: [:]))
        )
    }

    func testUnusableContinuationAfterWebSearchResolvesRelativeTomorrow() {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let decision = service.resolvedContinuationDecision(
            plannerOutcome: .unusable,
            originalUserMessage: "Is FC Barcelona playing a game tomorrow?",
            context: emptyContext,
            tools: [webSearchTool, currentDateTimeTool],
            completedSteps: [
                ToolTurnStep(
                    call: ToolCallRequest(
                        toolName: "web_search",
                        arguments: ["query": "Is FC Barcelona playing a game tomorrow"]
                    ),
                    result: result(toolName: "web_search", context: "Upcoming fixtures listed without a clear tomorrow match.")
                )
            ]
        )

        XCTAssertEqual(
            decision,
            .call(ToolCallRequest(toolName: "current_datetime", arguments: [:]))
        )
    }

    func testAggregationPreservesBothResultsAndDeduplicatesSources() {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let source = MessageSource(
            id: "shared",
            kind: .web,
            title: "Example",
            excerpt: "Excerpt",
            location: nil,
            url: URL(string: "https://example.com"),
            score: 1
        )
        let first = ToolTurnStep(
            call: ToolCallRequest(toolName: "web_search", arguments: ["query": "first"]),
            result: result(toolName: "web_search", context: String(repeating: "A", count: 300), sources: [source])
        )
        let second = ToolTurnStep(
            call: ToolCallRequest(toolName: "calendar_brief", arguments: ["range": "today"]),
            result: result(toolName: "calendar_brief", context: String(repeating: "B", count: 300), sources: [source])
        )

        let aggregate = service.aggregatedResults(for: [first, second], maxCharacters: 300)

        XCTAssertLessThanOrEqual(aggregate.contextBlock.count, 300)
        XCTAssertTrue(aggregate.contextBlock.contains("Tool result 1 — web_search"))
        XCTAssertTrue(aggregate.contextBlock.contains("Tool result 2 — calendar_brief"))
        XCTAssertTrue(aggregate.contextBlock.contains("AAAA"))
        XCTAssertTrue(aggregate.contextBlock.contains("BBBB"))
        XCTAssertEqual(aggregate.sources, [source])
    }

    func testChatMessageDecodesLegacySingularTrace() throws {
        let json = """
        {
          "id": "00000000-0000-0000-0000-000000000001",
          "role": "assistant",
          "content": "Done",
          "toolTrace": {
            "toolName": "web_search",
            "displayInput": "weather",
            "status": "success",
            "durationSeconds": 0.2,
            "success": true,
            "sourceCount": 1
          },
          "timestamp": 0
        }
        """

        let message = try JSONDecoder().decode(ChatMessage.self, from: Data(json.utf8))

        XCTAssertEqual(message.toolTraces?.count, 1)
        XCTAssertEqual(message.toolTrace?.toolName, "web_search")
    }

    func testChatMessageRoundTripsOrderedTraces() throws {
        let traces = [
            trace(toolName: "current_datetime", followUpReasoning: "Got the time; checking calendar next."),
            trace(toolName: "calendar_brief")
        ]
        let original = ChatMessage(role: .assistant, content: "Done", toolTraces: traces)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ChatMessage.self, from: data)

        XCTAssertEqual(decoded.toolTraces, traces)
        XCTAssertEqual(decoded.toolTraces?.first?.followUpReasoning, "Got the time; checking calendar next.")
        XCTAssertEqual(decoded.toolTrace?.toolName, "calendar_brief")
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("toolTraces"))
    }

    private var emptyContext: ToolInputContext {
        ToolInputContext(latestUserMessage: "", attachedImages: [], detectedPublicURLs: [])
    }

    private var readTool: ToolDefinition {
        ToolDefinition(
            name: "calendar_brief",
            description: "Reads calendar events.",
            argumentSchema: [
                ToolArgument(name: "range", type: "string", required: true, description: "Range")
            ]
        )
    }

    private var currentDateTimeTool: ToolDefinition {
        ToolDefinition(
            name: "current_datetime",
            description: "Returns the device local date and time.",
            argumentSchema: []
        )
    }

    private var webSearchTool: ToolDefinition {
        ToolDefinition(
            name: "web_search",
            description: "Searches the web.",
            argumentSchema: [
                ToolArgument(name: "query", type: "string", required: true, description: "Query")
            ],
            metadata: ToolMetadata(requiresWebAccessToggle: true, executionClass: .network)
        )
    }

    private var mutationTool: ToolDefinition {
        ToolDefinition(
            name: "reminders_create",
            description: "Creates a reminder.",
            argumentSchema: [
                ToolArgument(name: "title", type: "string", required: true, description: "Title"),
                ToolArgument(name: "due", type: "string", required: false, description: "Due"),
                ToolArgument(name: "notes", type: "string", required: false, description: "Notes")
            ],
            metadata: ToolMetadata(mutatesUserData: true)
        )
    }

    private func result(
        toolName: String,
        context: String,
        sources: [MessageSource] = []
    ) -> ToolExecutionResult {
        ToolExecutionResult(
            toolName: toolName,
            status: .success,
            message: nil,
            contextBlock: context,
            sources: sources,
            durationSeconds: 0.1
        )
    }

    private func trace(toolName: String, followUpReasoning: String? = nil) -> ToolCallTrace {
        ToolCallTrace(
            toolName: toolName,
            displayInput: nil,
            status: .success,
            durationSeconds: 0.1,
            success: true,
            sourceCount: 0,
            followUpReasoning: followUpReasoning
        )
    }
}
