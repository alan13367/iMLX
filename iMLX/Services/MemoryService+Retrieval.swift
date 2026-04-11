import Foundation

extension MemorySystem {
    nonisolated func archiveMatching(_ query: String) -> Int {
        blocking { [self] in await self.retrievalService.archiveMatching(query) }
    }

    nonisolated func retrieveActiveMemories(
        for query: String,
        personaId: String?,
        limit: Int,
        maxCharacters: Int
    ) -> [UserMemory] {
        blocking { [self] in
            await self.retrievalService.retrieve(
                for: query,
                personaId: personaId,
                limit: limit,
                maxCharacters: maxCharacters
            ).memories
        }
    }

    nonisolated func retrieveMemoryResult(
        for query: String,
        personaId: String?,
        limit: Int,
        maxCharacters: Int
    ) -> MemoryRetrievalResult {
        blocking { [self] in
            await self.retrievalService.retrieve(
                for: query,
                personaId: personaId,
                limit: limit,
                maxCharacters: maxCharacters
            )
        }
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

    nonisolated func archiveCandidateIndexes(
        queryTokens: [String],
        queryVector: [Double]?,
        forgetSignature: MemoryFactSignature?,
        index: MemoryVaultIndex
    ) -> Set<Int> {
        var candidateIndexes = Set<Int>()
        if let forgetSignature {
            candidateIndexes.formUnion(index.factCandidateIndexes(for: forgetSignature))
        }
        candidateIndexes.formUnion(index.sparseCandidateIndexes(for: queryTokens, limit: MemoryScoring.sparseCandidateLimit))
        candidateIndexes.formUnion(index.semanticCandidateIndexes(for: queryVector, limit: MemoryScoring.semanticCandidateLimit))
        if candidateIndexes.isEmpty {
            return Set(index.nonArchivedRecordIndexes)
        }
        return candidateIndexes
    }

    nonisolated func shouldArchive(
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

    nonisolated func retrievalCandidateIndexes(
        queryTokens: [String],
        queryVector: [Double]?,
        querySignatures: [MemoryFactSignature],
        index: MemoryVaultIndex
    ) -> Set<Int> {
        var candidateIndexes = Set<Int>()
        candidateIndexes.formUnion(index.sparseCandidateIndexes(for: queryTokens, limit: MemoryScoring.sparseCandidateLimit))
        candidateIndexes.formUnion(index.semanticCandidateIndexes(for: queryVector, limit: MemoryScoring.semanticCandidateLimit))

        for querySignature in querySignatures {
            candidateIndexes.formUnion(index.factCandidateIndexes(for: querySignature))
        }

        candidateIndexes.formUnion(index.recentActiveRecordIndexes(limit: MemoryScoring.fallbackRecentCandidateLimit))
        if candidateIndexes.isEmpty {
            candidateIndexes = Set(index.activeRecordIndexes)
        }
        return candidateIndexes.filter { index.records[$0].memory.status == .active }
    }

    nonisolated func retrievalCandidate(
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
        if let memoryPersonaId = record.memory.personaId {
            guard let personaId, memoryPersonaId == personaId else { return nil }
        }

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

    nonisolated func relevanceScore(
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

    nonisolated func normalizedBM25Score(_ score: Double) -> Double {
        guard score > 0 else { return 0 }
        return score / (score + MemoryScoring.bm25Saturation)
    }

    nonisolated func termCoverageScore(queryTokens: [String], documentTokens: [String]) -> Double {
        guard !queryTokens.isEmpty, !documentTokens.isEmpty else { return 0 }
        let querySet = Set(queryTokens)
        let documentSet = Set(documentTokens)
        return Double(querySet.intersection(documentSet).count) / Double(querySet.count)
    }

    nonisolated func topicalAffinityScore(query: String, memoryContent: String) -> Double {
        let queryTopics = topicKeywords(in: query)
        let memoryTopics = topicKeywords(in: memoryContent)
        guard !queryTopics.isEmpty, !memoryTopics.isEmpty else { return 0 }
        let overlap = queryTopics.intersection(memoryTopics)
        guard !overlap.isEmpty else { return 0 }
        return min(0.48, Double(overlap.count) / Double(max(queryTopics.count, memoryTopics.count)))
    }

    nonisolated func identityAffinityScore(query: String, memoryContent: String) -> Double {
        guard isUserNameMemory(memoryContent) else { return 0 }
        let normalizedQuery = normalizedMemoryContent(query)
        guard containsAny(["name", "called", "who am i"], in: normalizedQuery.lowercased()) else { return 0 }
        return 0.56
    }

    nonisolated func relationIntentScore(querySignatures: [MemoryFactSignature], record: IndexedMemoryRecord) -> Double {
        guard !querySignatures.isEmpty, let signature = record.signature else { return 0 }
        guard querySignatures.contains(where: { $0.relation == signature.relation }) else { return 0 }
        if querySignatures.contains(where: { $0.matchesForgetTarget(signature) || $0.isDuplicate(of: signature) }) {
            return 0.62
        }
        return MemoryScoring.relationIntentRetrievalScore
    }

    private nonisolated func topicKeywords(in text: String) -> Set<String> {
        let normalized = normalizedMemoryContent(text).lowercased()
        var topics = Set<String>()

        if containsAny(["travel", "trip", "flight", "hotel", "vacation"], in: normalized) {
            topics.insert("travel")
        }
        if containsAny(["food", "eat", "cuisine", "restaurant", "coffee"], in: normalized) {
            topics.insert("food")
        }
        if containsAny(["work", "job", "team", "career", "company"], in: normalized) {
            topics.insert("work")
        }
        if containsAny(["code", "app", "swift", "ios", "model", "tech"], in: normalized) {
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
}

extension MemoryRetrievalService {
    func archiveMatching(_ query: String) async -> Int {
        let normalizedQuery = system.normalizedMemoryContent(query)
        guard !normalizedQuery.isEmpty else { return 0 }

        let forgetSignature = MemoryFactParser.forgetSignature(for: normalizedQuery)
        let candidates = await store.candidateSummaries(
            for: normalizedQuery,
            signature: forgetSignature,
            personaId: nil,
            statuses: [.active, .pending],
            mode: .conflict
        )
        guard !candidates.isEmpty else { return 0 }

        let index = system.searchIndex(for: candidates)
        let queryTokens = MemoryText.tokens(normalizedQuery)
        let queryVector = MemoryVectorMath.normalized(system.embedding(for: normalizedQuery))
        let candidateIndexes = system.archiveCandidateIndexes(
            queryTokens: queryTokens,
            queryVector: queryVector,
            forgetSignature: forgetSignature,
            index: index
        )

        let archiveIDs = candidateIndexes.compactMap { recordIndex -> UUID? in
            let record = index.records[recordIndex]
            guard system.shouldArchive(
                record: record,
                recordIndex: recordIndex,
                query: normalizedQuery,
                queryTokens: queryTokens,
                queryVector: queryVector,
                forgetSignature: forgetSignature,
                index: index
            ) else {
                return nil
            }
            return record.memory.id
        }

        await store.archive(ids: archiveIDs, supersededBy: nil, reason: .forgotten, at: Date())
        return archiveIDs.count
    }

    func retrieve(
        for query: String,
        personaId: String?,
        limit: Int,
        maxCharacters: Int
    ) async -> MemoryRetrievalResult {
        let normalizedQuery = system.normalizedMemoryContent(query)
        guard !normalizedQuery.isEmpty else {
            return MemoryRetrievalResult(contextBlock: "", memories: [], explanations: [], trace: nil)
        }

        let queryTokens = MemoryText.tokens(normalizedQuery)
        let queryVector = MemoryVectorMath.normalized(system.embedding(for: normalizedQuery))
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

        var combinedCandidates = await store.candidateSummaries(
            for: normalizedQuery,
            signature: nil,
            personaId: personaId,
            statuses: [.active],
            mode: .retrieval
        )
        for signature in querySignatures {
            let more = await store.candidateSummaries(
                for: normalizedQuery,
                signature: signature,
                personaId: personaId,
                statuses: [.active],
                mode: .retrieval
            )
            for candidate in more where !combinedCandidates.contains(where: { $0.id == candidate.id }) {
                combinedCandidates.append(candidate)
            }
        }

        guard !combinedCandidates.isEmpty else {
            return MemoryRetrievalResult(contextBlock: "", memories: [], explanations: [], trace: nil)
        }

        let index = system.searchIndex(for: combinedCandidates)
        let candidateIndexes = system.retrievalCandidateIndexes(
            queryTokens: queryTokens,
            queryVector: queryVector,
            querySignatures: querySignatures,
            index: index
        )

        let ranked = candidateIndexes
            .compactMap { recordIndex in
                system.retrievalCandidate(
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
        var explanations: [MemoryRetrievalExplanation] = []
        var scoreBreakdown: [UUID: [String: Double]] = [:]
        var usedCharacters = 0

        for candidate in ranked {
            guard selected.count < limit else { break }
            let addedCharacters = candidate.memory.content.count + 4
            guard usedCharacters + addedCharacters <= maxCharacters || selected.isEmpty else { break }
            selected.append(candidate.memory)
            usedCharacters += addedCharacters

            let explanationBundle = explanationBundle(
                query: normalizedQuery,
                queryTokens: queryTokens,
                queryVector: queryVector,
                memory: candidate.memory,
                score: candidate.score,
                personaId: personaId
            )
            explanations.append(contentsOf: explanationBundle.explanations)
            scoreBreakdown[candidate.memory.id] = explanationBundle.breakdown
        }

        guard !selected.isEmpty else {
            return MemoryRetrievalResult(contextBlock: "", memories: [], explanations: [], trace: nil)
        }

        let trace = diagnosticsService.trace(
            candidateCount: combinedCandidates.count,
            selectedMemoryIDs: selected.map(\.id),
            scoreBreakdown: scoreBreakdown
        )
        await store.markRetrieved(ids: selected.map(\.id), explanations: explanations, trace: trace)

        let contextLines = selected.map { "- \($0.content)" }
        let contextBlock = """
        Relevant persistent user memories:
        These memories were retrieved as potentially relevant. Use only the ones that directly help the current request, ignore any that do not fit, and do not mention stored memories unless the user asks.

        \(contextLines.joined(separator: "\n"))
        """

        return MemoryRetrievalResult(
            contextBlock: contextBlock,
            memories: selected,
            explanations: explanations,
            trace: trace
        )
    }

    private func explanationBundle(
        query: String,
        queryTokens: [String],
        queryVector: [Double]?,
        memory: UserMemory,
        score: Double,
        personaId: String?
    ) -> (explanations: [MemoryRetrievalExplanation], breakdown: [String: Double]) {
        let normalizedMemory = system.normalizedMemoryContent(memory.content)
        let memoryTokens = MemoryText.tokens([memory.content, memory.sourceQuote].compactMap { $0 }.joined(separator: " "))
        let memoryVector = MemoryVectorMath.normalized(memory.vector)
        let coverage = system.termCoverageScore(queryTokens: queryTokens, documentTokens: memoryTokens)
        let semantic = MemoryVectorMath.cosine(normalizedQuery: queryVector, normalizedMemory: memoryVector)
        let sparse = coverage

        var explanations: [MemoryRetrievalExplanation] = []
        if let relation = memory.factRelation,
           let relationEnum = MemoryRelation(externalValue: relation),
           MemoryFactParser.queryIntentSignatures(for: query).contains(where: { $0.relation == relationEnum }) {
            explanations.append(
                diagnosticsService.explanation(
                    memoryId: memory.id,
                    kind: .matchedFact,
                    score: score,
                    detail: "Matched the same memory fact category."
                )
            )
        }
        if memory.personaId != nil, memory.personaId == personaId {
            explanations.append(
                diagnosticsService.explanation(
                    memoryId: memory.id,
                    kind: .samePersona,
                    score: score,
                    detail: "Scoped to the same persona as this conversation."
                )
            )
        }
        if coverage >= 0.45 {
            explanations.append(
                diagnosticsService.explanation(
                    memoryId: memory.id,
                    kind: .matchedTopic,
                    score: coverage,
                    detail: "Overlapped with the same topic terms."
                )
            )
        }
        if memory.updatedAt > Date().addingTimeInterval(-60 * 60 * 24 * 30) {
            explanations.append(
                diagnosticsService.explanation(
                    memoryId: memory.id,
                    kind: .recentRelevant,
                    score: 0.4,
                    detail: "Recently updated and still relevant."
                )
            )
        }
        if let sourceQuote = memory.sourceQuote,
           !sourceQuote.isEmpty,
           normalizedMemory.contains(query) || query.contains(normalizedMemory) || sourceQuote.lowercased().contains(query.lowercased()) {
            explanations.append(
                diagnosticsService.explanation(
                    memoryId: memory.id,
                    kind: .sourceQuoteOverlap,
                    score: 0.5,
                    detail: "The original evidence quote overlaps with this query."
                )
            )
        }

        return (
            explanations,
            [
                "coverage": coverage,
                "semantic": semantic,
                "sparse": sparse,
                "final": score
            ]
        )
    }
}
