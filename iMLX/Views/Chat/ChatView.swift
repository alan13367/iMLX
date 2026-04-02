import SwiftUI

struct ChatView: View {
    @State private var chatViewModel = ChatViewModel()
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var showModelPicker = false
    let appState: AppState
    let conversationId: UUID

    var body: some View {
        contentView
        .navigationTitle(conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomAccessoryStack
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                modelStatus
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                if appState.loadedModelId != nil {
                    Button {
                        Task {
                            await chatViewModel.unloadModel()
                        }
                    } label: {
                        Image(systemName: "eject")
                    }
                }

                Button {
                    isInputFocused = false
                    chatViewModel.startNewConversation()
                    inputText = ""
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded {
                isInputFocused = false
            }
        )
        .task(id: appState.selectedModel?.id) {
            if let model = appState.selectedModel,
               appState.loadedModelId != model.id {
                await chatViewModel.loadModel(model)
            }
        }
        .task(id: appState.activeConversationId ?? conversationId) {
            chatViewModel.configure(with: appState)
            let currentConversationId = appState.activeConversationId ?? conversationId
            if let conversation = appState.conversations.first(where: { $0.id == currentConversationId }) {
                chatViewModel.loadConversation(conversation)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        if chatViewModel.messages.isEmpty && !chatViewModel.isGenerating && chatViewModel.currentResponse.isEmpty {
            emptyState
        } else {
            messageList
        }
    }

    private var conversationTitle: String {
        let currentConversationId = appState.activeConversationId ?? conversationId
        if let conversation = appState.conversations.first(where: { $0.id == currentConversationId }) {
            return conversation.displayTitle
        }
        return "iMLX"
    }

    private var modelStatus: some View {
        HStack(spacing: 6) {
            if chatViewModel.isModelLoading {
                ProgressView()
                    .controlSize(.small)
                Text(appState.selectedModel?.displayName ?? "Loading...")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if appState.loadedModelId != nil,
                      let loadedModel = Constants.ModelRegistry.curatedModels.first(where: { $0.id == appState.loadedModelId }) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text(loadedModel.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
            } else {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("No model loaded")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .onTapGesture {
            showModelPicker = true
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(
                appState: appState,
                chatViewModel: chatViewModel,
                isPresented: $showModelPicker
            )
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56))
                .foregroundStyle(.secondary.opacity(0.4))
            VStack(spacing: 8) {
                Text("Start a conversation")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Select a model from the Models tab,\nthen type a message.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 40)
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(chatViewModel.messages) { message in
                        MessageBubbleView(message: message)
                            .id(message.id)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    if !chatViewModel.currentResponse.isEmpty {
                        MessageBubbleView(
                            message: ChatMessage(
                                role: .assistant,
                                content: chatViewModel.currentResponse + (chatViewModel.isGenerating ? "▊" : "")
                            ),
                            isStreaming: true
                        )
                        .id("streaming")
                        .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: chatViewModel.messages.count)
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .onChange(of: chatViewModel.messages.count) {
                withAnimation {
                    proxy.scrollTo(chatViewModel.messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: chatViewModel.currentResponse) {
                withAnimation {
                    proxy.scrollTo("streaming", anchor: .bottom)
                }
            }
        }
    }

    private var bottomAccessoryStack: some View {
        VStack(spacing: 8) {
            if let errorMessage = chatViewModel.errorMessage {
                errorBanner(message: errorMessage)
            }

            if chatViewModel.isModelLoading {
                modelLoadingCard
            }

            if chatViewModel.isGenerating {
                generatingIndicator
            }

            inputBar
        }
        .padding(.top, 8)
    }

    private var modelLoadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text("Loading Model")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(appState.selectedModel?.displayName ?? "Preparing the selected model for local inference")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .padding(.horizontal)
    }

    private var generatingIndicator: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            Text("Generating")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func errorBanner(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isOOMError(message) ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(isOOMError(message) ? .red : .orange)
            VStack(alignment: .leading, spacing: 2) {
                if isOOMError(message) {
                    Text("Out of Memory")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                }
                Text(isOOMError(message) ? "Close other apps or try a smaller model." : message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                chatViewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isOOMError(message) ? .red.opacity(0.1) : .orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""
        chatViewModel.sendMessage(text)
    }

    private func isOOMError(_ message: String) -> Bool {
        message.contains("memory") || message.contains("Memory") || message.contains("Low memory")
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if chatViewModel.canUseThinking {
                Button {
                    chatViewModel.toggleThinking()
                } label: {
                    Label(
                        chatViewModel.isThinkingEnabled ? "Thinking On" : "Thinking Off",
                        systemImage: chatViewModel.isThinkingEnabled ? "sparkles" : "circle.slash"
                    )
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(chatViewModel.isThinkingEnabled ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12))
                    .foregroundStyle(chatViewModel.isThinkingEnabled ? .orange : .secondary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.fill.tertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .focused($isInputFocused)
                    .onSubmit {
                        if !chatViewModel.isModelLoading {
                            sendMessage()
                        }
                    }

                if chatViewModel.isGenerating {
                    Button {
                        chatViewModel.stopGeneration()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.red)
                    }
                } else {
                    Button {
                        sendMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(canSendMessage ? .blue : .gray)
                    }
                    .disabled(!canSendMessage)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSendMessage: Bool {
        !chatViewModel.isModelLoading && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
