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
    let showsThinkingHeader: Bool
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
        showsThinkingHeader: Bool = true,
        thinkingExpansion: Binding<Bool>? = nil,
        onCopy: @escaping (String) -> Void = { _ in },
        onRetry: (() -> Void)? = nil,
        onOpenSourceURL: @escaping (URL?) -> Void = { _ in }
    ) {
        self.message = message
        self.isStreaming = isStreaming
        self.parsedAssistantContent = parsedAssistantContent
        self.deliveryState = deliveryState
        self.showsThinkingHeader = showsThinkingHeader
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
            && lhs.showsThinkingHeader == rhs.showsThinkingHeader
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
        VStack(alignment: .leading, spacing: 10) {
            if !isStreaming, let trace = message.toolTrace {
                MessageToolCallCard(phase: .completed(trace))
            }

            if let thinking = resolvedParsed.thinking, !thinking.isEmpty {
                MessageThinkingPanel(
                    text: thinking,
                    isStreaming: isStreaming,
                    isWaitingForAnswer: resolvedParsed.response.isEmpty,
                    mode: showsThinkingHeader ? .inline : .bodyOnly,
                    isExpanded: thinkingBinding
                )
            }

            if !resolvedParsed.response.isEmpty || isStreaming {
                AssistantMessageText(
                    text: resolvedParsed.response,
                    isStreaming: isStreaming,
                    streamID: message.id,
                    linkPhoneNumbers: shouldLinkPhoneNumbers
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .contextMenu { assistantContextMenu }
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

    // MARK: - Context menus

    @ViewBuilder
    private var assistantContextMenu: some View {
        if !isStreaming {
            Button {
                onCopy(resolvedParsed.copyableText)
            } label: {
                Label(String.appLocalized("message.copy"), systemImage: "doc.on.doc")
            }
            ShareLink(item: shareableText) {
                Label(String.appLocalized("message.share"), systemImage: "square.and.arrow.up")
            }
        }
    }

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
            return resolvedParsed.copyableText
        }
        return message.content
    }

    private var shouldLinkPhoneNumbers: Bool {
        !isStreaming
            && message.toolTrace?.toolName == "contacts_lookup"
            && message.toolTrace?.success == true
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
