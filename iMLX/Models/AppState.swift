import Foundation

@Observable
final class AppState {
    var selectedModel: ModelInfo?
    var isModelLoading: Bool = false
    var loadedModelId: String?

    let settingsViewModel = SettingsViewModel()
    let conversationService = ConversationService()
    let inferenceService = InferenceService()
    let downloadService = ModelDownloadService()
    var conversations: [Conversation] = []
    var activeConversationId: UUID?

    private let userDefaults = UserDefaults.standard
    private let manifestService = ManifestService()

    init() {
        restoreModelState()
        reconcileDownloadedModelState()
    }

    func selectModel(_ model: ModelInfo?) {
        selectedModel = model
        if let model {
            userDefaults.set(model.id, forKey: "selectedModelId")
        } else {
            userDefaults.removeObject(forKey: "selectedModelId")
        }
    }

    func setLoadedModel(id: String?) {
        loadedModelId = id
    }

    func restoreModelState() {
        let selectedId = userDefaults.string(forKey: "selectedModelId")
        userDefaults.removeObject(forKey: "loadedModelId")

        if let selectedId,
           let model = Constants.ModelRegistry.curatedModels.first(where: { $0.id == selectedId }),
           manifestService.isDownloaded(modelId: selectedId) {
            var updated = model
            updated.isDownloaded = true
            selectedModel = updated
        }

        loadedModelId = nil
    }

    private func reconcileDownloadedModelState() {
        Task {
            var staleModelIds: [String] = []

            for entry in manifestService.getDownloadedModels() {
                guard let model = Constants.ModelRegistry.curatedModels.first(where: { $0.id == entry.id }) else {
                    staleModelIds.append(entry.id)
                    continue
                }

                if !(await downloadService.isModelDownloaded(model)) {
                    staleModelIds.append(entry.id)
                }
            }

            guard !staleModelIds.isEmpty else { return }

            await MainActor.run {
                for modelId in staleModelIds {
                    self.manifestService.removeDownloaded(modelId: modelId)
                    if self.selectedModel?.id == modelId {
                        self.selectModel(nil)
                    }
                    if self.loadedModelId == modelId {
                        self.setLoadedModel(id: nil)
                    }
                }
            }
        }
    }

    func clearModel() {
        selectModel(nil)
        setLoadedModel(id: nil)
    }

    func loadConversations() {
        conversations = conversationService.listAll()
        reconcileActiveConversationForChat()
    }

    private func reconcileActiveConversationForChat() {
        if conversations.isEmpty {
            _ = createNewConversation()
            return
        }
        if activeConversationId == nil {
            activeConversationId = conversations.first?.id
            return
        }
        if !conversations.contains(where: { $0.id == activeConversationId }) {
            activeConversationId = conversations.first?.id
        }
    }

    @discardableResult
    func createNewConversation() -> UUID {
        let conversation = Conversation(modelId: loadedModelId)
        conversationService.save(conversation)
        conversations.insert(conversation, at: 0)
        activeConversationId = conversation.id
        Haptics.impactLight()
        return conversation.id
    }

    func deleteConversation(_ id: UUID) {
        conversationService.delete(id: id)
        conversations.removeAll { $0.id == id }
        if activeConversationId == id {
            activeConversationId = conversations.first?.id
        }
        Haptics.impactMedium()
    }

    func selectConversation(_ id: UUID) {
        activeConversationId = id
        Haptics.selectionChanged()
    }

    func activeConversation() -> Conversation? {
        conversations.first { $0.id == activeConversationId }
    }

    func updateConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations.remove(at: index)
        }
        conversations.insert(conversation, at: 0)
        conversationService.save(conversation)
    }
}
