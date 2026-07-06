import Foundation

@Observable
final class AppState {
    private enum Keys {
        static let selectedModelId = "selectedModelId"
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let pendingStarterModelId = "pendingStarterModelId"
        static let hasSeenWebSearchDisclosure = "hasSeenWebSearchDisclosure"
        static let assistantPersonalizationEnabled = "assistantPersonalizationEnabled"
        static let assistantSystemPrompt = "assistantSystemPrompt"
        static let assistantTemperature = "assistantTemperature"
        static let openKeyboardOnLaunch = "openKeyboardOnLaunch"
    }

    var selectedModel: ModelInfo?
    var isModelLoading: Bool = false
    var loadedModelId: String?
    var modelDownloadSnapshots: [String: ModelDownloadSnapshot] = [:]
    var speechAssetStatus: SpeechAssetStatus = .empty
    var hasCompletedOnboarding: Bool
    var pendingStarterModelId: String?
    var hasSeenWebSearchDisclosure: Bool
    var assistantPersonalizationEnabled: Bool
    var assistantSystemPrompt: String
    var assistantTemperature: Double
    var openKeyboardOnLaunch: Bool
    var voiceSessionInvalidationSeed: Int = 0
    var pendingShortcutRoute: AppShortcutRoute?
    var latestLLMExecutionProfile: LLMExecutionProfile?
    var llmExecutionProfiles: [LLMExecutionProfile] = []
    var llmProfilingSessions: [LLMProfilingSessionRecord] = []
    var llmInferenceCrashReports: [LLMInferenceCrashReport] = []
    var latestLLMBenchmarkResult: LLMBenchmarkResult?

    private static let preferredLatestProfileRunLabels: Set<String> = [
        "Chat Response",
        "Benchmark"
    ]

    let conversationService = ConversationService()
    let inferenceService = InferenceService()
    let downloadService: ModelDownloadService
    let manifestService: ManifestService
    let speechAssetService: SpeechAssetService
    let webSearchService = WebSearchService()
    let toolCallingService: ToolCallingService
    let memoryService = MemorySystem()
    let documentLibraryService = DocumentLibraryService()
    let calendarBriefService = CalendarBriefService()
    let remindersService = RemindersService()
    let timerService = TimerService()
    let contactsService = ContactsService()
    var conversations: [Conversation] = []
    var memories: [UserMemory] = []
    var activeConversationId: UUID?

    private static let curatedModelsByID = Dictionary(
        uniqueKeysWithValues: Constants.ModelRegistry.curatedModels.map { ($0.id, $0) }
    )
    private let userDefaults = UserDefaults.standard
    private var conversationsByID: [UUID: Conversation] = [:]

