import SwiftUI
import PhotosUI
import UIKit
import UniformTypeIdentifiers

struct ChatView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var chatViewModel: ChatViewModel
    @State private var inputText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var showCamera = false
    @State private var showPhotoLibrary = false
    @State private var showDocumentImporter = false
    @State private var showWebSearchDisclosure = false
    @State private var showLiveVoice = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var utilitySheet: ChatUtilitySheet?
    @State private var toast: ChatToastModel?
    @State private var toastDismissTask: Task<Void, Never>?
    @State private var downloadedModels: [ModelInfo] = []
    @State private var conversationHistorySwipePrimed = false
    @State private var didRequestLaunchKeyboard = false
    @State private var hapticSelectionTrigger = 0
    @State private var hapticMediumTrigger = 0
    @State private var hapticLightTrigger = 0
    let appState: AppState
    let conversationId: UUID

    init(appState: AppState, conversationId: UUID) {
        self.appState = appState
        self.conversationId = conversationId
        self._chatViewModel = State(initialValue: ChatViewModel(appState: appState))
    }

    var body: some View {
        visibleChatContent
        .overlay(alignment: .top) {
            ChatToastView(toast: toast)
                .padding(.top, 4)
        }
        .navigationTitle(conversationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            chatAccessoryInset
        }
        .toolbar {
            if #available(iOS 27, *) {
                ToolbarItem(placement: .topBarLeading) {
                    leadingToolbarContent
                }
                .visibilityPriority(.high)

                ToolbarItem(placement: .principal) {
                    principalToolbarContent
                }
                .visibilityPriority(.low)

                ToolbarItem(placement: .topBarPinnedTrailing) {
                    trailingToolbarContent
                }
            } else {
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
        }
        .chatNavigationToolbarBehavior()
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
            Task { await refreshDownloadedModels() }
            requestLaunchKeyboardIfReady()
        }
        .onChange(of: chatViewModel.isModelLoading) { _, _ in
            handlePendingShortcutRoute()
            requestLaunchKeyboardIfReady()
        }
        .onChange(of: utilitySheet) { oldValue, newValue in
            if oldValue == .models, newValue == nil {
                Task { await refreshDownloadedModels() }
            }
            if newValue == nil {
                requestLaunchKeyboardIfReady()
            }
        }
        .task(id: appState.modelDownloadSnapshots.count) {
            await refreshDownloadedModels()
        }
        .task {
            await refreshDownloadedModels()
            requestLaunchKeyboardIfReady()
        }
        .onChange(of: selectedPhotoItem) { _, _ in
            if let item = selectedPhotoItem {
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        chatViewModel.appendPendingImage(data)
                        selectedPhotoItem = nil
                    } else {
                        selectedPhotoItem = nil
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
        .sensoryFeedback(.selection, trigger: hapticSelectionTrigger)
        .sensoryFeedback(.impact(weight: .medium), trigger: hapticMediumTrigger)
        .sensoryFeedback(.impact(weight: .light), trigger: hapticLightTrigger)
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
                .contentShape(Rectangle())
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
                lastFailedUserMessageId: chatViewModel.lastFailedUserMessageId,
                conversationResetKey: appState.activeConversationId ?? conversationId,
                onTranscriptTap: { isInputFocused = false },
                onCopy: copyText(_:),
                onRetry: retryLastUserMessage,
                onOpenSourceURL: openSourceURL(_:)
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
            state: ChatAccessoryStackState(
                horizontalSizeClass: horizontalSizeClass,
                errorMessage: chatViewModel.errorMessage,
                toolNotice: chatViewModel.toolNotice,
                isModelLoading: chatViewModel.isModelLoading,
                selectedModelDisplayName: chatViewModel.loadingModel?.displayName ?? appState.selectedModel?.displayName,
                isGenerating: chatViewModel.isGenerating,
                memoryNotice: chatViewModel.memoryNotice,
                pendingDocuments: chatViewModel.pendingDocuments,
                pendingImages: chatViewModel.pendingImages,
                canUseThinking: chatViewModel.canUseThinking,
                isThinkingEnabled: chatViewModel.isThinkingEnabled,
                canSendMessage: canSendMessage,
                canPresentLiveVoice: canPresentLiveVoice,
                canUseVision: chatViewModel.canUseVision,
                isWebSearchEnabled: chatViewModel.isWebSearchEnabled
            ),
            actions: ChatAccessoryStackActions(
                dismissError: dismissError,
                dismissToolNotice: dismissToolNotice,
                dismissMemoryNotice: chatViewModel.dismissMemoryNotice,
                openMemoryLibrary: openMemoryLibrary,
                composer: ChatComposerActions(
                    removeDocument: chatViewModel.removeDocument,
                    removePendingImage: chatViewModel.removePendingImage(id:),
                    openAttachmentImporter: openDocumentImporter,
                    openCamera: openCamera,
                    openPhotoLibrary: openPhotoLibrary,
                    toggleThinking: chatViewModel.toggleThinking,
                    voiceTap: openLiveVoice,
                    send: sendMessage,
                    stop: { chatViewModel.stopGeneration() },
                    toggleWebSearch: handleWebSearchToggleTap
                )
            ),
            inputText: $inputText,
            isInputFocused: $isInputFocused
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
        DragGesture(minimumDistance: ConversationHistorySwipe.minimumDistance, coordinateSpace: .local)
            .onChanged { value in
                guard !conversationHistorySwipePrimed else { return }
                guard shouldPrimeConversationHistorySwipe(from: value) else { return }
                conversationHistorySwipePrimed = true
                hapticSelectionTrigger += 1
            }
            .onEnded { value in
                defer { conversationHistorySwipePrimed = false }
                guard shouldOpenConversationHistory(from: value) else { return }
                isInputFocused = false
                utilitySheet = .conversations
                hapticMediumTrigger += 1
            }
    }

    private func shouldPrimeConversationHistorySwipe(from value: DragGesture.Value) -> Bool {
        shouldRecognizeConversationHistorySwipe(
            from: value,
            horizontalThreshold: ConversationHistorySwipe.primeHorizontalDistance,
            predictedThreshold: ConversationHistorySwipe.primePredictedDistance
        )
    }

    private func shouldOpenConversationHistory(from value: DragGesture.Value) -> Bool {
        shouldRecognizeConversationHistorySwipe(
            from: value,
            horizontalThreshold: ConversationHistorySwipe.commitHorizontalDistance,
            predictedThreshold: ConversationHistorySwipe.commitPredictedDistance
        )
    }

    private func shouldRecognizeConversationHistorySwipe(
        from value: DragGesture.Value,
        horizontalThreshold: CGFloat,
        predictedThreshold: CGFloat
    ) -> Bool {
        guard utilitySheet == nil else { return false }
        guard value.startLocation.x <= ConversationHistorySwipe.edgeActivationWidth else { return false }

        let horizontalDistance = value.translation.width
        let verticalDistance = abs(value.translation.height)
        guard horizontalDistance > horizontalThreshold else { return false }
        guard horizontalDistance > verticalDistance * ConversationHistorySwipe.horizontalDominance else { return false }
        return value.predictedEndTranslation.width > predictedThreshold
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
        ChatModelStatusMenu(
            isModelLoading: chatViewModel.isModelLoading,
            selectedModelDisplayName: chatViewModel.loadingModel?.displayName ?? appState.selectedModel?.displayName,
            loadedModelId: appState.loadedModelId,
            loadedModelDisplayName: appState.modelInfo(id: appState.loadedModelId)?.displayName,
            downloadedModels: downloadedModels,
            onSelectModel: selectModelFromMenu,
            onUnload: unloadModelFromMenu,
            onManageModels: openModels
        )
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

    private func copyText(_ text: String) {
        UIPasteboard.general.setValue(text, forPasteboardType: UTType.plainText.identifier)
        hapticLightTrigger += 1
        presentToast(
            ChatToastModel(
                message: String.appLocalized("message.copied"),
                symbol: "checkmark.circle.fill"
            )
        )
    }

    private func retryLastUserMessage() {
        chatViewModel.retryLastUserMessage()
    }

    private func openSourceURL(_ url: URL?) {
        guard let url else { return }
        UIApplication.shared.open(url)
    }

    private func refreshDownloadedModels() async {
        let refreshed = await appState.reconcileModelCatalogState()
        downloadedModels = refreshed
    }

    private func selectModelFromMenu(_ model: ModelInfo) {
        #if targetEnvironment(simulator)
        Task { @MainActor in
            await chatViewModel.unloadModel()
            chatViewModel.errorMessage = InferenceError.simulatorUnsupported.localizedDescription
        }
        #else
        Task { @MainActor in
            await chatViewModel.loadModel(model)
        }
        #endif
    }

    private func unloadModelFromMenu() {
        Task { @MainActor in
            await chatViewModel.unloadModel()
        }
    }

    private func presentToast(_ model: ChatToastModel) {
        toast = model
        toastDismissTask?.cancel()
        toastDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.22)) {
                toast = nil
            }
        }
    }

    private func dismissToolNotice() {
        chatViewModel.toolNotice = nil
    }

    private func openMemoryLibrary() {
        isInputFocused = false
        utilitySheet = .memoryLibrary
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

    private func startNewConversation() {
        isInputFocused = false
        chatViewModel.startNewConversation()
        inputText = ""
    }

    private func requestLaunchKeyboardIfReady() {
        guard appState.openKeyboardOnLaunch else { return }
        guard !didRequestLaunchKeyboard else { return }
        guard appState.hasCompletedOnboarding else { return }
        guard appState.loadedModelId != nil else { return }
        guard !chatViewModel.isModelLoading else { return }
        guard !chatViewModel.isGenerating else { return }
        guard utilitySheet == nil else { return }
        guard !showLiveVoice else { return }

        didRequestLaunchKeyboard = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard appState.openKeyboardOnLaunch else { return }
            guard appState.loadedModelId != nil else { return }
            guard !chatViewModel.isModelLoading && !chatViewModel.isGenerating else { return }
            guard utilitySheet == nil && !showLiveVoice else { return }
            isInputFocused = true
        }
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

        if appState.selectedModel == nil && utilitySheet != .models {
            openModels()
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

private extension View {
    @ViewBuilder
    func chatNavigationToolbarBehavior() -> some View {
        if #available(iOS 27, *) {
            toolbarMinimizeBehavior(.never, for: .navigationBar)
        } else {
            self
        }
    }
}

#Preview("Chat Empty State") {
    ChatEmptyStateView()
}
