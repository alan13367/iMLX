import Foundation
import FoundationModels
import SwiftUI

enum ChatMemoryNoticeKind: String, Equatable {
    case saved
    case forgotten
    case pending
}

struct ChatMemoryNotice: Equatable, Identifiable {
    let id = UUID()
    let kind: ChatMemoryNoticeKind
    let message: String
    let eventKey: String

    var suppressionKey: String {
        "\(kind.rawValue):\(eventKey)"
    }
}

enum ToolActivityStatus: Equatable {
    case planning
    case running(toolName: String, displayInput: String?)
}

private enum ChatGenerationAbort: LocalizedError {
    case lowMemory(UInt64)

    var errorDescription: String? {
        switch self {
        case .lowMemory(let availableMB):
            String(format: String.appLocalized("error.chat.generation_memory_abort"), availableMB)
        }
    }
}

@Observable
final class ChatViewModel {
    private enum ReplyMode {
        case standard
        case liveVoice
    }

    private struct GenerationBudget {
        let streamMaxTokens: Int
        let hiddenThinkingMaxTokens: Int?
        let finalAnswerMaxTokens: Int
    }

    var messages: [ChatMessage] = []
    var currentResponse: String = ""
    var currentParsedResponse: ParsedAssistantContent = .empty
    var isGenerating: Bool = false
    var isModelLoading: Bool = false
    var loadingModel: ModelInfo?
    var errorMessage: String?
    var memoryNotice: ChatMemoryNotice?
    var activeConversationId: UUID?
    var isThinkingEnabled: Bool = false
    var isWebSearchEnabled: Bool = false
    var toolNotice: String?
    var toolActivityStatus: ToolActivityStatus?
    var currentToolTrace: ToolCallTrace?
    var lastFailedUserMessageId: UUID?

    var canUseThinking: Bool {
        resolvedCurrentModel()?.supportsThinking == true
    }

    var canUseVision: Bool {
        resolvedCurrentModel()?.supportsVision == true
    }

    var pendingImages: [ChatAttachmentImage] = []
    var pendingDocuments: [ConversationDocumentReference] = []
    var attachedDocuments: [ConversationDocumentReference] = []

    private var inferenceService: InferenceService { appState.inferenceService }
    private var downloadService: ModelDownloadService { appState.downloadService }
    private var generationTask: Task<ChatMessage?, Never>?
    private let appState: AppState
    private let deviceCapabilityService: DeviceCapabilityService
    private var capabilityModelId: String?
    private var memoryExtractionTasks: [UUID: Task<Void, Never>] = [:]
    private var titleGenerationTasks: [UUID: Task<Void, Never>] = [:]
    private var suppressedMemoryNoticeKey: String?
    private var shouldDiscardCancelledGeneration = false

    init(appState: AppState, deviceCapabilityService: DeviceCapabilityService = DeviceCapabilityService()) {
        self.appState = appState
        self.deviceCapabilityService = deviceCapabilityService
        updateThinkingAvailability(for: resolvedCurrentModel())
    }

    deinit {
        generationTask?.cancel()
        for task in memoryExtractionTasks.values {
            task.cancel()
        }
        for task in titleGenerationTasks.values {
            task.cancel()
        }
    }

    @MainActor
    func loadConversation(_ conversation: Conversation) {
        activeConversationId = conversation.id
        messages = conversation.messages
        attachedDocuments = conversation.documents
        pendingDocuments = conversation.messages.isEmpty ? conversation.documents : []
        currentResponse = ""
        currentParsedResponse = .empty
        errorMessage = nil
        memoryNotice = nil
        suppressedMemoryNoticeKey = nil
        isWebSearchEnabled = conversation.webSearchEnabled
        toolNotice = nil
        toolActivityStatus = nil
        currentToolTrace = nil
        lastFailedUserMessageId = nil
        updateThinkingAvailability(for: resolvedCurrentModel())
    }

    @MainActor
    func sendMessage(_ text: String) {
        let normalizedText = prepareToSendMessage(text)
        guard let normalizedText else { return }
        shouldDiscardCancelledGeneration = false
        generationTask = Task<ChatMessage?, Never> { @MainActor [self] in
            return await self.performSendMessage(normalizedText, allowPostReplyTasks: true, replyMode: .standard)
        }
    }

    @MainActor
    func sendMessageAndWait(_ text: String, allowPostReplyTasks: Bool = true, isLiveVoiceReply: Bool = false) async -> ChatMessage? {
        let normalizedText = prepareToSendMessage(text)
        guard let normalizedText else { return nil }
        shouldDiscardCancelledGeneration = false
        let replyMode: ReplyMode = isLiveVoiceReply ? .liveVoice : .standard
        let task = Task<ChatMessage?, Never> { @MainActor [self] in
            return await self.performSendMessage(normalizedText, allowPostReplyTasks: allowPostReplyTasks, replyMode: replyMode)
        }
        generationTask = task
        return await task.value
    }

    @MainActor
    func setWebSearchEnabled(_ enabled: Bool) {
        isWebSearchEnabled = enabled
        saveCurrentConversation()
    }

    @MainActor
    private func prepareToSendMessage(_ text: String) -> String? {
        guard !isGenerating else { return nil }
        guard !isModelLoading else {
            errorMessage = String.appLocalized("error.chat.model_still_loading")
            Haptics.notificationWarning()
            return nil
        }
        guard appState.loadedModelId != nil else {
            errorMessage = String.appLocalized("error.chat.no_model_loaded")
            Haptics.notificationWarning()
            return nil
        }

        let availableMB = deviceCapabilityService.availableMemoryMB
        if availableMB > 0 && availableMB < 200 {
            errorMessage = String(format: String.appLocalized("error.chat.low_memory"), availableMB)
            Haptics.notificationWarning()
            return nil
        }

        if activeConversationId == nil {
            let id = appState.createNewConversation()
            activeConversationId = id
        }

        return text
    }

