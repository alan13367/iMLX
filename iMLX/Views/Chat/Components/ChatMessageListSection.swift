import SwiftUI

struct ChatMessageListSection: View {
    let messages: [ChatMessage]
    let currentResponse: String
    let isGenerating: Bool
    let parsedResponse: ParsedAssistantContent
    let toolActivityStatus: ToolActivityStatus?
    let currentToolTrace: ToolCallTrace?
    let lastFailedUserMessageId: UUID?
    let conversationResetKey: UUID
    let onTranscriptTap: () -> Void
    let onCopy: (String) -> Void
    let onRetry: () -> Void
    let onOpenSourceURL: (URL?) -> Void

    @State private var streamingScrollTask: Task<Void, Never>?
    @State private var streamingScrollTaskToken: UUID?
    @State private var streamingAutoscrollEnabled = true
    @State private var canScrollToBottom = false
    @State private var scrollPinnedToBottom = true
    @State private var isStreamingThinkingExpanded = true
    @State private var streamingMessageId = UUID()
    @State private var streamingMessageTimestamp = Date()
    @State private var hapticSelectionTrigger = 0

    private var deliveryContext: MessageDeliveryContext {
        MessageDeliveryContext(
            isGenerating: isGenerating,
            hasStartedStreaming: !currentResponse.isEmpty,
            lastFailedUserMessageId: lastFailedUserMessageId,
            lastUserMessageId: messages.last(where: { $0.role == .user })?.id
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 18) {
                        ForEach(messages) { message in
                            MessageRow(
                                message: message,
                                deliveryState: deliveryContext.state(for: message.id),
                                onCopy: onCopy,
                                onRetry: lastFailedUserMessageId == message.id ? onRetry : nil,
                                onOpenSourceURL: onOpenSourceURL
                            )
                            .equatable()
                            .id(message.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        if let liveToolPhase {
                            MessageActivityView(
                                toolPhase: liveToolPhase,
                                thinking: nil,
                                isStreaming: true,
                                isWaitingForAnswer: true,
                                isThinkingExpanded: .constant(false)
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("toolActivity")
                            .transition(.opacity)
                        }

                        if !currentResponse.isEmpty {
                            streamingMessageBubble
                                .id("streaming")
                                .transition(.opacity)
                        }

                        Color.clear
                            .frame(height: 1)
                            .id("chatBottomAnchor")
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)
                }
                .simultaneousGesture(
                    TapGesture().onEnded(onTranscriptTap)
                )
                .onScrollGeometryChange(for: ChatScrollState.self, of: { geometry in
                    let contentHeight = geometry.contentSize.height
                    let remainingBelowViewport = max(0, contentHeight - geometry.visibleRect.maxY)
                    let canScrollToBottom = remainingBelowViewport > 56
                    let pinned = remainingBelowViewport <= 32
                    return ChatScrollState(canScrollToBottom: canScrollToBottom, isPinnedToBottom: pinned)
                }, action: { _, state in
                    if canScrollToBottom != state.canScrollToBottom {
                        canScrollToBottom = state.canScrollToBottom
                    }
                    if scrollPinnedToBottom != state.isPinnedToBottom {
                        scrollPinnedToBottom = state.isPinnedToBottom
                    }
                    guard shouldResumeAutoscrollWhenPinned(state) else { return }
                    resumeAutoscroll(using: proxy, animated: false)
                })
                .onScrollPhaseChange { _, newPhase in
                    if newPhase == .idle {
                        guard shouldResumeAutoscrollWhenPinned() else { return }
                        resumeAutoscroll(using: proxy, animated: false)
                        return
                    }
                    guard newPhase == .tracking || newPhase == .interacting else { return }
                    cancelScheduledAutoscroll()
                    guard isGenerating else { return }
                    guard streamingAutoscrollEnabled else { return }
                    streamingAutoscrollEnabled = false
                }
                .task(id: conversationResetKey) {
                    streamingAutoscrollEnabled = true
                    canScrollToBottom = false
                    scrollPinnedToBottom = true
                }
                .task(id: messages.count) {
                    guard streamingAutoscrollEnabled else { return }
                    scheduleAutoscroll(using: proxy)
                }
                .task(id: streamingAutoscrollKey) {
                    guard streamingAutoscrollEnabled else { return }
                    guard isGenerating else { return }
                    guard !currentResponse.isEmpty else { return }
                    scheduleAutoscroll(using: proxy)
                }
                .task(id: isGenerating) {
                    if isGenerating {
                        isStreamingThinkingExpanded = true
                        streamingMessageId = UUID()
                        streamingMessageTimestamp = Date()
                        return
                    }
                    guard streamingAutoscrollEnabled else { return }
                    guard !messages.isEmpty else { return }
                    scheduleAutoscroll(using: proxy, repeatAfterLayoutChange: true)
                }
                .onDisappear {
                    cancelScheduledAutoscroll()
                }

                scrollToBottomOverlay(using: proxy)
                    .opacity(isScrollToBottomVisible ? 1 : 0)
                    .allowsHitTesting(isScrollToBottomVisible)
                    .animation(.easeInOut(duration: 0.18), value: isScrollToBottomVisible)
            }
        }
        .sensoryFeedback(.selection, trigger: hapticSelectionTrigger)
    }

