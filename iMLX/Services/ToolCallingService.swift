import Foundation

protocol ToolExecutor: Sendable {
    var toolName: String { get }
    func execute(arguments: [String: String]) async throws -> ToolExecutionResult
}

actor ToolCallingService {
    private enum ToolExecutionError: Error {
        case timedOut
    }

    private let toolExecutionTimeoutSeconds: TimeInterval
    private let registeredTools: [ToolDefinition]
    private let registeredExecutors: [String: any ToolExecutor]

    init(
        webSearchService: WebSearchService,
        toolExecutionTimeoutSeconds: TimeInterval = Constants.ToolCalling.toolExecutionTimeoutSeconds
    ) {
        let webSearchTool = ToolDefinition(
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
        let webSearchExecutor = WebSearchToolExecutor(webSearchService: webSearchService)
        self.toolExecutionTimeoutSeconds = toolExecutionTimeoutSeconds
        self.registeredTools = [webSearchTool]
        self.registeredExecutors = [webSearchExecutor.toolName: webSearchExecutor]
    }

    func enabledTools(webSearchEnabled: Bool) -> [ToolDefinition] {
        guard webSearchEnabled else { return [] }
        return registeredTools
    }

    func executors() -> [String: any ToolExecutor] {
        registeredExecutors
    }

    nonisolated func heuristicFallbackDecision(
        userMessage: String,
        tools: [ToolDefinition]
    ) -> ToolDecision? {
        let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        guard let webSearchTool = toolsByName["web_search"],
              shouldForceWebSearch(for: userMessage) else {
            return nil
        }

        guard let query = heuristicWebSearchQuery(for: userMessage),
              let arguments = validatedArguments(["query": query], for: webSearchTool) else {
            return nil
        }

        Self.debugLog("heuristic fallback selected web_search for obvious live-data request")
        return .call(ToolCallRequest(toolName: "web_search", arguments: arguments))
    }

    func plan(
        userMessage: String,
        history: [ChatMessage],
        tools: [ToolDefinition],
        using inferenceService: InferenceService
    ) async throws -> ToolDecision {
        guard !tools.isEmpty else {
            Self.debugLog("planner skipped: no enabled tools")
            return .none
        }

        Self.debugLog(
            "planner start: tools=\(tools.map(\.name).joined(separator: ",")) " +
            "historyCount=\(history.count) userMessage=\(Self.sanitizedSnippet(userMessage))"
        )

        let stream = await inferenceService.generate(
            prompt: planningPrompt(userMessage: userMessage, history: history, tools: tools),
            thinkingEnabled: false,
            history: [],
            systemPrompt: Constants.ToolCalling.plannerSystemPrompt,
            maxTokens: Constants.ToolCalling.plannerMaxTokens,
            temperature: Constants.ToolCalling.plannerTemperature,
            topP: Constants.ToolCalling.plannerTopP,
            repetitionPenalty: 1.0
        )

        var rawOutput = ""

        do {
            for try await token in stream {
                try Task.checkCancellation()
                rawOutput += token
            }
            let decision = parsePlannerDecision(from: rawOutput, userMessage: userMessage, tools: tools)
            Self.debugLog(
                "planner output: raw=\(Self.sanitizedSnippet(rawOutput, limit: 280)) " +
                "decision=\(Self.describe(decision))"
            )
            return decision
        } catch is CancellationError {
            Self.debugLog("planner cancelled")
            throw CancellationError()
        } catch {
            Self.debugLog("planner failed with error: \(String(describing: error))")
            return .none
        }
    }

    func execute(
        call: ToolCallRequest,
        tools: [String: any ToolExecutor]
    ) async throws -> ToolExecutionResult {
        let startTime = Date()

        guard let executor = tools[call.toolName] else {
            Self.debugLog("execution skipped: no executor registered for \(call.toolName)")
            return ToolExecutionResult(
                toolName: call.toolName,
                contextBlock: "",
                sources: [],
                success: false,
                durationSeconds: 0
            )
        }

        do {
            Self.debugLog("execution start: tool=\(call.toolName) args=\(Self.formatted(arguments: call.arguments))")
            let result = try await withTimeout(seconds: toolExecutionTimeoutSeconds) {
                try await executor.execute(arguments: call.arguments)
            }
            try Task.checkCancellation()

            let clippedContext = clippedToolContext(result.contextBlock)
            let finalResult = ToolExecutionResult(
                toolName: result.toolName,
                contextBlock: clippedContext,
                sources: result.sources,
                success: result.success && !clippedContext.isEmpty,
                durationSeconds: result.durationSeconds
            )
            Self.debugLog(
                "execution finished: tool=\(call.toolName) success=\(finalResult.success) " +
                "sources=\(finalResult.sources.count) contextChars=\(finalResult.contextBlock.count) " +
                "duration=\(String(format: "%.2f", finalResult.durationSeconds))s"
            )
            return finalResult
        } catch is CancellationError {
            Self.debugLog("execution cancelled: tool=\(call.toolName)")
            throw CancellationError()
        } catch {
            Self.debugLog("execution failed: tool=\(call.toolName) error=\(String(describing: error))")
            return ToolExecutionResult(
                toolName: call.toolName,
                contextBlock: "",
                sources: [],
                success: false,
                durationSeconds: Date().timeIntervalSince(startTime)
            )
        }
    }

    nonisolated func parsePlannerDecision(
        from text: String,
        userMessage: String? = nil,
        tools: [ToolDefinition]
    ) -> ToolDecision {
        let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })

        for payload in jsonPayloads(in: text) {
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let dictionary = object as? [String: Any],
                  let rawToolName = dictionary["tool"] as? String else {
                continue
            }

            let toolName = rawToolName.trimmingCharacters(in: .whitespacesAndNewlines)
            if toolName == "none" {
                return .none
            }

            guard let toolDefinition = toolsByName[toolName] else {
                continue
            }

            let rawArguments = dictionary["args"] as? [String: Any] ?? [:]
            guard let arguments = validatedArguments(rawArguments, for: toolDefinition) else {
                continue
            }

            return .call(
                ToolCallRequest(
                    toolName: toolName,
                    arguments: arguments
                )
            )
        }

        if let fallbackDecision = fallbackPlannerDecision(
            from: text,
            userMessage: userMessage,
            toolsByName: toolsByName
        ) {
            return fallbackDecision
        }

        return .none
    }

    nonisolated func validatedArguments(
        _ rawArguments: [String: Any],
        for toolDefinition: ToolDefinition
    ) -> [String: String]? {
        var validated: [String: String] = [:]

        for argument in toolDefinition.argumentSchema {
            let rawValue = rawArguments[argument.name]
            let stringValue = stringValue(from: rawValue)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if argument.required && (stringValue?.isEmpty != false) {
                return nil
            }

            guard let stringValue, !stringValue.isEmpty else { continue }

            switch argument.name {
            case "query":
                let clamped = String(stringValue.prefix(Constants.ToolCalling.maxQueryLength))
                if clamped.isEmpty {
                    return nil
                }
                validated[argument.name] = clamped
            default:
                validated[argument.name] = stringValue
            }
        }

        return validated
    }

    private nonisolated func planningPrompt(
        userMessage: String,
        history: [ChatMessage],
        tools: [ToolDefinition]
    ) -> String {
        let toolDescriptions = tools.map { tool in
            let arguments = tool.argumentSchema
                .map { argument in
                    "\(argument.name): \(argument.type)\(argument.required ? " required" : " optional")"
                }
                .joined(separator: ", ")
            return "- \(tool.name): \(tool.description) Args: \(arguments)"
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
                return "\(message.role.rawValue): \(boundedContent)"
            }
            .joined(separator: "\n")

        return """
        Available tools:
        \(toolDescriptions)

        Recent conversation:
        \(recentHistory.isEmpty ? "(none)" : recentHistory)

        Latest user message:
        \(userMessage)
        """
    }

    private nonisolated func stringValue(from rawValue: Any?) -> String? {
        switch rawValue {
        case let value as Bool:
            return value ? "true" : "false"
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }

    private func withTimeout<T: Sendable>(
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

    private func clippedToolContext(_ context: String) -> String {
        guard context.count > Constants.ToolCalling.maxToolResultContextCharacters else {
            return context
        }
        return String(context.prefix(Constants.ToolCalling.maxToolResultContextCharacters))
    }

    private nonisolated func jsonPayloads(in text: String) -> [String] {
        var payloads = [text]
        payloads.append(contentsOf: fencedCodePayloads(in: text))
        payloads.append(contentsOf: balancedJSONFragments(in: text))

        var seen = Set<String>()
        return payloads.compactMap { payload in
            let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { return nil }
            return trimmed
        }
    }

    private nonisolated func fencedCodePayloads(in text: String) -> [String] {
        let parts = text.components(separatedBy: "```")
        guard parts.count > 2 else { return [] }

        return parts.indices.compactMap { index in
            guard index.isMultiple(of: 2) == false else { return nil }
            var payload = parts[index].trimmingCharacters(in: .whitespacesAndNewlines)
            if payload.lowercased().hasPrefix("json") {
                payload = payload.dropFirst(4).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return payload
        }
    }

    private nonisolated func balancedJSONFragments(in text: String) -> [String] {
        var fragments: [String] = []
        var stack: [Character] = []
        var startIndex: String.Index?
        var isInString = false
        var isEscaped = false

        for index in text.indices {
            let character = text[index]

            if isInString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    isInString = false
                }
                continue
            }

            if character == "\"" {
                isInString = true
                continue
            }

            if character == "[" || character == "{" {
                if stack.isEmpty {
                    startIndex = index
                }
                stack.append(character)
                continue
            }

            if character == "]" || character == "}" {
                guard let opening = stack.last,
                      (opening == "[" && character == "]") || (opening == "{" && character == "}") else {
                    stack.removeAll()
                    startIndex = nil
                    continue
                }

                stack.removeLast()
                if stack.isEmpty, let fragmentStartIndex = startIndex {
                    fragments.append(String(text[fragmentStartIndex...index]))
                    startIndex = nil
                }
            }
        }

        return fragments
    }

    private nonisolated func fallbackPlannerDecision(
        from text: String,
        userMessage: String?,
        toolsByName: [String: ToolDefinition]
    ) -> ToolDecision? {
        let lowercasedText = text.lowercased()

        for (toolName, toolDefinition) in toolsByName {
            guard proseSuggestsUsingTool(named: toolName, in: lowercasedText) else { continue }

            switch toolName {
            case "web_search":
                guard let query = inferredWebSearchQuery(from: text, userMessage: userMessage) else {
                    continue
                }
                guard let arguments = validatedArguments(["query": query], for: toolDefinition) else {
                    continue
                }
                Self.debugLog("planner recovered prose decision for \(toolName)")
                return .call(ToolCallRequest(toolName: toolName, arguments: arguments))
            default:
                continue
            }
        }

        return nil
    }

    private nonisolated func proseSuggestsUsingTool(named toolName: String, in lowercasedText: String) -> Bool {
        let underscored = toolName.lowercased()
        let spaced = underscored.replacingOccurrences(of: "_", with: " ")
        let positivePatterns = [
            "use the \(underscored) tool",
            "use \(underscored)",
            "call \(underscored)",
            "invoke \(underscored)",
            "need to use \(underscored)",
            "should use \(underscored)",
            "use the \(spaced) tool",
            "use \(spaced)",
            "call \(spaced)",
            "invoke \(spaced)",
            "need to use \(spaced)",
            "should use \(spaced)"
        ]

        return positivePatterns.contains { lowercasedText.contains($0) }
    }

    private nonisolated func inferredWebSearchQuery(from text: String, userMessage: String?) -> String? {
        if let explicitQuery = firstRegexCapture(
            pattern: #"(?i)\bsearch for\s+["“]?(.+?)["”]?(?:[.!?\n]|$)"#,
            in: text
        ) {
            let sanitized = sanitizeRecoveredQuery(explicitQuery)
            if !sanitized.isEmpty {
                return sanitized
            }
        }

        if let explicitQuery = firstRegexCapture(
            pattern: #"(?i)\bquery\s*[:=]\s*["“]?(.+?)["”]?(?:[.!?\n]|$)"#,
            in: text
        ) {
            let sanitized = sanitizeRecoveredQuery(explicitQuery)
            if !sanitized.isEmpty {
                return sanitized
            }
        }

        guard let userMessage else { return nil }
        let sanitized = sanitizeRecoveredQuery(userMessage)
        return sanitized.isEmpty ? nil : sanitized
    }

    private nonisolated func sanitizeRecoveredQuery(_ query: String) -> String {
        query
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private nonisolated func shouldForceWebSearch(for userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }

        let liveDataPhrases = [
            "latest news",
            "breaking news",
            "news in",
            "weather today",
            "weather tomorrow",
            "weather in",
            "current weather",
            "stock price",
            "share price",
            "exchange rate",
            "next game",
            "next match",
            "live score",
            "score today",
            "price of",
            "price today"
        ]

        if liveDataPhrases.contains(where: { normalized.contains($0) }) {
            return true
        }

        let tokens = Set(normalized.split(separator: " ").map(String.init))
        let currentInfoMarkers = Set(["latest", "current", "today", "tomorrow", "now", "live"])
        let topicalMarkers = Set(["news", "weather", "forecast", "score", "match", "game", "price", "stock", "stocks"])

        return !tokens.intersection(currentInfoMarkers).isEmpty
            && !tokens.intersection(topicalMarkers).isEmpty
    }

    private nonisolated func heuristicWebSearchQuery(for userMessage: String) -> String? {
        let sanitized = sanitizeRecoveredQuery(userMessage)
        guard !sanitized.isEmpty else { return nil }

        let compact = sanitized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        if let weatherLocation = firstRegexCapture(
            pattern: #"(?i)\bweather(?:\s+for|\s+in)?\s+(.+?)(?:\s+for\s+(today|tomorrow)|\s+(today|tomorrow)|\?|$)"#,
            in: compact
        ) {
            let timeframe = firstRegexCapture(
                pattern: #"(?i)\b(today|tomorrow)\b"#,
                in: compact
            )
            let query = ["weather", sanitizeRecoveredQuery(weatherLocation), timeframe].compactMap { value in
                guard let value, !value.isEmpty else { return nil }
                return value
            }.joined(separator: " ")
            let finalQuery = sanitizeRecoveredQuery(query)
            if !finalQuery.isEmpty {
                return finalQuery
            }
        }

        if compact.range(of: #"(?i)\b(latest|breaking)\s+news\b"#, options: .regularExpression) != nil {
            if let location = firstRegexCapture(
                pattern: #"(?i)\bnews(?:\s+in|\s+for|\s+about)?\s+(.+?)(?:\?|$)"#,
                in: compact
            ) {
                let query = sanitizeRecoveredQuery("latest news \(location)")
                if !query.isEmpty {
                    return query
                }
            }
            return "latest news"
        }

        return compact
    }

    private nonisolated func normalizeForHeuristicMatching(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private nonisolated func firstRegexCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }
}

