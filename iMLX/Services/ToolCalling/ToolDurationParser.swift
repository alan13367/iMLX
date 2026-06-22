import Foundation

nonisolated enum ToolDurationParser {
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
