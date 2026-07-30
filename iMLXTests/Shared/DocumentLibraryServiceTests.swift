import XCTest
@testable import iMLX

final class DocumentLibraryServiceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        super.tearDown()
    }

    func testTextDocumentImportPersistsAndRetrievesGroundedContext() async throws {
        let baseDirectory = try makeDirectory()
        let sourceURL = baseDirectory.appendingPathComponent("notes.txt")
        try """
        Barcelona has a yellow heat warning tomorrow.

        Drink water and avoid strenuous activity during the hottest hours.
        """.write(to: sourceURL, atomically: true, encoding: .utf8)

        let service = DocumentLibraryService(baseDirectory: baseDirectory)
        let reference = try await service.importDocument(
            from: sourceURL,
            conversationId: UUID()
        )
        let result = await service.retrieveContext(
            for: "What warning applies to Barcelona?",
            documents: [reference]
        )

        XCTAssertFalse(result.contextBlock.isEmpty)
        XCTAssertTrue(result.contextBlock.contains("yellow heat warning"))
        XCTAssertEqual(result.sources.first?.kind, .document)
        XCTAssertEqual(result.sources.first?.title, "notes")
    }

    func testDeletingConversationDocumentsRemovesPersistedIndex() async throws {
        let baseDirectory = try makeDirectory()
        let sourceURL = baseDirectory.appendingPathComponent("notes.txt")
        try "Persistent document content".write(
            to: sourceURL,
            atomically: true,
            encoding: .utf8
        )

        let conversationID = UUID()
        let service = DocumentLibraryService(baseDirectory: baseDirectory)
        let reference = try await service.importDocument(
            from: sourceURL,
            conversationId: conversationID
        )

        await service.deleteDocuments(for: conversationID)
        let result = await service.retrieveContext(
            for: "document content",
            documents: [reference]
        )
        XCTAssertTrue(result.contextBlock.isEmpty)
        XCTAssertTrue(result.sources.isEmpty)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocumentLibraryServiceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }
}
