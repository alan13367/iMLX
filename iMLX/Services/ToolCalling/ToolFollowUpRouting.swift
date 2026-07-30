import Foundation

extension ToolCallingService {
    nonisolated func pendingToolClarificationPreviousUserMessage(
        for userMessage: String,
        history: [ChatMessage],
        toolsByName: [String: ToolDefinition]
    ) -> String? {
        guard !normalizeForHeuristicMatching(userMessage).isEmpty,
              let assistantIndex = history.lastIndex(where: { $0.role == .assistant }),
              history[(assistantIndex + 1)...].allSatisfy({ $0.role == .system }),
              assistantLooksLikeToolClarification(history[assistantIndex].content),
              let previousUserMessage = history[..<assistantIndex]
                .last(where: { $0.role == .user })?
                .content else {
            return nil
        }

        if toolsByName["reminders_create"] != nil,
           messageLooksReminderCreateAdjacent(previousUserMessage) {
            return previousUserMessage
        }
        if toolsByName["calendar_create"] != nil,
           messageLooksCalendarCreateAdjacent(previousUserMessage) {
            return previousUserMessage
        }
        if toolsByName["timer_create"] != nil,
           messageLooksTimerCreateAdjacent(previousUserMessage) {
            return previousUserMessage
        }
        if toolsByName["contacts_lookup"] != nil,
           messageLooksContactsLookupAdjacent(previousUserMessage) {
            return previousUserMessage
        }
        if toolsByName["calendar_brief"] != nil,
           heuristicCalendarRange(for: previousUserMessage) != nil {
            return previousUserMessage
        }
        if toolsByName["reminders_brief"] != nil,
           heuristicReminderRange(for: previousUserMessage) != nil {
            return previousUserMessage
        }
        if toolsByName["web_search"] != nil,
           (messageLooksWebSearchAdjacent(previousUserMessage)
                || messageLooksLikeFactualQuestion(previousUserMessage)) {
            return previousUserMessage
        }
        return nil
    }

    nonisolated func assistantLooksLikeToolClarification(_ assistantMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(assistantMessage)
        guard !normalized.isEmpty else { return false }

        if assistantMessage.contains("?") {
            return true
        }

        let clarificationPhrases = [
            "please tell me",
            "please provide",
            "please specify",
            "please clarify",
            "i need the",
            "i still need",
            "what time",
            "which time",
            "what date",
            "which date",
            "how long",
            "which contact",
            "which one"
        ]
        return clarificationPhrases.contains(where: { normalized.contains($0) })
    }

    nonisolated func contextualCreateFollowUpDecision(
        userMessage: String,
        history: [ChatMessage],
        context: ToolInputContext,
        toolsByName: [String: ToolDefinition]
    ) -> ToolDecision? {
        guard let previousUserMessage = pendingToolClarificationPreviousUserMessage(
            for: userMessage,
            history: history,
            toolsByName: toolsByName
        ) else {
            return nil
        }

        if let remindersCreateTool = toolsByName["reminders_create"],
           let raw = pendingReminderCompletionRawArguments(
                previousUserMessage: previousUserMessage,
                userMessage: userMessage
           ),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: remindersCreateTool,
                context: context
           ) {
            ToolCallingDebugLog.line("recover", "reminders_create · pending clarification")
            return .call(
                ToolCallRequest(
                    toolName: remindersCreateTool.name,
                    arguments: arguments
                )
            )
        }

