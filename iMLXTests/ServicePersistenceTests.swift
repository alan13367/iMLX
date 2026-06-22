import XCTest
@testable import iMLX

@MainActor
final class ServicePersistenceTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        super.tearDown()
    }

    func testConversationServiceRoundTripsAndDeletesConversation() throws {
        let directory = try makeDirectory()
        let service = ConversationService(conversationsDirectory: directory)
        let conversation = Conversation(title: "Persisted conversation")

        service.save(conversation)

        XCTAssertEqual(service.load(id: conversation.id)?.title, conversation.title)
        XCTAssertEqual(service.listAll().map(\.id), [conversation.id])

        service.delete(id: conversation.id)
        XCTAssertNil(service.load(id: conversation.id))
    }

    func testManifestServicePersistsEntriesAcrossInstances() throws {
        let directory = try makeDirectory()
        let manifestURL = directory.appendingPathComponent("manifest.json")
        let service = ManifestService(manifestURL: manifestURL)

        service.addDownloaded(
            modelId: "model-id",
            displayName: "Model",
            huggingFaceId: "owner/model",
            localPath: "/tmp/model",
            sizeOnDiskBytes: 42
        )

        let restored = ManifestService(manifestURL: manifestURL)
        XCTAssertTrue(restored.isDownloaded(modelId: "model-id"))
        XCTAssertEqual(restored.getEntry(for: "model-id")?.sizeOnDiskBytes, 42)
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ServicePersistenceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }
}
