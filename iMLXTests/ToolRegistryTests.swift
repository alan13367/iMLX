import XCTest
@testable import iMLX

final class ToolRegistryTests: XCTestCase {
    func testWebSearchToolIsAvailableWhenToggleIsOn() async {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let tools = await service.enabledTools(
            webSearchEnabled: true,
            context: emptyContext
        )

        XCTAssertEqual(tools.map(\.name), ["web_search", "calendar_brief"])
    }

    func testNoToolsAreAvailableWhenToggleIsOff() async {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let tools = await service.enabledTools(
            webSearchEnabled: false,
            context: emptyContext
        )

        XCTAssertEqual(tools.map(\.name), ["calendar_brief"])
    }

    func testExecutorRegistryContainsWebSearchExecutor() async {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let executors = await service.executors()

        XCTAssertNotNil(executors["web_search"])
        XCTAssertNotNil(executors["document_synthesize"])
        XCTAssertNotNil(executors["calendar_brief"])
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

        XCTAssertEqual(tools.map(\.name), ["read_url", "web_search", "calendar_brief"])
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

        XCTAssertEqual(tools.map(\.name), ["calendar_brief"])
    }

    func testReadURLToolIsUnavailableWhenMultipleURLsArePresent() async {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Compare https://example.com and https://openai.com",
            attachedImages: [],
            detectedPublicURLs: [
                URL(string: "https://example.com")!,
                URL(string: "https://openai.com")!
            ]
        )

        let tools = await service.enabledTools(
            webSearchEnabled: true,
            context: context
        )

        XCTAssertEqual(tools.map(\.name), ["web_search", "calendar_brief"])
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

        XCTAssertEqual(tools.map(\.name), ["ocr_image_text", "calendar_brief"])
    }

    func testDocumentToolIsAvailableWhenDocumentsAreAttached() async {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let context = ToolInputContext(
            latestUserMessage: "Summarize this PDF",
            attachedImages: [],
            attachedDocuments: [sampleDocument],
            hasNewlyAttachedDocuments: true,
            detectedPublicURLs: []
        )

        let tools = await service.enabledTools(
            webSearchEnabled: false,
            context: context
        )

        XCTAssertEqual(tools.map(\.name), ["document_synthesize", "calendar_brief"])
    }

    private var emptyContext: ToolInputContext {
        ToolInputContext(
            latestUserMessage: "",
            attachedImages: [],
            detectedPublicURLs: []
        )
    }

    private var sampleDocument: ConversationDocumentReference {
        ConversationDocumentReference(
            id: "doc-1",
            displayName: "Sample",
            kind: .pdf,
            importedAt: Date(timeIntervalSince1970: 0)
        )
    }
}
