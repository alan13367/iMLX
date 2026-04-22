import XCTest
@testable import iMLX

final class ToolExecutionTests: XCTestCase {
    func testExecuteReturnsFailureResultWhenExecutorThrows() async throws {
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
        XCTAssertEqual(result.contextBlock, "")
        XCTAssertTrue(result.sources.isEmpty)
        XCTAssertGreaterThanOrEqual(result.durationSeconds, 0)
    }

    func testExecuteReturnsFailureResultOnTimeout() async throws {
        let service = ToolCallingService(
            webSearchService: WebSearchService(),
            toolExecutionTimeoutSeconds: 0.01
        )

        let result = try await service.execute(
            call: ToolCallRequest(
                toolName: "web_search",
                arguments: ["query": "Barcelona next match"]
            ),
            tools: ["web_search": SlowExecutor()],
            context: emptyContext
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.contextBlock, "")
        XCTAssertTrue(result.sources.isEmpty)
        XCTAssertGreaterThanOrEqual(result.durationSeconds, 0.01)
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
                tools: ["web_search": SlowExecutor()],
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
    let toolName = "web_search"

    func execute(arguments _: [String : String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        try await Task.sleep(nanoseconds: 250_000_000)
        return ToolExecutionResult(
            toolName: toolName,
            contextBlock: "slow result",
            sources: [],
            success: true,
            durationSeconds: 0.25
        )
    }
}
