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
        completedSteps: [ToolTurnStep] = [],
        thinkingEnabled: Bool = false,
        using inferenceService: InferenceService
    ) async throws -> ToolPlannerOutcome {
        guard !tools.isEmpty else {
            ToolCallingDebugLog.line("planner", "skipped · no enabled tools")
            return .decision(.none)
        }

        let plannerMaxTokens = thinkingEnabled
            ? Constants.ToolCalling.plannerThinkingMaxTokens
            : Constants.ToolCalling.plannerMaxTokens

        ToolCallingDebugLog.line("planner", "start · thinking=\(thinkingEnabled ? "on" : "off")")
        ToolCallingDebugLog.line("tools", ToolCallingDebugLog.joinedNames(tools.map(\.name)))
        ToolCallingDebugLog.line("history", "\(history.count)")
        if !completedSteps.isEmpty {
            ToolCallingDebugLog.line("prior", ToolCallingDebugLog.joinedNames(completedSteps.map(\.call.toolName)))
        }
        ToolCallingDebugLog.line("message", ToolCallingDebugLog.sanitized(userMessage))

        let stream = await inferenceService.generate(
            prompt: planningPrompt(
                userMessage: userMessage,
                history: history,
                tools: tools,
                context: context,
                completedSteps: completedSteps
            ),
            thinkingEnabled: thinkingEnabled,
            history: [],
            systemPrompt: Constants.ToolCalling.plannerSystemPrompt,
            maxTokens: plannerMaxTokens,
            temperature: Constants.ToolCalling.plannerTemperature,
            topP: Constants.ToolCalling.plannerTopP,
            repetitionPenalty: 1.0,
            profileRunLabel: "Tool Planning",
            profilingContext: LLMProfilingRunContext(
                maxTokens: plannerMaxTokens,
                temperature: Constants.ToolCalling.plannerTemperature,
                topP: Constants.ToolCalling.plannerTopP,
                repetitionPenalty: 1.0,
                thinkingEnabled: thinkingEnabled
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
            ToolCallingDebugLog.line(
                "planner",
                ToolCallingDebugLog.describe(outcome)
            )
            ToolCallingDebugLog.line(
                "earlyStop",
                sawCompleteToolDecisionJSON ? "yes" : "no"
            )
            ToolCallingDebugLog.line("raw", ToolCallingDebugLog.sanitized(rawOutput, limit: 220))
            return outcome
        } catch is CancellationError {
            ToolCallingDebugLog.line("planner", "cancelled")
            throw CancellationError()
        } catch {
            ToolCallingDebugLog.line("planner", "failed · \(error.localizedDescription)")
            return .unusable
        }
    }

    private nonisolated func containsCompleteToolDecisionJSON(_ rawOutput: String) -> Bool {
        let rawOutput = Self.plannerTextByStrippingThinking(rawOutput)
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
            ToolCallingDebugLog.line("execute", "skipped · \(call.toolName) not registered")
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
            ToolCallingDebugLog.line("execute", "rejected · \(call.toolName)")
            ToolCallingDebugLog.line("status", failure.status.rawValue)
            ToolCallingDebugLog.line("reason", ToolCallingDebugLog.sanitized(failure.message))
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
            ToolCallingDebugLog.line("execute", "skipped · \(call.toolName) has no executor")
            return failureResult(
                toolName: call.toolName,
                status: .unavailable,
                message: "No executor is registered for this tool.",
                durationSeconds: 0
            )
        }

        do {
            ToolCallingDebugLog.line("execute", call.toolName)
            ToolCallingDebugLog.line("args", ToolCallingDebugLog.formatted(arguments: normalizedArguments))
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
            ToolCallingDebugLog.line(
                "result",
                "\(finalResult.status.rawValue) · \(String(format: "%.2fs", finalResult.durationSeconds)) · \(finalResult.sources.count) sources · \(finalResult.contextBlock.count) chars"
            )
            if let message = finalResult.message, !message.isEmpty {
                ToolCallingDebugLog.line("detail", ToolCallingDebugLog.sanitized(message))
            }
            return finalResult
        } catch is CancellationError {
            ToolCallingDebugLog.line("execute", "cancelled · \(call.toolName)")
            throw CancellationError()
        } catch ToolExecutionError.timedOut {
            ToolCallingDebugLog.line("execute", "timed out · \(call.toolName)")
            return failureResult(
                toolName: call.toolName,
                status: .timedOut,
                message: "Tool execution timed out.",
                durationSeconds: Date().timeIntervalSince(startTime)
            )
        } catch let failure as ToolExecutionFailure {
            ToolCallingDebugLog.line("execute", "failed · \(call.toolName)")
            ToolCallingDebugLog.line("status", failure.status.rawValue)
            ToolCallingDebugLog.line("reason", ToolCallingDebugLog.sanitized(failure.message))
            return failureResult(
                toolName: call.toolName,
                status: failure.status,
                message: failure.message,
                durationSeconds: Date().timeIntervalSince(startTime)
            )
        } catch {
            ToolCallingDebugLog.line("execute", "failed · \(call.toolName)")
            ToolCallingDebugLog.line("reason", error.localizedDescription)
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
        ToolCallingDebugLog.note(message)
    }

    static func sanitizedSnippet(_ text: String, limit: Int = 180) -> String {
        ToolCallingDebugLog.sanitized(text, limit: limit)
    }

    static func describe(_ decision: ToolDecision) -> String {
        ToolCallingDebugLog.describe(decision)
    }

    static func describe(_ outcome: ToolPlannerOutcome) -> String {
        ToolCallingDebugLog.describe(outcome)
    }

    static func formatted(arguments: [String: String]) -> String {
        ToolCallingDebugLog.formatted(arguments: arguments)
    }
}
