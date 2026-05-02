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

/// Result of the synchronous preflight that decides whether a turn even needs the
/// LLM-backed planner. `skip` carries a final decision (either a confident tool
/// call or `.none`); `deliberate` means the planner should run because the turn
/// is ambiguous enough that an LLM round-trip might add value.
nonisolated enum ToolPreflight: Equatable, Sendable {
    case skip(ToolDecision)
    case deliberate
}

private enum ToolDueDateParser {
    private static let isoDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()

    static func parse(_ raw: String, referenceDate: Date, calendar: Calendar) -> Result<Date, ToolExecutionFailure> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.invalidArguments("Argument `due` must not be empty when provided."))
        }
        let lower = trimmed.lowercased()

        if lower == "today" {
            let start = calendar.startOfDay(for: referenceDate)
            var endComps = DateComponents()
            endComps.day = 1
            endComps.second = -1
            let endOfDay = calendar.date(byAdding: endComps, to: start) ?? start.addingTimeInterval(86_400 - 1)
            return .success(endOfDay)
        }
        if lower == "tomorrow" {
            guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: referenceDate) else {
                return .failure(.invalidArguments("Could not resolve tomorrow for `due`."))
            }
            let start = calendar.startOfDay(for: tomorrow)
            var endComps = DateComponents()
            endComps.day = 1
            endComps.second = -1
            let endOfDay = calendar.date(byAdding: endComps, to: start) ?? start.addingTimeInterval(86_400 - 1)
            return .success(endOfDay)
        }
        if lower == "tonight" {
            var comps = calendar.dateComponents([.year, .month, .day], from: referenceDate)
            comps.hour = 22
            comps.minute = 0
            comps.second = 0
            guard let date = calendar.date(from: comps) else {
                return .failure(.invalidArguments("Could not resolve tonight for `due`."))
            }
            return .success(date)
        }

        if let n = matchIntGroup(pattern: #"^in\s+(\d+)\s+minutes?$"#, in: lower),
           n >= 0, n <= 10_080,
           let date = calendar.date(byAdding: .minute, value: n, to: referenceDate) {
            return .success(date)
        }
        if let n = matchIntGroup(pattern: #"^in\s+(\d+)\s+hours?$"#, in: lower),
           n >= 0, n <= 8760,
           let date = calendar.date(byAdding: .hour, value: n, to: referenceDate) {
            return .success(date)
        }
        if let n = matchIntGroup(pattern: #"^in\s+(\d+)\s+days?$"#, in: lower),
           n >= 0, n <= 365,
           let date = calendar.date(byAdding: .day, value: n, to: referenceDate) {
            return .success(date)
        }

        let compactDate = trimmed.replacingOccurrences(of: " ", with: "")
        if let date = isoDateFormatter.date(from: compactDate) {
            return .success(date)
        }

        let dt = ISO8601DateFormatter()
        dt.formatOptions = [.withInternetDateTime]
        if let date = dt.date(from: compactDate) {
            return .success(date)
        }

        let df = DateFormatter()
        df.calendar = calendar
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = calendar.timeZone
        df.dateFormat = "yyyy-MM-dd'T'HH:mm"
        if let date = df.date(from: compactDate) {
            return .success(date)
        }

        return .failure(.invalidArguments("Argument `due` must be today, tomorrow, tonight, ISO date/datetime, or in N hours/minutes/days."))
    }

    static func iso8601DueString(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private static func matchIntGroup(pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[captureRange])
    }
}

private nonisolated enum ToolDateTimeParser {
    static func parse(_ raw: String, referenceDate: Date = Date(), calendar: Calendar = .current) -> Result<Date, ToolExecutionFailure> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.invalidArguments("Date/time arguments must not be empty."))
        }

        let compact = trimmed.replacingOccurrences(of: " ", with: "")
        let internet = ISO8601DateFormatter()
        internet.formatOptions = [.withInternetDateTime]
        if let date = internet.date(from: compact) {
            return .success(date)
        }

        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return .success(date)
            }
        }

        if let relative = parseRelativeDayTime(trimmed, referenceDate: referenceDate, calendar: calendar) {
            return .success(relative)
        }

        return .failure(.invalidArguments("Date/time arguments must be ISO datetime or an explicit today/tomorrow time."))
    }

    static func iso8601String(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    private static func parseRelativeDayTime(_ raw: String, referenceDate: Date, calendar: Calendar) -> Date? {
        let lower = raw.lowercased()
        guard let regex = try? NSRegularExpression(
            pattern: #"^(today|tomorrow)\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$"#,
            options: []
        ) else {
            return nil
        }
        let range = NSRange(lower.startIndex..., in: lower)
        guard let match = regex.firstMatch(in: lower, options: [], range: range),
              match.numberOfRanges >= 3,
              let dayRange = Range(match.range(at: 1), in: lower),
              let hourRange = Range(match.range(at: 2), in: lower) else {
            return nil
        }

        var hour = Int(lower[hourRange]) ?? -1
        let minute: Int
        if match.range(at: 3).location != NSNotFound,
           let minuteRange = Range(match.range(at: 3), in: lower) {
            minute = Int(lower[minuteRange]) ?? -1
        } else {
            minute = 0
        }

        if match.range(at: 4).location != NSNotFound,
           let meridiemRange = Range(match.range(at: 4), in: lower) {
            let meridiem = String(lower[meridiemRange])
            if meridiem == "pm", hour < 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        }

        guard (0...23).contains(hour), (0...59).contains(minute) else {
            return nil
        }

        let day = String(lower[dayRange])
        let base = day == "tomorrow"
            ? (calendar.date(byAdding: .day, value: 1, to: referenceDate) ?? referenceDate.addingTimeInterval(86_400))
            : referenceDate
        var components = calendar.dateComponents([.year, .month, .day], from: base)
        components.hour = hour
        components.minute = minute
        components.second = 0
        return calendar.date(from: components)
    }
}

