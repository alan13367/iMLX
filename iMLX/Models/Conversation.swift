import Foundation

struct Conversation: Identifiable, Codable, Hashable {
    let id: UUID
    var title: String
    var messages: [ChatMessage]
    var modelId: String?
    var personaId: String?
    var documents: [ConversationDocumentReference]
    let createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        messages: [ChatMessage] = [],
        modelId: String? = nil,
        personaId: String? = Persona.defaultID,
        documents: [ConversationDocumentReference] = [],
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.messages = messages
        self.modelId = modelId
        self.personaId = personaId
        self.documents = documents
        self.createdAt = createdAt
        self.updatedAt = updatedAt
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
