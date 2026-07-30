import Foundation
import GRDB

private struct MemoryItemRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "memory_item"

    var id: UUID
    var canonicalText: String
    var status: UserMemoryStatus
    var scopeType: MemoryScopeType
    var personaId: String?
    var captureType: UserMemoryCaptureType
    var category: String?
    var salience: Double
    var confidence: Double
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var usageCount: Int
    var supersededBy: UUID?
    var archivedAt: Date?
}

private struct MemoryFactRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "memory_fact"

    var memoryId: UUID
    var relation: String?
    var valueKey: String?
    var valueDisplay: String?
    var isNegated: Bool
}

private struct MemoryEvidenceRecordDB: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "memory_evidence"

    var id: UUID
    var memoryId: UUID
    var conversationId: UUID?
    var messageId: UUID?
    var sourceQuote: String
    var sourceLanguageCode: String?
    var extractionVersion: String
    var createdAt: Date
}

private struct MemoryEventRecordDB: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "memory_event"

    var id: UUID
    var memoryId: UUID
    var eventType: MemoryEventKind
    var payload: String?
    var createdAt: Date
}

private struct MemoryEmbeddingCacheRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "memory_embedding_cache"

    var memoryId: UUID
    var vector: Data?
    var sketch: Data?
    var updatedAt: Date
}

struct MemoryPersistedInput {
    let id: UUID
    let canonicalText: String
    let status: UserMemoryStatus
    let scopeType: MemoryScopeType
    let personaId: String?
    let captureType: UserMemoryCaptureType
    let category: String?
    let salience: Double
    let confidence: Double
    let createdAt: Date
    let updatedAt: Date
    let lastUsedAt: Date?
    let usageCount: Int
    let vector: [Double]?
    let sourceConversationId: UUID?
    let sourceMessageId: UUID?
    let sourceQuote: String
    let sourceLanguageCode: String?
    let relation: String?
    let valueDisplay: String?
    let isNegated: Bool
    let extractionVersion: String
}

private struct RetrievalEventPayload {
    struct ExplanationPayload {
        let memoryId: UUID
        let kind: String
        let message: String
        let score: Double
    }

    let candidateCount: Int
    let selectedMemoryIDs: [UUID]
    let scoreBreakdown: [String: [String: Double]]
    let explanations: [ExplanationPayload]
}

