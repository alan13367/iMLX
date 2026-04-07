import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MessageBubbleView: View {
    let message: ChatMessage
    let isStreaming: Bool
    @State private var showCopyFeedback = false
    @State private var isThinkingExpanded = false
    @State private var userBubbleWidth: CGFloat = 0

    init(message: ChatMessage, isStreaming: Bool = false) {
        self.message = message
        self.isStreaming = isStreaming
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                attachmentStrip

                if message.role == .assistant {
                    assistantContent
                } else if !message.content.isEmpty {
                    bubble(text: message.content, foregroundStyle: .white, measureWidth: true)
                }
            }
            if message.role == .assistant { Spacer(minLength: 36) }
        }
        .overlay(copyFeedback, alignment: .bottom)
    }

    @ViewBuilder
    private var attachmentStrip: some View {
        if hasAttachments {
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
                if let attachedDocuments = message.attachedDocuments, !attachedDocuments.isEmpty {
                    documentAttachmentStrip(attachedDocuments)
                }
                if let attachedImages = message.attachedImages, !attachedImages.isEmpty {
                    imageAttachmentStrip(attachedImages)
                }
            }
        }
    }

    @ViewBuilder
    private func imageAttachmentStrip(_ attachedImages: [Data]) -> some View {
        if message.role == .user, attachedImages.count == 1 {
            attachmentStripContent(attachedImages)
                .frame(width: max(userBubbleWidth, 80), alignment: .center)
                .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            HStack {
                if message.role == .assistant {
                    attachmentStripContent(attachedImages)
                    Spacer(minLength: 0)
                } else {
                    Spacer(minLength: 0)
                    attachmentStripContent(attachedImages)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func attachmentStripContent(_ attachedImages: [Data]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachedImages.enumerated()), id: \.offset) { _, imageData in
                    if let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 80, height: 80)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        }
        .frame(maxWidth: 220)
    }

    private func documentAttachmentStrip(_ attachedDocuments: [ConversationDocumentReference]) -> some View {
        HStack {
            if message.role == .assistant {
                documentAttachmentContent(attachedDocuments)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
                documentAttachmentContent(attachedDocuments)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func documentAttachmentContent(_ attachedDocuments: [ConversationDocumentReference]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachedDocuments) { document in
                    HStack(spacing: 8) {
                        Image(systemName: iconName(for: document.kind))
                            .foregroundStyle(message.role == .user ? .white : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.displayName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(document.kind.displayName)
                                .font(.caption2)
                                .foregroundStyle(message.role == .user ? .white.opacity(0.8) : .secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(message.role == .user ? Color.blue.opacity(0.82) : Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
        }
        .frame(maxWidth: 260)
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
                        Label(String.appLocalized("message.thinking"), systemImage: "brain.head.profile")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if isStreaming && parsedContent.response.isEmpty {
                            Text(String.appLocalized("message.waiting_final"))
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
                HStack(alignment: .bottom, spacing: 8) {
                    bubble(text: parsedContent.response, foregroundStyle: .primary)
                    if !isStreaming {
                        copyButton(copyText: parsedContent.copyableText)
                            .padding(.bottom, 4)
                    }
                }
            }

            if !isStreaming {
                VStack(alignment: .leading, spacing: 6) {
                    if let sources = message.retrievedSources, !sources.isEmpty {
                        sourcesSection(sources)
                    }
                    if let generationStats = message.generationStats {
                        StatsOverlayView(stats: generationStats, isLive: false)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if parsedContent.response.isEmpty {
                        HStack {
                            Spacer()
                            copyButton(copyText: parsedContent.copyableText)
                        }
                    }
                }
            }
        }
    }

    private func sourcesSection(_ sources: [RetrievedDocumentSource]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(String.appLocalized("message.sources"), systemImage: "doc.text.magnifyingglass")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(sources) { source in
                VStack(alignment: .leading, spacing: 4) {
                    Text(sourceTitle(for: source))
                        .font(.caption.weight(.semibold))
                    Text(source.excerpt)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.fill.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    @ViewBuilder
    private func bubble(text: String, foregroundStyle: Color, measureWidth: Bool = false) -> some View {
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
            .background {
                if measureWidth {
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear {
                                userBubbleWidth = proxy.size.width
                            }
                            .onChange(of: proxy.size.width) {
                                userBubbleWidth = proxy.size.width
                            }
                    }
                }
            }
    }

    @ViewBuilder
    private func assistantText(_ text: String) -> some View {
        if isStreaming {
            Text(text)
                .font(.body)
        } else if let attributed = try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
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
            Task { @MainActor in
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
        .frame(minWidth: 44, minHeight: 44)
        .accessibilityLabel("Copy response")
    }

    private var copyFeedback: some View {
        Group {
            if showCopyFeedback {
                Text(String.appLocalized("message.copied"))
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
        }
    }

    private var hasAttachments: Bool {
        (message.attachedDocuments?.isEmpty == false) || (message.attachedImages?.isEmpty == false)
    }

    private func iconName(for kind: ConversationDocumentKind) -> String {
        switch kind {
        case .pdf:
            "doc.richtext"
        case .csv:
            "tablecells"
        case .text:
            "doc.text"
        }
    }

    private func sourceTitle(for source: RetrievedDocumentSource) -> String {
        if let location = source.location, !location.isEmpty {
            return "\(source.documentName) | \(location)"
        }
        return source.documentName
    }
}

struct ParsedAssistantContent {
    let thinking: String?
    let response: String
    let copyableText: String

    init(_ rawContent: String, isStreaming: Bool = false) {
        let normalizedContent = Self.normalizedContent(rawContent)

        if let tagged = Self.parseTaggedThinking(normalizedContent) {
            let cleanedResponse = Self.stripAnswerHeading(tagged.response)
            self.thinking = tagged.thinking
            self.response = cleanedResponse
            self.copyableText = cleanedResponse.isEmpty ? tagged.thinking : cleanedResponse
            return
        }

        if let trailingTagged = Self.parseTrailingClosingTag(normalizedContent) {
            let cleanedResponse = Self.stripAnswerHeading(trailingTagged.response)
            self.thinking = trailingTagged.thinking
            self.response = cleanedResponse
            self.copyableText = cleanedResponse.isEmpty ? trailingTagged.thinking : cleanedResponse
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
        var normalized = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: #"^\s*#{1,6}\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*(?:>\s*)+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*[-*]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"^\s*\d+[\.)]\s+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "`", with: "")
            .lowercased()

        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)
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
            "^(?:\\s*#{1,6}\\s*)?(?:\\*{0,2}|_{0,2}|`{0,1})final answer(?:\\s*[:：])?(?:\\*{0,2}|_{0,2}|`{0,1})\\s*",
            "^(?:\\s*#{1,6}\\s*)?(?:\\*{0,2}|_{0,2}|`{0,1})suggested answer(?:\\s*[:：])?(?:\\*{0,2}|_{0,2}|`{0,1})\\s*",
            "^(?:\\s*#{1,6}\\s*)?(?:\\*{0,2}|_{0,2}|`{0,1})answer(?:\\s*[:：])?(?:\\*{0,2}|_{0,2}|`{0,1})\\s*",
            "^(?:\\s*#{1,6}\\s*)?(?:\\*{0,2}|_{0,2}|`{0,1})response(?:\\s*[:：])?(?:\\*{0,2}|_{0,2}|`{0,1})\\s*"
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
