import Foundation

enum UserMemoryStatus: String, Codable, CaseIterable {
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

enum UserMemoryCaptureType: String, Codable, CaseIterable {
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

struct UserMemory: Identifiable, Codable, Hashable {
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
        vector: [Double]? = nil
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

struct MemoryRetrievalResult {
    let contextBlock: String
    let memories: [UserMemory]
}
