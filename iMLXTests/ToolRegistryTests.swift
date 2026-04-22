import XCTest
@testable import iMLX

final class ToolRegistryTests: XCTestCase {
    func testWebSearchToolIsAvailableWhenToggleIsOn() async {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let tools = await service.enabledTools(
            webSearchEnabled: true,
            context: emptyContext
        )

        XCTAssertEqual(tools.map(\.name), ["web_search"])
    }

    func testNoToolsAreAvailableWhenToggleIsOff() async {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let tools = await service.enabledTools(
            webSearchEnabled: false,
            context: emptyContext
        )

        XCTAssertTrue(tools.isEmpty)
    }

    func testExecutorRegistryContainsWebSearchExecutor() async {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let executors = await service.executors()

        XCTAssertNotNil(executors["web_search"])
    }

    func testReadURLToolIsAvailableWhenSingleURLIsPresent() async {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Read https://example.com",
            attachedImages: [],
            detectedPublicURLs: [URL(string: "https://example.com")!]
        )

        let tools = await service.enabledTools(
            webSearchEnabled: true,
            context: context
        )

        XCTAssertEqual(tools.map(\.name), ["read_url", "web_search"])
    }

    func testReadURLToolIsUnavailableWhenToggleIsOff() async {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Read https://example.com",
            attachedImages: [],
            detectedPublicURLs: [URL(string: "https://example.com")!]
        )

        let tools = await service.enabledTools(
            webSearchEnabled: false,
            context: context
        )

        XCTAssertTrue(tools.isEmpty)
    }

    func testOCRToolIsAvailableWhenImagesAreAttached() async {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "What does this screenshot say?",
            attachedImages: [ChatAttachmentImage(data: Data([0x01]))],
            detectedPublicURLs: []
        )

        let tools = await service.enabledTools(
            webSearchEnabled: false,
            context: context
        )

        XCTAssertEqual(tools.map(\.name), ["ocr_image_text"])
    }

    private var emptyContext: ToolInputContext {
        ToolInputContext(
            latestUserMessage: "",
            attachedImages: [],
            detectedPublicURLs: []
        )
    }
}
