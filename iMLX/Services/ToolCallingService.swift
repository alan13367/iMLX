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
        documentLibraryService: DocumentLibraryService = DocumentLibraryService(),
        calendarBriefService: CalendarBriefService = CalendarBriefService(),
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
            ],
            metadata: ToolMetadata(
                requiresWebAccessToggle: true,
                requiresSinglePublicURL: true,
                executionClass: .network
            )
        )
        let ocrTool = ToolDefinition(
            name: "ocr_image_text",
            description: "Extracts visible text from images attached on the latest user message.",
            argumentSchema: [],
            metadata: ToolMetadata(
                requiresAttachedImages: true,
                executionClass: .local
            )
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
            ],
            metadata: ToolMetadata(
                requiresWebAccessToggle: true,
                executionClass: .network
            )
        )
        let documentTool = ToolDefinition(
            name: "document_synthesize",
            description: "Retrieves bounded excerpts from attached conversation documents for summaries, comparisons, extraction, and document Q&A.",
            argumentSchema: [
                ToolArgument(
                    name: "query",
                    type: "string",
                    required: true,
                    description: "The user's document-focused question or synthesis request."
                )
            ],
            metadata: ToolMetadata(
                requiresAttachedDocuments: true,
                executionClass: .local
            )
        )
        let calendarTool = ToolDefinition(
            name: "calendar_brief",
            description: "Reads local calendar events for a bounded date range and returns a private schedule brief.",
            argumentSchema: [
                ToolArgument(
                    name: "range",
                    type: "string",
                    required: true,
                    description: "One of: today, tomorrow, this_week, next_7_days."
                )
            ],
            metadata: ToolMetadata(executionClass: .local)
        )

        let readURLExecutor = ReadURLToolExecutor(webSearchService: webSearchService)
        let ocrExecutor = OCRImageTextToolExecutor(imageOCRService: imageOCRService)
        let webSearchExecutor = WebSearchToolExecutor(webSearchService: webSearchService)
        let documentExecutor = DocumentSynthesizeToolExecutor(documentLibraryService: documentLibraryService)
        let calendarExecutor = CalendarBriefToolExecutor(calendarBriefService: calendarBriefService)

        self.toolExecutionTimeoutSeconds = toolExecutionTimeoutSeconds
        self.registeredTools = [readURLTool, ocrTool, webSearchTool, documentTool, calendarTool]
        self.registeredExecutors = [
            readURLExecutor.toolName: readURLExecutor,
            ocrExecutor.toolName: ocrExecutor,
            webSearchExecutor.toolName: webSearchExecutor,
            documentExecutor.toolName: documentExecutor,
            calendarExecutor.toolName: calendarExecutor
        ]
    }

    func context(
        for userMessage: ChatMessage,
        attachedDocuments: [ConversationDocumentReference] = [],
        hasNewlyAttachedDocuments: Bool = false
    ) -> ToolInputContext {
        ToolInputContext(
            latestUserMessage: userMessage.content,
            attachedImages: userMessage.attachedImages ?? [],
            attachedDocuments: attachedDocuments,
            hasNewlyAttachedDocuments: hasNewlyAttachedDocuments,
            detectedPublicURLs: detectedPublicURLs(in: userMessage.content)
        )
    }

    func enabledTools(webSearchEnabled: Bool, context: ToolInputContext) -> [ToolDefinition] {
        registeredTools.filter { tool in
            isToolEnabled(tool, webSearchEnabled: webSearchEnabled, context: context)
        }
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
              case .success(let arguments) = validatedArguments(
                ["query": query],
                for: webSearchTool,
                context: nil
              ) else {
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
           case .success(let arguments) = validatedArguments(
                ["url": directURL.absoluteString],
                for: readURLTool,
                context: context
           ) {
            Self.debugLog("deterministic arbitration selected read_url for pasted URL")
            return .call(ToolCallRequest(toolName: readURLTool.name, arguments: arguments))
        }

        if let documentTool = toolsByName["document_synthesize"],
           shouldForceDocumentSynthesis(for: userMessage, context: context),
           case .success(let arguments) = validatedArguments(
                ["query": userMessage],
                for: documentTool,
                context: context
           ) {
            Self.debugLog("deterministic arbitration selected document_synthesize for attached document request")
            return .call(ToolCallRequest(toolName: documentTool.name, arguments: arguments))
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
           case .success(let arguments) = validatedArguments(
                [:],
                for: ocrTool,
                context: context
           ) {
            Self.debugLog("heuristic fallback selected ocr_image_text for text-focused image request")
            return .call(ToolCallRequest(toolName: ocrTool.name, arguments: arguments))
        }

        if let calendarTool = toolsByName["calendar_brief"],
           let range = heuristicCalendarRange(for: userMessage),
           case .success(let arguments) = validatedArguments(
                ["range": range.rawValue],
                for: calendarTool,
                context: context
           ) {
            Self.debugLog("heuristic fallback selected calendar_brief for schedule request")
            return .call(ToolCallRequest(toolName: calendarTool.name, arguments: arguments))
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
        guard let toolDefinition = registeredTools.first(where: { $0.name == call.toolName }) else {
            Self.debugLog("execution skipped: no tool definition registered for \(call.toolName)")
            return failureResult(
                toolName: call.toolName,
                status: .unavailable,
                message: "Tool is not registered.",
                durationSeconds: 0
            )
        }

        switch validatedArguments(
            Dictionary(uniqueKeysWithValues: call.arguments.map { ($0.key, $0.value as Any) }),
            for: toolDefinition,
            context: context
        ) {
        case .failure(let failure):
            Self.debugLog(
                "execution rejected: tool=\(call.toolName) status=\(failure.status.rawValue) " +
                "message=\(Self.sanitizedSnippet(failure.message))"
            )
            return failureResult(
                toolName: call.toolName,
                status: failure.status,
                message: failure.message,
                durationSeconds: Date().timeIntervalSince(startTime)
            )
        case .success:
            break
        }

        guard let executor = tools[call.toolName] else {
            Self.debugLog("execution skipped: no executor registered for \(call.toolName)")
            return failureResult(
                toolName: call.toolName,
                status: .unavailable,
                message: "No executor is registered for this tool.",
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
                status: result.status == .success && !clippedContext.isEmpty ? .success : .noContent,
                message: result.status == .success && !clippedContext.isEmpty
                    ? result.message
                    : (result.message ?? "Tool returned no usable context."),
                contextBlock: clippedContext,
                sources: result.status == .success && !clippedContext.isEmpty ? result.sources : [],
                durationSeconds: result.durationSeconds
            )
            Self.debugLog(
                "execution finished: tool=\(call.toolName) status=\(finalResult.status.rawValue) " +
                "sources=\(finalResult.sources.count) contextChars=\(finalResult.contextBlock.count) " +
                "message=\(Self.sanitizedSnippet(finalResult.message ?? "nil")) " +
                "duration=\(String(format: "%.2f", finalResult.durationSeconds))s"
            )
            return finalResult
        } catch is CancellationError {
            Self.debugLog("execution cancelled: tool=\(call.toolName)")
            throw CancellationError()
        } catch ToolExecutionError.timedOut {
            Self.debugLog("execution timed out: tool=\(call.toolName)")
            return failureResult(
                toolName: call.toolName,
                status: .timedOut,
                message: "Tool execution timed out.",
                durationSeconds: Date().timeIntervalSince(startTime)
            )
        } catch let failure as ToolExecutionFailure {
            Self.debugLog(
                "execution failed: tool=\(call.toolName) status=\(failure.status.rawValue) " +
                "message=\(Self.sanitizedSnippet(failure.message))"
            )
            return failureResult(
                toolName: call.toolName,
                status: failure.status,
                message: failure.message,
                durationSeconds: Date().timeIntervalSince(startTime)
            )
        } catch {
            Self.debugLog("execution failed: tool=\(call.toolName) error=\(String(describing: error))")
            return failureResult(
                toolName: call.toolName,
                status: .executionFailed,
                message: error.localizedDescription,
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
            guard case .success(let arguments) = validatedArguments(
                rawArguments,
                for: toolDefinition,
                context: context
            ) else {
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
    ) -> Result<[String: String], ToolExecutionFailure> {
        if toolDefinition.metadata.requiresAttachedImages,
           context?.attachedImages.isEmpty != false {
            return .failure(.invalidArguments("This tool requires at least one attached image on the latest user message."))
        }

        if toolDefinition.metadata.requiresAttachedDocuments,
           context?.attachedDocuments.isEmpty != false {
            return .failure(.invalidArguments("This tool requires at least one attached document in the current conversation."))
        }

        if toolDefinition.metadata.requiresSinglePublicURL,
           context?.singleDetectedPublicURL == nil,
           rawArguments["url"] == nil {
            return .failure(.invalidArguments("This tool requires exactly one public http or https URL in the latest user message."))
        }

        var validated: [String: String] = [:]

        for argument in toolDefinition.argumentSchema {
            let rawValue = rawArguments[argument.name]
            switch normalizedArgumentValue(argument, rawValue: rawValue, context: context) {
            case .success(let normalized):
                if let normalized, !normalized.isEmpty {
                    validated[argument.name] = normalized
                }
            case .failure(let failure):
                return .failure(failure)
            }
        }

        if toolDefinition.metadata.requiresSinglePublicURL,
           validated["url"]?.isEmpty != false,
           let fallbackURL = context?.singleDetectedPublicURL?.absoluteString {
            validated["url"] = fallbackURL
        }

        if toolDefinition.name == "read_url", validated["url"]?.isEmpty != false {
            return .failure(.invalidArguments("A readable public http or https URL is required for this tool."))
        }

        return .success(validated)
    }

    private nonisolated func normalizedRequest(
        from request: ToolCallRequest,
        context: ToolInputContext,
        toolsByName: [String: ToolDefinition]
    ) -> ToolCallRequest? {
        guard let toolDefinition = toolsByName[request.toolName] else {
            return nil
        }

        guard case .success(let arguments) = validatedArguments(
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

    private nonisolated func isToolEnabled(
        _ tool: ToolDefinition,
        webSearchEnabled: Bool,
        context: ToolInputContext
    ) -> Bool {
        if tool.metadata.requiresWebAccessToggle && !webSearchEnabled {
            return false
        }
        if tool.metadata.requiresAttachedImages && context.attachedImages.isEmpty {
            return false
        }
        if tool.metadata.requiresAttachedDocuments && context.attachedDocuments.isEmpty {
            return false
        }
        if tool.metadata.requiresSinglePublicURL && context.singleDetectedPublicURL == nil {
            return false
        }
        return true
    }

    private nonisolated func normalizedArgumentValue(
        _ argument: ToolArgument,
        rawValue: Any?,
        context: ToolInputContext?
    ) -> Result<String?, ToolExecutionFailure> {
        switch argument.name {
        case "query":
            guard let rawValue else {
                return argument.required
                    ? .failure(.invalidArguments("Argument `query` is required."))
                    : .success(nil)
            }
            guard let query = normalizedStringValue(from: rawValue) else {
                return .failure(.invalidArguments("Argument `query` must be a string."))
            }
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                return .failure(.invalidArguments("Argument `query` must not be empty."))
            }
            let clamped = String(trimmed.prefix(Constants.ToolCalling.maxQueryLength))
            guard !clamped.isEmpty else {
                return .failure(.invalidArguments("Argument `query` must not be empty."))
            }
            return .success(clamped)

        case "url":
            let candidate = normalizedStringValue(from: rawValue)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                ?? context?.singleDetectedPublicURL?.absoluteString
            guard let candidate, !candidate.isEmpty else {
                return argument.required
                    ? .failure(.invalidArguments("Argument `url` is required."))
                    : .success(nil)
            }
            guard let normalizedURL = normalizedPublicURL(from: candidate) else {
                return .failure(.invalidArguments("Argument `url` must be a public http or https URL."))
            }
            return .success(normalizedURL.absoluteString)

        case "range":
            guard let rawValue else {
                return argument.required
                    ? .failure(.invalidArguments("Argument `range` is required."))
                    : .success(nil)
            }
            guard let range = normalizedStringValue(from: rawValue)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                  CalendarBriefRange(rawValue: range) != nil else {
                return .failure(.invalidArguments("Argument `range` must be one of: today, tomorrow, this_week, next_7_days."))
            }
            return .success(range)

        default:
            return normalizedPrimitiveValue(for: argument, rawValue: rawValue)
        }
    }

    private nonisolated func normalizedPrimitiveValue(
        for argument: ToolArgument,
        rawValue: Any?
    ) -> Result<String?, ToolExecutionFailure> {
        guard let rawValue else {
            return argument.required
                ? .failure(.invalidArguments("Argument `\(argument.name)` is required."))
                : .success(nil)
        }

        switch argument.type {
        case "string":
            guard let value = normalizedStringValue(from: rawValue) else {
                return .failure(.invalidArguments("Argument `\(argument.name)` must be a string."))
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if argument.required && trimmed.isEmpty {
                return .failure(.invalidArguments("Argument `\(argument.name)` must not be empty."))
            }
            return .success(trimmed.isEmpty ? nil : trimmed)

        case "number":
            if let number = rawValue as? NSNumber {
                return .success(number.stringValue)
            }
            if let string = normalizedStringValue(from: rawValue)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               Double(string) != nil {
                return .success(string)
            }
            return .failure(.invalidArguments("Argument `\(argument.name)` must be a number."))

        case "boolean":
            if let value = rawValue as? Bool {
                return .success(value ? "true" : "false")
            }
            if let string = normalizedStringValue(from: rawValue)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
               ["true", "false"].contains(string) {
                return .success(string)
            }
            return .failure(.invalidArguments("Argument `\(argument.name)` must be a boolean."))

        default:
            guard let value = normalizedStringValue(from: rawValue) else {
                return .failure(.invalidArguments("Argument `\(argument.name)` is invalid."))
            }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if argument.required && trimmed.isEmpty {
                return .failure(.invalidArguments("Argument `\(argument.name)` must not be empty."))
            }
            return .success(trimmed.isEmpty ? nil : trimmed)
        }
    }

    private nonisolated func normalizedStringValue(from rawValue: Any?) -> String? {
        rawValue as? String
    }

    private nonisolated func normalizedPublicURL(from candidate: String) -> URL? {
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }

    private nonisolated func failureResult(
        toolName: String,
        status: ToolExecutionStatus,
        message: String?,
        durationSeconds: TimeInterval
    ) -> ToolExecutionResult {
        ToolExecutionResult(
            toolName: toolName,
            status: status,
            message: message,
            contextBlock: "",
            sources: [],
            durationSeconds: durationSeconds
        )
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
                      case .success(let arguments) = validatedArguments(
                        ["query": query],
                        for: toolDefinition,
                        context: context
                      ) else {
                    continue
                }
                Self.debugLog("planner recovered prose decision for \(toolName)")
                return .call(ToolCallRequest(toolName: toolName, arguments: arguments))

            case "read_url":
                guard let url = inferredReadURL(from: text, context: context),
                      case .success(let arguments) = validatedArguments(
                        ["url": url.absoluteString],
                        for: toolDefinition,
                        context: context
                      ) else {
                    continue
                }
                Self.debugLog("planner recovered prose decision for \(toolName)")
                return .call(ToolCallRequest(toolName: toolName, arguments: arguments))

            case "ocr_image_text":
                guard case .success(let arguments) = validatedArguments(
                    [:],
                    for: toolDefinition,
                    context: context
                ) else {
                    continue
                }
                Self.debugLog("planner recovered prose decision for \(toolName)")
                return .call(ToolCallRequest(toolName: toolName, arguments: arguments))

            case "document_synthesize":
                let query = userMessage ?? context.latestUserMessage
                guard case .success(let arguments) = validatedArguments(
                    ["query": query],
                    for: toolDefinition,
                    context: context
                ) else {
                    continue
                }
                Self.debugLog("planner recovered prose decision for \(toolName)")
                return .call(ToolCallRequest(toolName: toolName, arguments: arguments))

            case "calendar_brief":
                guard let range = heuristicCalendarRange(for: userMessage ?? context.latestUserMessage),
                      case .success(let arguments) = validatedArguments(
                        ["range": range.rawValue],
                        for: toolDefinition,
                        context: context
                      ) else {
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
            "what does this image say",
            "what does this screenshot say",
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

    private nonisolated func shouldForceDocumentSynthesis(for userMessage: String, context: ToolInputContext) -> Bool {
        guard !context.attachedDocuments.isEmpty else { return false }
        if context.hasNewlyAttachedDocuments {
            return true
        }

        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }

        let documentPhrases = [
            "this document",
            "the document",
            "this pdf",
            "the pdf",
            "this file",
            "the file",
            "attached document",
            "attached pdf",
            "attached file",
            "summarize this",
            "summarise this",
            "summarize the document",
            "summarise the document",
            "key points",
            "action items",
            "extract from",
            "compare the documents",
            "what does it say",
            "what does this say"
        ]

        if documentPhrases.contains(where: { normalized.contains($0) }) {
            return true
        }

        let tokens = Set(normalized.split(separator: " ").map(String.init))
        let documentTokens = Set(["document", "documents", "pdf", "file", "files", "attachment", "attachments", "csv", "report"])
        let actionTokens = Set(["summarize", "summarise", "compare", "extract", "find", "answer", "explain", "analyze", "analyse", "list"])

        return !tokens.intersection(documentTokens).isEmpty
            && !tokens.intersection(actionTokens).isEmpty
    }

    private nonisolated func heuristicCalendarRange(for userMessage: String) -> CalendarBriefRange? {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return nil }

        let calendarMarkers = [
            "calendar",
            "schedule",
            "agenda",
            "availability",
            "available",
            "busy",
            "free",
            "appointments",
            "meetings",
            "events",
            "conflicts",
            "what do i have",
            "what's on"
        ]
        guard calendarMarkers.contains(where: { normalized.contains($0) }) else {
            return nil
        }

        if normalized.contains("tomorrow") {
            return .tomorrow
        }
        if normalized.contains("this week") || normalized.contains("week") {
            return .thisWeek
        }
        if normalized.contains("next 7 days")
            || normalized.contains("next seven days")
            || normalized.contains("coming 7 days")
            || normalized.contains("upcoming") {
            return .next7Days
        }
        return .today
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
        let query = (arguments["query"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw ToolExecutionFailure.invalidArguments("A search query is required.")
        }

        let startTime = Date()
        let result: MessageGroundingResult
        do {
            result = try await webSearchService.retrieveContext(for: query)
        } catch {
            if error.isNetworkAvailabilityFailure {
                throw ToolExecutionFailure.networkUnavailable("Web search was unavailable.")
            }
            throw ToolExecutionFailure.executionFailed("Web search failed.")
        }

        guard !result.contextBlock.isEmpty else {
            throw ToolExecutionFailure.noContent("Web search did not return usable results.")
        }

        let duration = Date().timeIntervalSince(startTime)
        return ToolExecutionResult(
            toolName: toolName,
            status: .success,
            message: nil,
            contextBlock: result.contextBlock,
            sources: result.sources,
            durationSeconds: duration
        )
    }
}

private struct ReadURLToolExecutor: ToolExecutor {
    let toolName = "read_url"
    let webSearchService: WebSearchService

    func execute(arguments: [String: String], context: ToolInputContext) async throws -> ToolExecutionResult {
        let startTime = Date()
        let urlString = (arguments["url"] ?? context.singleDetectedPublicURL?.absoluteString ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = normalizedPublicURL(urlString) else {
            throw ToolExecutionFailure.invalidArguments("A readable public http or https URL is required.")
        }

        let result: MessageGroundingResult
        do {
            result = try await webSearchService.retrieveContext(forDirectURL: url, userQuery: context.latestUserMessage)
        } catch {
            if error.isNetworkAvailabilityFailure {
                throw ToolExecutionFailure.networkUnavailable("That link could not be read because network access was unavailable.")
            }
            throw ToolExecutionFailure.executionFailed("That link could not be read.")
        }

        guard !result.contextBlock.isEmpty else {
            throw ToolExecutionFailure.noContent("That link did not contain readable content.")
        }

        let duration = Date().timeIntervalSince(startTime)
        return ToolExecutionResult(
            toolName: toolName,
            status: .success,
            message: nil,
            contextBlock: result.contextBlock,
            sources: result.sources,
            durationSeconds: duration
        )
    }

    private func normalizedPublicURL(_ candidate: String) -> URL? {
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }
        return url
    }
}

private struct OCRImageTextToolExecutor: ToolExecutor {
    let toolName = "ocr_image_text"
    let imageOCRService: ImageOCRService

    func execute(arguments _: [String: String], context: ToolInputContext) async throws -> ToolExecutionResult {
        guard !context.attachedImages.isEmpty else {
            throw ToolExecutionFailure.invalidArguments("At least one attached image is required for OCR.")
        }

        let startTime = Date()
        let result: MessageGroundingResult
        do {
            result = try await imageOCRService.retrieveContext(from: context.attachedImages)
        } catch {
            throw ToolExecutionFailure.executionFailed("Image text extraction failed.")
        }

        guard !result.contextBlock.isEmpty else {
            throw ToolExecutionFailure.noContent("No readable text was found in the attached images.")
        }

        let duration = Date().timeIntervalSince(startTime)
        return ToolExecutionResult(
            toolName: toolName,
            status: .success,
            message: nil,
            contextBlock: result.contextBlock,
            sources: result.sources,
            durationSeconds: duration
        )
    }
}

private struct DocumentSynthesizeToolExecutor: ToolExecutor {
    let toolName = "document_synthesize"
    let documentLibraryService: DocumentLibraryService

    func execute(arguments: [String: String], context: ToolInputContext) async throws -> ToolExecutionResult {
        guard !context.attachedDocuments.isEmpty else {
            throw ToolExecutionFailure.invalidArguments("At least one attached document is required.")
        }

        let query = (arguments["query"] ?? context.latestUserMessage)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            throw ToolExecutionFailure.invalidArguments("A document query is required.")
        }

        let startTime = Date()
        let result = await documentLibraryService.retrieveContext(
            for: query,
            documents: context.attachedDocuments
        )

        guard !result.contextBlock.isEmpty else {
            throw ToolExecutionFailure.noContent("No relevant document excerpts were found.")
        }

        return ToolExecutionResult(
            toolName: toolName,
            status: .success,
            message: nil,
            contextBlock: result.contextBlock,
            sources: result.sources,
            durationSeconds: Date().timeIntervalSince(startTime)
        )
    }
}

private struct CalendarBriefToolExecutor: ToolExecutor {
    let toolName = "calendar_brief"
    let calendarBriefService: CalendarBriefService

    func execute(arguments: [String: String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        guard let rawRange = arguments["range"],
              let range = CalendarBriefRange(rawValue: rawRange) else {
            throw ToolExecutionFailure.invalidArguments("A supported calendar range is required.")
        }

        let startTime = Date()
        let result = try await calendarBriefService.retrieveContext(for: range)
        guard !result.contextBlock.isEmpty else {
            throw ToolExecutionFailure.noContent("No calendar events were found.")
        }

        return ToolExecutionResult(
            toolName: toolName,
            status: .success,
            message: nil,
            contextBlock: result.contextBlock,
            sources: result.sources,
            durationSeconds: Date().timeIntervalSince(startTime)
        )
    }
}

private extension Error {
    var isNetworkAvailabilityFailure: Bool {
        let urlError: URLError?
        if let error = self as? URLError {
            urlError = error
        } else {
            let nsError = self as NSError
            if nsError.domain == NSURLErrorDomain {
                urlError = URLError(.init(rawValue: nsError.code))
            } else {
                urlError = nil
            }
        }

        guard let urlError else { return false }
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotFindHost,
             .cannotConnectToHost,
             .dnsLookupFailed,
             .internationalRoamingOff,
             .callIsActive,
             .dataNotAllowed,
             .resourceUnavailable:
            return true
        default:
            return false
        }
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
