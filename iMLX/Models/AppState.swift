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
    var pendingShortcutRoute: AppShortcutRoute?

    let conversationService = ConversationService()
    let inferenceService = InferenceService()
    let downloadService: ModelDownloadService
    let manifestService: ManifestService
    let speechAssetService: SpeechAssetService
    let webSearchService = WebSearchService()
    let toolCallingService: ToolCallingService
    let personaService = PersonaService()
    let memoryService = MemorySystem()
    let documentLibraryService = DocumentLibraryService()
    var conversations: [Conversation] = []
    var personas: [Persona] = []
    var memories: [UserMemory] = []
    var activeConversationId: UUID?
    var preferredAppLanguageCode: String?

    private static let curatedModelsByID = Dictionary(
        uniqueKeysWithValues: Constants.ModelRegistry.curatedModels.map { ($0.id, $0) }
    )
    private let userDefaults = UserDefaults.standard
    private var conversationsByID: [UUID: Conversation] = [:]
    private var personasByID: [String: Persona] = [:]

    init() {
        self.manifestService = ManifestService()
        self.downloadService = ModelDownloadService(manifestService: manifestService)
        self.speechAssetService = SpeechAssetService()
        self.toolCallingService = ToolCallingService(webSearchService: webSearchService)
        preferredAppLanguageCode = userDefaults.string(forKey: AppLocalization.preferredLanguageUserDefaultsKey)
        if let persistedOnboardingState = userDefaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool {
            hasCompletedOnboarding = persistedOnboardingState
        } else {
            hasCompletedOnboarding = Self.hasExistingUserState(userDefaults: userDefaults)
        }
        pendingStarterModelId = userDefaults.string(forKey: Keys.pendingStarterModelId)
        hasSeenWebSearchDisclosure = userDefaults.bool(forKey: Keys.hasSeenWebSearchDisclosure)
        pendingShortcutRoute = AppShortcutRouteStore.loadPendingRoute(userDefaults: userDefaults)
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
            || !MemorySystem().listAll().isEmpty
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

    func refreshPendingShortcutRoute() {
        pendingShortcutRoute = AppShortcutRouteStore.loadPendingRoute(userDefaults: userDefaults)
    }

    func clearPendingShortcutRoute() {
        AppShortcutRouteStore.clearPendingRoute(userDefaults: userDefaults)
        pendingShortcutRoute = nil
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
            modelInfo(id: id)
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
           let model = modelInfo(id: selectedId),
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
                if let model = modelInfo(id: pendingStarterModelId) {
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
        rebuildConversationLookup()
        reconcileActiveConversationForChat()
    }

    private func loadConversationsFromDisk() {
        conversations = conversationService.listAll()
        migrateConversationsWithoutPersona()
        rebuildConversationLookup()
        reconcileActiveConversationForChat()
    }

    nonisolated private static func fetchConversationsInBackground(using conversationService: ConversationService) async -> [Conversation] {
        return await Task.detached(priority: .utility) {
            conversationService.listAll()
        }.value
    }

    func loadPersonas() {
        personas = personaService.listAll()
        rebuildPersonaLookup()
    }

    func loadMemories() {
        memories = memoryService.listAll()
    }

    @MainActor
    func loadMemoriesAsync() async {
        memories = await memoryService.listAllAsync()
    }

    func memoryDetail(id: UUID) -> MemoryDetail? {
        memoryService.memoryDetail(id: id)
    }

    func isMemoryRelationBlocked(_ relation: String?) -> Bool {
        memoryService.isRelationBlocked(relation)
    }

    func canBlockMemoryRelation(_ relation: String?) -> Bool {
        memoryService.canBlockRelation(relation)
    }

    func setMemoryRelationBlocked(_ relation: String?, blocked: Bool) {
        guard let relation else { return }
        if blocked {
            memoryService.blockRelation(relation)
        } else {
            memoryService.unblockRelation(relation)
        }
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
        if conversation(id: activeConversationId) == nil {
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
        conversationsByID[conversation.id] = conversation
        activeConversationId = conversation.id
        Haptics.impactLight()
        return conversation.id
    }

    func deleteConversation(_ id: UUID) {
        conversationService.delete(id: id)
        conversations.removeAll { $0.id == id }
        conversationsByID[id] = nil
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
        conversation(id: activeConversationId)
    }

    func conversation(id: UUID?) -> Conversation? {
        guard let id else { return nil }
        return conversationsByID[id]
    }

    func persona(id: String?) -> Persona? {
        guard let id else { return nil }
        return personasByID[id]
    }

    func modelInfo(id: String?) -> ModelInfo? {
        guard let id else { return nil }
        return Self.curatedModelsByID[id]
    }

    func defaultPersona() -> Persona {
        if let explicitDefault = personasByID[Persona.defaultID] {
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
        rebuildConversationLookup()

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
        sourceMessageId: UUID? = nil,
        sourceLanguageCode: String? = nil,
        sourceQuote: String? = nil,
        factRelation: String? = nil,
        factValue: String? = nil
    ) -> UserMemory? {
        let memory = memoryService.upsert(
            content: content,
            status: status,
            captureType: captureType,
            personaId: personaId,
            category: category,
            sourceConversationId: sourceConversationId,
            sourceMessageId: sourceMessageId,
            sourceLanguageCode: sourceLanguageCode,
            sourceQuote: sourceQuote,
            factRelation: factRelation,
            factValue: factValue
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
    ) async -> MemoryRetrievalResult {
        let result = await memoryService.retrieveMemoryResultAsync(
            for: query,
            personaId: personaId,
            limit: Constants.Memory.maxRetrievedMemories,
            maxCharacters: maxCharacters
        )
        guard !result.memories.isEmpty else {
            return MemoryRetrievalResult(contextBlock: "", memories: [], explanations: [], trace: nil)
        }
        return result
    }

    func updateConversation(_ conversation: Conversation) {
        if let index = conversations.firstIndex(where: { $0.id == conversation.id }) {
            conversations.remove(at: index)
        }
        conversations.insert(conversation, at: 0)
        conversationsByID[conversation.id] = conversation
        conversationService.save(conversation)
    }

    private func migrateConversationsWithoutPersona() {
        let fallbackPersonaID = defaultPersona().id
        for index in conversations.indices where conversations[index].personaId == nil {
            conversations[index].personaId = fallbackPersonaID
            conversationService.save(conversations[index])
        }
    }

    private func rebuildConversationLookup() {
        conversationsByID = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
    }

    private func rebuildPersonaLookup() {
        personasByID = Dictionary(uniqueKeysWithValues: personas.map { ($0.id, $0) })
    }
}
