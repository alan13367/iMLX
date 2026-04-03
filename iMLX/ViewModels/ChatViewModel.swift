import Foundation
import SwiftUI

private enum ChatGenerationAbort: LocalizedError {
    case lowMemory(UInt64)

    var errorDescription: String? {
        switch self {
        case .lowMemory(let availableMB):
            "Generation was stopped to avoid a memory crash (\(availableMB) MB available). Try disabling thinking or using a smaller model."
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

    private var inferenceService: InferenceService { appState?.inferenceService ?? InferenceService() }
    private var downloadService: ModelDownloadService { appState?.downloadService ?? ModelDownloadService() }
    private var generationTask: Task<Void, Never>?
    private weak var appState: AppState?
    private var capabilityModelId: String?

    func configure(with appState: AppState) {
        self.appState = appState
        updateThinkingAvailability(for: resolvedCurrentModel())
    }

    func loadConversation(_ conversation: Conversation) {
        activeConversationId = conversation.id
        messages = conversation.messages
        currentResponse = ""
        errorMessage = nil
    }

    func sendMessage(_ text: String) {
        guard let appState else { return }
        guard appState.loadedModelId != nil else {
            errorMessage = "No model loaded. Please select and load a model first."
            Haptics.notificationWarning()
            return
        }

        let availableMB = DeviceCapabilityService().availableMemoryMB
        if availableMB > 0 && availableMB < 200 {
            errorMessage = "Low memory (\(availableMB) MB available). Close other apps or try a smaller model."
            Haptics.notificationWarning()
            return
        }

        if activeConversationId == nil {
            let id = appState.createNewConversation()
            activeConversationId = id
        }

        let history = messages
        let userMessage = ChatMessage(role: .user, content: text, attachedImages: pendingImages.isEmpty ? nil : pendingImages)
        messages.append(userMessage)

        isGenerating = true
        currentResponse = ""
        errorMessage = nil
        pendingImages.removeAll()

        Haptics.impactLight()

        let temperature = Float(appState.settingsViewModel.temperature)
        let topP = Float(appState.settingsViewModel.topP)
        let repetitionPenalty = Float(appState.settingsViewModel.repetitionPenalty)
        let systemPrompt = appState.settingsViewModel.systemPrompt
        let loadedModel = resolvedCurrentModel()
        let thinkingEnabled = loadedModel?.supportsThinking == true ? isThinkingEnabled : false
        let generationMaxTokens = generationTokenLimit(for: loadedModel, thinkingEnabled: thinkingEnabled)
        let effectiveSystemPrompt = mergedSystemPrompt(
            base: systemPrompt,
            thinkingEnabled: thinkingEnabled
        )

        generationTask = Task { @MainActor in
            let startTime = Date()
            var tokenCount = 0
            var shouldForceFinalAnswerFollowUp = false

            func enforceMemorySafety() throws {
                let availableMB = DeviceCapabilityService().availableMemoryMB
                if availableMB > 0 && availableMB < Constants.Generation.lowMemoryAbortThresholdMB {
                    throw ChatGenerationAbort.lowMemory(availableMB)
                }
            }

            do {
                let stream = await inferenceService.generate(
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
                    currentResponse += token
                    tokenCount += 1
                    if tokenCount.isMultiple(of: Constants.Generation.lowMemoryCheckInterval) {
                        try enforceMemorySafety()
                        if shouldInterruptRepetitiveThinking(
                            in: currentResponse,
                            thinkingEnabled: thinkingEnabled,
                            tokenCount: tokenCount
                        ) {
                            shouldForceFinalAnswerFollowUp = true
                            break
                        }
                    }
                }

                if shouldForceFinalAnswerFollowUp || shouldRunFinalAnswerFollowUp(for: currentResponse, thinkingEnabled: thinkingEnabled) {
                    let followUpStream = await inferenceService.generate(
                        prompt: text,
                        images: userMessage.attachedImages,
                        thinkingEnabled: false,
                        history: history,
                        systemPrompt: finalAnswerSystemPrompt(base: systemPrompt),
                        maxTokens: Constants.Generation.finalAnswerMaxTokens,
                        temperature: temperature,
                        topP: topP,
                        repetitionPenalty: repetitionPenalty
                    )

                    var startedFollowUpOutput = false
                    for try await token in followUpStream {
                        guard !Task.isCancelled else { break }
                        if !startedFollowUpOutput {
                            currentResponse += "\n\nFinal Answer:\n"
                            startedFollowUpOutput = true
                        }
                        currentResponse += token
                        tokenCount += 1
                        if tokenCount.isMultiple(of: Constants.Generation.lowMemoryCheckInterval) {
                            try enforceMemorySafety()
                        }
                    }
                }

                let elapsed = Date().timeIntervalSince(startTime)
                let peakMemory = await currentMemoryUsage()
                let generationStats = GenerationStats(
                    tokensPerSecond: Double(tokenCount) / max(elapsed, 0.001),
                    totalTokens: tokenCount,
                    promptTokens: messages.count - (currentResponse.isEmpty ? 1 : 2),
                    generationTime: elapsed,
                    peakMemoryMB: peakMemory
                )

                if !currentResponse.isEmpty {
                    let assistantMessage = ChatMessage(
                        role: .assistant,
                        content: currentResponse,
                        generationStats: generationStats
                    )
                    messages.append(assistantMessage)
                }

                saveCurrentConversation()
                Haptics.impactMedium()
            } catch is CancellationError {
                if !currentResponse.isEmpty {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let peakMemory = await currentMemoryUsage()
                    let partialMessage = ChatMessage(
                        role: .assistant,
                        content: currentResponse,
                        generationStats: GenerationStats(
                            tokensPerSecond: Double(tokenCount) / max(elapsed, 0.001),
                            totalTokens: tokenCount,
                            promptTokens: messages.count - 1,
                            generationTime: elapsed,
                            peakMemoryMB: peakMemory
                        )
                    )
                    messages.append(partialMessage)
                }
                saveCurrentConversation()
            } catch {
                if !currentResponse.isEmpty {
                    let elapsed = Date().timeIntervalSince(startTime)
                    let peakMemory = await currentMemoryUsage()
                    let partialMessage = ChatMessage(
                        role: .assistant,
                        content: currentResponse,
                        generationStats: GenerationStats(
                            tokensPerSecond: Double(tokenCount) / max(elapsed, 0.001),
                            totalTokens: tokenCount,
                            promptTokens: messages.count - 1,
                            generationTime: elapsed,
                            peakMemoryMB: peakMemory
                        )
                    )
                    messages.append(partialMessage)
                }
                errorMessage = error.localizedDescription
                saveCurrentConversation()
                Haptics.notificationError()
            }

            currentResponse = ""
            isGenerating = false
        }
    }

    func stopGeneration() {
        generationTask?.cancel()
    }

    func loadModel(_ model: ModelInfo) async {
        isModelLoading = true
        errorMessage = nil

        do {
            guard await downloadService.isModelDownloaded(model) else {
                appState?.selectModel(nil)
                appState?.setLoadedModel(id: nil)
                throw InferenceError.modelLoadFailed("Model files are missing for \(model.displayName). Re-download it from the Models tab.")
            }
            let localURL = await downloadService.localURL(for: model)
            try await inferenceService.load(
                modelId: model.id,
                localDirectory: localURL
            )
            var updatedModel = model
            updatedModel.isDownloaded = true
            updatedModel.localURL = localURL
            appState?.selectModel(updatedModel)
            appState?.setLoadedModel(id: model.id)
            updateThinkingAvailability(for: updatedModel)
            saveCurrentConversation()
            Haptics.notificationSuccess()
        } catch {
            errorMessage = error.localizedDescription
            appState?.selectModel(nil)
            appState?.setLoadedModel(id: nil)
            updateThinkingAvailability(for: nil)
            Haptics.notificationError()
        }

        isModelLoading = false
    }

    func unloadModel() async {
        await inferenceService.unload()
        appState?.selectModel(nil)
        appState?.setLoadedModel(id: nil)
        updateThinkingAvailability(for: nil)
    }

    @discardableResult
    func startNewConversation() -> UUID? {
        guard let appState else {
            messages.removeAll()
            currentResponse = ""
            errorMessage = nil
            activeConversationId = nil
            return nil
        }

        let id = appState.createNewConversation()
        if let conversation = appState.conversations.first(where: { $0.id == id }) {
            loadConversation(conversation)
        } else {
            activeConversationId = id
            messages.removeAll()
            currentResponse = ""
            errorMessage = nil
        }
        return id
    }

    func toggleThinking() {
        guard canUseThinking else { return }
        isThinkingEnabled.toggle()
        Haptics.selectionChanged()
    }

    private func saveCurrentConversation() {
        guard let appState, let conversationId = activeConversationId else { return }

        var conversation: Conversation
        if let existing = appState.conversations.first(where: { $0.id == conversationId }) {
            conversation = existing
            conversation.messages = messages
            conversation.modelId = appState.loadedModelId
            conversation.updatedAt = Date()
        } else {
            conversation = Conversation(
                id: conversationId,
                messages: messages,
                modelId: appState.loadedModelId
            )
        }

        appState.updateConversation(conversation)
    }

    private func currentMemoryUsage() async -> UInt64 {
        let info = DeviceCapabilityService()
        return UInt64(info.currentMemoryUsageMB)
    }

    private func resolvedCurrentModel() -> ModelInfo? {
        if let selectedModel = appState?.selectedModel {
            return selectedModel
        }

        guard let loadedModelId = appState?.loadedModelId else { return nil }
        return Constants.ModelRegistry.curatedModels.first(where: { $0.id == loadedModelId })
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
        let deviceTier = DeviceCapabilityService().tier
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

    private func mergedSystemPrompt(base: String, thinkingEnabled: Bool) -> String {
        var parts: [String] = []
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBase.isEmpty {
            parts.append(trimmedBase)
        }
        if thinkingEnabled {
            parts.append(Constants.Generation.conciseThinkingInstruction)
        }
        return parts.joined(separator: "\n\n")
    }

    private func finalAnswerSystemPrompt(base: String) -> String {
        var parts: [String] = []
        let trimmedBase = base.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedBase.isEmpty {
            parts.append(trimmedBase)
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
