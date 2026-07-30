import Foundation

nonisolated struct ToolTurnPolicy: Equatable, Sendable {
    let maxToolCallsPerTurn: Int

    init(platformClass: HostMemoryProfile.PlatformClass) {
        switch platformClass {
        case .desktop:
            maxToolCallsPerTurn = Constants.ToolCalling.maxDesktopToolCallsPerTurn
        case .mobile:
            maxToolCallsPerTurn = Constants.ToolCalling.maxMobileToolCallsPerTurn
        }
    }

    func allowsAnotherCall(after completedCallCount: Int) -> Bool {
        completedCallCount < maxToolCallsPerTurn
    }

    func shouldStop(after tool: ToolDefinition) -> Bool {
        tool.metadata.mutatesUserData
    }
}

extension ToolCallingService {
    nonisolated func isMutationExplicitlyAuthorized(
        toolName: String,
        by originalUserMessage: String
    ) -> Bool {
        let normalized = normalizeForHeuristicMatching(originalUserMessage)
        guard !normalized.isEmpty,
              !looksLikeConceptualHowToRequest(normalized) else {
            return false
        }

        switch toolName {
        case "calendar_create":
            return messageLooksCalendarCreateAdjacent(originalUserMessage)
        case "reminders_create":
            return messageLooksReminderCreateAdjacent(originalUserMessage)
        case "timer_create":
            return messageLooksTimerCreateAdjacent(originalUserMessage)
        default:
            return false
        }
    }

    nonisolated func continuationTools(
        from tools: [ToolDefinition],
        originalUserMessage: String,
        completedSteps: [ToolTurnStep],
        authorizationHistory: [ChatMessage] = []
    ) -> [ToolDefinition] {
        let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        let alreadyMutated = completedSteps.contains { step in
            toolsByName[step.call.toolName]?.metadata.mutatesUserData == true
        }
        guard !alreadyMutated else { return [] }

        let pendingAuthorizationMessage = pendingToolClarificationPreviousUserMessage(
            for: originalUserMessage,
            history: authorizationHistory,
            toolsByName: toolsByName
        )
        return tools.filter { tool in
            !tool.metadata.mutatesUserData
                || isMutationExplicitlyAuthorized(toolName: tool.name, by: originalUserMessage)
                || pendingAuthorizationMessage.map {
                    isMutationExplicitlyAuthorized(toolName: tool.name, by: $0)
                } == true
        }
    }

    nonisolated func validatedTurnDecision(
        _ decision: ToolDecision,
        originalUserMessage: String,
        context: ToolInputContext,
        tools: [ToolDefinition],
        completedSteps: [ToolTurnStep],
        authorizationHistory: [ChatMessage] = []
    ) -> ToolDecision {
        guard case .call(let request) = decision else { return .none }
        let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        guard let tool = toolsByName[request.toolName],
              let normalizedRequest = normalizedRequest(
                from: request,
                context: context,
                toolsByName: toolsByName
              ) else {
            ToolCallingDebugLog.line("reject", "unavailable tool or invalid args")
            return .none
        }

        if completedSteps.contains(where: { $0.call == normalizedRequest }) {
            ToolCallingDebugLog.line("reject", "identical call already completed")
            return .none
        }

        if tool.metadata.mutatesUserData {
            let pendingAuthorizationMessage = pendingToolClarificationPreviousUserMessage(
                for: originalUserMessage,
                history: authorizationHistory,
                toolsByName: toolsByName
            )
            let mutationIsAuthorized = isMutationExplicitlyAuthorized(
                toolName: tool.name,
                by: originalUserMessage
            ) || pendingAuthorizationMessage.map {
                isMutationExplicitlyAuthorized(toolName: tool.name, by: $0)
            } == true
            guard mutationIsAuthorized else {
                ToolCallingDebugLog.line("reject", "mutation not explicitly authorized")
                return .none
            }
            let alreadyMutated = completedSteps.contains { step in
                toolsByName[step.call.toolName]?.metadata.mutatesUserData == true
            }
            guard !alreadyMutated else {
                ToolCallingDebugLog.line("reject", "mutation limit reached")
                return .none
            }
        }

        return .call(normalizedRequest)
    }

    nonisolated func resolvedContinuationDecision(
        plannerOutcome: ToolPlannerOutcome,
        originalUserMessage: String,
        context: ToolInputContext,
        tools: [ToolDefinition],
        completedSteps: [ToolTurnStep],
        authorizationHistory: [ChatMessage] = []
    ) -> ToolDecision {
        let plannedDecision: ToolDecision
        switch plannerOutcome {
        case .decision(let decision):
            plannedDecision = decision
        case .unusable:
            ToolCallingDebugLog.line("continue", "unusable planner output")
            plannedDecision = .none
        }

        let validated = validatedTurnDecision(
            plannedDecision,
            originalUserMessage: originalUserMessage,
            context: context,
            tools: tools,
            completedSteps: completedSteps,
            authorizationHistory: authorizationHistory
        )
        if validated != .none {
            return validated
        }

        if let fallback = pendingReadContinuationDecision(
            originalUserMessage: originalUserMessage,
            context: context,
            tools: tools,
            completedSteps: completedSteps
        ) {
            ToolCallingDebugLog.line("continue", "fallback · \(ToolCallingDebugLog.describe(fallback))")
            return fallback
        }
        return .none
    }

    /// When the planner ends a multi-tool turn early, recover an outstanding
    /// read that the original compound request still requires.
    nonisolated func pendingReadContinuationDecision(
        originalUserMessage: String,
        context: ToolInputContext,
        tools: [ToolDefinition],
        completedSteps: [ToolTurnStep]
    ) -> ToolDecision? {
        let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
        let completedNames = Set(completedSteps.map(\.call.toolName))

        if let dateTimeTool = toolsByName["current_datetime"],
           !completedNames.contains(dateTimeTool.name),
           (shouldForceCurrentDateTime(for: originalUserMessage)
                || messageNeedsDeviceDateAnchor(for: originalUserMessage)),
           case .success(let arguments) = validatedArguments(
                [:],
                for: dateTimeTool,
                context: context
           ) {
            return .call(ToolCallRequest(toolName: dateTimeTool.name, arguments: arguments))
        }

        if let calendarTool = toolsByName["calendar_brief"],
           let range = heuristicCalendarRange(for: originalUserMessage),
           !completedNames.contains(calendarTool.name),
           case .success(let arguments) = validatedArguments(
                ["range": range.rawValue],
                for: calendarTool,
                context: context
           ) {
            return .call(ToolCallRequest(toolName: calendarTool.name, arguments: arguments))
        }

        if let remindersTool = toolsByName["reminders_brief"],
           let range = heuristicReminderRange(for: originalUserMessage),
           !completedNames.contains(remindersTool.name),
           case .success(let arguments) = validatedArguments(
                ["range": range.rawValue],
                for: remindersTool,
                context: context
           ) {
            return .call(ToolCallRequest(toolName: remindersTool.name, arguments: arguments))
        }

        return nil
    }

    private nonisolated func looksLikeConceptualHowToRequest(_ normalizedMessage: String) -> Bool {
        let prefixes = [
            "how do i ",
            "how can i ",
            "how would i ",
            "how do you ",
            "explain how ",
            "tell me how "
        ]
        return prefixes.contains(where: { normalizedMessage.hasPrefix($0) })
    }
}
