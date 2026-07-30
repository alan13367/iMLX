import Foundation

extension ToolCallingService {
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
            return normalizedCalendarCreateArguments(validated, context: context)
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

    nonisolated func normalizedCalendarCreateArguments(
        _ arguments: [String: String],
        context: ToolInputContext?
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
        if let userMessage = context?.latestUserMessage,
           let explicitWeekdayStart = ToolDateTimeParser.explicitWeekdayStartDate(in: userMessage, calendar: calendar) {
            startDate = explicitWeekdayStart
        } else {
            switch ToolDateTimeParser.parse(startRaw, calendar: calendar) {
            case .success(let date):
                startDate = date
            case .failure(let failure):
                return .failure(failure)
            }
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

    nonisolated func normalizedTimerCreateArguments(
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

    nonisolated func normalizedContactsLookupArguments(
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

    nonisolated func normalizedRequest(
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

    nonisolated func isToolEnabled(
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

    nonisolated func normalizedArgumentValue(
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
                guard isActionableReminderTitle(trimmed) else {
                    return .failure(.invalidArguments("Argument `title` must describe what the user should be reminded about."))
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
            let clamped = toolDefinition.name == "web_search"
                ? boundedWebSearchQuery(trimmed)
                : String(trimmed.prefix(Constants.ToolCalling.maxQueryLength))
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
                    return .failure(.invalidArguments("Argument `range` must be one of: all, today, tomorrow, this_week, next_7_days, overdue."))
                }
                return .success(range)
            default:
                return .failure(.invalidArguments("Unexpected `range` argument for tool `\(toolDefinition.name)`."))
            }

        default:
            return normalizedPrimitiveValue(for: argument, rawValue: rawValue)
        }
    }

    nonisolated func normalizedPrimitiveValue(
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

    nonisolated func normalizedStringValue(from rawValue: Any?) -> String? {
        rawValue as? String
    }

    nonisolated func boundedWebSearchQuery(_ query: String) -> String {
        let limit = Constants.ToolCalling.maxQueryLength
        guard query.count > limit else { return query }

        let separator = " … "
        let available = max(2, limit - separator.count)
        let headCount = Int(Double(available) * 0.65)
        let tailCount = available - headCount
        return String(query.prefix(headCount))
            + separator
            + String(query.suffix(tailCount))
    }

    nonisolated func normalizedPublicURL(from candidate: String) -> URL? {
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return nil
        }

        // Upgrade http to https to comply with ATS policy
        if scheme == "http" {
            let httpsString = url.absoluteString.replacingOccurrences(of: "http://", with: "https://", options: .caseInsensitive)
            return URL(string: httpsString) ?? url
        }

        return url
    }

    nonisolated func failureResult(
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


}
