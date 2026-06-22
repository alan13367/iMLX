import Foundation

actor ToolCallingService {
    enum ToolExecutionError: Error {
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
        remindersService: RemindersService = RemindersService(),
        timerService: TimerService = TimerService(),
        contactsService: ContactsService = ContactsService(),
        currentDateTimeNow: @escaping @Sendable () -> Date = { Date() },
        currentDateTimeTimeZone: TimeZone = .current,
        toolExecutionTimeoutSeconds: TimeInterval = Constants.ToolCalling.toolExecutionTimeoutSeconds
    ) {
        let catalog = ToolCatalog.make(
            webSearchService: webSearchService,
            imageOCRService: imageOCRService,
            documentLibraryService: documentLibraryService,
            calendarBriefService: calendarBriefService,
            remindersService: remindersService,
            timerService: timerService,
            contactsService: contactsService,
            currentDateTimeNow: currentDateTimeNow,
            currentDateTimeTimeZone: currentDateTimeTimeZone
        )
        self.toolExecutionTimeoutSeconds = toolExecutionTimeoutSeconds
        self.registeredTools = catalog.definitions
        self.registeredExecutors = catalog.executors
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

    func plan(
        userMessage: String,
        history: [ChatMessage],
        tools: [ToolDefinition],
        context: ToolInputContext,
        using inferenceService: InferenceService
    ) async throws -> ToolPlannerOutcome {
        guard !tools.isEmpty else {
            Self.debugLog("planner skipped: no enabled tools")
            return .decision(.none)
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
            repetitionPenalty: 1.0,
            profileRunLabel: "Tool Planning",
            profilingContext: LLMProfilingRunContext(
                maxTokens: Constants.ToolCalling.plannerMaxTokens,
                temperature: Constants.ToolCalling.plannerTemperature,
                topP: Constants.ToolCalling.plannerTopP,
                repetitionPenalty: 1.0,
                thinkingEnabled: false
            )
        )

        var rawOutput = ""
        var sawCompleteToolDecisionJSON = false

        do {
            for try await token in stream {
                try Task.checkCancellation()
                rawOutput += token
                // Early stop: the planner is asked for ONE JSON object. As soon
                // as we see a balanced object containing a "tool" key we can
                // break out of the stream — the inference task is cancelled
                // through the AsyncThrowingStream `onTermination` hook in
                // InferenceService.generate, saving the rest of the maxTokens
                // budget. Particularly valuable on memory-pressured big models
                // where each unused planner token is 30–100 ms of GPU time.
                if !sawCompleteToolDecisionJSON,
                   containsCompleteToolDecisionJSON(rawOutput) {
                    sawCompleteToolDecisionJSON = true
                    break
                }
            }
            let outcome = parsePlannerOutcome(
                from: rawOutput,
                userMessage: userMessage,
                tools: tools,
                context: context
            )
            Self.debugLog(
                "planner output: raw=\(Self.sanitizedSnippet(rawOutput, limit: 280)) " +
                "earlyStop=\(sawCompleteToolDecisionJSON) outcome=\(Self.describe(outcome))"
            )
            return outcome
        } catch is CancellationError {
            Self.debugLog("planner cancelled")
            throw CancellationError()
        } catch {
            Self.debugLog("planner failed with error: \(String(describing: error))")
            return .unusable
        }
    }

    private nonisolated func containsCompleteToolDecisionJSON(_ rawOutput: String) -> Bool {
        // Cheap pre-reject: no closing brace yet → cannot have a complete object.
        guard rawOutput.contains("}") else { return false }

        for payload in balancedJSONFragments(in: rawOutput) {
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let dictionary = object as? [String: Any] else {
                continue
            }
            if dictionary["tool"] is String {
                return true
            }
        }
        return false
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

        let normalizedArguments: [String: String]
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
        case .success(let arguments):
            normalizedArguments = arguments
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
            Self.debugLog("execution start: tool=\(call.toolName) args=\(Self.formatted(arguments: normalizedArguments))")
            let result = try await withTimeout(seconds: toolExecutionTimeoutSeconds) {
                try await executor.execute(arguments: normalizedArguments, context: context)
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

}

extension ToolCallingService {
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

    static func describe(_ outcome: ToolPlannerOutcome) -> String {
        switch outcome {
        case .decision(let decision):
            return describe(decision)
        case .unusable:
            return "unusable"
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
