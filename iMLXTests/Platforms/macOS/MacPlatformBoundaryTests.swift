import Foundation
import XCTest
@testable import iMLX

final class MacPlatformBoundaryTests: XCTestCase {
    func testAvailableMemoryEstimateIsPositiveAndBounded() throws {
        let available = try XCTUnwrap(SystemMemory.availableBytes())
        let physical = ProcessInfo.processInfo.physicalMemory

        XCTAssertGreaterThan(available, 0)
        XCTAssertLessThanOrEqual(available, physical)
    }

    func testTimerIsUnavailable() {
        XCTAssertFalse(TimerService.isSupported)
    }

    func testCurrentHostProfileIsDesktopClass() {
        let host = HostMemoryProfile.current
        XCTAssertEqual(host.platformClass, .desktop)
        XCTAssertGreaterThan(host.physicalMemoryGB, 0)
    }

    func testWiredMemoryBudgetIncludesHeadroom() {
        let weightBytes = 4 * Int(HostMemoryProfile.gigabyte)
        let budget = InferenceWiredMemory.budgetBytes(weightBytes: weightBytes)

        XCTAssertTrue(InferenceWiredMemory.isSupported)
        XCTAssertGreaterThan(budget ?? 0, weightBytes)
        XCTAssertNil(InferenceWiredMemory.budgetBytes(weightBytes: nil))
        XCTAssertNil(InferenceWiredMemory.budgetBytes(weightBytes: 0))
    }
}
