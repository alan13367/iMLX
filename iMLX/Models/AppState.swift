import Foundation

@Observable
final class AppState {
    private enum Keys {
        static let selectedModelId = "selectedModelId"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let pendingStarterModelId = "pendingStarterModelId"
        static let hasSeenWebSearchDisclosure = "hasSeenWebSearchDisclosure"
    }

    var selectedModel: ModelInfo?
    var isModelLoading: Bool = false
    var loadedModelId: String?
    var modelDownloadSnapshots: [String: ModelDownloadSnapshot] = [:]
    var speechAssetStatus: SpeechAssetStatus = .empty
    var hasCompletedOnboarding: Bool
    var pendingStarterModelId: String?
    var hasSeenWebSearchDisclosure: Bool
    var voiceSessionInvalidationSeed: Int = 0

    let conversationService = ConversationService()
    let inferenceService = InferenceService()
    let downloadService: ModelDownloadService
    let manifestService: ManifestService
    let speechAssetService: SpeechAssetService
    let webSearchService = WebSearchService()
    let personaService = PersonaService()
    let memoryService = MemoryService()
    let documentLibraryService = DocumentLibraryService()
    var conversations: [Conversation] = []
    var personas: [Persona] = []
    var memories: [UserMemory] = []
    var activeConversationId: UUID?
    var preferredAppLanguageCode: String?

    private let userDefaults = UserDefaults.standard

    init() {
        self.manifestService = ManifestService()
        self.downloadService = ModelDownloadService(manifestService: manifestService)
        self.speechAssetService = SpeechAssetService()
        preferredAppLanguageCode = userDefaults.string(forKey: AppLocalization.preferredLanguageUserDefaultsKey)
        if let persistedOnboardingState = userDefaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool {
            hasCompletedOnboarding = persistedOnboardingState
        } else {
            hasCompletedOnboarding = Self.hasExistingUserState(userDefaults: userDefaults)
        }
        pendingStarterModelId = userDefaults.string(forKey: Keys.pendingStarterModelId)
        hasSeenWebSearchDisclosure = userDefaults.bool(forKey: Keys.hasSeenWebSearchDisclosure)
        loadPersonas()
        loadMemories()
        loadConversationsFromDisk()
        restoreModelState()

        Task { [weak self] in
            guard let self else { return }
            await self.downloadService.setSnapshotObserver { [weak self] snapshots in
                guard let self else { return }
                await self.handleDownloadSnapshots(snapshots)
            }
            await self.speechAssetService.setStatusObserver { [weak self] status in
                guard let self else { return }
                await MainActor.run {
                    self.speechAssetStatus = status
                }
            }
            await self.downloadService.restorePendingDownloads()
            let speechStatus = await self.speechAssetService.status()
            await MainActor.run {
                self.speechAssetStatus = speechStatus
            }
            _ = await self.reconcileModelCatalogState()
        }
    }

    private static func hasExistingUserState(userDefaults: UserDefaults) -> Bool {
        userDefaults.string(forKey: Keys.selectedModelId) != nil
            || userDefaults.string(forKey: AppLocalization.preferredLanguageUserDefaultsKey) != nil
            || !ManifestService().getDownloadedModels().isEmpty
            || !MemoryService().listAll().isEmpty
            || !ConversationService().listAll().isEmpty
    }

    var effectiveLocale: Locale {
        AppLocalization.effectiveLocale
    }

    var resolvedVoiceLocale: VoiceLocale {
        VoiceLocale.resolve(
            preferredAppLanguageCode: preferredAppLanguageCode,
            effectiveLocale: effectiveLocale
        )
    }

    func setPreferredAppLanguage(_ code: String?) {
        if let code, !code.isEmpty {
            userDefaults.set(code, forKey: AppLocalization.preferredLanguageUserDefaultsKey)
        } else {
            userDefaults.removeObject(forKey: AppLocalization.preferredLanguageUserDefaultsKey)
        }
        preferredAppLanguageCode = code
        voiceSessionInvalidationSeed &+= 1
    }

    func markOnboardingCompleted() {
        hasCompletedOnboarding = true
        userDefaults.set(true, forKey: Keys.hasCompletedOnboarding)
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
        userDefaults.set(false, forKey: Keys.hasCompletedOnboarding)
    }

    func markWebSearchDisclosureSeen() {
        hasSeenWebSearchDisclosure = true
        userDefaults.set(true, forKey: Keys.hasSeenWebSearchDisclosure)
    }

    func recommendedStarterModels(deviceCapabilityService: DeviceCapabilityService = DeviceCapabilityService()) -> [ModelInfo] {
        let modelIDs: [String]
        switch deviceCapabilityService.tier {
        case .tier8GB:
            modelIDs = ["qwen3-1.7b-4bit", "lfm2.5-350m-4bit", "qwen3.5-2b-4bit"]
        case .tier12GB, .tier16GB, .tier24GB:
            modelIDs = ["qwen3-4b-4bit", "lfm2.5-350m-4bit", "qwen3.5-4b-4bit"]
        }

        return modelIDs.compactMap { id in
            Constants.ModelRegistry.curatedModels.first(where: { $0.id == id })
        }
    }

