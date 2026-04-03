import Foundation

struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    var content: String
    var attachedImages: [Data]?
    var generationStats: GenerationStats?
    let timestamp: Date

    enum Role: String, Codable {
        case user
        case assistant
        case system
    }

    init(role: Role, content: String, attachedImages: [Data]? = nil, generationStats: GenerationStats? = nil) {
        self.id = UUID()
        self.role = role
        self.content = content
        self.attachedImages = attachedImages
        self.generationStats = generationStats
        self.timestamp = Date()
    }
}
