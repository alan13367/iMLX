import XCTest
@testable import iMLX

final class ToolRegistryTests: XCTestCase {
    func testWebSearchToolIsAvailableWhenToggleIsOn() async {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let tools = await service.enabledTools(
            webSearchEnabled: true,
            context: emptyContext
        )

        XCTAssertEqual(
            tools.map(\.name),
            webEnabledToolNames
        )
    }

    func testNoToolsAreAvailableWhenToggleIsOff() async {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let tools = await service.enabledTools(
            webSearchEnabled: false,
            context: emptyContext
        )

        XCTAssertEqual(
            tools.map(\.name),
            localToolNames
        )
    }

    func testExecutorRegistryContainsWebSearchExecutor() async {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let executors = await service.executors()

        XCTAssertNotNil(executors["web_search"])
        XCTAssertNotNil(executors["document_synthesize"])
        XCTAssertNotNil(executors["calendar_brief"])
        XCTAssertNotNil(executors["calendar_create"])
        XCTAssertNotNil(executors["current_datetime"])
        XCTAssertNotNil(executors["reminders_brief"])
        XCTAssertNotNil(executors["reminders_create"])
        XCTAssertNotNil(executors["timer_create"])
        XCTAssertNotNil(executors["contacts_lookup"])
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

        XCTAssertEqual(
            tools.map(\.name),
            [
                "read_url",
            ] + webEnabledToolNames
        )
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

        XCTAssertEqual(
            tools.map(\.name),
            localToolNames
        )
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

        XCTAssertEqual(
            tools.map(\.name),
            webEnabledToolNames
        )
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

        XCTAssertEqual(
            tools.map(\.name),
            ["ocr_image_text"] + localToolNames
        )
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

        XCTAssertEqual(
            tools.map(\.name),
            ["document_synthesize"] + localToolNames
        )
    }

    func testCurrentDateTimeIsAlwaysAvailable() async {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let tools = await service.enabledTools(
            webSearchEnabled: false,
            context: emptyContext
        )

        XCTAssertTrue(tools.map(\.name).contains("current_datetime"))
    }

    func testRemindersToolsAreAvailable() async {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let tools = await service.enabledTools(
            webSearchEnabled: false,
            context: emptyContext
        )

        let names = tools.map(\.name)
        XCTAssertTrue(names.contains("reminders_brief"))
        XCTAssertTrue(names.contains("reminders_create"))
        XCTAssertTrue(names.contains("calendar_create"))
        XCTAssertTrue(names.contains("timer_create"))
        XCTAssertTrue(names.contains("contacts_lookup"))
    }

    private var localToolNames: [String] {
        [
            "calendar_brief",
            "calendar_create",
            "current_datetime",
            "reminders_brief",
            "reminders_create",
            "timer_create",
            "contacts_lookup"
        ]
    }

    private var webEnabledToolNames: [String] {
        ["web_search"] + localToolNames
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
