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
        Task { @MainActor [weak self] in
            guard let self else { return }
            _ = await self.reconcileModelCatalogState()
        }
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

    @MainActor
    @discardableResult
    func reconcileModelCatalogState() async -> [ModelInfo] {
        var downloadedById: [String: ModelInfo] = [:]

        for model in Constants.ModelRegistry.curatedModels {
            let isDownloaded = await downloadService.isModelDownloaded(model)
            guard isDownloaded else { continue }

            var updated = model
            updated.isDownloaded = true
            updated.localURL = await downloadService.localURL(for: model)
            downloadedById[model.id] = updated

            if !manifestService.isDownloaded(modelId: model.id) {
                let sizeOnDisk = await downloadService.sizeOfModel(model)
                manifestService.addDownloaded(
                    modelId: model.id,
                    displayName: model.displayName,
                    huggingFaceId: model.huggingFaceId,
                    localPath: model.id,
                    sizeOnDiskBytes: sizeOnDisk
                )
            }
        }

        let staleModelIds = Set(
            manifestService.getDownloadedModels()
                .map(\.id)
                .filter { downloadedById[$0] == nil }
        )

        for modelId in staleModelIds {
            manifestService.removeDownloaded(modelId: modelId)
            if selectedModel?.id == modelId {
                selectModel(nil)
            }
            if loadedModelId == modelId {
                setLoadedModel(id: nil)
            }
        }

        if let selectedId = selectedModel?.id,
           let updatedSelectedModel = downloadedById[selectedId] {
            selectedModel = updatedSelectedModel
        } else if let selectedId = selectedModel?.id,
                  downloadedById[selectedId] == nil {
            selectModel(nil)
        }

        if let loadedModelId,
           downloadedById[loadedModelId] == nil {
            setLoadedModel(id: nil)
        }

        return Constants.ModelRegistry.curatedModels.compactMap { downloadedById[$0.id] }
    }

    func clearModel() {
        selectModel(nil)
        setLoadedModel(id: nil)
    }

    @MainActor
    func clearAllDownloadedModels() async {
        let downloadedEntries = manifestService.getDownloadedModels()
        let idsToRemove = Set(downloadedEntries.map(\.id))

        await inferenceService.unload()
        clearModel()

        for entry in downloadedEntries {
            try? await downloadService.deleteModel(modelId: entry.id, huggingFaceId: entry.huggingFaceId)
        }
        manifestService.removeDownloaded(modelIds: idsToRemove)
    }

    @MainActor
    func loadConversations() async {
        let loaded = await fetchConversationsInBackground()
        conversations = loaded
        migrateConversationsWithoutPersona()
        reconcileActiveConversationForChat()
    }

    nonisolated private func fetchConversationsInBackground() async -> [Conversation] {
        return await Task.detached {
            self.conversationService.listAll()
        }.value
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
        if conversations.isEmpty {
            _ = createNewConversation()
        } else if activeConversationId == id {
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
