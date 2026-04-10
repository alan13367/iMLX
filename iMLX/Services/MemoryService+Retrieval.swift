import Foundation

extension MemoryService {
    nonisolated func archiveMatching(_ query: String) -> Int {
        let normalizedQuery = normalizedMemoryContent(query)
        guard !normalizedQuery.isEmpty else { return 0 }

        var memories = listAll()
        let index = searchIndex(for: memories)
        let queryTokens = MemoryText.tokens(normalizedQuery)
        let queryVector = MemoryVectorMath.normalized(embedding(for: normalizedQuery))
        let forgetSignature = MemoryFactParser.forgetSignature(for: normalizedQuery)
        let candidateIndexes = archiveCandidateIndexes(
            queryTokens: queryTokens,
            queryVector: queryVector,
            forgetSignature: forgetSignature,
            index: index
        )
        var archivedCount = 0

        for recordIndex in candidateIndexes {
            let record = index.records[recordIndex]
            guard record.memory.status != .archived else { continue }

            if shouldArchive(
                record: record,
                recordIndex: recordIndex,
                query: normalizedQuery,
                queryTokens: queryTokens,
                queryVector: queryVector,
                forgetSignature: forgetSignature,
                index: index
            ) {
                memories[record.memoryIndex].status = .archived
                memories[record.memoryIndex].updatedAt = Date()
                archivedCount += 1
            }
        }

        if archivedCount > 0 {
            persist(memories)
        }

        return archivedCount
    }

