import Foundation

extension ToolCallingService {
    nonisolated func planningPrompt(
        userMessage: String,
        history: [ChatMessage],
        tools: [ToolDefinition],
        context: ToolInputContext
    ) -> String {
        let toolDescriptions = tools.map { tool in
            let arguments = tool.argumentSchema
                .map { argument in
                    "\(argument.name): \(argument.type)\(argument.required ? " required" : " optional")"
                }
                .joined(separator: ", ")
            return "- \(tool.name): \(tool.description) Args: \(arguments.isEmpty ? "(none)" : arguments)"
        }
        .joined(separator: "\n")

        let recentHistory = history
            .filter { $0.role != .system }
            .suffix(4)
            .map { message in
                let compactContent = message.content
                    .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let boundedContent = String(compactContent.prefix(220))
                let toolSummary: String
                if let trace = message.toolTrace, trace.success {
                    let input = trace.displayInput.map {
                        String($0.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).prefix(100))
                    }
                    let inputSummary = input.map { ", input: \($0)" } ?? ""
                    toolSummary = " [successful tool: \(trace.toolName)\(inputSummary)]"
                } else {
                    toolSummary = ""
                }
                return "\(message.role.rawValue): \(boundedContent)\(toolSummary)"
            }
            .joined(separator: "\n")

        let currentDateTimeFormatter = ISO8601DateFormatter()
        currentDateTimeFormatter.formatOptions = [.withInternetDateTime]
        currentDateTimeFormatter.timeZone = .current
        let currentLocalDateTime = currentDateTimeFormatter.string(from: Date())
        let currentTurnContext = [
            "- Current local datetime: \(currentLocalDateTime) (\(TimeZone.current.identifier))",
            "- Attached image count: \(context.attachedImages.count)",
            "- Attached document count: \(context.attachedDocuments.count)",
            "- Newly attached documents this turn: \(context.hasNewlyAttachedDocuments ? "yes" : "no")",
            "- Detected public URL: \(context.singleDetectedPublicURL?.absoluteString ?? (context.detectedPublicURLs.isEmpty ? "none" : "multiple URLs detected"))"
        ]
        .joined(separator: "\n")

        return """
        Available tools:
        \(toolDescriptions)

        Current turn context:
        \(currentTurnContext)

        Recent conversation:
        \(recentHistory.isEmpty ? "(none)" : recentHistory)

        Latest user message:
        \(userMessage)
        """
    }

    func withTimeout<T: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try Task.checkCancellation()
                return try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw ToolExecutionError.timedOut
            }

            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    func clippedToolContext(_ context: String) -> String {
        guard context.count > Constants.ToolCalling.maxToolResultContextCharacters else {
            return context
        }
        return String(context.prefix(Constants.ToolCalling.maxToolResultContextCharacters))
    }


}
