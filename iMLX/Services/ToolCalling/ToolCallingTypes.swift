import Foundation

enum ToolExecutionFailure: Error, Equatable, Sendable {
    case invalidArguments(String)
    case noContent(String)
    case networkUnavailable(String)
    case permissionDenied(String)
    case unavailable(String)
    case executionFailed(String)

    var status: ToolExecutionStatus {
        switch self {
        case .invalidArguments:
            return .invalidArguments
        case .noContent:
            return .noContent
        case .networkUnavailable:
            return .networkUnavailable
        case .permissionDenied:
            return .permissionDenied
        case .unavailable:
            return .unavailable
        case .executionFailed:
            return .executionFailed
        }
    }

    var message: String {
        switch self {
        case .invalidArguments(let message),
             .noContent(let message),
             .networkUnavailable(let message),
             .permissionDenied(let message),
             .unavailable(let message),
             .executionFailed(let message):
            return message
        }
    }
}

protocol ToolExecutor: Sendable {
    var toolName: String { get }
    func execute(arguments: [String: String], context: ToolInputContext) async throws -> ToolExecutionResult
}

nonisolated struct ToolTurnStep: Equatable, Sendable {
    let call: ToolCallRequest
    let result: ToolExecutionResult
}

/// Result of the synchronous preflight that decides whether a turn even needs the
/// LLM-backed planner. `skip` carries a final decision (either a confident heuristic
/// tool call or `.none` for clearly tool-independent turns); `deliberate` means the
/// planner should run so the model can choose a tool when heuristics did not match.
nonisolated enum ToolPreflight: Equatable, Sendable {
    case skip(ToolDecision)
    case deliberate
}

/// Keeps a valid planner decision distinct from output that could not be
/// interpreted safely. A valid `.none` is respected unless the latest turn
/// deterministically completes a pending tool clarification from history.
nonisolated enum ToolPlannerOutcome: Equatable, Sendable {
    case decision(ToolDecision)
    case unusable
}
