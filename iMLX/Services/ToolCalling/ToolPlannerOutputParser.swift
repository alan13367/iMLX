import Foundation

extension ToolCallingService {
    nonisolated func parsePlannerDecision(
        from text: String,
        userMessage: String? = nil,
        tools: [ToolDefinition],
        context: ToolInputContext
    ) -> ToolDecision {
        switch parsePlannerOutcome(
            from: text,
            userMessage: userMessage,
            tools: tools,
            context: context
        ) {
        case .decision(let decision):
            return decision
        case .unusable:
            return .none
        }
    }

    nonisolated func parsePlannerOutcome(
        from text: String,
        userMessage: String? = nil,
        tools: [ToolDefinition],
        context: ToolInputContext
    ) -> ToolPlannerOutcome {
        let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })

        for payload in jsonPayloads(in: text) {
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
                  let dictionary = object as? [String: Any],
                  let rawToolName = dictionary["tool"] as? String else {
                continue
            }

            let toolName = rawToolName
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: " ", with: "_")
            if toolName == "none" {
                return .decision(.none)
            }

            guard let toolDefinition = toolsByName[toolName] else {
                continue
            }

            let rawArguments = (dictionary["args"] as? [String: Any])
                ?? (dictionary["arguments"] as? [String: Any])
                ?? [:]
            guard case .success(let arguments) = validatedArguments(
                rawArguments,
                for: toolDefinition,
                context: context
            ) else {
                continue
            }

            return .decision(
                .call(
                    ToolCallRequest(
                        toolName: toolName,
                        arguments: arguments
                    )
                )
            )
        }

        if let fallbackDecision = fallbackPlannerDecision(
            from: text,
            userMessage: userMessage,
            context: context,
            toolsByName: toolsByName
        ) {
            return .decision(fallbackDecision)
        }

        return .unusable
    }

    nonisolated func jsonPayloads(in text: String) -> [String] {
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

    nonisolated func fencedCodePayloads(in text: String) -> [String] {
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

    nonisolated func balancedJSONFragments(in text: String) -> [String] {
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

    nonisolated func fallbackPlannerDecision(
        from text: String,
        userMessage: String?,
        context: ToolInputContext,
        toolsByName: [String: ToolDefinition]
    ) -> ToolDecision? {
        let lowercasedText = text.lowercased()
        let recoveryPriority = [
            "read_url",
            "ocr_image_text",
            "document_synthesize",
            "timer_create",
            "calendar_create",
            "reminders_create",
            "contacts_lookup",
            "calendar_brief",
            "reminders_brief",
            "current_datetime",
            "web_search"
        ]
        let orderedToolNames = recoveryPriority.filter { toolsByName[$0] != nil }
            + toolsByName.keys.filter { !recoveryPriority.contains($0) }.sorted()

        for toolName in orderedToolNames {
            guard let toolDefinition = toolsByName[toolName] else { continue }
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

    nonisolated func proseSuggestsUsingTool(named toolName: String, in lowercasedText: String) -> Bool {
        let underscored = toolName.lowercased()
        let spaced = underscored.replacingOccurrences(of: "_", with: " ")
        let negativePatterns = [
            "do not use \(underscored)",
            "don't use \(underscored)",
            "should not use \(underscored)",
            "without using \(underscored)",
            "do not use \(spaced)",
            "don't use \(spaced)",
            "should not use \(spaced)",
            "without using \(spaced)"
        ]
        if negativePatterns.contains(where: { lowercasedText.contains($0) }) {
            return false
        }

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

    nonisolated func inferredWebSearchQuery(from text: String, userMessage: String?) -> String? {
        if let explicitQuery = firstRegexCapture(
            pattern: #"(?i)\bsearch for\s+["“]?(.+?)["”]?(?:\n|$)"#,
            in: text
        ) {
            let sanitized = sanitizeRecoveredQuery(explicitQuery)
            if !sanitized.isEmpty {
                return sanitized
            }
        }

        if let explicitQuery = firstRegexCapture(
            pattern: #"(?i)\bquery\s*[:=]\s*["“]?(.+?)["”]?(?:\n|$)"#,
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

    nonisolated func inferredReadURL(from text: String, context: ToolInputContext) -> URL? {
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

    nonisolated func sanitizeRecoveredQuery(_ query: String) -> String {
        query
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }


}
