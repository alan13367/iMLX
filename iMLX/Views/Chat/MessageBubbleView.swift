import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MessageBubbleView: View {
    let message: ChatMessage
    let isStreaming: Bool
    @State private var showCopyFeedback = false
    @State private var isThinkingExpanded = false

    init(message: ChatMessage, isStreaming: Bool = false) {
        self.message = message
        self.isStreaming = isStreaming
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if let attachedImages = message.attachedImages, !attachedImages.isEmpty {
                    HStack {
                        if message.role == .user { Spacer(minLength: 0) }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(attachedImages, id: \.self) { imageData in
                                    if let uiImage = UIImage(data: imageData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 80, height: 80)
                                            .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }
                        }
                        if message.role == .assistant { Spacer(minLength: 0) }
                    }
                }

                if message.role == .assistant {
                    assistantContent
                } else {
                    bubble(text: message.content, foregroundStyle: .white)
                }
            }
            if message.role == .assistant { Spacer(minLength: 36) }
        }
        .overlay(copyFeedback, alignment: .bottom)
    }

    private var assistantContent: some View {
        let parsedContent = ParsedAssistantContent(message.content, isStreaming: isStreaming)

        return VStack(alignment: .leading, spacing: 8) {
            if let thinking = parsedContent.thinking, !thinking.isEmpty {
                DisclosureGroup(isExpanded: $isThinkingExpanded) {
                    assistantText(thinking)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } label: {
                    HStack(spacing: 8) {
                        Label("Thinking", systemImage: "brain.head.profile")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if isStreaming && parsedContent.response.isEmpty {
                            Text("Waiting for final response")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.fill.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }

            if !parsedContent.response.isEmpty {
                bubble(text: parsedContent.response, foregroundStyle: .primary)
            }

            if !isStreaming {
                VStack(alignment: .leading, spacing: 6) {
                    if let generationStats = message.generationStats {
                        StatsOverlayView(stats: generationStats, isLive: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    HStack {
                        Spacer()
                        copyButton(copyText: parsedContent.copyableText)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func bubble(text: String, foregroundStyle: Color) -> some View {
        assistantText(text)
            .foregroundStyle(foregroundStyle)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                message.role == .user
                    ? AnyShapeStyle(.blue)
                    : AnyShapeStyle(.fill.tertiary)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private func assistantText(_ text: String) -> some View {
        if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            Text(attributed)
                .font(.body)
                .tint(.blue)
        } else {
            Text(text)
                .font(.body)
        }
    }

    private func copyButton(copyText: String) -> some View {
        Button {
            UIPasteboard.general.setValue(copyText, forPasteboardType: UTType.plainText.identifier)
            showCopyFeedback = true
            Haptics.impactLight()
            Task {
                try? await Task.sleep(for: .seconds(1.5))
                showCopyFeedback = false
            }
        } label: {
            Image(systemName: showCopyFeedback ? "checkmark" : "doc.on.doc")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var copyFeedback: some View {
        Group {
            if showCopyFeedback {
                Text("Copied")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
    }
}

struct ParsedAssistantContent {
    let thinking: String?
    let response: String
    let copyableText: String

    init(_ rawContent: String, isStreaming: Bool = false) {
        let normalizedContent = Self.normalizedContent(rawContent)

        if let tagged = Self.parseTaggedThinking(normalizedContent) {
            self.thinking = tagged.thinking
            self.response = tagged.response
            self.copyableText = tagged.response.isEmpty ? tagged.thinking : tagged.response
            return
        }

        if let trailingTagged = Self.parseTrailingClosingTag(normalizedContent) {
            self.thinking = trailingTagged.thinking
            self.response = trailingTagged.response
            self.copyableText = trailingTagged.response.isEmpty ? trailingTagged.thinking : trailingTagged.response
            return
        }

        if let inferred = Self.parseInferredThinking(normalizedContent, isStreaming: isStreaming) {
            self.thinking = inferred.thinking
            self.response = inferred.response
            self.copyableText = inferred.response.isEmpty ? inferred.thinking : inferred.response
            return
        }

        let cleanedResponse = normalizedContent.trimmingCharacters(in: .whitespacesAndNewlines)
        self.thinking = nil
        self.response = cleanedResponse
        self.copyableText = cleanedResponse
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
            "context:"
        ]
        if directCues.contains(where: lowered.contains) {
            return true
        }

        return looksLikePlanningList(text)
    }

    private static func looksLikePlanningList(_ text: String) -> Bool {
        let planningVerbs = [
            "state",
            "provide",
            "note",
            "give",
            "explain",
            "compare",
            "address",
            "outline",
            "summarize",
            "mention"
        ]

        let planningLineCount = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { line in
                let numberedLine = line.range(of: #"^\d+[\.\)]\s+"#, options: .regularExpression) != nil
                let bulletedLine = line.hasPrefix("- ") || line.hasPrefix("* ")
                guard numberedLine || bulletedLine else { return false }
                return planningVerbs.contains { verb in
                    line.contains(" \(verb) ") || line.hasSuffix(" \(verb)") || line.hasPrefix("\(verb) ")
                }
            }
            .count

        return planningLineCount >= 2
    }

    private static func isAnswerSectionStart(_ line: String) -> Bool {
        let normalized = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "*", with: "")
        guard !normalized.isEmpty else { return false }

        let headings = [
            "final answer:",
            "final answer",
            "suggested answer:",
            "suggested answer",
            "answer:",
            "response:"
        ]

        return headings.contains { normalized.hasPrefix($0) }
    }

    private static func stripAnswerHeading(_ response: String) -> String {
        var cleaned = response.trimmingCharacters(in: .whitespacesAndNewlines)
        let headingPatterns = [
            "^\\*{0,2}final answer:?\\*{0,2}\\s*",
            "^\\*{0,2}suggested answer:?\\*{0,2}\\s*",
            "^\\*{0,2}answer:?\\*{0,2}\\s*",
            "^\\*{0,2}response:?\\*{0,2}\\s*"
        ]

        for pattern in headingPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
                cleaned = regex.stringByReplacingMatches(in: cleaned, options: [], range: range, withTemplate: "")
            }
        }

        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
