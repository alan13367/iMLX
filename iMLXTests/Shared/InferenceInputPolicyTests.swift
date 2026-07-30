import XCTest
@testable import iMLX

final class InferenceInputPolicyTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories = []
        super.tearDown()
    }

    func testSpeechChunksAreBoundedAndWhitespaceNormalized() {
        let chunks = InferenceInputPolicy.speechChunks(
            for: "  First sentence.   Second sentence!  ",
            maximumInputCharacters: 1_000,
            maximumChunks: 4
        )

        XCTAssertEqual(chunks, ["First sentence. Second sentence"])
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 220 })
    }

    func testSpeechChunksRespectMaximumChunkCount() {
        let longWords = Array(repeating: String(repeating: "a", count: 90), count: 10)
            .joined(separator: " ")
        let chunks = InferenceInputPolicy.speechChunks(
            for: longWords,
            maximumInputCharacters: 2_000,
            maximumChunks: 2
        )

        XCTAssertEqual(chunks.count, 2)
    }

    func testVisionDetectionRecognizesVisionConfigAndKnownModelType() throws {
        let visionConfigDirectory = try makeDirectory()
        try #"{"vision_config":{"hidden_size":1024}}"#
            .write(
                to: visionConfigDirectory.appendingPathComponent("config.json"),
                atomically: true,
                encoding: .utf8
            )
        XCTAssertTrue(
            InferenceInputPolicy.modelConfigurationSupportsVision(in: visionConfigDirectory)
        )

        let modelTypeDirectory = try makeDirectory()
        try #"{"model_type":"qwen3_5"}"#
            .write(
                to: modelTypeDirectory.appendingPathComponent("config.json"),
                atomically: true,
                encoding: .utf8
            )
        XCTAssertTrue(
            InferenceInputPolicy.modelConfigurationSupportsVision(in: modelTypeDirectory)
        )
    }

    func testVisionDetectionFailsClosedForMissingOrMalformedConfig() throws {
        let directory = try makeDirectory()
        XCTAssertFalse(InferenceInputPolicy.modelConfigurationSupportsVision(in: directory))

        try "not-json".write(
            to: directory.appendingPathComponent("config.json"),
            atomically: true,
            encoding: .utf8
        )
        XCTAssertFalse(InferenceInputPolicy.modelConfigurationSupportsVision(in: directory))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("InferenceInputPolicyTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        temporaryDirectories.append(directory)
        return directory
    }
}
