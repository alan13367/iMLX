import SwiftUI

struct ChatComposerState {
    let maxWidth: CGFloat
    let pendingDocuments: [ConversationDocumentReference]
    let pendingImages: [ChatAttachmentImage]
    let canUseThinking: Bool
    let isThinkingEnabled: Bool
    let isGenerating: Bool
    let canSendMessage: Bool
    let canPresentLiveVoice: Bool
    let canUseVision: Bool
    let isWebSearchEnabled: Bool
}

struct ChatComposerActions {
    let removeDocument: (ConversationDocumentReference) -> Void
    let removePendingImage: (UUID) -> Void
    let openAttachmentImporter: () -> Void
    let openCamera: () -> Void
    let openPhotoLibrary: () -> Void
    let toggleThinking: () -> Void
    let voiceTap: () -> Void
    let send: () -> Void
    let stop: () -> Void
    let toggleWebSearch: () -> Void
}

struct ChatComposerSection: View {
    let state: ChatComposerState
    let actions: ChatComposerActions
    @Binding var inputText: String
    @FocusState.Binding var isInputFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !state.pendingDocuments.isEmpty {
                ChatPendingDocumentStrip(
                    pendingDocuments: state.pendingDocuments,
                    onRemoveDocument: actions.removeDocument,
                    iconName: iconName(for:)
                )
            }

            if !state.pendingImages.isEmpty {
                ChatPendingImageStrip(
                    pendingImages: state.pendingImages,
                    onRemoveImage: actions.removePendingImage
                )
            }

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button(action: actions.openAttachmentImporter) {
                        Label(String.appLocalized("chat.import_document"), systemImage: "doc.text")
                    }

                    if state.canUseVision {
                        if PlatformChatCapabilities.supportsCameraCapture {
                            Button(action: actions.openCamera) {
                                Label(String.appLocalized("chat.take_photo"), systemImage: "camera")
                            }
                        }

                        Button(action: actions.openPhotoLibrary) {
                            Label(String.appLocalized("chat.photo_library"), systemImage: "photo.on.rectangle")
                        }
                    }

                    Divider()

                    Toggle(isOn: Binding(
                        get: { state.isWebSearchEnabled },
                        set: { _ in actions.toggleWebSearch() }
                    )) {
                        Label(String.appLocalized("Web Search"), systemImage: "globe")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title3)
                        .frame(width: 30, height: 30)
                        .foregroundStyle(.secondary)
                }
                .tint(.primary)
                .menuIndicator(.hidden)
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .accessibilityLabel("Add attachment")

                if state.canUseThinking {
                    Button(action: actions.toggleThinking) {
                        Image(systemName: state.isThinkingEnabled ? "lightbulb.fill" : "lightbulb")
                            .font(.title3)
                            .frame(width: 30, height: 30)
                            .foregroundStyle(state.isThinkingEnabled ? BrandPalette.accent : .secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
                    .accessibilityLabel(state.isThinkingEnabled ? "Disable thinking" : "Enable thinking")
                }

                InputBarView(
                    text: $inputText,
                    isGenerating: state.isGenerating,
                    isSendEnabled: state.canSendMessage,
                    isVoiceEnabled: state.canPresentLiveVoice,
                    isFocused: $isInputFocused,
                    onVoiceTap: actions.voiceTap,
                    onSend: actions.send,
                    onStop: actions.stop
                )
            }
        }
        .frame(maxWidth: state.maxWidth)
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .liquidGlassSurface(
            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
            fallback: AnyShapeStyle(.regularMaterial)
        )
        .padding(.horizontal)
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
}
