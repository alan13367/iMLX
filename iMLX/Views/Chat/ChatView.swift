import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

private enum ChatUtilitySheet: String, Identifiable {
    case conversations
    case models
    case memoryLibrary
    case settings

    var id: String { rawValue }
}

private struct ChatScrollState: Equatable {
    let contentOverflows: Bool
    let isPinnedToBottom: Bool
}

private struct WebSearchPillSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule()
                .fill(isOn ? BrandPalette.accent : Color.secondary.opacity(0.24))
                .overlay {
                    Capsule()
                        .stroke(Color.secondary.opacity(isOn ? 0 : 0.18), lineWidth: 1)
                }

            Circle()
                .fill(.white)
                .shadow(color: .black.opacity(0.16), radius: 2, x: 0, y: 1)
                .padding(3)
        }
        .frame(width: 52, height: 32)
        .animation(.spring(response: 0.24, dampingFraction: 0.82), value: isOn)
    }
}

private struct WebSearchPrivacyConfirmationSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onEnable: () -> Void
    let onKeepLocal: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: "globe.badge.chevron.backward")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(BrandPalette.cyan)
                            .frame(width: 44, height: 44)
                            .liquidGlassSurface(
                                tint: BrandPalette.cyan.opacity(0.18),
                                in: Circle(),
                                fallback: AnyShapeStyle(BrandPalette.cyan.opacity(0.10))
                            )

                        VStack(alignment: .leading, spacing: 6) {
                            Text(String.appLocalized("web_search.privacy.title"))
                                .font(.title3.weight(.semibold))
                            Text(String.appLocalized("web_search.privacy.subtitle"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        privacyPoint("network", String.appLocalized("web_search.privacy.point_message"))
                        privacyPoint("safari", String.appLocalized("web_search.privacy.point_pages"))
                        privacyPoint("lock.slash", String.appLocalized("web_search.privacy.point_boundary"))
                        privacyPoint("checkmark.shield", String.appLocalized("web_search.privacy.point_local"))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 28)
                .padding(.bottom, 18)
            }

            VStack(spacing: 10) {
                Button {
                    onEnable()
                    dismiss()
                } label: {
                    Text(String.appLocalized("web_search.privacy.enable"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .liquidGlassButtonStyle(prominent: true, tint: BrandPalette.accent)

                Button {
                    onKeepLocal()
                    dismiss()
                } label: {
                    Text(String.appLocalized("web_search.privacy.keep_local"))
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .liquidGlassButtonStyle(tint: BrandPalette.cyan)
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .presentationDetents([.fraction(0.82), .large])
        .presentationDragIndicator(.visible)
    }

    private func privacyPoint(_ systemImage: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandPalette.accent)
                .frame(width: 24, height: 24)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct ChatView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var chatViewModel: ChatViewModel
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var showModelPicker = false
    @State private var showPersonaPicker = false
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var showDocumentImporter = false
    @State private var showWebSearchDisclosure = false
    @State private var showLiveVoice = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var utilitySheet: ChatUtilitySheet?
    let appState: AppState
    let conversationId: UUID

    init(appState: AppState, conversationId: UUID) {
        self.appState = appState
        self.conversationId = conversationId
        self._chatViewModel = State(initialValue: ChatViewModel(appState: appState))
    }

    var body: some View {
        visibleChatContent
        .navigationTitle(conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            chatAccessoryInset
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                leadingToolbarContent
            }
            ToolbarItem(placement: .principal) {
                principalToolbarContent
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                trailingToolbarContent
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(openConversationHistoryGesture)
        .task(id: appState.selectedModel?.id) {
            if let model = appState.selectedModel,
               appState.loadedModelId != model.id {
                await chatViewModel.loadModel(model)
            }
        }
        .task(id: appState.activeConversationId ?? conversationId) {
            let currentConversationId = appState.activeConversationId ?? conversationId
            if let conversation = appState.conversation(id: currentConversationId) {
                chatViewModel.loadConversation(conversation)
            }
        }
        .task(id: appState.pendingShortcutRoute) {
            handlePendingShortcutRoute()
        }
        .onChange(of: appState.loadedModelId) { _, _ in
            handlePendingShortcutRoute()
        }
        .onChange(of: chatViewModel.isModelLoading) { _, _ in
            handlePendingShortcutRoute()
        }
        .onChange(of: selectedPhotoItem) {
            if let item = selectedPhotoItem {
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await MainActor.run {
                            chatViewModel.appendPendingImage(data)
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
                chatViewModel.appendPendingImage(data)
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
        .sheet(item: $utilitySheet) { sheet in
            utilitySheetView(sheet)
        }
        .sheet(isPresented: $showPersonaPicker) {
            PersonaPickerSheet(
                appState: appState,
                chatViewModel: chatViewModel,
                isPresented: $showPersonaPicker
            )
        }
        .fullScreenCover(isPresented: $showLiveVoice) {
            LiveVoiceConversationView(appState: appState, chatViewModel: chatViewModel)
        }
        .sheet(isPresented: $showWebSearchDisclosure) {
            WebSearchPrivacyConfirmationSheet {
                chatViewModel.setWebSearchEnabled(true)
                showWebSearchDisclosure = false
            } onKeepLocal: {
                showWebSearchDisclosure = false
            }
        }
    }

    private var isShowingEmptyState: Bool {
        chatViewModel.messages.isEmpty && !chatViewModel.isGenerating && chatViewModel.currentResponse.isEmpty
    }

    @ViewBuilder
    private var visibleChatContent: some View {
        if showLiveVoice {
            Color.clear
        } else {
            chatContent
        }
    }

    private var chatContent: some View {
        ZStack {
            ChatBackgroundView()
            
            ChatEmptyStateView()
                .opacity(isShowingEmptyState ? 1 : 0)
                .allowsHitTesting(isShowingEmptyState)
                .onTapGesture {
                    isInputFocused = false
                }

            ChatMessageListSection(
                messages: chatViewModel.messages,
                currentResponse: chatViewModel.currentResponse,
                isGenerating: chatViewModel.isGenerating,
                parsedResponse: chatViewModel.currentParsedResponse,
                toolActivityStatus: chatViewModel.toolActivityStatus,
                currentToolTrace: chatViewModel.currentToolTrace,
                conversationResetKey: appState.activeConversationId ?? conversationId,
                onTranscriptTap: { isInputFocused = false }
            )
            .opacity(isShowingEmptyState ? 0 : 1)
            .allowsHitTesting(!isShowingEmptyState)
        }
    }

    @ViewBuilder
    private var chatAccessoryInset: some View {
        if showLiveVoice {
            EmptyView()
        } else {
            chatAccessoryStack
        }
    }

    private var chatAccessoryStack: some View {
        ChatAccessoryStackView(
            horizontalSizeClass: horizontalSizeClass,
            errorMessage: chatViewModel.errorMessage,
            toolNotice: chatViewModel.toolNotice,
            toolActivityStatus: chatViewModel.toolActivityStatus,
            isModelLoading: chatViewModel.isModelLoading,
            selectedModelDisplayName: appState.selectedModel?.displayName,
            isGenerating: chatViewModel.isGenerating,
            memoryNotice: chatViewModel.memoryNotice,
            activePersona: chatViewModel.activePersona,
            pendingDocuments: chatViewModel.pendingDocuments,
            pendingImages: chatViewModel.pendingImages,
            canUseThinking: chatViewModel.canUseThinking,
            isThinkingEnabled: chatViewModel.isThinkingEnabled,
            canSendMessage: canSendMessage,
            canPresentLiveVoice: canPresentLiveVoice,
            canUseVision: chatViewModel.canUseVision,
            isWebSearchEnabled: chatViewModel.isWebSearchEnabled,
            inputText: $inputText,
            isInputFocused: $isInputFocused,
            onDismissError: dismissError,
            onDismissToolNotice: dismissToolNotice,
            onDismissMemoryNotice: chatViewModel.dismissMemoryNotice,
            onOpenMemoryLibrary: openMemoryLibrary,
            onOpenPersonaPicker: openPersonaPicker,
            onRemoveDocument: chatViewModel.removeDocument,
            onRemovePendingImage: chatViewModel.removePendingImage(id:),
            onOpenAttachmentImporter: openDocumentImporter,
            onOpenCamera: openCamera,
            onOpenPhotoLibrary: openPhotoLibrary,
            onToggleThinking: chatViewModel.toggleThinking,
            onVoiceTap: openLiveVoice,
            onSend: sendMessage,
            onStop: { chatViewModel.stopGeneration() },
            onToggleWebSearch: handleWebSearchToggleTap
        )
    }

    private var conversationTitle: String {
        let currentConversationId = appState.activeConversationId ?? conversationId
        if let conversation = appState.conversation(id: currentConversationId) {
            return conversation.displayTitle
        }
        return "iMLX"
    }

    private var openConversationHistoryGesture: some Gesture {
        DragGesture(minimumDistance: 24, coordinateSpace: .local)
            .onEnded { value in
                guard shouldOpenConversationHistory(from: value) else { return }
                isInputFocused = false
                utilitySheet = .conversations
            }
    }

    private func shouldOpenConversationHistory(from value: DragGesture.Value) -> Bool {
        guard utilitySheet == nil else { return false }
        guard value.startLocation.x <= 56 else { return false }

        let horizontalDistance = value.translation.width
        let verticalDistance = abs(value.translation.height)
        guard horizontalDistance > 90 else { return false }
        guard horizontalDistance > verticalDistance * 1.6 else { return false }
        return value.predictedEndTranslation.width > 120
    }

    @ViewBuilder
    private func utilitySheetView(_ sheet: ChatUtilitySheet) -> some View {
        NavigationStack {
            switch sheet {
            case .conversations:
                ConversationListView(
                    appState: appState,
                    presentation: .modalSheet,
                    onClose: { utilitySheet = nil }
                ) { _ in
                    utilitySheet = nil
                }
            case .models:
                ModelBrowserView(appState: appState)
            case .memoryLibrary:
                MemoryLibraryView(appState: appState, onClose: { utilitySheet = nil })
            case .settings:
                SettingsView(appState: appState)
            }
        }
    }

    private var modelStatus: some View {
        ChatModelStatusButton(
            isModelLoading: chatViewModel.isModelLoading,
            selectedModelDisplayName: appState.selectedModel?.displayName,
            loadedModelDisplayName: appState.modelInfo(id: appState.loadedModelId)?.displayName,
            onTap: { showModelPicker = true }
        )
        .sheet(isPresented: $showModelPicker) {
            ModelPickerSheet(
                appState: appState,
                chatViewModel: chatViewModel,
                isPresented: $showModelPicker
            )
        }
    }

    @ViewBuilder
    private var leadingToolbarContent: some View {
        if showLiveVoice {
            EmptyView()
        } else {
            ChatToolbarMenu(
                onOpenConversations: openConversationHistory,
                onOpenModels: openModels,
                onOpenSettings: openSettings
            )
        }
    }

    @ViewBuilder
    private var principalToolbarContent: some View {
        if showLiveVoice {
            EmptyView()
        } else {
            modelStatus
        }
    }

    @ViewBuilder
    private var trailingToolbarContent: some View {
        if !showLiveVoice && appState.loadedModelId != nil {
            ChatToolbarIconButton(
                systemImage: "eject",
                accessibilityLabel: String.appLocalized("models.picker.unload"),
                action: unloadModel
            )
        }

        if !showLiveVoice {
            ChatToolbarIconButton(
                systemImage: "square.and.pencil",
                accessibilityLabel: String.appLocalized("New conversation"),
                action: startNewConversation
            )
        }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSendMessage else { return }
        inputText = ""
        chatViewModel.sendMessage(text)
    }

    private func dismissError() {
        chatViewModel.errorMessage = nil
    }

    private func dismissToolNotice() {
        chatViewModel.toolNotice = nil
    }

    private func openMemoryLibrary() {
        isInputFocused = false
        utilitySheet = .memoryLibrary
    }

    private func openPersonaPicker() {
        isInputFocused = false
        showPersonaPicker = true
    }

    private func openDocumentImporter() {
        isInputFocused = false
        showDocumentImporter = true
    }

    private func openCamera() {
        isInputFocused = false
        showCamera = true
    }

    private func openPhotoLibrary() {
        isInputFocused = false
        showPhotoLibrary = true
    }

    private func openLiveVoice() {
        isInputFocused = false
        showLiveVoice = true
    }

    private func openConversationHistory() {
        isInputFocused = false
        utilitySheet = .conversations
    }

    private func openModels() {
        isInputFocused = false
        utilitySheet = .models
    }

    private func openSettings() {
        isInputFocused = false
        utilitySheet = .settings
    }

    private func unloadModel() {
        Task {
            await chatViewModel.unloadModel()
        }
    }

    private func startNewConversation() {
        isInputFocused = false
        chatViewModel.startNewConversation()
        inputText = ""
    }

    private var canSendMessage: Bool {
        !chatViewModel.isModelLoading && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canPresentLiveVoice: Bool {
        !chatViewModel.isModelLoading
            && !chatViewModel.isGenerating
            && !chatViewModel.isThinkingEnabled
            && appState.loadedModelId != nil
            && !isRunningOnSimulator
    }

    private func handleWebSearchToggleTap() {
        if chatViewModel.isWebSearchEnabled {
            chatViewModel.setWebSearchEnabled(false)
        } else {
            showWebSearchDisclosure = true
        }
    }

    private func handlePendingShortcutRoute() {
        guard appState.pendingShortcutRoute == .openLiveVoice else { return }
        guard appState.hasCompletedOnboarding else { return }
        guard !showLiveVoice else {
            appState.clearPendingShortcutRoute()
            return
        }
        guard !isRunningOnSimulator else { return }

        if canPresentLiveVoice {
            showLiveVoice = true
            appState.clearPendingShortcutRoute()
            return
        }

        if appState.selectedModel == nil && !showModelPicker {
            showModelPicker = true
        }
    }

    private var supportedDocumentTypes: [UTType] {
        Self.cachedSupportedDocumentTypes
    }

    private static let cachedSupportedDocumentTypes: [UTType] = {
        var types: [UTType] = [.pdf, .plainText, .commaSeparatedText]
        if let markdown = UTType(filenameExtension: "md") {
            types.append(markdown)
        }
        return types
    }()

    private var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}

private struct ChatToolbarMenu: View {
    let onOpenConversations: () -> Void
    let onOpenModels: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Menu {
            Button(action: onOpenConversations) {
                Label(String.appLocalized("conversation.title.chats"), systemImage: "bubble.left.and.bubble.right")
            }

            Button(action: onOpenModels) {
                Label(String.appLocalized("tab.models"), systemImage: "arrow.down.circle")
            }

            Button(action: onOpenSettings) {
                Label(String.appLocalized("tab.settings"), systemImage: "gearshape")
            }
        } label: {
            Image(systemName: "line.3.horizontal")
        }
        .accessibilityLabel("Open app menu")
    }
}

private struct ChatToolbarIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct ChatModelStatusButton: View {
    let isModelLoading: Bool
    let selectedModelDisplayName: String?
    let loadedModelDisplayName: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 6) {
                if isModelLoading {
                    ProgressView()
                        .controlSize(.small)
                    Text(selectedModelDisplayName ?? String.appLocalized("chat.loading_model"))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(1)
                } else if let loadedModelDisplayName {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Text(loadedModelDisplayName)
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
            .liquidGlassSurface(in: Capsule(), interactive: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            loadedModelDisplayName == nil
                ? String.appLocalized("chat.select_model")
                : String.appLocalized("chat.change_model_a11y")
        )
        .accessibilityHint(String.appLocalized("chat.model_picker_hint"))
    }
}

private struct ChatEmptyStateView: View {
    var body: some View {
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
}

private struct ChatMessageListSection: View {
    let messages: [ChatMessage]
    let currentResponse: String
    let isGenerating: Bool
    let parsedResponse: ParsedAssistantContent
    let toolActivityStatus: ToolActivityStatus?
    let currentToolTrace: ToolCallTrace?
    let conversationResetKey: UUID
    let onTranscriptTap: () -> Void

    @State private var streamingScrollTask: Task<Void, Never>?
    @State private var streamingAutoscrollEnabled = true
    @State private var contentOverflows = false
    @State private var scrollPinnedToBottom = true
    @State private var contentHeight: CGFloat = 0
    @State private var finalizationStickToBottomTask: Task<Void, Never>?
    @State private var shouldStickToBottomDuringFinalization = false
    @State private var scrollViewResetKey = UUID()
    @State private var isStreamingThinkingExpanded = true

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 12, pinnedViews: [.sectionHeaders]) {
                        ForEach(messages) { message in
                            MessageBubbleView(message: message)
                                .equatable()
                                .id(message.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        if let toolActivityStatus {
                            ToolActivityChainView(status: toolActivityStatus)
                                .id("toolActivity")
                                .transition(.opacity)
                        } else if let currentToolTrace, isGenerating {
                            CompletedToolChainView(trace: currentToolTrace)
                                .id("toolTraceInline")
                                .transition(.opacity)
                        }

                        if !currentResponse.isEmpty, shouldPinStreamingThinkingHeader {
                            Section {
                                streamingMessageBubble
                            } header: {
                                StreamingThinkingPinnedHeader(
                                    isExpanded: $isStreamingThinkingExpanded,
                                    isWaitingForAnswer: parsedResponse.response.isEmpty
                                ) {
                                    guard streamingAutoscrollEnabled else { return }
                                    scheduleAutoscroll(using: proxy, repeatAfterLayoutChange: true)
                                }
                            }
                            .id("streaming")
                            .transition(.opacity)
                        } else if !currentResponse.isEmpty {
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
                .id(scrollViewResetKey)
                .simultaneousGesture(
                    TapGesture().onEnded(onTranscriptTap)
                )
                .onScrollGeometryChange(for: ChatScrollState.self, of: { geometry in
                    let contentHeight = geometry.contentSize.height
                    let visibleHeight = geometry.visibleRect.height
                    let overflows = contentHeight > visibleHeight + 32
                    let pinned = !overflows || geometry.visibleRect.maxY >= contentHeight - 32
                    return ChatScrollState(contentOverflows: overflows, isPinnedToBottom: pinned)
                }, action: { _, state in
                    contentOverflows = state.contentOverflows
                    scrollPinnedToBottom = state.isPinnedToBottom
                })
                .onScrollGeometryChange(for: CGFloat.self, of: { geometry in
                    geometry.contentSize.height
                }, action: { _, height in
                    contentHeight = height
                    guard shouldStickToBottomDuringFinalization else { return }
                    guard streamingAutoscrollEnabled else { return }
                    scrollToBottom(using: proxy, animated: false)
                })
                .onScrollPhaseChange { _, newPhase in
                    guard newPhase == .tracking || newPhase == .interacting else { return }
                    guard isGenerating else { return }
                    guard streamingAutoscrollEnabled else { return }
                    streamingScrollTask?.cancel()
                    streamingScrollTask = nil
                    streamingAutoscrollEnabled = false
                }
                .task(id: conversationResetKey) {
                    streamingAutoscrollEnabled = true
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
                        return
                    }
                    guard streamingAutoscrollEnabled else { return }
                    guard !messages.isEmpty else { return }
                    stickToBottomDuringFinalization(using: proxy)
                }
                .task(id: contentHeight) {
                    guard shouldStickToBottomDuringFinalization else { return }
                    guard streamingAutoscrollEnabled else { return }
                    scrollToBottom(using: proxy, animated: false)
                }
                .onDisappear {
                    streamingScrollTask?.cancel()
                    finalizationStickToBottomTask?.cancel()
                }

                if contentOverflows && (!scrollPinnedToBottom || !streamingAutoscrollEnabled) {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            resumeAutoscroll(using: proxy)
                        } label: {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.title2)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.primary)
                                .frame(width: 44, height: 44)
                                .liquidGlassSurface(
                                    tint: BrandPalette.accent.opacity(0.28),
                                    in: Circle(),
                                    fallback: AnyShapeStyle(BrandPalette.primaryGradient),
                                    interactive: true
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Scroll to bottom")
                        Spacer(minLength: 0)
                    }
                    .padding(.bottom, 12)
                }
            }
        }
    }

    private var shouldPinStreamingThinkingHeader: Bool {
        guard isGenerating else { return false }
        guard let thinking = parsedResponse.thinking else { return false }
        return !thinking.isEmpty
    }

    private var streamingMessageBubble: some View {
        MessageBubbleView(
            message: ChatMessage(
                role: .assistant,
                content: currentResponse + (isGenerating ? "▊" : "")
            ),
            isStreaming: true,
            parsedAssistantContent: parsedResponse,
            thinkingExpansion: $isStreamingThinkingExpanded,
            showsThinkingHeader: !shouldPinStreamingThinkingHeader
        )
    }

    private var streamingAutoscrollKey: Int {
        guard !currentResponse.isEmpty else { return 0 }
        let visibleCharacterCount = parsedResponse.response.isEmpty
            ? currentResponse.count
            : parsedResponse.response.count
        return 1 + visibleCharacterCount / Constants.UI.streamingAutoscrollCharacterStride
    }

    private func resumeAutoscroll(using proxy: ScrollViewProxy) {
        streamingScrollTask?.cancel()
        scrollToBottom(using: proxy)
        streamingAutoscrollEnabled = true
        scheduleAutoscroll(using: proxy)
    }

    private func scheduleAutoscroll(using proxy: ScrollViewProxy, repeatAfterLayoutChange: Bool = false) {
        streamingScrollTask?.cancel()
        streamingScrollTask = Task { @MainActor in
            defer { streamingScrollTask = nil }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            scrollToBottom(using: proxy)
            guard repeatAfterLayoutChange else { return }
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled else { return }
            scrollToBottom(using: proxy)
        }
    }

    private func scrollToBottom(using proxy: ScrollViewProxy) {
        scrollToBottom(using: proxy, animated: true)
    }

    private func scrollToBottom(using proxy: ScrollViewProxy, animated: Bool) {
        if animated {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
            }
        } else {
            proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
        }
    }

    private func stickToBottomDuringFinalization(using proxy: ScrollViewProxy) {
        finalizationStickToBottomTask?.cancel()
        shouldStickToBottomDuringFinalization = true
        scrollViewResetKey = UUID()
        scheduleAutoscroll(using: proxy, repeatAfterLayoutChange: true)
        finalizationStickToBottomTask = Task { @MainActor in
            defer {
                shouldStickToBottomDuringFinalization = false
                finalizationStickToBottomTask = nil
            }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            scrollToBottom(using: proxy, animated: false)
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            scrollToBottom(using: proxy, animated: false)
        }
    }
}

private struct StreamingThinkingPinnedHeader: View {
    @Binding var isExpanded: Bool
    let isWaitingForAnswer: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
                onToggle()
            } label: {
                ThinkingDisclosureLabel(
                    isExpanded: isExpanded,
                    isStreaming: true,
                    isWaitingForAnswer: isWaitingForAnswer
                )
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String.appLocalized("message.thinking"))
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            Spacer(minLength: 36)
        }
    }
}

private struct ChatAccessoryStackView: View {
    let horizontalSizeClass: UserInterfaceSizeClass?
    let errorMessage: String?
    let toolNotice: String?
    let toolActivityStatus: ToolActivityStatus?
    let isModelLoading: Bool
    let selectedModelDisplayName: String?
    let isGenerating: Bool
    let memoryNotice: ChatMemoryNotice?
    let activePersona: Persona
    let pendingDocuments: [ConversationDocumentReference]
    let pendingImages: [ChatAttachmentImage]
    let canUseThinking: Bool
    let isThinkingEnabled: Bool
    let canSendMessage: Bool
    let canPresentLiveVoice: Bool
    let canUseVision: Bool
    let isWebSearchEnabled: Bool
    @Binding var inputText: String
    @FocusState.Binding var isInputFocused: Bool
    let onDismissError: () -> Void
    let onDismissToolNotice: () -> Void
    let onDismissMemoryNotice: () -> Void
    let onOpenMemoryLibrary: () -> Void
    let onOpenPersonaPicker: () -> Void
    let onRemoveDocument: (ConversationDocumentReference) -> Void
    let onRemovePendingImage: (UUID) -> Void
    let onOpenAttachmentImporter: () -> Void
    let onOpenCamera: () -> Void
    let onOpenPhotoLibrary: () -> Void
    let onToggleThinking: () -> Void
    let onVoiceTap: () -> Void
    let onSend: () -> Void
    let onStop: () -> Void
    let onToggleWebSearch: () -> Void

    private var maxWidth: CGFloat {
        horizontalSizeClass == .regular ? 760 : .infinity
    }

    var body: some View {
        VStack(spacing: 12) {
            if let errorMessage {
                ChatNoticeBanner(
                    style: .error(isOOM: isOOMError(errorMessage)),
                    message: isOOMError(errorMessage) ? String.appLocalized("chat.oom_suggestion") : errorMessage,
                    title: isOOMError(errorMessage) ? String.appLocalized("chat.out_of_memory") : nil,
                    onDismiss: onDismissError
                )
                .frame(maxWidth: maxWidth)
            }

            if let toolNotice {
                ChatNoticeBanner(
                    style: .info,
                    message: toolNotice,
                    title: nil,
                    onDismiss: onDismissToolNotice
                )
                .frame(maxWidth: maxWidth)
            }

            if isModelLoading {
                ChatStatusCard(
                    title: String.appLocalized("chat.loading_model_title"),
                    subtitle: selectedModelDisplayName ?? String.appLocalized("chat.preparing_model")
                )
                .frame(maxWidth: maxWidth)
            }

            if isGenerating {
                ChatGeneratingIndicator()
                    .frame(maxWidth: maxWidth)
            }

            if let memoryNotice {
                ChatMemoryNoticeView(
                    notice: memoryNotice,
                    title: memoryNoticeTitle(for: memoryNotice),
                    onOpenMemoryLibrary: onOpenMemoryLibrary,
                    onDismiss: onDismissMemoryNotice
                )
                .frame(maxWidth: maxWidth)
            }

            ChatComposerSection(
                maxWidth: maxWidth,
                activePersona: activePersona,
                pendingDocuments: pendingDocuments,
                pendingImages: pendingImages,
                canUseThinking: canUseThinking,
                isThinkingEnabled: isThinkingEnabled,
                isGenerating: isGenerating,
                canSendMessage: canSendMessage,
                canPresentLiveVoice: canPresentLiveVoice,
                canUseVision: canUseVision,
                isWebSearchEnabled: isWebSearchEnabled,
                inputText: $inputText,
                isInputFocused: $isInputFocused,
                onOpenPersonaPicker: onOpenPersonaPicker,
                onRemoveDocument: onRemoveDocument,
                onRemovePendingImage: onRemovePendingImage,
                onOpenAttachmentImporter: onOpenAttachmentImporter,
                onOpenCamera: onOpenCamera,
                onOpenPhotoLibrary: onOpenPhotoLibrary,
                onToggleThinking: onToggleThinking,
                onVoiceTap: onVoiceTap,
                onSend: onSend,
                onStop: onStop,
                onToggleWebSearch: onToggleWebSearch
            )
        }
        .padding(.top, 8)
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

private struct ChatComposerSection: View {
    let maxWidth: CGFloat
    let activePersona: Persona
    let pendingDocuments: [ConversationDocumentReference]
    let pendingImages: [ChatAttachmentImage]
    let canUseThinking: Bool
    let isThinkingEnabled: Bool
    let isGenerating: Bool
    let canSendMessage: Bool
    let canPresentLiveVoice: Bool
    let canUseVision: Bool
    let isWebSearchEnabled: Bool
    @Binding var inputText: String
    @FocusState.Binding var isInputFocused: Bool
    let onOpenPersonaPicker: () -> Void
    let onRemoveDocument: (ConversationDocumentReference) -> Void
    let onRemovePendingImage: (UUID) -> Void
    let onOpenAttachmentImporter: () -> Void
    let onOpenCamera: () -> Void
    let onOpenPhotoLibrary: () -> Void
    let onToggleThinking: () -> Void
    let onVoiceTap: () -> Void
    let onSend: () -> Void
    let onStop: () -> Void
    let onToggleWebSearch: () -> Void



    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ChatComposerPersonaRow(persona: activePersona, onChangePersona: openPersonaPicker)

            if !pendingDocuments.isEmpty {
                ChatPendingDocumentStrip(
                    pendingDocuments: pendingDocuments,
                    onRemoveDocument: onRemoveDocument,
                    iconName: iconName(for:)
                )
            }

            if !pendingImages.isEmpty {
                ChatPendingImageStrip(
                    pendingImages: pendingImages,
                    onRemoveImage: onRemovePendingImage
                )
            }

            HStack(alignment: .bottom, spacing: 8) {
                Menu {
                    Button(action: onOpenAttachmentImporter) {
                        Label(String.appLocalized("chat.import_document"), systemImage: "doc.text")
                    }

                    if canUseVision {
                        Button(action: onOpenCamera) {
                            Label(String.appLocalized("chat.take_photo"), systemImage: "camera")
                        }

                        Button(action: onOpenPhotoLibrary) {
                            Label(String.appLocalized("chat.photo_library"), systemImage: "photo.on.rectangle")
                        }
                    }

                    Divider()

                    Toggle(isOn: Binding(
                        get: { isWebSearchEnabled },
                        set: { _ in onToggleWebSearch() }
                    )) {
                        Label(String.appLocalized("Web Search"), systemImage: "globe")
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.title3.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .foregroundStyle(BrandPalette.accent)
                        .liquidGlassSurface(
                            tint: BrandPalette.accent.opacity(0.12),
                            in: Circle(),
                            fallback: AnyShapeStyle(BrandPalette.accent.opacity(0.10)),
                            interactive: true
                        )
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Add attachment")

                if canUseThinking {
                    Button(action: onToggleThinking) {
                        Image(systemName: isThinkingEnabled ? "lightbulb.fill" : "lightbulb")
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .foregroundStyle(isThinkingEnabled ? .orange : .secondary)
                            .liquidGlassSurface(
                                tint: isThinkingEnabled ? .orange.opacity(0.2) : nil,
                                in: Circle(),
                                fallback: AnyShapeStyle(isThinkingEnabled ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12)),
                                interactive: true
                            )
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(isThinkingEnabled ? "Disable thinking" : "Enable thinking")
                }

                InputBarView(
                    text: $inputText,
                    isGenerating: isGenerating,
                    isSendEnabled: canSendMessage,
                    isVoiceEnabled: canPresentLiveVoice,
                    isFocused: $isInputFocused,
                    onVoiceTap: onVoiceTap,
                    onSend: onSend,
                    onStop: onStop
                )
            }
        }
        .frame(maxWidth: maxWidth)
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .liquidGlassSurface(
            tint: BrandPalette.navy.opacity(0.10),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous),
            fallback: AnyShapeStyle(.thinMaterial)
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

    private func openPersonaPicker() {
        isInputFocused = false
        onOpenPersonaPicker()
    }
}

private struct ChatComposerPersonaRow: View {
    let persona: Persona
    let onChangePersona: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: persona.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandPalette.primaryGradient)
                .frame(width: 30, height: 30)
                .liquidGlassSurface(
                    tint: BrandPalette.accent.opacity(0.14),
                    in: Circle(),
                    fallback: AnyShapeStyle(BrandPalette.accent.opacity(0.10))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(persona.localizedName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !persona.localizedDisplaySummary.isEmpty {
                    Text(persona.localizedDisplaySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button(String.appLocalized("common.change"), action: onChangePersona)
                .font(.caption.weight(.semibold))
                .liquidGlassButtonStyle(tint: BrandPalette.accent)
                .controlSize(.small)
                .frame(minHeight: 36)
        }
    }
}

private struct ChatPendingDocumentStrip: View {
    let pendingDocuments: [ConversationDocumentReference]
    let onRemoveDocument: (ConversationDocumentReference) -> Void
    let iconName: (ConversationDocumentKind) -> String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingDocuments) { document in
                    HStack(spacing: 6) {
                        Image(systemName: iconName(document.kind))
                            .foregroundStyle(BrandPalette.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.displayName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            Text(document.kind.displayName)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            onRemoveDocument(document)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 44, height: 44)
                        .accessibilityLabel("Remove document")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .liquidGlassSurface(
                        tint: BrandPalette.cyan.opacity(0.18),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous),
                        fallback: AnyShapeStyle(BrandPalette.cyan.opacity(0.1))
                    )
                }
            }
            .liquidGlassContainer(spacing: 10)
            .padding(.horizontal, 4)
        }
    }
}

private struct ChatPendingImageStrip: View {
    let pendingImages: [ChatAttachmentImage]
    let onRemoveImage: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(pendingImages) { image in
                    ZStack(alignment: .topTrailing) {
                        AttachmentImageThumbnailView(imageData: image.data, size: 60, cornerRadius: 8)

                        Button {
                            onRemoveImage(image.id)
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
            .padding(.horizontal, 4)
        }
    }
}


private struct ChatStatusCard: View {
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .liquidGlassSurface(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
    }
}

private struct ToolChainCardModifier: ViewModifier {
    let accentColor: Color

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .liquidGlassSurface(
                tint: accentColor.opacity(0.08),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous),
                fallback: AnyShapeStyle(accentColor.opacity(0.06))
            )
            .overlay(alignment: .leading) {
                UnevenRoundedRectangle(
                    topLeadingRadius: 16,
                    bottomLeadingRadius: 16,
                    bottomTrailingRadius: 0,
                    topTrailingRadius: 0
                )
                .fill(BrandPalette.primaryGradient)
                .frame(width: 2.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private extension View {
    func toolChainCard(accent: Color = BrandPalette.cyan) -> some View {
        modifier(ToolChainCardModifier(accentColor: accent))
    }
}

private struct ToolActivityChainView: View {
    let status: ToolActivityStatus

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                ToolActivityStepRow(
                    icon: "wand.and.stars",
                    text: String.appLocalized("tool.activity.planning"),
                    state: planningState
                )

                if let executionDetails {
                    ToolActivityConnector()
                    ToolActivityStepRow(
                        icon: executionDetails.icon,
                        text: executionDetails.text,
                        state: executionState
                    )
                }
            }
            .toolChainCard()

            Spacer(minLength: 36)
        }
    }

    private var planningState: ToolActivityStepState {
        switch status {
        case .planning:
            return .active
        case .running:
            return .completed
        }
    }

    private var executionState: ToolActivityStepState {
        switch status {
        case .planning:
            return .pending
        case .running:
            return .active
        }
    }

    private var executionDetails: (icon: String, text: String)? {
        switch status {
        case .planning:
            return nil
        case .running(let toolName, let displayInput):
            return toolExecutionPresentation(toolName: toolName, displayInput: displayInput)
        }
    }
}

private struct CompletedToolChainView: View {
    let trace: ToolCallTrace

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 0) {
                ToolActivityStepRow(
                    icon: "wand.and.stars",
                    text: String.appLocalized("tool.activity.planning"),
                    state: .completed
                )

                if let executionDetails = toolExecutionPresentation(
                    toolName: trace.toolName,
                    displayInput: trace.displayInput
                ) {
                    ToolActivityConnector()
                    ToolActivityStepRow(
                        icon: executionDetails.icon,
                        text: executionDetails.text,
                        state: trace.success ? .completed : .failed
                    )
                }

                if trace.success, trace.sourceCount > 0 {
                    ToolActivityConnector()
                    ToolActivityStepRow(
                        icon: "doc.text.magnifyingglass",
                        text: String(format: String.appLocalized("tool.trace.sources_found"), trace.sourceCount),
                        state: .completed
                    )
                }
            }
            .toolChainCard()

            Spacer(minLength: 36)
        }
    }
}

