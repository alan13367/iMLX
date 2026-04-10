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
    @State private var showAttachmentPanel = false
    @State private var showWebSearchDisclosure = false
    @State private var showLiveVoice = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var utilitySheet: ChatUtilitySheet?
    @State private var streamingScrollTask: Task<Void, Never>?
    @State private var streamingAutoscrollEnabled = true
    @State private var contentOverflows = false
    @State private var scrollPinnedToBottom = true
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
                Menu {
                    Button {
                        isInputFocused = false
                        utilitySheet = .conversations
                    } label: {
                        Label(String.appLocalized("conversation.title.chats"), systemImage: "bubble.left.and.bubble.right")
                    }

                    Button {
                        isInputFocused = false
                        utilitySheet = .models
                    } label: {
                        Label(String.appLocalized("tab.models"), systemImage: "arrow.down.circle")
                    }

                    Button {
                        isInputFocused = false
                        utilitySheet = .settings
                    } label: {
                        Label(String.appLocalized("tab.settings"), systemImage: "gearshape")
                    }
                } label: {
                    Image(systemName: "line.3.horizontal")
                }
                .accessibilityLabel("Open app menu")
            }
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
                            .font(.body)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Unload model")
                }

                Button {
                    isInputFocused = false
                    streamingAutoscrollEnabled = true
                    chatViewModel.startNewConversation()
                    inputText = ""
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.body)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("New conversation")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .simultaneousGesture(
            TapGesture().onEnded {
                isInputFocused = false
            }
        )
        .simultaneousGesture(openConversationHistoryGesture)
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
        .onChange(of: appState.activeConversationId) { _, _ in
            streamingAutoscrollEnabled = true
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
        .sheet(isPresented: $showLiveVoice) {
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
                ConversationListView(appState: appState, presentation: .modalSheet) { _ in
                    utilitySheet = nil
                }
            case .models:
                ModelBrowserView(appState: appState)
            case .memoryLibrary:
                MemoryLibraryView(appState: appState)
            case .settings:
                SettingsView(appState: appState)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(String.appLocalized("common.done")) {
                    utilitySheet = nil
                }
            }
        }
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
            .liquidGlassSurface(in: Capsule(), interactive: true)
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
            ZStack(alignment: .bottom) {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(chatViewModel.messages) { message in
                            MessageBubbleView(message: message)
                                .equatable()
                                .id(message.id)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }
                        if !chatViewModel.currentResponse.isEmpty {
                            MessageBubbleView(
                                message: ChatMessage(
                                    role: .assistant,
                                    content: chatViewModel.currentResponse + (chatViewModel.isGenerating ? "▊" : "")
                                ),
                                isStreaming: true,
                                parsedAssistantContent: chatViewModel.currentParsedResponse
                            )
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
                .onScrollPhaseChange { _, newPhase in
                    guard newPhase == .tracking || newPhase == .interacting else { return }
                    guard chatViewModel.isGenerating else { return }
                    guard streamingAutoscrollEnabled else { return }
                    streamingScrollTask?.cancel()
                    streamingScrollTask = nil
                    streamingAutoscrollEnabled = false
                }
                .onChange(of: chatViewModel.messages.count) {
                    guard streamingAutoscrollEnabled else { return }
                    streamingScrollTask?.cancel()
                    withAnimation {
                        proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
                    }
                }
                .onChange(of: chatViewModel.currentResponse.count) {
                    guard streamingAutoscrollEnabled else { return }
                    guard chatViewModel.isGenerating else { return }
                    guard streamingScrollTask == nil else { return }
                    streamingScrollTask = Task { @MainActor in
                        defer { streamingScrollTask = nil }
                        try? await Task.sleep(for: .milliseconds(50))
                        guard !Task.isCancelled else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
                            proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
                        }
                    }
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

    private func resumeAutoscroll(using proxy: ScrollViewProxy) {
        streamingScrollTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
        }
        streamingAutoscrollEnabled = true
        streamingScrollTask = Task { @MainActor in
            defer { streamingScrollTask = nil }
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("chatBottomAnchor", anchor: .bottom)
            }
        }
    }

    private var bottomAccessoryStack: some View {
        bottomAccessoryContent
            .liquidGlassContainer(spacing: 16)
            .padding(.top, 8)
    }

    private var bottomAccessoryContent: some View {
        VStack(spacing: 8) {
            if let errorMessage = chatViewModel.errorMessage {
                errorBanner(message: errorMessage)
            }

            if let webSearchNotice = chatViewModel.webSearchNotice {
                infoBanner(message: webSearchNotice)
            }

            if chatViewModel.isModelLoading {
                modelLoadingCard
            }

            if chatViewModel.isGenerating {
                generatingIndicator
            }

            if let memoryNotice = chatViewModel.memoryNotice {
                memoryNoticeCard(memoryNotice)
            }

            inputBar
        }
    }

    private var composerPersonaRow: some View {
        HStack(spacing: 10) {
            Image(systemName: chatViewModel.activePersona.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(BrandPalette.primaryGradient)
                .frame(width: 30, height: 30)
                .liquidGlassSurface(
                    tint: BrandPalette.accent.opacity(0.14),
                    in: Circle(),
                    fallback: AnyShapeStyle(BrandPalette.accent.opacity(0.10))
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(chatViewModel.activePersona.localizedName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                if !chatViewModel.activePersona.localizedDisplaySummary.isEmpty {
                    Text(chatViewModel.activePersona.localizedDisplaySummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Button {
                isInputFocused = false
                showPersonaPicker = true
            } label: {
                Text(String.appLocalized("common.change"))
                    .font(.caption.weight(.semibold))
            }
            .liquidGlassButtonStyle(tint: BrandPalette.accent)
            .controlSize(.small)
            .frame(minHeight: 36)
        }
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
        .frame(maxWidth: bottomChromeMaxWidth)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .liquidGlassSurface(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
    }

    private var generatingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(BrandPalette.cyan)
            Text(String.appLocalized("chat.generating"))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: bottomChromeMaxWidth)
        .padding(.horizontal, 20)
        .padding(.vertical, 2)
        .padding(.horizontal)
        .accessibilityElement(children: .combine)
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
        .frame(maxWidth: bottomChromeMaxWidth)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassSurface(
            tint: isOOMError(message) ? .red.opacity(0.18) : .orange.opacity(0.18),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            fallback: AnyShapeStyle(isOOMError(message) ? Color.red.opacity(0.1) : Color.orange.opacity(0.12))
        )
        .padding(.horizontal)
    }

    private func infoBanner(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .foregroundStyle(BrandPalette.cyan)
            Text(message)
                .font(.caption)
                .foregroundStyle(.primary)
            Spacer()
            Button {
                chatViewModel.webSearchNotice = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: bottomChromeMaxWidth)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .liquidGlassSurface(
            tint: BrandPalette.cyan.opacity(0.16),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous),
            fallback: AnyShapeStyle(BrandPalette.cyan.opacity(0.08))
        )
        .padding(.horizontal)
    }

    private func memoryNoticeCard(_ notice: ChatMemoryNotice) -> some View {
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
                Text(memoryNoticeTitle(for: notice))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(notice.message)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)

                if notice.kind == .pending {
                    Button(String.appLocalized("settings.manage_memory")) {
                        isInputFocused = false
                        utilitySheet = .memoryLibrary
                    }
                    .liquidGlassButtonStyle(tint: BrandPalette.cyan)
                    .controlSize(.small)
                    .frame(minHeight: 32)
                }
            }

            Spacer(minLength: 8)

            Button {
                chatViewModel.dismissMemoryNotice()
            } label: {
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
        .frame(maxWidth: bottomChromeMaxWidth, alignment: .leading)
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

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSendMessage else { return }
        inputText = ""
        streamingAutoscrollEnabled = true
        chatViewModel.sendMessage(text)
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

    private var inputBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            composerPersonaRow

            if !chatViewModel.pendingDocuments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chatViewModel.pendingDocuments) { document in
                            HStack(spacing: 6) {
                                Image(systemName: iconName(for: document.kind))
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

            if !chatViewModel.pendingImages.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(chatViewModel.pendingImages) { image in
                            ZStack(alignment: .topTrailing) {
                                AttachmentImageThumbnailView(imageData: image.data, size: 60, cornerRadius: 8)

                                Button {
                                    chatViewModel.removePendingImage(id: image.id)
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

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    isInputFocused = false
                    showAttachmentPanel.toggle()
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
                .popover(isPresented: $showAttachmentPanel, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                    attachmentPanel
                        .presentationCompactAdaptation(.popover)
                }

                if chatViewModel.canUseThinking {
                    Button {
                        chatViewModel.toggleThinking()
                    } label: {
                        Image(systemName: chatViewModel.isThinkingEnabled ? "lightbulb.fill" : "lightbulb")
                            .font(.title3)
                            .frame(width: 32, height: 32)
                            .foregroundStyle(chatViewModel.isThinkingEnabled ? .orange : .secondary)
                            .liquidGlassSurface(
                                tint: chatViewModel.isThinkingEnabled ? .orange.opacity(0.2) : nil,
                                in: Circle(),
                                fallback: AnyShapeStyle(chatViewModel.isThinkingEnabled ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12)),
                                interactive: true
                            )
                    }
                    .frame(width: 44, height: 44)
                    .accessibilityLabel(chatViewModel.isThinkingEnabled ? "Disable thinking" : "Enable thinking")
                }

                InputBarView(
                    text: $inputText,
                    isGenerating: chatViewModel.isGenerating,
                    isSendEnabled: canSendMessage,
                    isVoiceEnabled: canPresentLiveVoice,
                    isFocused: $isInputFocused,
                    onVoiceTap: { showLiveVoice = true },
                    onSend: sendMessage,
                    onStop: chatViewModel.stopGeneration
                )
            }
        }
        .frame(maxWidth: bottomChromeMaxWidth)
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

    private var attachmentPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            attachmentPanelButton(
                String.appLocalized("chat.import_document"),
                systemImage: "doc.text"
            ) {
                closeAttachmentPanelThen {
                    showDocumentImporter = true
                }
            }

            if chatViewModel.canUseVision {
                attachmentPanelButton(
                    String.appLocalized("chat.take_photo"),
                    systemImage: "camera"
                ) {
                    closeAttachmentPanelThen {
                        showCamera = true
                    }
                }

                attachmentPanelButton(
                    String.appLocalized("chat.photo_library"),
                    systemImage: "photo.on.rectangle"
                ) {
                    closeAttachmentPanelThen {
                        showPhotoLibrary = true
                    }
                }
            }

            Divider()
                .padding(.vertical, 4)

            webSearchToggleRow
        }
        .padding(10)
        .frame(width: 286)
        .liquidGlassSurface(
            tint: BrandPalette.navy.opacity(0.08),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous),
            fallback: AnyShapeStyle(.thinMaterial)
        )
    }

    private func attachmentPanelButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(BrandPalette.accent)
                    .frame(width: 24, height: 24)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                Spacer(minLength: 8)
            }
            .frame(minHeight: 44)
            .padding(.horizontal, 8)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    private var webSearchToggleRow: some View {
        Button {
            handleWebSearchToggleTap()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .font(.body)
                    .foregroundStyle(BrandPalette.cyan)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String.appLocalized("Web Search"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(String.appLocalized("web_search.menu.subtitle"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                WebSearchPillSwitch(isOn: chatViewModel.isWebSearchEnabled)
            }
            .frame(minHeight: 52)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String.appLocalized("Web Search"))
        .accessibilityValue(
            chatViewModel.isWebSearchEnabled
                ? String.appLocalized("web_search.state.on")
                : String.appLocalized("web_search.state.off")
        )
        .accessibilityHint(String.appLocalized("web_search.menu.accessibility_hint"))
        .accessibilityAddTraits(.isButton)
    }

    private var bottomChromeMaxWidth: CGFloat {
        horizontalSizeClass == .regular ? 760 : .infinity
    }

    private var canSendMessage: Bool {
        !chatViewModel.isModelLoading && !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canPresentLiveVoice: Bool {
        !chatViewModel.isModelLoading
            && !chatViewModel.isGenerating
            && appState.loadedModelId != nil
            && !isRunningOnSimulator
    }

    private func handleWebSearchToggleTap() {
        if chatViewModel.isWebSearchEnabled {
            showAttachmentPanel = false
            chatViewModel.setWebSearchEnabled(false)
        } else {
            closeAttachmentPanelThen {
                showWebSearchDisclosure = true
            }
        }
    }

    private func closeAttachmentPanelThen(_ action: @escaping () -> Void) {
        showAttachmentPanel = false
        Task { @MainActor in
            await Task.yield()
            action()
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

    private var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }
}
