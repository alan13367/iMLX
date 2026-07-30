import Foundation

enum ToolDueDateParser {
    private static let isoDateOnlyPattern = #"^\d{4}-\d{2}-\d{2}$"#

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

        if lower.range(
            of: #"^(?:(?:next|this)\s+)?(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday)\s+(?:at\s+)?\d{1,2}(?::\d{2})?\s*(?:am|pm)?$"#,
            options: .regularExpression
        ) != nil,
           let date = ToolDateTimeParser.explicitWeekdayStartDate(
                in: lower,
                referenceDate: referenceDate,
                calendar: calendar
           ) {
            return .success(date)
        }

        if lower.range(
            of: #"^(?:today|tomorrow)\s+(?:at\s+)?\d{1,2}(?::\d{2})?\s*(?:am|pm)?$"#,
            options: .regularExpression
        ) != nil {
            switch ToolDateTimeParser.parse(lower, referenceDate: referenceDate, calendar: calendar) {
            case .success(let date):
                return .success(date)
            case .failure:
                break
            }
        }

        let compactDate = trimmed.replacingOccurrences(of: " ", with: "")

        // Full datetimes must be tried before date-only. ISO8601DateFormatter with
        // `.withFullDate` alone will otherwise accept `2026-07-27T12:11:10+02:00` as
        // midnight UTC, which re-encodes to 02:00 in +02 and corrupts relative dues.
        if compactDate.contains("T") || trimmed.contains(" ") {
            if let date = parseISO8601DateTime(compactDate) {
                return .success(date)
            }

            let df = DateFormatter()
            df.calendar = calendar
            df.locale = Locale(identifier: "en_US_POSIX")
            df.timeZone = calendar.timeZone
            df.isLenient = false
            for format in ["yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm", "yyyy-MM-dd HH:mm"] {
                df.dateFormat = format
                if let date = df.date(from: trimmed) ?? df.date(from: compactDate) {
                    return .success(date)
                }
            }
        }

        if lower.range(of: isoDateOnlyPattern, options: .regularExpression) != nil {
            let parts = lower.split(separator: "-")
            guard parts.count == 3,
                  let year = Int(parts[0]),
                  let month = Int(parts[1]),
                  let day = Int(parts[2]) else {
                return .failure(.invalidArguments("Argument `due` has an invalid ISO date."))
            }
            var comps = DateComponents()
            comps.year = year
            comps.month = month
            comps.day = day
            comps.hour = 23
            comps.minute = 59
            comps.second = 59
            guard let date = calendar.date(from: comps) else {
                return .failure(.invalidArguments("Could not resolve ISO date for `due`."))
            }
            return .success(date)
        }

        return .failure(.invalidArguments("Argument `due` must be today, tomorrow, tonight, a named weekday with an explicit time, ISO date/datetime, or in N hours/minutes/days."))
    }

    static func iso8601DueString(from date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        formatter.timeZone = timeZone
        return formatter.string(from: date)
    }

    static func parseISO8601DateTime(_ raw: String) -> Date? {
        let compact = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        guard !compact.isEmpty else { return nil }

        let withColon = ISO8601DateFormatter()
        withColon.formatOptions = [.withInternetDateTime, .withColonSeparatorInTimeZone]
        if let date = withColon.date(from: compact) {
            return date
        }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: compact) {
            return date
        }

        // Accept Zulu / offset forms without requiring a caller-chosen timezone.
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds, .withColonSeparatorInTimeZone]
        return fractional.date(from: compact)
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