actor MemoryStore {
    private let fileManager: FileManager
    private let database: MemoryDatabase?
    private let encoder = JSONEncoder()

    init(databaseURL: URL, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.database = Self.openDatabase(at: databaseURL, fileManager: fileManager)
    }

    func hasAnyMemory() -> Bool {
        guard let database else { return false }
        return (try? database.dbPool.read { db in
            try MemoryItemRecord.fetchCount(db) > 0
        }) ?? false
    }

    func importLegacyJSONMemories(_ memories: [UserMemory]) -> Bool {
        guard let database else { return false }
        do {
            var didImport = false
            try database.dbPool.write { db in
                guard try MemoryItemRecord.fetchCount(db) == 0 else {
                    return
                }

                for memory in memories {
                    var item = MemoryItemRecord(
                        id: memory.id,
                        canonicalText: memory.content,
                        status: memory.status,
                        scopeType: .global,
                        personaId: nil,
                        captureType: memory.captureType,
                        category: memory.category,
                        salience: memory.captureType == .explicit ? 0.92 : 0.74,
                        confidence: memory.captureType == .explicit ? 1.0 : 0.78,
                        createdAt: memory.createdAt,
                        updatedAt: memory.updatedAt,
                        lastUsedAt: memory.lastUsedAt,
                        usageCount: memory.usageCount,
                        supersededBy: nil,
                        archivedAt: memory.status == .archived ? memory.updatedAt : nil
                    )
                    try item.insert(db)
                    try upsertFact(memoryId: memory.id, relation: memory.factRelation, valueDisplay: memory.factValue, in: db)
                    let sourceQuote = memory.sourceQuote ?? memory.content
                    let input = MemoryPersistedInput(
                        id: memory.id,
                        canonicalText: memory.content,
                        status: memory.status,
                        scopeType: .global,
                        personaId: nil,
                        captureType: memory.captureType,
                        category: memory.category,
                        salience: memory.captureType == .explicit ? 0.92 : 0.74,
                        confidence: memory.captureType == .explicit ? 1.0 : 0.78,
                        createdAt: memory.createdAt,
                        updatedAt: memory.updatedAt,
                        lastUsedAt: memory.lastUsedAt,
                        usageCount: memory.usageCount,
                        vector: memory.vector,
                        sourceConversationId: memory.sourceConversationId,
                        sourceMessageId: memory.sourceMessageId,
                        sourceQuote: sourceQuote,
                        sourceLanguageCode: memory.sourceLanguageCode,
                        relation: memory.factRelation,
                        valueDisplay: memory.factValue,
                        isNegated: false,
                        extractionVersion: "legacy-json-v1"
                    )
                    try insertEvidence(from: input, in: db)
                    try upsertEmbedding(memoryId: memory.id, vector: memory.vector, updatedAt: memory.updatedAt, in: db)
                    try refreshFTS(memoryId: memory.id, canonicalText: memory.content, in: db)
                    try insertEvent(
                        MemoryEventRecordDB(
                            id: UUID(),
                            memoryId: memory.id,
                            eventType: .created,
                            payload: "{\"source\":\"legacy-json-v1\"}",
                            createdAt: memory.createdAt
                        ),
                        in: db
                    )
                }

                didImport = !memories.isEmpty
            }
            return didImport
        } catch {
            #if DEBUG
            print("Failed to import legacy JSON memories: \(error)")
            #endif
            return false
        }
    }

    func listSummaries() -> [UserMemory] {
        guard let database else { return [] }
        return (try? database.dbPool.read { db in
            try summaryRows(in: db, whereClause: nil, arguments: [])
        }) ?? []
    }

    func summary(for id: UUID) -> UserMemory? {
        guard let database else { return nil }
        return try? database.dbPool.read { db in
            try summaryRows(
                in: db,
                whereClause: "mi.id = ?",
                arguments: [id]
            ).first
        }
    }

    func detail(for id: UUID, blockedRelations: Set<String>) -> MemoryDetail? {
        guard let database else { return nil }
        return try? database.dbPool.read { db -> MemoryDetail? in
            guard let summary = try summaryRows(in: db, whereClause: "mi.id = ?", arguments: [id]).first,
                  let itemRow = try Row.fetchOne(
                    db,
                    sql: """
                        SELECT scopeType, salience, confidence
                        FROM memory_item
                        WHERE id = ?
                        """,
                    arguments: [id]
                  ) else {
                return nil
            }

            let evidence = try MemoryEvidenceRecordDB
                .filter(Column("memoryId") == id)
                .order(Column("createdAt").desc)
                .fetchAll(db)
                .map {
                    MemoryEvidence(
                        id: $0.id,
                        memoryId: $0.memoryId,
                        sourceConversationId: $0.conversationId,
                        sourceMessageId: $0.messageId,
                        sourceQuote: $0.sourceQuote,
                        sourceLanguageCode: $0.sourceLanguageCode,
                        extractionVersion: $0.extractionVersion,
                        createdAt: $0.createdAt
                    )
                }

            let events = try MemoryEventRecordDB
                .filter(Column("memoryId") == id)
                .order(Column("createdAt").desc)
                .fetchAll(db)
                .map {
                    MemoryEvent(
                        id: $0.id,
                        memoryId: $0.memoryId,
                        kind: $0.eventType,
                        payload: $0.payload,
                        createdAt: $0.createdAt
                    )
                }

            let retrievalPayloads: [RetrievalEventPayload] = events
                .filter { $0.kind == .retrieved }
                .reduce(into: []) { partialResult, event in
                    if let payload = parseRetrievalPayload(from: event.payload) {
                        partialResult.append(payload)
                    }
                }

            let recentExplanations = retrievalPayloads
                .flatMap(\.explanations)
                .prefix(12)
                .map {
                    MemoryRetrievalExplanation(
                        id: UUID(),
                        memoryId: $0.memoryId,
                        kind: MemoryRetrievalExplanationKind(rawValue: $0.kind) ?? .matchedTopic,
                        message: $0.message,
                        score: $0.score
                    )
                }

            let latestTrace = retrievalPayloads.first.map {
                MemoryRetrievalTrace(
                    candidateCount: $0.candidateCount,
                    selectedMemoryIDs: $0.selectedMemoryIDs,
                    scoreBreakdown: Dictionary(
                        uniqueKeysWithValues: $0.scoreBreakdown.compactMap { key, value in
                            guard let uuid = UUID(uuidString: key) else { return nil }
                            return (uuid, value)
                        }
                    )
                )
            }

            return MemoryDetail(
                id: id,
                summary: summary,
                scopeType: MemoryScopeType(rawValue: itemRow["scopeType"]) ?? .global,
                salience: itemRow["salience"] ?? 0.5,
                confidence: itemRow["confidence"] ?? 1.0,
                blockedByRelationPolicy: blockedRelations.contains(summary.factRelation ?? ""),
                evidence: evidence,
                events: events,
                recentRetrievalExplanations: Array(recentExplanations),
                latestRetrievalTrace: latestTrace
            )
        }
    }

    func pendingCount() -> Int {
        guard let database else { return 0 }
        return (try? database.dbPool.read { db in
            try MemoryItemRecord.filter(Column("status") == UserMemoryStatus.pending.rawValue).fetchCount(db)
        }) ?? 0
    }

    func clearAll() {
        guard let database else { return }
        try? database.dbPool.write { db in
            try MemoryItemRecord.deleteAll(db)
            try db.execute(sql: "DELETE FROM memory_fts")
        }
    }

    func delete(id: UUID) {
        guard let database else { return }
        try? database.dbPool.write { db in
            try MemoryItemRecord.deleteOne(db, key: id)
            try db.execute(sql: "DELETE FROM memory_fts WHERE memoryId = ?", arguments: [id])
        }
    }

    func setStatus(id: UUID, status: UserMemoryStatus, eventKind: MemoryEventKind) -> UserMemory? {
        guard let database else { return nil }
        return try? database.dbPool.write { db in
            guard var item = try MemoryItemRecord.fetchOne(db, key: id) else { return nil }
            item.status = status
            item.updatedAt = Date()
            item.archivedAt = status == .archived ? item.updatedAt : nil
            try item.update(db)
            try insertEvent(
                MemoryEventRecordDB(
                    id: UUID(),
                    memoryId: id,
                    eventType: eventKind,
                    payload: nil,
                    createdAt: item.updatedAt
                ),
                in: db
            )
            return try summaryRows(in: db, whereClause: "mi.id = ?", arguments: [id]).first
        }
    }

    func updateMemory(_ memory: UserMemory) -> UserMemory? {
        guard let database else { return nil }
        return try? database.dbPool.write { db in
            guard var item = try MemoryItemRecord.fetchOne(db, key: memory.id) else { return nil }
            item.canonicalText = memory.content
            item.status = memory.status
            item.scopeType = .global
            item.personaId = nil
            item.captureType = memory.captureType
            item.category = memory.category
            item.updatedAt = memory.updatedAt
            item.lastUsedAt = memory.lastUsedAt
            item.usageCount = memory.usageCount
            item.archivedAt = memory.status == .archived ? memory.updatedAt : nil
            try item.update(db)

            try upsertFact(
                memoryId: memory.id,
                relation: memory.factRelation,
                valueDisplay: memory.factValue,
                in: db
            )

            try upsertEmbedding(memoryId: memory.id, vector: memory.vector, updatedAt: memory.updatedAt, in: db)
            try refreshFTS(memoryId: memory.id, canonicalText: memory.content, in: db)
            try insertEvent(
                MemoryEventRecordDB(
                    id: UUID(),
                    memoryId: memory.id,
                    eventType: .updated,
                    payload: nil,
                    createdAt: memory.updatedAt
                ),
                in: db
            )

            return try summaryRows(in: db, whereClause: "mi.id = ?", arguments: [memory.id]).first
        }
    }

    func candidateSummaries(
        for query: String,
        signature: MemoryFactSignature?,
        statuses: [UserMemoryStatus],
        mode: MemoryCandidateScopeMode,
        factLimit: Int = 48,
        ftsLimit: Int = 96,
        recentLimit: Int = 24
    ) -> [UserMemory] {
        guard let database else { return [] }
        return (try? database.dbPool.read { db in
            var orderedIDs: [UUID] = []
            var seen = Set<UUID>()

            func append(_ ids: [UUID]) {
                for id in ids where seen.insert(id).inserted {
                    orderedIDs.append(id)
                }
            }

            append(try candidateFactIDs(
                in: db,
                signature: signature,
                statuses: statuses,
                mode: mode,
                limit: factLimit
            ))
            append(try candidateFTSIDs(
                in: db,
                query: query,
                statuses: statuses,
                mode: mode,
                limit: ftsLimit
            ))
            append(try recentCandidateIDs(
                in: db,
                statuses: statuses,
                mode: mode,
                limit: recentLimit
            ))

            var summaries: [UserMemory] = []
            summaries.reserveCapacity(orderedIDs.count)
            for id in orderedIDs {
                if let summary = try summaryRows(in: db, whereClause: "mi.id = ?", arguments: [id]).first {
                    summaries.append(summary)
                }
            }
            return summaries
        }) ?? []
    }

    func createMemory(_ input: MemoryPersistedInput, archivedIDs: [UUID], archiveReason: MemoryEventKind) -> UserMemory? {
        guard let database else { return nil }
        return try? database.dbPool.write { db in
            try archive(ids: archivedIDs, supersededBy: input.id, reason: archiveReason, at: input.updatedAt, in: db)
            var item = MemoryItemRecord(
                id: input.id,
                canonicalText: input.canonicalText,
                status: input.status,
                scopeType: input.scopeType,
                personaId: input.personaId,
                captureType: input.captureType,
                category: input.category,
                salience: input.salience,
                confidence: input.confidence,
                createdAt: input.createdAt,
                updatedAt: input.updatedAt,
                lastUsedAt: input.lastUsedAt,
                usageCount: input.usageCount,
                supersededBy: nil,
                archivedAt: input.status == .archived ? input.updatedAt : nil
            )
            try item.insert(db)
            try upsertFact(memoryId: input.id, relation: input.relation, valueDisplay: input.valueDisplay, isNegated: input.isNegated, in: db)
            try insertEvidence(from: input, in: db)
            try upsertEmbedding(memoryId: input.id, vector: input.vector, updatedAt: input.updatedAt, in: db)
            try refreshFTS(memoryId: input.id, canonicalText: input.canonicalText, in: db)
            try insertEvent(
                MemoryEventRecordDB(
                    id: UUID(),
                    memoryId: input.id,
                    eventType: .created,
                    payload: nil,
                    createdAt: input.createdAt
                ),
                in: db
            )

            return try summaryRows(in: db, whereClause: "mi.id = ?", arguments: [input.id]).first
        }
    }

    func updateExistingMemory(
        id: UUID,
        with input: MemoryPersistedInput,
        eventKind: MemoryEventKind
    ) -> UserMemory? {
        guard let database else { return nil }
        return try? database.dbPool.write { db in
            guard var item = try MemoryItemRecord.fetchOne(db, key: id) else {
                return nil
            }

            item.canonicalText = input.canonicalText
            item.status = input.status
            item.scopeType = input.scopeType
            item.personaId = input.personaId
            item.captureType = input.captureType
            item.category = input.category
            item.salience = input.salience
            item.confidence = max(item.confidence, input.confidence)
            item.updatedAt = input.updatedAt
            item.archivedAt = input.status == .archived ? input.updatedAt : nil
            try item.update(db)

            try upsertFact(memoryId: id, relation: input.relation, valueDisplay: input.valueDisplay, isNegated: input.isNegated, in: db)
            try insertEvidence(from: input, memoryId: id, in: db)
            try upsertEmbedding(memoryId: id, vector: input.vector, updatedAt: input.updatedAt, in: db)
            try refreshFTS(memoryId: id, canonicalText: input.canonicalText, in: db)
            try insertEvent(
                MemoryEventRecordDB(
                    id: UUID(),
                    memoryId: id,
                    eventType: eventKind,
                    payload: nil,
                    createdAt: input.updatedAt
                ),
                in: db
            )

            return try summaryRows(in: db, whereClause: "mi.id = ?", arguments: [id]).first
        }
    }

    func archive(ids: [UUID], supersededBy: UUID?, reason: MemoryEventKind, at date: Date = Date()) {
        guard let database else { return }
        try? database.dbPool.write { db in
            try archive(ids: ids, supersededBy: supersededBy, reason: reason, at: date, in: db)
        }
    }

    func markRetrieved(
        ids: [UUID],
        explanations: [MemoryRetrievalExplanation],
        trace: MemoryRetrievalTrace?
    ) {
        guard let database else { return }
        guard !ids.isEmpty else { return }
        let now = Date()
        try? database.dbPool.write { db in
            for id in ids {
                if var item = try MemoryItemRecord.fetchOne(db, key: id) {
                    item.usageCount += 1
                    item.lastUsedAt = now
                    try item.update(db)
                }
            }

            let payload = try? retrievalPayload(explanations: explanations, trace: trace)
            for id in ids {
                try insertEvent(
                    MemoryEventRecordDB(
                        id: UUID(),
                        memoryId: id,
                        eventType: .retrieved,
                        payload: payload,
                        createdAt: now
                    ),
                    in: db
                )
            }
        }
    }

    private func summaryRows(in db: Database, whereClause: String?, arguments: StatementArguments) throws -> [UserMemory] {
        var sql = """
            SELECT
                mi.id AS id,
                mi.canonicalText AS content,
                mi.status AS status,
                mi.captureType AS captureType,
                mi.personaId AS personaId,
                mi.category AS category,
                latest.conversationId AS sourceConversationId,
                latest.messageId AS sourceMessageId,
                mi.createdAt AS createdAt,
                mi.updatedAt AS updatedAt,
                mi.lastUsedAt AS lastUsedAt,
                mi.usageCount AS usageCount,
                mi.confidence AS confidence,
                mi.salience AS salience,
                ec.vector AS vector,
                latest.sourceLanguageCode AS sourceLanguageCode,
                latest.sourceQuote AS sourceQuote,
                mf.relation AS factRelation,
                mf.valueDisplay AS factValue
            FROM memory_item mi
            LEFT JOIN memory_fact mf ON mf.memoryId = mi.id
            LEFT JOIN memory_embedding_cache ec ON ec.memoryId = mi.id
            LEFT JOIN memory_evidence latest ON latest.id = (
                SELECT e.id
                FROM memory_evidence e
                WHERE e.memoryId = mi.id
                ORDER BY e.createdAt DESC
                LIMIT 1
            )
            """

        if let whereClause {
            sql += "\nWHERE \(whereClause)"
        }

        sql += "\nORDER BY mi.updatedAt DESC"
        return try Row.fetchAll(db, sql: sql, arguments: arguments).map(Self.userMemory(from:))
    }

    private static func userMemory(from row: Row) -> UserMemory {
        UserMemory(
            id: row["id"] ?? UUID(),
            content: row["content"] ?? "",
            status: UserMemoryStatus(rawValue: row["status"] ?? UserMemoryStatus.active.rawValue) ?? .active,
            captureType: UserMemoryCaptureType(rawValue: row["captureType"] ?? UserMemoryCaptureType.inferred.rawValue) ?? .inferred,
            personaId: row["personaId"],
            category: row["category"],
            sourceConversationId: row["sourceConversationId"],
            sourceMessageId: row["sourceMessageId"],
            createdAt: row["createdAt"] ?? Date(),
            updatedAt: row["updatedAt"] ?? Date(),
            lastUsedAt: row["lastUsedAt"],
            usageCount: row["usageCount"] ?? 0,
            vector: decodeVector(row["vector"]),
            sourceLanguageCode: row["sourceLanguageCode"],
            sourceQuote: row["sourceQuote"],
            factRelation: row["factRelation"],
            factValue: row["factValue"],
            confidence: row["confidence"],
            salience: row["salience"]
        )
    }

    private func candidateFactIDs(
        in db: Database,
        signature: MemoryFactSignature?,
        statuses: [UserMemoryStatus],
        mode: MemoryCandidateScopeMode,
        limit: Int
    ) throws -> [UUID] {
        guard let signature else { return [] }
        let (scopeSQL, scopeArgs) = scopeFilter(mode: mode)
        let statusSQL = statusFilter(statuses: statuses)

        var sql = """
            SELECT mi.id
            FROM memory_item mi
            JOIN memory_fact mf ON mf.memoryId = mi.id
            WHERE \(statusSQL)
              AND \(scopeSQL)
              AND mf.relation = ?
            ORDER BY mi.updatedAt DESC
            LIMIT ?
            """
        var args = StatementArguments()
        statusArguments(statuses: statuses).forEach { args += [$0] }
        scopeArgs.forEach { args += [$0] }
        args += [signature.relation.rawValue, limit]

        if !signature.valueKey.isEmpty, !signature.relation.isSingleValued {
            sql = """
                SELECT mi.id
                FROM memory_item mi
                JOIN memory_fact mf ON mf.memoryId = mi.id
                WHERE \(statusSQL)
                  AND \(scopeSQL)
                  AND mf.relation = ?
                  AND mf.valueKey = ?
                ORDER BY mi.updatedAt DESC
                LIMIT ?
                """
            args = StatementArguments()
            statusArguments(statuses: statuses).forEach { args += [$0] }
            scopeArgs.forEach { args += [$0] }
            args += [signature.relation.rawValue, signature.valueKey, limit]
        }

        return try UUID.fetchAll(db, sql: sql, arguments: args)
    }

    private func candidateFTSIDs(
        in db: Database,
        query: String,
        statuses: [UserMemoryStatus],
        mode: MemoryCandidateScopeMode,
        limit: Int
    ) throws -> [UUID] {
        let tokens = Array(MemoryText.tokens(query).prefix(6))
        guard !tokens.isEmpty else { return [] }
        let match = tokens
            .map { "\"\($0.replacingOccurrences(of: "\"", with: ""))\"*" }
            .joined(separator: " OR ")
        let (scopeSQL, scopeArgs) = scopeFilter(mode: mode)
        let statusSQL = statusFilter(statuses: statuses)
        let sql = """
            SELECT mi.id
            FROM memory_fts f
            JOIN memory_item mi ON mi.id = f.memoryId
            WHERE memory_fts MATCH ?
              AND \(statusSQL)
              AND \(scopeSQL)
            ORDER BY bm25(memory_fts), mi.updatedAt DESC
            LIMIT ?
            """
        var args = StatementArguments()
        args += [match]
        statusArguments(statuses: statuses).forEach { args += [$0] }
        scopeArgs.forEach { args += [$0] }
        args += [limit]
        return try UUID.fetchAll(db, sql: sql, arguments: args)
    }

    private func recentCandidateIDs(
        in db: Database,
        statuses: [UserMemoryStatus],
        mode: MemoryCandidateScopeMode,
        limit: Int
    ) throws -> [UUID] {
        let (scopeSQL, scopeArgs) = scopeFilter(mode: mode)
        let statusSQL = statusFilter(statuses: statuses)
        let sql = """
            SELECT mi.id
            FROM memory_item mi
            WHERE \(statusSQL)
              AND \(scopeSQL)
            ORDER BY mi.salience DESC, mi.updatedAt DESC
            LIMIT ?
            """
        var args = StatementArguments()
        statusArguments(statuses: statuses).forEach { args += [$0] }
        scopeArgs.forEach { args += [$0] }
        args += [limit]
        return try UUID.fetchAll(db, sql: sql, arguments: args)
    }

    private func archive(ids: [UUID], supersededBy: UUID?, reason: MemoryEventKind, at date: Date, in db: Database) throws {
        guard !ids.isEmpty else { return }
        for id in ids {
            guard var item = try MemoryItemRecord.fetchOne(db, key: id) else { continue }
            guard item.status != .archived else { continue }
            item.status = .archived
            item.archivedAt = date
            item.updatedAt = date
            item.supersededBy = supersededBy
            try item.update(db)
            try insertEvent(
                MemoryEventRecordDB(
                    id: UUID(),
                    memoryId: id,
                    eventType: reason,
                    payload: supersededBy.map { "{\"supersededBy\":\"\($0.uuidString)\"}" },
                    createdAt: date
                ),
                in: db
            )
        }
    }

    private func upsertFact(
        memoryId: UUID,
        relation: String?,
        valueDisplay: String?,
        isNegated: Bool = false,
        in db: Database
    ) throws {
        guard relation != nil || valueDisplay != nil else {
            try MemoryFactRecord.deleteOne(db, key: memoryId)
            return
        }
        var fact = MemoryFactRecord(
            memoryId: memoryId,
            relation: relation,
            valueKey: valueDisplay.map(MemoryText.valueKey),
            valueDisplay: valueDisplay,
            isNegated: isNegated
        )
        try fact.save(db)
    }

    private func insertEvidence(from input: MemoryPersistedInput, memoryId: UUID? = nil, in db: Database) throws {
        let quote = input.sourceQuote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quote.isEmpty else { return }
        var evidence = MemoryEvidenceRecordDB(
            id: UUID(),
            memoryId: memoryId ?? input.id,
            conversationId: input.sourceConversationId,
            messageId: input.sourceMessageId,
            sourceQuote: quote,
            sourceLanguageCode: input.sourceLanguageCode,
            extractionVersion: input.extractionVersion,
            createdAt: input.updatedAt
        )
        try evidence.insert(db)
    }

    private func insertEvent(_ event: MemoryEventRecordDB, in db: Database) throws {
        var event = event
        try event.insert(db)
    }

    private func upsertEmbedding(memoryId: UUID, vector: [Double]?, updatedAt: Date, in db: Database) throws {
        guard let vector else {
            try MemoryEmbeddingCacheRecord.deleteOne(db, key: memoryId)
            return
        }
        let encodedVector = try encoder.encode(vector)
        let encodedSketch = try encoder.encode(MemoryVectorSketch.keys(for: MemoryVectorMath.normalized(vector)))
        var record = MemoryEmbeddingCacheRecord(
            memoryId: memoryId,
            vector: encodedVector,
            sketch: encodedSketch,
            updatedAt: updatedAt
        )
        try record.save(db)
    }

    private func refreshFTS(memoryId: UUID, canonicalText: String, in db: Database) throws {
        let evidenceText = try String.fetchOne(
            db,
            sql: """
                SELECT sourceQuote
                FROM memory_evidence
                WHERE memoryId = ?
                ORDER BY createdAt DESC
                LIMIT 1
                """,
            arguments: [memoryId]
        ) ?? canonicalText
        try db.execute(sql: "DELETE FROM memory_fts WHERE memoryId = ?", arguments: [memoryId])
        try db.execute(
            sql: """
                INSERT INTO memory_fts (memoryId, canonicalText, evidenceText)
                VALUES (?, ?, ?)
                """,
            arguments: [memoryId, canonicalText, evidenceText]
        )
    }

    private func retrievalPayload(explanations: [MemoryRetrievalExplanation], trace: MemoryRetrievalTrace?) throws -> String {
        let payload = RetrievalEventPayload(
            candidateCount: trace?.candidateCount ?? explanations.count,
            selectedMemoryIDs: trace?.selectedMemoryIDs ?? explanations.map(\.memoryId),
            scoreBreakdown: Dictionary(
                uniqueKeysWithValues: (trace?.scoreBreakdown ?? [:]).map { ($0.key.uuidString, $0.value) }
            ),
            explanations: explanations.map {
                RetrievalEventPayload.ExplanationPayload(
                    memoryId: $0.memoryId,
                    kind: $0.kind.rawValue,
                    message: $0.message,
                    score: $0.score
                )
            }
        )
        let jsonObject: [String: Any] = [
            "candidateCount": payload.candidateCount,
            "selectedMemoryIDs": payload.selectedMemoryIDs.map(\.uuidString),
            "scoreBreakdown": Dictionary(
                uniqueKeysWithValues: payload.scoreBreakdown.map { key, value in
                    (key, value)
                }
            ),
            "explanations": payload.explanations.map {
                [
                    "memoryId": $0.memoryId.uuidString,
                    "kind": $0.kind,
                    "message": $0.message,
                    "score": $0.score
                ]
            }
        ]
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private func parseRetrievalPayload(from rawPayload: String?) -> RetrievalEventPayload? {
        guard let rawPayload,
              let data = rawPayload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let selectedMemoryIDs = (json["selectedMemoryIDs"] as? [String] ?? []).compactMap(UUID.init(uuidString:))
        let rawBreakdown = json["scoreBreakdown"] as? [String: [String: Double]] ?? [:]
        var explanations: [RetrievalEventPayload.ExplanationPayload] = []
        for rawExplanation in (json["explanations"] as? [[String: Any]] ?? []) {
            guard let memoryIDRaw = rawExplanation["memoryId"] as? String,
                  let memoryID = UUID(uuidString: memoryIDRaw),
                  let kind = rawExplanation["kind"] as? String,
                  let message = rawExplanation["message"] as? String else {
                continue
            }
            let score = rawExplanation["score"] as? Double ?? 0
            explanations.append(
                RetrievalEventPayload.ExplanationPayload(
                    memoryId: memoryID,
                    kind: kind,
                    message: message,
                    score: score
                )
            )
        }

        return RetrievalEventPayload(
            candidateCount: json["candidateCount"] as? Int ?? explanations.count,
            selectedMemoryIDs: selectedMemoryIDs,
            scoreBreakdown: rawBreakdown,
            explanations: explanations
        )
    }

    private func scopeFilter(mode: MemoryCandidateScopeMode) -> (String, [DatabaseValueConvertible?]) {
        switch mode {
        case .retrieval:
            return ("1 = 1", [])
        case .conflict:
            return ("1 = 1", [])
        }
    }

    private func statusFilter(statuses: [UserMemoryStatus]) -> String {
        let placeholders = statuses.map { _ in "?" }.joined(separator: ", ")
        return "mi.status IN (\(placeholders))"
    }

    private func statusArguments(statuses: [UserMemoryStatus]) -> [String] {
        statuses.map(\.rawValue)
    }

    private static func openDatabase(at dbURL: URL, fileManager: FileManager) -> MemoryDatabase? {
        do {
            return try MemoryDatabase(databaseURL: dbURL)
        } catch {
            #if DEBUG
            print("Failed to open memory database: \(error)")
            #endif
            moveAsideDatabaseFiles(for: dbURL, fileManager: fileManager)
            do {
                return try MemoryDatabase(databaseURL: dbURL)
            } catch {
                #if DEBUG
                print("Failed to recreate memory database: \(error)")
                #endif
                return nil
            }
        }
    }

    private static func moveAsideDatabaseFiles(for dbURL: URL, fileManager: FileManager) {
        let timestamp = Int(Date().timeIntervalSince1970)
        let candidates = [
            dbURL,
            URL(fileURLWithPath: dbURL.path + "-wal"),
            URL(fileURLWithPath: dbURL.path + "-shm")
        ]

        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            let movedURL = candidate
                .deletingLastPathComponent()
                .appendingPathComponent("\(candidate.lastPathComponent).corrupt-\(timestamp)")
            try? fileManager.moveItem(at: candidate, to: movedURL)
        }
    }

    private static func decodeVector(_ data: Data?) -> [Double]? {
        guard let data else { return nil }
        return try? JSONDecoder().decode([Double].self, from: data)
    }
}

enum MemoryCandidateScopeMode {
    case retrieval
    case conflict
}