    init() {
        self.manifestService = ManifestService()
        self.downloadService = ModelDownloadService(manifestService: manifestService)
        self.speechAssetService = SpeechAssetService()
        self.toolCallingService = ToolCallingService(
            webSearchService: webSearchService,
            documentLibraryService: documentLibraryService,
            calendarBriefService: calendarBriefService,
            remindersService: remindersService,
            timerService: timerService,
            contactsService: contactsService
        )
        if let persistedOnboardingState = userDefaults.object(forKey: Keys.hasCompletedOnboarding) as? Bool {
            hasCompletedOnboarding = persistedOnboardingState
        } else {
            hasCompletedOnboarding = Self.hasExistingUserState(userDefaults: userDefaults)
        }
        pendingStarterModelId = userDefaults.string(forKey: Keys.pendingStarterModelId)
        hasSeenWebSearchDisclosure = userDefaults.bool(forKey: Keys.hasSeenWebSearchDisclosure)
        assistantPersonalizationEnabled = userDefaults.bool(forKey: Keys.assistantPersonalizationEnabled)
        assistantSystemPrompt = userDefaults.string(forKey: Keys.assistantSystemPrompt) ?? Constants.Generation.defaultSystemPrompt
        let storedTemperature = userDefaults.object(forKey: Keys.assistantTemperature) as? Double
        assistantTemperature = Self.clampedAssistantTemperature(storedTemperature ?? Double(Constants.Generation.defaultPersonalizationTemperature))
        openKeyboardOnLaunch = userDefaults.bool(forKey: Keys.openKeyboardOnLaunch)
        pendingShortcutRoute = AppShortcutRouteStore.loadPendingRoute(userDefaults: userDefaults)
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
            await self.refreshLLMExecutionProfiles()
        }
    }

    private static func hasExistingUserState(userDefaults: UserDefaults) -> Bool {
        userDefaults.string(forKey: Keys.selectedModelId) != nil
            || !ManifestService().getDownloadedModels().isEmpty
            || !MemorySystem().listAll().isEmpty
            || !ConversationService().listAll().isEmpty
    }

    var effectiveLocale: Locale {
        AppLocalization.effectiveLocale
    }

    var resolvedVoiceLocale: VoiceLocale {
        VoiceLocale.resolve(
            preferredAppLanguageCode: nil,
            effectiveLocale: effectiveLocale
        )
    }

    func setAssistantSystemPrompt(_ prompt: String) {
        assistantSystemPrompt = prompt
        userDefaults.set(prompt, forKey: Keys.assistantSystemPrompt)
    }

    func setAssistantPersonalizationEnabled(_ enabled: Bool) {
        assistantPersonalizationEnabled = enabled
        userDefaults.set(enabled, forKey: Keys.assistantPersonalizationEnabled)
    }

    func setAssistantTemperature(_ temperature: Double) {
        let clamped = Self.clampedAssistantTemperature(temperature)
        assistantTemperature = clamped
        userDefaults.set(clamped, forKey: Keys.assistantTemperature)
    }

    func setOpenKeyboardOnLaunch(_ enabled: Bool) {
        openKeyboardOnLaunch = enabled
        userDefaults.set(enabled, forKey: Keys.openKeyboardOnLaunch)
    }

    var effectiveAssistantSystemPrompt: String {
        guard assistantPersonalizationEnabled else {
            return Constants.Generation.defaultSystemPrompt
        }

        let trimmedPrompt = assistantSystemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedPrompt.isEmpty ? Constants.Generation.defaultSystemPrompt : assistantSystemPrompt
    }

    var effectiveAssistantTemperature: Double {
        assistantPersonalizationEnabled ? assistantTemperature : Double(Constants.Generation.defaultTemperature)
    }

    func resetAssistantGenerationSettings() {
        assistantPersonalizationEnabled = false
        assistantSystemPrompt = Constants.Generation.defaultSystemPrompt
        assistantTemperature = Double(Constants.Generation.defaultPersonalizationTemperature)
        userDefaults.removeObject(forKey: Keys.assistantPersonalizationEnabled)
        userDefaults.removeObject(forKey: Keys.assistantSystemPrompt)
        userDefaults.removeObject(forKey: Keys.assistantTemperature)
    }

    private static func clampedAssistantTemperature(_ temperature: Double) -> Double {
        min(max(temperature, 0.0), 1.0)
    }

    var showsOnboarding: Bool {
        get { !hasCompletedOnboarding }
        set {
            if !newValue {
                markOnboardingCompleted()
            }
        }
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
    func cancelStarterModelDownload() async {
        if let pendingStarterModelId,
           let model = modelInfo(id: pendingStarterModelId) {
            await downloadService.cancelDownload(for: model)
        }
        pendingStarterModelId = nil
        userDefaults.removeObject(forKey: Keys.pendingStarterModelId)
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

    @MainActor
    func refreshLatestLLMExecutionProfile() async {
        await refreshLLMExecutionProfiles()
    }

    @MainActor
    func refreshLLMExecutionProfiles() async {
        let sessions = await inferenceService.executionProfileSessions()
        let profiles = await inferenceService.executionProfileHistory()
        let crashReports = await inferenceService.recoveredInferenceCrashReports()
        llmProfilingSessions = sessions.sorted { $0.startedAt > $1.startedAt }
        llmExecutionProfiles = profiles.sorted { $0.createdAt > $1.createdAt }
        latestLLMExecutionProfile = Self.preferredLatestProfile(from: llmExecutionProfiles)
        llmInferenceCrashReports = crashReports.sorted { $0.recoveredAt > $1.recoveredAt }
    }

    @MainActor
    func recordLLMExecutionProfile(_ profile: LLMExecutionProfile, updateLatest: Bool = true) {
        if let index = llmExecutionProfiles.firstIndex(where: { $0.id == profile.id }) {
            llmExecutionProfiles[index] = profile
        } else {
            llmExecutionProfiles.insert(profile, at: 0)
        }
        llmExecutionProfiles.sort { $0.createdAt > $1.createdAt }
        if updateLatest, Self.shouldPromoteToLatestProfile(profile) {
            latestLLMExecutionProfile = profile
        } else {
            latestLLMExecutionProfile = Self.preferredLatestProfile(from: llmExecutionProfiles)
        }
    }

    @MainActor
    func recordLLMBenchmarkResult(_ result: LLMBenchmarkResult) {
        latestLLMBenchmarkResult = result
        for profile in result.profiles.reversed() {
            recordLLMExecutionProfile(profile, updateLatest: profile.runLabel == "Benchmark")
        }
    }

    @MainActor
    func runLLMBenchmark(
        prompt: String,
        iterations: Int,
        systemPrompt: String = "",
        maxTokens: Int = 256
    ) async throws {
        guard let modelId = loadedModelId,
              let model = selectedModel ?? modelInfo(id: modelId) else {
            throw InferenceError.noModelLoaded
        }
        let result = try await inferenceService.benchmark(
            prompt: prompt,
            iterations: iterations,
            systemPrompt: systemPrompt,
            maxTokens: maxTokens,
            modelName: model.displayName,
            profilingContext: LLMProfilingRunContext(
                model: model,
                maxTokens: maxTokens,
                temperature: Constants.Generation.defaultTemperature,
                topP: Constants.Generation.defaultTopP,
                repetitionPenalty: Constants.Generation.defaultRepetitionPenalty,
                thinkingEnabled: false
            )
        )
        recordLLMBenchmarkResult(result)
    }

    @MainActor
    private static func preferredLatestProfile(from profiles: [LLMExecutionProfile]) -> LLMExecutionProfile? {
        let sorted = profiles.sorted { $0.createdAt > $1.createdAt }
        return sorted.first { preferredLatestProfileRunLabels.contains($0.runLabel) } ?? sorted.first
    }

    @MainActor
    private static func shouldPromoteToLatestProfile(_ profile: LLMExecutionProfile) -> Bool {
        preferredLatestProfileRunLabels.contains(profile.runLabel)
    }

    @MainActor
    func makeLLMProfilingSessionExport(for sessionID: UUID) -> LLMProfilingSessionExport? {
        guard let session = llmProfilingSessions.first(where: { $0.id == sessionID }) else {
            return nil
        }
        return LLMProfilingSessionExport(session: session)
    }

    @MainActor
    func deleteLLMProfilingSession(id: UUID) async {
        await inferenceService.deleteExecutionProfileSession(id: id)
        await refreshLLMExecutionProfiles()
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
        rebuildConversationLookup()
        reconcileActiveConversationForChat()
    }

    private func loadConversationsFromDisk() {
        conversations = conversationService.listAll()
        let hadPersistedConversations = !conversations.isEmpty
        rebuildConversationLookup()
        if hadPersistedConversations {
            createNewConversation(emitHaptics: false)
        } else {
            reconcileActiveConversationForChat()
        }
    }

    nonisolated private static func fetchConversationsInBackground(using conversationService: ConversationService) async -> [Conversation] {
        return await Task.detached(priority: .utility) {
            conversationService.listAll()
        }.value
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
    func createNewConversation(emitHaptics: Bool = true) -> UUID {
        removeEmptyDraftConversations()
        let conversation = Conversation(
            modelId: loadedModelId
        )
        conversations.insert(conversation, at: 0)
        conversationsByID[conversation.id] = conversation
        activeConversationId = conversation.id
        if emitHaptics {
            Haptics.impactLight()
        }
        return conversation.id
    }

    private func removeEmptyDraftConversations(excluding preservedID: UUID? = nil) {
        let emptyDraftIDs = conversations
            .filter { conversation in
                conversation.isEmptyDraft && conversation.id != preservedID
            }
            .map(\.id)
        guard !emptyDraftIDs.isEmpty else { return }

        let emptyDraftIDSet = Set(emptyDraftIDs)
        conversations.removeAll { emptyDraftIDSet.contains($0.id) }
        Task {
            for id in emptyDraftIDs {
                await documentLibraryService.deleteDocuments(for: id)
            }
        }
        for draftID in emptyDraftIDs {
            conversationsByID[draftID] = nil
            conversationService.delete(id: draftID)
        }
    }

    @discardableResult
    func deleteConversation(_ id: UUID) -> UUID? {
        deleteConversations([id])
    }

    @discardableResult
    func deleteConversations(_ ids: Set<UUID>) -> UUID? {
        let existingIDs = Set(conversations.map(\.id))
        let deletedIDs = ids.intersection(existingIDs)
        guard !deletedIDs.isEmpty else { return activeConversationId }

        for id in deletedIDs {
            conversationService.delete(id: id)
        }

        let previousActiveConversationId = activeConversationId
        let remainingConversations = conversations.filter { !deletedIDs.contains($0.id) }

        Task {
            for id in deletedIDs {
                await documentLibraryService.deleteDocuments(for: id)
            }
        }

        if remainingConversations.isEmpty {
            let conversation = Conversation(modelId: loadedModelId)
            conversations = [conversation]
            conversationsByID = [conversation.id: conversation]
            activeConversationId = conversation.id
        } else {
            conversations = remainingConversations
            rebuildConversationLookup()
            if let previousActiveConversationId,
               deletedIDs.contains(previousActiveConversationId) {
                activeConversationId = conversations.first?.id
            }
        }

        Haptics.impactMedium()
        return activeConversationId
    }

    func clearAllConversations() {
        let conversationIDs = conversations.map(\.id)
        conversationService.deleteAll()
        let conversation = Conversation(modelId: loadedModelId)
        conversations = [conversation]
        conversationsByID = [conversation.id: conversation]
        activeConversationId = conversation.id

        Task {
            for id in conversationIDs {
                await documentLibraryService.deleteDocuments(for: id)
            }
        }

        Haptics.notificationSuccess()
    }

    func selectConversation(_ id: UUID) {
        removeEmptyDraftConversations(excluding: id)
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

    func modelInfo(id: String?) -> ModelInfo? {
        guard let id else { return nil }
        return Self.curatedModelsByID[id]
    }

    @discardableResult
    func saveMemory(
        content: String,
        status: UserMemoryStatus,
        captureType: UserMemoryCaptureType,
        category: String? = nil,
        sourceConversationId: UUID? = nil,
        sourceMessageId: UUID? = nil,
        sourceLanguageCode: String? = nil,
        sourceQuote: String? = nil,
        factRelation: String? = nil,
        factValue: String? = nil,
        confidence: Double? = nil
    ) -> UserMemory? {
        let memory = memoryService.upsert(
            content: content,
            status: status,
            captureType: captureType,
            category: category,
            sourceConversationId: sourceConversationId,
            sourceMessageId: sourceMessageId,
            sourceLanguageCode: sourceLanguageCode,
            sourceQuote: sourceQuote,
            factRelation: factRelation,
            factValue: factValue,
            confidence: confidence
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
        maxCharacters: Int = Constants.Memory.maxContextCharacters
    ) async -> MemoryRetrievalResult {
        let result = await memoryService.retrieveMemoryResultAsync(
            for: query,
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
        guard !conversation.isEmptyDraft else {
            conversationService.delete(id: conversation.id)
            return
        }
        conversationService.save(conversation)
    }

    private func rebuildConversationLookup() {
        conversationsByID = Dictionary(uniqueKeysWithValues: conversations.map { ($0.id, $0) })
    }
}

private extension Conversation {
    var isEmptyDraft: Bool {
        messages.isEmpty && documents.isEmpty
    }
}
