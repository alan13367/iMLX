import Foundation
import SwiftUI

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
    var isGenerating: Bool = false
    var isModelLoading: Bool = false
    var errorMessage: String?
    var activeConversationId: UUID?
    var isThinkingEnabled: Bool = false

    var canUseThinking: Bool {
        resolvedCurrentModel()?.supportsThinking == true
    }

    var canUseVision: Bool {
        resolvedCurrentModel()?.supportsVision == true
    }

    var pendingImages: [Data] = []
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
    private var generationTask: Task<Void, Never>?
    private let appState: AppState
    private let deviceCapabilityService: DeviceCapabilityService
    private var capabilityModelId: String?

    init(appState: AppState, deviceCapabilityService: DeviceCapabilityService = DeviceCapabilityService()) {
        self.appState = appState
        self.deviceCapabilityService = deviceCapabilityService
        updateThinkingAvailability(for: resolvedCurrentModel())
    }

    deinit {
        generationTask?.cancel()
    }

    @MainActor
    func loadConversation(_ conversation: Conversation) {
        activeConversationId = conversation.id
        messages = conversation.messages
        pendingDocuments = []
        attachedDocuments = conversation.documents
        activePersonaId = appState.persona(id: conversation.personaId)?.id ?? appState.defaultPersona().id
        currentResponse = ""
        errorMessage = nil
        updateThinkingAvailability(for: resolvedCurrentModel())
    }

    @MainActor
    func sendMessage(_ text: String) {
        guard !isGenerating else { return }
        guard !isModelLoading else {
            errorMessage = String.appLocalized("error.chat.model_still_loading")
            Haptics.notificationWarning()
            return
        }
        guard appState.loadedModelId != nil else {
            errorMessage = String.appLocalized("error.chat.no_model_loaded")
            Haptics.notificationWarning()
            return
        }

        let availableMB = deviceCapabilityService.availableMemoryMB
        if availableMB > 0 && availableMB < 200 {
            errorMessage = String(format: String.appLocalized("error.chat.low_memory"), availableMB)
            Haptics.notificationWarning()
            return
        }

        if activeConversationId == nil {
            let id = appState.createNewConversation()
            activeConversationId = id
        }

        let history = messages
        let userMessage = ChatMessage(
            role: .user,
            content: text,
            attachedImages: pendingImages.isEmpty ? nil : pendingImages,
            attachedDocuments: pendingDocuments.isEmpty ? nil : pendingDocuments
        )
        messages.append(userMessage)

        isGenerating = true
        currentResponse = ""
        errorMessage = nil
        pendingImages.removeAll()
        pendingDocuments.removeAll()

        Haptics.impactLight()

        let persona = activePersona
        let temperature = Float(persona.temperature)
        let topP = Float(persona.topP)
        let repetitionPenalty = safeRepetitionPenalty(Float(persona.repetitionPenalty))
        let systemPrompt = persona.effectiveSystemPrompt
        let loadedModel = resolvedCurrentModel()
        let thinkingEnabled = loadedModel?.supportsThinking == true ? isThinkingEnabled : false
        let generationMaxTokens = generationTokenLimit(for: loadedModel, thinkingEnabled: thinkingEnabled)

        generationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let startTime = Date()
            var tokenCount = 0
            var shouldForceFinalAnswerFollowUp = false
            let retrievalResult = await self.appState.documentLibraryService.retrieveContext(
                for: text,
                documents: self.attachedDocuments
            )
            let effectiveSystemPrompt = self.mergedSystemPrompt(
                base: systemPrompt,
                documentContext: retrievalResult.contextBlock,
                thinkingEnabled: thinkingEnabled
            )

            func enforceMemorySafety() throws {
                let availableMB = self.deviceCapabilityService.availableMemoryMB
                if availableMB > 0 && availableMB < Constants.Generation.lowMemoryAbortThresholdMB {
                    throw ChatGenerationAbort.lowMemory(availableMB)
                }
            }

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
                    self.currentResponse += token
                    tokenCount += 1
                    if tokenCount.isMultiple(of: Constants.Generation.lowMemoryCheckInterval) {
                        try enforceMemorySafety()
                        if self.shouldInterruptRepetitiveThinking(
                            in: self.currentResponse,
                            thinkingEnabled: thinkingEnabled,
                            tokenCount: tokenCount
                        ) {
                            shouldForceFinalAnswerFollowUp = true
                            break
                        }
                    }
                }

                if shouldForceFinalAnswerFollowUp || self.shouldRunFinalAnswerFollowUp(for: self.currentResponse, thinkingEnabled: thinkingEnabled) {
                    let followUpStream = await self.inferenceService.generate(
                        prompt: text,
                        images: userMessage.attachedImages,
                        thinkingEnabled: false,
                        history: history,
                        systemPrompt: self.finalAnswerSystemPrompt(
                            base: systemPrompt,
                            documentContext: retrievalResult.contextBlock
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
                            self.currentResponse += "\n\nFinal Answer:\n"
                            startedFollowUpOutput = true
                        }
                        self.currentResponse += token
                        tokenCount += 1
                        if tokenCount.isMultiple(of: Constants.Generation.lowMemoryCheckInterval) {
                            try enforceMemorySafety()
                        }
                    }
                }

                let elapsed = Date().timeIntervalSince(startTime)
                let peakMemory = await self.currentMemoryUsage()
                let promptMessageCount = self.messages.count - (self.currentResponse.isEmpty ? 1 : 2)
                let generationStats = GenerationStats(
                    tokensPerSecond: Double(tokenCount) / max(elapsed, 0.001),
                    totalTokens: tokenCount,
                    promptTokens: promptMessageCount,
                    generationTime: elapsed,
                    peakMemoryMB: peakMemory
                )

                if !self.currentResponse.isEmpty {
                    let assistantMessage = ChatMessage(
                        role: .assistant,
                        content: self.currentResponse,
                        retrievedSources: retrievalResult.sources.isEmpty ? nil : retrievalResult.sources,
                        generationStats: generationStats
                    )
                    self.messages.append(assistantMessage)
                }

                self.saveCurrentConversation()
                Haptics.impactMedium()
            } catch is CancellationError {
                if !self.currentResponse.isEmpty {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let peakMemory = await self.currentMemoryUsage()
                    let partialMessage = ChatMessage(
                        role: .assistant,
                        content: self.currentResponse,
                        retrievedSources: retrievalResult.sources.isEmpty ? nil : retrievalResult.sources,
                        generationStats: GenerationStats(
                            tokensPerSecond: Double(tokenCount) / max(elapsed, 0.001),
                            totalTokens: tokenCount,
                            promptTokens: self.messages.count - 1,
                            generationTime: elapsed,
                            peakMemoryMB: peakMemory
                        )
                    )
                    self.messages.append(partialMessage)
                }
                self.saveCurrentConversation()
            } catch {
                if !self.currentResponse.isEmpty {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let peakMemory = await self.currentMemoryUsage()
                    let partialMessage = ChatMessage(
                        role: .assistant,
                        content: self.currentResponse,
                        retrievedSources: retrievalResult.sources.isEmpty ? nil : retrievalResult.sources,
                        generationStats: GenerationStats(
                            tokensPerSecond: Double(tokenCount) / max(elapsed, 0.001),
                            totalTokens: tokenCount,
                            promptTokens: self.messages.count - 1,
                            generationTime: elapsed,
                            peakMemoryMB: peakMemory
                        )
                    )
                    self.messages.append(partialMessage)
                }
                self.errorMessage = error.localizedDescription
                self.saveCurrentConversation()
                Haptics.notificationError()
            }

            self.currentResponse = ""
            self.isGenerating = false
        }
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
            errorMessage = nil
            activePersonaId = appState.defaultPersona().id
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
            conversation.documents = attachedDocuments
            conversation.updatedAt = Date()
        } else {
            conversation = Conversation(
                id: conversationId,
                messages: messages,
                modelId: appState.loadedModelId,
                personaId: activePersonaId ?? appState.defaultPersona().id,
                documents: attachedDocuments
            )
        }

        appState.updateConversation(conversation)
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
        guard thinkingEnabled else { return Constants.Generation.standardMaxTokens }
        let deviceTier = deviceCapabilityService.tier
        let estimatedSizeGB = model?.estimatedSizeGB ?? 0
        let isLargeModel = (model?.minDeviceRAM ?? 0) >= 12 || (model?.estimatedSizeGB ?? 0) >= 2.5
        if estimatedSizeGB > 0 && estimatedSizeGB <= 1.0 {
            return Constants.Generation.compactModelThinkingMaxTokens
        }
        if deviceTier <= .tier12GB && isLargeModel {
            return Constants.Generation.memoryConstrainedThinkingMaxTokens
        }
        return Constants.Generation.thinkingMaxTokens
    }

    private func safeRepetitionPenalty(_ requested: Float) -> Float {
        max(1.0, min(requested, 2.0))
    }

    private func mergedSystemPrompt(base: String, documentContext: String, thinkingEnabled: Bool) -> String {
        var parts: [String] = []
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBase.isEmpty {
            parts.append(trimmedBase)
        }
        let trimmedDocumentContext = documentContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDocumentContext.isEmpty {
            parts.append(trimmedDocumentContext)
        }
        if thinkingEnabled {
            parts.append(Constants.Generation.conciseThinkingInstruction)
        }
        return parts.joined(separator: "\n\n")
    }

    private func finalAnswerSystemPrompt(base: String, documentContext: String) -> String {
        var parts: [String] = []
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBase.isEmpty {
            parts.append(trimmedBase)
        }
        let trimmedDocumentContext = documentContext.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDocumentContext.isEmpty {
            parts.append(trimmedDocumentContext)
        }
        parts.append(Constants.Generation.finalAnswerOnlyInstruction)
        return parts.joined(separator: "\n\n")
    }

    private func shouldRunFinalAnswerFollowUp(for content: String, thinkingEnabled: Bool) -> Bool {
        guard thinkingEnabled else { return false }
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return ParsedAssistantContent(trimmed, isStreaming: true).response.isEmpty
    }

    private func shouldInterruptRepetitiveThinking(in content: String, thinkingEnabled: Bool, tokenCount: Int) -> Bool {
        guard thinkingEnabled else { return false }
        guard tokenCount >= Constants.Generation.repetitiveThinkingCheckStartTokens else { return false }

        let parsed = ParsedAssistantContent(content, isStreaming: true)
        guard parsed.response.isEmpty, let thinking = parsed.thinking, !thinking.isEmpty else { return false }

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
