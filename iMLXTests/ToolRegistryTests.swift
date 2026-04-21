import XCTest
@testable import iMLX

final class ToolRegistryTests: XCTestCase {
    func testWebSearchToolIsAvailableWhenToggleIsOn() async {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let tools = await service.enabledTools(webSearchEnabled: true)

        XCTAssertEqual(tools.map(\.name), ["web_search"])
    }

    func testNoToolsAreAvailableWhenToggleIsOff() async {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let tools = await service.enabledTools(webSearchEnabled: false)

        XCTAssertTrue(tools.isEmpty)
    }

    func testExecutorRegistryContainsWebSearchExecutor() async {
        let service = ToolCallingService(webSearchService: WebSearchService())

        let executors = await service.executors()

        XCTAssertNotNil(executors["web_search"])
    }
}
