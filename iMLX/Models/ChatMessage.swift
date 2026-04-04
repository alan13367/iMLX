import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    var content: String
    var attachedImages: [Data]?
    var attachedDocuments: [ConversationDocumentReference]?
    var retrievedSources: [RetrievedDocumentSource]?
    var generationStats: GenerationStats?
    let timestamp: Date

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    init(
        role: Role,
        content: String,
        attachedImages: [Data]? = nil,
        attachedDocuments: [ConversationDocumentReference]? = nil,
        retrievedSources: [RetrievedDocumentSource]? = nil,
        generationStats: GenerationStats? = nil
    ) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.attachedImages = attachedImages
        self.attachedDocuments = attachedDocuments
        self.retrievedSources = retrievedSources
        self.generationStats = generationStats
        self.timestamp = Date()
    }
}
