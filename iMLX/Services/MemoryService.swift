import Foundation

nonisolated final class MemoryService {
    private let fileManager = FileManager.default
    private let memoriesDirectory: URL
    private let memoriesURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var cachedIndex: MemoryVaultIndex?

    init() {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        memoriesDirectory = appSupport.appendingPathComponent(Constants.Storage.memoriesDirectory, isDirectory: true)
        memoriesURL = memoriesDirectory.appendingPathComponent(Constants.Storage.memoriesFilename)
        try? fileManager.createDirectory(at: memoriesDirectory, withIntermediateDirectories: true)
    }

    func listAll() -> [UserMemory] {
        guard let data = try? Data(contentsOf: memoriesURL),
              let memories = try? decoder.decode([UserMemory].self, from: data) else {
            return []
        }
        return memories.sorted { $0.updatedAt > $1.updatedAt }
    }

    func upsert(
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
        let normalizedContent = normalizedStoredMemoryContent(content)
        guard !normalizedContent.isEmpty else { return nil }
        guard captureType != .inferred || !isLowValueInferredMemory(normalizedContent) else { return nil }

        let normalizedSourceQuote = normalizedMetadataValue(sourceQuote, maxLength: 320)
        let normalizedSourceLanguageCode = normalizedLanguageCode(sourceLanguageCode)
            ?? normalizedSourceQuote.flatMap(detectedLanguageCode)
        let normalizedFactRelation = MemoryFactParser.normalizedRelationRawValue(factRelation)
        let normalizedFactValue = normalizedMetadataValue(factValue, maxLength: 180)
        var memories = listAll()
        let index = searchIndex(for: memories)
        let signature = MemoryFactParser.signature(relation: normalizedFactRelation, value: normalizedFactValue)
            ?? MemoryFactParser.signature(for: normalizedContent)

        if let signature, signature.isRetraction {
            let archived = archiveContradictingMemories(
                matching: signature,
                in: &memories,
                personaId: personaId,
                now: Date()
            )
            if archived > 0 {
                persist(memories)
            }
            return nil
        }

        if let duplicateIndex = duplicateIndex(for: normalizedContent, signature: signature, in: memories, index: index) {
            var duplicate = memories[duplicateIndex]
            if duplicate.status == .archived || (duplicate.status == .pending && status == .active) {
                duplicate.status = status
            }
            duplicate.content = normalizedContent
            duplicate.personaId = duplicate.personaId ?? personaId
            duplicate.category = duplicate.category ?? category
            duplicate.updatedAt = Date()
            duplicate.vector = duplicate.vector ?? embedding(for: normalizedContent)
            duplicate.sourceLanguageCode = duplicate.sourceLanguageCode ?? normalizedSourceLanguageCode
            duplicate.sourceQuote = duplicate.sourceQuote ?? normalizedSourceQuote
            duplicate.factRelation = duplicate.factRelation ?? normalizedFactRelation
            duplicate.factValue = duplicate.factValue ?? normalizedFactValue
            memories[duplicateIndex] = duplicate
            persist(memories)
            return duplicate
        }

        if let signature {
            _ = archiveContradictingMemories(
                matching: signature,
                in: &memories,
                personaId: personaId,
                now: Date()
            )
        }

        let memory = UserMemory(
            content: normalizedContent,
            status: status,
            captureType: captureType,
            personaId: personaId,
            category: category,
            sourceConversationId: sourceConversationId,
            sourceMessageId: sourceMessageId,
            vector: embedding(for: normalizedContent),
            sourceLanguageCode: normalizedSourceLanguageCode,
            sourceQuote: normalizedSourceQuote,
            factRelation: normalizedFactRelation,
            factValue: normalizedFactValue
        )
        memories.insert(memory, at: 0)
        persist(memories)
        return memory
    }

    func update(_ memory: UserMemory) -> UserMemory {
        var updated = memory
        updated.content = normalizedStoredMemoryContent(memory.content)
        updated.sourceLanguageCode = normalizedLanguageCode(memory.sourceLanguageCode)
        updated.sourceQuote = normalizedMetadataValue(memory.sourceQuote, maxLength: 320)
        updated.factRelation = MemoryFactParser.normalizedRelationRawValue(memory.factRelation)
        updated.factValue = normalizedMetadataValue(memory.factValue, maxLength: 180)
        if let factValue = updated.factValue,
           !MemoryText.valuesCompatible(MemoryText.valueKey(factValue), MemoryText.valueKey(updated.content)) {
            updated.factRelation = nil
            updated.factValue = nil
        }
        updated.updatedAt = Date()
        updated.vector = embedding(for: updated.content)
        replace(updated)
        return updated
    }

    func setStatus(id: UUID, status: UserMemoryStatus) -> UserMemory? {
        var memories = listAll()
        guard let index = memories.firstIndex(where: { $0.id == id }) else { return nil }
        memories[index].status = status
        memories[index].updatedAt = Date()
        let updated = memories[index]
        persist(memories)
        return updated
    }

    func delete(id: UUID) {
        var memories = listAll()
        memories.removeAll { $0.id == id }
        persist(memories)
    }

    func clearAll() {
        persist([])
    }


    func markUsed(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let idSet = Set(ids)
        var memories = listAll()
        var changed = false

        for index in memories.indices where idSet.contains(memories[index].id) {
            memories[index].usageCount += 1
            memories[index].lastUsedAt = Date()
            changed = true
        }

        if changed {
            persist(memories)
        }
    }

    func pendingCount() -> Int {
        listAll().filter { $0.status == .pending }.count
    }


    private func replace(_ memory: UserMemory) {
        var memories = listAll()
        if let index = memories.firstIndex(where: { $0.id == memory.id }) {
            memories[index] = memory
        } else {
            memories.insert(memory, at: 0)
        }
        persist(memories)
    }

    func persist(_ memories: [UserMemory]) {
        guard let data = try? encoder.encode(memories.sorted(by: { $0.updatedAt > $1.updatedAt })) else { return }
        try? data.write(to: memoriesURL, options: .atomic)
        cachedIndex = nil
    }

    func searchIndex(for memories: [UserMemory]) -> MemoryVaultIndex {
        let fingerprint = MemoryVaultIndex.fingerprint(for: memories)
        if let cachedIndex, cachedIndex.fingerprint == fingerprint {
            return cachedIndex
        }
        let index = MemoryVaultIndex(memories: memories)
        cachedIndex = index
        return index
    }

}