    @MainActor
    private func performSendMessage(_ text: String, allowPostReplyTasks: Bool, replyMode: ReplyMode) async -> ChatMessage? {
        let loadedModel = resolvedCurrentModel()
        let history = promptHistory(from: messages, for: loadedModel)
        Self.debugToolLog(
            "send start: model=\(loadedModel?.displayName ?? "none") webSearchEnabled=\(isWebSearchEnabled) " +
            "historyCount=\(history.count) userMessage=\(Self.sanitizedToolLogSnippet(text))"
        )
        let userMessage = ChatMessage(
            role: .user,
            content: text,
            attachedImages: pendingImages.isEmpty ? nil : pendingImages,
            attachedDocuments: pendingDocuments.isEmpty ? nil : pendingDocuments
        )
        let toolContext = await appState.toolCallingService.context(
            for: userMessage,
            attachedDocuments: attachedDocuments,
            hasNewlyAttachedDocuments: !pendingDocuments.isEmpty
        )
        messages.append(userMessage)
        let handledExplicitMemoryCommand = handleExplicitMemoryCommands(in: text, userMessage: userMessage)

        isGenerating = true
        currentResponse = ""
        currentParsedResponse = .empty
        errorMessage = nil
        toolNotice = nil
        toolActivityStatus = nil
        lastFailedUserMessageId = nil
        pendingImages.removeAll()
        pendingDocuments.removeAll()

        Haptics.impactLight()

        let temperature = Float(appState.effectiveAssistantTemperature)
        let topP = Constants.Generation.defaultTopP
        let repetitionPenalty = Constants.Generation.defaultRepetitionPenalty
        let systemPrompt = appState.effectiveAssistantSystemPrompt
        let thinkingEnabled = loadedModel?.supportsThinking == true ? isThinkingEnabled : false
        let generationBudget = generationBudget(for: loadedModel, thinkingEnabled: thinkingEnabled)

        let startTime = Date()
        var tokenCount = 0
        var accumulatedResponse = ""
        var latestParsedResponse = ParsedAssistantContent.empty
        var lastResponseFlush = Date.distantPast
        var shouldForceFinalAnswerFollowUp = false
        var peakMemoryMB = await self.currentMemoryUsage()
        var toolResult: ToolExecutionResult?
        var toolTrace: ToolCallTrace?

        @MainActor
        func enforceMemorySafety() throws {
            let availableMB = self.deviceCapabilityService.availableMemoryMB
            if availableMB > 0 && availableMB < Constants.Generation.lowMemoryAbortThresholdMB {
                throw ChatGenerationAbort.lowMemory(availableMB)
            }
        }

        @MainActor
        func updatePeakMemoryUsage() async {
            peakMemoryMB = max(peakMemoryMB, await self.currentMemoryUsage())
        }

        @MainActor
        func refreshParsedResponse() {
            latestParsedResponse = ParsedAssistantContent(accumulatedResponse, isStreaming: true)
        }

        @MainActor
        func flushResponseToUI(force: Bool = false) {
            // Token-level fast reject: most tokens don't need to consult the wall clock.
            // Skipping Date() construction on ~3 out of 4 tokens removes a measurable
            // amount of @MainActor work during long generations on big models.
            if !force, !tokenCount.isMultiple(of: Constants.UI.streamingFlushTokenGate) {
                return
            }
            let isLongResponse = accumulatedResponse.count >= Constants.UI.streamingLongResponseCharacterThreshold
            let flushInterval: TimeInterval
            if thinkingEnabled && latestParsedResponse.response.isEmpty {
                flushInterval = isLongResponse
                    ? Constants.UI.streamingThinkingLongFlushInterval
                    : Constants.UI.streamingThinkingFlushInterval
            } else {
                flushInterval = isLongResponse
                    ? Constants.UI.streamingResponseLongFlushInterval
                    : Constants.UI.streamingResponseFlushInterval
            }
            let now = Date()
            guard force || now.timeIntervalSince(lastResponseFlush) >= flushInterval else { return }
            refreshParsedResponse()
            self.currentResponse = accumulatedResponse
            self.currentParsedResponse = latestParsedResponse
            lastResponseFlush = now
        }

        var completedAssistantMessage: ChatMessage?

        do {
            try Task.checkCancellation()

            let tools = await appState.toolCallingService.enabledTools(
                webSearchEnabled: isWebSearchEnabled,
                context: toolContext
            )
            if !tools.isEmpty {
                Self.debugToolLog("tool stage enabled: registeredTools=\(tools.map(\.name).joined(separator: ","))")

                // Run the synchronous preflight first. For high-confidence
                // turns (pasted URL, calendar/doc/OCR/live-data phrases) and
                // for clearly tool-irrelevant turns (greetings, math, casual
                // questions) this returns a final decision without paying for
                // a planner inference round-trip — the dominant source of
                // perceived "thinking" lag on simple prompts.
                let preflight = appState.toolCallingService.preflightDecision(
                    userMessage: text,
                    context: toolContext,
                    tools: tools,
                    history: history
                )

                let decision: ToolDecision
                switch preflight {
                case .skip(let resolved):
                    Self.debugToolLog("planner stage skipped via preflight decision=\(Self.describeDecision(resolved))")
                    decision = resolved

                case .deliberate:
                    toolActivityStatus = .planning
                    let plannedDecision = try await appState.toolCallingService.plan(
                        userMessage: text,
                        history: history,
                        tools: tools,
                        context: toolContext,
                        using: inferenceService
                    )
                    decision = appState.toolCallingService.resolvedDecision(
                        plannedDecision: plannedDecision,
                        userMessage: text,
                        context: toolContext,
                        tools: tools,
                        preferThinkingFallback: loadedModel?.supportsThinking == true
                    )
                }

                switch decision {
                case .none:
                    Self.debugToolLog("planner decision: none")
                    toolActivityStatus = nil

                case .call(let request):
                    let displayInput = self.toolDisplayInput(for: request, context: toolContext)
                    Self.debugToolLog(
                        "planner decision: call tool=\(request.toolName) input=\(Self.sanitizedToolLogSnippet(displayInput ?? "(none)"))"
                    )
                    toolActivityStatus = .running(toolName: request.toolName, displayInput: displayInput)
                    let executors = await appState.toolCallingService.executors()
                    let executionResult = try await appState.toolCallingService.execute(
                        call: request,
                        tools: executors,
                        context: toolContext
                    )
                    toolResult = executionResult
                    toolTrace = ToolCallTrace(
                        toolName: request.toolName,
                        displayInput: displayInput,
                        status: executionResult.status,
                        durationSeconds: executionResult.durationSeconds,
                        success: executionResult.success,
                        sourceCount: executionResult.sources.count
                    )
                    Self.debugToolLog(
                        "tool result: tool=\(request.toolName) status=\(executionResult.status.rawValue) " +
                        "sources=\(executionResult.sources.count) contextChars=\(executionResult.contextBlock.count) " +
                        "message=\(Self.sanitizedToolLogSnippet(executionResult.message ?? "nil"))"
                    )
                    if executionResult.status != .success {
                        toolNotice = self.toolFailureNotice(result: executionResult, context: toolContext)
                    }
                    currentToolTrace = toolTrace
                    toolActivityStatus = nil
                }
            } else {
                Self.debugToolLog("tool stage skipped: no eligible tools")
            }

            try Task.checkCancellation()

            let memoryRetrievalResult = await self.appState.retrieveMemoryContext(
                for: text,
                maxCharacters: self.memoryContextCharacterLimit(for: loadedModel)
            )
            try Task.checkCancellation()

            let memoryContext = self.promptMemoryContext(
                memoryRetrievalResult.contextBlock,
                for: loadedModel
            )
            let toolContextBlock: String
            if let toolResult = toolResult,
               toolResult.status == .noContent,
               let message = toolResult.message,
               !message.isEmpty {
                toolContextBlock = message
            } else {
                toolContextBlock = self.promptToolContext(
                    toolResult?.contextBlock ?? "",
                    for: loadedModel
                )
            }
            let effectiveUserPrompt = self.promptWithToolContext(
                userPrompt: text,
                toolContext: toolContextBlock
            )
            Self.debugToolLog(
                "generation context: tool=\(toolResult?.toolName ?? "none") toolSources=\(toolResult?.sources.count ?? 0) " +
                "toolContextChars=\(toolContextBlock.count)"
            )
            let effectiveSystemPrompt = self.mergedSystemPrompt(
                base: systemPrompt,
                memoryContext: memoryContext,
                toolContext: "",
                thinkingEnabled: thinkingEnabled,
                replyMode: replyMode
            )

            let stream = await self.inferenceService.generate(
                prompt: effectiveUserPrompt,
                images: userMessage.attachedImages,
                thinkingEnabled: loadedModel?.supportsThinking == true ? thinkingEnabled : nil,
                history: history,
                systemPrompt: effectiveSystemPrompt,
                maxTokens: generationBudget.streamMaxTokens,
                temperature: temperature,
                topP: topP,
                repetitionPenalty: repetitionPenalty
            )

            for try await token in stream {
                guard !Task.isCancelled else { break }
                accumulatedResponse += token
                tokenCount += 1
                flushResponseToUI()
                if tokenCount.isMultiple(of: Constants.Generation.lowMemoryCheckInterval) {
                    refreshParsedResponse()
                    await updatePeakMemoryUsage()
                    try enforceMemorySafety()
                    if self.shouldInterruptThinking(
                        in: latestParsedResponse,
                        thinkingEnabled: thinkingEnabled,
                        tokenCount: tokenCount,
                        hiddenThinkingMaxTokens: generationBudget.hiddenThinkingMaxTokens
                    ) {
                        shouldForceFinalAnswerFollowUp = true
                        break
                    }
                }
            }

            flushResponseToUI(force: true)

            if shouldForceFinalAnswerFollowUp || self.shouldRunFinalAnswerFollowUp(for: latestParsedResponse, thinkingEnabled: thinkingEnabled) {
                let followUpStream = await self.inferenceService.generate(
                    prompt: effectiveUserPrompt,
                    images: userMessage.attachedImages,
                    thinkingEnabled: false,
                    history: history,
                    systemPrompt: self.finalAnswerSystemPrompt(
                        base: systemPrompt,
                        memoryContext: memoryContext,
                        toolContext: "",
                        replyMode: replyMode
                    ),
                    maxTokens: generationBudget.finalAnswerMaxTokens,
                    temperature: temperature,
                    topP: topP,
                    repetitionPenalty: repetitionPenalty
                )

                var startedFollowUpOutput = false
                for try await token in followUpStream {
                    guard !Task.isCancelled else { break }
                    if !startedFollowUpOutput {
                        accumulatedResponse += "\n\nFinal Answer:\n"
                        startedFollowUpOutput = true
                    }
                    accumulatedResponse += token
                    tokenCount += 1
                    flushResponseToUI()
                    if tokenCount.isMultiple(of: Constants.Generation.lowMemoryCheckInterval) {
                        await updatePeakMemoryUsage()
                        try enforceMemorySafety()
                    }
                }
            }

            flushResponseToUI(force: true)
            await updatePeakMemoryUsage()

            let elapsed = Date().timeIntervalSince(startTime)
            let promptMessageCount = self.messages.count - (accumulatedResponse.isEmpty ? 1 : 2)
            let generationStats = GenerationStats(
                tokensPerSecond: Double(tokenCount) / max(elapsed, 0.001),
                totalTokens: tokenCount,
                promptTokens: promptMessageCount,
                generationTime: elapsed,
                peakMemoryMB: peakMemoryMB
            )

            if !accumulatedResponse.isEmpty {
                let assistantMessage = ChatMessage(
                        role: .assistant,
                        content: accumulatedResponse,
                        retrievedSources: combinedSources(toolResult?.sources ?? []),
                        toolTrace: toolTrace,
                        generationStats: generationStats
                    )
                Self.debugToolLog(
                    "send complete: responseChars=\(accumulatedResponse.count) " +
                    "toolTrace=\(toolTrace.map(Self.describeToolTrace(_:)) ?? "nil")"
                )
                self.messages.append(assistantMessage)
                if allowPostReplyTasks {
                    self.scheduleMemoryExtraction(
                        userMessage: userMessage,
                        assistantMessage: assistantMessage,
                        conversationId: self.activeConversationId,
                        isEnabled: !handledExplicitMemoryCommand
                    )
                }
                completedAssistantMessage = assistantMessage
                self.saveCurrentConversation()
                if allowPostReplyTasks {
                    self.scheduleConversationTitleGeneration(
                        userMessage: userMessage,
                        assistantMessage: assistantMessage
                    )
                }
            } else {
                Self.debugToolLog("send complete: empty assistant response")
                self.saveCurrentConversation()
            }
            Haptics.impactMedium()
        } catch is CancellationError {
            Self.debugToolLog("send cancelled")
            toolActivityStatus = nil
            flushResponseToUI(force: true)
            if !shouldDiscardCancelledGeneration, !accumulatedResponse.isEmpty {
                await updatePeakMemoryUsage()
                let elapsed = Date().timeIntervalSince(startTime)
                let partialMessage = ChatMessage(
                        role: .assistant,
                        content: accumulatedResponse,
                        retrievedSources: combinedSources(toolResult?.sources ?? []),
                        toolTrace: toolTrace,
                        generationStats: GenerationStats(
                            tokensPerSecond: Double(tokenCount) / max(elapsed, 0.001),
                            totalTokens: tokenCount,
                            promptTokens: self.messages.count - 1,
                            generationTime: elapsed,
                            peakMemoryMB: peakMemoryMB
                        )
                    )
                self.messages.append(partialMessage)
                completedAssistantMessage = partialMessage
            }
            self.saveCurrentConversation()
        } catch {
            Self.debugToolLog("send failed: \(String(describing: error))")
            toolActivityStatus = nil
            flushResponseToUI(force: true)
            if !accumulatedResponse.isEmpty {
                await updatePeakMemoryUsage()
                let elapsed = Date().timeIntervalSince(startTime)
                let partialMessage = ChatMessage(
                        role: .assistant,
                        content: accumulatedResponse,
                        retrievedSources: combinedSources(toolResult?.sources ?? []),
                        toolTrace: toolTrace,
                        generationStats: GenerationStats(
                            tokensPerSecond: Double(tokenCount) / max(elapsed, 0.001),
                            totalTokens: tokenCount,
                            promptTokens: self.messages.count - 1,
                            generationTime: elapsed,
                            peakMemoryMB: peakMemoryMB
                        )
                    )
                self.messages.append(partialMessage)
                completedAssistantMessage = partialMessage
            }
            self.errorMessage = error.localizedDescription
            self.lastFailedUserMessageId = userMessage.id
            self.saveCurrentConversation()
            Haptics.notificationError()
        }

        self.currentResponse = ""
        self.currentParsedResponse = .empty
        self.toolActivityStatus = nil
        self.currentToolTrace = nil
        self.isGenerating = false
        self.generationTask = nil
        self.shouldDiscardCancelledGeneration = false
        return completedAssistantMessage
    }

