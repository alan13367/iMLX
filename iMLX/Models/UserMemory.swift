import Foundation
import GRDB

nonisolated enum UserMemoryStatus: String, Codable, CaseIterable, DatabaseValueConvertible {
    case pending
    case active
    case archived

    var displayName: String {
        switch self {
        case .pending:
            String.appLocalized("memory.status.pending")
        case .active:
            String.appLocalized("memory.status.active")
        case .archived:
            String.appLocalized("memory.status.archived")
        }
    }
}

nonisolated enum MemoryScopeType: String, Codable, CaseIterable, DatabaseValueConvertible {
    case global

    var displayName: String {
        switch self {
        case .global:
            String.appLocalized("memory.scope.global")
        }
    }
}

nonisolated enum UserMemoryCaptureType: String, Codable, CaseIterable, DatabaseValueConvertible {
    case explicit
    case inferred

    var displayName: String {
        switch self {
        case .explicit:
            String.appLocalized("memory.capture.explicit")
        case .inferred:
            String.appLocalized("memory.capture.inferred")
        }
    }
}

nonisolated enum MemoryEventKind: String, Codable, CaseIterable, DatabaseValueConvertible {
    case created
    case updated
    case archived
    case forgotten
    case reactivated
    case retrieved
    case accepted
    case rejected
    case deleted
}

nonisolated enum MemoryRetrievalExplanationKind: String, Codable, CaseIterable {
    case matchedFact = "matched_fact"
    case matchedTopic = "matched_topic"
    case recentRelevant = "recent_relevant"
    case sourceQuoteOverlap = "source_quote_overlap"
}

nonisolated struct UserMemory: Identifiable, Codable, Hashable {
    let id: UUID
    var content: String
    var status: UserMemoryStatus
    var captureType: UserMemoryCaptureType
    var personaId: String?
    var category: String?
    var sourceConversationId: UUID?
    var sourceMessageId: UUID?
    let createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var usageCount: Int
    var vector: [Double]?
    var sourceLanguageCode: String?
    var sourceQuote: String?
    var factRelation: String?
    var factValue: String?

    init(
        id: UUID = UUID(),
        content: String,
        status: UserMemoryStatus,
        captureType: UserMemoryCaptureType,
        personaId: String? = nil,
        category: String? = nil,
        sourceConversationId: UUID? = nil,
        sourceMessageId: UUID? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        lastUsedAt: Date? = nil,
        usageCount: Int = 0,
        vector: [Double]? = nil,
        sourceLanguageCode: String? = nil,
        sourceQuote: String? = nil,
        factRelation: String? = nil,
        factValue: String? = nil
    ) {
        self.id = id
        self.content = content
        self.status = status
        self.captureType = captureType
        self.personaId = personaId
        self.category = category
        self.sourceConversationId = sourceConversationId
        self.sourceMessageId = sourceMessageId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.lastUsedAt = lastUsedAt
        self.usageCount = usageCount
        self.vector = vector
        self.sourceLanguageCode = sourceLanguageCode
        self.sourceQuote = sourceQuote
        self.factRelation = factRelation
        self.factValue = factValue
    }

    var displayCategory: String {
        let trimmed = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? String.appLocalized("memory.category.general") : trimmed
    }

    var updatedRelativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }
}

nonisolated struct MemoryEvidence: Identifiable, Codable, Hashable {
    let id: UUID
    let memoryId: UUID
    let sourceConversationId: UUID?
    let sourceMessageId: UUID?
    let sourceQuote: String
    let sourceLanguageCode: String?
    let extractionVersion: String
    let createdAt: Date
}

nonisolated struct MemoryEvent: Identifiable, Codable, Hashable {
    let id: UUID
    let memoryId: UUID
    let kind: MemoryEventKind
    let payload: String?
    let createdAt: Date
}

nonisolated struct MemoryRetrievalExplanation: Identifiable, Codable, Hashable {
    let id: UUID
    let memoryId: UUID
    let kind: MemoryRetrievalExplanationKind
    let message: String
    let score: Double
}

nonisolated struct MemoryRetrievalTrace: Codable, Hashable {
    let candidateCount: Int
    let selectedMemoryIDs: [UUID]
    let scoreBreakdown: [UUID: [String: Double]]
}

nonisolated struct MemoryDetail: Identifiable, Codable, Hashable {
    let id: UUID
    let summary: UserMemory
    let scopeType: MemoryScopeType
    let salience: Double
    let confidence: Double
    let blockedByRelationPolicy: Bool
    let evidence: [MemoryEvidence]
    let events: [MemoryEvent]
    let recentRetrievalExplanations: [MemoryRetrievalExplanation]
    let latestRetrievalTrace: MemoryRetrievalTrace?
}

nonisolated struct MemoryExtractionCandidate: Hashable {
    let canonicalContent: String
    let relation: String?
    let value: String?
    let sourceQuote: String?
    let sourceLanguageCode: String?
    let confidence: Double

    init(
        canonicalContent: String,
        relation: String? = nil,
        value: String? = nil,
        sourceQuote: String? = nil,
        sourceLanguageCode: String? = nil,
        confidence: Double = 1
    ) {
        self.canonicalContent = canonicalContent
        self.relation = relation
        self.value = value
        self.sourceQuote = sourceQuote
        self.sourceLanguageCode = sourceLanguageCode
        self.confidence = confidence
    }
}

nonisolated struct MemoryRetrievalResult {
    let contextBlock: String
    let memories: [UserMemory]
    let explanations: [MemoryRetrievalExplanation]
    let trace: MemoryRetrievalTrace?
}
