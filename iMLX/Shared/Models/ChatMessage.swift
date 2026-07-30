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
    var retrievedSources: [MessageSource]?
    var toolTraces: [ToolCallTrace]?
    var generationStats: GenerationStats?

    var toolTrace: ToolCallTrace? {
        get { toolTraces?.last }
        set { toolTraces = newValue.map { [$0] } }
    }
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
        case toolTrace
        case toolTraces
        case generationStats
        case timestamp
    }

    init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        attachedImages: [ChatAttachmentImage]? = nil,
        attachedDocuments: [ConversationDocumentReference]? = nil,
        retrievedSources: [MessageSource]? = nil,
        toolTrace: ToolCallTrace? = nil,
        toolTraces: [ToolCallTrace]? = nil,
        generationStats: GenerationStats? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.attachedImages = attachedImages
        self.attachedDocuments = attachedDocuments
        self.retrievedSources = retrievedSources
        if let toolTraces, !toolTraces.isEmpty {
            self.toolTraces = toolTraces
        } else {
            self.toolTraces = toolTrace.map { [$0] }
        }
        self.generationStats = generationStats
        self.timestamp = timestamp
    }

    init(from decoder: any Swift.Decoder) throws {
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
        if let decodedSources = try container.decodeIfPresent([MessageSource].self, forKey: .retrievedSources) {
            retrievedSources = decodedSources
        } else if let legacySources = try container.decodeIfPresent([RetrievedDocumentSource].self, forKey: .retrievedSources) {
            retrievedSources = legacySources.map(\.messageSource)
        } else {
            retrievedSources = nil
        }
        if let decodedTraces = try container.decodeIfPresent([ToolCallTrace].self, forKey: .toolTraces),
           !decodedTraces.isEmpty {
            toolTraces = decodedTraces
        } else if let legacyTrace = try container.decodeIfPresent(ToolCallTrace.self, forKey: .toolTrace) {
            toolTraces = [legacyTrace]
        } else {
            toolTraces = nil
        }
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
        try container.encodeIfPresent(toolTraces, forKey: .toolTraces)
        try container.encodeIfPresent(generationStats, forKey: .generationStats)
        try container.encode(timestamp, forKey: .timestamp)
    }
}