    @MainActor
    func retryLastUserMessage() {
        guard !isGenerating else { return }
        guard let failedId = lastFailedUserMessageId,
              let userIndex = messages.lastIndex(where: { $0.id == failedId && $0.role == .user })
        else {
            lastFailedUserMessageId = nil
            return
        }

        let failedMessage = messages[userIndex]
        let restoredText = failedMessage.content
        let restoredImages = failedMessage.attachedImages ?? []
        let restoredDocuments = failedMessage.attachedDocuments ?? []

        if userIndex < messages.count - 1 {
            messages.removeSubrange((userIndex + 1)..<messages.count)
        }
        messages.remove(at: userIndex)

        pendingImages = restoredImages
        pendingDocuments = restoredDocuments

        errorMessage = nil
        toolNotice = nil
        lastFailedUserMessageId = nil
        saveCurrentConversation()
        sendMessage(restoredText)
    }

    @MainActor
    func stopGeneration(discardPartialResponse: Bool = false) {
        if discardPartialResponse {
            shouldDiscardCancelledGeneration = true
        }
        generationTask?.cancel()
        generationTask = nil
        toolActivityStatus = nil
    }

    @MainActor
    func loadModel(_ model: ModelInfo) async {
        isModelLoading = true
        loadingModel = model
        errorMessage = nil

        do {
            guard await downloadService.isModelDownloaded(model) else {
                appState.selectModel(nil)
                appState.setLoadedModel(id: nil)
                throw InferenceError.modelLoadFailed(
                    String(format: String.appLocalized("error.chat.model_files_missing"), model.displayName)
                )
            }
            let localURL = await downloadService.localURL(for: model)
            try await inferenceService.load(
                modelId: model.id,
                localDirectory: localURL
            )
            var updatedModel = model
            updatedModel.isDownloaded = true
            updatedModel.localURL = localURL
            appState.selectModel(updatedModel)
            appState.setLoadedModel(id: model.id)
            updateThinkingAvailability(for: updatedModel)
            saveCurrentConversation()
            Haptics.notificationSuccess()
        } catch {
            errorMessage = error.localizedDescription
            appState.selectModel(nil)
            appState.setLoadedModel(id: nil)
            updateThinkingAvailability(for: nil)
            Haptics.notificationError()
        }

        isModelLoading = false
        loadingModel = nil
    }

    @MainActor
    func unloadModel() async {
        await inferenceService.unload()
        appState.selectModel(nil)
        appState.setLoadedModel(id: nil)
        updateThinkingAvailability(for: nil)
    }

    @MainActor
    func suspendLoadedModelForVoicePlayback() async -> ModelInfo? {
        guard let selectedModel = appState.selectedModel else { return nil }
        guard appState.loadedModelId == selectedModel.id else { return selectedModel }

        await inferenceService.unload()
        appState.setLoadedModel(id: nil)
        updateThinkingAvailability(for: selectedModel)
        return selectedModel
    }

