import Foundation

protocol ToolExecutor: Sendable {
    var toolName: String { get }
    func execute(arguments: [String: String], context: ToolInputContext) async throws -> ToolExecutionResult
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
        imageOCRService: ImageOCRService = ImageOCRService(),
        toolExecutionTimeoutSeconds: TimeInterval = Constants.ToolCalling.toolExecutionTimeoutSeconds
    ) {
        let readURLTool = ToolDefinition(
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
        let ocrTool = ToolDefinition(
            name: "ocr_image_text",
            description: "Extracts visible text from images attached on the latest user message.",
            argumentSchema: []
        )
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

        let readURLExecutor = ReadURLToolExecutor(webSearchService: webSearchService)
        let ocrExecutor = OCRImageTextToolExecutor(imageOCRService: imageOCRService)
        let webSearchExecutor = WebSearchToolExecutor(webSearchService: webSearchService)

        self.toolExecutionTimeoutSeconds = toolExecutionTimeoutSeconds
        self.registeredTools = [readURLTool, ocrTool, webSearchTool]
        self.registeredExecutors = [
            readURLExecutor.toolName: readURLExecutor,
            ocrExecutor.toolName: ocrExecutor,
            webSearchExecutor.toolName: webSearchExecutor
        ]
    }

    func context(for userMessage: ChatMessage) -> ToolInputContext {
        ToolInputContext(
            latestUserMessage: userMessage.content,
            attachedImages: userMessage.attachedImages ?? [],
            detectedPublicURLs: detectedPublicURLs(in: userMessage.content)
        )
    }

    func enabledTools(webSearchEnabled: Bool, context: ToolInputContext) -> [ToolDefinition] {
        var enabled: [ToolDefinition] = []

        if webSearchEnabled,
           context.singleDetectedPublicURL != nil,
           let readURLTool = registeredTools.first(where: { $0.name == "read_url" }) {
            enabled.append(readURLTool)
        }

        if !context.attachedImages.isEmpty,
           let ocrTool = registeredTools.first(where: { $0.name == "ocr_image_text" }) {
            enabled.append(ocrTool)
        }

        if webSearchEnabled,
           let webSearchTool = registeredTools.first(where: { $0.name == "web_search" }) {
            enabled.append(webSearchTool)
        }

        return enabled
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
              let arguments = validatedArguments(["query": query], for: webSearchTool, context: nil) else {
            return nil
        }

        Self.debugLog("heuristic fallback selected web_search for obvious live-data request")
        return .call(ToolCallRequest(toolName: "web_search", arguments: arguments))
    }

    nonisolated func resolvedDecision(
        plannedDecision: ToolDecision,
        userMessage: String,
        context: ToolInputContext,
        tools: [ToolDefinition],
        preferThinkingFallback: Bool
    ) -> ToolDecision {
        let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })

        if let directURL = context.singleDetectedPublicURL,
           let readURLTool = toolsByName["read_url"],
           let arguments = validatedArguments(
                ["url": directURL.absoluteString],
                for: readURLTool,
                context: context
           ) {
            Self.debugLog("deterministic arbitration selected read_url for pasted URL")
            return .call(ToolCallRequest(toolName: readURLTool.name, arguments: arguments))
        }

        switch plannedDecision {
        case .call(let request):
            guard let normalizedRequest = normalizedRequest(
                from: request,
                context: context,
                toolsByName: toolsByName
            ) else {
                break
            }
            return .call(normalizedRequest)

        case .none:
            break
        }

        if let ocrTool = toolsByName["ocr_image_text"],
           shouldForceOCR(for: userMessage, context: context),
           let arguments = validatedArguments([:], for: ocrTool, context: context) {
            Self.debugLog("heuristic fallback selected ocr_image_text for text-focused image request")
            return .call(ToolCallRequest(toolName: ocrTool.name, arguments: arguments))
        }

        if preferThinkingFallback,
           let fallbackDecision = heuristicFallbackDecision(userMessage: userMessage, tools: tools) {
            return fallbackDecision
        }

        return .none
    }

    func plan(
        userMessage: String,
        history: [ChatMessage],
        tools: [ToolDefinition],
        context: ToolInputContext,
        using inferenceService: InferenceService
    ) async throws -> ToolDecision {
        guard !tools.isEmpty else {
            Self.debugLog("planner skipped: no enabled tools")
            return .none
        }

        Self.debugLog(
            "planner start: tools=\(tools.map(\.name).joined(separator: ",")) " +
            "historyCount=\(history.count) images=\(context.attachedImages.count) " +
            "urls=\(context.detectedPublicURLs.count) userMessage=\(Self.sanitizedSnippet(userMessage))"
        )

        let stream = await inferenceService.generate(
            prompt: planningPrompt(userMessage: userMessage, history: history, tools: tools, context: context),
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
            let decision = parsePlannerDecision(
                from: rawOutput,
                userMessage: userMessage,
                tools: tools,
                context: context
            )
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
        tools: [String: any ToolExecutor],
        context: ToolInputContext
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
                try await executor.execute(arguments: call.arguments, context: context)
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
        tools: [ToolDefinition],
        context: ToolInputContext
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
            guard let arguments = validatedArguments(rawArguments, for: toolDefinition, context: context) else {
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
            context: context,
            toolsByName: toolsByName
        ) {
            return fallbackDecision
        }

        return .none
    }

    nonisolated func validatedArguments(
        _ rawArguments: [String: Any],
        for toolDefinition: ToolDefinition,
        context: ToolInputContext?
    ) -> [String: String]? {
        var validated: [String: String] = [:]

        for argument in toolDefinition.argumentSchema {
            let rawValue = rawArguments[argument.name]
            let stringValue = stringValue(from: rawValue)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            switch argument.name {
            case "query":
                let candidateValue = stringValue ?? ""
                if argument.required && candidateValue.isEmpty {
                    return nil
                }
                guard !candidateValue.isEmpty else { continue }
                let clamped = String(candidateValue.prefix(Constants.ToolCalling.maxQueryLength))
                guard !clamped.isEmpty else { return nil }
                validated[argument.name] = clamped

            case "url":
                let resolvedURL = stringValue
                    ?? context?.singleDetectedPublicURL?.absoluteString
                if argument.required && (resolvedURL?.isEmpty != false) {
                    return nil
                }
                guard let resolvedURL, !resolvedURL.isEmpty,
                      let url = URL(string: resolvedURL),
                      let scheme = url.scheme?.lowercased(),
                      ["http", "https"].contains(scheme),
                      url.host != nil else {
                    continue
                }
                validated[argument.name] = url.absoluteString

            default:
                if argument.required && (stringValue?.isEmpty != false) {
                    return nil
                }
                guard let stringValue, !stringValue.isEmpty else { continue }
                validated[argument.name] = stringValue
            }
        }

        if toolDefinition.name == "read_url", validated["url"]?.isEmpty != false {
            return nil
        }

        return validated
    }

    private nonisolated func normalizedRequest(
        from request: ToolCallRequest,
        context: ToolInputContext,
        toolsByName: [String: ToolDefinition]
    ) -> ToolCallRequest? {
        guard let toolDefinition = toolsByName[request.toolName],
              let arguments = validatedArguments(
                Dictionary(uniqueKeysWithValues: request.arguments.map { ($0.key, $0.value as Any) }),
                for: toolDefinition,
                context: context
              ) else {
            return nil
        }

        return ToolCallRequest(toolName: request.toolName, arguments: arguments)
    }

    private nonisolated func planningPrompt(
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
                return "\(message.role.rawValue): \(boundedContent)"
            }
            .joined(separator: "\n")

        let currentTurnContext = [
            "- Attached image count: \(context.attachedImages.count)",
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
        context: ToolInputContext,
        toolsByName: [String: ToolDefinition]
    ) -> ToolDecision? {
        let lowercasedText = text.lowercased()

        for (toolName, toolDefinition) in toolsByName {
            guard proseSuggestsUsingTool(named: toolName, in: lowercasedText) else { continue }

            switch toolName {
            case "web_search":
                guard let query = inferredWebSearchQuery(from: text, userMessage: userMessage),
                      let arguments = validatedArguments(["query": query], for: toolDefinition, context: context) else {
                    continue
                }
                Self.debugLog("planner recovered prose decision for \(toolName)")
                return .call(ToolCallRequest(toolName: toolName, arguments: arguments))

            case "read_url":
                guard let url = inferredReadURL(from: text, context: context),
                      let arguments = validatedArguments(["url": url.absoluteString], for: toolDefinition, context: context) else {
                    continue
                }
                Self.debugLog("planner recovered prose decision for \(toolName)")
                return .call(ToolCallRequest(toolName: toolName, arguments: arguments))

            case "ocr_image_text":
                guard let arguments = validatedArguments([:], for: toolDefinition, context: context) else {
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

    private nonisolated func inferredReadURL(from text: String, context: ToolInputContext) -> URL? {
        if let explicitURLString = firstRegexCapture(
            pattern: #"(?i)\burl\s*[:=]\s*(https?://\S+)"#,
            in: text
        ),
           let explicitURL = URL(string: sanitizeRecoveredQuery(explicitURLString)),
           let scheme = explicitURL.scheme?.lowercased(),
           ["http", "https"].contains(scheme),
           explicitURL.host != nil {
            return explicitURL
        }

        return context.singleDetectedPublicURL
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

    private nonisolated func shouldForceOCR(for userMessage: String, context: ToolInputContext) -> Bool {
        guard !context.attachedImages.isEmpty else { return false }

        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }

        let textFocusedPhrases = [
            "ocr",
            "extract text",
            "read this image",
            "read the image",
            "read this screenshot",
            "read the screenshot",
            "what does this say",
            "what does the image say",
            "what does the screenshot say",
            "copy the text",
            "text in this image",
            "text in this screenshot",
            "translate this image",
            "translate this screenshot",
            "summarize the text",
            "receipt",
            "menu",
            "scan"
        ]

        if textFocusedPhrases.contains(where: { normalized.contains($0) }) {
            return true
        }

        let tokens = Set(normalized.split(separator: " ").map(String.init))
        let actionTokens = Set(["read", "extract", "copy", "translate", "scan", "summarize"])
        let textTokens = Set(["text", "words", "receipt", "menu", "screenshot", "image", "photo"])
        let containsSayPattern = normalized.contains("what does this say")
            || normalized.contains("what does it say")

        return containsSayPattern
            || (!tokens.intersection(actionTokens).isEmpty && !tokens.intersection(textTokens).isEmpty)
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
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s:/._-]"#, with: " ", options: .regularExpression)
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

    private nonisolated func detectedPublicURLs(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var urls: [URL] = []
        var seen = Set<String>()

        for match in detector.matches(in: text, options: [], range: range) {
            guard let url = match.url,
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https"].contains(scheme),
                  url.host != nil else {
                continue
            }

            let absoluteString = url.absoluteString
            guard seen.insert(absoluteString).inserted else { continue }
            urls.append(url)
        }

        return urls
    }
}

private struct WebSearchToolExecutor: ToolExecutor {
    let toolName = "web_search"
    let webSearchService: WebSearchService

    func execute(arguments: [String: String], context _: ToolInputContext) async throws -> ToolExecutionResult {
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

private struct ReadURLToolExecutor: ToolExecutor {
    let toolName = "read_url"
    let webSearchService: WebSearchService

    func execute(arguments: [String: String], context: ToolInputContext) async throws -> ToolExecutionResult {
        let startTime = Date()
        let urlString = arguments["url"] ?? context.singleDetectedPublicURL?.absoluteString ?? ""
        guard let url = URL(string: urlString) else {
            return ToolExecutionResult(
                toolName: toolName,
                contextBlock: "",
                sources: [],
                success: false,
                durationSeconds: 0
            )
        }
        let result = try await webSearchService.retrieveContext(forDirectURL: url, userQuery: context.latestUserMessage)
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

private struct OCRImageTextToolExecutor: ToolExecutor {
    let toolName = "ocr_image_text"
    let imageOCRService: ImageOCRService

    func execute(arguments _: [String: String], context: ToolInputContext) async throws -> ToolExecutionResult {
        let startTime = Date()
        let result = try await imageOCRService.retrieveContext(from: context.attachedImages)
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
