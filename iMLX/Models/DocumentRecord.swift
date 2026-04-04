import Foundation

enum ConversationDocumentKind: String, Codable, CaseIterable {
    case pdf
    case csv
    case text

    var displayName: String {
        switch self {
        case .pdf:
            String.appLocalized("document.kind.pdf")
        case .csv:
            String.appLocalized("document.kind.csv")
        case .text:
            String.appLocalized("document.kind.text")
        }
    }

    static func from(pathExtension: String) -> ConversationDocumentKind {
        switch pathExtension.lowercased() {
        case "pdf":
            .pdf
        case "csv":
            .csv
        default:
            .text
        }
    }
}

struct ConversationDocumentReference: Identifiable, Codable, Hashable {
    let id: String
    var displayName: String
    var kind: ConversationDocumentKind
    var importedAt: Date
}

struct DocumentRecord: Identifiable, Codable {
    let id: String
    let conversationId: UUID
    var displayName: String
    var originalFilename: String
    var kind: ConversationDocumentKind
    var storedFilename: String
    var byteCount: Int
    var chunkCount: Int
    let createdAt: Date
    var updatedAt: Date
}

struct DocumentChunk: Codable {
    let id: String
    let documentId: String
    let ordinal: Int
    let text: String
    let location: String?
    let vector: [Double]?
}

struct DocumentIndex: Codable {
    let documentId: String
    let languageCode: String?
    let chunks: [DocumentChunk]
}

struct RetrievedDocumentSource: Identifiable, Codable, Hashable {
    let id: String
    let documentId: String
    let documentName: String
    let chunkId: String
    let excerpt: String
    let location: String?
    let score: Double
}

struct DocumentRetrievalResult {
    let contextBlock: String
    let sources: [RetrievedDocumentSource]
}

enum DocumentImportError: LocalizedError {
    case unreadable
    case unsupportedType
    case emptyDocument

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "The selected document could not be read."
        case .unsupportedType:
            "Only PDF, CSV, and text-based files are supported right now."
        case .emptyDocument:
            "The selected document did not contain any readable text."
        }
    }
}
