import XCTest
@testable import iMLX

final class ModelMetadataTests: XCTestCase {
  func testModelInfoDecodesLegacyJSONWithoutRuntimeMetadata() throws {
        let json = """
        {
          "id": "legacy-model",
          "displayName": "Legacy Model",
          "huggingFaceId": "example/legacy-model",
          "parameterCount": "1B",
          "quantization": "4-bit",
          "estimatedSizeGB": 1.0,
          "minDeviceRAM": 8,
          "family": "qwen3",
          "logoName": "qwen_logo",
          "supportsThinking": true,
          "supportsVision": false,
          "prefersThinkingEnabled": false,
          "isDownloaded": false
        }
        """

        let model = try JSONDecoder().decode(ModelInfo.self, from: Data(json.utf8))

    XCTAssertNil(model.localURL)
        XCTAssertFalse(model.isDownloaded)
    }

  func testCustomImlxModelRetainsExpectedRegistryMetadata() throws {
        let model = try XCTUnwrap(Constants.ModelRegistry.curatedModels.first { $0.id == "imlx-qwen3-1.7b-4bit" })

    XCTAssertEqual(model.displayName, "iMLX Qwen3 1.7B")
    XCTAssertEqual(model.huggingFaceId, "alan13367/iMLX-Qwen3-1.7B-4bit")
    XCTAssertEqual(model.family, .imlx)
    XCTAssertEqual(model.logoName, "BrandLogo")
    XCTAssertFalse(model.isDownloaded)
    XCTAssertNil(model.localURL)
    }

    func testDownloadedModelEntryDecodesLegacyManifestEntry() throws {
        let json = """
        {
          "id": "imlx-qwen3-1.7b-4bit",
          "displayName": "iMLX Qwen3 1.7B",
          "huggingFaceId": "alan13367/iMLX-Qwen3-1.7B-4bit",
          "downloadDate": "2026-04-22T12:00:00Z",
          "localPath": "imlx-qwen3-1.7b-4bit",
          "sizeOnDiskBytes": 1024
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let entry = try decoder.decode(DownloadedModelEntry.self, from: Data(json.utf8))

        XCTAssertEqual(entry.id, "imlx-qwen3-1.7b-4bit")
        XCTAssertEqual(entry.displayName, "iMLX Qwen3 1.7B")
        XCTAssertEqual(entry.huggingFaceId, "alan13367/iMLX-Qwen3-1.7B-4bit")
        XCTAssertEqual(entry.localPath, "imlx-qwen3-1.7b-4bit")
        XCTAssertEqual(entry.sizeOnDiskBytes, 1024)
    }
}
