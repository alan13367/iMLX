import Foundation

nonisolated struct ChatAttachmentImage: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var data: Data

    init(id: UUID = UUID(), data: Data) {
        self.id = id
        self.data = data
    }
}

nonisolated struct ChatMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    var content: String
    var attachedImages: [ChatAttachmentImage]?
    var attachedDocuments: [ConversationDocumentReference]?
    var retrievedSources: [RetrievedDocumentSource]?
    var generationStats: GenerationStats?
    let timestamp: Date

    enum Role: String, Codable, Equatable {
        case user
        case assistant
        case system
    }

    enum CodingKeys: String, CodingKey {
        case id
        case role
        case content
        case attachedImages
        case attachedDocuments
        case retrievedSources
        case generationStats
        case timestamp
    }

    init(
        role: Role,
        content: String,
        attachedImages: [ChatAttachmentImage]? = nil,
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        role = try container.decode(Role.self, forKey: .role)
        content = try container.decode(String.self, forKey: .content)

        if let decodedImages = try container.decodeIfPresent([ChatAttachmentImage].self, forKey: .attachedImages) {
            attachedImages = decodedImages
        } else if let legacyImages = try container.decodeIfPresent([Data].self, forKey: .attachedImages) {
            attachedImages = legacyImages.map { ChatAttachmentImage(data: $0) }
        } else {
            attachedImages = nil
        }

        attachedDocuments = try container.decodeIfPresent([ConversationDocumentReference].self, forKey: .attachedDocuments)
        retrievedSources = try container.decodeIfPresent([RetrievedDocumentSource].self, forKey: .retrievedSources)
        generationStats = try container.decodeIfPresent(GenerationStats.self, forKey: .generationStats)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(attachedImages, forKey: .attachedImages)
        try container.encodeIfPresent(attachedDocuments, forKey: .attachedDocuments)
        try container.encodeIfPresent(retrievedSources, forKey: .retrievedSources)
        try container.encodeIfPresent(generationStats, forKey: .generationStats)
        try container.encode(timestamp, forKey: .timestamp)
    }
}
