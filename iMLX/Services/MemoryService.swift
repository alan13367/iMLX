import Foundation

nonisolated final class MemorySystem: @unchecked Sendable {
    private enum Keys {
        static let blockedRelations = "memory.blockedRelations"
        static let didResetMemoryStorage = "memory.didResetStorage.v3"
    }

    private let fileManager: FileManager
    private let memoriesDirectory: URL
    private let memoriesURL: URL
    private let store: MemoryStore
    private let userDefaults: UserDefaults

    lazy var diagnosticsService = MemoryDiagnosticsService(system: self)
    lazy var ingestionService = MemoryIngestionService(system: self, store: store, diagnosticsService: diagnosticsService)
    lazy var retrievalService = MemoryRetrievalService(system: self, store: store, diagnosticsService: diagnosticsService)

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        memoriesDirectory: URL? = nil,
        resetStorageIfNeeded: Bool = true
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let resolvedDirectory = memoriesDirectory
            ?? appSupport.appendingPathComponent(Constants.Storage.memoriesDirectory, isDirectory: true)
        self.memoriesDirectory = resolvedDirectory
        memoriesURL = resolvedDirectory.appendingPathComponent(Constants.Storage.memoriesFilename)
        if resetStorageIfNeeded {
            Self.resetMemoryStorageIfNeeded(
                fileManager: fileManager,
                userDefaults: userDefaults,
                memoriesDirectory: resolvedDirectory
            )
        }
        try? fileManager.createDirectory(at: resolvedDirectory, withIntermediateDirectories: true)
        let dbURL = resolvedDirectory.appendingPathComponent("memories.sqlite")
        store = MemoryStore(databaseURL: dbURL, fileManager: fileManager)
    }

    func listAll() -> [UserMemory] {
        blocking { [self] in await self.store.listSummaries() }
    }

    func listAllAsync() async -> [UserMemory] {
        await store.listSummaries()
    }

    func memoryDetail(id: UUID) -> MemoryDetail? {
        let blockedRelations = blockedRelationSet()
        return blocking { [self] in await self.store.detail(for: id, blockedRelations: blockedRelations) }
    }

    func retrieveMemoryResultAsync(
        for query: String,
        limit: Int,
        maxCharacters: Int
    ) async -> MemoryRetrievalResult {
        await retrievalService.retrieve(
            for: query,
            limit: limit,
            maxCharacters: maxCharacters
        )
    }

    func upsert(
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
        blocking { [self] in
            await self.ingestionService.upsert(
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
        }
    }

    func update(_ memory: UserMemory) -> UserMemory {
        blocking { [self] in
            await self.ingestionService.update(memory)
        }
    }

    func setStatus(id: UUID, status: UserMemoryStatus) -> UserMemory? {
        let eventKind: MemoryEventKind
        switch status {
        case .active:
            eventKind = .accepted
        case .pending:
            eventKind = .updated
        case .archived:
            eventKind = .rejected
        }
        return blocking { [self] in await self.store.setStatus(id: id, status: status, eventKind: eventKind) }
    }

    func delete(id: UUID) {
        blockingVoid { [self] in await self.store.delete(id: id) }
    }

    func clearAll() {
        blockingVoid { [self] in await self.store.clearAll() }
    }

    func pendingCount() -> Int {
        blocking { [self] in await self.store.pendingCount() }
    }

    func blockRelation(_ relation: String) {
        var blocked = blockedRelationSet()
        blocked.insert(relation)
        userDefaults.set(Array(blocked).sorted(), forKey: Keys.blockedRelations)
    }

    func unblockRelation(_ relation: String) {
        var blocked = blockedRelationSet()
        blocked.remove(relation)
        userDefaults.set(Array(blocked).sorted(), forKey: Keys.blockedRelations)
    }

    func isRelationBlocked(_ relation: String?) -> Bool {
        guard let relation else { return false }
        return blockedRelationSet().contains(relation)
    }

    func canBlockRelation(_ relation: String?) -> Bool {
        guard let relation = MemoryRelation(externalValue: relation) else { return false }
        switch relation {
        case .name, .pronouns, .residence, .timezone, .likes, .dislikes, .goal, .project, .constraint, .allergy, .diet, .occupation, .language:
            return true
        case .employer, .education, .identity, .general:
            return false
        }
    }

    nonisolated func blockedRelationSet() -> Set<String> {
        Set(userDefaults.stringArray(forKey: Keys.blockedRelations) ?? [])
    }

    nonisolated func searchIndex(for memories: [UserMemory]) -> MemoryVaultIndex {
        MemoryVaultIndex(memories: memories)
    }

    nonisolated func blocking<T>(_ operation: @escaping @Sendable () async -> T) -> T {
        let semaphore = DispatchSemaphore(value: 0)
        var result: T?
        Task.detached(priority: .userInitiated) {
            result = await operation()
            semaphore.signal()
        }
        semaphore.wait()
        return result!
    }

    nonisolated func blockingVoid(_ operation: @escaping @Sendable () async -> Void) {
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached(priority: .userInitiated) {
            await operation()
            semaphore.signal()
        }
        semaphore.wait()
    }

    private static func resetMemoryStorageIfNeeded(
        fileManager: FileManager,
        userDefaults: UserDefaults,
        memoriesDirectory: URL
    ) {
        guard !userDefaults.bool(forKey: Keys.didResetMemoryStorage) else { return }
        if fileManager.fileExists(atPath: memoriesDirectory.path) {
            try? fileManager.removeItem(at: memoriesDirectory)
        }
        userDefaults.set(true, forKey: Keys.didResetMemoryStorage)
    }
}

