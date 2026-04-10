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
    var messages: [ChatMessage] = []
    var currentResponse: String = ""
    var currentParsedResponse: ParsedAssistantContent = .empty
    var isGenerating: Bool = false
    var isModelLoading: Bool = false
    var errorMessage: String?
    var memoryNotice: ChatMemoryNotice?
    var activeConversationId: UUID?
    var isThinkingEnabled: Bool = false
    var isWebSearchEnabled: Bool = false
    var webSearchNotice: String?

    var canUseThinking: Bool {
        resolvedCurrentModel()?.supportsThinking == true
    }

    var canUseVision: Bool {
        resolvedCurrentModel()?.supportsVision == true
    }

    var pendingImages: [ChatAttachmentImage] = []
    var pendingDocuments: [ConversationDocumentReference] = []
    var attachedDocuments: [ConversationDocumentReference] = []
    var activePersonaId: String?

    var activePersona: Persona {
        appState.persona(id: activePersonaId) ?? appState.defaultPersona()
    }

    var availablePersonas: [Persona] {
        appState.personas
    }

    private var inferenceService: InferenceService { appState.inferenceService }
    private var downloadService: ModelDownloadService { appState.downloadService }
    private var generationTask: Task<ChatMessage?, Never>?
    private let appState: AppState
    private let deviceCapabilityService: DeviceCapabilityService
    private var capabilityModelId: String?
    private var memoryExtractionTasks: [UUID: Task<Void, Never>] = [:]
    private var titleGenerationTasks: [UUID: Task<Void, Never>] = [:]
    private var suppressedMemoryNoticeKey: String?

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
        pendingDocuments = []
        attachedDocuments = conversation.documents
        activePersonaId = appState.persona(id: conversation.personaId)?.id ?? appState.defaultPersona().id
        currentResponse = ""
        currentParsedResponse = .empty
        errorMessage = nil
        memoryNotice = nil
        suppressedMemoryNoticeKey = nil
        isWebSearchEnabled = conversation.webSearchEnabled
        webSearchNotice = nil
        updateThinkingAvailability(for: resolvedCurrentModel())
    }

    @MainActor
    func sendMessage(_ text: String) {
        let normalizedText = prepareToSendMessage(text)
        guard let normalizedText else { return }
        generationTask = Task<ChatMessage?, Never> { @MainActor [self] in
            return await self.performSendMessage(normalizedText)
        }
    }

    @MainActor
    func sendMessageAndWait(_ text: String) async -> ChatMessage? {
        let normalizedText = prepareToSendMessage(text)
        guard let normalizedText else { return nil }
        let task = Task<ChatMessage?, Never> { @MainActor [self] in
            return await self.performSendMessage(normalizedText)
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
    private func performSendMessage(_ text: String) async -> ChatMessage? {
        let loadedModel = resolvedCurrentModel()
        let history = promptHistory(from: messages, for: loadedModel)
        let userMessage = ChatMessage(
            role: .user,
            content: text,
            attachedImages: pendingImages.isEmpty ? nil : pendingImages,
            attachedDocuments: pendingDocuments.isEmpty ? nil : pendingDocuments
        )
        messages.append(userMessage)
        let handledExplicitMemoryCommand = handleExplicitMemoryCommands(in: text, userMessage: userMessage)

        isGenerating = true
        currentResponse = ""
        currentParsedResponse = .empty
        errorMessage = nil
        webSearchNotice = nil
        pendingImages.removeAll()
        pendingDocuments.removeAll()

        Haptics.impactLight()

        let persona = activePersona
        let temperature = Float(persona.temperature)
        let topP = Float(persona.topP)
        let repetitionPenalty = safeRepetitionPenalty(Float(persona.repetitionPenalty))
        let systemPrompt = persona.effectiveSystemPrompt
        let thinkingEnabled = loadedModel?.supportsThinking == true ? isThinkingEnabled : false
        let generationMaxTokens = generationTokenLimit(for: loadedModel, thinkingEnabled: thinkingEnabled)

        let startTime = Date()
        var tokenCount = 0
        var accumulatedResponse = ""
        var latestParsedResponse = ParsedAssistantContent.empty
        var lastResponseFlush = Date.distantPast
        var shouldForceFinalAnswerFollowUp = false
        let retrievalResult = await self.appState.documentLibraryService.retrieveContext(
                for: text,
                documents: self.attachedDocuments
            )
        let webRetrievalResult: MessageGroundingResult
        if isWebSearchEnabled {
            do {
                webRetrievalResult = try await appState.webSearchService.retrieveContext(for: text)
            } catch {
                webRetrievalResult = MessageGroundingResult(contextBlock: "", sources: [])
                webSearchNotice = "Web search was unavailable for this turn. iMLX answered locally instead."
            }
        } else {
            webRetrievalResult = MessageGroundingResult(contextBlock: "", sources: [])
        }
        let memoryRetrievalResult = self.appState.retrieveMemoryContext(
                for: text,
                personaId: persona.id,
                maxCharacters: self.memoryContextCharacterLimit(for: loadedModel)
            )
        let memoryContext = self.promptMemoryContext(
                memoryRetrievalResult.contextBlock,
                for: loadedModel
            )
        let documentContext = self.promptDocumentContext(
                retrievalResult.contextBlock,
                for: loadedModel
            )
        let webContext = self.promptWebContext(
            webRetrievalResult.contextBlock,
            for: loadedModel
        )
        let effectiveSystemPrompt = self.mergedSystemPrompt(
                base: systemPrompt,
                memoryContext: memoryContext,
                documentContext: documentContext,
                webContext: webContext,
                thinkingEnabled: thinkingEnabled
            )

        @MainActor
        func enforceMemorySafety() throws {
            let availableMB = self.deviceCapabilityService.availableMemoryMB
            if availableMB > 0 && availableMB < Constants.Generation.lowMemoryAbortThresholdMB {
                throw ChatGenerationAbort.lowMemory(availableMB)
            }
        }

        @MainActor
        func refreshParsedResponse() {
            latestParsedResponse = ParsedAssistantContent(accumulatedResponse, isStreaming: true)
        }

        @MainActor
        func flushResponseToUI(force: Bool = false) {
            let now = Date()
            guard force || now.timeIntervalSince(lastResponseFlush) >= Constants.UI.streamingResponseFlushInterval else { return }
            refreshParsedResponse()
            self.currentResponse = accumulatedResponse
            self.currentParsedResponse = latestParsedResponse
            lastResponseFlush = now
        }

        var completedAssistantMessage: ChatMessage?

        do {
            let stream = await self.inferenceService.generate(
                    prompt: text,
                    images: userMessage.attachedImages,
                    thinkingEnabled: loadedModel?.supportsThinking == true ? thinkingEnabled : nil,
                    history: history,
                    systemPrompt: effectiveSystemPrompt,
                    maxTokens: generationMaxTokens,
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
                        try enforceMemorySafety()
                        if self.shouldInterruptRepetitiveThinking(
                            in: latestParsedResponse,
                            thinkingEnabled: thinkingEnabled,
                            tokenCount: tokenCount
                        ) {
                            shouldForceFinalAnswerFollowUp = true
                            break
                        }
                    }
                }

                flushResponseToUI(force: true)

            if shouldForceFinalAnswerFollowUp || self.shouldRunFinalAnswerFollowUp(for: latestParsedResponse, thinkingEnabled: thinkingEnabled) {
                let followUpStream = await self.inferenceService.generate(
                        prompt: text,
                        images: userMessage.attachedImages,
                        thinkingEnabled: false,
                        history: history,
                        systemPrompt: self.finalAnswerSystemPrompt(
                            base: systemPrompt,
                            memoryContext: memoryContext,
                            documentContext: documentContext,
                            webContext: webContext
                        ),
                        maxTokens: Constants.Generation.finalAnswerMaxTokens,
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
                            try enforceMemorySafety()
                        }
                    }
                }

                flushResponseToUI(force: true)

                let elapsed = Date().timeIntervalSince(startTime)
                let peakMemory = await self.currentMemoryUsage()
                let promptMessageCount = self.messages.count - (accumulatedResponse.isEmpty ? 1 : 2)
                let generationStats = GenerationStats(
                    tokensPerSecond: Double(tokenCount) / max(elapsed, 0.001),
                    totalTokens: tokenCount,
                    promptTokens: promptMessageCount,
                    generationTime: elapsed,
                    peakMemoryMB: peakMemory
                )

            if !accumulatedResponse.isEmpty {
                let assistantMessage = ChatMessage(
                        role: .assistant,
                        content: accumulatedResponse,
                        retrievedSources: combinedSources(
                            retrievalResult.sources,
                            webRetrievalResult.sources
                        ),
                        generationStats: generationStats
                    )
                self.messages.append(assistantMessage)
                self.scheduleMemoryExtraction(
                    userMessage: userMessage,
                    assistantMessage: assistantMessage,
                    personaId: persona.id,
                    conversationId: self.activeConversationId,
                    isEnabled: !handledExplicitMemoryCommand
                )
                completedAssistantMessage = assistantMessage
                self.saveCurrentConversation()
                self.scheduleConversationTitleGeneration(
                    userMessage: userMessage,
                    assistantMessage: assistantMessage
                )
            } else {
                self.saveCurrentConversation()
            }
            Haptics.impactMedium()
        } catch is CancellationError {
            flushResponseToUI(force: true)
            if !accumulatedResponse.isEmpty {
                let elapsed = Date().timeIntervalSince(startTime)
                let peakMemory = await self.currentMemoryUsage()
                let partialMessage = ChatMessage(
                        role: .assistant,
                        content: accumulatedResponse,
                        retrievedSources: combinedSources(
                            retrievalResult.sources,
                            webRetrievalResult.sources
                        ),
                        generationStats: GenerationStats(
                            tokensPerSecond: Double(tokenCount) / max(elapsed, 0.001),
                            totalTokens: tokenCount,
                            promptTokens: self.messages.count - 1,
                            generationTime: elapsed,
                            peakMemoryMB: peakMemory
                        )
                    )
                self.messages.append(partialMessage)
                completedAssistantMessage = partialMessage
            }
            self.saveCurrentConversation()
        } catch {
            flushResponseToUI(force: true)
            if !accumulatedResponse.isEmpty {
                let elapsed = Date().timeIntervalSince(startTime)
                let peakMemory = await self.currentMemoryUsage()
                let partialMessage = ChatMessage(
                        role: .assistant,
                        content: accumulatedResponse,
                        retrievedSources: combinedSources(
                            retrievalResult.sources,
                            webRetrievalResult.sources
                        ),
                        generationStats: GenerationStats(
                            tokensPerSecond: Double(tokenCount) / max(elapsed, 0.001),
                            totalTokens: tokenCount,
                            promptTokens: self.messages.count - 1,
                            generationTime: elapsed,
                            peakMemoryMB: peakMemory
                        )
                    )
                self.messages.append(partialMessage)
                completedAssistantMessage = partialMessage
            }
            self.errorMessage = error.localizedDescription
            self.saveCurrentConversation()
            Haptics.notificationError()
        }

        self.currentResponse = ""
        self.currentParsedResponse = .empty
        self.isGenerating = false
        self.generationTask = nil
        return completedAssistantMessage
    }

    @MainActor
    func stopGeneration() {
        generationTask?.cancel()
        generationTask = nil
    }

    @MainActor
    func loadModel(_ model: ModelInfo) async {
        isModelLoading = true
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
        if let conversation = appState.conversations.first(where: { $0.id == id }) {
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
            activePersonaId = appState.defaultPersona().id
            isWebSearchEnabled = false
            webSearchNotice = nil
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
    func selectPersona(_ persona: Persona) {
        activePersonaId = persona.id
        saveCurrentConversation()
        updateThinkingAvailability(for: resolvedCurrentModel())
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
        if let existing = appState.conversations.first(where: { $0.id == conversationId }) {
            conversation = existing
            conversation.messages = messages
            conversation.modelId = appState.loadedModelId
            conversation.personaId = activePersonaId ?? appState.defaultPersona().id
            conversation.webSearchEnabled = isWebSearchEnabled
            conversation.documents = attachedDocuments
            conversation.updatedAt = Date()
        } else {
            conversation = Conversation(
                id: conversationId,
                messages: messages,
                modelId: appState.loadedModelId,
                personaId: activePersonaId ?? appState.defaultPersona().id,
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
        guard let conversation = appState.conversations.first(where: { $0.id == conversationId }) else { return }
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

    private func combinedSources(_ documentSources: [MessageSource], _ webSources: [MessageSource]) -> [MessageSource]? {
        let sources = documentSources + webSources
        return sources.isEmpty ? nil : sources
    }

    @MainActor
    private func handleExplicitMemoryCommands(in text: String, userMessage: ChatMessage) -> Bool {
        var handledCommand = false

        if let memoryContent = explicitRememberContent(from: text) {
            handledCommand = true
            let savedMemory = appState.saveMemory(
                content: memoryContent,
                status: .active,
                captureType: .explicit,
                personaId: activePersonaId,
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
                personaId: activePersonaId,
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
        personaId: String?,
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
                        personaId: personaId,
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
           let loadedModel = Constants.ModelRegistry.curatedModels.first(where: { $0.id == loadedModelId }) {
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

    private func generationTokenLimit(for model: ModelInfo?, thinkingEnabled: Bool) -> Int {
        let baseLimit: Int
        if thinkingEnabled {
            let estimatedSizeGB = model?.estimatedSizeGB ?? 0
            if estimatedSizeGB > 0 && estimatedSizeGB <= 1.0 {
                baseLimit = Constants.Generation.compactModelThinkingMaxTokens
            } else if isMemoryConstrainedLargeModel(model) {
                baseLimit = Constants.Generation.memoryConstrainedThinkingMaxTokens
            } else {
                baseLimit = Constants.Generation.thinkingMaxTokens
            }
        } else {
            baseLimit = Constants.Generation.standardMaxTokens
        }

        guard isMemoryConstrainedLargeModel(model) else { return baseLimit }
        if model?.supportsVision == true {
            return min(baseLimit, memoryConstrainedVisionTokenLimit())
        }
        return min(baseLimit, Constants.Generation.memoryConstrainedStandardMaxTokens)
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

    private func promptDocumentContext(_ context: String, for model: ModelInfo?) -> String {
        guard isMemoryConstrainedLargeModel(model) else { return context }
        let characterLimit = Constants.Generation.memoryConstrainedDocumentContextCharacters
        guard context.count > characterLimit else { return context }
        return String(context.prefix(characterLimit))
    }

    private func promptWebContext(_ context: String, for model: ModelInfo?) -> String {
        guard isMemoryConstrainedLargeModel(model) else { return context }
        let characterLimit = Constants.Generation.memoryConstrainedDocumentContextCharacters
        guard context.count > characterLimit else { return context }
        return String(context.prefix(characterLimit))
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

    private func mergedSystemPrompt(base: String, memoryContext: String, documentContext: String, webContext: String, thinkingEnabled: Bool) -> String {
        var parts: [String] = []
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBase.isEmpty {
            parts.append(trimmedBase)
        }
        let trimmedMemoryContext = memoryContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMemoryContext.isEmpty {
            parts.append(trimmedMemoryContext)
        }
        let trimmedDocumentContext = documentContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDocumentContext.isEmpty {
            parts.append(trimmedDocumentContext)
        }
        let trimmedWebContext = webContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedWebContext.isEmpty {
            parts.append(trimmedWebContext)
        }
        if thinkingEnabled {
            parts.append(Constants.Generation.conciseThinkingInstruction)
        }
        return parts.joined(separator: "\n\n")
    }

    private func finalAnswerSystemPrompt(base: String, memoryContext: String, documentContext: String, webContext: String) -> String {
        var parts: [String] = []
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBase.isEmpty {
            parts.append(trimmedBase)
        }
        let trimmedMemoryContext = memoryContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMemoryContext.isEmpty {
            parts.append(trimmedMemoryContext)
        }
        let trimmedDocumentContext = documentContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDocumentContext.isEmpty {
            parts.append(trimmedDocumentContext)
        }
        let trimmedWebContext = webContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedWebContext.isEmpty {
            parts.append(trimmedWebContext)
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

    private func shouldInterruptRepetitiveThinking(in parsedContent: ParsedAssistantContent, thinkingEnabled: Bool, tokenCount: Int) -> Bool {
        guard thinkingEnabled else { return false }
        guard tokenCount >= Constants.Generation.repetitiveThinkingCheckStartTokens else { return false }
        guard parsedContent.response.isEmpty, let thinking = parsedContent.thinking, !thinking.isEmpty else { return false }

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
