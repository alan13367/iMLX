import XCTest
@testable import iMLX

final class ToolExecutionTests: XCTestCase {
    func testExecuteMapsGenericExecutorFailureToExecutionFailed() async throws {
        let service = ToolCallingService(
            webSearchService: WebSearchService(),
            toolExecutionTimeoutSeconds: 0.05
        )

        let result = try await service.execute(
            call: ToolCallRequest(
                toolName: "web_search",
                arguments: ["query": "Barcelona next match"]
            ),
            tools: ["web_search": ThrowingExecutor()],
            context: emptyContext
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.status, .executionFailed)
        XCTAssertEqual(result.contextBlock, "")
        XCTAssertTrue(result.sources.isEmpty)
        XCTAssertGreaterThanOrEqual(result.durationSeconds, 0)
    }

    func testExecuteReturnsTimedOutResultOnTimeout() async throws {
        let service = ToolCallingService(
            webSearchService: WebSearchService(),
            toolExecutionTimeoutSeconds: 0.01
        )

        let result = try await service.execute(
            call: ToolCallRequest(
                toolName: "web_search",
                arguments: ["query": "Barcelona next match"]
            ),
            tools: ["web_search": SlowExecutor(toolName: "web_search")],
            context: emptyContext
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.status, .timedOut)
        XCTAssertEqual(result.contextBlock, "")
        XCTAssertTrue(result.sources.isEmpty)
        XCTAssertGreaterThanOrEqual(result.durationSeconds, 0.01)
    }

    func testExecuteMapsWebSearchNetworkFailureToNetworkUnavailable() async throws {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let result = try await service.execute(
            call: ToolCallRequest(
                toolName: "web_search",
                arguments: ["query": "Barcelona next match"]
            ),
            tools: ["web_search": NetworkUnavailableExecutor(toolName: "web_search")],
            context: emptyContext
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.status, .networkUnavailable)
    }

    func testExecuteMapsReadURLNetworkFailureToNetworkUnavailable() async throws {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Read https://example.com",
            attachedImages: [],
            detectedPublicURLs: [URL(string: "https://example.com")!]
        )

