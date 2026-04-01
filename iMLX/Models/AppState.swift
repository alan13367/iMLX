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
        if let id {
            userDefaults.set(id, forKey: "loadedModelId")
        } else {
            userDefaults.removeObject(forKey: "loadedModelId")
        }
    }

    func restoreModelState() {
        let selectedId = userDefaults.string(forKey: "selectedModelId")
        let loadedId = userDefaults.string(forKey: "loadedModelId")

        if let selectedId,
           let model = Constants.ModelRegistry.curatedModels.first(where: { $0.id == selectedId }),
           manifestService.isDownloaded(modelId: selectedId) {
            var updated = model
            updated.isDownloaded = true
            selectedModel = updated
        }

        loadedModelId = loadedId
    }

    func clearModel() {
        selectedModel = nil
        loadedModelId = nil
    }

    func loadConversations() {
        conversations = conversationService.listAll()
        if activeConversationId == nil, let first = conversations.first {
            activeConversationId = first.id
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
            conversations[index] = conversation
        }
        conversationService.save(conversation)
    }
}
