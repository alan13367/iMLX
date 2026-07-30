import XCTest
@testable import iMLX

final class IOSPlatformBoundaryTests: XCTestCase {
    func testTimerIsAvailable() {
        XCTAssertTrue(TimerService.isSupported)
    }

    func testCurrentHostProfileIsMobileClass() {
        let host = HostMemoryProfile.current
        XCTAssertEqual(host.platformClass, .mobile)
        XCTAssertGreaterThan(host.physicalMemoryGB, 0)
    }

    func testWiredMemoryIsUnavailable() {
        let weightBytes = 4 * Int(HostMemoryProfile.gigabyte)
        XCTAssertFalse(InferenceWiredMemory.isSupported)
        XCTAssertNil(InferenceWiredMemory.budgetBytes(weightBytes: weightBytes))
        XCTAssertNil(InferenceWiredMemory.budgetBytes(weightBytes: nil))
        XCTAssertNil(InferenceWiredMemory.budgetBytes(weightBytes: 0))
    }
}
