import Foundation

@Observable
final class AppState {
    var selectedModel: ModelInfo?
    var isModelLoading: Bool = false
    var loadedModelId: String?

    let conversationService = ConversationService()
    let inferenceService = InferenceService()
    let downloadService = ModelDownloadService()
    let manifestService = ManifestService()
    let personaService = PersonaService()
    let documentLibraryService = DocumentLibraryService()
    var conversations: [Conversation] = []
    var personas: [Persona] = []
    var activeConversationId: UUID?
    var preferredAppLanguageCode: String?

    private let userDefaults = UserDefaults.standard

    init() {
        preferredAppLanguageCode = userDefaults.string(forKey: AppLocalization.preferredLanguageUserDefaultsKey)
        loadPersonas()
        restoreModelState()
        reconcileDownloadedModelState()
    }

    var effectiveLocale: Locale {
        AppLocalization.effectiveLocale
    }

    func setPreferredAppLanguage(_ code: String?) {
        if let code, !code.isEmpty {
            userDefaults.set(code, forKey: AppLocalization.preferredLanguageUserDefaultsKey)
        } else {
            userDefaults.removeObject(forKey: AppLocalization.preferredLanguageUserDefaultsKey)
        }
        preferredAppLanguageCode = code
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
        migrateConversationsWithoutPersona()
        reconcileActiveConversationForChat()
    }

    func loadPersonas() {
        personas = personaService.listAll()
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
        let conversation = Conversation(
            modelId: loadedModelId,
            personaId: defaultPersona().id
        )
        conversationService.save(conversation)
        conversations.insert(conversation, at: 0)
        activeConversationId = conversation.id
        Haptics.impactLight()
        return conversation.id
    }

    func deleteConversation(_ id: UUID) {
        conversationService.delete(id: id)
        conversations.removeAll { $0.id == id }
        Task {
            await documentLibraryService.deleteDocuments(for: id)
        }
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

    func persona(id: String?) -> Persona? {
        guard let id else { return nil }
        return personas.first { $0.id == id }
    }

    func defaultPersona() -> Persona {
        if let explicitDefault = personas.first(where: { $0.id == Persona.defaultID }) {
            return explicitDefault
        }
        if let firstPersona = personas.first {
            return firstPersona
        }
        let seeded = Persona.starterPersonas()
        return seeded.first ?? Persona(
            id: Persona.defaultID,
            name: "General Assistant",
            summary: "a clear everyday helper",
            goal: "Help with common questions and practical tasks.",
            tone: .balanced,
            suggestedOpening: "Help me think this through.",
            defaultModelId: nil,
            temperature: 0.7,
            topP: 1.0,
            repetitionPenalty: 1.0,
            symbolName: "sparkles",
            isBuiltIn: true
        )
    }

    func savePersona(_ persona: Persona) {
        personaService.save(persona)
        loadPersonas()
    }

    func deletePersona(_ id: String) {
        guard let persona = persona(id: id), !persona.isBuiltIn else { return }
        personaService.delete(id: id)

        let fallbackPersonaID = defaultPersona().id
        for index in conversations.indices where conversations[index].personaId == id {
            conversations[index].personaId = fallbackPersonaID
            conversationService.save(conversations[index])
        }

        loadPersonas()
    }

    func updateConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations.remove(at: index)
        }
        conversations.insert(conversation, at: 0)
        conversationService.save(conversation)
    }

    private func migrateConversationsWithoutPersona() {
        let fallbackPersonaID = defaultPersona().id
        for index in conversations.indices where conversations[index].personaId == nil {
            conversations[index].personaId = fallbackPersonaID
            conversationService.save(conversations[index])
        }
    }
}
