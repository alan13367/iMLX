import Foundation
import XCTest
@testable import iMLX

final class PlatformCompatibilityTests: XCTestCase {
    func testAvailableMemoryEstimateIsPositiveAndBounded() throws {
        #if os(macOS)
        let available = try XCTUnwrap(SystemMemory.availableBytes())
        let physical = ProcessInfo.processInfo.physicalMemory

        XCTAssertGreaterThan(available, 0)
        XCTAssertLessThanOrEqual(available, physical)
        #else
        throw XCTSkip("macOS host-memory accounting is not exercised in the iOS simulator.")
        #endif
    }

    func testTimerAvailabilityMatchesPlatformSupport() {
        #if canImport(AlarmKit)
        XCTAssertTrue(TimerService.isSupported)
        #else
        XCTAssertFalse(TimerService.isSupported)
        #endif
    }
}
