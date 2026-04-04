import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct ChatView: View {
    @State private var chatViewModel: ChatViewModel
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var showModelPicker = false
    @State private var showPersonaPicker = false
    @State private var showAttachmentActionSheet = false
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var showDocumentImporter = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showConversationHistory = false
    @State private var streamingScrollTask: Task<Void, Never>?
    let appState: AppState
    let conversationId: UUID

    init(appState: AppState, conversationId: UUID) {
        self.appState = appState
        self.conversationId = conversationId
        self._chatViewModel = State(initialValue: ChatViewModel(appState: appState))
    }

    var body: some View {
        contentView
        .navigationTitle(conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomAccessoryStack
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    isInputFocused = false
                    showConversationHistory = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                }
                .accessibilityLabel("Open conversations")
            }
            ToolbarItem(placement: .principal) {
                modelStatus
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isInputFocused = false
                    showPersonaPicker = true
                } label: {
                    Image(systemName: "person.crop.circle")
                }
                .accessibilityLabel("Choose persona")

                if appState.loadedModelId != nil {
                    Button {
                        Task {
                            await chatViewModel.unloadModel()
                        }
                    } label: {
                        Image(systemName: "eject")
                    }
                    .accessibilityLabel("Unload model")
                }

                Button {
                    isInputFocused = false
                    chatViewModel.startNewConversation()
                    inputText = ""
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("New conversation")
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
            let currentConversationId = appState.activeConversationId ?? conversationId
            if let conversation = appState.conversations.first(where: { $0.id == currentConversationId }) {
                chatViewModel.loadConversation(conversation)
            }
        }
        .onChange(of: selectedPhotoItem) {
            if let item = selectedPhotoItem {
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            chatViewModel.pendingImages.append(data)
                            selectedPhotoItem = nil
                        }
                    } else {
                        await MainActor.run {
                            selectedPhotoItem = nil
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            ImagePicker(isPresented: $showCamera) { data in
                chatViewModel.pendingImages.append(data)
            }
        }
        .photosPicker(isPresented: $showPhotoLibrary, selection: $selectedPhotoItem, matching: .images)
        .fileImporter(
            isPresented: $showDocumentImporter,
            allowedContentTypes: supportedDocumentTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                Task {
                    await chatViewModel.importDocument(from: url)
                }
            case .failure(let error):
                chatViewModel.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $showConversationHistory) {
            NavigationStack {
                ConversationListView(appState: appState, presentation: .modalSheet) { _ in
                    showConversationHistory = false
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(String.appLocalized("common.done")) {
                            showConversationHistory = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showPersonaPicker) {
            PersonaPickerSheet(
                appState: appState,
                chatViewModel: chatViewModel,
                isPresented: $showPersonaPicker
            )
        }
        .onDisappear {
            streamingScrollTask?.cancel()
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
        Button {
            showModelPicker = true
        } label: {
            HStack(spacing: 6) {
                if chatViewModel.isModelLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text(appState.selectedModel?.displayName ?? String.appLocalized("chat.loading_model"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                } else if appState.loadedModelId != nil,
                          let loadedModel = Constants.ModelRegistry.curatedModels.first(where: { $0.id == appState.loadedModelId }) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(loadedModel.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(String.appLocalized("chat.select_model"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .overlay {
                Capsule()
                    .strokeBorder(.secondary.opacity(0.18), lineWidth: 1)
            }
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            appState.loadedModelId == nil
                ? String.appLocalized("chat.select_model")
                : String.appLocalized("chat.change_model_a11y")
        )
        .accessibilityHint(String.appLocalized("chat.model_picker_hint"))
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
                Text(String.appLocalized("chat.start_conversation"))
                    .font(.title2)
                    .fontWeight(.semibold)
                Text(String.appLocalized("chat.empty_hint"))
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
                streamingScrollTask?.cancel()
                withAnimation {
                    proxy.scrollTo(chatViewModel.messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: chatViewModel.currentResponse) {
                guard !chatViewModel.currentResponse.isEmpty else { return }
                streamingScrollTask?.cancel()
                streamingScrollTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    guard !Task.isCancelled else { return }
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

            personaBadge
            inputBar
        }
        .padding(.top, 8)
    }

    private var personaBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: chatViewModel.activePersona.symbolName)
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(chatViewModel.activePersona.localizedName)
                    .font(.caption.weight(.semibold))
                Text(chatViewModel.activePersona.localizedDisplaySummary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button(String.appLocalized("common.change")) {
                isInputFocused = false
                showPersonaPicker = true
            }
            .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    private var modelLoadingCard: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(String.appLocalized("chat.loading_model_title"))
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(appState.selectedModel?.displayName ?? String.appLocalized("chat.preparing_model"))
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
            Text(String.appLocalized("chat.generating"))
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
                    Text(String.appLocalized("chat.out_of_memory"))
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                }
                Text(isOOMError(message) ? String.appLocalized("chat.oom_suggestion") : message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            }
            Spacer()
            Button {
                chatViewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel("Dismiss error")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isOOMError(message) ? .red.opacity(0.1) : .orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSendMessage else { return }
        inputText = ""
        chatViewModel.sendMessage(text)
    }

    private func isOOMError(_ message: String) -> Bool {
        let lower = message.lowercased()
        if lower.contains("memory") || lower.contains("memoria") || lower.contains("内存") {
            return true
        }
        return lower.contains("low memory") || lower.contains("poca memoria") || lower.contains("内存偏低")
    }

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !chatViewModel.pendingDocuments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chatViewModel.pendingDocuments) { document in
                            HStack(spacing: 6) {
                                Image(systemName: iconName(for: document.kind))
                                    .foregroundStyle(.blue)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(document.displayName)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text(document.kind.displayName)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Button {
                                    chatViewModel.removeDocument(document)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 44, height: 44)
                                .accessibilityLabel("Remove document")
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.fill.tertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            if !chatViewModel.pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(chatViewModel.pendingImages.enumerated()), id: \.offset) { index, imageData in
                            if let uiImage = UIImage(data: imageData) {
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 60, height: 60)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                    
                                    Button {
                                        chatViewModel.pendingImages.remove(at: index)
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                            .font(.caption)
                                    }
                                    .frame(width: 44, height: 44)
                                    .accessibilityLabel("Remove image")
                                    .offset(x: 4, y: -4)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    showAttachmentActionSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Color.secondary.opacity(0.12))
                        .foregroundStyle(.secondary)
                        .clipShape(Circle())
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Add attachment")
                .padding(.bottom, 4)
                .confirmationDialog(String.appLocalized("chat.add_to_conversation"), isPresented: $showAttachmentActionSheet) {
                    Button(String.appLocalized("chat.import_document")) {
                        showDocumentImporter = true
                    }
                    if chatViewModel.canUseVision {
                        Button(String.appLocalized("chat.take_photo")) {
                            showCamera = true
                        }
                        Button(String.appLocalized("chat.photo_library")) {
                            showPhotoLibrary = true
                        }
                    }
                    Button(String.appLocalized("common.cancel"), role: .cancel) {}
                }

                if chatViewModel.canUseThinking {
                    Button {
                        chatViewModel.toggleThinking()
                    } label: {
                        Image(systemName: chatViewModel.isThinkingEnabled ? "lightbulb.fill" : "lightbulb")
                            .font(.system(size: 18, weight: .medium))
                            .frame(width: 32, height: 32)
                            .background(chatViewModel.isThinkingEnabled ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12))
                            .foregroundStyle(chatViewModel.isThinkingEnabled ? .orange : .secondary)
                            .clipShape(Circle())
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(chatViewModel.isThinkingEnabled ? "Disable thinking" : "Enable thinking")
                    .padding(.bottom, 4)
                }

                InputBarView(
                    text: $inputText,
                    isGenerating: chatViewModel.isGenerating,
                    isSendEnabled: canSendMessage,
                    isFocused: $isInputFocused,
                    onSend: sendMessage,
                    onStop: chatViewModel.stopGeneration
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var canSendMessage: Bool {
        !chatViewModel.isModelLoading && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var supportedDocumentTypes: [UTType] {
        var types: [UTType] = [.pdf, .plainText, .commaSeparatedText]
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        return types
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