struct ToolTraceChainView: View {
    let trace: ToolCallTrace
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: trace.success ? toolTraceIcon(toolName: trace.toolName) : "exclamationmark.triangle")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(trace.success ? BrandPalette.cyan : .orange)
                        .frame(width: 24, height: 24)
                        .background(
                            Circle()
                                .fill(trace.success ? BrandPalette.cyan.opacity(0.14) : Color.orange.opacity(0.14))
                        )

                    Text(toolLabel)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(trace.success ? BrandPalette.cyan : .secondary)

                    if let duration = trace.durationSeconds {
                        Text(String(format: "%.1fs", duration))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(.fill.quaternary))
                    }

                    Spacer(minLength: 4)

                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 0 : -90))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ToolActivityStepRow(
                        icon: "wand.and.stars",
                        text: String.appLocalized("tool.activity.planning"),
                        state: .completed
                    )

                    if let executionDetails = toolExecutionPresentation(
                        toolName: trace.toolName,
                        displayInput: trace.displayInput
                    ) {
                        ToolActivityConnector()
                        ToolActivityStepRow(
                            icon: executionDetails.icon,
                            text: executionDetails.text,
                            state: trace.success ? .completed : .failed
                        )
                    }

                    if trace.success, trace.sourceCount > 0 {
                        ToolActivityConnector()
                        ToolActivityStepRow(
                            icon: "doc.text.magnifyingglass",
                            text: String(format: String.appLocalized("tool.trace.sources_found"), trace.sourceCount),
                            state: .completed
                        )
                    }
                }
                .padding(.top, 10)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .toolChainCard(accent: trace.success ? BrandPalette.cyan : .orange)
    }

    private var toolLabel: String {
        toolTraceLabel(toolName: trace.toolName, success: trace.success)
    }
}