    @MainActor
    func resumeModelAfterVoicePlayback(_ model: ModelInfo?) async {
        guard let model else { return }
        guard appState.loadedModelId != model.id else { return }
        await loadModel(model)
    }

    @discardableResult
    @MainActor
    func startNewConversation() -> UUID? {
        let id = appState.createNewConversation()
        if let conversation = appState.conversation(id: id) {
            loadConversation(conversation)
        } else {
            activeConversationId = id
            messages.removeAll()
            pendingDocuments.removeAll()
            attachedDocuments.removeAll()
            currentResponse = ""
            currentParsedResponse = .empty
            errorMessage = nil
            memoryNotice = nil
            suppressedMemoryNoticeKey = nil
            isWebSearchEnabled = false
            toolNotice = nil
            toolActivityStatus = nil
        }
        return id
    }

    @MainActor
    func toggleThinking() {
        guard canUseThinking else { return }
        isThinkingEnabled.toggle()
        Haptics.selectionChanged()
    }

    @MainActor
    func dismissMemoryNotice() {
        suppressedMemoryNoticeKey = memoryNotice?.suppressionKey
        memoryNotice = nil
    }

    @MainActor
    func importDocument(from url: URL) async {
        if activeConversationId == nil {
            let id = appState.createNewConversation()
            activeConversationId = id
        }

        guard let conversationId = activeConversationId else { return }

        do {
            let reference = try await appState.documentLibraryService.importDocument(
                from: url,
                conversationId: conversationId
            )
            attachedDocuments.append(reference)
            pendingDocuments.append(reference)
            saveCurrentConversation()
            Haptics.notificationSuccess()
        } catch {
            errorMessage = error.localizedDescription
            Haptics.notificationError()
        }
    }

    @MainActor
    func appendPendingImage(_ data: Data) {
        pendingImages.append(ChatAttachmentImage(data: data))
    }

    @MainActor
    func removePendingImage(id: UUID) {
        pendingImages.removeAll { $0.id == id }
    }

    @MainActor
    func removeDocument(_ reference: ConversationDocumentReference) {
        pendingDocuments.removeAll { $0.id == reference.id }
        attachedDocuments.removeAll { $0.id == reference.id }
        Task {
            await appState.documentLibraryService.removeDocument(id: reference.id)
        }
        saveCurrentConversation()
        Haptics.impactLight()
    }

    @MainActor
    private func saveCurrentConversation() {
        guard let conversationId = activeConversationId else { return }

        var conversation: Conversation
        if let existing = appState.conversation(id: conversationId) {
            conversation = existing
            conversation.messages = messages
            conversation.modelId = appState.loadedModelId
            conversation.webSearchEnabled = isWebSearchEnabled
            conversation.documents = attachedDocuments
            conversation.updatedAt = Date()
        } else {
            conversation = Conversation(
                id: conversationId,
                messages: messages,
                modelId: appState.loadedModelId,
                webSearchEnabled: isWebSearchEnabled,
                documents: attachedDocuments
            )
        }

        appState.updateConversation(conversation)
    }

