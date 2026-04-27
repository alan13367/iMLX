import Foundation
import SwiftUI

/// Back-compatibility wrapper around `MessageRow`.
///
/// Existing call sites that referenced `MessageBubbleView` keep compiling.
/// New code should use `MessageRow` directly.
struct MessageBubbleView: View, Equatable {
    let message: ChatMessage
    let isStreaming: Bool
    let parsedAssistantContent: ParsedAssistantContent?
    private let thinkingExpansion: Binding<Bool>?
    private let showsThinkingHeader: Bool
    private let deliveryState: MessageDeliveryState
    private let onCopy: (String) -> Void
    private let onRetry: (() -> Void)?
    private let onOpenSourceURL: (URL?) -> Void

    init(
        message: ChatMessage,
        isStreaming: Bool = false,
        parsedAssistantContent: ParsedAssistantContent? = nil,
        thinkingExpansion: Binding<Bool>? = nil,
        showsThinkingHeader: Bool = true,
        deliveryState: MessageDeliveryState = .sent,
        onCopy: @escaping (String) -> Void = { _ in },
        onRetry: (() -> Void)? = nil,
        onOpenSourceURL: @escaping (URL?) -> Void = { _ in }
    ) {
        self.message = message
        self.isStreaming = isStreaming
        self.parsedAssistantContent = parsedAssistantContent
        self.thinkingExpansion = thinkingExpansion
        self.showsThinkingHeader = showsThinkingHeader
        self.deliveryState = deliveryState
        self.onCopy = onCopy
        self.onRetry = onRetry
        self.onOpenSourceURL = onOpenSourceURL
    }

    static func == (lhs: MessageBubbleView, rhs: MessageBubbleView) -> Bool {
        lhs.message == rhs.message
            && lhs.isStreaming == rhs.isStreaming
            && lhs.parsedAssistantContent == rhs.parsedAssistantContent
            && lhs.deliveryState == rhs.deliveryState
            && lhs.showsThinkingHeader == rhs.showsThinkingHeader
    }

    var body: some View {
        MessageRow(
            message: message,
            isStreaming: isStreaming,
            parsedAssistantContent: parsedAssistantContent,
            deliveryState: deliveryState,
            showsThinkingHeader: showsThinkingHeader,
            thinkingExpansion: thinkingExpansion,
            onCopy: onCopy,
            onRetry: onRetry,
            onOpenSourceURL: onOpenSourceURL
        )
    }
}