private func toolExecutionPresentation(toolName: String, displayInput: String?) -> (icon: String, text: String)? {
    switch toolName {
    case "web_search":
        guard let displayInput, !displayInput.isEmpty else { return nil }
        return ("globe", String(format: String.appLocalized("tool.activity.searching"), displayInput))
    case "read_url":
        guard let displayInput, !displayInput.isEmpty else { return nil }
        return ("link", String(format: String.appLocalized("tool.activity.read_url"), displayInput))
    case "ocr_image_text":
        return ("text.viewfinder", String.appLocalized("tool.activity.ocr_image_text"))
    default:
        return nil
    }
}

private func toolTraceLabel(toolName: String, success: Bool) -> String {
    switch (toolName, success) {
    case ("read_url", true):
        return String.appLocalized("tool.trace.read_url")
    case ("read_url", false):
        return String.appLocalized("tool.trace.read_url_failed")
    case ("ocr_image_text", true):
        return String.appLocalized("tool.trace.ocr_image_text")
    case ("ocr_image_text", false):
        return String.appLocalized("tool.trace.ocr_image_text_failed")
    case ("web_search", true):
        return String.appLocalized("tool.trace.web_search")
    case ("web_search", false):
        return String.appLocalized("tool.trace.web_search_failed")
    default:
        return success ? toolName : "\(toolName) Failed"
    }
}

