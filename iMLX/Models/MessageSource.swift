import Foundation

nonisolated enum MessageSourceKind: String, Codable, Hashable {
    case document
    case image
    case web
}

nonisolated struct MessageSource: Identifiable, Codable, Hashable {
    let id: String
    let kind: MessageSourceKind
    let title: String
    let excerpt: String
    let location: String?
    let url: URL?
    let score: Double?
}

nonisolated struct MessageGroundingResult {
    let contextBlock: String
    let sources: [MessageSource]
}

nonisolated struct RetrievedDocumentSource: Identifiable, Codable, Hashable {
    let id: String
    let documentId: String
    let documentName: String
    let chunkId: String
    let excerpt: String
    let location: String?
    let score: Double

    var messageSource: MessageSource {
        MessageSource(
            id: id,
            kind: .document,
            title: documentName,
            excerpt: excerpt,
            location: location,
            url: nil,
            score: score
        )
    }
}