typealias MemoryService = MemorySystem

nonisolated final class MemoryDiagnosticsService: @unchecked Sendable {
    unowned let system: MemorySystem

    init(system: MemorySystem) {
        self.system = system
    }

    func explanation(
        memoryId: UUID,
        kind: MemoryRetrievalExplanationKind,
        score: Double,
        detail: String
    ) -> MemoryRetrievalExplanation {
        MemoryRetrievalExplanation(
            id: UUID(),
            memoryId: memoryId,
            kind: kind,
            message: detail,
            score: max(0, min(score, 1))
        )
    }

    func trace(
        candidateCount: Int,
        selectedMemoryIDs: [UUID],
        scoreBreakdown: [UUID: [String: Double]]
    ) -> MemoryRetrievalTrace {
        MemoryRetrievalTrace(
            candidateCount: candidateCount,
            selectedMemoryIDs: selectedMemoryIDs,
            scoreBreakdown: scoreBreakdown
        )
    }
}

nonisolated final class MemoryIngestionService: @unchecked Sendable {
    unowned let system: MemorySystem
    let store: MemoryStore
    let diagnosticsService: MemoryDiagnosticsService

    init(system: MemorySystem, store: MemoryStore, diagnosticsService: MemoryDiagnosticsService) {
        self.system = system
        self.store = store
        self.diagnosticsService = diagnosticsService
    }

    func upsert(
        content: String,
        status: UserMemoryStatus,
        captureType: UserMemoryCaptureType,
        category: String?,
        sourceConversationId: UUID?,
        sourceMessageId: UUID?,
        sourceLanguageCode: String?,
        sourceQuote: String?,
        factRelation: String?,
        factValue: String?,
        confidence: Double?
    ) async -> UserMemory? {
        let normalizedContent = system.normalizedStoredMemoryContent(content)
        guard !normalizedContent.isEmpty else { return nil }
        guard captureType != .inferred || !system.isLowValueInferredMemory(normalizedContent) else { return nil }

        let normalizedSourceQuote = system.normalizedMetadataValue(sourceQuote, maxLength: 320) ?? normalizedContent
        let normalizedSourceLanguageCode = system.normalizedLanguageCode(sourceLanguageCode)
            ?? system.detectedLanguageCode(in: normalizedSourceQuote)
        let normalizedFactRelation = MemoryFactParser.normalizedRelationRawValue(factRelation)
        let normalizedFactValue = system.normalizedMetadataValue(factValue, maxLength: 180)
        let normalizedConfidence = confidence.map { min(max($0, 0), 1) }

        if system.isRelationBlocked(normalizedFactRelation) {
            return nil
        }

        let signature = MemoryFactParser.signature(relation: normalizedFactRelation, value: normalizedFactValue)
            ?? MemoryFactParser.signature(for: normalizedContent)
        let now = Date()
        let candidates = await store.candidateSummaries(
            for: normalizedContent,
            signature: signature,
            statuses: [.active, .pending, .archived],
            mode: .conflict
        )

        if let signature, signature.isRetraction {
            let archiveIDs = conflictingIDs(
                matching: signature,
                in: candidates
            )
            await store.archive(ids: archiveIDs, supersededBy: nil, reason: .forgotten, at: now)
            return nil
        }

        let index = system.searchIndex(for: candidates)
        if let duplicateIndex = system.duplicateIndex(for: normalizedContent, signature: signature, in: candidates, index: index) {
            var duplicate = candidates[duplicateIndex]
            if duplicate.status == .archived || (duplicate.status == .pending && status == .active) {
                duplicate.status = status
            }
            duplicate.content = normalizedContent
            duplicate.personaId = nil
            duplicate.category = duplicate.category ?? category
            duplicate.updatedAt = now
            duplicate.vector = duplicate.vector ?? system.embedding(for: normalizedContent)
            duplicate.sourceLanguageCode = duplicate.sourceLanguageCode ?? normalizedSourceLanguageCode
            duplicate.sourceQuote = duplicate.sourceQuote ?? normalizedSourceQuote
            duplicate.factRelation = duplicate.factRelation ?? normalizedFactRelation
            duplicate.factValue = duplicate.factValue ?? normalizedFactValue

            let updated = await store.updateExistingMemory(
                id: duplicate.id,
                with: persistedInput(
                    id: duplicate.id,
                    content: duplicate.content,
                    status: duplicate.status,
                    captureType: duplicate.captureType,
                    category: duplicate.category,
                    sourceConversationId: sourceConversationId,
                    sourceMessageId: sourceMessageId,
                    sourceLanguageCode: normalizedSourceLanguageCode,
                    sourceQuote: normalizedSourceQuote,
                    relation: duplicate.factRelation,
                    valueDisplay: duplicate.factValue,
                    createdAt: duplicate.createdAt,
                    updatedAt: now,
                    usageCount: duplicate.usageCount,
                    vector: duplicate.vector,
                    confidence: duplicate.captureType == .explicit ? 1.0 : (normalizedConfidence ?? 0.82)
                ),
                eventKind: duplicate.status == .archived ? .reactivated : .updated
            )
            return updated
        }

        let archiveIDs = signature.map { conflictingIDs(matching: $0, in: candidates) } ?? []
        let memoryID = UUID()
        return await store.createMemory(
            persistedInput(
                id: memoryID,
                content: normalizedContent,
                status: status,
                captureType: captureType,
                category: category,
                sourceConversationId: sourceConversationId,
                sourceMessageId: sourceMessageId,
                sourceLanguageCode: normalizedSourceLanguageCode,
                sourceQuote: normalizedSourceQuote,
                relation: normalizedFactRelation,
                valueDisplay: normalizedFactValue,
                createdAt: now,
                updatedAt: now,
                usageCount: 0,
                vector: system.embedding(for: normalizedContent),
                confidence: captureType == .explicit ? 1.0 : (normalizedConfidence ?? 0.78)
            ),
            archivedIDs: archiveIDs,
            archiveReason: .archived
        )
    }

    func update(_ memory: UserMemory) async -> UserMemory {
        var updated = memory
        updated.content = system.normalizedStoredMemoryContent(memory.content)
        updated.sourceLanguageCode = system.normalizedLanguageCode(memory.sourceLanguageCode)
        updated.sourceQuote = system.normalizedMetadataValue(memory.sourceQuote, maxLength: 320) ?? updated.content
        updated.factRelation = MemoryFactParser.normalizedRelationRawValue(memory.factRelation)
        updated.factValue = system.normalizedMetadataValue(memory.factValue, maxLength: 180)
        if let relation = updated.factRelation, system.isRelationBlocked(relation) {
            updated.factRelation = nil
            updated.factValue = nil
        }
        if let factValue = updated.factValue,
           !MemoryText.valuesCompatible(MemoryText.valueKey(factValue), MemoryText.valueKey(updated.content)) {
            updated.factRelation = nil
            updated.factValue = nil
        }
        updated.updatedAt = Date()
        updated.vector = system.embedding(for: updated.content)
        return await store.updateMemory(updated) ?? updated
    }

    private func conflictingIDs(
        matching signature: MemoryFactSignature,
        in memories: [UserMemory]
    ) -> [UUID] {
        let candidates = memories.filter { candidate in
            guard candidate.status != .archived else { return false }
            guard let existingSignature = MemoryFactParser.signature(for: candidate) else { return false }
            return signature.isRetraction
                ? signature.matchesForgetTarget(existingSignature)
                : signature.conflicts(with: existingSignature)
        }
        return candidates.map(\.id)
    }

    private func persistedInput(
        id: UUID,
        content: String,
        status: UserMemoryStatus,
        captureType: UserMemoryCaptureType,
        category: String?,
        sourceConversationId: UUID?,
        sourceMessageId: UUID?,
        sourceLanguageCode: String?,
        sourceQuote: String,
        relation: String?,
        valueDisplay: String?,
        createdAt: Date,
        updatedAt: Date,
        usageCount: Int,
        vector: [Double]?,
        confidence: Double
    ) -> MemoryPersistedInput {
        MemoryPersistedInput(
            id: id,
            canonicalText: content,
            status: status,
            scopeType: .global,
            personaId: nil,
            captureType: captureType,
            category: category,
            salience: captureType == .explicit ? 0.92 : 0.74,
            confidence: confidence,
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastUsedAt: nil,
            usageCount: usageCount,
            vector: vector,
            sourceConversationId: sourceConversationId,
            sourceMessageId: sourceMessageId,
            sourceQuote: sourceQuote,
            sourceLanguageCode: sourceLanguageCode,
            relation: relation,
            valueDisplay: valueDisplay,
            isNegated: false,
            extractionVersion: "memory-system-v2"
        )
    }
}

nonisolated final class MemoryRetrievalService: @unchecked Sendable {
    unowned let system: MemorySystem
    let store: MemoryStore
    let diagnosticsService: MemoryDiagnosticsService

    init(system: MemorySystem, store: MemoryStore, diagnosticsService: MemoryDiagnosticsService) {
        self.system = system
        self.store = store
        self.diagnosticsService = diagnosticsService
    }
}