    nonisolated func retrieveActiveMemories(
        for query: String,
        personaId: String?,
        limit: Int,
        maxCharacters: Int
    ) -> [UserMemory] {
        let normalizedQuery = normalizedMemoryContent(query)
        guard !normalizedQuery.isEmpty else { return [] }

        let memories = listAll()
        let index = searchIndex(for: memories)
        let queryTokens = MemoryText.tokens(normalizedQuery)
        let queryVector = MemoryVectorMath.normalized(embedding(for: normalizedQuery))
        var querySignatures = MemoryFactParser.queryIntentSignatures(for: normalizedQuery)
        if let querySignature = MemoryFactParser.forgetSignature(for: normalizedQuery) {
            let retrievalSignature = MemoryFactSignature(
                relation: querySignature.relation,
                valueKey: querySignature.valueKey,
                isRetraction: false
            )
            if !querySignatures.contains(retrievalSignature) {
                querySignatures.append(retrievalSignature)
            }
        }
        let candidateIndexes = retrievalCandidateIndexes(
            queryTokens: queryTokens,
            queryVector: queryVector,
            querySignatures: querySignatures,
            index: index
        )
        var usedCharacters = 0

        let ranked = candidateIndexes
            .compactMap { recordIndex in
                retrievalCandidate(
                    query: normalizedQuery,
                    queryTokens: queryTokens,
                    queryVector: queryVector,
                    record: index.records[recordIndex],
                    recordIndex: recordIndex,
                    index: index,
                    querySignatures: querySignatures,
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



    nonisolated func duplicateIndex(
        for content: String,
        signature: MemoryFactSignature?,
        in memories: [UserMemory],
        index: MemoryVaultIndex
    ) -> Int? {
        let queryTokens = MemoryText.tokens(content)
        let queryVector = MemoryVectorMath.normalized(embedding(for: content))
        var candidateIndexes: Set<Int>

        if index.nonArchivedRecordIndexes.count <= MemoryScoring.exactScanLimit {
            candidateIndexes = Set(index.nonArchivedRecordIndexes)
        } else if let signature {
            candidateIndexes = index.factCandidateIndexes(for: signature)
            candidateIndexes.formUnion(index.sparseCandidateIndexes(for: queryTokens, limit: MemoryScoring.sparseCandidateLimit))
            candidateIndexes.formUnion(
                index.semanticCandidateIndexes(for: queryVector, limit: MemoryScoring.semanticCandidateLimit)
            )
        } else {
            candidateIndexes = Set(index.sparseCandidateIndexes(for: queryTokens, limit: MemoryScoring.sparseCandidateLimit))
            candidateIndexes.formUnion(
                index.semanticCandidateIndexes(for: queryVector, limit: MemoryScoring.semanticCandidateLimit)
            )
        }

        for recordIndex in candidateIndexes {
            let record = index.records[recordIndex]
            guard memories.indices.contains(record.memoryIndex), memories[record.memoryIndex].status != .archived else { continue }

            if record.normalizedContent == content {
                return record.memoryIndex
            }

            if let signature, let existingSignature = record.signature {
                if signature.isDuplicate(of: existingSignature) {
                    return record.memoryIndex
                }
                if signature.conflicts(with: existingSignature) {
                    continue
                }
            }

            let containmentMatch = record.normalizedContent.contains(content) || content.contains(record.normalizedContent)
            let sparseScore = normalizedBM25Score(index.bm25Score(queryTokens: queryTokens, recordIndex: recordIndex))
            let semanticScore = MemoryVectorMath.cosine(normalizedQuery: queryVector, normalizedMemory: record.normalizedVector)
            let coverageScore = termCoverageScore(queryTokens: queryTokens, documentTokens: record.tokens)
            let hybridScore = max((semanticScore * 0.7) + (sparseScore * 0.3), coverageScore)

            if containmentMatch, coverageScore >= 0.72 {
                return record.memoryIndex
            }

            if hybridScore >= Constants.Memory.duplicateScoreThreshold {
                return record.memoryIndex
            }
        }

        return nil
    }

    nonisolated func archiveContradictingMemories(
        matching signature: MemoryFactSignature,
        in memories: inout [UserMemory],
        personaId: String?,
        now: Date
    ) -> Int {
        let index = searchIndex(for: memories)
        let candidateIndexes: Set<Int>
        if signature.isRetraction {
            candidateIndexes = index.factCandidateIndexes(for: signature)
        } else if signature.relation.isSingleValued {
            candidateIndexes = index.relationBuckets[signature.relation] ?? []
        } else {
            candidateIndexes = index.factCandidateIndexes(for: signature)
        }
        var archivedCount = 0

        for recordIndex in candidateIndexes {
            let record = index.records[recordIndex]
            guard memories.indices.contains(record.memoryIndex),
                  memories[record.memoryIndex].status != .archived,
                  memoryScopesCanConflict(existing: memories[record.memoryIndex].personaId, incoming: personaId),
                  let existingSignature = record.signature else {
                continue
            }

            let shouldArchive = signature.isRetraction
                ? signature.matchesForgetTarget(existingSignature)
                : signature.conflicts(with: existingSignature)

            if shouldArchive {
                memories[record.memoryIndex].status = .archived
                memories[record.memoryIndex].updatedAt = now
                archivedCount += 1
            }
        }

        return archivedCount
    }

    private nonisolated func archiveCandidateIndexes(
        queryTokens: [String],
        queryVector: [Double]?,
        forgetSignature: MemoryFactSignature?,
        index: MemoryVaultIndex
    ) -> Set<Int> {
        if index.nonArchivedRecordIndexes.count <= MemoryScoring.exactScanLimit {
            return Set(index.nonArchivedRecordIndexes)
        }

        var candidateIndexes = Set<Int>()
        if let forgetSignature {
            candidateIndexes.formUnion(index.factCandidateIndexes(for: forgetSignature))
        }
        candidateIndexes.formUnion(index.sparseCandidateIndexes(for: queryTokens, limit: MemoryScoring.sparseCandidateLimit))
        candidateIndexes.formUnion(index.semanticCandidateIndexes(for: queryVector, limit: MemoryScoring.semanticCandidateLimit))
        return candidateIndexes
    }

    private nonisolated func shouldArchive(
        record: IndexedMemoryRecord,
        recordIndex: Int,
        query: String,
        queryTokens: [String],
        queryVector: [Double]?,
        forgetSignature: MemoryFactSignature?,
        index: MemoryVaultIndex
    ) -> Bool {
        if let forgetSignature, let memorySignature = record.signature, forgetSignature.matchesForgetTarget(memorySignature) {
            return true
        }

        let memoryContent = normalizedMemoryContent(record.normalizedContent)
        if memoryContent.contains(query) || query.contains(memoryContent) {
            return true
        }

        let score = relevanceScore(
            query: query,
            queryTokens: queryTokens,
            queryVector: queryVector,
            record: record,
            recordIndex: recordIndex,
            index: index,
            personaId: nil
        )
        return score >= Constants.Memory.forgetMatchThreshold
    }

    private nonisolated func retrievalCandidateIndexes(
        queryTokens: [String],
        queryVector: [Double]?,
        querySignatures: [MemoryFactSignature],
        index: MemoryVaultIndex
    ) -> Set<Int> {
        if index.activeRecordIndexes.count <= MemoryScoring.exactScanLimit {
            return Set(index.activeRecordIndexes)
        }

        var candidateIndexes = Set<Int>()
        candidateIndexes.formUnion(index.sparseCandidateIndexes(for: queryTokens, limit: MemoryScoring.sparseCandidateLimit))
        candidateIndexes.formUnion(index.semanticCandidateIndexes(for: queryVector, limit: MemoryScoring.semanticCandidateLimit))

        for querySignature in querySignatures {
            candidateIndexes.formUnion(index.factCandidateIndexes(for: querySignature))
        }

        candidateIndexes.formUnion(index.recentActiveRecordIndexes(limit: MemoryScoring.fallbackRecentCandidateLimit))
        return candidateIndexes.filter { index.records[$0].memory.status == .active }
    }

    private nonisolated func retrievalCandidate(
        query: String,
        queryTokens: [String],
        queryVector: [Double]?,
        record: IndexedMemoryRecord,
        recordIndex: Int,
        index: MemoryVaultIndex,
        querySignatures: [MemoryFactSignature],
        personaId: String?
    ) -> MemoryRetrievalCandidate? {
        guard record.memory.status == .active else { return nil }

        let baseScore = relevanceScore(
            query: query,
            queryTokens: queryTokens,
            queryVector: queryVector,
            record: record,
            recordIndex: recordIndex,
            index: index,
            querySignatures: querySignatures,
            personaId: personaId
        )
        let topicalScore = topicalAffinityScore(query: query, memoryContent: record.normalizedContent)
        let identityScore = identityAffinityScore(query: query, memoryContent: record.normalizedContent)
        let relationIntentScore = relationIntentScore(querySignatures: querySignatures, record: record)
        let eligibilityScore = max(baseScore, topicalScore, identityScore, relationIntentScore)

        guard eligibilityScore >= Constants.Memory.minimumBaseRetrievalScore else { return nil }

        var score = eligibilityScore
        if let memoryPersonaId = record.memory.personaId, let personaId, memoryPersonaId == personaId {
            score += Constants.Memory.personaMatchBoost
        } else if record.memory.personaId == nil {
            score += Constants.Memory.globalMemoryBoost
        }

        return MemoryRetrievalCandidate(memory: record.memory, score: min(score, 1.0))
    }

    private nonisolated func relevanceScore(
        query: String,
        queryTokens: [String],
        queryVector: [Double]?,
        record: IndexedMemoryRecord,
        recordIndex: Int,
        index: MemoryVaultIndex,
        querySignatures: [MemoryFactSignature] = [],
        personaId: String?
    ) -> Double {
        let sparseScore = normalizedBM25Score(index.bm25Score(queryTokens: queryTokens, recordIndex: recordIndex))
        let semanticScore = MemoryVectorMath.cosine(normalizedQuery: queryVector, normalizedMemory: record.normalizedVector)
        let coverageScore = termCoverageScore(queryTokens: queryTokens, documentTokens: record.tokens)
        var score = semanticScore > 0
            ? (semanticScore * MemoryScoring.semanticWeight)
                + (sparseScore * MemoryScoring.sparseWeight)
                + (coverageScore * MemoryScoring.coverageWeight)
            : max(sparseScore, coverageScore)

        if query.contains(record.normalizedContent) || record.normalizedContent.contains(query) {
            score += Constants.Memory.substringMatchBoost
        }

        score = max(score, relationIntentScore(querySignatures: querySignatures, record: record))

        if let memoryPersonaId = record.memory.personaId, let personaId, memoryPersonaId == personaId {
            score += Constants.Memory.personaMatchBoost
        } else if record.memory.personaId == nil {
            score += Constants.Memory.globalMemoryBoost
        }

        return min(score, 1.0)
    }

    private nonisolated func normalizedBM25Score(_ score: Double) -> Double {
        guard score > 0 else { return 0 }
        return score / (score + MemoryScoring.bm25Saturation)
    }

    private nonisolated func relationIntentScore(querySignatures: [MemoryFactSignature], record: IndexedMemoryRecord) -> Double {
        guard let memorySignature = record.signature, !querySignatures.isEmpty else { return 0 }

        for querySignature in querySignatures {
            if querySignature.relation == memorySignature.relation,
               querySignature.valueKey.isEmpty || querySignature.matchesForgetTarget(memorySignature) {
                return MemoryScoring.relationIntentRetrievalScore
            }
        }

        return 0
    }

    private nonisolated func termCoverageScore(queryTokens: [String], documentTokens: [String]) -> Double {
        let queryTerms = Set(queryTokens)
        let documentTerms = Set(documentTokens)
        guard !queryTerms.isEmpty, !documentTerms.isEmpty else { return 0 }

        let overlap = queryTerms.intersection(documentTerms).count
        guard overlap > 0 else { return 0 }
        return Double(overlap) / Double(queryTerms.count)
    }

    private nonisolated func topicalAffinityScore(query: String, memoryContent: String) -> Double {
        let sharedTopics = topicCategories(for: query).intersection(topicCategories(for: memoryContent))
        return sharedTopics.isEmpty ? 0 : Constants.Memory.topicalAffinityScore
    }

    private nonisolated func identityAffinityScore(query: String, memoryContent: String) -> Double {
        guard isUserNameMemory(memoryContent) else { return 0 }
        let queryTerms = Set(MemoryText.tokens(query))
        return queryTerms.contains("name") || queryTerms.contains("identity") || query.lowercased().contains("who am i")
            ? Constants.Memory.coreIdentityRetrievalScore
            : 0
    }

    private nonisolated func topicCategories(for text: String) -> Set<String> {
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

    private nonisolated func isUserNameMemory(_ content: String) -> Bool {
        let normalized = content.lowercased()
        return normalized.hasPrefix("the user's name is ")
            || normalized.hasPrefix("the user’s name is ")
            || normalized.hasPrefix("my name is ")
    }


    private nonisolated func memoryScopesCanConflict(existing: String?, incoming: String?) -> Bool {
        existing == incoming || existing == nil || incoming == nil
    }
}
