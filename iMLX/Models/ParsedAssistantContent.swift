import Foundation

nonisolated struct ParsedAssistantContent: Equatable {
    let thinking: String?
    let response: String
    let copyableText: String

    static let empty = ParsedAssistantContent(thinking: nil, response: "", copyableText: "")

    init(thinking: String?, response: String, copyableText: String? = nil) {
        let trimmedThinking = thinking?.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedResponse = response.trimmingCharacters(in: .whitespacesAndNewlines)

        self.thinking = trimmedThinking?.isEmpty == false ? trimmedThinking : nil
        self.response = trimmedResponse
        if let copyableText {
            self.copyableText = copyableText
        } else {
            self.copyableText = trimmedResponse.isEmpty ? (self.thinking ?? "") : trimmedResponse
        }
    }

    private static let answerHeadingRegexes: [NSRegularExpression] = [
        "^(?:\\s*#{1,6}\\s*)?(?:\\*{0,2}|_{0,2}|`{0,1})final answer(?:\\s*[:：])?(?:\\*{0,2}|_{0,2}|`{0,1})\\s*",
        "^(?:\\s*#{1,6}\\s*)?(?:\\*{0,2}|_{0,2}|`{0,1})suggested answer(?:\\s*[:：])?(?:\\*{0,2}|_{0,2}|`{0,1})\\s*",
        "^(?:\\s*#{1,6}\\s*)?(?:\\*{0,2}|_{0,2}|`{0,1})answer(?:\\s*[:：])?(?:\\*{0,2}|_{0,2}|`{0,1})\\s*",
        "^(?:\\s*#{1,6}\\s*)?(?:\\*{0,2}|_{0,2}|`{0,1})response(?:\\s*[:：])?(?:\\*{0,2}|_{0,2}|`{0,1})\\s*"
    ].compactMap {
        try? NSRegularExpression(pattern: $0, options: [.caseInsensitive])
    }

    init(_ rawContent: String, isStreaming: Bool = false) {
        let normalizedContent = Self.normalizedContent(rawContent)

        if let tagged = Self.parseTaggedThinking(normalizedContent) {
            let cleanedResponse = Self.stripAnswerHeading(tagged.response)
            self.init(
                thinking: tagged.thinking,
                response: cleanedResponse,
                copyableText: cleanedResponse.isEmpty ? tagged.thinking : cleanedResponse
            )
            return
        }

        if let trailingTagged = Self.parseTrailingClosingTag(normalizedContent) {
            let cleanedResponse = Self.stripAnswerHeading(trailingTagged.response)
            self.init(
                thinking: trailingTagged.thinking,
                response: cleanedResponse,
                copyableText: cleanedResponse.isEmpty ? trailingTagged.thinking : cleanedResponse
            )
            return
        }

        if let inferred = Self.parseInferredThinking(normalizedContent, isStreaming: isStreaming) {
            self.init(
                thinking: inferred.thinking,
                response: inferred.response,
                copyableText: inferred.response.isEmpty ? inferred.thinking : inferred.response
            )
            return
        }

        let cleanedResponse = normalizedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        self.init(thinking: nil, response: cleanedResponse, copyableText: cleanedResponse)
    }

    private static func normalizedContent(_ rawContent: String) -> String {
        rawContent
            .replacingOccurrences(of: "▊", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseTaggedThinking(_ rawContent: String) -> (thinking: String, response: String)? {
        for tagName in ["think", "thinking", "reasoning"] {
            let openTag = "<\(tagName)>"
            guard let openRange = rawContent.range(of: openTag, options: [.caseInsensitive]) else { continue }

            let closeTag = "</\(tagName)>"
            if let closeRange = rawContent.range(
                of: closeTag,
                options: [.caseInsensitive],
                range: openRange.upperBound..<rawContent.endIndex
            ) {
                let thinkingSlice = rawContent[openRange.upperBound..<closeRange.lowerBound]
                let afterThinking = rawContent[closeRange.upperBound...]
                let cleanedThinking = thinkingSlice.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedResponse = afterThinking.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cleanedThinking.isEmpty else { return nil }
                return (cleanedThinking, cleanedResponse)
            }

            let thinkingSlice = rawContent[openRange.upperBound...]
            let cleanedThinking = thinkingSlice.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanedThinking.isEmpty else { return nil }
            return (cleanedThinking, "")
        }

        return nil
    }

    private static func parseTrailingClosingTag(_ rawContent: String) -> (thinking: String, response: String)? {
        for tagName in ["think", "thinking", "reasoning"] {
            let closeTag = "</\(tagName)>"
            guard let closeRange = rawContent.range(of: closeTag, options: [.caseInsensitive]) else { continue }

            let prefix = String(rawContent[..<closeRange.lowerBound])
            let openTag = "<\(tagName)>"
            if prefix.range(of: openTag, options: [.caseInsensitive]) != nil {
                continue
            }

            let thinking = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = rawContent[closeRange.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !thinking.isEmpty else { return nil }
            return (thinking, response)
        }

        return nil
    }

    private static func parseInferredThinking(_ rawContent: String, isStreaming: Bool) -> (thinking: String, response: String)? {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let allLines = trimmed.components(separatedBy: .newlines)
        if let answerLineIndex = firstExplicitAnswerLineIndex(in: allLines), answerLineIndex > 0 {
            let thinking = allLines[..<answerLineIndex]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let response = allLines[answerLineIndex...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !thinking.isEmpty {
                return (thinking, stripAnswerHeading(response))
            }
        }

        let paragraphs = paragraphs(in: trimmed)
        guard let firstParagraph = paragraphs.first, paragraphLooksLikeReasoning(firstParagraph) else { return nil }

        if isStreaming {
            if let answerLineIndex = firstExplicitAnswerLineIndex(in: trimmed.components(separatedBy: .newlines)) {
                let lines = trimmed.components(separatedBy: .newlines)
                let thinking = lines[..<answerLineIndex]
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let response = lines[answerLineIndex...]
                    .joined(separator: "\n")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !thinking.isEmpty {
                    return (thinking, stripAnswerHeading(response))
                }
            }

            return (trimmed, "")
        }

        if let responseParagraphIndex = firstResponseParagraphIndex(in: paragraphs) {
            let thinking = paragraphs[..<responseParagraphIndex]
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let response = paragraphs[responseParagraphIndex...]
                .joined(separator: "\n\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !thinking.isEmpty {
                return (thinking, stripAnswerHeading(response))
            }
        }

        let lines = trimmed.components(separatedBy: .newlines)
        if let answerLineIndex = lines.firstIndex(where: isAnswerSectionStart) {
            let thinking = lines[..<answerLineIndex]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let response = lines[answerLineIndex...]
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !thinking.isEmpty {
                return (thinking, stripAnswerHeading(response))
            }
        }

        return (trimmed, "")
    }

    private static func paragraphs(in text: String) -> [String] {
        var result: [String] = []
        var currentLines: [String] = []

        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                if !currentLines.isEmpty {
                    result.append(currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
                    currentLines.removeAll()
                }
            } else {
                currentLines.append(line)
            }
        }

        if !currentLines.isEmpty {
            result.append(currentLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return result
    }

    private static func firstExplicitAnswerLineIndex(in lines: [String]) -> Int? {
        lines.firstIndex(where: isAnswerSectionStart)
    }

    private static func firstResponseParagraphIndex(in paragraphs: [String]) -> Int? {
        guard paragraphs.count > 1 else { return nil }

        for index in paragraphs.indices.dropFirst() {
            let paragraph = paragraphs[index]
            if isAnswerSectionStart(paragraph) || !paragraphLooksLikeReasoning(paragraph) {
                return index
            }
        }

        return nil
    }

    private static func paragraphLooksLikeReasoning(_ text: String) -> Bool {
        let lowered = String(text.prefix(500)).lowercased()
        let directCues = [
            "thinking process",
            "reasoning process",
            "analyze the request",
            "identify key information",
            "the user is asking",
            "the user wants",
            "the question is",
            "the prompt is asking",
            "let me think",
            "let me structure",
            "let me break",
            "i need to think",
            "i need to reason",
            "i need to analyze",
            "wait, i need to",
            "the most important thing is to",
            "provide an accurate answer",
            "intent:",
            "constraints:",
            "need to satisfy",
            "plan:",
            "approach:"
        ]

        if directCues.contains(where: lowered.contains) {
            return true
        }

        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { return false }

        let structuredPrefixes = [
            "- ",
            "* ",
            "1.",
            "2.",
            "3.",
            "first,",
            "second,",
            "finally,"
        ]

        let structuredLineCount = lines.filter { line in
            structuredPrefixes.contains { line.hasPrefix($0) }
        }.count

        return structuredLineCount >= max(2, lines.count / 2)
    }

    private static func isAnswerSectionStart(_ candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let fullRange = NSRange(location: 0, length: (trimmed as NSString).length)
        return answerHeadingRegexes.contains { regex in
            regex.firstMatch(in: trimmed, options: [], range: fullRange) != nil
        }
    }

    private static func stripAnswerHeading(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let fullRange = NSRange(location: 0, length: (trimmed as NSString).length)
        for regex in answerHeadingRegexes {
            if let match = regex.firstMatch(in: trimmed, options: [], range: fullRange),
               match.range.location != NSNotFound {
                let nsText = trimmed as NSString
                let stripped = nsText.replacingCharacters(in: match.range, with: "")
                return stripped.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return trimmed
    }
}
