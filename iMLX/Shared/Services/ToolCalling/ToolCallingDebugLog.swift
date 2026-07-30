import Foundation

/// Shared DEBUG console formatting for tool-calling. Prefer short stage labels and
/// aligned detail lines over dense `key=value` soup.
enum ToolCallingDebugLog {
    private static let labelWidth = 10

#if DEBUG
    static func section(_ title: String) {
        print("[Tools] ── \(title) ──")
    }

    static func line(_ label: String, _ value: String) {
        print("[Tools] \(padded(label)) \(value)")
    }

    static func note(_ message: String) {
        print("[Tools] \(message)")
    }

    static func decision(_ label: String, _ decision: ToolDecision) {
        line(label, describe(decision))
    }

    static func describe(_ decision: ToolDecision) -> String {
        switch decision {
        case .none:
            return "none"
        case .call(let request):
            let args = formatted(arguments: request.arguments)
            if args == "{}" {
                return "call \(request.toolName)"
            }
            return "call \(request.toolName) \(args)"
        }
    }

    static func describe(_ outcome: ToolPlannerOutcome) -> String {
        switch outcome {
        case .decision(let decision):
            return describe(decision)
        case .unusable:
            return "unusable"
        }
    }

    static func describe(_ preflight: ToolPreflight) -> String {
        switch preflight {
        case .skip(let decision):
            switch decision {
            case .none:
                return "skip · no tool"
            case .call(let request):
                return "fast-path · \(request.toolName)"
            }
        case .deliberate:
            return "deliberate → planner"
        }
    }

    static func describe(trace: ToolCallTrace) -> String {
        var parts = [trace.toolName]
        if let status = trace.status?.rawValue {
            parts.append(status)
        }
        if let duration = trace.durationSeconds {
            parts.append(String(format: "%.2fs", duration))
        }
        if let input = trace.displayInput, !input.isEmpty {
            parts.append(sanitized(input, limit: 80))
        }
        return parts.joined(separator: " · ")
    }

    static func sanitized(_ text: String, limit: Int = 160) -> String {
        let compact = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard compact.count > limit else { return compact }
        return String(compact.prefix(limit)) + "…"
    }

    static func formatted(arguments: [String: String]) -> String {
        let pairs = arguments
            .sorted { $0.key < $1.key }
            .map { key, value in
                "\(key)=\(sanitized(value, limit: 80))"
            }
        guard !pairs.isEmpty else { return "{}" }
        return "{\(pairs.joined(separator: ", "))}"
    }

    static func joinedNames(_ names: [String]) -> String {
        names.isEmpty ? "(none)" : names.joined(separator: ", ")
    }

    private static func padded(_ label: String) -> String {
        if label.count >= labelWidth {
            return label
        }
        return label.padding(toLength: labelWidth, withPad: " ", startingAt: 0)
    }
#else
    static func section(_ title: String) {}
    static func line(_ label: String, _ value: String) {}
    static func note(_ message: String) {}
    static func decision(_ label: String, _ decision: ToolDecision) {}
    static func describe(_ decision: ToolDecision) -> String { "" }
    static func describe(_ outcome: ToolPlannerOutcome) -> String { "" }
    static func describe(_ preflight: ToolPreflight) -> String { "" }
    static func describe(trace: ToolCallTrace) -> String { "" }
    static func sanitized(_ text: String, limit: Int = 160) -> String { text }
    static func formatted(arguments: [String: String]) -> String { "{}" }
    static func joinedNames(_ names: [String]) -> String { "" }
#endif
}