private func toolTraceIcon(toolName: String) -> String {
    switch toolName {
    case "read_url":
        return "link"
    case "ocr_image_text":
        return "text.viewfinder"
    case "web_search":
        return "globe"
    default:
        return "wand.and.stars"
    }
}

enum ToolActivityStepState {
    case pending
    case active
    case completed
    case failed
}

struct ToolActivityStepRow: View {
    let icon: String
    let text: String
    let state: ToolActivityStepState

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                switch state {
                case .active:
                    ProgressView()
                        .controlSize(.mini)
                        .tint(BrandPalette.cyan)
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.green)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.red)
                case .pending:
                    Image(systemName: "circle")
                        .font(.caption)
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(width: 18, height: 18)

            Image(systemName: icon)
                .font(.caption2.weight(.bold))
                .foregroundStyle(iconColor)
                .frame(width: 14)

            Text(text)
                .font(.callout)
                .foregroundStyle(textColor)
                .lineLimit(2)
        }
    }

    private var iconColor: Color {
        switch state {
        case .active: BrandPalette.cyan
        case .completed: .secondary
        case .failed: .secondary
        case .pending: Color(.quaternaryLabel)
        }
    }

    private var textColor: Color {
        switch state {
        case .active: .primary
        case .completed: .secondary
        case .failed: .secondary
        case .pending: Color(.quaternaryLabel)
        }
    }
}

