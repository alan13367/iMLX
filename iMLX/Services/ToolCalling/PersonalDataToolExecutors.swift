import Foundation

struct CurrentDateTimeToolExecutor: ToolExecutor {
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

struct RemindersBriefToolExecutor: ToolExecutor {
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

struct RemindersCreateToolExecutor: ToolExecutor {
    let toolName = "reminders_create"
    let remindersService: RemindersService

    func execute(arguments: [String: String], context _: ToolInputContext) async throws -> ToolExecutionResult {
        guard let title = arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty else {
            throw ToolExecutionFailure.invalidArguments("A reminder title is required.")
        }

        let dueDate: Date?
        if let due = arguments["due"]?.trimmingCharacters(in: .whitespacesAndNewlines), !due.isEmpty {
            dueDate = ToolDueDateParser.parseISO8601DateTime(due)
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

struct CalendarCreateToolExecutor: ToolExecutor {
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

struct CalendarBriefToolExecutor: ToolExecutor {
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

struct TimerCreateToolExecutor: ToolExecutor {
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

struct ContactsLookupToolExecutor: ToolExecutor {
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

