import Foundation

extension ToolCallingService {
    nonisolated func shouldForceWebSearch(for userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }

        let tokens = Set(normalized.split(separator: " ").map(String.init))
        let recencyMarkers = Set([
            "latest", "current", "today", "tomorrow", "tonight", "now",
            "live", "recent", "recently", "upcoming"
        ])
        let hasRecency = !tokens.intersection(recencyMarkers).isEmpty

        let newsMarkers = Set(["news", "headline", "headlines", "breaking"])
        if !tokens.intersection(newsMarkers).isEmpty,
           hasRecency
            || normalized.contains("news about")
            || normalized.contains("news on")
            || normalized.contains("what happened") {
            return true
        }

        let weatherMarkers = Set([
            "weather", "forecast", "temperature", "temperatures",
            "rain", "raining", "snow", "storm", "storms"
        ])
        if !tokens.intersection(weatherMarkers).isEmpty {
            if hasRecency {
                return true
            }
            let asksForConditions = normalized.contains("weather in")
                || normalized.contains("weather for")
                || normalized.contains("forecast in")
                || normalized.contains("forecast for")
                || normalized.contains("temperature in")
                || normalized.contains("temperature for")
            if asksForConditions {
                return true
            }
            let conceptualWeatherMarkers = Set([
                "pattern", "patterns", "climate", "science", "definition",
                "meaning", "works", "work", "causes"
            ])
            if tokens.count <= 6,
               tokens.count > 1,
               tokens.intersection(conceptualWeatherMarkers).isEmpty {
                return true
            }
        }

        let marketMarkers = Set([
            "price", "prices", "stock", "stocks", "share", "shares",
            "rate", "rates", "market", "markets", "exchange"
        ])
        let conceptualMarketQuestion = [
            "why do ",
            "why does ",
            "how do ",
            "how does ",
            "what causes ",
            "explain how "
        ].contains(where: { normalized.hasPrefix($0) })
        if !conceptualMarketQuestion,
           !tokens.intersection(marketMarkers).isEmpty,
           hasRecency
            || normalized.contains("price of")
            || normalized.contains("share price")
            || normalized.contains("exchange rate")
            || normalized.contains("how much is")
            || (tokens.count <= 6
                && !tokens.intersection(Set(["price", "prices", "rate", "rates", "stock", "stocks", "share", "shares"])).isEmpty) {
            return true
        }

        let sportsMarkers = Set([
            "score", "scores", "match", "matches", "game", "games",
            "standings", "ranking", "rankings", "fixture", "fixtures"
        ])
        if !tokens.intersection(sportsMarkers).isEmpty,
           hasRecency
            || normalized.contains("next match")
            || normalized.contains("next game")
            || normalized.contains("live score")
            || normalized.contains("standings") {
            return true
        }

        let alertMarkers = Set(["warning", "warnings", "alert", "alerts", "advisory", "advisories"])
        if hasRecency, !tokens.intersection(alertMarkers).isEmpty {
            return true
        }

        let transportMarkers = Set(["flight", "flights", "train", "trains", "traffic", "delay", "delays", "status"])
        if hasRecency, !tokens.intersection(transportMarkers).isEmpty {
            return true
        }