        let result = try await service.execute(
            call: ToolCallRequest(
                toolName: "read_url",
                arguments: ["url": "https://example.com"]
            ),
            tools: ["read_url": NetworkUnavailableExecutor(toolName: "read_url")],
            context: context
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.status, .networkUnavailable)
    }

    func testExecuteMapsOCRNoTextToNoContent() async throws {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Read this screenshot",
            attachedImages: [ChatAttachmentImage(data: Data([0x01]))],
            detectedPublicURLs: []
        )

        let result = try await service.execute(
            call: ToolCallRequest(toolName: "ocr_image_text", arguments: [:]),
            tools: ["ocr_image_text": NoContentExecutor(toolName: "ocr_image_text")],
            context: context
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.status, .noContent)
    }

    func testExecuteRejectsInvalidQueryArguments() async throws {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let result = try await service.execute(
            call: ToolCallRequest(toolName: "web_search", arguments: ["query": ""]),
            tools: ["web_search": SlowExecutor(toolName: "web_search")],
            context: emptyContext
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.status, .invalidArguments)
    }

    func testExecuteRejectsInvalidReadURLArguments() async throws {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let result = try await service.execute(
            call: ToolCallRequest(toolName: "read_url", arguments: ["url": "ftp://example.com"]),
            tools: ["read_url": SlowExecutor(toolName: "read_url")],
            context: emptyContext
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.status, .invalidArguments)
    }

    func testExecuteRejectsDocumentSynthesisWithoutAttachedDocuments() async throws {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let result = try await service.execute(
            call: ToolCallRequest(toolName: "document_synthesize", arguments: ["query": "summarize"]),
            tools: ["document_synthesize": SlowExecutor(toolName: "document_synthesize")],
            context: emptyContext
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.status, .invalidArguments)
    }

    func testExecuteRejectsInvalidCalendarRange() async throws {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let result = try await service.execute(
            call: ToolCallRequest(toolName: "calendar_brief", arguments: ["range": "next_month"]),
            tools: ["calendar_brief": SlowExecutor(toolName: "calendar_brief")],
            context: emptyContext
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.status, .invalidArguments)
    }

    func testExecuteCurrentDateTimeReturnsFormattedNow() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1_704_067_200)
        let timeZone = TimeZone(identifier: "Europe/Madrid")!
        let service = ToolCallingService(
            webSearchService: WebSearchService(),
            currentDateTimeNow: { fixedDate },
            currentDateTimeTimeZone: timeZone
        )

        let executors = await service.executors()
        let result = try await service.execute(
            call: ToolCallRequest(toolName: "current_datetime", arguments: [:]),
            tools: executors,
            context: emptyContext
        )

        XCTAssertTrue(result.success)
        XCTAssertTrue(result.contextBlock.contains("Current local date/time:"))
        XCTAssertTrue(result.contextBlock.contains("ISO 8601:"))
        XCTAssertTrue(result.contextBlock.contains("Europe/Madrid"))
    }

    func testExecuteRemindersCreateRejectsEmptyTitle() async throws {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let executors = await service.executors()
        let result = try await service.execute(
            call: ToolCallRequest(toolName: "reminders_create", arguments: ["title": "   "]),
            tools: executors,
            context: emptyContext
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.status, .invalidArguments)
    }

    func testExecuteRemindersCreatePassesNormalizedArgumentsToExecutor() async throws {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let recorder = ArgumentRecorder()

        let result = try await service.execute(
            call: ToolCallRequest(
                toolName: "reminders_create",
                arguments: [
                    "title": "  Buy milk  ",
                    "due": "tomorrow",
                    "notes": "  Organic if possible  "
                ]
            ),
            tools: ["reminders_create": RecordingExecutor(toolName: "reminders_create", recorder: recorder)],
            context: emptyContext
        )

        let arguments = await recorder.arguments
        XCTAssertTrue(result.success)
        XCTAssertEqual(arguments["title"], "Buy milk")
        XCTAssertEqual(arguments["notes"], "Organic if possible")
        XCTAssertNotNil(arguments["due"])
        XCTAssertTrue(arguments["due"]?.contains("T") == true)
    }

    func testExecuteRemindersBriefRejectsInvalidRange() async throws {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let executors = await service.executors()
        let result = try await service.execute(
            call: ToolCallRequest(toolName: "reminders_brief", arguments: ["range": "next_month"]),
            tools: executors,
            context: emptyContext
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.status, .invalidArguments)
    }

    func testExecuteCalendarCreatePassesNormalizedArgumentsToExecutor() async throws {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let recorder = ArgumentRecorder()

        let result = try await service.execute(
            call: ToolCallRequest(
                toolName: "calendar_create",
                arguments: [
                    "title": "  Project review  ",
                    "start": "2026-05-03T10:00",
                    "end_or_duration": "30 minutes",
                    "location": "  Office  ",
                    "alert_minutes_before": "10"
                ]
            ),
            tools: ["calendar_create": RecordingExecutor(toolName: "calendar_create", recorder: recorder)],
            context: emptyContext
        )

        let arguments = await recorder.arguments
        XCTAssertTrue(result.success)
        XCTAssertEqual(arguments["title"], "Project review")
        XCTAssertEqual(arguments["location"], "Office")
        XCTAssertEqual(arguments["alert_minutes_before"], "10")
        XCTAssertTrue(arguments["start"]?.contains("T") == true)
        XCTAssertTrue(arguments["end_or_duration"]?.contains("T") == true)
    }

    func testExecuteCalendarCreateRejectsVagueStart() async throws {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let result = try await service.execute(
            call: ToolCallRequest(
                toolName: "calendar_create",
                arguments: [
                    "title": "Lunch",
                    "start": "tomorrow",
                    "end_or_duration": "1 hour"
                ]
            ),
            tools: ["calendar_create": SlowExecutor(toolName: "calendar_create")],
            context: emptyContext
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.status, .invalidArguments)
    }

    func testExecuteTimerCreatePassesDurationSecondsToExecutor() async throws {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let recorder = ArgumentRecorder()

        let result = try await service.execute(
            call: ToolCallRequest(
                toolName: "timer_create",
                arguments: [
                    "duration": "10 minutes",
                    "title": "  Pasta  "
                ]
            ),
            tools: ["timer_create": RecordingExecutor(toolName: "timer_create", recorder: recorder)],
            context: emptyContext
        )

        let arguments = await recorder.arguments
        XCTAssertTrue(result.success)
        XCTAssertEqual(arguments["duration"], "600")
        XCTAssertEqual(arguments["title"], "Pasta")
    }

    func testExecuteContactsLookupPassesTrimmedQueryToExecutor() async throws {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let recorder = ArgumentRecorder()

        let result = try await service.execute(
            call: ToolCallRequest(
                toolName: "contacts_lookup",
                arguments: ["query": "  Alice   Appleseed  "]
            ),
            tools: ["contacts_lookup": RecordingExecutor(toolName: "contacts_lookup", recorder: recorder)],
            context: emptyContext
        )

        let arguments = await recorder.arguments
        XCTAssertTrue(result.success)
        XCTAssertEqual(arguments["query"], "Alice Appleseed")
    }

    func testExecutePropagatesCancellation() async {
        let service = ToolCallingService(
            webSearchService: WebSearchService(),
            toolExecutionTimeoutSeconds: 1
        )

        let task = Task {
            try await service.execute(
                call: ToolCallRequest(
                    toolName: "web_search",
                    arguments: ["query": "Barcelona next match"]
                ),
                tools: ["web_search": SlowExecutor(toolName: "web_search")],
                context: emptyContext
            )
        }

        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    func testToolTraceDecodesWithoutStatusForBackwardCompatibility() throws {
        let json = """
        {
          "toolName": "web_search",
          "rewrittenQuery": "weather Barcelona today",
          "durationSeconds": 1.5,
          "success": true,
          "sourceCount": 2
        }
        """

        let trace = try JSONDecoder().decode(ToolCallTrace.self, from: Data(json.utf8))

        XCTAssertEqual(trace.toolName, "web_search")
        XCTAssertEqual(trace.displayInput, "weather Barcelona today")
        XCTAssertNil(trace.status)
        XCTAssertTrue(trace.success)
        XCTAssertEqual(trace.sourceCount, 2)
    }

    private var emptyContext: ToolInputContext {
        ToolInputContext(
            latestUserMessage: "",
            attachedImages: [],
            detectedPublicURLs: []
        )
    }
}