    @MainActor
    private func scheduleConversationTitleGeneration(
        userMessage: ChatMessage,
        assistantMessage: ChatMessage
    ) {
        guard let conversationId = activeConversationId else { return }
        guard let conversation = appState.conversation(id: conversationId) else { return }
        guard conversation.title == "New Conversation" else { return }

        titleGenerationTasks[conversationId]?.cancel()
        titleGenerationTasks[conversationId] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.titleGenerationTasks[conversationId] = nil }
            guard let generatedTitle = try? await self.generateConversationTitle(
                userMessage: userMessage,
                assistantMessage: assistantMessage
            ) else {
                return
            }
            guard !generatedTitle.isEmpty else { return }
            guard var refreshedConversation = self.appState.conversationService.load(id: conversationId),
                  refreshedConversation.title == "New Conversation" else {
                return
            }
            refreshedConversation.title = generatedTitle
            self.appState.updateConversation(refreshedConversation)
        }
    }

    @MainActor
    private func generateConversationTitle(
        userMessage: ChatMessage,
        assistantMessage: ChatMessage
    ) async throws -> String? {
        guard #available(iOS 26.0, *) else { return nil }
        let model = SystemLanguageModel(useCase: .general)
        guard model.isAvailable else { return nil }

        let session = LanguageModelSession(
            model: model,
            instructions: """
            You generate short conversation titles for a private on-device chat app.
            Return only the title text.
            Keep it plain, specific, and between 2 and 4 words when possible.
            Never use quotes, markdown, punctuation at the end, or line breaks.
            """
        )

        let response = try await session.respond(
            to: """
            First user message:
            \(userMessage.content)

            First assistant reply:
            \(assistantMessage.content)
            """,
            options: GenerationOptions(
                sampling: .greedy,
                temperature: 0.0,
                maximumResponseTokens: 12
            )
        )

        let sanitized = sanitizeConversationTitle(response.content)
        return sanitized.isEmpty ? nil : sanitized
    }

    private func sanitizeConversationTitle(_ rawTitle: String) -> String {
        let flattened = rawTitle
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .replacingOccurrences(of: #"[\"*_`#]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
        let collapsedWhitespace = flattened.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        if collapsedWhitespace.count <= 32 {
            return collapsedWhitespace
        }
        let endIndex = collapsedWhitespace.index(collapsedWhitespace.startIndex, offsetBy: 32)
        return String(collapsedWhitespace[..<endIndex])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }

    private func combinedSources(_ sources: [MessageSource]) -> [MessageSource]? {
        return sources.isEmpty ? nil : sources
    }

    private func toolDisplayInput(for request: ToolCallRequest, context: ToolInputContext) -> String? {
        switch request.toolName {
        case "web_search":
            return request.arguments["query"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        case "read_url":
            return request.arguments["url"]?.trimmingCharacters(in: .whitespacesAndNewlines)
                ?? context.singleDetectedPublicURL?.absoluteString
        case "ocr_image_text":
            return nil
        case "document_synthesize":
            return request.arguments["query"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        case "calendar_brief":
            return request.arguments["range"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        case "calendar_create":
            return request.arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        case "reminders_brief":
            return request.arguments["range"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        case "reminders_create":
            return request.arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        case "timer_create":
            if let title = request.arguments["title"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                return title
            }
            if let duration = request.arguments["duration"]?.trimmingCharacters(in: .whitespacesAndNewlines),
               let totalSeconds = Int(duration) {
                let hours = totalSeconds / 3600
                let minutes = (totalSeconds % 3600) / 60
                let secs = totalSeconds % 60
                if hours > 0 { return "\(hours)h \(minutes)m" }
                if minutes > 0 { return "\(minutes)m \(secs)s" }
                return "\(secs)s"
            }
            return request.arguments["duration"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        case "contacts_lookup":
            return request.arguments["query"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        case "current_datetime":
            return nil
        default:
            return nil
        }
    }

    private func toolFailureNotice(result: ToolExecutionResult, context: ToolInputContext) -> String {
        switch result.status {
        case .networkUnavailable, .timedOut, .permissionDenied, .unavailable:
            switch result.toolName {
            case "read_url":
                return String.appLocalized("tool.notice.read_url_failed")
            case "ocr_image_text":
                return String.appLocalized("tool.notice.ocr_failed")
            case "web_search":
                return String.appLocalized("tool.notice.search_failed")
            case "document_synthesize":
                return String.appLocalized("tool.notice.document_failed")
            case "calendar_brief", "calendar_create":
                return String.appLocalized("tool.notice.calendar_failed")
            case "reminders_brief", "reminders_create":
                return String.appLocalized("tool.notice.reminders_failed")
            case "timer_create":
                return String.appLocalized("tool.notice.timer_failed")
            case "contacts_lookup":
                return String.appLocalized("tool.notice.contacts_failed")
            case "current_datetime":
                return String.appLocalized("tool.notice.datetime_failed")
            default:
                return String.appLocalized("tool.notice.search_failed")
            }

        case .noContent:
            switch result.toolName {
            case "read_url":
                return String.appLocalized("tool.notice.read_url_no_content")
            case "ocr_image_text":
                return context.attachedImages.isEmpty
                    ? String.appLocalized("tool.notice.ocr_failed")
                    : String.appLocalized("tool.notice.ocr_no_text")
            case "web_search":
                return String.appLocalized("tool.notice.search_no_content")
            case "document_synthesize":
                return String.appLocalized("tool.notice.document_no_content")
            case "calendar_brief":
                return String.appLocalized("tool.notice.calendar_no_content")
            case "calendar_create":
                return String.appLocalized("tool.notice.calendar_failed")
            case "reminders_brief":
                return String.appLocalized("tool.notice.reminders_no_content")
            case "reminders_create":
                return String.appLocalized("tool.notice.reminders_failed")
            case "timer_create":
                return String.appLocalized("tool.notice.timer_failed")
            case "contacts_lookup":
                return String.appLocalized("tool.notice.contacts_no_content")
            case "current_datetime":
                return String.appLocalized("tool.notice.datetime_failed")
            default:
                return String.appLocalized("tool.notice.search_failed")
            }

        case .invalidArguments, .executionFailed:
            switch result.toolName {
            case "read_url":
                return String.appLocalized("tool.notice.read_url_failed")
            case "ocr_image_text":
                return String.appLocalized("tool.notice.ocr_failed")
            case "web_search":
                return String.appLocalized("tool.notice.search_failed")
            case "document_synthesize":
                return String.appLocalized("tool.notice.document_failed")
            case "calendar_brief", "calendar_create":
                return String.appLocalized("tool.notice.calendar_failed")
            case "reminders_brief", "reminders_create":
                return String.appLocalized("tool.notice.reminders_failed")
            case "timer_create":
                return String.appLocalized("tool.notice.timer_failed")
            case "contacts_lookup":
                return String.appLocalized("tool.notice.contacts_failed")
            case "current_datetime":
                return String.appLocalized("tool.notice.datetime_failed")
            default:
                return String.appLocalized("tool.notice.search_failed")
            }

        case .success:
            return String.appLocalized("tool.notice.search_failed")
        }
    }

    private static func debugToolLog(_ message: String) {
#if DEBUG
        print("[ChatTooling] \(message)")
#endif
    }

    private static func sanitizedToolLogSnippet(_ text: String, limit: Int = 180) -> String {
        let compact = text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if compact.count <= limit {
            return compact
        }
        return String(compact.prefix(limit)) + "..."
    }

    private static func describeDecision(_ decision: ToolDecision) -> String {
        switch decision {
        case .none:
            return "none"
        case .call(let request):
            return "call(\(request.toolName))"
        }
    }

    private static func describeToolTrace(_ trace: ToolCallTrace) -> String {
        "tool=\(trace.toolName), input=\(trace.displayInput ?? "nil"), status=\(trace.status?.rawValue ?? "nil"), success=\(trace.success), " +
        "sources=\(trace.sourceCount), duration=\(trace.durationSeconds.map { String(format: "%.2f", $0) } ?? "nil")s"
    }

    /// Explicit memory commands use "remember …" / "forget …". Reminder creation is routed separately via
    /// ToolCallingService using phrases like "remind me to …" (requires `to`), which avoids colliding with
    /// "remind me of …" style memory prompts.
    @MainActor
    private func handleExplicitMemoryCommands(in text: String, userMessage: ChatMessage) -> Bool {
        var handledCommand = false

        if let memoryContent = explicitRememberContent(from: text) {
            handledCommand = true
            let savedMemory = appState.saveMemory(
                content: memoryContent,
                status: .active,
                captureType: .explicit,
                sourceConversationId: activeConversationId,
                sourceMessageId: userMessage.id,
                sourceQuote: text
            )
            if savedMemory != nil {
                showMemoryNotice(
                    kind: .saved,
                    message: String.appLocalized("memory.notice.saved"),
                    eventKey: "saved:\(userMessage.id.uuidString)"
                )
                Haptics.notificationSuccess()
            }
        }

        if let forgetContent = explicitForgetContent(from: text) {
            handledCommand = true
            let count = appState.forgetMemory(matching: forgetContent)
            if count > 0 {
                showMemoryNotice(
                    kind: .forgotten,
                    message: String(format: String.appLocalized("memory.notice.forgotten"), count),
                    eventKey: "forgotten:\(userMessage.id.uuidString)"
                )
                Haptics.impactLight()
            }
        }

        if !handledCommand,
           let memoryContent = highConfidenceSelfFactMemoryContent(from: text) {
            handledCommand = true
            let savedMemory = appState.saveMemory(
                content: memoryContent,
                status: .active,
                captureType: .inferred,
                sourceConversationId: activeConversationId,
                sourceMessageId: userMessage.id,
                sourceQuote: text
            )
            if savedMemory != nil {
                showMemoryNotice(
                    kind: .saved,
                    message: String.appLocalized("memory.notice.saved"),
                    eventKey: "saved:\(userMessage.id.uuidString)"
                )
                Haptics.notificationSuccess()
            }
        }

        return handledCommand
    }

    @MainActor
    private func scheduleMemoryExtraction(
        userMessage: ChatMessage,
        assistantMessage: ChatMessage,
        conversationId: UUID?,
        isEnabled: Bool
    ) {
        guard isEnabled else { return }

        let messageId = userMessage.id
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.memoryExtractionTasks[messageId] = nil
            }
            do {
                let candidates = try await self.extractMemoryCandidates(
                    userMessage: userMessage,
                    assistantMessage: assistantMessage
                )
                guard !Task.isCancelled else { return }
                guard !candidates.isEmpty else { return }

                let pendingBefore = self.appState.memories.filter { $0.status == .pending }.count
                let activeBefore = self.appState.memories.filter { $0.status == .active }.count
                for candidate in candidates {
                    let status: UserMemoryStatus = self.shouldAutoSaveExtractedMemory(candidate) ? .active : .pending
                    _ = self.appState.saveMemory(
                        content: candidate.canonicalContent,
                        status: status,
                        captureType: .inferred,
                        sourceConversationId: conversationId,
                        sourceMessageId: userMessage.id,
                        sourceLanguageCode: candidate.sourceLanguageCode,
                        sourceQuote: candidate.sourceQuote,
                        factRelation: candidate.relation,
                        factValue: candidate.value
                    )
                }

                let activeSavedCount = max(0, self.appState.memories.filter { $0.status == .active }.count - activeBefore)
                let pendingSavedCount = max(0, self.appState.memories.filter { $0.status == .pending }.count - pendingBefore)
                if activeSavedCount > 0 {
                    self.showMemoryNotice(
                        kind: .saved,
                        message: String.appLocalized("memory.notice.saved"),
                        eventKey: "saved:\(messageId.uuidString)"
                    )
                    Haptics.notificationSuccess()
                } else if pendingSavedCount > 0 {
                    self.showMemoryNotice(
                        kind: .pending,
                        message: String(format: String.appLocalized("memory.notice.pending"), pendingSavedCount),
                        eventKey: "pending:\(messageId.uuidString)"
                    )
                }
            } catch is CancellationError {
            } catch {
            }
        }
        memoryExtractionTasks[messageId] = task
    }

    private func shouldAutoSaveExtractedMemory(_ candidate: MemoryExtractionCandidate) -> Bool {
        let relation = candidate.relation?.lowercased()
        return relation == "name"
            && candidate.confidence >= 0.90
            && candidate.sourceQuote?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            && candidate.value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    @MainActor
    private func showMemoryNotice(kind: ChatMemoryNoticeKind, message: String, eventKey: String) {
        let notice = ChatMemoryNotice(kind: kind, message: message, eventKey: eventKey)
        guard suppressedMemoryNoticeKey != notice.suppressionKey else { return }
        memoryNotice = notice
    }

    private func extractMemoryCandidates(
        userMessage: ChatMessage,
        assistantMessage _: ChatMessage
    ) async throws -> [MemoryExtractionCandidate] {
        if #available(iOS 26.0, *) {
            if let candidates = try await extractMemoryCandidatesWithAppleFoundationModel(
                userMessage: userMessage
            ) {
                return candidates
            }
        }

        guard appState.loadedModelId != nil else { return [] }
        return try await extractMemoryCandidatesWithLoadedMLXModel(
            userMessage: userMessage
        )
    }

    @available(iOS 26.0, *)
    private func extractMemoryCandidatesWithAppleFoundationModel(
        userMessage: ChatMessage
    ) async throws -> [MemoryExtractionCandidate]? {
        let model = SystemLanguageModel(useCase: .general)
        guard model.isAvailable else { return nil }

        let session = LanguageModelSession(
            model: model,
            instructions: memoryExtractionSystemPrompt()
        )
        let response = try await session.respond(
            to: memoryExtractionPrompt(userMessage: userMessage),
            options: GenerationOptions(
                sampling: .greedy,
                temperature: 0.0,
                maximumResponseTokens: Constants.Memory.extractionMaxTokens
            )
        )
        return appState.memoryService.extractionCandidates(
            from: response.content,
            sourceText: userMessage.content
        )
    }

    private func extractMemoryCandidatesWithLoadedMLXModel(
        userMessage: ChatMessage
    ) async throws -> [MemoryExtractionCandidate] {
        let prompt = memoryExtractionPrompt(userMessage: userMessage)
        let stream = await inferenceService.generate(
            prompt: prompt,
            history: [],
            systemPrompt: memoryExtractionSystemPrompt(),
            maxTokens: Constants.Memory.extractionMaxTokens,
            temperature: 0.1,
            topP: 0.8,
            repetitionPenalty: 1.0
        )

        var rawOutput = ""
        for try await token in stream {
            guard !Task.isCancelled else { throw CancellationError() }
            rawOutput += token
        }
        return appState.memoryService.extractionCandidates(
            from: rawOutput,
            sourceText: userMessage.content
        )
    }

    private func currentMemoryUsage() async -> UInt64 {
        UInt64(deviceCapabilityService.currentMemoryUsageMB)
    }

    private func resolvedCurrentModel() -> ModelInfo? {
        if let loadedModelId = appState.loadedModelId,
           let loadedModel = appState.modelInfo(id: loadedModelId) {
            return loadedModel
        }

        if let selectedModel = appState.selectedModel {
            return selectedModel
        }

        return nil
    }

    private func updateThinkingAvailability(for model: ModelInfo?) {
        let modelId = model?.id
        if capabilityModelId != modelId {
            capabilityModelId = modelId
            isThinkingEnabled = model?.prefersThinkingEnabled ?? false
        }

        if model?.supportsThinking != true {
            isThinkingEnabled = false
        }
    }

    private func generationBudget(for model: ModelInfo?, thinkingEnabled: Bool) -> GenerationBudget {
        guard thinkingEnabled else {
            return GenerationBudget(
                streamMaxTokens: standardGenerationTokenLimit(for: model),
                hiddenThinkingMaxTokens: nil,
                finalAnswerMaxTokens: 0
            )
        }

        var budget = baseThinkingGenerationBudget(for: model)
        if isMemoryConstrainedLargeModel(model) {
            budget = cappedThinkingGenerationBudget(
                budget,
                answerMaxTokens: standardGenerationTokenLimit(for: model)
            )
        }
        return budget
    }

    private func standardGenerationTokenLimit(for model: ModelInfo?) -> Int {
        guard isMemoryConstrainedLargeModel(model) else { return Constants.Generation.standardMaxTokens }
        if model?.supportsVision == true {
            return memoryConstrainedVisionTokenLimit()
        }
        return Constants.Generation.memoryConstrainedStandardMaxTokens
    }

    private func baseThinkingGenerationBudget(for model: ModelInfo?) -> GenerationBudget {
        let estimatedSizeGB = model?.estimatedSizeGB ?? 0
        let answerMaxTokens = standardGenerationTokenLimit(for: model)
        switch estimatedSizeGB {
        case let size where size > 0 && size <= Constants.Generation.compactThinkingMaxSizeGB:
            return GenerationBudget(
                streamMaxTokens: answerMaxTokens + Constants.Generation.compactModelHiddenThinkingMaxTokens,
                hiddenThinkingMaxTokens: Constants.Generation.compactModelHiddenThinkingMaxTokens,
                finalAnswerMaxTokens: answerMaxTokens
            )
        case let size where size <= Constants.Generation.mediumThinkingMaxSizeGB:
            return GenerationBudget(
                streamMaxTokens: answerMaxTokens + Constants.Generation.mediumModelHiddenThinkingMaxTokens,
                hiddenThinkingMaxTokens: Constants.Generation.mediumModelHiddenThinkingMaxTokens,
                finalAnswerMaxTokens: answerMaxTokens
            )
        case let size where size <= Constants.Generation.largeThinkingMaxSizeGB:
            return GenerationBudget(
                streamMaxTokens: answerMaxTokens + Constants.Generation.largeModelHiddenThinkingMaxTokens,
                hiddenThinkingMaxTokens: Constants.Generation.largeModelHiddenThinkingMaxTokens,
                finalAnswerMaxTokens: answerMaxTokens
            )
        default:
            return GenerationBudget(
                streamMaxTokens: answerMaxTokens + Constants.Generation.extraLargeModelHiddenThinkingMaxTokens,
                hiddenThinkingMaxTokens: Constants.Generation.extraLargeModelHiddenThinkingMaxTokens,
                finalAnswerMaxTokens: answerMaxTokens
            )
        }
    }

    private func cappedThinkingGenerationBudget(_ budget: GenerationBudget, answerMaxTokens: Int) -> GenerationBudget {
        let cappedFinalAnswerTokens = max(
            Constants.Generation.minimumFinalAnswerMaxTokens,
            answerMaxTokens
        )
        let cappedHiddenThinkingTokens = min(
            budget.hiddenThinkingMaxTokens ?? cappedFinalAnswerTokens,
            max(Constants.Generation.minimumHiddenThinkingMaxTokens, cappedFinalAnswerTokens / 2)
        )
        let cappedStreamTokens = cappedFinalAnswerTokens + cappedHiddenThinkingTokens

        return GenerationBudget(
            streamMaxTokens: cappedStreamTokens,
            hiddenThinkingMaxTokens: cappedHiddenThinkingTokens,
            finalAnswerMaxTokens: cappedFinalAnswerTokens
        )
    }

    private func memoryConstrainedVisionTokenLimit() -> Int {
        let availableMB = deviceCapabilityService.availableMemoryMB
        if availableMB >= Constants.Generation.highMemoryHeadroomMB {
            return Constants.Generation.memoryConstrainedVisionMaxTokens
        }
        if availableMB >= Constants.Generation.mediumMemoryHeadroomMB {
            return Constants.Generation.mediumHeadroomVisionMaxTokens
        }
        return Constants.Generation.lowHeadroomVisionMaxTokens
    }

    private func promptHistory(from history: [ChatMessage], for model: ModelInfo?) -> [ChatMessage] {
        guard isMemoryConstrainedLargeModel(model) else { return history }
        return history
            .suffix(Constants.Generation.memoryConstrainedHistoryMessageLimit)
            .map { message in
                var promptMessage = message
                promptMessage.attachedImages = nil
                return promptMessage
            }
    }

    private func promptToolContext(_ context: String, for model: ModelInfo?) -> String {
        guard isMemoryConstrainedLargeModel(model) else { return context }
        let characterLimit = Constants.Generation.memoryConstrainedDocumentContextCharacters
        guard context.count > characterLimit else { return context }
        return String(context.prefix(characterLimit))
    }

    private func promptWithToolContext(userPrompt: String, toolContext: String) -> String {
        let trimmedToolContext = toolContext.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToolContext.isEmpty else { return userPrompt }

        return """
        Use the tool result below to answer the user's request. The tool result is available content; do not ask the user to provide it again. If the tool result is insufficient, say what is missing.

        Tool result:
        \(trimmedToolContext)

        User request:
        \(userPrompt)
        """
    }

    private func promptMemoryContext(_ context: String, for model: ModelInfo?) -> String {
        let characterLimit = memoryContextCharacterLimit(for: model)
        guard context.count > characterLimit else { return context }
        return String(context.prefix(characterLimit))
    }

    private func memoryContextCharacterLimit(for model: ModelInfo?) -> Int {
        isMemoryConstrainedLargeModel(model)
            ? Constants.Memory.memoryConstrainedContextCharacters
            : Constants.Memory.maxContextCharacters
    }

    private func isMemoryConstrainedLargeModel(_ model: ModelInfo?) -> Bool {
        let isLargeModel = (model?.minDeviceRAM ?? 0) >= 12 || (model?.estimatedSizeGB ?? 0) >= 2.5
        return deviceCapabilityService.tier <= .tier12GB && isLargeModel
    }

    private func safeRepetitionPenalty(_ requested: Float) -> Float {
        max(1.0, min(requested, 2.0))
    }

    private func mergedSystemPrompt(base: String, memoryContext: String, toolContext: String, thinkingEnabled: Bool, replyMode: ReplyMode) -> String {
        var parts: [String] = []
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBase.isEmpty {
            parts.append(trimmedBase)
        }
        let trimmedMemoryContext = memoryContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMemoryContext.isEmpty {
            parts.append(trimmedMemoryContext)
        }
        let trimmedToolContext = toolContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToolContext.isEmpty {
            parts.append(trimmedToolContext)
        }
        if thinkingEnabled {
            parts.append(Constants.Generation.conciseThinkingInstruction)
        }
        if replyMode == .liveVoice {
            parts.append(Constants.Generation.liveVoiceConciseInstruction)
        }
        return parts.joined(separator: "\n\n")
    }

    private func finalAnswerSystemPrompt(base: String, memoryContext: String, toolContext: String, replyMode: ReplyMode) -> String {
        var parts: [String] = []
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBase.isEmpty {
            parts.append(trimmedBase)
        }
        let trimmedMemoryContext = memoryContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMemoryContext.isEmpty {
            parts.append(trimmedMemoryContext)
        }
        let trimmedToolContext = toolContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedToolContext.isEmpty {
            parts.append(trimmedToolContext)
        }
        if replyMode == .liveVoice {
            parts.append(Constants.Generation.liveVoiceConciseInstruction)
        }
        parts.append(Constants.Generation.finalAnswerOnlyInstruction)
        return parts.joined(separator: "\n\n")
    }

    private func explicitRememberContent(from text: String) -> String? {
        captureExplicitCommand(
            in: text,
            patterns: [
                #"^\s*(?:please\s+)?remember(?:\s+that)?\s+(.+)$"#,
                #"^\s*(?:please\s+)?keep\s+in\s+mind(?:\s+that)?\s+(.+)$"#
            ]
        )
    }

    private func explicitForgetContent(from text: String) -> String? {
        captureExplicitCommand(
            in: text,
            patterns: [
                #"^\s*(?:please\s+)?forget(?:\s+that|\s+about)?\s+(.+)$"#,
                #"^\s*(?:please\s+)?don't\s+remember(?:\s+that)?\s+(.+)$"#
            ]
        )
    }

    private func highConfidenceSelfFactMemoryContent(from text: String) -> String? {
        if let name = captureExplicitCommand(
            in: text,
            minimumCharacters: 2,
            patterns: [
                #"^\s*(?:(?:hi|hello|hey|hola|buenas)[,!\.\s]+)?(?:my\s+name\s+is|my\s+name(?:'|’)?s|i(?:'|’)?m\s+called|i\s+am\s+called)\s+(.+)$"#,
                #"^\s*(?:(?:hi|hello|hey|hola|buenas)[,!\.\s]+)?(?:me\s+llamo|mi\s+nombre\s+es|me\s+chamo|je\s+m(?:'|’)?appelle|ich\s+hei(?:ss|ß)e|mi\s+chiamo)\s+(.+)$"#
            ]
        ) {
            let phrase = normalizedMemoryPhrase(stableSelfFactPhrase(from: name))
            guard !phrase.isEmpty else { return nil }
            return "The user's name is \(phrase)."
        }

        if let fandom = highConfidenceFandomTarget(from: text) {
            let phrase = "\(fandom) fan"
            return "The user is \(article(for: phrase)) \(phrase)."
        }

        if let occupation = captureExplicitCommand(
            in: text,
            minimumCharacters: 3,
            patterns: [
                #"^\s*(?:(?:hi|hello|hey|hola)[,!\.\s]+)?i(?:'|’)?m\s+an?\s+([a-z][a-z0-9\s\-\/&,]+)$"#,
                #"^\s*(?:(?:hi|hello|hey|hola)[,!\.\s]+)?i\s+am\s+an?\s+([a-z][a-z0-9\s\-\/&,]+)$"#,
                #"^\s*i\s+work\s+as\s+(?:an?\s+)?([a-z][a-z0-9\s\-\/&,]+)$"#,
                #"^\s*my\s+(?:job|profession|occupation|role)\s+is\s+(?:an?\s+)?([a-z][a-z0-9\s\-\/&,]+)$"#
            ]
        ) {
            let phrase = normalizedMemoryPhrase(stableSelfFactPhrase(from: occupation))
            guard !phrase.isEmpty, !isLowConfidenceSelfDescription(phrase) else { return nil }
            return "The user is \(article(for: phrase)) \(phrase)."
        }

        return nil
    }

    private func highConfidenceFandomTarget(from text: String) -> String? {
        if let explicitTarget = captureExplicitCommand(
            in: text,
            minimumCharacters: 2,
            patterns: [
                #".*\bi(?:'|’)?m\s+(?:an?\s+)?(?:(?:big|huge|massive|lifelong)\s+)?fan\s+of\s+([A-Za-z0-9][A-Za-z0-9\s&'\-\.]+)$"#,
                #".*\bi\s+am\s+(?:an?\s+)?(?:(?:big|huge|massive|lifelong)\s+)?fan\s+of\s+([A-Za-z0-9][A-Za-z0-9\s&'\-\.]+)$"#
            ]
        ) {
            let target = normalizedMemoryPhrase(stableSelfFactPhrase(from: explicitTarget))
            return target.isEmpty ? nil : target
        }

        guard let fanRange = rangeOfFanDeclaration(in: text) else { return nil }
        return fandomTargetFromContext(String(text[..<fanRange.lowerBound]))
    }

    private func rangeOfFanDeclaration(in text: String) -> Range<String.Index>? {
        let pattern = #"\bi(?:'|’)?m\s+(?:an?\s+)?(?:(?:big|huge|massive|lifelong)\s+)?fan\b|\bi\s+am\s+(?:an?\s+)?(?:(?:big|huge|massive|lifelong)\s+)?fan\b"#
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: range),
              let declarationRange = Range(match.range, in: text) else {
            return nil
        }
        return declarationRange
    }

    private func fandomTargetFromContext(_ context: String) -> String? {
        let pattern = #"\b(?:[A-Z][A-Za-z0-9]+|[A-Z]{2,})(?:\s+(?:[A-Z][A-Za-z0-9]+|[A-Z]{2,}))*\b"#
        let range = NSRange(context.startIndex..<context.endIndex, in: context)
        guard let regex = try? NSRegularExpression(pattern: pattern),
              !context.isEmpty else {
            return nil
        }

        let ignoredCandidates = Set([
            "what",
            "who",
            "when",
            "where",
            "why",
            "how",
            "which",
            "tell",
            "can",
            "could",
            "would",
            "please"
        ])

        let matches = regex.matches(in: context, range: range)
        for match in matches.reversed() {
            guard let matchRange = Range(match.range, in: context) else { continue }
            let candidate = normalizedMemoryPhrase(String(context[matchRange]))
            guard !candidate.isEmpty, !ignoredCandidates.contains(candidate.lowercased()) else { continue }
            return candidate
        }

        return nil
    }

    private func captureExplicitCommand(
        in text: String,
        minimumCharacters: Int = Constants.Memory.minimumCandidateCharacters,
        patterns: [String]
    ) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let capturedRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            let captured = text[capturedRange]
                .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!\"'")))
            if captured.count >= minimumCharacters {
                return String(captured)
            }
        }
        return nil
    }

    private func normalizedMemoryPhrase(_ phrase: String) -> String {
        phrase
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?,;:\"'")))
    }

    private func stableSelfFactPhrase(from phrase: String) -> String {
        let markerTrimmedPhrase = phraseByDroppingRequestTailMarkers(from: phrase)
        let requestTailPatterns = [
            #"\s+(?:and|but|so|because)\s+(?:i(?:'|’)?m|i\s+am|i(?:'|’)?d|i\s+would|i\s+want|i\s+need|i\s+like|i\s+would\s+like|please|can\s+you|could\s+you|would\s+you|you|we)\b.*$"#,
            #"\s+(?:and|but|so|because)\s+(?:help|use|prefer|would|want|need|like)\b.*$"#,
            #"\s*,\s*(?:and|but|so|because)\s+.*$"#
        ]

        return requestTailPatterns.reduce(markerTrimmedPhrase) { partial, pattern in
            partial.replacingOccurrences(
                of: pattern,
                with: "",
                options: [.caseInsensitive, .regularExpression]
            )
        }
    }

    private func phraseByDroppingRequestTailMarkers(from phrase: String) -> String {
        let normalized = phrase.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        let lowercased = normalized.lowercased()
        let markers = [
            " and i would like ",
            " and i'd like ",
            " and i want ",
            " and i need ",
            " and would like ",
            " and want ",
            " and need ",
            " and please ",
            ", i would like ",
            ", i'd like ",
            ", i want ",
            ", i need ",
            ", would like ",
            ", want ",
            ", need ",
            ", please ",
            " but i would like ",
            " but i'd like ",
            " but i want ",
            " but i need ",
            " but would like ",
            " but want ",
            " but need ",
            " so i would like ",
            " so i'd like ",
            " so i want ",
            " so i need ",
            " so would like ",
            " so want ",
            " so need "
        ]

        let firstMarkerRange = markers
            .compactMap { marker in lowercased.range(of: marker) }
            .min { left, right in left.lowerBound < right.lowerBound }

        guard let firstMarkerRange else { return normalized }
        return String(normalized[..<firstMarkerRange.lowerBound])
    }

    private func isLowConfidenceSelfDescription(_ phrase: String) -> Bool {
        let normalized = phrase.lowercased()
        let blockedTerms = [
            "ready",
            "here",
            "fine",
            "good",
            "ok",
            "okay",
            "sure",
            "happy",
            "sad",
            "tired",
            "hungry",
            "busy",
            "bored"
        ]
        return blockedTerms.contains(normalized)
            || normalized.contains("looking for")
            || normalized.contains("trying to")
            || normalized.contains("going to")
    }

    private func article(for phrase: String) -> String {
        let trimmedPhrase = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let firstWord = trimmedPhrase.split(separator: " ").first else {
            return "a"
        }

        let firstWordText = String(firstWord)
        let isInitialism = firstWordText.count > 1 && firstWordText == firstWordText.uppercased()
        if isInitialism, ["A", "E", "F", "H", "I", "L", "M", "N", "O", "R", "S", "X"].contains(String(firstWordText.prefix(1))) {
            return "an"
        }

        guard let firstCharacter = trimmedPhrase.lowercased().first else { return "a" }
        return ["a", "e", "i", "o", "u"].contains(firstCharacter) ? "an" : "a"
    }

    private func memoryExtractionSystemPrompt() -> String {
        """
        You write durable user memories for a private on-device assistant. You are not a topic tagger.
        Return only a compact JSON array of objects.
        Read only the provided user message and decide whether it contains anything worth remembering for future conversations.
        Use only stable user facts, preferences, likes, dislikes, fandoms, goals, ongoing projects, names, roles, or constraints.
        Each object must use exactly these keys: canonicalContent, relation, value, sourceQuote, sourceLanguageCode, confidence.
        canonicalContent must be English and must start with "The user..." or "The user's...".
        relation must be one of: name, pronouns, residence, timezone, occupation, employer, education, language, likes, dislikes, goal, project, constraint, allergy, diet, identity, general.
        value must be the short canonical English value for the relation.
        sourceQuote must be an exact quote copied from the provided user message; never invent or paraphrase the source quote.
        sourceLanguageCode should be a BCP-47 language code when clear.
        confidence must be a number from 0 to 1.
        Example: "Me llamo Alan" becomes {"canonicalContent":"The user's name is Alan.","relation":"name","value":"Alan","sourceQuote":"Me llamo Alan","sourceLanguageCode":"es","confidence":0.98}.
        Example: "Odio el brócoli" becomes {"canonicalContent":"The user dislikes broccoli.","relation":"dislikes","value":"broccoli","sourceQuote":"Odio el brócoli","sourceLanguageCode":"es","confidence":0.95}.
        Example: "Quiero apuntarme a un gimnasio" becomes {"canonicalContent":"The user wants to join a gym.","relation":"goal","value":"join a gym","sourceQuote":"Quiero apuntarme a un gimnasio","sourceLanguageCode":"es","confidence":0.90}.
        If a user message mixes a stable fact with a request, save only the stable fact.
        Do not output labels, topics, categories, keywords, or request types like "clarification request" or "sports recommendation".
        Do not save greetings, thanks, acknowledgements, small talk, or descriptions of what the user said, such as "The user says hi."
        Use only information stated or directly implied by the user message; never turn your own likely answer, price estimate, recommendation, or budget number into a user memory.
        Do not infer a preference just because the user asks about a topic.
        Do not include temporary requests, assistant facts, generic advice, secrets, or anything uncertain.
        If there is nothing worth remembering, return [].
        Keep each memory under 22 words.
        """
    }

    private func memoryExtractionPrompt(userMessage: ChatMessage) -> String {
        """
        User message only:
        \(userMessage.content)
        """
    }

    private func shouldRunFinalAnswerFollowUp(for parsedContent: ParsedAssistantContent, thinkingEnabled: Bool) -> Bool {
        guard thinkingEnabled else { return false }
        return parsedContent.response.isEmpty
    }

    private func shouldInterruptThinking(
        in parsedContent: ParsedAssistantContent,
        thinkingEnabled: Bool,
        tokenCount: Int,
        hiddenThinkingMaxTokens: Int?
    ) -> Bool {
        guard thinkingEnabled else { return false }
        guard tokenCount >= Constants.Generation.repetitiveThinkingCheckStartTokens else { return false }
        guard parsedContent.response.isEmpty, let thinking = parsedContent.thinking, !thinking.isEmpty else { return false }
        if let hiddenThinkingMaxTokens, tokenCount >= hiddenThinkingMaxTokens {
            return true
        }

        let duplicateThreshold = Constants.Generation.repetitiveThinkingDuplicateLineThreshold
        var counts: [String: Int] = [:]

        for line in thinking.components(separatedBy: .newlines) {
            let normalized = normalizedThinkingLine(line)
            guard normalized.count >= 18 else { continue }
            let updatedCount = (counts[normalized] ?? 0) + 1
            counts[normalized] = updatedCount
            if updatedCount >= duplicateThreshold {
                return true
            }
        }

        return false
    }

    private func normalizedThinkingLine(_ line: String) -> String {
        line
            .lowercased()
            .replacingOccurrences(of: #"^\s*(?:\d+[\.\)]\s*|[-*]\s*)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"[*_`"]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