        return false
    }

    nonisolated func shouldForceOCR(for userMessage: String, context: ToolInputContext) -> Bool {
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

    nonisolated func shouldForceDocumentSynthesis(for userMessage: String, context: ToolInputContext) -> Bool {
        guard !context.attachedDocuments.isEmpty else { return false }

        let normalized = normalizeForHeuristicMatching(userMessage)
        if normalized.isEmpty {
            return context.hasNewlyAttachedDocuments
        }

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

    nonisolated func heuristicCalendarRange(for userMessage: String) -> CalendarBriefRange? {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return nil }

        let strongCalendarPhrases = [
            "my calendar",
            "my schedule",
            "my agenda",
            "my availability",
            "my appointment",
            "my appointments",
            "my meeting",
            "my meetings",
            "my event",
            "my events",
            "what do i have",
            "what s on",
            // Keep these specific: bare "do i have" matches duration follow-ups
            // such as "how much time do i have to wait".
            "do i have anything",
            "do i have any",
            "do i have a meeting",
            "do i have meetings",
            "do i have an appointment",
            "do i have appointments",
            "do i have an event",
            "do i have events",
            "do i have plans",
            "do i have something",
            "am i free",
            "am i busy",
            "am i available",
            "any upcoming appointment",
            "any upcoming meeting",
            "any upcoming event"
        ]
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        let calendarNouns = Set([
            "calendar", "schedule", "agenda", "availability", "appointment",
            "appointments", "meeting", "meetings", "event", "events"
        ])
        let readCues = Set(["show", "list", "check", "see", "have", "any", "upcoming"])
        let statusCues = Set(["available", "availability", "busy", "free", "conflict", "conflicts"])
        let temporalCues = Set(["today", "tomorrow", "week", "upcoming"])
        let hasStrongPhrase = strongCalendarPhrases.contains(where: { normalized.contains($0) })
        let hasReadShapedNounRequest = !tokens.intersection(calendarNouns).isEmpty
            && !tokens.intersection(readCues).isEmpty
        let hasAvailabilityRequest = !tokens.intersection(statusCues).isEmpty
            && (tokens.contains("i") || tokens.contains("my"))
        let hasTerseTemporalRequest = tokens.count <= 4
            && !tokens.intersection(Set(["calendar", "agenda"])).isEmpty
            && !tokens.intersection(temporalCues).isEmpty
        guard hasStrongPhrase
            || hasReadShapedNounRequest
            || hasAvailabilityRequest
            || hasTerseTemporalRequest else {
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

    nonisolated func heuristicCalendarCreateRawArguments(for userMessage: String) -> [String: String]? {
        let compact = userMessage
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizeForHeuristicMatching(compact)
        let reminderPrefixes = [
            "remind me to ",
            "set a reminder to ",
            "add a reminder to ",
            "create a reminder to "
        ]
        guard !reminderPrefixes.contains(where: { normalized.contains($0) }) else {
            return nil
        }
        guard messageLooksCalendarCreateAdjacent(normalized) else { return nil }

        guard let weekdayWithParticipantRegex = try? NSRegularExpression(
            pattern: #"(?i)\b(?:create|add|schedule|put)\b(?:\s+(?:a|an))?\s+(?:calendar\s+)?(event|meeting|appointment)\s+for\s+((?:(?:next|this)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday))\s+with\s+(.+?)\s+at\s+(\d{1,2}(?::\d{2})?\s*(?:am|pm)?)$"#
        ) else {
            return nil
        }
        if let match = weekdayWithParticipantRegex.firstMatch(
            in: compact,
            options: [],
            range: NSRange(compact.startIndex..., in: compact)
        ),
           match.numberOfRanges == 5,
           let kindRange = Range(match.range(at: 1), in: compact),
           let weekdayRange = Range(match.range(at: 2), in: compact),
           let participantRange = Range(match.range(at: 3), in: compact),
           let timeRange = Range(match.range(at: 4), in: compact) {
            let kind = sanitizeRecoveredQuery(String(compact[kindRange])).capitalized
            let weekday = sanitizeRecoveredQuery(String(compact[weekdayRange]))
            let participant = sanitizeRecoveredQuery(String(compact[participantRange]))
            let time = sanitizeRecoveredQuery(String(compact[timeRange]))
            guard !kind.isEmpty, !weekday.isEmpty, !participant.isEmpty, !time.isEmpty else {
                return nil
            }
            return [
                "title": "\(kind) with \(participant)",
                "start": "\(weekday) at \(time)",
                "end_or_duration": "1 hour"
            ]
        }

        let meetingPatterns = [
            #"(?i)\b(?:create|add|schedule|put)\b(?:\s+(?:a|an))?\s+(?:calendar\s+)?(event|meeting|appointment)\s+for\s+((?:(?:next|this)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+(?:at\s+)?\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s+with\s+(.+)$"#,
            #"(?i)\b(?:create|add|schedule|put)\b(?:\s+(?:a|an))?\s+(?:calendar\s+)?(event|meeting|appointment)\s+with\s+(.+?)\s+for\s+((?:(?:next|this)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+(?:at\s+)?\d{1,2}(?::\d{2})?\s*(?:am|pm)?)$"#
        ]
        for (index, pattern) in meetingPatterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: compact,
                    options: [],
                    range: NSRange(compact.startIndex..., in: compact)
                  ),
                  match.numberOfRanges == 4,
                  let kindRange = Range(match.range(at: 1), in: compact) else {
                continue
            }

            let startCaptureIndex = index == 0 ? 2 : 3
            let participantCaptureIndex = index == 0 ? 3 : 2
            guard let startRange = Range(match.range(at: startCaptureIndex), in: compact),
                  let participantRange = Range(match.range(at: participantCaptureIndex), in: compact) else {
                continue
            }

            let kind = sanitizeRecoveredQuery(String(compact[kindRange])).capitalized
            let participant = sanitizeRecoveredQuery(String(compact[participantRange]))
            let start = sanitizeRecoveredQuery(String(compact[startRange]))
            guard !kind.isEmpty, !participant.isEmpty, !start.isEmpty else { continue }
            return [
                "title": "\(kind) with \(participant)",
                "start": start,
                "end_or_duration": "1 hour"
            ]
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"(?i)\b(?:create|add|schedule|put)\b(?:\s+(?:a|an))?(?:\s+(?:calendar\s+)?(?:event|meeting|appointment))?\s+(.+?)\s+(?:at|on)\s+((?:\d{4}-\d{2}-\d{2}[ T]\d{1,2}:\d{2}(?::\d{2})?)|(?:today|tomorrow)\s+(?:at\s+)?\d{1,2}(?::\d{2})?\s*(?:am|pm)?)\s+(?:for|lasting)\s+(.+)$"#
        ) else {
            return nil
        }

        let range = NSRange(compact.startIndex..., in: compact)
        guard let match = regex.firstMatch(in: compact, options: [], range: range),
              match.numberOfRanges == 4,
              let titleRange = Range(match.range(at: 1), in: compact),
              let startRange = Range(match.range(at: 2), in: compact),
              let durationRange = Range(match.range(at: 3), in: compact) else {
            return nil
        }

        let title = sanitizeRecoveredQuery(String(compact[titleRange]))
        let start = sanitizeRecoveredQuery(String(compact[startRange]))
        let duration = sanitizeRecoveredQuery(String(compact[durationRange]))
        guard !title.isEmpty, !start.isEmpty, !duration.isEmpty else { return nil }
        return [
            "title": title,
            "start": start,
            "end_or_duration": duration
        ]
    }

    nonisolated func heuristicTimerCreateRawArguments(for userMessage: String) -> [String: String]? {
        let compact = normalizeForHeuristicMatching(userMessage)
        guard messageLooksTimerCreateAdjacent(compact) else { return nil }

        let durationPatterns = [
            #"(?i)\b(?:set|start|create|put|add)\s+(?:a\s+)?timer\s+(?:for\s+)?(.+)$"#,
            #"(?i)\b(?:set|start|create|put|add)\s+(?:a\s+)?(.+?)\s+timer$"#,
            #"(?i)\btimer\s+(?:for\s+)(.+)$"#
        ]
        for pattern in durationPatterns {
            guard let duration = firstRegexCapture(pattern: pattern, in: compact) else { continue }
            let sanitized = sanitizeRecoveredQuery(duration)
            guard !sanitized.isEmpty else { continue }
            return ["duration": sanitized]
        }
        return nil
    }

    nonisolated func heuristicContactsLookupRawArguments(for userMessage: String) -> [String: String]? {
        let compact = userMessage
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: "‘", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?i)\b(?:look up|find|search(?:\s+for)?)\s+(.+?)\s+(?:in\s+|on\s+)?(?:my\s+)?(?:contacts?|phone|address book)\b"#,
            #"(?i)\b(?:look up|find|search)\s+(?:my\s+)?(?:contacts?|phone|address book)\s+for\s+(.+?)(?:[.?]|$)"#,
            #"(?i)\b(?:contact info|contact details)\s+(?:for\s+)?(.+?)(?:[.?]|$)"#,
            #"(?i)\bwhat(?:'s| is)?\s+(.+?)\s+(?:contact|contact info|contact details)(?:[.?]|$)"#,
            #"(?i)\b(?:phone number|email address|email|number)\s+(?:for|of)\s+(.+?)(?:[.?]|$)"#,
            #"(?i)\bwhat(?:'s| is)?\s+(.+?)(?:'s|\s+s)?\s+(?:phone number|email address|email|number)(?:[.?]|$)"#,
            #"(?i)\b(?:do i have|is)\s+(.+?)\s+(?:as\s+(?:a\s+)?)?(?:in\s+|on\s+)?(?:my\s+)?(?:contacts?|phone|address book)\b"#,
            #"(?i)\b(?:do i have|is)\s+(.+?)\s+as\s+(?:a\s+)?contact\s+(?:in\s+|on\s+)?(?:my\s+)?(?:phone|address book|contacts?)\b"#
        ]
        for pattern in patterns {
            guard let capture = firstRegexCapture(pattern: pattern, in: compact) else { continue }
            let query = sanitizeRecoveredQuery(capture)
            guard !query.isEmpty else { continue }
            return ["query": query]
        }
        return nil
    }

    nonisolated func heuristicRemindersCreateRawArguments(for userMessage: String) -> [String: String]? {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return nil }

        let orderedPrefixes = [
            "set a reminder to ",
            "add a reminder to ",
            "create a reminder to ",
            "remind me to "
        ]
        for prefix in orderedPrefixes {
            if let range = normalized.range(of: prefix) {
                let title = String(normalized[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
                if let arguments = reminderCreateArguments(fromTitleTail: title) { return arguments }
                return nil
            }
        }

        if normalized.hasPrefix("set a reminder") {
            var tail = String(normalized.dropFirst("set a reminder".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if tail.hasPrefix("to ") {
                tail = String(tail.dropFirst(3)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let arguments = reminderCreateArguments(fromTitleTail: tail) { return arguments }
            return nil
        }

        if let range = normalized.range(of: "add to my reminders") {
            let title = String(normalized[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let arguments = reminderCreateArguments(fromTitleTail: title) { return arguments }
            return nil
        }

        if let range = normalized.range(of: "add this to reminders") {
            let title = String(normalized[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            if let arguments = reminderCreateArguments(fromTitleTail: title) { return arguments }
            return nil
        }

        return nil
    }

    nonisolated func reminderCreateArguments(fromTitleTail titleTail: String) -> [String: String]? {
        var title = titleTail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        var arguments: [String: String] = [:]
        let duePatterns = [
            #"(?i)\s+((?:today|tomorrow)\s+(?:at\s+)?\d{1,2}(?::[0-5]\d)?\s*(?:am|pm)?)$"#,
            #"(?i)\s+((?:(?:next|this)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?:\s+(?:at\s+)?\d{1,2}(?::[0-5]\d)?\s*(?:am|pm)?)?)$"#,
            #"(?i)\s+(today|tomorrow|tonight)$"#,
            #"(?i)\s+(in\s+\d+\s+(?:minutes?|hours?|days?))$"#,
            #"(?i)\s+(\d{4}-\d{2}-\d{2}(?:t\d{2}:\d{2}(?::\d{2})?(?:z|[+-]\d{2}:\d{2})?)?)$"#
        ]

        for pattern in duePatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(title.startIndex..., in: title)
            guard let match = regex.firstMatch(in: title, options: [], range: range),
                  match.numberOfRanges > 1,
                  let fullRange = Range(match.range(at: 0), in: title),
                  let dueRange = Range(match.range(at: 1), in: title) else {
                continue
            }
            arguments["due"] = String(title[dueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            title.removeSubrange(fullRange)
            title = title.trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }

        guard isActionableReminderTitle(title) else { return nil }
        arguments["title"] = title
        return arguments
    }

    nonisolated func isActionableReminderTitle(_ candidate: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(candidate)
        guard !normalized.isEmpty else { return false }

        let nonActionableTitles: Set<String> = [
            "a",
            "an",
            "the",
            "for",
            "on",
            "at",
            "to",
            "about",
            "reminder",
            "a reminder",
            "today",
            "tomorrow",
            "tonight",
            "for today",
            "for tomorrow",
            "for tonight",
            "on today",
            "on tomorrow"
        ]
        return !nonActionableTitles.contains(normalized)
    }

    nonisolated func shouldForceCurrentDateTime(for userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }

        let phrases = [
            "what time is it",
            "current time",
            "what s the time",
            "what day is it",
            "what s the date",
            "today s date",
            "current date",
            "what year is it",
            "what s the day",
            "what s today",
            "what timezone",
            "which timezone",
            "my timezone",
            "what time zone",
            "which time zone",
            "my time zone"
        ]
        if phrases.contains(where: { normalized.contains($0) }) {
            return true
        }

        let tokens = Set(normalized.split(separator: " ").map(String.init))
        let temporal = Set(["time", "date", "day", "weekday", "year", "timezone"])
        let anchor = Set(["current", "now", "today"])
        return !tokens.intersection(temporal).isEmpty && !tokens.intersection(anchor).isEmpty
    }

    /// True when answering depends on the device's local "now" to interpret a
    /// relative day/time in the user request (e.g. "playing tomorrow").
    nonisolated func messageNeedsDeviceDateAnchor(for userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }

        let strongRelativePhrases = [
            "tomorrow",
            "tonight",
            "yesterday",
            "this morning",
            "this afternoon",
            "this evening",
            "this weekend",
            "this week",
            "next week",
            "next month",
            "in an hour",
            "in 1 hour",
            "in one hour"
        ]
        if strongRelativePhrases.contains(where: { normalized.contains($0) }) {
            return true
        }

        // Bare "today" is common in casual chat; only treat it as a date anchor
        // when paired with schedule/event language.
        guard normalized.contains("today") else { return false }
        let eventTokens = Set([
            "game", "match", "matches", "playing", "fixture", "fixtures",
            "flight", "flights", "train", "event", "events", "meeting",
            "appointment", "deadline", "due", "open", "closed", "hours",
            "schedule", "kickoff", "kick off"
        ])
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        return !tokens.intersection(eventTokens).isEmpty
    }

    nonisolated func heuristicReminderRange(for userMessage: String) -> RemindersRange? {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return nil }

        let strongReminderPhrases = [
            "my reminder",
            "my reminders",
            "my todo",
            "my todos",
            "my task",
            "my tasks",
            "what do i have to do",
            "what i need to do",
            "what reminders i have",
            "what reminders do i have",
            "what tasks i have",
            "what tasks do i have",
            "show reminders",
            "show tasks",
            "list reminders",
            "list tasks",
            "overdue reminders",
            "overdue tasks",
            "any upcoming reminder",
            "any upcoming reminders",
            "any upcoming task",
            "any upcoming tasks"
        ]
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        let reminderNouns = Set(["reminder", "reminders", "todo", "todos", "task", "tasks"])
        let readCues = Set(["show", "list", "check", "have", "any", "upcoming", "overdue"])
        let temporalCues = Set(["today", "tomorrow", "week", "upcoming", "overdue"])
        let hasStrongPhrase = strongReminderPhrases.contains(where: { normalized.contains($0) })
        let hasReadShapedRequest = !tokens.intersection(reminderNouns).isEmpty
            && !tokens.intersection(readCues).isEmpty
        let hasTerseTemporalRequest = tokens.count <= 4
            && !tokens.intersection(reminderNouns).isEmpty
            && !tokens.intersection(temporalCues).isEmpty
        guard hasStrongPhrase || hasReadShapedRequest || hasTerseTemporalRequest else {
            return nil
        }

        if normalized.contains("overdue") {
            return .overdue
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
        if normalized.contains("today") {
            return .today
        }
        return .all
    }

    nonisolated func heuristicWebSearchQuery(for userMessage: String) -> String? {
        let sanitized = sanitizeRecoveredQuery(userMessage)
        guard !sanitized.isEmpty else { return nil }

        let compact = sanitized.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)

        let explicitSearchPatterns = [
            #"(?i)\b(?:please\s+)?(?:web search|search the web|search online|search the internet|search internet|google|find online|look up online|look it up online)\s+(?:for\s+)?(.+?)(?:\n|$)"#,
            #"(?i)\bcan you (?:search the web|search online|find online)\s+(?:for\s+)?(.+?)(?:\n|$)"#
        ]
        for pattern in explicitSearchPatterns {
            if let explicitQuery = firstRegexCapture(pattern: pattern, in: compact) {
                let query = sanitizeRecoveredQuery(explicitQuery)
                if !query.isEmpty {
                    return query
                }
            }
        }

        // Natural-language search engines handle complete questions well.
        // Preserve every entity, location, date, and qualifier instead of
        // performing a lossy topic-specific rewrite.
        return compact
    }

    nonisolated func normalizeForHeuristicMatching(_ text: String) -> String {
        text
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: #"[^\p{L}\p{N}\s:/._-]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    nonisolated func firstRegexCapture(pattern: String, in text: String) -> String? {
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

    nonisolated func detectedPublicURLs(in text: String) -> [URL] {
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