    private var streamingMessageBubble: some View {
        MessageRow(
            message: ChatMessage(
                id: streamingMessageId,
                role: .assistant,
                content: currentResponse,
                timestamp: streamingMessageTimestamp
            ),
            isStreaming: true,
            parsedAssistantContent: parsedResponse,
            thinkingExpansion: $isStreamingThinkingExpanded,
            onCopy: onCopy
        )
    }

    /// In-flight tool activity. Falls back to the just-completed trace so the
    /// summary line stays visible while the answer streams in behind it.
    private var liveToolPhase: MessageActivityToolPhase? {
        if let toolActivityStatus {
            switch toolActivityStatus {
            case .planning:
                return .planning
            case .running(let toolName, let displayInput):
                return .running(toolName: toolName, displayInput: displayInput)
            }
        }
        if let currentToolTrace, isGenerating {
            return .completed(currentToolTrace)
        }
        return nil
    }

    private var streamingAutoscrollKey: Int {
        guard !currentResponse.isEmpty else { return 0 }
        let visibleCharacterCount = parsedResponse.response.isEmpty
            ? currentResponse.count
            : parsedResponse.response.count
        let stride = visibleCharacterCount >= Constants.UI.streamingLongResponseCharacterThreshold
            ? Constants.UI.streamingAutoscrollLongCharacterStride
            : Constants.UI.streamingAutoscrollCharacterStride
        return 1 + visibleCharacterCount / stride
    }

    private var isScrollToBottomVisible: Bool {
        canScrollToBottom && (!scrollPinnedToBottom || !streamingAutoscrollEnabled)
    }

    private var finalizedScrollTargetMessageId: UUID? {
        guard !isGenerating, currentResponse.isEmpty else { return nil }
        return messages.last?.id
    }

    @ViewBuilder
    private func scrollToBottomOverlay(using proxy: ScrollViewProxy) -> some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Button {
                jumpToBottomFromButton(using: proxy)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .liquidGlassSurface(
                        in: Circle(),
                        fallback: AnyShapeStyle(.regularMaterial),
                        interactive: true
                    )
                    .frame(width: 44, height: 44)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Scroll to bottom")
        }
        .padding(.trailing, 14)
        .padding(.bottom, 10)
    }

    private func jumpToBottomFromButton(using proxy: ScrollViewProxy) {
        hapticSelectionTrigger += 1
        cancelScheduledAutoscroll()
        streamingAutoscrollEnabled = true
        scrollToBottom(using: proxy, animated: true)
    }

    private func resumeAutoscroll(using proxy: ScrollViewProxy) {
        resumeAutoscroll(using: proxy, animated: true)
    }

    private func resumeAutoscroll(using proxy: ScrollViewProxy, animated: Bool) {
        cancelScheduledAutoscroll()
        streamingAutoscrollEnabled = true
        scrollToBottom(using: proxy, animated: animated)
        scheduleAutoscroll(using: proxy)
    }

    private func shouldResumeAutoscrollWhenPinned(_ state: ChatScrollState? = nil) -> Bool {
        guard isGenerating else { return false }
        guard !currentResponse.isEmpty else { return false }
        guard !streamingAutoscrollEnabled else { return false }
        return state?.isPinnedToBottom ?? scrollPinnedToBottom
    }

    private func scheduleAutoscroll(using proxy: ScrollViewProxy, repeatAfterLayoutChange: Bool = false) {
        streamingScrollTask?.cancel()
        let taskToken = UUID()
        streamingScrollTaskToken = taskToken
        streamingScrollTask = Task { @MainActor in
            defer {
                if streamingScrollTaskToken == taskToken {
                    streamingScrollTask = nil
                    streamingScrollTaskToken = nil
                }
            }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            scrollToBottom(using: proxy)
            guard repeatAfterLayoutChange else { return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            scrollToBottom(using: proxy)
        }
    }

    private func cancelScheduledAutoscroll() {
        streamingScrollTask?.cancel()
        streamingScrollTask = nil
        streamingScrollTaskToken = nil
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        scrollToBottom(using: proxy, animated: true)
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                scrollToResolvedBottomTarget(using: proxy)
            }
        } else {
            scrollToResolvedBottomTarget(using: proxy)
        }
    }

    private func scrollToResolvedBottomTarget(using proxy: ScrollViewProxy) {
        if let finalizedScrollTargetMessageId {
            proxy.scrollTo(finalizedScrollTargetMessageId, anchor: .bottom)
        } else {
            proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
        }
    }

}
