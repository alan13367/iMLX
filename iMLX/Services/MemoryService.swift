import Foundation
import NaturalLanguage

private struct MemoryExtractionEnvelope: Decodable {
    let memories: [String]
}

private struct MemoryRetrievalCandidate {
    let memory: UserMemory
    let score: Double
}

nonisolated final class MemoryService {
    private let fileManager = FileManager.default
    private let memoriesDirectory: URL
    private let memoriesURL: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

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
        sourceMessageId: UUID? = nil
    ) -> UserMemory? {
        let normalizedContent = normalizedMemoryContent(content)
        guard !normalizedContent.isEmpty else { return nil }

        var memories = listAll()
        if let duplicateIndex = duplicateIndex(for: normalizedContent, in: memories) {
            var duplicate = memories[duplicateIndex]
            if duplicate.status == .archived || (duplicate.status == .pending && status == .active) {
                duplicate.status = status
            }
            duplicate.content = normalizedContent
            duplicate.personaId = duplicate.personaId ?? personaId
            duplicate.category = duplicate.category ?? category
            duplicate.updatedAt = Date()
            duplicate.vector = duplicate.vector ?? embedding(for: normalizedContent)
            memories[duplicateIndex] = duplicate
            persist(memories)
            return duplicate
        }

        let memory = UserMemory(
            content: normalizedContent,
            status: status,
            captureType: captureType,
            personaId: personaId,
            category: category,
            sourceConversationId: sourceConversationId,
            sourceMessageId: sourceMessageId,
            vector: embedding(for: normalizedContent)
        )
        memories.insert(memory, at: 0)
        persist(memories)
        return memory
    }

    func update(_ memory: UserMemory) -> UserMemory {
        var updated = memory
        updated.content = normalizedMemoryContent(memory.content)
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

    func archiveMatching(_ query: String) -> Int {
        let normalizedQuery = normalizedMemoryContent(query)
        guard !normalizedQuery.isEmpty else { return 0 }

        let queryVector = embedding(for: normalizedQuery)
        var memories = listAll()
        var archivedCount = 0

        for index in memories.indices where memories[index].status != .archived {
            let score = relevanceScore(
                query: normalizedQuery,
                queryVector: queryVector,
                memory: memories[index],
                personaId: nil
            )
            if score >= Constants.Memory.forgetMatchThreshold || normalizedMemoryContent(memories[index].content).contains(normalizedQuery) {
                memories[index].status = .archived
                memories[index].updatedAt = Date()
                archivedCount += 1
            }
        }

        if archivedCount > 0 {
            persist(memories)
        }

        return archivedCount
    }

    func retrieveActiveMemories(
        for query: String,
        personaId: String?,
        limit: Int,
        maxCharacters: Int
    ) -> [UserMemory] {
        let normalizedQuery = normalizedMemoryContent(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let queryVector = embedding(for: normalizedQuery)
        var usedCharacters = 0
        let ranked = listAll()
            .filter { $0.status == .active }
            .compactMap { memory in
                retrievalCandidate(
                    query: normalizedQuery,
                    queryVector: queryVector,
                    memory: memory,
                    personaId: personaId
                )
            }
            .sorted {
                if $0.score == $1.score {
                    return $0.memory.updatedAt > $1.memory.updatedAt
                }
                return $0.score > $1.score
            }

        var selected: [UserMemory] = []
        for candidate in ranked {
            guard selected.count < limit else { break }
            let addedCharacters = candidate.memory.content.count + 4
            guard usedCharacters + addedCharacters <= maxCharacters || selected.isEmpty else { break }
            selected.append(candidate.memory)
            usedCharacters += addedCharacters
        }

        return selected
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

    func extractionCandidates(from rawOutput: String) -> [String] {
        let trimmed = rawOutput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return sanitizedCandidates(decoded)
        }

        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(MemoryExtractionEnvelope.self, from: data) {
            return sanitizedCandidates(decoded.memories)
        }

        if let arrayText = firstJSONArray(in: trimmed),
           let data = arrayText.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            return sanitizedCandidates(decoded)
        }

        let lineCandidates = trimmed
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .replacingOccurrences(of: #"^\s*(?:[-*]|\d+[\.\)])\s*"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            }

        return sanitizedCandidates(lineCandidates)
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

    private func persist(_ memories: [UserMemory]) {
        guard let data = try? encoder.encode(memories.sorted(by: { $0.updatedAt > $1.updatedAt })) else { return }
        try? data.write(to: memoriesURL, options: .atomic)
    }

    private func duplicateIndex(for content: String, in memories: [UserMemory]) -> Int? {
        let vector = embedding(for: content)
        for index in memories.indices where memories[index].status != .archived {
            let existing = normalizedMemoryContent(memories[index].content)
            if existing == content {
                return index
            }
            if existing.contains(content) || content.contains(existing) {
                return index
            }
            let lexicalScore = lexicalSimilarity(content, existing)
            let semanticScore = score(queryVector: vector, memoryVector: memories[index].vector)
            if max(lexicalScore, semanticScore) >= Constants.Memory.duplicateScoreThreshold {
                return index
            }
        }
        return nil
    }

    private func relevanceScore(
        query: String,
        queryVector: [Double]?,
        memory: UserMemory,
        personaId: String?
    ) -> Double {
        let memoryContent = normalizedMemoryContent(memory.content)
        let lexicalScore = lexicalSimilarity(query, memoryContent)
        let semanticScore = score(queryVector: queryVector, memoryVector: memory.vector)
        var score = max(lexicalScore, semanticScore)

        if let memoryPersonaId = memory.personaId, let personaId, memoryPersonaId == personaId {
            score += Constants.Memory.personaMatchBoost
        } else if memory.personaId == nil {
            score += Constants.Memory.globalMemoryBoost
        }

        if query.contains(memoryContent) || memoryContent.contains(query) {
            score += Constants.Memory.substringMatchBoost
        }

        return min(score, 1.0)
    }

    private func retrievalCandidate(
        query: String,
        queryVector: [Double]?,
        memory: UserMemory,
        personaId: String?
    ) -> MemoryRetrievalCandidate? {
        let memoryContent = normalizedMemoryContent(memory.content)
        let baseScore = baseRelevanceScore(
            query: query,
            queryVector: queryVector,
            memoryContent: memoryContent,
            memoryVector: memory.vector
        )
        let topicalScore = topicalAffinityScore(query: query, memoryContent: memoryContent)
        let substringScore = query.contains(memoryContent) || memoryContent.contains(query)
            ? Constants.Memory.substringMatchBoost
            : 0
        let identityScore = isUserNameMemory(memoryContent)
            ? Constants.Memory.coreIdentityRetrievalScore
            : 0
        let eligibilityScore = max(baseScore, topicalScore, substringScore, identityScore)

        guard eligibilityScore >= Constants.Memory.minimumBaseRetrievalScore else { return nil }

        var score = eligibilityScore
        if let memoryPersonaId = memory.personaId, let personaId, memoryPersonaId == personaId {
            score += Constants.Memory.personaMatchBoost
        } else if memory.personaId == nil {
            score += Constants.Memory.globalMemoryBoost
        }

        return MemoryRetrievalCandidate(memory: memory, score: min(score, 1.0))
    }

    private func baseRelevanceScore(
        query: String,
        queryVector: [Double]?,
        memoryContent: String,
        memoryVector: [Double]?
    ) -> Double {
        let lexicalScore = lexicalSimilarity(query, memoryContent)
        let semanticScore = score(queryVector: queryVector, memoryVector: memoryVector)
        return max(lexicalScore, semanticScore)
    }

    private func topicalAffinityScore(query: String, memoryContent: String) -> Double {
        let sharedTopics = topicCategories(for: query).intersection(topicCategories(for: memoryContent))
        return sharedTopics.isEmpty ? 0 : Constants.Memory.topicalAffinityScore
    }

    private func topicCategories(for text: String) -> Set<String> {
        let normalized = normalizedMemoryContent(text).lowercased()
        var topics = Set<String>()

        if containsAny(
            [
                "breakfast", "carb", "cook", "cuisine", "dessert", "dinner", "dish", "eat", "food",
                "italian", "lunch", "meal", "pasta", "pizza", "recipe", "restaurant", "snack", "sushi",
                "vegan", "vegetarian"
            ],
            in: normalized
        ) {
            topics.insert("food")
        }

        if containsAny(
            [
                "barca", "barcelona", "champions league", "club", "fc ", "football", "goal", "la liga",
                "laliga", "league", "madrid", "match", "messi", "player", "soccer", "sport", "team"
            ],
            in: normalized
        ) {
            topics.insert("sports")
        }

        if containsAny(
            [
                "game", "gaming", "mario", "nintendo", "playstation", "pokemon", "switch", "videogame",
                "video game", "xbox", "zelda"
            ],
            in: normalized
        ) {
            topics.insert("gaming")
        }

        if containsAny(
            [
                "code", "developer", "engineer", "programming", "rust", "software", "swift", "xcode"
            ],
            in: normalized
        ) {
            topics.insert("tech")
        }

        return topics
    }

    private func containsAny(_ terms: [String], in text: String) -> Bool {
        terms.contains { text.contains($0) }
    }

    private func isUserNameMemory(_ content: String) -> Bool {
        let normalized = content.lowercased()
        return normalized.hasPrefix("the user's name is ")
            || normalized.hasPrefix("the user’s name is ")
            || normalized.hasPrefix("my name is ")
    }

    private func embedding(for text: String) -> [Double]? {
        let normalizedText = normalizedMemoryContent(text)
        guard !normalizedText.isEmpty else { return nil }
        let language = NLLanguageRecognizer.dominantLanguage(for: normalizedText) ?? .english

        if let embedding = NLEmbedding.sentenceEmbedding(for: language),
           let vector = embedding.vector(for: normalizedText) {
            return vector
        }

        guard language != .english,
              let fallbackEmbedding = NLEmbedding.sentenceEmbedding(for: .english),
              let vector = fallbackEmbedding.vector(for: normalizedText) else {
            return nil
        }

        return vector
    }

    private func score(queryVector: [Double]?, memoryVector: [Double]?) -> Double {
        guard let queryVector, let memoryVector, queryVector.count == memoryVector.count else {
            return 0
        }

        var dotProduct = 0.0
        var queryMagnitude = 0.0
        var memoryMagnitude = 0.0

        for index in queryVector.indices {
            dotProduct += queryVector[index] * memoryVector[index]
            queryMagnitude += queryVector[index] * queryVector[index]
            memoryMagnitude += memoryVector[index] * memoryVector[index]
        }

        let denominator = sqrt(queryMagnitude) * sqrt(memoryMagnitude)
        guard denominator > 0 else { return 0 }
        return max(0, dotProduct / denominator)
    }

    private func lexicalSimilarity(_ left: String, _ right: String) -> Double {
        let leftTerms = Set(tokenize(left))
        let rightTerms = Set(tokenize(right))
        guard !leftTerms.isEmpty, !rightTerms.isEmpty else { return 0 }
        let overlap = leftTerms.intersection(rightTerms).count
        let denominator = max(leftTerms.count, rightTerms.count)
        return Double(overlap) / Double(denominator)
    }

    private func tokenize(_ text: String) -> [String] {
        normalizedMemoryContent(text)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }

    private func normalizedMemoryContent(_ content: String) -> String {
        content
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
    }

    private func sanitizedCandidates(_ candidates: [String]) -> [String] {
        var seen = Set<String>()
        return candidates.compactMap { candidate in
            guard var normalized = normalizedExtractionCandidate(candidate) else { return nil }
            guard normalized.count >= Constants.Memory.minimumCandidateCharacters else { return nil }
            if normalized.count > Constants.Memory.maximumCandidateCharacters {
                normalized = String(normalized.prefix(Constants.Memory.maximumCandidateCharacters))
            }
            let key = normalized.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return normalized
        }
    }

    private func normalizedExtractionCandidate(_ candidate: String) -> String? {
        var normalized = normalizedMemoryContent(candidate)
        normalized = durableMemoryContent(from: normalized)
        normalized = normalizedUserMemorySentence(normalized)

        guard isWellFormedUserMemory(normalized) else { return nil }
        guard !isGenericRequestMemory(normalized) else { return nil }

        if let lastCharacter = normalized.last, !".!?".contains(lastCharacter) {
            normalized += "."
        }
        return normalized
    }

    private func normalizedUserMemorySentence(_ content: String) -> String {
        let lowercased = content.lowercased()
        if lowercased.hasPrefix("user's ") {
            return "The user's \(content.dropFirst(7))"
        }
        if lowercased.hasPrefix("user ") {
            return "The user \(content.dropFirst(5))"
        }
        return content
    }

    private func isWellFormedUserMemory(_ content: String) -> Bool {
        let lowercased = content.lowercased()
        guard lowercased.hasPrefix("the user ") || lowercased.hasPrefix("the user's ") else {
            return false
        }

        let wordCount = content
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .count
        return wordCount >= 4
    }

    private func isGenericRequestMemory(_ content: String) -> Bool {
        let lowercased = content.lowercased()
        let blockedPrefixes = [
            "the user asked",
            "the user asks",
            "the user requested",
            "the user requests",
            "the user is asking",
            "the user is requesting",
            "the user needs help",
            "the user wants help",
            "the user would like help"
        ]
        if blockedPrefixes.contains(where: { lowercased.hasPrefix($0) }) {
            return true
        }

        let blockedPhrases = [
            "clarification request",
            "information request",
            "recommendation request",
            "correction request",
            "comparison request"
        ]
        return blockedPhrases.contains { lowercased.contains($0) }
    }

    private func durableMemoryContent(from content: String) -> String {
        let lowercased = content.lowercased()
        let markers = [
            " and i would like ",
            " and i'd like ",
            " and i want ",
            " and i need ",
            " and would like ",
            " and want ",
            " and need ",
            ", i would like ",
            ", i'd like ",
            ", i want ",
            ", i need ",
            ", would like ",
            ", want ",
            ", need ",
            " but i would like ",
            " but i'd like ",
            " but i want ",
            " but i need ",
            " but would like ",
            " but want ",
            " but need ",
            " so i would like ",
            " so i'd like ",
            " so i want ",
            " so i need ",
            " so would like ",
            " so want ",
            " so need "
        ]

        let firstMarkerRange = markers
            .compactMap { marker in lowercased.range(of: marker) }
            .min { left, right in left.lowerBound < right.lowerBound }

        guard let firstMarkerRange else { return content }

        let trimmed = content[..<firstMarkerRange.lowerBound]
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: ".!?,;:")))
        guard !trimmed.isEmpty else { return content }
        return "\(trimmed)."
    }

    private func firstJSONArray(in text: String) -> String? {
        guard let start = text.firstIndex(of: "["),
              let end = text.lastIndex(of: "]"),
              start <= end else {
            return nil
        }
        return String(text[start...end])
    }
}
