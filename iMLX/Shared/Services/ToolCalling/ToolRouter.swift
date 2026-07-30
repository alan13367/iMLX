import Foundation

extension ToolCallingService {
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

        ToolCallingDebugLog.line("fallback", "web_search · live-data")
        return .call(ToolCallRequest(toolName: "web_search", arguments: arguments))
    }

    nonisolated func resolvedDecision(
        plannerOutcome: ToolPlannerOutcome,
        userMessage: String,
        context: ToolInputContext,
        tools: [ToolDefinition],
        history: [ChatMessage] = []
    ) -> ToolDecision {
        let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })

        if let directURL = context.singleDetectedPublicURL,
           let readURLTool = toolsByName["read_url"],
           shouldForceReadURL(for: userMessage, context: context),
           case .success(let arguments) = validatedArguments(
                ["url": directURL.absoluteString],
                for: readURLTool,
                context: context
           ) {
            ToolCallingDebugLog.line("resolve", "read_url · pasted URL")
            return .call(ToolCallRequest(toolName: readURLTool.name, arguments: arguments))
        }

        if let documentTool = toolsByName["document_synthesize"],
           shouldForceDocumentSynthesis(for: userMessage, context: context),
           case .success(let arguments) = validatedArguments(
                ["query": userMessage],
                for: documentTool,
                context: context
           ) {
            ToolCallingDebugLog.line("resolve", "document_synthesize · attached docs")
            return .call(ToolCallRequest(toolName: documentTool.name, arguments: arguments))
        }

        switch plannerOutcome {
        case .decision(.call(let request)):
            guard let normalizedRequest = normalizedRequest(
                from: request,
                context: context,
                toolsByName: toolsByName
            ) else {
                break
            }
            return .call(normalizedRequest)

        case .decision(.none):
            if let contextualDecision = contextualCreateFollowUpDecision(
                userMessage: userMessage,
                history: history,
                context: context,
                toolsByName: toolsByName
            ) {
                return contextualDecision
            }
            return .none

        case .unusable:
            break
        }

        if let contextualDecision = contextualCreateFollowUpDecision(
            userMessage: userMessage,
            history: history,
            context: context,
            toolsByName: toolsByName
        ) {
            return contextualDecision
        }

        if let ocrTool = toolsByName["ocr_image_text"],
           shouldForceOCR(for: userMessage, context: context),
           case .success(let arguments) = validatedArguments(
                [:],
                for: ocrTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fallback", "ocr_image_text")
            return .call(ToolCallRequest(toolName: ocrTool.name, arguments: arguments))
        }

        if let timerCreateTool = toolsByName["timer_create"],
           let raw = heuristicTimerCreateRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: timerCreateTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fallback", "timer_create")
            return .call(ToolCallRequest(toolName: timerCreateTool.name, arguments: arguments))
        }

        if let calendarCreateTool = toolsByName["calendar_create"],
           let raw = heuristicCalendarCreateRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: calendarCreateTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fallback", "calendar_create")
            return .call(ToolCallRequest(toolName: calendarCreateTool.name, arguments: arguments))
        }

        if let remindersCreateTool = toolsByName["reminders_create"],
           let raw = heuristicRemindersCreateRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: remindersCreateTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fallback", "reminders_create")
            return .call(ToolCallRequest(toolName: remindersCreateTool.name, arguments: arguments))
        }

        if let contactsLookupTool = toolsByName["contacts_lookup"],
           let raw = heuristicContactsLookupRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: contactsLookupTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fallback", "contacts_lookup")
            return .call(ToolCallRequest(toolName: contactsLookupTool.name, arguments: arguments))
        }

        if let calendarTool = toolsByName["calendar_brief"],
           !isBriefRangeOnlyFollowUp(userMessage),
           let range = heuristicCalendarRange(for: userMessage),
           case .success(let arguments) = validatedArguments(
                ["range": range.rawValue],
                for: calendarTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fallback", "calendar_brief")
            return .call(ToolCallRequest(toolName: calendarTool.name, arguments: arguments))
        }

        if let dateTimeTool = toolsByName["current_datetime"],
           shouldForceCurrentDateTime(for: userMessage),
           case .success(let arguments) = validatedArguments([:], for: dateTimeTool, context: context) {
            ToolCallingDebugLog.line("fallback", "current_datetime")
            return .call(ToolCallRequest(toolName: dateTimeTool.name, arguments: arguments))
        }

        if let remindersBriefTool = toolsByName["reminders_brief"],
           !isBriefRangeOnlyFollowUp(userMessage),
           let range = heuristicReminderRange(for: userMessage),
           case .success(let arguments) = validatedArguments(
                ["range": range.rawValue],
                for: remindersBriefTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fallback", "reminders_brief")
            return .call(ToolCallRequest(toolName: remindersBriefTool.name, arguments: arguments))
        }

        if let fallbackDecision = heuristicFallbackDecision(userMessage: userMessage, tools: tools) {
            return fallbackDecision
        }

        if let contextualDecision = contextualFallbackDecision(
            userMessage: userMessage,
            history: history,
            context: context,
            toolsByName: toolsByName
        ) {
            return contextualDecision
        }

        return .none
    }

    /// Decides whether the LLM-backed planner needs to run this turn.
    ///
    /// Runs deterministic arbitration first (pasted URL, document/OCR/calendar/
    /// live-data heuristics) and short-circuits to a final `ToolDecision` when
    /// the answer is unambiguous. Returns `.deliberate` for any remaining turn
    /// that is not clearly tool-independent, so the planner can choose a tool
    /// when heuristics did not confidently match.
    ///
    /// This keeps short, simple questions ("hi", "what's 2+2") from paying for
    /// a full planner inference round-trip just to be told `.none`.
    nonisolated func preflightDecision(
        userMessage: String,
        context: ToolInputContext,
        tools: [ToolDefinition],
        history: [ChatMessage] = []
    ) -> ToolPreflight {
        guard !tools.isEmpty else {
            ToolCallingDebugLog.line("reason", "no enabled tools")
            return .skip(.none)
        }

        let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })

        // Multiple URLs cannot be handled safely by read_url v1. Do not let
        // another web tool arbitrarily choose one; normal generation can ask
        // the user which URL they want read.
        if context.detectedPublicURLs.count > 1 {
            ToolCallingDebugLog.line("reason", "multiple URLs · ask which to read")
            return .skip(.none)
        }

        // 1. Explicit request to inspect a pasted single public URL.
        if let directURL = context.singleDetectedPublicURL,
           let readURLTool = toolsByName["read_url"],
           shouldForceReadURL(for: userMessage, context: context),
           case .success(let arguments) = validatedArguments(
                ["url": directURL.absoluteString],
                for: readURLTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fast-path", "read_url · pasted URL")
            return .skip(.call(ToolCallRequest(toolName: readURLTool.name, arguments: arguments)))
        }

        // 2. An explicit request to search the web wins over incidental local
        // tool keywords such as "events", "reminders", or "contacts".
        if let webSearchTool = toolsByName["web_search"],
           shouldForceExplicitWebSearch(for: userMessage),
           let query = heuristicWebSearchQuery(for: userMessage),
           case .success(let arguments) = validatedArguments(
                ["query": query],
                for: webSearchTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fast-path", "web_search · explicit")
            return .skip(.call(ToolCallRequest(toolName: webSearchTool.name, arguments: arguments)))
        }

        // 3. Newly-attached documents or explicit document language.
        if let documentTool = toolsByName["document_synthesize"],
           shouldForceDocumentSynthesis(for: userMessage, context: context),
           case .success(let arguments) = validatedArguments(
                ["query": userMessage],
                for: documentTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fast-path", "document_synthesize")
            return .skip(.call(ToolCallRequest(toolName: documentTool.name, arguments: arguments)))
        }

        // 4. Text-focused image request with attached images.
        if let ocrTool = toolsByName["ocr_image_text"],
           shouldForceOCR(for: userMessage, context: context),
           case .success(let arguments) = validatedArguments(
                [:],
                for: ocrTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fast-path", "ocr_image_text")
            return .skip(.call(ToolCallRequest(toolName: ocrTool.name, arguments: arguments)))
        }

        // 5. Explicit timer create request.
        if let timerCreateTool = toolsByName["timer_create"],
           let raw = heuristicTimerCreateRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: timerCreateTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fast-path", "timer_create")
            return .skip(.call(ToolCallRequest(toolName: timerCreateTool.name, arguments: arguments)))
        }

        // 5a. Explicit calendar event create request when all required fields are parseable.
        if let calendarCreateTool = toolsByName["calendar_create"],
           let raw = heuristicCalendarCreateRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: calendarCreateTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fast-path", "calendar_create")
            return .skip(.call(ToolCallRequest(toolName: calendarCreateTool.name, arguments: arguments)))
        }

        // 5b. Explicit create-reminder request. This must run before calendar
        // reads so nouns such as "meeting" in a reminder title do not hijack
        // the turn.
        if let remindersCreateTool = toolsByName["reminders_create"],
           let raw = heuristicRemindersCreateRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: remindersCreateTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fast-path", "reminders_create")
            return .skip(.call(ToolCallRequest(toolName: remindersCreateTool.name, arguments: arguments)))
        }

        // 5c. Contact lookup request.
        if let contactsLookupTool = toolsByName["contacts_lookup"],
           let raw = heuristicContactsLookupRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: contactsLookupTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fast-path", "contacts_lookup")
            return .skip(.call(ToolCallRequest(toolName: contactsLookupTool.name, arguments: arguments)))
        }

        // 5d. Calendar-shaped request. If the user also asked for the device
        // clock, prefer current_datetime first so a multi-tool turn can answer
        // both parts instead of fast-pathing only the calendar brief.
        if let calendarTool = toolsByName["calendar_brief"],
           let range = heuristicCalendarRange(for: userMessage),
           case .success(let arguments) = validatedArguments(
                ["range": range.rawValue],
                for: calendarTool,
                context: context
           ) {
            if let dateTimeTool = toolsByName["current_datetime"],
               shouldForceCurrentDateTime(for: userMessage),
               case .success(let dateTimeArguments) = validatedArguments(
                    [:],
                    for: dateTimeTool,
                    context: context
               ) {
                ToolCallingDebugLog.line("preflight", "compound time+calendar → current_datetime first")
                return .skip(.call(ToolCallRequest(toolName: dateTimeTool.name, arguments: dateTimeArguments)))
            }
            ToolCallingDebugLog.line("fast-path", "calendar_brief · \(range.rawValue)")
            return .skip(.call(ToolCallRequest(toolName: calendarTool.name, arguments: arguments)))
        }

        // 5e. Device date/time from the system clock.
        if let dateTimeTool = toolsByName["current_datetime"],
           shouldForceCurrentDateTime(for: userMessage),
           case .success(let arguments) = validatedArguments(
                [:],
                for: dateTimeTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fast-path", "current_datetime")
            return .skip(.call(ToolCallRequest(toolName: dateTimeTool.name, arguments: arguments)))
        }

        // 5f. Reminders list / todo brief for all reminders or a bounded range.
        if let remindersBriefTool = toolsByName["reminders_brief"],
           let range = heuristicReminderRange(for: userMessage),
           case .success(let arguments) = validatedArguments(
                ["range": range.rawValue],
                for: remindersBriefTool,
                context: context
           ) {
            if let dateTimeTool = toolsByName["current_datetime"],
               shouldForceCurrentDateTime(for: userMessage),
               case .success(let dateTimeArguments) = validatedArguments(
                    [:],
                    for: dateTimeTool,
                    context: context
               ) {
                ToolCallingDebugLog.line("preflight", "compound time+reminders → current_datetime first")
                return .skip(.call(ToolCallRequest(toolName: dateTimeTool.name, arguments: dateTimeArguments)))
            }
            ToolCallingDebugLog.line("fast-path", "reminders_brief · \(range.rawValue)")
            return .skip(.call(ToolCallRequest(toolName: remindersBriefTool.name, arguments: arguments)))
        }

        // 5g. Range-only follow-up after a previous brief tool, e.g. "And for tomorrow?"
        if let followUpDecision = contextualBriefFollowUpDecision(
            userMessage: userMessage,
            history: history,
            context: context,
            toolsByName: toolsByName
        ) {
            return .skip(followUpDecision)
        }

        // 6. Strong live-data web_search phrases,
        //    but only when no attachments might reframe the request as
        //    document/image-grounded.
        if let webSearchTool = toolsByName["web_search"],
           context.attachedDocuments.isEmpty,
           context.attachedImages.isEmpty,
           shouldForceWebSearch(for: userMessage),
           let query = heuristicWebSearchQuery(for: userMessage),
           case .success(let arguments) = validatedArguments(
                ["query": query],
                for: webSearchTool,
                context: context
           ) {
            ToolCallingDebugLog.line("fast-path", "web_search · live-data")
            return .skip(.call(ToolCallRequest(toolName: webSearchTool.name, arguments: arguments)))
        }

        // 7. Quick reject only for turns that clearly do not need tools.
        //    Heuristics above are a confident fast path; everything else with
        //    enabled tools deliberates so the planner can decide.
        if !mightBenefitFromPlanner(
            userMessage: userMessage,
            context: context,
            toolsByName: toolsByName,
            history: history
        ) {
            ToolCallingDebugLog.line("reason", "tool-independent turn")
            return .skip(.none)
        }

        return .deliberate
    }

    nonisolated func mightBenefitFromPlanner(
        userMessage: String,
        context: ToolInputContext,
        toolsByName: [String: ToolDefinition],
        history: [ChatMessage]
    ) -> Bool {
        // Attached docs/images without a clear forcing phrase → planner can route.
        if !context.attachedDocuments.isEmpty,
           toolsByName["document_synthesize"] != nil {
            return true
        }
        if !context.attachedImages.isEmpty,
           toolsByName["ocr_image_text"] != nil {
            return true
        }
        // An ambiguous single-URL turn still benefits from planner context.
        if context.singleDetectedPublicURL != nil,
           toolsByName["read_url"] != nil {
            return true
        }
        if pendingToolClarificationPreviousUserMessage(
            for: userMessage,
            history: history,
            toolsByName: toolsByName
        ) != nil {
            return true
        }
        if let trace = contextualFollowUpToolTrace(for: userMessage, history: history),
           toolsByName[trace.toolName] != nil {
            return true
        }
        // Heuristics remain the confident fast path (handled before this), but
        // unmatched turns default to the planner unless they are clearly just
        // chat, math, or local creative writing.
        if isClearlyToolIndependentTurn(userMessage) {
            return false
        }
        return true
    }

    nonisolated func isClearlyToolIndependentTurn(_ userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return true }

        let exactConversationalTurns = [
            "hi",
            "hello",
            "hey",
            "thanks",
            "thank you",
            "ok",
            "okay",
            "how are you",
            "good morning",
            "good afternoon",
            "good evening"
        ]
        if exactConversationalTurns.contains(normalized) {
            return true
        }

        let compactOriginal = userMessage
            .lowercased()
            .replacingOccurrences(of: #"[\?!=]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if compactOriginal.range(
            of: #"^(?:what(?:'s|\s+is)?\s+)?-?\d+(?:\.\d+)?\s*[\+\-\*/]\s*-?\d+(?:\.\d+)?$"#,
            options: .regularExpression
        ) != nil {
            return true
        }

        let localCreationPhrases = [
            "write a ",
            "write me ",
            "can you write ",
            "could you write ",
            "draft a ",
            "draft me ",
            "compose a ",
            "brainstorm ",
            "rewrite this",
            "rephrase this",
            "proofread this",
            "fix the grammar",
            "translate this"
        ]
        if localCreationPhrases.contains(where: { normalized.hasPrefix($0) }) {
            return true
        }

        // Duration / wait follow-ups that refer to earlier chat facts ("therefore
        // how much time do i have to wait") should not open calendar/reminder tools.
        if looksLikeContextDurationFollowUp(normalized) {
            return true
        }

        // Ultra-short replies without tool vocabulary are almost never tool
        // requests ("Green", "Brush teeth"), so skip the planner cost.
        let tokens = normalized.split(separator: " ").map(String.init)
        if tokens.count <= 2,
           !tokens.contains(where: { tokenLooksToolRelated($0) }) {
            return true
        }

        return false
    }

    /// True for asks that compute an interval from prior conversation dates,
    /// not from the user's device calendar.
    nonisolated func looksLikeContextDurationFollowUp(_ normalizedMessage: String) -> Bool {
        let durationPhrases = [
            "how much time",
            "how much longer",
            "how long do i have",
            "how long until",
            "how long till",
            "how long to wait",
            "how long will i wait",
            "how long do i wait",
            "time do i have to wait",
            "time left until",
            "time left till",
            "days until",
            "days till",
            "weeks until",
            "weeks till"
        ]
        guard durationPhrases.contains(where: { normalizedMessage.contains($0) })
            || (normalizedMessage.contains("to wait")
                && (normalizedMessage.contains("how long")
                    || normalizedMessage.contains("how much")
                    || normalizedMessage.contains("therefore")
                    || normalizedMessage.contains("so then")
                    || normalizedMessage.hasPrefix("so "))) else {
            return false
        }

        let personalScheduleTokens = Set([
            "calendar", "schedule", "agenda", "appointment", "appointments",
            "meeting", "meetings", "event", "events", "reminder", "reminders",
            "todo", "todos", "task", "tasks", "timer", "alarm"
        ])
        let tokens = Set(normalizedMessage.split(separator: " ").map(String.init))
        return tokens.isDisjoint(with: personalScheduleTokens)
    }

    nonisolated func tokenLooksToolRelated(_ token: String) -> Bool {
        let exact = Set([
            "reminder", "reminders", "remind", "todo", "todos", "task", "tasks",
            "calendar", "event", "events", "meeting", "meetings",
            "appointment", "appointments", "schedule", "agenda",
            "timer", "alarm",
            "search", "google", "web", "online", "news", "weather", "forecast",
            "contact", "contacts", "phone", "email",
            "time", "date", "timezone", "clock",
            "document", "pdf", "ocr", "image", "photo", "screenshot",
            "url", "http", "https",
            "set", "create", "add", "make", "start", "put",
            "lookup", "find"
        ])
        if exact.contains(token) {
            return true
        }
        return looksLikeReminderNoun(token)
    }

    nonisolated func messageLooksWebSearchAdjacent(_ userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }

        let webHints = [
            "search ",
            "look up",
            "look it up",
            "find online",
            "online for",
            "google ",
            "any news",
            "recent news",
            "the latest",
            "right now",
            "today's",
            "as of today",
            "current price",
            "current weather",
            "live score",
            "live update",
            "do you know",
            "can you find",
            "information about",
            "information on",
            "how many",
            "how much does",
            "how much is",
            "who is",
            "who was",
            "what happened to",
            "why did",
            "is it true that",
            "true that",
            "real or",
            "difference between",
            "what's the",
            "what is the",
            "when is the next",
            "has there been",
            "is it still",
            "tell me about"
        ]
        return webHints.contains(where: { normalized.contains($0) })
    }

    nonisolated func shouldForceExplicitWebSearch(for userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }

        let explicitPhrases = [
            "web search",
            "search the web",
            "search online",
            "search internet",
            "search the internet",
            "find online",
            "look up online",
            "look it up online",
            "google ",
            "can you search the web",
            "can you search online",
            "please search the web",
            "please search online",
            "can you find online",
            "please find online"
        ]
        return explicitPhrases.contains(where: { normalized.contains($0) })
    }

    nonisolated func shouldForceReadURL(
        for userMessage: String,
        context: ToolInputContext
    ) -> Bool {
        guard context.singleDetectedPublicURL != nil else { return false }
        if shouldForceExplicitWebSearch(for: userMessage) {
            return false
        }

        let messageWithoutURL = userMessage
            .replacingOccurrences(
                of: #"(?i)https?://\S+"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        if messageWithoutURL.isEmpty {
            return true
        }

        let normalized = normalizeForHeuristicMatching(messageWithoutURL)
        let nonReadingActions = [
            "save this",
            "remember this",
            "bookmark this",
            "send this",
            "share this",
            "add this link"
        ]
        if nonReadingActions.contains(where: { normalized.contains($0) }) {
            return false
        }

        let directReadingPhrases = [
            "read this",
            "read the",
            "open this",
            "check this",
            "inspect this",
            "review this",
            "summarize this",
            "summarise this",
            "summarize the",
            "summarise the",
            "explain this",
            "analyze this",
            "analyse this",
            "what does this say",
            "what is on this",
            "what s on this",
            "what is this link",
            "what s this link",
            "is this link safe",
            "is this site safe"
        ]
        if directReadingPhrases.contains(where: { normalized.contains($0) }) {
            return true
        }

        let tokens = Set(normalized.split(separator: " ").map(String.init))
        let readingActions = Set(["read", "open", "check", "inspect", "review", "summarize", "summarise", "explain", "analyze", "analyse"])
        return !tokens.intersection(readingActions).isEmpty
    }

    nonisolated func messageLooksLikeFactualQuestion(_ userMessage: String) -> Bool {
        let trimmed = userMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if trimmed.contains("?") {
            return true
        }

        let lowercase = trimmed.lowercased()
        let factualQuestionWords = ["who ", "what ", "where ", "when ", "why ", "how "]
        if factualQuestionWords.contains(where: { lowercase.hasPrefix($0) }) {
            return true
        }

        return false
    }

    nonisolated func messageLooksDateTimeAdjacent(_ userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }

        let hints = [
            "timezone",
            "time zone",
            "what time",
            "what date",
            "what day",
            "current date",
            "current time"
        ]
        return hints.contains(where: { normalized.contains($0) })
    }

    nonisolated func messageLooksCalendarCreateAdjacent(_ userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }
        let createHints = ["create", "add", "schedule", "put"]
        let calendarHints = ["calendar", "event", "meeting", "appointment"]
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        return !tokens.intersection(createHints).isEmpty
            && (!tokens.intersection(calendarHints).isEmpty || normalized.contains("on my calendar"))
    }

    nonisolated func messageLooksReminderCreateAdjacent(_ userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }

        if normalized.contains("remind me") {
            return true
        }

        let tokens = Set(normalized.split(separator: " ").map(String.init))
        let createHints = Set(["set", "create", "add", "make"])
        let reminderHints = Set(["reminder", "reminders", "todo", "todos"])
        let hasCreateCue = !tokens.intersection(createHints).isEmpty
        let hasReminderNoun = !tokens.intersection(reminderHints).isEmpty
            || tokens.contains(where: { looksLikeReminderNoun($0) })
        return hasCreateCue && hasReminderNoun
    }

    /// Accepts common near-miss spellings of reminder nouns so mutation
    /// authorization and adjacency gates do not fail closed on typos.
    nonisolated func looksLikeReminderNoun(_ token: String) -> Bool {
        if token.hasPrefix("remind") {
            return true
        }
        let targets = ["reminder", "reminders"]
        for target in targets {
            guard abs(token.count - target.count) <= 2 else { continue }
            if editDistance(token, target) <= 2 {
                return true
            }
        }
        return false
    }

    nonisolated func editDistance(_ lhs: String, _ rhs: String) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if left.isEmpty { return right.count }
        if right.isEmpty { return left.count }

        var previous = Array(0...right.count)
        var current = Array(repeating: 0, count: right.count + 1)
        for i in 1...left.count {
            current[0] = i
            for j in 1...right.count {
                let cost = left[i - 1] == right[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
            }
            previous = current
        }
        return previous[right.count]
    }

    nonisolated func messageLooksTimerCreateAdjacent(_ userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }
        let createHints = ["set", "start", "create", "put", "add"]
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        return normalized.contains("timer")
            && !tokens.intersection(createHints).isEmpty
    }

    nonisolated func messageLooksContactsLookupAdjacent(_ userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }
        let hints = [
            "contact",
            "contacts",
            "address book",
            "phone number",
            "email address",
            "email for",
            "number for"
        ]
        return hints.contains(where: { normalized.contains($0) })
    }


}
