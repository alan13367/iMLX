import EventKit
import Foundation

nonisolated enum CalendarBriefRange: String, CaseIterable, Sendable {
    case today
    case tomorrow
    case thisWeek = "this_week"
    case next7Days = "next_7_days"
}

actor CalendarBriefService {
    private let eventStore: EKEventStore
    private let calendar: Calendar

    init(eventStore: EKEventStore = EKEventStore(), calendar: Calendar = .current) {
        self.eventStore = eventStore
        self.calendar = calendar
    }

    func retrieveContext(for range: CalendarBriefRange, now: Date = Date()) async throws -> MessageGroundingResult {
        guard try await ensureCalendarAccess() else {
            throw ToolExecutionFailure.permissionDenied("Calendar access is required to brief events.")
        }

        let interval = dateInterval(for: range, now: now)
        let calendars = eventStore.calendars(for: .event)
        let predicate = eventStore.predicateForEvents(
            withStart: interval.start,
            end: interval.end,
            calendars: calendars.isEmpty ? nil : calendars
        )
        let events = eventStore.events(matching: predicate)
            .filter { !$0.isDetached }
            .sorted { $0.startDate < $1.startDate }

        guard !events.isEmpty else {
            throw ToolExecutionFailure.noContent("No calendar events were found for this range.")
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale.current
        dayFormatter.timeZone = calendar.timeZone
        dayFormatter.dateStyle = .full
        dayFormatter.timeStyle = .none

        var sections: [String] = []
        var sources: [MessageSource] = []
        var usedCharacters = 0

        for event in events {
            let title = event.title?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                ? event.title!
                : "Untitled event"
            let timeDescription = event.isAllDay
                ? "All day on \(dayFormatter.string(from: event.startDate))"
                : "\(formatter.string(from: event.startDate)) - \(formatter.string(from: event.endDate))"
            let calendarName = event.calendar?.title ?? "Calendar"
            let location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
            let locationLine = location?.isEmpty == false ? "\nLocation: \(location!)" : ""
            let section = """
            Event: \(title)
            Time: \(timeDescription)
            Calendar: \(calendarName)\(locationLine)
            """

            if usedCharacters + section.count > Constants.ToolCalling.maxToolResultContextCharacters, !sections.isEmpty {
                break
            }

            sections.append(section)
            sources.append(
                MessageSource(
                    id: event.eventIdentifier ?? "\(title)-\(event.startDate.timeIntervalSince1970)",
                    kind: .calendar,
                    title: title,
                    excerpt: timeDescription,
                    location: calendarName,
                    url: nil,
                    score: nil
                )
            )
            usedCharacters += section.count
        }

        let contextBlock = """
        The user granted local calendar access. Use the calendar events below only for schedule, availability, conflict, and preparation questions.

        Do not mention event notes, attendees, or private details that are not shown here.

        Calendar range: \(range.rawValue)

        \(sections.joined(separator: "\n\n---\n\n"))
        """

        return MessageGroundingResult(contextBlock: contextBlock, sources: sources)
    }

    func createEvent(
        title: String,
        startDate: Date,
        endDate: Date,
        location: String?,
        notes: String?,
        alertMinutesBefore: Int?
    ) async throws -> MessageGroundingResult {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ToolExecutionFailure.invalidArguments("A calendar event title is required.")
        }
        guard endDate > startDate else {
            throw ToolExecutionFailure.invalidArguments("Calendar event end time must be after the start time.")
        }
        guard try await ensureCalendarAccess() else {
            throw ToolExecutionFailure.permissionDenied("Calendar access is required to create events.")
        }
        guard let targetCalendar = eventStore.defaultCalendarForNewEvents else {
            throw ToolExecutionFailure.unavailable("No writable default calendar is available.")
        }

        let event = EKEvent(eventStore: eventStore)
        event.calendar = targetCalendar
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.startDate = startDate
        event.endDate = endDate

        let cleanedLocation = location?.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedLocation?.isEmpty == false {
            event.location = cleanedLocation
        }

        let cleanedNotes = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanedNotes?.isEmpty == false {
            event.notes = cleanedNotes
        }

        if let alertMinutesBefore {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-alertMinutesBefore * 60)))
        }

        try eventStore.save(event, span: .thisEvent, commit: true)

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = calendar.timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short

        let timeDescription = "\(formatter.string(from: startDate)) - \(formatter.string(from: endDate))"
        let contextBlock = """
        Calendar event created:
        - Title: \(event.title ?? title)
        - Time: \(timeDescription)
        - Calendar: \(targetCalendar.title)
        """

        let source = MessageSource(
            id: event.eventIdentifier ?? "\(title)-\(startDate.timeIntervalSince1970)",
            kind: .calendar,
            title: event.title ?? title,
            excerpt: timeDescription,
            location: targetCalendar.title,
            url: nil,
            score: nil
        )

        return MessageGroundingResult(contextBlock: contextBlock, sources: [source])
    }

    private func ensureCalendarAccess() async throws -> Bool {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess:
            return true
        case .notDetermined:
            if #available(iOS 17.0, macOS 14.0, *) {
                return try await eventStore.requestFullAccessToEvents()
            } else {
                return try await withCheckedThrowingContinuation { continuation in
                    eventStore.requestAccess(to: .event) { granted, error in
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(returning: granted)
                        }
                    }
                }
            }
        case .authorized:
            return true
        case .denied, .restricted, .writeOnly:
            return false
        @unknown default:
            return false
        }
    }

    private func dateInterval(for range: CalendarBriefRange, now: Date) -> DateInterval {
        switch range {
        case .today:
            return calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 86_400)
        case .tomorrow:
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) ?? now.addingTimeInterval(86_400)
            return calendar.dateInterval(of: .day, for: tomorrow) ?? DateInterval(start: tomorrow, duration: 86_400)
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: now, duration: 604_800)
        case .next7Days:
            let start = now
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start.addingTimeInterval(604_800)
            return DateInterval(start: start, end: end)
        }
    }
}
