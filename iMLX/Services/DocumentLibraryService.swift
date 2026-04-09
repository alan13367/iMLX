import Foundation
import NaturalLanguage
import PDFKit

actor DocumentLibraryService {
    private struct ExtractedBlock {
        let text: String
        let location: String?
    }

    private let fileManager: FileManager
    private let documentsDirectory: URL
    private let metadataDirectory: URL
    private let indexesDirectory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        self.fileManager = fileManager
        documentsDirectory = appSupport.appendingPathComponent(Constants.Storage.documentsDirectory, isDirectory: true)
        metadataDirectory = appSupport.appendingPathComponent(Constants.Storage.documentMetadataDirectory, isDirectory: true)
        indexesDirectory = appSupport.appendingPathComponent(Constants.Storage.documentIndexesDirectory, isDirectory: true)

        try? fileManager.createDirectory(at: documentsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: indexesDirectory, withIntermediateDirectories: true)
    }

    func importDocument(from sourceURL: URL, conversationId: UUID) throws -> ConversationDocumentReference {
        let didAccess = sourceURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                sourceURL.stopAccessingSecurityScopedResource()
            }
        }

        let documentID = UUID().uuidString
        let kind = ConversationDocumentKind.from(pathExtension: sourceURL.pathExtension)
        let conversationDirectory = documentsDirectory.appendingPathComponent(conversationId.uuidString, isDirectory: true)
        try fileManager.createDirectory(at: conversationDirectory, withIntermediateDirectories: true)

        let sanitizedExtension = sourceURL.pathExtension.isEmpty ? defaultFileExtension(for: kind) : sourceURL.pathExtension.lowercased()
        let storedFilename = "\(documentID).\(sanitizedExtension)"
        let destinationURL = conversationDirectory.appendingPathComponent(storedFilename)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try? fileManager.removeItem(at: destinationURL)
        }
        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        let extractedBlocks = try extractBlocks(from: destinationURL, kind: kind)
        guard !extractedBlocks.isEmpty else {
            try? fileManager.removeItem(at: destinationURL)
            throw DocumentImportError.emptyDocument
        }

        let languageCode = detectLanguageCode(in: extractedBlocks.map(\.text).joined(separator: "\n\n"))
        let chunks = buildChunks(
            documentID: documentID,
            blocks: extractedBlocks,
            languageCode: languageCode
        )
        guard !chunks.isEmpty else {
            try? fileManager.removeItem(at: destinationURL)
            throw DocumentImportError.emptyDocument
        }

        let displayName = sourceURL.deletingPathExtension().lastPathComponent
        let byteCount = (try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let record = DocumentRecord(
            id: documentID,
            conversationId: conversationId,
            displayName: displayName.isEmpty ? sourceURL.lastPathComponent : displayName,
            originalFilename: sourceURL.lastPathComponent,
            kind: kind,
            storedFilename: storedFilename,
            byteCount: byteCount,
            chunkCount: chunks.count,
            createdAt: Date(),
            updatedAt: Date()
        )
        let index = DocumentIndex(documentId: documentID, languageCode: languageCode, chunks: chunks)

        try persist(record: record, index: index)

        return ConversationDocumentReference(
            id: documentID,
            displayName: record.displayName,
            kind: kind,
            importedAt: record.createdAt
        )
    }

    func removeDocument(id: String) {
        guard let record = loadRecord(id: id) else { return }
        let fileURL = documentsDirectory
            .appendingPathComponent(record.conversationId.uuidString, isDirectory: true)
            .appendingPathComponent(record.storedFilename)

        try? fileManager.removeItem(at: metadataURL(for: id))
        try? fileManager.removeItem(at: indexURL(for: id))
        try? fileManager.removeItem(at: fileURL)
    }

    func deleteDocuments(for conversationId: UUID) {
        let records = allRecords().filter { $0.conversationId == conversationId }
        for record in records {
            removeDocument(id: record.id)
        }
        let conversationDirectory = documentsDirectory.appendingPathComponent(conversationId.uuidString, isDirectory: true)
        try? fileManager.removeItem(at: conversationDirectory)
    }

    func retrieveContext(for query: String, documents: [ConversationDocumentReference]) -> DocumentRetrievalResult {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty, !documents.isEmpty else {
            return DocumentRetrievalResult(contextBlock: "", sources: [])
        }

        let queryVector = embedding(for: trimmedQuery, languageCode: detectLanguageCode(in: trimmedQuery))
        var candidates: [(source: RetrievedDocumentSource, text: String)] = []
        let shouldUseOverview = wantsDocumentOverview(for: trimmedQuery)

        for reference in documents {
            guard let index = loadIndex(id: reference.id) else { continue }

            if shouldUseOverview {
                candidates.append(contentsOf: overviewCandidates(for: reference, index: index))
                continue
            }

            for chunk in index.chunks {
                let semanticScore = score(queryVector: queryVector, chunkVector: chunk.vector)
                let lexicalScore = lexicalSimilarity(query: trimmedQuery, text: chunk.text)
                let score = semanticScore > 0 ? (semanticScore * 0.85) + (lexicalScore * 0.15) : lexicalScore
                guard score > 0 else { continue }

                let excerpt = compactExcerpt(from: chunk.text)
                let source = RetrievedDocumentSource(
                    id: "\(reference.id)-\(chunk.id)",
                    documentId: reference.id,
                    documentName: reference.displayName,
                    chunkId: chunk.id,
                    excerpt: excerpt,
                    location: chunk.location,
                    score: score
                )
                candidates.append((source, chunk.text))
            }
        }

        if candidates.isEmpty {
            for reference in documents {
                guard let index = loadIndex(id: reference.id) else { continue }
                candidates.append(contentsOf: overviewCandidates(for: reference, index: index))
            }
        }

        let ranked = candidates
            .sorted { lhs, rhs in
                if lhs.source.score == rhs.source.score {
                    return lhs.source.documentName.localizedCaseInsensitiveCompare(rhs.source.documentName) == .orderedAscending
                }
                return lhs.source.score > rhs.source.score
            }
            .prefix(Constants.RAG.maxRetrievedChunks)

        var contextSections: [String] = []
        var sources: [RetrievedDocumentSource] = []
        var usedCharacters = 0

        for candidate in ranked {
            let headerParts = [
                "Source: \(candidate.source.documentName)",
                candidate.source.location
            ]
            .compactMap { $0 }
            .joined(separator: " | ")
            let section = "\(headerParts)\n\(candidate.text)"
            if usedCharacters + section.count > Constants.RAG.maxContextCharacters, !contextSections.isEmpty {
                break
            }
            contextSections.append(section)
            sources.append(candidate.source)
            usedCharacters += section.count
        }

        let contextBlock: String
        if contextSections.isEmpty {
            contextBlock = ""
        } else {
            contextBlock = """
            The user attached local documents for this conversation. Treat the excerpts below as readable document content you can use directly.

            If the user asks about "this PDF", "this file", or "the attached document", they mean the excerpts below. Do not claim that you cannot access the file when excerpts are present.

            Use the document excerpts below when they are relevant to the user's request. If the excerpts do not answer the question, say so plainly.

            \(contextSections.joined(separator: "\n\n---\n\n"))
            """
        }

        return DocumentRetrievalResult(contextBlock: contextBlock, sources: sources)
    }

    private func persist(record: DocumentRecord, index: DocumentIndex) throws {
        let recordData = try encoder.encode(record)
        let indexData = try encoder.encode(index)
        try recordData.write(to: metadataURL(for: record.id), options: .atomic)
        try indexData.write(to: indexURL(for: index.documentId), options: .atomic)
    }

    private func loadRecord(id: String) -> DocumentRecord? {
        guard let data = try? Data(contentsOf: metadataURL(for: id)) else { return nil }
        return try? decoder.decode(DocumentRecord.self, from: data)
    }

    private func loadIndex(id: String) -> DocumentIndex? {
        guard let data = try? Data(contentsOf: indexURL(for: id)) else { return nil }
        return try? decoder.decode(DocumentIndex.self, from: data)
    }

    private func allRecords() -> [DocumentRecord] {
        guard let urls = try? fileManager.contentsOfDirectory(at: metadataDirectory, includingPropertiesForKeys: nil) else {
            return []
        }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? decoder.decode(DocumentRecord.self, from: data)
            }
    }

    private func metadataURL(for id: String) -> URL {
        metadataDirectory.appendingPathComponent(id).appendingPathExtension("json")
    }

    private func indexURL(for id: String) -> URL {
        indexesDirectory.appendingPathComponent(id).appendingPathExtension("json")
    }

    private func defaultFileExtension(for kind: ConversationDocumentKind) -> String {
        switch kind {
        case .pdf:
            "pdf"
        case .csv:
            "csv"
        case .text:
            "txt"
        }
    }

    private func extractBlocks(from url: URL, kind: ConversationDocumentKind) throws -> [ExtractedBlock] {
        switch kind {
        case .pdf:
            return try extractPDFBlocks(from: url)
        case .csv:
            return try extractCSVBlocks(from: url)
        case .text:
            return try extractTextBlocks(from: url)
        }
    }

    private func extractPDFBlocks(from url: URL) throws -> [ExtractedBlock] {
        guard let document = PDFDocument(url: url) else {
            throw DocumentImportError.unreadable
        }

        let blocks = (0..<document.pageCount).compactMap { pageIndex -> ExtractedBlock? in
            guard let page = document.page(at: pageIndex) else { return nil }
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !text.isEmpty else { return nil }
            return ExtractedBlock(text: normalizeWhitespace(text), location: "Page \(pageIndex + 1)")
        }

        if blocks.isEmpty {
            throw DocumentImportError.emptyDocument
        }

        return blocks
    }

    private func extractCSVBlocks(from url: URL) throws -> [ExtractedBlock] {
        let text = try decodeText(from: url)
        let rows = text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !rows.isEmpty else {
            throw DocumentImportError.emptyDocument
        }

        let header = splitCSVRow(rows[0])
        let dataRows = rows.dropFirst()

        if dataRows.isEmpty {
            return [ExtractedBlock(text: normalizeWhitespace(rows[0]), location: "Header")]
        }

        return dataRows.enumerated().compactMap { index, row in
            let columns = splitCSVRow(row)
            let pairs = zipLongest(header, columns).compactMap { headerValue, rowValue -> String? in
                let trimmedValue = rowValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedValue.isEmpty else { return nil }
                let trimmedHeader = headerValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmedHeader.isEmpty {
                    return trimmedValue
                }
                return "\(trimmedHeader): \(trimmedValue)"
            }

            let text = pairs.joined(separator: "; ")
            guard !text.isEmpty else { return nil }
            return ExtractedBlock(text: normalizeWhitespace(text), location: "Row \(index + 2)")
        }
    }

    private func extractTextBlocks(from url: URL) throws -> [ExtractedBlock] {
        let text = try decodeText(from: url)
        let paragraphs = text
            .components(separatedBy: CharacterSet.newlines)
            .map { normalizeWhitespace($0) }
            .filter { !$0.isEmpty }

        guard !paragraphs.isEmpty else {
            throw DocumentImportError.emptyDocument
        }

        return paragraphs.map { ExtractedBlock(text: $0, location: nil) }
    }

    private func decodeText(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let encodings: [String.Encoding] = [.utf8, .unicode, .utf16, .ascii, .isoLatin1]
        for encoding in encodings {
            if let string = String(data: data, encoding: encoding) {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        throw DocumentImportError.unreadable
    }

    private func buildChunks(
        documentID: String,
        blocks: [ExtractedBlock],
        languageCode: String?
    ) -> [DocumentChunk] {
        var chunks: [DocumentChunk] = []
        var ordinal = 0

        for block in blocks {
            let words = block.text.split(whereSeparator: \.isWhitespace)
            guard !words.isEmpty else { continue }

            let step = max(Constants.RAG.chunkWordTarget - Constants.RAG.chunkWordOverlap, 1)
            var startIndex = 0

            while startIndex < words.count {
                let endIndex = min(startIndex + Constants.RAG.chunkWordTarget, words.count)
                let chunkWords = words[startIndex..<endIndex]
                let text = chunkWords.joined(separator: " ")
                let normalizedText = normalizeWhitespace(text)
                if !normalizedText.isEmpty {
                    chunks.append(
                        DocumentChunk(
                            id: "\(documentID)-chunk-\(ordinal)",
                            documentId: documentID,
                            ordinal: ordinal,
                            text: normalizedText,
                            location: block.location,
                            vector: embedding(for: normalizedText, languageCode: languageCode)
                        )
                    )
                    ordinal += 1
                }

                if endIndex == words.count {
                    break
                }
                startIndex += step
            }
        }

        return chunks
    }

    private func detectLanguageCode(in text: String) -> String? {
        guard let language = NLLanguageRecognizer.dominantLanguage(for: text) else {
            return nil
        }
        return language.rawValue
    }

    private func embedding(for text: String, languageCode: String?) -> [Double]? {
        let normalizedText = normalizeWhitespace(text)
        guard !normalizedText.isEmpty else { return nil }

        let detectedLanguage = languageCode.flatMap(NLLanguage.init(rawValue:))
            ?? NLLanguageRecognizer.dominantLanguage(for: normalizedText)
            ?? .english

        if let embedding = NLEmbedding.sentenceEmbedding(for: detectedLanguage),
           let vector = embedding.vector(for: normalizedText) {
            return vector
        }

        guard detectedLanguage != .english,
              let fallbackEmbedding = NLEmbedding.sentenceEmbedding(for: .english),
              let vector = fallbackEmbedding.vector(for: normalizedText) else {
            return nil
        }

        return vector
    }

    private func score(queryVector: [Double]?, chunkVector: [Double]?) -> Double {
        guard let queryVector, let chunkVector, queryVector.count == chunkVector.count else {
            return 0
        }

        var dotProduct = 0.0
        var queryMagnitude = 0.0
        var chunkMagnitude = 0.0

        for index in queryVector.indices {
            dotProduct += queryVector[index] * chunkVector[index]
            queryMagnitude += queryVector[index] * queryVector[index]
            chunkMagnitude += chunkVector[index] * chunkVector[index]
        }

        let denominator = sqrt(queryMagnitude) * sqrt(chunkMagnitude)
        guard denominator > 0 else { return 0 }
        return max(0, dotProduct / denominator)
    }

    private func lexicalSimilarity(query: String, text: String) -> Double {
        let queryTerms = Set(tokenize(query))
        let textTerms = Set(tokenize(text))
        guard !queryTerms.isEmpty, !textTerms.isEmpty else { return 0 }
        let overlap = queryTerms.intersection(textTerms).count
        guard overlap > 0 else { return 0 }
        return Double(overlap) / Double(queryTerms.count)
    }

    private func tokenize(_ text: String) -> [String] {
        normalizeWhitespace(text)
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count > 2 }
    }

    private func compactExcerpt(from text: String) -> String {
        let normalized = normalizeWhitespace(text)
        guard normalized.count > Constants.RAG.maxPreviewCharacters else {
            return normalized
        }
        let index = normalized.index(normalized.startIndex, offsetBy: Constants.RAG.maxPreviewCharacters)
        return String(normalized[..<index]) + "..."
    }

    private func normalizeWhitespace(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func wantsDocumentOverview(for query: String) -> Bool {
        let normalized = normalizeWhitespace(query).lowercased()
        let overviewTerms = [
            "summarize",
            "summary",
            "summery",
            "overview",
            "recap",
            "abstract",
            "gist",
            "main points",
            "key points",
            "what is this document about",
            "what is this pdf about",
            "what is this file about"
        ]
        let attachmentTerms = [
            "this pdf",
            "this document",
            "this file",
            "attached pdf",
            "attached document",
            "attached file"
        ]

        let asksForOverview = overviewTerms.contains { normalized.contains($0) }
        let referencesAttachment = attachmentTerms.contains { normalized.contains($0) }
        return asksForOverview || referencesAttachment
    }

    private func overviewCandidates(
        for reference: ConversationDocumentReference,
        index: DocumentIndex
    ) -> [(source: RetrievedDocumentSource, text: String)] {
        guard !index.chunks.isEmpty else { return [] }

        let selectedChunks = sampledOverviewChunks(from: index.chunks)
        return selectedChunks.map { chunk in
            let source = RetrievedDocumentSource(
                id: "\(reference.id)-\(chunk.id)",
                documentId: reference.id,
                documentName: reference.displayName,
                chunkId: chunk.id,
                excerpt: compactExcerpt(from: chunk.text),
                location: chunk.location,
                score: 1.0
            )
            return (source, chunk.text)
        }
    }

    private func sampledOverviewChunks(from chunks: [DocumentChunk]) -> [DocumentChunk] {
        let targetCount = min(Constants.RAG.maxRetrievedChunks, chunks.count)
        guard targetCount > 0 else { return [] }
        guard chunks.count > targetCount else { return chunks }

        var selected: [DocumentChunk] = []
        var usedOrdinals = Set<Int>()

        for position in 0..<targetCount {
            let ratio = targetCount == 1 ? 0.0 : Double(position) / Double(targetCount - 1)
            let index = min(Int(round(ratio * Double(chunks.count - 1))), chunks.count - 1)
            let chunk = chunks[index]
            if usedOrdinals.insert(chunk.ordinal).inserted {
                selected.append(chunk)
            }
        }

        if selected.count < targetCount {
            for chunk in chunks where usedOrdinals.insert(chunk.ordinal).inserted {
                selected.append(chunk)
                if selected.count == targetCount {
                    break
                }
            }
        }

        return selected.sorted { $0.ordinal < $1.ordinal }
    }

    private func splitCSVRow(_ row: String) -> [String] {
        var values: [String] = []
        var current = ""
        var isInsideQuotes = false

        for character in row {
            if character == "\"" {
                isInsideQuotes.toggle()
                continue
            }
            if character == ",", !isInsideQuotes {
                values.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }

        values.append(current)
        return values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private func zipLongest(_ left: [String], _ right: [String]) -> [(String, String)] {
        let maxCount = max(left.count, right.count)
        return (0..<maxCount).map { index in
            let leftValue = index < left.count ? left[index] : ""
            let rightValue = index < right.count ? right[index] : ""
            return (leftValue, rightValue)
        }
    }
}
