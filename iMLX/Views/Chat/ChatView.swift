import SwiftUI

struct ChatView: View {
    @State private var chatViewModel = ChatViewModel()
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var showModelPicker = false
    let appState: AppState
    let conversationId: UUID

    var body: some View {
        ZStack {
            if chatViewModel.isModelLoading {
                loadingShimmer
            } else if chatViewModel.messages.isEmpty && !chatViewModel.isGenerating {
                emptyState
            } else {
                messageList
            }
            VStack(spacing: 0) {
                Spacer()
                if let errorMessage = chatViewModel.errorMessage {
                    errorBanner(message: errorMessage)
                }
                if chatViewModel.isGenerating {
                    generatingIndicator
                } else if let stats = chatViewModel.stats {
                    StatsOverlayView(stats: stats, isLive: false)
                }
                inputBar
            }
        }
        .navigationTitle(conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                modelStatus
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    chatViewModel.clearConversation()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    isInputFocused = false
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .task(id: appState.selectedModel?.id) {
            if let model = appState.selectedModel,
               appState.loadedModelId != model.id {
                await chatViewModel.loadModel(model)
            }
        }
        .task(id: conversationId) {
            chatViewModel.configure(with: appState)
            if let conversation = appState.conversations.first(where: { $0.id == conversationId }) {
                chatViewModel.loadConversation(conversation)
            }
        }
    }

    private var conversationTitle: String {
        if let conversation = appState.conversations.first(where: { $0.id == conversationId }) {
            return conversation.displayTitle
        }
        return "iMLX"
    }

    private var modelStatus: some View {
        HStack(spacing: 6) {
            if chatViewModel.isModelLoading {
                ProgressView()
                    .controlSize(.small)
                Text("Loading...")
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

    private var loadingShimmer: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .controlSize(.large)
            Text("Loading model...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                            )
                        )
                        .id("streaming")
                        .transition(.opacity)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: chatViewModel.messages.count)
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: 1)
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
                    sendMessage()
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
                        .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
