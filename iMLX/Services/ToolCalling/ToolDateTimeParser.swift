import Foundation

nonisolated enum ToolDateTimeParser {
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

    static func explicitWeekdayStartDate(
        in text: String,
        referenceDate: Date = Date(),
        calendar: Calendar = .current
    ) -> Date? {
        let lower = text.lowercased()
        guard let regex = try? NSRegularExpression(
            pattern: #"\b(?:on\s+)?(?:(next|this)\s+)?(monday|tuesday|wednesday|thursday|friday|saturday|sunday)(?:\s+with\s+.+?)?\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\b"#,
            options: []
        ) else {
            return nil
        }
        let range = NSRange(lower.startIndex..., in: lower)
        guard let match = regex.firstMatch(in: lower, options: [], range: range),
              match.numberOfRanges >= 4,
              let weekdayRange = Range(match.range(at: 2), in: lower),
              let hourRange = Range(match.range(at: 3), in: lower) else {
            return nil
        }

        let qualifier: String?
        if match.range(at: 1).location != NSNotFound,
           let qualifierRange = Range(match.range(at: 1), in: lower) {
            qualifier = String(lower[qualifierRange])
        } else {
            qualifier = nil
        }

        let weekdayName = String(lower[weekdayRange])
        let weekday: Int
        switch weekdayName {
        case "sunday": weekday = 1
        case "monday": weekday = 2
        case "tuesday": weekday = 3
        case "wednesday": weekday = 4
        case "thursday": weekday = 5
        case "friday": weekday = 6
        case "saturday": weekday = 7
        default: return nil
        }

        var hour = Int(lower[hourRange]) ?? -1
        let minute: Int
        if match.range(at: 4).location != NSNotFound,
           let minuteRange = Range(match.range(at: 4), in: lower) {
            minute = Int(lower[minuteRange]) ?? -1
        } else {
            minute = 0
        }

        if match.range(at: 5).location != NSNotFound,
           let meridiemRange = Range(match.range(at: 5), in: lower) {
            let meridiem = String(lower[meridiemRange])
            if meridiem == "pm", hour < 12 { hour += 12 }
            if meridiem == "am", hour == 12 { hour = 0 }
        }

        guard (0...23).contains(hour), (0...59).contains(minute) else {
            return nil
        }

        let startOfReferenceDay = calendar.startOfDay(for: referenceDate)
        for dayOffset in 0...14 {
            guard qualifier != "next" || dayOffset > 0,
                  let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfReferenceDay) else {
                continue
            }
            guard calendar.component(.weekday, from: day) == weekday else {
                continue
            }
            var components = calendar.dateComponents([.year, .month, .day], from: day)
            components.hour = hour
            components.minute = minute
            components.second = 0
            guard let date = calendar.date(from: components), date > referenceDate else {
                continue
            }
            return date
        }

        return nil
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
