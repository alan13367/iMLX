import XCTest
@testable import iMLX

final class SpeechAssetServiceTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeechAssetServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testSpeechAssetStatusInitializedLocales() async {
        let service = SpeechAssetService(assetsDirectory: temporaryDirectory)
        let status = await service.status()
        XCTAssertFalse(status.hasVoiceAssets)
        XCTAssertTrue(status.activatedLocales.isEmpty)
    }

    func testPrepareAssetsMarksOnlyRequestedLocaleReady() async throws {
        SpeechAssetURLProtocol.responseData = Self.validSafeTensorsData()
        let service = SpeechAssetService(
            assetsDirectory: temporaryDirectory,
            session: Self.mockSession()
        )

        let spanishStatus = try await service.prepareAssets(for: .spanish)
        XCTAssertTrue(spanishStatus.isReady(for: .spanish))
        XCTAssertFalse(spanishStatus.isReady(for: .english))
        XCTAssertFalse(spanishStatus.isReady(for: .simplifiedChinese))
        let spanishLocations = await service.fileLocations(for: .spanish)
        let englishLocations = await service.fileLocations(for: .english)
        let chineseLocations = await service.fileLocations(for: .simplifiedChinese)
        XCTAssertNotNil(spanishLocations)
        XCTAssertNil(englishLocations)
        XCTAssertNil(chineseLocations)

        let chineseStatus = try await service.prepareAssets(for: .simplifiedChinese)
        XCTAssertTrue(chineseStatus.isReady(for: .spanish))
        XCTAssertTrue(chineseStatus.isReady(for: .simplifiedChinese))
        XCTAssertFalse(chineseStatus.isReady(for: .english))
    }

    func testPersistedLocaleStateStillRequiresVoiceFile() async throws {
        let stateURL = temporaryDirectory.appendingPathComponent(Constants.Storage.speechAssetsStateFilename)
        let stateData = #"{"activatedLocales":["es"]}"#.data(using: .utf8)!
        try stateData.write(to: stateURL)

        let service = SpeechAssetService(assetsDirectory: temporaryDirectory)
        let status = await service.status()
        let spanishLocations = await service.fileLocations(for: .spanish)

        XCTAssertFalse(status.isReady(for: .spanish))
        XCTAssertTrue(status.activatedLocales.isEmpty)
        XCTAssertNil(spanishLocations)
    }

    private static func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SpeechAssetURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private static func validSafeTensorsData() -> Data {
        let header = #"{"weight":{"dtype":"F32","shape":[1],"data_offsets":[0,4]}}"#
        var data = Data()
        var headerLength = UInt64(header.utf8.count).littleEndian
        withUnsafeBytes(of: &headerLength) { data.append(contentsOf: $0) }
        data.append(header.data(using: .utf8)!)
        data.append(contentsOf: [0, 0, 0, 0])
        return data
    }
}

private final class SpeechAssetURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responseData = Data()

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