struct ToolActivityConnector: View {
    var body: some View {
        Capsule()
            .fill(BrandPalette.cyan.opacity(0.18))
            .frame(width: 2, height: 12)
            .padding(.leading, 8)
    }
}

private struct ChatGeneratingIndicator: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(BrandPalette.cyan)
            Text(String.appLocalized("chat.generating"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 2)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
    }
}

private struct ChatNoticeBanner: View {
    enum Style {
        case error(isOOM: Bool)
        case info
    }

    let style: Style
    let message: String
    let title: String?
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 2) {
                if let title {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(titleColor)
                }
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .accessibilityLabel(dismissLabel)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassSurface(
            tint: tintColor,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            fallback: AnyShapeStyle(fallbackColor)
        )
        .padding(.horizontal)
    }

    private var iconName: String {
        switch style {
        case .error(let isOOM):
            isOOM ? "exclamationmark.triangle.fill" : "exclamationmark.circle.fill"
        case .info:
            "globe"
        }
    }

    private var iconColor: Color {
        switch style {
        case .error(let isOOM):
            isOOM ? .red : .orange
        case .info:
            BrandPalette.cyan
        }
    }

    private var titleColor: Color {
        switch style {
        case .error:
            .red
        case .info:
            .primary
        }
    }

    private var tintColor: Color {
        switch style {
        case .error(let isOOM):
            return isOOM ? .red.opacity(0.18) : .orange.opacity(0.18)
        case .info:
            return BrandPalette.cyan.opacity(0.16)
        }
    }

    private var fallbackColor: Color {
        switch style {
        case .error(let isOOM):
            return isOOM ? Color.red.opacity(0.1) : Color.orange.opacity(0.12)
        case .info:
            return BrandPalette.cyan.opacity(0.08)
        }
    }

    private var dismissLabel: String {
        switch style {
        case .error:
            "Dismiss error"
        case .info:
            "Dismiss notice"
        }
    }
}