private nonisolated enum ToolDurationParser {
    static func parseSeconds(_ raw: String) -> Result<Int, ToolExecutionFailure> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return .failure(.invalidArguments("Duration must not be empty."))
        }
        let lower = trimmed.lowercased()

        if let seconds = Int(lower), (1...86_400).contains(seconds) {
            return .success(seconds)
        }

        if let hms = parseColonDuration(lower), (1...86_400).contains(hms) {
            return .success(hms)
        }

        let patterns: [(String, Int)] = [
            (#"^(?:for\s+)?(\d+)\s*(?:seconds?|secs?|sec|s)$"#, 1),
            (#"^(?:for\s+)?(\d+)\s*(?:minutes?|mins?|min|m)$"#, 60),
            (#"^(?:for\s+)?(\d+)\s*(?:hours?|hrs?|hr|h)$"#, 3600)
        ]
        for (pattern, multiplier) in patterns {
            if let value = firstInt(pattern: pattern, in: lower) {
                let seconds = value * multiplier
                guard (1...86_400).contains(seconds) else {
                    return .failure(.invalidArguments("Duration must be between 1 second and 24 hours."))
                }
                return .success(seconds)
            }
        }

        if let total = parseCompoundDuration(lower), (1...86_400).contains(total) {
            return .success(total)
        }

        return .failure(.invalidArguments("Duration must be seconds, minutes, hours, MM:SS, HH:MM:SS, or a simple compound duration."))
    }

    static func durationDescription(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let seconds = seconds % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours)h") }
        if minutes > 0 { parts.append("\(minutes)m") }
        if seconds > 0 || parts.isEmpty { parts.append("\(seconds)s") }
        return parts.joined(separator: " ")
    }

    private static func parseColonDuration(_ text: String) -> Int? {
        let pieces = text.split(separator: ":").compactMap { Int($0) }
        guard pieces.count == 2 || pieces.count == 3 else { return nil }
        if pieces.count == 2 {
            guard (0...59).contains(pieces[1]) else { return nil }
            return pieces[0] * 60 + pieces[1]
        }
        guard (0...59).contains(pieces[1]), (0...59).contains(pieces[2]) else { return nil }
        return pieces[0] * 3600 + pieces[1] * 60 + pieces[2]
    }

    private static func parseCompoundDuration(_ text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: #"(\d+)\s*(hours?|hrs?|hr|h|minutes?|mins?|min|m|seconds?|secs?|sec|s)"#) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, options: [], range: range)
        guard !matches.isEmpty else { return nil }

        var total = 0
        for match in matches {
            guard match.numberOfRanges == 3,
                  let valueRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let value = Int(text[valueRange]) else {
                return nil
            }
            let unit = String(text[unitRange])
            if unit.hasPrefix("h") { total += value * 3600 }
            else if unit.hasPrefix("m") { total += value * 60 }
            else { total += value }
        }
        return total
    }

    private static func firstInt(pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[valueRange])
    }
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
        remindersService: RemindersService = RemindersService(),
        timerService: TimerService = TimerService(),
        contactsService: ContactsService = ContactsService(),
        currentDateTimeNow: @escaping @Sendable () -> Date = { Date() },
        currentDateTimeTimeZone: TimeZone = .current,
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
        let calendarCreateTool = ToolDefinition(
            name: "calendar_create",
            description: "Creates one basic event in the user's default Calendar when title, start, and end or duration are explicit.",
            argumentSchema: [
                ToolArgument(
                    name: "title",
                    type: "string",
                    required: true,
                    description: "Short event title."
                ),
                ToolArgument(
                    name: "start",
                    type: "string",
                    required: true,
                    description: "Explicit start datetime: ISO datetime, yyyy-MM-dd HH:mm, today HH:mm, or tomorrow HH:mm."
                ),
                ToolArgument(
                    name: "end_or_duration",
                    type: "string",
                    required: true,
                    description: "Explicit end datetime or duration such as 30 minutes or 1 hour."
                ),
                ToolArgument(
                    name: "location",
                    type: "string",
                    required: false,
                    description: "Optional event location."
                ),
                ToolArgument(
                    name: "notes",
                    type: "string",
                    required: false,
                    description: "Optional event notes."
                ),
                ToolArgument(
                    name: "alert_minutes_before",
                    type: "string",
                    required: false,
                    description: "Optional alert offset in minutes before the event."
                )
            ],
            metadata: ToolMetadata(executionClass: .local)
        )
        let currentDateTimeTool = ToolDefinition(
            name: "current_datetime",
            description: "Returns the device's current local date, time, weekday, and timezone using the system clock.",
            argumentSchema: [],
            metadata: ToolMetadata(executionClass: .local)
        )
        let remindersBriefTool = ToolDefinition(
            name: "reminders_brief",
            description: "Reads incomplete local reminders for a bounded due-date range and returns a private brief.",
            argumentSchema: [
                ToolArgument(
                    name: "range",
                    type: "string",
                    required: true,
                    description: "One of: today, tomorrow, this_week, next_7_days, overdue."
                )
            ],
            metadata: ToolMetadata(executionClass: .local)
        )
        let remindersCreateTool = ToolDefinition(
            name: "reminders_create",
            description: "Creates one reminder in the user's default Reminders list with an optional due date and notes.",
            argumentSchema: [
                ToolArgument(
                    name: "title",
                    type: "string",
                    required: true,
                    description: "Short reminder title."
                ),
                ToolArgument(
                    name: "due",
                    type: "string",
                    required: false,
                    description: "Optional due: today, tomorrow, tonight, ISO date/datetime, or in N hours/minutes/days."
                ),
                ToolArgument(
                    name: "notes",
                    type: "string",
                    required: false,
                    description: "Optional notes."
                )
            ],
            metadata: ToolMetadata(executionClass: .local)
        )
        let timerCreateTool = ToolDefinition(
            name: "timer_create",
            description: "Creates and starts one native timer for an explicit duration between 1 second and 24 hours.",
            argumentSchema: [
                ToolArgument(
                    name: "duration",
                    type: "string",
                    required: true,
                    description: "Explicit duration such as 10 minutes, 1 hour 30 minutes, MM:SS, HH:MM:SS, or seconds."
                ),
                ToolArgument(
                    name: "title",
                    type: "string",
                    required: false,
                    description: "Optional short timer title."
                )
            ],
            metadata: ToolMetadata(executionClass: .local)
        )
        let contactsLookupTool = ToolDefinition(
            name: "contacts_lookup",
            description: "Looks up matching local Contacts and returns names plus phone numbers and email addresses only.",
            argumentSchema: [
                ToolArgument(
                    name: "query",
                    type: "string",
                    required: true,
                    description: "The person's or organization's name to look up."
                )
            ],
            metadata: ToolMetadata(executionClass: .local)
        )

        let readURLExecutor = ReadURLToolExecutor(webSearchService: webSearchService)
        let ocrExecutor = OCRImageTextToolExecutor(imageOCRService: imageOCRService)
        let webSearchExecutor = WebSearchToolExecutor(webSearchService: webSearchService)
        let documentExecutor = DocumentSynthesizeToolExecutor(documentLibraryService: documentLibraryService)
        let calendarExecutor = CalendarBriefToolExecutor(calendarBriefService: calendarBriefService)
        let calendarCreateExecutor = CalendarCreateToolExecutor(calendarBriefService: calendarBriefService)
        let currentDateTimeExecutor = CurrentDateTimeToolExecutor(
            now: currentDateTimeNow,
            timeZone: currentDateTimeTimeZone
        )
        let remindersBriefExecutor = RemindersBriefToolExecutor(remindersService: remindersService)
        let remindersCreateExecutor = RemindersCreateToolExecutor(remindersService: remindersService)
        let timerCreateExecutor = TimerCreateToolExecutor(timerService: timerService)
        let contactsLookupExecutor = ContactsLookupToolExecutor(contactsService: contactsService)

        self.toolExecutionTimeoutSeconds = toolExecutionTimeoutSeconds
        self.registeredTools = [
            readURLTool,
            ocrTool,
            webSearchTool,
            documentTool,
            calendarTool,
            calendarCreateTool,
            currentDateTimeTool,
            remindersBriefTool,
            remindersCreateTool,
            timerCreateTool,
            contactsLookupTool
        ]
        self.registeredExecutors = [
            readURLExecutor.toolName: readURLExecutor,
            ocrExecutor.toolName: ocrExecutor,
            webSearchExecutor.toolName: webSearchExecutor,
            documentExecutor.toolName: documentExecutor,
            calendarExecutor.toolName: calendarExecutor,
            calendarCreateExecutor.toolName: calendarCreateExecutor,
            currentDateTimeExecutor.toolName: currentDateTimeExecutor,
            remindersBriefExecutor.toolName: remindersBriefExecutor,
            remindersCreateExecutor.toolName: remindersCreateExecutor,
            timerCreateExecutor.toolName: timerCreateExecutor,
            contactsLookupExecutor.toolName: contactsLookupExecutor
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

        if let timerCreateTool = toolsByName["timer_create"],
           let raw = heuristicTimerCreateRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: timerCreateTool,
                context: context
           ) {
            Self.debugLog("heuristic fallback selected timer_create for explicit timer request")
            return .call(ToolCallRequest(toolName: timerCreateTool.name, arguments: arguments))
        }

        if let calendarCreateTool = toolsByName["calendar_create"],
           let raw = heuristicCalendarCreateRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: calendarCreateTool,
                context: context
           ) {
            Self.debugLog("heuristic fallback selected calendar_create for explicit event request")
            return .call(ToolCallRequest(toolName: calendarCreateTool.name, arguments: arguments))
        }

        if let contactsLookupTool = toolsByName["contacts_lookup"],
           let raw = heuristicContactsLookupRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: contactsLookupTool,
                context: context
           ) {
            Self.debugLog("heuristic fallback selected contacts_lookup for contact request")
            return .call(ToolCallRequest(toolName: contactsLookupTool.name, arguments: arguments))
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

        if let remindersCreateTool = toolsByName["reminders_create"],
           let raw = heuristicRemindersCreateRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: remindersCreateTool,
                context: context
           ) {
            Self.debugLog("heuristic fallback selected reminders_create for explicit reminder request")
            return .call(ToolCallRequest(toolName: remindersCreateTool.name, arguments: arguments))
        }

        if let dateTimeTool = toolsByName["current_datetime"],
           shouldForceCurrentDateTime(for: userMessage),
           case .success(let arguments) = validatedArguments([:], for: dateTimeTool, context: context) {
            Self.debugLog("heuristic fallback selected current_datetime for time/date question")
            return .call(ToolCallRequest(toolName: dateTimeTool.name, arguments: arguments))
        }

        if let remindersBriefTool = toolsByName["reminders_brief"],
           let range = heuristicReminderRange(for: userMessage),
           case .success(let arguments) = validatedArguments(
                ["range": range.rawValue],
                for: remindersBriefTool,
                context: context
           ) {
            Self.debugLog("heuristic fallback selected reminders_brief for todo/reminder request")
            return .call(ToolCallRequest(toolName: remindersBriefTool.name, arguments: arguments))
        }

        if preferThinkingFallback,
           let fallbackDecision = heuristicFallbackDecision(userMessage: userMessage, tools: tools) {
            return fallbackDecision
        }

        return .none
    }

    /// Decides whether the LLM-backed planner needs to run this turn.
    ///
    /// Runs deterministic arbitration first (pasted URL, document/OCR/calendar/
    /// live-data heuristics) and short-circuits to a final `ToolDecision` when
    /// the answer is unambiguous. Returns `.deliberate` only when the turn has
    /// genuinely ambiguous context that an LLM might disambiguate (attached
    /// docs/images without a clear request, multiple URLs, web-search-leaning
    /// language without a strong heuristic match).
    ///
    /// This keeps short, simple questions ("hi", "what's 2+2") from paying for
    /// a full planner inference round-trip just to be told `.none`.
    nonisolated func preflightDecision(
        userMessage: String,
        context: ToolInputContext,
        tools: [ToolDefinition]
    ) -> ToolPreflight {
        guard !tools.isEmpty else {
            Self.debugLog("preflight skip: no enabled tools (decision=none)")
            return .skip(.none)
        }

        let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })

        // 1. Pasted single public URL → high-confidence read_url.
        if let directURL = context.singleDetectedPublicURL,
           let readURLTool = toolsByName["read_url"],
           case .success(let arguments) = validatedArguments(
                ["url": directURL.absoluteString],
                for: readURLTool,
                context: context
           ) {
            Self.debugLog("preflight selected read_url for pasted URL (planner skipped)")
            return .skip(.call(ToolCallRequest(toolName: readURLTool.name, arguments: arguments)))
        }

        // 2. Newly-attached documents or explicit document language.
        if let documentTool = toolsByName["document_synthesize"],
           shouldForceDocumentSynthesis(for: userMessage, context: context),
           case .success(let arguments) = validatedArguments(
                ["query": userMessage],
                for: documentTool,
                context: context
           ) {
            Self.debugLog("preflight selected document_synthesize (planner skipped)")
            return .skip(.call(ToolCallRequest(toolName: documentTool.name, arguments: arguments)))
        }

        // 3. Text-focused image request with attached images.
        if let ocrTool = toolsByName["ocr_image_text"],
           shouldForceOCR(for: userMessage, context: context),
           case .success(let arguments) = validatedArguments(
                [:],
                for: ocrTool,
                context: context
           ) {
            Self.debugLog("preflight selected ocr_image_text (planner skipped)")
            return .skip(.call(ToolCallRequest(toolName: ocrTool.name, arguments: arguments)))
        }

        // 4. Explicit timer create request.
        if let timerCreateTool = toolsByName["timer_create"],
           let raw = heuristicTimerCreateRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: timerCreateTool,
                context: context
           ) {
            Self.debugLog("preflight selected timer_create (planner skipped)")
            return .skip(.call(ToolCallRequest(toolName: timerCreateTool.name, arguments: arguments)))
        }

        // 4a. Explicit calendar event create request when all required fields are parseable.
        if let calendarCreateTool = toolsByName["calendar_create"],
           let raw = heuristicCalendarCreateRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: calendarCreateTool,
                context: context
           ) {
            Self.debugLog("preflight selected calendar_create (planner skipped)")
            return .skip(.call(ToolCallRequest(toolName: calendarCreateTool.name, arguments: arguments)))
        }

        // 4b. Contact lookup request.
        if let contactsLookupTool = toolsByName["contacts_lookup"],
           let raw = heuristicContactsLookupRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: contactsLookupTool,
                context: context
           ) {
            Self.debugLog("preflight selected contacts_lookup (planner skipped)")
            return .skip(.call(ToolCallRequest(toolName: contactsLookupTool.name, arguments: arguments)))
        }

        // 4c. Calendar-shaped request.
        if let calendarTool = toolsByName["calendar_brief"],
           let range = heuristicCalendarRange(for: userMessage),
           case .success(let arguments) = validatedArguments(
                ["range": range.rawValue],
                for: calendarTool,
                context: context
           ) {
            Self.debugLog("preflight selected calendar_brief range=\(range.rawValue) (planner skipped)")
            return .skip(.call(ToolCallRequest(toolName: calendarTool.name, arguments: arguments)))
        }

        // 4d. Explicit create-reminder request (before brief so "remind me to …" does not read the list).
        if let remindersCreateTool = toolsByName["reminders_create"],
           let raw = heuristicRemindersCreateRawArguments(for: userMessage),
           case .success(let arguments) = validatedArguments(
                Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                for: remindersCreateTool,
                context: context
           ) {
            Self.debugLog("preflight selected reminders_create (planner skipped)")
            return .skip(.call(ToolCallRequest(toolName: remindersCreateTool.name, arguments: arguments)))
        }

        // 4e. Device date/time from the system clock.
        if let dateTimeTool = toolsByName["current_datetime"],
           shouldForceCurrentDateTime(for: userMessage),
           case .success(let arguments) = validatedArguments(
                [:],
                for: dateTimeTool,
                context: context
           ) {
            Self.debugLog("preflight selected current_datetime (planner skipped)")
            return .skip(.call(ToolCallRequest(toolName: dateTimeTool.name, arguments: arguments)))
        }

        // 4f. Reminders list / todo brief for a bounded range.
        if let remindersBriefTool = toolsByName["reminders_brief"],
           let range = heuristicReminderRange(for: userMessage),
           case .success(let arguments) = validatedArguments(
                ["range": range.rawValue],
                for: remindersBriefTool,
                context: context
           ) {
            Self.debugLog("preflight selected reminders_brief range=\(range.rawValue) (planner skipped)")
            return .skip(.call(ToolCallRequest(toolName: remindersBriefTool.name, arguments: arguments)))
        }

        // 5. Strong live-data web_search phrase, but only when no attachments
        //    might reframe the request as document/image-grounded.
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
            Self.debugLog("preflight selected web_search via live-data heuristic (planner skipped)")
            return .skip(.call(ToolCallRequest(toolName: webSearchTool.name, arguments: arguments)))
        }

        // 6. Quick reject: nothing in the turn could plausibly need a tool.
        //    Skip the planner entirely and let the model answer directly.
        if !mightBenefitFromPlanner(
            userMessage: userMessage,
            context: context,
            toolsByName: toolsByName
        ) {
            Self.debugLog("preflight skip: no actionable context or heuristic match (decision=none)")
            return .skip(.none)
        }

        return .deliberate
    }

    private nonisolated func mightBenefitFromPlanner(
        userMessage: String,
        context: ToolInputContext,
        toolsByName: [String: ToolDefinition]
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
        // Multiple URLs → planner picks one or returns none (read_url v1
        // requires exactly one public URL, and we won't guess for the user).
        if context.detectedPublicURLs.count > 1,
           toolsByName["read_url"] != nil {
            return true
        }
        // Web-search-leaning language that didn't satisfy the strong force.
        if toolsByName["web_search"] != nil,
           messageLooksWebSearchAdjacent(userMessage) {
            return true
        }
        if toolsByName["current_datetime"] != nil,
           messageLooksDateTimeAdjacent(userMessage) {
            return true
        }
        if toolsByName["calendar_create"] != nil,
           messageLooksCalendarCreateAdjacent(userMessage) {
            return true
        }
        if toolsByName["timer_create"] != nil,
           messageLooksTimerCreateAdjacent(userMessage) {
            return true
        }
        if toolsByName["contacts_lookup"] != nil,
           messageLooksContactsLookupAdjacent(userMessage) {
            return true
        }
        return false
    }

    private nonisolated func messageLooksWebSearchAdjacent(_ userMessage: String) -> Bool {
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
            "live update"
        ]
        return webHints.contains(where: { normalized.contains($0) })
    }

    private nonisolated func messageLooksDateTimeAdjacent(_ userMessage: String) -> Bool {
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

    private nonisolated func messageLooksCalendarCreateAdjacent(_ userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }
        let createHints = ["create", "add", "schedule", "put"]
        let calendarHints = ["calendar", "event", "meeting", "appointment"]
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        return !tokens.intersection(createHints).isEmpty
            && (!tokens.intersection(calendarHints).isEmpty || normalized.contains("on my calendar"))
    }

    private nonisolated func messageLooksTimerCreateAdjacent(_ userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }
        let createHints = ["set", "start", "create", "put", "add"]
        let tokens = Set(normalized.split(separator: " ").map(String.init))
        return normalized.contains("timer")
            && !tokens.intersection(createHints).isEmpty
    }

    private nonisolated func messageLooksContactsLookupAdjacent(_ userMessage: String) -> Bool {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return false }
        let hints = [
            "contact",
            "contacts",
            "phone number",
            "email address",
            "email for",
            "number for"
        ]
        return hints.contains(where: { normalized.contains($0) })
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
            let decision = parsePlannerDecision(
                from: rawOutput,
                userMessage: userMessage,
                tools: tools,
                context: context
            )
            Self.debugLog(
                "planner output: raw=\(Self.sanitizedSnippet(rawOutput, limit: 280)) " +
                "earlyStop=\(sawCompleteToolDecisionJSON) decision=\(Self.describe(decision))"
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
            switch normalizedArgumentValue(argument, rawValue: rawValue, context: context, toolDefinition: toolDefinition) {
            case .success(let normalized):
                if let normalized, !normalized.isEmpty {
                    validated[argument.name] = normalized
                }
            case .failure(let failure):
                return .failure(failure)
            }
        }

        switch toolDefinition.name {
        case "calendar_create":
            return normalizedCalendarCreateArguments(validated)
        case "timer_create":
            return normalizedTimerCreateArguments(validated)
        case "contacts_lookup":
            return normalizedContactsLookupArguments(validated)
        default:
            break
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

    private nonisolated func normalizedCalendarCreateArguments(
        _ arguments: [String: String]
    ) -> Result<[String: String], ToolExecutionFailure> {
        guard let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            return .failure(.invalidArguments("Argument `title` is required."))
        }
        guard let startRaw = arguments["start"] else {
            return .failure(.invalidArguments("Argument `start` is required."))
        }
        guard let endRaw = arguments["end_or_duration"] else {
            return .failure(.invalidArguments("Argument `end_or_duration` is required."))
        }

        let calendar = Calendar.current
        let startDate: Date
        switch ToolDateTimeParser.parse(startRaw, calendar: calendar) {
        case .success(let date):
            startDate = date
        case .failure(let failure):
            return .failure(failure)
        }

        let endDate: Date
        switch ToolDurationParser.parseSeconds(endRaw) {
        case .success(let seconds):
            endDate = startDate.addingTimeInterval(TimeInterval(seconds))
        case .failure:
            switch ToolDateTimeParser.parse(endRaw, calendar: calendar) {
            case .success(let date):
                endDate = date
            case .failure:
                return .failure(.invalidArguments("Argument `end_or_duration` must be an explicit end datetime or duration."))
            }
        }

        guard endDate > startDate else {
            return .failure(.invalidArguments("Argument `end_or_duration` must resolve after `start`."))
        }

        var normalized: [String: String] = [
            "title": String(title.prefix(Constants.ToolCalling.maxCalendarTitleLength)),
            "start": ToolDateTimeParser.iso8601String(from: startDate),
            "end_or_duration": ToolDateTimeParser.iso8601String(from: endDate)
        ]

        if let location = arguments["location"]?.trimmingCharacters(in: .whitespacesAndNewlines), !location.isEmpty {
            normalized["location"] = String(location.prefix(Constants.ToolCalling.maxCalendarLocationLength))
        }
        if let notes = arguments["notes"]?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            normalized["notes"] = String(notes.prefix(Constants.ToolCalling.maxCalendarNotesLength))
        }
        if let alert = arguments["alert_minutes_before"]?.trimmingCharacters(in: .whitespacesAndNewlines), !alert.isEmpty {
            guard let minutes = Int(alert), (0...10_080).contains(minutes) else {
                return .failure(.invalidArguments("Argument `alert_minutes_before` must be an integer from 0 to 10080."))
            }
            normalized["alert_minutes_before"] = String(minutes)
        }

        return .success(normalized)
    }

    private nonisolated func normalizedTimerCreateArguments(
        _ arguments: [String: String]
    ) -> Result<[String: String], ToolExecutionFailure> {
        guard let durationRaw = arguments["duration"] else {
            return .failure(.invalidArguments("Argument `duration` is required."))
        }
        let seconds: Int
        switch ToolDurationParser.parseSeconds(durationRaw) {
        case .success(let value):
            seconds = value
        case .failure(let failure):
            return .failure(failure)
        }

        var normalized = ["duration": String(seconds)]
        if let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            normalized["title"] = String(title.prefix(Constants.ToolCalling.maxTimerTitleLength))
        }
        return .success(normalized)
    }

    private nonisolated func normalizedContactsLookupArguments(
        _ arguments: [String: String]
    ) -> Result<[String: String], ToolExecutionFailure> {
        guard let query = arguments["query"]?
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            return .failure(.invalidArguments("Argument `query` is required."))
        }
        return .success(["query": String(query.prefix(Constants.ToolCalling.maxContactQueryLength))])
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
        context: ToolInputContext?,
        toolDefinition: ToolDefinition
    ) -> Result<String?, ToolExecutionFailure> {
        if toolDefinition.name == "reminders_create" {
            switch argument.name {
            case "title":
                guard let rawValue else {
                    return .failure(.invalidArguments("Argument `title` is required."))
                }
                guard let raw = normalizedStringValue(from: rawValue) else {
                    return .failure(.invalidArguments("Argument `title` must be a string."))
                }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return .failure(.invalidArguments("Argument `title` must not be empty."))
                }
                let clamped = String(trimmed.prefix(Constants.ToolCalling.maxReminderTitleLength))
                return .success(clamped)

            case "due":
                guard let rawValue else {
                    return .success(nil)
                }
                guard let dueRaw = normalizedStringValue(from: rawValue)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !dueRaw.isEmpty else {
                    return .success(nil)
                }
                switch ToolDueDateParser.parse(dueRaw, referenceDate: Date(), calendar: Calendar.current) {
                case .success(let date):
                    return .success(ToolDueDateParser.iso8601DueString(from: date))
                case .failure(let failure):
                    return .failure(failure)
                }

            case "notes":
                guard let rawValue else {
                    return .success(nil)
                }
                guard let raw = normalizedStringValue(from: rawValue) else {
                    return .failure(.invalidArguments("Argument `notes` must be a string."))
                }
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    return .success(nil)
                }
                let clamped = String(trimmed.prefix(Constants.ToolCalling.maxReminderNotesLength))
                return .success(clamped)

            default:
                break
            }
        }

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
                .lowercased() else {
                return .failure(.invalidArguments("Argument `range` must be a string."))
            }

            switch toolDefinition.name {
            case "calendar_brief":
                guard CalendarBriefRange(rawValue: range) != nil else {
                    return .failure(.invalidArguments("Argument `range` must be one of: today, tomorrow, this_week, next_7_days."))
                }
                return .success(range)
            case "reminders_brief":
                guard RemindersRange(rawValue: range) != nil else {
                    return .failure(.invalidArguments("Argument `range` must be one of: today, tomorrow, this_week, next_7_days, overdue."))
                }
                return .success(range)
            default:
                return .failure(.invalidArguments("Unexpected `range` argument for tool `\(toolDefinition.name)`."))
            }

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

            case "calendar_create":
                let source = userMessage ?? context.latestUserMessage
                guard let raw = heuristicCalendarCreateRawArguments(for: source),
                      case .success(let arguments) = validatedArguments(
                        Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                        for: toolDefinition,
                        context: context
                      ) else {
                    continue
                }
                Self.debugLog("planner recovered prose decision for \(toolName)")
                return .call(ToolCallRequest(toolName: toolName, arguments: arguments))

            case "current_datetime":
                guard case .success(let arguments) = validatedArguments(
                    [:],
                    for: toolDefinition,
                    context: context
                ) else {
                    continue
                }
                Self.debugLog("planner recovered prose decision for \(toolName)")
                return .call(ToolCallRequest(toolName: toolName, arguments: arguments))

            case "reminders_brief":
                guard let range = heuristicReminderRange(for: userMessage ?? context.latestUserMessage),
                      case .success(let arguments) = validatedArguments(
                        ["range": range.rawValue],
                        for: toolDefinition,
                        context: context
                      ) else {
                    continue
                }
                Self.debugLog("planner recovered prose decision for \(toolName)")
                return .call(ToolCallRequest(toolName: toolName, arguments: arguments))

            case "reminders_create":
                let source = userMessage ?? context.latestUserMessage
                guard let raw = heuristicRemindersCreateRawArguments(for: source),
                      case .success(let arguments) = validatedArguments(
                        Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                        for: toolDefinition,
                        context: context
                      ) else {
                    continue
                }
                Self.debugLog("planner recovered prose decision for \(toolName)")
                return .call(ToolCallRequest(toolName: toolName, arguments: arguments))

            case "timer_create":
                let source = userMessage ?? context.latestUserMessage
                guard let raw = heuristicTimerCreateRawArguments(for: source),
                      case .success(let arguments) = validatedArguments(
                        Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
                        for: toolDefinition,
                        context: context
                      ) else {
                    continue
                }
                Self.debugLog("planner recovered prose decision for \(toolName)")
                return .call(ToolCallRequest(toolName: toolName, arguments: arguments))

            case "contacts_lookup":
                let source = userMessage ?? context.latestUserMessage
                guard let raw = heuristicContactsLookupRawArguments(for: source),
                      case .success(let arguments) = validatedArguments(
                        Dictionary(uniqueKeysWithValues: raw.map { ($0.key, $0.value as Any) }),
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
            "weather today",
            "weather tomorrow",
            "current weather",
            "stock price",
            "share price",
            "exchange rate",
            "next game",
            "next match",
            "live score",
            "score today",
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

    private nonisolated func heuristicCalendarCreateRawArguments(for userMessage: String) -> [String: String]? {
        let compact = userMessage
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = normalizeForHeuristicMatching(compact)
        guard messageLooksCalendarCreateAdjacent(normalized) else { return nil }

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

    private nonisolated func heuristicTimerCreateRawArguments(for userMessage: String) -> [String: String]? {
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

    private nonisolated func heuristicContactsLookupRawArguments(for userMessage: String) -> [String: String]? {
        let compact = userMessage
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = [
            #"(?i)\b(?:look up|find|search for)\s+(.+?)\s+(?:in\s+)?(?:my\s+)?contacts?\b"#,
            #"(?i)\b(?:contact info|contact details)\s+(?:for\s+)?(.+?)(?:[.?]|$)"#,
            #"(?i)\bwhat(?:'s| is)?\s+(.+?)\s+(?:contact|contact info|contact details)(?:[.?]|$)"#,
            #"(?i)\b(?:phone number|email address|email|number)\s+(?:for|of)\s+(.+?)(?:[.?]|$)"#,
            #"(?i)\bwhat(?:'s| is)?\s+(.+?)'s\s+(?:phone number|email address|email|number)(?:[.?]|$)"#
        ]
        for pattern in patterns {
            guard let capture = firstRegexCapture(pattern: pattern, in: compact) else { continue }
            let query = sanitizeRecoveredQuery(capture)
            guard !query.isEmpty else { continue }
            return ["query": query]
        }
        return nil
    }

    private nonisolated func heuristicRemindersCreateRawArguments(for userMessage: String) -> [String: String]? {
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

    private nonisolated func reminderCreateArguments(fromTitleTail titleTail: String) -> [String: String]? {
        var title = titleTail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }

        var arguments: [String: String] = [:]
        let duePatterns = [
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

        guard !title.isEmpty else { return nil }
        arguments["title"] = title
        return arguments
    }

    private nonisolated func shouldForceCurrentDateTime(for userMessage: String) -> Bool {
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

    private nonisolated func heuristicReminderRange(for userMessage: String) -> RemindersRange? {
        let normalized = normalizeForHeuristicMatching(userMessage)
        guard !normalized.isEmpty else { return nil }

        let markers = [
            "reminder",
            "reminders",
            "todo",
            "to do",
            "to-do",
            "todos",
            "task",
            "tasks",
            "overdue",
            "what do i have to do",
            "what i need to do"
        ]
        guard markers.contains(where: { normalized.contains($0) }) else {
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

private struct CurrentDateTimeToolExecutor: ToolExecutor {
    let toolName = "current_datetime"
    let now: @Sendable () -> Date
    let timeZone: TimeZone

    func execute(arguments _: [String: String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        let startTime = Date()
        let date = now()

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        isoFormatter.timeZone = timeZone
        let iso = isoFormatter.string(from: date)

        let readable = DateFormatter()
        readable.locale = Locale.current
        readable.timeZone = timeZone
        readable.dateStyle = .full
        readable.timeStyle = .short
        let readableString = readable.string(from: date)

        let offsetFormatter = DateFormatter()
        offsetFormatter.locale = Locale(identifier: "en_US_POSIX")
        offsetFormatter.dateFormat = "XXXXX"
        offsetFormatter.timeZone = timeZone
        let offsetLabel = offsetFormatter.string(from: date)

        let contextBlock = """
        Current local date/time:
        - ISO 8601: \(iso)
        - Readable: \(readableString)
        - Timezone: \(timeZone.identifier) (\(offsetLabel))
        """

        return ToolExecutionResult(
            toolName: toolName,
            status: .success,
            message: nil,
            contextBlock: contextBlock,
            sources: [],
            durationSeconds: Date().timeIntervalSince(startTime)
        )
    }
}

private struct RemindersBriefToolExecutor: ToolExecutor {
    let toolName = "reminders_brief"
    let remindersService: RemindersService

    func execute(arguments: [String: String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        guard let rawRange = arguments["range"],
              let range = RemindersRange(rawValue: rawRange) else {
            throw ToolExecutionFailure.invalidArguments("A supported reminders range is required.")
        }

        let startTime = Date()
        let result = try await remindersService.retrieveContext(for: range)
        guard !result.contextBlock.isEmpty else {
            throw ToolExecutionFailure.noContent("No reminders were found.")
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

private struct RemindersCreateToolExecutor: ToolExecutor {
    let toolName = "reminders_create"
    let remindersService: RemindersService

    func execute(arguments: [String: String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        guard let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            throw ToolExecutionFailure.invalidArguments("A reminder title is required.")
        }

        let dueDate: Date?
        if let due = arguments["due"]?.trimmingCharacters(in: .whitespacesAndNewlines), !due.isEmpty {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            formatter.timeZone = .current
            dueDate = formatter.date(from: due)
        } else {
            dueDate = nil
        }

        let rawNotes = arguments["notes"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = (rawNotes?.isEmpty == false) ? rawNotes : nil

        let startTime = Date()
        let result = try await remindersService.createReminder(title: title, dueDate: dueDate, notes: notes)
        guard !result.contextBlock.isEmpty else {
            throw ToolExecutionFailure.noContent("Reminder was created but returned no confirmation text.")
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

private struct CalendarCreateToolExecutor: ToolExecutor {
    let toolName = "calendar_create"
    let calendarBriefService: CalendarBriefService

    func execute(arguments: [String: String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        guard let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            throw ToolExecutionFailure.invalidArguments("A calendar event title is required.")
        }
        guard let startRaw = arguments["start"],
              let endRaw = arguments["end_or_duration"] else {
            throw ToolExecutionFailure.invalidArguments("Calendar event start and end are required.")
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = .current
        guard let startDate = formatter.date(from: startRaw),
              let endDate = formatter.date(from: endRaw),
              endDate > startDate else {
            throw ToolExecutionFailure.invalidArguments("Calendar event start and end must be valid ISO datetimes.")
        }

        let location = arguments["location"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let notes = arguments["notes"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let alertMinutesBefore = arguments["alert_minutes_before"].flatMap(Int.init)

        let startTime = Date()
        let result = try await calendarBriefService.createEvent(
            title: title,
            startDate: startDate,
            endDate: endDate,
            location: location?.isEmpty == false ? location : nil,
            notes: notes?.isEmpty == false ? notes : nil,
            alertMinutesBefore: alertMinutesBefore
        )
        guard !result.contextBlock.isEmpty else {
            throw ToolExecutionFailure.noContent("Calendar event was created but returned no confirmation text.")
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

private struct TimerCreateToolExecutor: ToolExecutor {
    let toolName = "timer_create"
    let timerService: TimerService

    func execute(arguments: [String: String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        guard let rawDuration = arguments["duration"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              let durationSeconds = TimeInterval(rawDuration),
              durationSeconds >= 1,
              durationSeconds <= 86_400 else {
            throw ToolExecutionFailure.invalidArguments("A timer duration from 1 second to 24 hours is required.")
        }

        let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let startTime = Date()
        let result = try await timerService.createTimer(
            durationSeconds: durationSeconds,
            title: title?.isEmpty == false ? title : nil
        )
        guard !result.contextBlock.isEmpty else {
            throw ToolExecutionFailure.noContent("Timer was created but returned no confirmation text.")
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

private struct ContactsLookupToolExecutor: ToolExecutor {
    let toolName = "contacts_lookup"
    let contactsService: ContactsService

    func execute(arguments: [String: String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        guard let query = arguments["query"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !query.isEmpty else {
            throw ToolExecutionFailure.invalidArguments("A contact lookup query is required.")
        }

        let startTime = Date()
        let result = try await contactsService.retrieveContext(for: query)
        guard !result.contextBlock.isEmpty else {
            throw ToolExecutionFailure.noContent("No matching contacts were found.")
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
