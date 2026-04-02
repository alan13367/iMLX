import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct MessageBubbleView: View {
    let message: ChatMessage
    let isStreaming: Bool
    @State private var showCopyFeedback = false

    init(message: ChatMessage, isStreaming: Bool = false) {
        self.message = message
        self.isStreaming = isStreaming
    }

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 60) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
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
        let parsedContent = ParsedAssistantContent(message.content)

        return VStack(alignment: .leading, spacing: 8) {
            if let thinking = parsedContent.thinking, !thinking.isEmpty {
                DisclosureGroup {
                    assistantText(thinking)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                } label: {
                    Label("Thinking", systemImage: "brain.head.profile")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
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

private struct ParsedAssistantContent {
    let thinking: String?
    let response: String
    let copyableText: String

    init(_ rawContent: String) {
        if let openRange = rawContent.range(of: "<think>") {
            if let closeRange = rawContent.range(of: "</think>") {
                let thinkingSlice = rawContent[openRange.upperBound..<closeRange.lowerBound]
                let afterThinking = rawContent[closeRange.upperBound...]
                let cleanedThinking = thinkingSlice.trimmingCharacters(in: .whitespacesAndNewlines)
                let cleanedResponse = afterThinking.trimmingCharacters(in: .whitespacesAndNewlines)
                self.thinking = cleanedThinking.isEmpty ? nil : cleanedThinking
                self.response = cleanedResponse
                self.copyableText = cleanedResponse.isEmpty ? cleanedThinking : cleanedResponse
            } else {
                let thinkingSlice = rawContent[openRange.upperBound...]
                let cleanedThinking = thinkingSlice.trimmingCharacters(in: .whitespacesAndNewlines)
                self.thinking = cleanedThinking.isEmpty ? nil : cleanedThinking
                self.response = ""
                self.copyableText = cleanedThinking
            }
        } else {
            let cleanedResponse = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
            self.thinking = nil
            self.response = cleanedResponse
            self.copyableText = cleanedResponse
        }
    }
}