private struct ChatMemoryNoticeView: View {
    let notice: ChatMemoryNotice
    let title: String
    let onOpenMemoryLibrary: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.kind == .pending ? "brain.head.profile" : "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(notice.kind == .pending ? BrandPalette.cyan : .green)
                .frame(width: 30, height: 30)
                .liquidGlassSurface(
                    tint: notice.kind == .pending ? BrandPalette.cyan.opacity(0.18) : Color.green.opacity(0.18),
                    in: Circle(),
                    fallback: AnyShapeStyle(notice.kind == .pending ? BrandPalette.cyan.opacity(0.1) : Color.green.opacity(0.1))
                )

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if notice.kind == .pending {
                    Button(String.appLocalized("settings.manage_memory"), action: onOpenMemoryLibrary)
                        .liquidGlassButtonStyle(tint: BrandPalette.cyan)
                        .controlSize(.small)
                        .frame(minHeight: 32)
                }
            }

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .liquidGlassSurface(
                        in: Circle(),
                        fallback: AnyShapeStyle(Color.secondary.opacity(0.1)),
                        interactive: true
                    )
            }
            .buttonStyle(.plain)
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(String.appLocalized("memory.notice.dismiss"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemBackground))
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(notice.kind == .pending ? BrandPalette.cyan.opacity(0.18) : Color.green.opacity(0.16))
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(notice.kind == .pending ? BrandPalette.cyan.opacity(0.30) : Color.green.opacity(0.24), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
        .padding(.horizontal)
    }
}

#Preview("Chat Empty State") {
    ChatEmptyStateView()
}
