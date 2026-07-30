import SwiftUI

/// Top-level message row. Renders a `ChatMessage` (and an optional in-flight
/// streaming overlay) using the small per-purpose component library.
///
/// This is the only view chat list code should instantiate per message. It
/// preserves the previous architecture (immutable `ChatMessage`, parsed
/// content, optional thinking expansion binding for pinned-header support)
/// while replacing the visual implementation.
struct MessageRow: View, Equatable {
    let message: ChatMessage
    let isStreaming: Bool
    let parsedAssistantContent: ParsedAssistantContent?
    let deliveryState: MessageDeliveryState
    let thinkingExpansion: Binding<Bool>?
    let onCopy: (String) -> Void
    let onRetry: (() -> Void)?
    let onOpenSourceURL: (URL?) -> Void

    @State private var localThinkingExpanded: Bool = false

    init(
        message: ChatMessage,
        isStreaming: Bool = false,
        parsedAssistantContent: ParsedAssistantContent? = nil,
        deliveryState: MessageDeliveryState = .sent,
        thinkingExpansion: Binding<Bool>? = nil,
        onCopy: @escaping (String) -> Void = { _ in },
        onRetry: (() -> Void)? = nil,
        onOpenSourceURL: @escaping (URL?) -> Void = { _ in }
    ) {
        self.message = message
        self.isStreaming = isStreaming
        self.parsedAssistantContent = parsedAssistantContent
        self.deliveryState = deliveryState
        self.thinkingExpansion = thinkingExpansion
        self.onCopy = onCopy
        self.onRetry = onRetry
        self.onOpenSourceURL = onOpenSourceURL
    }

    static func == (lhs: MessageRow, rhs: MessageRow) -> Bool {
        lhs.message == rhs.message
            && lhs.isStreaming == rhs.isStreaming
            && lhs.parsedAssistantContent == rhs.parsedAssistantContent
            && lhs.deliveryState == rhs.deliveryState
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if message.role == .user {
                Spacer(minLength: 56)
            }

            VStack(alignment: alignment, spacing: 8) {
                if hasAttachments {
                    MessageAttachments(
                        role: message.role,
                        attachedDocuments: message.attachedDocuments ?? [],
                        attachedImages: message.attachedImages ?? []
                    )
                }

                if message.role == .assistant {
                    assistantContent
                } else if !message.content.isEmpty {
                    UserMessageBubble(
                        text: message.content,
                        deliveryState: deliveryState,
                        onRetry: onRetry
                    )
                    .contextMenu { userContextMenu }
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 24)
            }
        }
    }

    // MARK: - Assistant body

    private var assistantContent: some View {
        VStack(alignment: .leading, spacing: ChatMetrics.messageSectionSpacing) {
            ForEach(Array(agenticSegments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .tools(let phases):
                    MessageActivityView(
                        toolPhases: phases,
                        thinking: nil,
                        isStreaming: false,
                        isWaitingForAnswer: false,
                        isThinkingExpanded: .constant(false)
                    )
                case .prose(let text, let streaming):
                    AssistantMessageText(
                        text: text,
                        isStreaming: streaming,
                        streamID: message.id,
                        linkPhoneNumbers: shouldLinkPhoneNumbers
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        if !streaming {
                            Button {
                                onCopy(text)
                            } label: {
                                Label(String.appLocalized("message.copy"), systemImage: "doc.on.doc")
                            }
                            ShareLink(item: text.isEmpty ? shareableText : text) {
                                Label(String.appLocalized("message.share"), systemImage: "square.and.arrow.up")
                            }
                        }
                    }
                case .thinking(let text):
                    MessageActivityView(
                        toolPhases: [],
                        thinking: text,
                        isStreaming: isStreaming,
                        isWaitingForAnswer: resolvedParsed.response.isEmpty,
                        isThinkingExpanded: thinkingBinding
                    )
                }
            }

            if !isStreaming {
                if let sources = message.retrievedSources, !sources.isEmpty {
                    MessageSourcesPanel(sources: sources, openSource: onOpenSourceURL)
                }
                if let stats = message.generationStats {
                    MessageStatsBar(stats: stats)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private enum AgenticSegment: Equatable {
        case tools([MessageActivityToolPhase])
        case prose(String, isStreaming: Bool)
        case thinking(String)
    }

    /// Agentic layout: tool → assistant prose → tool → … → final answer.
    private var agenticSegments: [AgenticSegment] {
        var segments: [AgenticSegment] = []
        let traces = isStreaming ? [] : (message.toolTraces ?? [])

        for trace in traces {
            segments.append(.tools([.completed(trace)]))
            if let note = trace.followUpReasoning, !note.isEmpty {
                segments.append(.prose(note, isStreaming: false))
            }
        }

        if let thinking = resolvedParsed.thinking, !thinking.isEmpty {
            segments.append(.thinking(thinking))
        }

        if !resolvedParsed.response.isEmpty || isStreaming {
            segments.append(.prose(resolvedParsed.response, isStreaming: isStreaming))
        }

        return segments
    }

    // MARK: - Context menus

    @ViewBuilder
    private var userContextMenu: some View {
        Button {
            onCopy(message.content)
        } label: {
            Label(String.appLocalized("message.copy"), systemImage: "doc.on.doc")
        }
        ShareLink(item: shareableText) {
            Label(String.appLocalized("message.share"), systemImage: "square.and.arrow.up")
        }
        if deliveryState == .failed, let onRetry {
            Button {
                onRetry()
            } label: {
                Label(String.appLocalized("message.retry"), systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - Derived

    private var alignment: HorizontalAlignment {
        message.role == .user ? .trailing : .leading
    }

    private var hasAttachments: Bool {
        (message.attachedDocuments?.isEmpty == false) || (message.attachedImages?.isEmpty == false)
    }

    private var resolvedParsed: ParsedAssistantContent {
        parsedAssistantContent ?? ParsedAssistantContent(message.content, isStreaming: isStreaming)
    }

    private var thinkingBinding: Binding<Bool> {
        thinkingExpansion ?? Binding(get: { localThinkingExpanded }, set: { localThinkingExpanded = $0 })
    }

    private var shareableText: String {
        if message.role == .assistant {
            var parts: [String] = []
            for trace in message.toolTraces ?? [] {
                if let note = trace.followUpReasoning, !note.isEmpty {
                    parts.append(note)
                }
            }
            let finalText = resolvedParsed.copyableText
            if !finalText.isEmpty {
                parts.append(finalText)
            }
            return parts.joined(separator: "\n\n")
        }
        return message.content
    }

    private var shouldLinkPhoneNumbers: Bool {
        !isStreaming
            && (message.toolTraces ?? []).contains { trace in
                trace.toolName == "contacts_lookup" && trace.success
            }
    }
}

#Preview("Assistant message") {
    MessageRow(
        message: ChatMessage(
            role: .assistant,
            content: "Here is a **formatted** answer with a source-backed summary."
        )
    )
    .padding()
}

#Preview("User message") {
    MessageRow(
        message: ChatMessage(
            role: .user,
            content: "Summarize my notes from today."
        )
    )
    .padding()
}