        return nil
    }

    nonisolated func pendingReminderCompletionRawArguments(
        previousUserMessage: String,
        userMessage: String
    ) -> [String: String]? {
        guard let time = standaloneTimeExpression(in: userMessage),
              let draft = reminderDraftRequiringTime(from: previousUserMessage) else {
            return nil
        }

        return [
            "title": draft.title,
            "due": "\(draft.day) at \(time)"
        ]
    }

    nonisolated func reminderDraftRequiringTime(
        from userMessage: String
    ) -> (title: String, day: String)? {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return nil }

        let dayPattern = #"(?:(?:next|this)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)|today|tomorrow"#
        let dayBeforeTitlePatterns = [
            #"\bremind me\s+(?:for|on)\s+("# + dayPattern + #")\s+to\s+(.+)$"#,
            #"\b(?:set|create|add|make)\s+(?:a\s+)?reminder\s+(?:for|on)\s+("# + dayPattern + #")\s+to\s+(.+)$"#
        ]
        for pattern in dayBeforeTitlePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(
                    in: normalized,
                    options: [],
                    range: NSRange(normalized.startIndex..., in: normalized)
                  ),
                  match.numberOfRanges > 2,
                  let dayRange = Range(match.range(at: 1), in: normalized),
                  let titleRange = Range(match.range(at: 2), in: normalized) else {
                continue
            }
            let day = String(normalized[dayRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let title = String(normalized[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !day.isEmpty, !title.isEmpty {
                return (title, day)
            }
        }

        let titleBeforeDayPatterns = [
            #"\bremind me to\s+(.+?)\s+(?:for|on)\s+("# + dayPattern + #")$"#,
            #"\bremind me to\s+(.+?)\s+("# + dayPattern + #")$"#,
            #"\b(?:set|create|add|make)\s+(?:a\s+)?reminder\s+to\s+(.+?)\s+(?:for|on)\s+("# + dayPattern + #")$"#
        ]
        for pattern in titleBeforeDayPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(
                    in: normalized,
                    options: [],
                    range: NSRange(normalized.startIndex..., in: normalized)
                  ),
                  match.numberOfRanges > 2,
                  let titleRange = Range(match.range(at: 1), in: normalized),
                  let dayRange = Range(match.range(at: 2), in: normalized) else {
                continue
            }
            let title = String(normalized[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            let day = String(normalized[dayRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !day.isEmpty, !title.isEmpty {
                return (title, day)
            }
        }

        return nil
    }

    nonisolated func standaloneTimeExpression(in userMessage: String) -> String? {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty,
              normalized.range(
                of: #"^(?:at\s+)?(?:\d{1,2}(?::[0-5]\d)?\s*(?:am|pm)|(?:[01]?\d|2[0-3]):[0-5]\d)$"#,
                options: .regularExpression
              ) != nil else {
            return nil
        }

        if normalized.hasPrefix("at ") {
            return String(normalized.dropFirst(3))
        }
        return normalized
    }

    nonisolated func contextualBriefFollowUpDecision(
        userMessage: String,
        history: [ChatMessage],
        context: ToolInputContext,
        toolsByName: [String: ToolDefinition]
    ) -> ToolDecision? {
        guard let range = briefFollowUpRange(for: userMessage),
              let previousTrace = latestSuccessfulToolTrace(in: history) else {
            return nil
        }

        switch previousTrace.toolName {
        case "reminders_brief":
            guard let remindersTool = toolsByName["reminders_brief"],
                  let remindersRange = RemindersRange(rawValue: range),
                  case .success(let arguments) = validatedArguments(
                    ["range": remindersRange.rawValue],
                    for: remindersTool,
                    context: context
                  ) else {
                return nil
            }
            ToolCallingDebugLog.line("fast-path", "reminders_brief follow-up · \(remindersRange.rawValue)")
            return .call(ToolCallRequest(toolName: remindersTool.name, arguments: arguments))

        case "calendar_brief":
            guard range != RemindersRange.all.rawValue,
                  range != RemindersRange.overdue.rawValue,
                  let calendarTool = toolsByName["calendar_brief"],
                  let calendarRange = CalendarBriefRange(rawValue: range),
                  case .success(let arguments) = validatedArguments(
                    ["range": calendarRange.rawValue],
                    for: calendarTool,
                    context: context
                  ) else {
                return nil
            }
            ToolCallingDebugLog.line("fast-path", "calendar_brief follow-up · \(calendarRange.rawValue)")
            return .call(ToolCallRequest(toolName: calendarTool.name, arguments: arguments))

        default:
            return nil
        }
    }

    nonisolated func contextualFollowUpToolTrace(
        for userMessage: String,
        history: [ChatMessage]
    ) -> ToolCallTrace? {
        guard let trace = latestSuccessfulToolTrace(in: history) else {
            return nil
        }

        let normalized = normalizeForHeuristicMatching(userMessage)
        let words = normalized.split(separator: " ")
        guard !words.isEmpty, words.count <= 16 else { return nil }

        let acknowledgements = [
            "thanks",
            "thank you",
            "ok",
            "okay",
            "got it",
            "perfect",
            "great"
        ]
        if acknowledgements.contains(normalized) {
            return nil
        }

        let commandStarts = [
            "write ",
            "draft ",
            "create ",
            "set ",
            "start ",
            "translate ",
            "rewrite ",
            "summarize ",
            "summarise "
        ]
        if commandStarts.contains(where: { normalized.hasPrefix($0) }) {
            return nil
        }

        let followUpStarts = [
            "and ",
            "also ",
            "what about",
            "how about",
            "does ",
            "do ",
            "is ",
            "are ",
            "was ",
            "were ",
            "why ",
            "when ",
            "where ",
            "which ",
            "who ",
            "what ",
            "how ",
            "any "
        ]
        if userMessage.contains("?")
            || followUpStarts.contains(where: { normalized.hasPrefix($0) }) {
            return trace
        }

        if ["web_search", "read_url", "contacts_lookup"].contains(trace.toolName),
           words.count <= 5 {
            return trace
        }

        return nil
    }

    nonisolated func contextualFallbackDecision(
        userMessage: String,
        history: [ChatMessage],
        context: ToolInputContext,
        toolsByName: [String: ToolDefinition]
    ) -> ToolDecision? {
        guard let trace = contextualFollowUpToolTrace(for: userMessage, history: history) else {
            return nil
        }

        switch trace.toolName {
        case "web_search", "read_url":
            guard let webSearchTool = toolsByName["web_search"],
                  let previousUserMessage = history.reversed().first(where: { $0.role == .user })?.content else {
                return nil
            }
            let combinedQuery = "\(previousUserMessage) Follow-up: \(userMessage)"
            guard let query = heuristicWebSearchQuery(for: combinedQuery),
                  case .success(let arguments) = validatedArguments(
                    ["query": query],
                    for: webSearchTool,
                    context: context
                  ) else {
                return nil
            }
            ToolCallingDebugLog.line("fallback", "web_search · follow-up")
            return .call(ToolCallRequest(toolName: webSearchTool.name, arguments: arguments))

        case "contacts_lookup":
            guard let contactsTool = toolsByName["contacts_lookup"],
                  let previousQuery = trace.displayInput,
                  messageLooksContactsLookupAdjacent(userMessage),
                  case .success(let arguments) = validatedArguments(
                    ["query": previousQuery],
                    for: contactsTool,
                    context: context
                  ) else {
                return nil
            }
            ToolCallingDebugLog.line("fallback", "contacts_lookup · follow-up")
            return .call(ToolCallRequest(toolName: contactsTool.name, arguments: arguments))

        default:
            return nil
        }
    }

    nonisolated func latestSuccessfulToolTrace(in history: [ChatMessage]) -> ToolCallTrace? {
        for message in history.reversed() {
            if let trace = message.toolTraces?.reversed().first(where: { $0.success }) {
                return trace
            }
        }
        return nil
    }

    nonisolated func briefFollowUpRange(for userMessage: String) -> String? {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return nil }

        let tokens = Set(normalized.split(separator: " ").map(String.init))
        let allowedTokens = Set([
            "and",
            "for",
            "what",
            "about",
            "any",
            "anything",
            "how",
            "bout",
            "the",
            "ones",
            "one",
            "on",
            "in",
            "my",
            "appointment",
            "appointments",
            "event",
            "events",
            "meeting",
            "meetings",
            "reminder",
            "reminders",
            "todo",
            "todos",
            "task",
            "tasks",
            "to",
            "do",
            "show",
            "list",
            "me",
            "them",
            "those",
            "all",
            "today",
            "tomorrow",
            "overdue",
            "this",
            "week",
            "next",
            "seven",
            "7",
            "days",
            "coming",
            "upcoming"
        ])
        guard tokens.isSubset(of: allowedTokens) else { return nil }

        if normalized.contains("overdue") {
            return RemindersRange.overdue.rawValue
        }
        if normalized.contains("tomorrow") {
            return RemindersRange.tomorrow.rawValue
        }
        if normalized.contains("today") {
            return RemindersRange.today.rawValue
        }
        if normalized.contains("this week") || tokens.contains("week") {
            return RemindersRange.thisWeek.rawValue
        }
        if normalized.contains("next 7 days")
            || normalized.contains("next seven days")
            || normalized.contains("coming 7 days")
            || normalized.contains("upcoming") {
            return RemindersRange.next7Days.rawValue
        }
        if tokens.contains("all") {
            return RemindersRange.all.rawValue
        }
        return nil
    }

    nonisolated func isBriefRangeOnlyFollowUp(_ userMessage: String) -> Bool {
        guard briefFollowUpRange(for: userMessage) != nil else {
            return false
        }

        let normalized = normalizeForHeuristicMatching(userMessage)
        let followUpPrefixes = [
            "and ",
            "what about",
            "how about",
            "for "
        ]
        if followUpPrefixes.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }

        let standaloneRanges: Set<String> = [
            "today",
            "tomorrow",
            "overdue",
            "this week",
            "next week",
            "next seven days",
            "next 7 days",
            "upcoming"
        ]
        return standaloneRanges.contains(normalized)
    }
}
