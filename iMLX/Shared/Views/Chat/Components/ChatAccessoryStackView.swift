import SwiftUI

struct ChatAccessoryStackState {
    let horizontalSizeClass: UserInterfaceSizeClass?
    let errorMessage: String?
    let toolNotice: String?
    let isModelLoading: Bool
    let selectedModelDisplayName: String?
    let isGenerating: Bool
    let memoryNotice: ChatMemoryNotice?
    let pendingDocuments: [ConversationDocumentReference]
    let pendingImages: [ChatAttachmentImage]
    let canUseThinking: Bool
    let isThinkingEnabled: Bool
    let canSendMessage: Bool
    let canPresentLiveVoice: Bool
    let canUseVision: Bool
    let isWebSearchEnabled: Bool

    func composerState(maxWidth: CGFloat) -> ChatComposerState {
        ChatComposerState(
            maxWidth: maxWidth,
            pendingDocuments: pendingDocuments,
            pendingImages: pendingImages,
            canUseThinking: canUseThinking,
            isThinkingEnabled: isThinkingEnabled,
            isGenerating: isGenerating,
            canSendMessage: canSendMessage,
            canPresentLiveVoice: canPresentLiveVoice,
            canUseVision: canUseVision,
            isWebSearchEnabled: isWebSearchEnabled
        )
    }
}

struct ChatAccessoryStackActions {
    let dismissError: () -> Void
    let dismissToolNotice: () -> Void
    let dismissMemoryNotice: () -> Void
    let openMemoryLibrary: () -> Void
    let composer: ChatComposerActions
}

struct ChatAccessoryStackView: View {
    let state: ChatAccessoryStackState
    let actions: ChatAccessoryStackActions
    @Binding var inputText: String
    @FocusState.Binding var isInputFocused: Bool

    private var maxWidth: CGFloat {
        state.horizontalSizeClass == .regular ? 760 : .infinity
    }

    var body: some View {
        VStack(spacing: 8) {
            if let errorMessage = state.errorMessage {
                ChatNoticeBanner(
                    style: .error(isOOM: isOOMError(errorMessage)),
                    message: isOOMError(errorMessage) ? String.appLocalized("chat.oom_suggestion") : errorMessage,
                    title: isOOMError(errorMessage) ? String.appLocalized("chat.out_of_memory") : nil,
                    onDismiss: actions.dismissError
                )
                .frame(maxWidth: maxWidth)
            }

            if let toolNotice = state.toolNotice {
                ChatNoticeBanner(
                    style: .info,
                    message: toolNotice,
                    title: nil,
                    onDismiss: actions.dismissToolNotice
                )
                .frame(maxWidth: maxWidth)
            }

            if state.isModelLoading {
                ChatStatusLine(
                    title: String.appLocalized("chat.loading_model_title"),
                    detail: state.selectedModelDisplayName ?? String.appLocalized("chat.preparing_model")
                )
                .frame(maxWidth: maxWidth)
            } else if state.isGenerating {
                ChatStatusLine(
                    title: String.appLocalized("chat.generating"),
                    detail: nil
                )
                .frame(maxWidth: maxWidth)
            }

            if let memoryNotice = state.memoryNotice {
                ChatMemoryNoticeView(
                    notice: memoryNotice,
                    title: memoryNoticeTitle(for: memoryNotice),
                    onOpenMemoryLibrary: actions.openMemoryLibrary,
                    onDismiss: actions.dismissMemoryNotice
                )
                .frame(maxWidth: maxWidth)
            }

            ChatComposerSection(
                state: state.composerState(maxWidth: maxWidth),
                actions: actions.composer,
                inputText: $inputText,
                isInputFocused: $isInputFocused
            )
        }
        .padding(.top, 8)
        .padding(.bottom, PlatformChatLayout.accessoryBottomPadding)
    }

    private func isOOMError(_ message: String) -> Bool {
        let lower = message.lowercased()
        if lower.contains("memory") || lower.contains("memoria") || lower.contains("内存") {
            return true
        }
        return lower.contains("low memory") || lower.contains("poca memoria") || lower.contains("内存偏低")
    }

    private func memoryNoticeTitle(for notice: ChatMemoryNotice) -> String {
        switch notice.kind {
        case .saved, .forgotten:
            "Memory"
        case .pending:
            String.appLocalized("memory.section.pending")
        }
    }
}