private struct WebSearchToolExecutor: ToolExecutor {
    let toolName = "web_search"
    let webSearchService: WebSearchService

    func execute(arguments: [String: String]) async throws -> ToolExecutionResult {
        let query = arguments["query"] ?? ""
        let startTime = Date()
        let result = try await webSearchService.retrieveContext(for: query)
        let duration = Date().timeIntervalSince(startTime)
        return ToolExecutionResult(
            toolName: toolName,
            contextBlock: result.contextBlock,
            sources: result.sources,
            success: !result.contextBlock.isEmpty,
            durationSeconds: duration
        )
    }
}

private extension ToolCallingService {
    static func debugLog(_ message: String) {
#if DEBUG
        print("[ToolCalling] \(message)")
#endif
    }

    static func sanitizedSnippet(_ text: String, limit: Int = 180) -> String {
        let compact = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.count <= limit {
            return compact
        }
        return String(compact.prefix(limit)) + "..."
    }

    static func describe(_ decision: ToolDecision) -> String {
        switch decision {
        case .none:
            return "none"
        case .call(let request):
            return "call(tool=\(request.toolName), args=\(formatted(arguments: request.arguments)))"
        }
    }

    static func formatted(arguments: [String: String]) -> String {
        let pairs = arguments
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(sanitizedSnippet(value, limit: 120))"
            }
            .joined(separator: ", ")
        return "{\(pairs)}"
    }
}
