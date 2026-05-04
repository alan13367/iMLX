import EventKit
import Foundation

nonisolated enum RemindersRange: String, CaseIterable, Sendable {
    case all
    case today
    case tomorrow
    case thisWeek = "this_week"
    case next7Days = "next_7_days"
    case overdue
}

actor RemindersService {
    private let eventStore: EKEventStore
    private let calendar: Calendar

    init(eventStore: EKEventStore = EKEventStore(), calendar: Calendar = .current) {
        self.eventStore = eventStore
        self.calendar = calendar
    }

    func retrieveContext(for range: RemindersRange, now: Date = Date()) async throws -> MessageGroundingResult {
        guard try await ensureRemindersAccess() else {
            throw ToolExecutionFailure.permissionDenied("Reminders access is required to list your reminders.")
        }

        let reminderCalendars = eventStore.calendars(for: .reminder)
        let lists = reminderCalendars.isEmpty ? nil : reminderCalendars
        let (startDate, endDate) = dueDateBounds(for: range, now: now)
        let predicate = eventStore.predicateForIncompleteReminders(
            withDueDateStarting: startDate,
            ending: endDate,
            calendars: lists
        )

        let rawReminders = try await fetchReminders(matching: predicate)
        let reminders = rawReminders
            .filter { !$0.isCompleted }
            .sorted { lhs, rhs in
                let ld = lhs.dueDateComponents.flatMap { calendar.date(from: $0) } ?? Date.distantFuture
                let rd = rhs.dueDateComponents.flatMap { calendar.date(from: $0) } ?? Date.distantFuture
                return ld < rd
            }

        guard !reminders.isEmpty else {
            throw ToolExecutionFailure.noContent("No incomplete reminders were found for this range.")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let rangeReference = dateReferenceBlock(
            range: range.rawValue,
            startDate: startDate,
            endDate: endDate,
            now: now,
            formatter: formatter
        )

        var sections: [String] = []
        var sources: [MessageSource] = []
        var usedCharacters = 0

        for reminder in reminders {
            let rawTitle = reminder.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = rawTitle.isEmpty ? "Untitled reminder" : rawTitle
            let listName = reminder.calendar?.title ?? "Reminders"
            let dueLine: String
            if let dueComps = reminder.dueDateComponents, let due = calendar.date(from: dueComps) {
                if reminder.hasRecurrenceRules {
                    dueLine = "Due (next): \(formatter.string(from: due)) (repeating)"
                } else {
                    dueLine = "Due: \(formatter.string(from: due))"
                }
            } else {
                dueLine = "Due: (no date)"
            }

            let priorityLine = reminder.priority > 0 ? "\nPriority: \(reminder.priority)" : ""
            let section = """
            Reminder: \(title)
            \(dueLine)
            List: \(listName)\(priorityLine)
            """

            if usedCharacters + section.count > Constants.ToolCalling.maxToolResultContextCharacters, !sections.isEmpty {
                break
            }

            sections.append(section)
            let excerpt = dueLine.replacingOccurrences(of: "Due: ", with: "")
            sources.append(
                MessageSource(
                    id: reminder.calendarItemIdentifier,
                    kind: .reminder,
                    title: title,
                    excerpt: excerpt,
                    location: listName,
                    url: nil,
                    score: nil
                )
            )
            usedCharacters += section.count
        }

        let contextBlock = """
        The user granted local Reminders access. Use the items below only for todo, task, and reminder questions.

        \(rangeReference)

        \(sections.joined(separator: "\n\n---\n\n"))
        """

        return MessageGroundingResult(contextBlock: contextBlock, sources: sources)
    }

    func createReminder(title: String, dueDate: Date?, notes: String?, now: Date = Date()) async throws -> MessageGroundingResult {
        guard try await ensureRemindersAccess() else {
            throw ToolExecutionFailure.permissionDenied("Reminders access is required to create a reminder.")
        }

        guard let targetCalendar = eventStore.defaultCalendarForNewReminders() else {
            throw ToolExecutionFailure.unavailable("No default Reminders list is available.")
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.calendar = targetCalendar
        if let notes, !notes.isEmpty {
            reminder.notes = notes
        }
        if let dueDate {
            reminder.dueDateComponents = calendar.dateComponents(
                [.year, .month, .day, .hour, .minute, .second, .timeZone],
                from: dueDate
            )
        }

        try eventStore.save(reminder, commit: true)

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let dueSummary: String
        if let dueDate {
            dueSummary = "for \(formatter.string(from: dueDate))"
        } else {
            dueSummary = "with no due date"
        }

        let contextBlock = "Added '\(title)' to Reminders \(dueSummary)."
        return MessageGroundingResult(
            contextBlock: contextBlock,
            sources: []
        )
    }

    private func fetchReminders(matching predicate: NSPredicate) async throws -> [EKReminder] {
        try await withCheckedThrowingContinuation { continuation in
            eventStore.fetchReminders(matching: predicate) { reminders in
                continuation.resume(returning: reminders ?? [])
            }
        }
    }

    private func ensureRemindersAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .fullAccess, .authorized:
            return true
        case .writeOnly:
            return false
        case .notDetermined:
            if #available(iOS 17.0, *) {
                return try await eventStore.requestFullAccessToReminders()
            } else {
                return try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestAccess(to: .reminder) { granted, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private func dueDateBounds(for range: RemindersRange, now: Date) -> (Date?, Date?) {
        switch range {
        case .all:
            return (nil, nil)
        case .overdue:
            return (nil, now)
        case .today:
            let interval = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 86_400)
            return (interval.start, interval.end.addingTimeInterval(-1))
        case .tomorrow:
            let day = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
            let interval = calendar.dateInterval(of: .day, for: day) ?? DateInterval(start: day, duration: 86_400)
            return (interval.start, interval.end.addingTimeInterval(-1))
        case .thisWeek:
            let interval = calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 604_800)
            return (interval.start, interval.end.addingTimeInterval(-1))
        case .next7Days:
            let end = calendar.date(byAdding: .day, value: 7, to: now) ?? now.addingTimeInterval(604_800)
            return (now, end)
        }
    }

    private func dateReferenceBlock(
        range: String,
        startDate: Date?,
        endDate: Date?,
        now: Date,
        formatter: DateFormatter
    ) -> String {
        let start = startDate.map { formatter.string(from: $0) } ?? "unbounded"
        let end = endDate.map { formatter.string(from: $0) } ?? "unbounded"
        return """
        Current local date/time: \(formatter.string(from: now))
        Reminders range: \(range)
        Range start: \(start)
        Range end: \(end)
        """
    }
}
