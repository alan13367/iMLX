import Foundation
import XCTest
@testable import iMLX

final class AdditionalModelDiscoveryTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryDirectory)
        temporaryDirectory = nil
    }

    func testDiscoversDirectMLXModelFolder() throws {
        let modelDirectory = temporaryDirectory.appendingPathComponent(
            "My-Qwen3-1.7B-4bit",
            isDirectory: true
        )
        try makeModel(
            at: modelDirectory,
            config: [
                "model_type": "qwen3",
                "quantization": ["bits": 4, "group_size": 64]
            ]
        )

        let discovered = AdditionalModelDiscovery.discoverModels(
            in: temporaryDirectory,
            curatedModels: []
        )

        let model = try XCTUnwrap(discovered.first?.model)
        XCTAssertEqual(discovered.count, 1)
        XCTAssertEqual(model.displayName, "My-Qwen3-1.7B-4bit")
        XCTAssertEqual(model.parameterCount, "1.7B")
        XCTAssertEqual(model.quantization, "4-bit")
        XCTAssertEqual(model.family, .qwen3)
        XCTAssertEqual(
            model.localURL?.resolvingSymlinksInPath(),
            modelDirectory.resolvingSymlinksInPath()
        )
        XCTAssertTrue(model.isDownloaded)
    }

    func testDiscoversOwnerRepositoryLayout() throws {
        let modelDirectory = temporaryDirectory
            .appendingPathComponent("mlx-community", isDirectory: true)
            .appendingPathComponent("Example-Vision-2B-8bit", isDirectory: true)
        try makeModel(
            at: modelDirectory,
            config: [
                "_name_or_path": "mlx-community/Example-Vision-2B-8bit",
                "model_type": "example_vl",
                "vision_config": [:],
                "quantization_config": ["bits": 8]
            ]
        )
        try Data("{}".utf8).write(
            to: modelDirectory.appendingPathComponent("processor_config.json")
        )

        let discovered = AdditionalModelDiscovery.discoverModels(
            in: temporaryDirectory,
            curatedModels: []
        )

        let model = try XCTUnwrap(discovered.first?.model)
        XCTAssertEqual(discovered.count, 1)
        XCTAssertEqual(model.huggingFaceId, "mlx-community/Example-Vision-2B-8bit")
        XCTAssertEqual(model.parameterCount, "2B")
        XCTAssertEqual(model.quantization, "8-bit")
        XCTAssertTrue(model.supportsVision)
    }

    func testMatchesCuratedModelWithoutCreatingDuplicateMetadata() throws {
        let curated = ModelInfo(
            id: "known-model",
            displayName: "Known Model",
            huggingFaceId: "owner/Known-Model-4bit",
            parameterCount: "1B",
            quantization: "4-bit",
            estimatedSizeGB: 1,
            minDeviceRAM: 8,
            family: .custom,
            logoName: "",
            supportsThinking: false,
            supportsVision: false,
            prefersThinkingEnabled: false
        )
        let modelDirectory = temporaryDirectory.appendingPathComponent(
            "Known-Model-4bit",
            isDirectory: true
        )
        try makeModel(at: modelDirectory, config: ["model_type": "example"])

        let discovered = AdditionalModelDiscovery.discoverModels(
            in: temporaryDirectory,
            curatedModels: [curated]
        )

        let result = try XCTUnwrap(discovered.first)
        XCTAssertEqual(result.model.id, curated.id)
        XCTAssertEqual(result.model.displayName, curated.displayName)
        XCTAssertTrue(result.matchesCuratedModel)
        XCTAssertEqual(
            result.directoryURL.resolvingSymlinksInPath(),
            modelDirectory.resolvingSymlinksInPath()
        )
    }

    func testIgnoresFoldersWithoutConfigOrSafetensors() throws {
        let missingWeights = temporaryDirectory.appendingPathComponent(
            "Missing-Weights",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: missingWeights, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: missingWeights.appendingPathComponent("config.json"))

        let missingConfig = temporaryDirectory.appendingPathComponent(
            "Missing-Config",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: missingConfig, withIntermediateDirectories: true)
        try Data([0]).write(to: missingConfig.appendingPathComponent("model.safetensors"))

        XCTAssertTrue(
            AdditionalModelDiscovery.discoverModels(
                in: temporaryDirectory,
                curatedModels: []
            ).isEmpty
        )
    }

    private func makeModel(at directory: URL, config: [String: Any]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let configData = try JSONSerialization.data(withJSONObject: config)
        try configData.write(to: directory.appendingPathComponent("config.json"))
        try Data(repeating: 1, count: 32).write(
            to: directory.appendingPathComponent("model.safetensors")
        )
    }
}
