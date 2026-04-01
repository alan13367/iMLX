import Foundation
import SwiftUI

@Observable
final class ChatViewModel {
    var messages: [ChatMessage] = []
    var currentResponse: String = ""
    var isGenerating: Bool = false
    var isModelLoading: Bool = false
    var stats: GenerationStats?
    var errorMessage: String?
    var activeModelId: String?
    var activeConversationId: UUID?

    private var inferenceService: InferenceService { appState?.inferenceService ?? InferenceService() }
    private var downloadService: ModelDownloadService { appState?.downloadService ?? ModelDownloadService() }
    private var generationTask: Task<Void, Never>?
    private weak var appState: AppState?

    func configure(with appState: AppState) {
        self.appState = appState
    }

    func loadConversation(_ conversation: Conversation) {
        activeConversationId = conversation.id
        messages = conversation.messages
        currentResponse = ""
        stats = nil
        errorMessage = nil
    }

    func sendMessage(_ text: String) {
        guard activeModelId != nil else {
            errorMessage = "No model loaded. Please select and load a model first."
            Haptics.notificationWarning()
            return
        }

        guard let appState else { return }

        let availableMB = DeviceCapabilityService().availableMemoryMB
        if availableMB > 0 && availableMB < 200 {
            errorMessage = "Low memory (\(availableMB) MB available). Close other apps or try a smaller model."
            Haptics.notificationWarning()
            return
        }

        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        isGenerating = true
        currentResponse = ""
        stats = nil
        errorMessage = nil

        Haptics.impactLight()

        let maxTokens = appState.settingsViewModel.maxTokens
        let temperature = Float(appState.settingsViewModel.temperature)
        let topP = Float(appState.settingsViewModel.topP)

        generationTask = Task { @MainActor in
            let startTime = Date()
            var tokenCount = 0

            do {
                let prompt = buildPrompt(systemPrompt: appState.settingsViewModel.systemPrompt)

                let stream = await inferenceService.generate(
                    prompt: prompt,
                    maxTokens: maxTokens,
                    temperature: temperature,
                    topP: topP
                )

                for try await token in stream {
                    guard !Task.isCancelled else { break }
                    currentResponse += token
                    tokenCount += 1
                }

                let elapsed = Date().timeIntervalSince(startTime)
                let peakMemory = await currentMemoryUsage()

                if !currentResponse.isEmpty {
                    let assistantMessage = ChatMessage(role: .assistant, content: currentResponse)
                    messages.append(assistantMessage)
                }

                stats = GenerationStats(
                    tokensPerSecond: Double(tokenCount) / max(elapsed, 0.001),
                    totalTokens: tokenCount,
                    promptTokens: messages.count - (currentResponse.isEmpty ? 1 : 2),
                    generationTime: elapsed,
                    peakMemoryMB: peakMemory
                )

                saveCurrentConversation()
                Haptics.impactMedium()
            } catch is CancellationError {
                if !currentResponse.isEmpty {
                    let partialMessage = ChatMessage(role: .assistant, content: currentResponse)
                    messages.append(partialMessage)
                }
                saveCurrentConversation()
            } catch {
                errorMessage = error.localizedDescription
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
            let localURL = await downloadService.localURL(for: model)
            try await inferenceService.load(
                modelId: model.id,
                localDirectory: localURL
            )
            activeModelId = model.id
            appState?.setLoadedModel(id: model.id)
            Haptics.notificationSuccess()
        } catch {
            errorMessage = error.localizedDescription
            activeModelId = nil
            appState?.setLoadedModel(id: nil)
            Haptics.notificationError()
        }

        isModelLoading = false
    }

    func unloadModel() async {
        await inferenceService.unload()
        activeModelId = nil
        appState?.setLoadedModel(id: nil)
    }

    func clearConversation() {
        messages.removeAll()
        currentResponse = ""
        stats = nil
        errorMessage = nil
        activeConversationId = nil
    }

    private func buildPrompt(systemPrompt: String = "") -> String {
        var parts: [String] = []

        if !systemPrompt.isEmpty {
            parts.append("System: \(systemPrompt)")
        }

        for msg in messages {
            switch msg.role {
            case .user: parts.append("User: \(msg.content)")
            case .assistant: parts.append("Assistant: \(msg.content)")
            case .system: parts.append("System: \(msg.content)")
            }
        }

        return parts.joined(separator: "\n") + "\nAssistant:"
    }

    private func saveCurrentConversation() {
        guard let appState, let conversationId = activeConversationId else { return }

        var conversation: Conversation
        if let existing = appState.conversations.first(where: { $0.id == conversationId }) {
            conversation = existing
            conversation.messages = messages
            conversation.modelId = activeModelId
            conversation.updatedAt = Date()
        } else {
            conversation = Conversation(
                id: conversationId,
                messages: messages,
                modelId: activeModelId
            )
        }

        appState.updateConversation(conversation)
    }

    private func currentMemoryUsage() async -> UInt64 {
        let info = DeviceCapabilityService()
        return UInt64(info.currentMemoryUsageMB)
    }
}
