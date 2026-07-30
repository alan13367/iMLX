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
        XCTAssertEqual(executors["timer_create"] != nil, TimerService.isSupported)
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

    func testMutationMetadataMatchesCreateTools() async {
        let service = ToolCallingService(webSearchService: WebSearchService())
        let tools = await service.enabledTools(webSearchEnabled: true, context: emptyContext)
        let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })

        XCTAssertTrue(toolsByName["calendar_create"]?.metadata.mutatesUserData == true)
        XCTAssertTrue(toolsByName["reminders_create"]?.metadata.mutatesUserData == true)
        XCTAssertEqual(
            toolsByName["timer_create"]?.metadata.mutatesUserData,
            TimerService.isSupported ? true : nil
        )
        XCTAssertFalse(toolsByName["calendar_brief"]?.metadata.mutatesUserData == true)
        XCTAssertFalse(toolsByName["web_search"]?.metadata.mutatesUserData == true)
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
        XCTAssertEqual(names.contains("timer_create"), TimerService.isSupported)
        XCTAssertTrue(names.contains("contacts_lookup"))
    }

    private var localToolNames: [String] {
        var names = [
            "calendar_brief",
            "calendar_create",
            "current_datetime",
            "reminders_brief",
            "reminders_create",
            "contacts_lookup"
        ]
        if TimerService.isSupported {
            names.insert("timer_create", at: names.count - 1)
        }
        return names
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