private struct ThrowingExecutor: ToolExecutor {
    let toolName = "web_search"

    func execute(arguments _: [String : String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        struct StubError: Error {}
        throw StubError()
    }
}

private struct SlowExecutor: ToolExecutor {
    let toolName: String

    func execute(arguments _: [String : String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        try await Task.sleep(nanoseconds: 250_000_000)
        return ToolExecutionResult(
            toolName: toolName,
            status: .success,
            message: nil,
            contextBlock: "slow result",
            sources: [],
            durationSeconds: 0.25
        )
    }
}

private struct NetworkUnavailableExecutor: ToolExecutor {
    let toolName: String

    func execute(arguments _: [String : String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        throw ToolExecutionFailure.networkUnavailable("Offline")
    }
}

private struct NoContentExecutor: ToolExecutor {
    let toolName: String

    func execute(arguments _: [String : String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        throw ToolExecutionFailure.noContent("No content")
    }
}

private actor ArgumentRecorder {
    private(set) var arguments: [String: String] = [:]

    func record(_ arguments: [String: String]) {
        self.arguments = arguments
    }
}

private struct RecordingExecutor: ToolExecutor {
    let toolName: String
    let recorder: ArgumentRecorder

    func execute(arguments: [String: String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        await recorder.record(arguments)
        return ToolExecutionResult(
            toolName: toolName,
            status: .success,
            message: nil,
            contextBlock: "recorded",
            sources: [],
            durationSeconds: 0
        )
    }
}
