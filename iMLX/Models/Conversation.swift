import Foundation

nonisolated struct Conversation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var modelId: String?
    var personaId: String?
    var webSearchEnabled: Bool
    var documents: [ConversationDocumentReference]
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case messages
        case modelId
        case personaId
        case webSearchEnabled
        case documents
        case createdAt
        case updatedAt
    }

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        messages: [ChatMessage] = [],
        modelId: String? = nil,
        personaId: String? = Persona.defaultID,
        webSearchEnabled: Bool = false,
        documents: [ConversationDocumentReference] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.modelId = modelId
        self.personaId = personaId
        self.webSearchEnabled = webSearchEnabled
        self.documents = documents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: any Swift.Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        messages = try container.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        modelId = try container.decodeIfPresent(String.self, forKey: .modelId)
        personaId = try container.decodeIfPresent(String.self, forKey: .personaId)
        webSearchEnabled = try container.decodeIfPresent(Bool.self, forKey: .webSearchEnabled) ?? false
        documents = try container.decodeIfPresent([ConversationDocumentReference].self, forKey: .documents) ?? []
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(modelId, forKey: .modelId)
        try container.encodeIfPresent(personaId, forKey: .personaId)
        try container.encode(webSearchEnabled, forKey: .webSearchEnabled)
        try container.encode(documents, forKey: .documents)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var displayTitle: String {
        if title == "New Conversation" {
            if let firstUser = messages.first(where: { $0.role == .user }) {
                let truncated = String(firstUser.content.prefix(40))
                return truncated.count < firstUser.content.count ? truncated + "..." : truncated
            }
        }
        return title
    }

    var formattedDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: updatedAt, relativeTo: Date())
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Conversation, rhs: Conversation) -> Bool {
        lhs.id == rhs.id
    }
}
