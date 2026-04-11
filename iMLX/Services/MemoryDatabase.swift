import Foundation
import GRDB

nonisolated final class MemoryDatabase {
    let dbPool: DatabasePool

    init(databaseURL: URL) throws {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        #if DEBUG
        configuration.prepareDatabase { db in
            if ProcessInfo.processInfo.environment["IMLX_TRACE_MEMORY_SQL"] == "1" {
                db.trace { print($0) }
            }
        }
        #endif

        dbPool = try DatabasePool(path: databaseURL.path, configuration: configuration)
        try migrator.migrate(dbPool)
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_legacy_user_memory") { db in
            try db.create(table: "user_memory", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("content", .text).notNull()
                t.column("status", .text).notNull()
                t.column("captureType", .text).notNull()
                t.column("personaId", .text)
                t.column("category", .text)
                t.column("sourceConversationId", .text)
                t.column("sourceMessageId", .text)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("lastUsedAt", .datetime)
                t.column("usageCount", .integer).notNull().defaults(to: 0)
                t.column("vector", .blob)
                t.column("sourceLanguageCode", .text)
                t.column("sourceQuote", .text)
                t.column("factRelation", .text)
                t.column("factValue", .text)
            }
        }

        migrator.registerMigration("v2_normalized_memory") { db in
            try db.create(table: "memory_item", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("canonicalText", .text).notNull()
                t.column("status", .text).notNull()
                t.column("scopeType", .text).notNull()
                t.column("personaId", .text)
                t.column("captureType", .text).notNull()
                t.column("category", .text)
                t.column("salience", .double).notNull().defaults(to: 0.5)
                t.column("confidence", .double).notNull().defaults(to: 1.0)
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
                t.column("lastUsedAt", .datetime)
                t.column("usageCount", .integer).notNull().defaults(to: 0)
                t.column("supersededBy", .text)
                t.column("archivedAt", .datetime)
            }
            try db.create(index: "memory_item_status_scope", on: "memory_item", columns: ["status", "scopeType", "personaId"], ifNotExists: true)
            try db.create(index: "memory_item_updated_at", on: "memory_item", columns: ["updatedAt"], ifNotExists: true)

            try db.create(table: "memory_fact", ifNotExists: true) { t in
                t.column("memoryId", .text).primaryKey().references("memory_item", onDelete: .cascade)
                t.column("relation", .text)
                t.column("valueKey", .text)
                t.column("valueDisplay", .text)
                t.column("isNegated", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "memory_fact_relation_value", on: "memory_fact", columns: ["relation", "valueKey"], ifNotExists: true)

            try db.create(table: "memory_evidence", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("memoryId", .text).notNull().references("memory_item", onDelete: .cascade)
                t.column("conversationId", .text)
                t.column("messageId", .text)
                t.column("sourceQuote", .text).notNull()
                t.column("sourceLanguageCode", .text)
                t.column("extractionVersion", .text).notNull()
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "memory_evidence_memory_created", on: "memory_evidence", columns: ["memoryId", "createdAt"], ifNotExists: true)

            try db.create(table: "memory_event", ifNotExists: true) { t in
                t.column("id", .text).primaryKey()
                t.column("memoryId", .text).notNull().references("memory_item", onDelete: .cascade)
                t.column("eventType", .text).notNull()
                t.column("payload", .text)
                t.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "memory_event_memory_created", on: "memory_event", columns: ["memoryId", "createdAt"], ifNotExists: true)

            try db.create(table: "memory_embedding_cache", ifNotExists: true) { t in
                t.column("memoryId", .text).primaryKey().references("memory_item", onDelete: .cascade)
                t.column("vector", .blob)
                t.column("sketch", .blob)
                t.column("updatedAt", .datetime).notNull()
            }

            try db.execute(sql: """
                CREATE VIRTUAL TABLE IF NOT EXISTS memory_fts
                USING fts5(memoryId UNINDEXED, canonicalText, evidenceText, tokenize = 'unicode61 remove_diacritics 2');
                """)
        }

        migrator.registerMigration("v3_backfill_normalized_memory") { db in
            return
        }

        migrator.registerMigration("v4_drop_legacy_user_memory") { db in
            guard try db.tableExists("user_memory") else { return }
            try db.drop(table: "user_memory")
        }

        return migrator
    }

    private static func defaultSalience(captureType: String, relation: String?) -> Double {
        if captureType == UserMemoryCaptureType.explicit.rawValue {
            return 0.92
        }
        guard let relation = MemoryRelation(externalValue: relation) else { return 0.60 }
        switch relation {
        case .name, .pronouns, .residence, .timezone:
            return 0.88
        case .likes, .dislikes, .goal, .project, .constraint:
            return 0.74
        default:
            return 0.64
        }
    }

}
