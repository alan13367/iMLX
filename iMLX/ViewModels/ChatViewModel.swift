import Foundation
import SwiftUI

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
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        isGenerating = true
        currentResponse = ""
        errorMessage = nil

        Haptics.impactLight()

        let temperature = Float(appState.settingsViewModel.temperature)
        let topP = Float(appState.settingsViewModel.topP)
        let repetitionPenalty = Float(appState.settingsViewModel.repetitionPenalty)
        let systemPrompt = appState.settingsViewModel.systemPrompt
        let loadedModel = resolvedCurrentModel()
        let generationPrompt = loadedModel?.prompt(for: text, thinkingEnabled: isThinkingEnabled) ?? text

        generationTask = Task { @MainActor in
            let startTime = Date()
            var tokenCount = 0

            do {
                let stream = await inferenceService.generate(
                    prompt: generationPrompt,
                    history: history,
                    systemPrompt: systemPrompt,
                    temperature: temperature,
                    topP: topP,
                    repetitionPenalty: repetitionPenalty
                )

                for try await token in stream {
                    guard !Task.isCancelled else { break }
                    currentResponse += token
                    tokenCount += 1
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
}