    @MainActor
    func startStarterModelDownload(_ model: ModelInfo) async throws {
        pendingStarterModelId = model.id
        userDefaults.set(model.id, forKey: Keys.pendingStarterModelId)
        try await downloadService.startDownload(for: model)
    }

    @MainActor
    func clearSpeechAssets() async {
        await speechAssetService.clearAllAssets()
        speechAssetStatus = await speechAssetService.status()
    }

    func selectModel(_ model: ModelInfo?) {
        selectedModel = model
        if let model {
            userDefaults.set(model.id, forKey: Keys.selectedModelId)
        } else {
            userDefaults.removeObject(forKey: Keys.selectedModelId)
        }
    }

    func setLoadedModel(id: String?) {
        loadedModelId = id
    }

    func restoreModelState() {
        let selectedId = userDefaults.string(forKey: Keys.selectedModelId)
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

    func handleBackgroundDownloadEvents() async {
        await downloadService.restorePendingDownloads()
        _ = await reconcileModelCatalogState()
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

    private func handleDownloadSnapshots(_ snapshots: [String: ModelDownloadSnapshot]) async {
        let previousModelIDs = Set(modelDownloadSnapshots.keys)
        modelDownloadSnapshots = snapshots

        let removedModelIDs = previousModelIDs.subtracting(snapshots.keys)
        if !removedModelIDs.isEmpty {
            _ = await reconcileModelCatalogState()
        }

        if let pendingStarterModelId,
           snapshots[pendingStarterModelId] == nil,
           manifestService.isDownloaded(modelId: pendingStarterModelId) {
            if selectedModel == nil || selectedModel?.id == pendingStarterModelId {
                if let model = Constants.ModelRegistry.curatedModels.first(where: { $0.id == pendingStarterModelId }) {
                    var updatedModel = model
                    updatedModel.isDownloaded = true
                    updatedModel.localURL = await downloadService.localURL(for: model)
                    selectModel(updatedModel)
                }
            }
            self.pendingStarterModelId = nil
            userDefaults.removeObject(forKey: Keys.pendingStarterModelId)
        }
    }

    @MainActor
    func loadConversations() async {
        let loaded = await Self.fetchConversationsInBackground(using: conversationService)
        conversations = loaded
        migrateConversationsWithoutPersona()
        reconcileActiveConversationForChat()
    }

    private func loadConversationsFromDisk() {
        conversations = conversationService.listAll()
        migrateConversationsWithoutPersona()
        reconcileActiveConversationForChat()
    }

    nonisolated private static func fetchConversationsInBackground(using conversationService: ConversationService) async -> [Conversation] {
        return await Task.detached(priority: .utility) {
            conversationService.listAll()
        }.value
    }

    func loadPersonas() {
        personas = personaService.listAll()
    }

    func loadMemories() {
        memories = memoryService.listAll()
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

    @discardableResult
    func saveMemory(
        content: String,
        status: UserMemoryStatus,
        captureType: UserMemoryCaptureType,
        personaId: String? = nil,
        category: String? = nil,
        sourceConversationId: UUID? = nil,
        sourceMessageId: UUID? = nil
    ) -> UserMemory? {
        let memory = memoryService.upsert(
            content: content,
            status: status,
            captureType: captureType,
            personaId: personaId,
            category: category,
            sourceConversationId: sourceConversationId,
            sourceMessageId: sourceMessageId
        )
        loadMemories()
        return memory
    }

    func updateMemory(_ memory: UserMemory) {
        _ = memoryService.update(memory)
        loadMemories()
    }

    func acceptMemory(id: UUID) {
        _ = memoryService.setStatus(id: id, status: .active)
        loadMemories()
    }

    func rejectMemory(id: UUID) {
        _ = memoryService.setStatus(id: id, status: .archived)
        loadMemories()
    }

    func deleteMemory(id: UUID) {
        memoryService.delete(id: id)
        loadMemories()
    }

    func clearAllMemories() {
        memoryService.clearAll()
        loadMemories()
    }

    @discardableResult
    func forgetMemory(matching query: String) -> Int {
        let count = memoryService.archiveMatching(query)
        loadMemories()
        return count
    }

    func retrieveMemoryContext(
        for query: String,
        personaId: String?,
        maxCharacters: Int = Constants.Memory.maxContextCharacters
    ) -> MemoryRetrievalResult {
        let selectedMemories = memoryService.retrieveActiveMemories(
            for: query,
            personaId: personaId,
            limit: Constants.Memory.maxRetrievedMemories,
            maxCharacters: maxCharacters
        )
        guard !selectedMemories.isEmpty else {
            return MemoryRetrievalResult(contextBlock: "", memories: [])
        }

        memoryService.markUsed(ids: selectedMemories.map(\.id))
        loadMemories()

        let contextLines = selectedMemories.map { "- \($0.content)" }
        let contextBlock = """
        Relevant persistent user memories:
        These memories were retrieved as potentially relevant. Use only the ones that directly help the current request, ignore any that do not fit, and do not mention stored memories unless the user asks.

        \(contextLines.joined(separator: "\n"))
        """

        return MemoryRetrievalResult(contextBlock: contextBlock, memories: selectedMemories)
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
