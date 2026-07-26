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

    func testCurrentHostProfileMatchesBuildPlatform() {
        let host = HostMemoryProfile.current

        #if os(macOS)
        XCTAssertEqual(host.platformClass, .desktop)
        #else
        XCTAssertEqual(host.platformClass, .mobile)
        #endif
        XCTAssertGreaterThan(host.physicalMemoryGB, 0)
    }

    func testDesktopHeadroomThresholdsScaleWithPhysicalMemory() {
        let smallMac = HostMemoryProfile(
            platformClass: .desktop,
            physicalMemoryBytes: 8 * HostMemoryProfile.gigabyte
        )
        let largeMac = HostMemoryProfile(
            platformClass: .desktop,
            physicalMemoryBytes: 64 * HostMemoryProfile.gigabyte
        )

        XCTAssertLessThan(smallMac.severeHeadroomBytes, largeMac.severeHeadroomBytes)
        XCTAssertLessThan(smallMac.constrainedHeadroomBytes, largeMac.constrainedHeadroomBytes)
        XCTAssertLessThan(smallMac.abundantHeadroomBytes, largeMac.abundantHeadroomBytes)
        XCTAssertLessThan(smallMac.severeHeadroomBytes, smallMac.constrainedHeadroomBytes)
        XCTAssertLessThan(smallMac.constrainedHeadroomBytes, smallMac.abundantHeadroomBytes)
    }

    func testDesktopKeepsFullKVCacheWhileMobileWindowsIt() {
        let mac = HostMemoryProfile(
            platformClass: .desktop,
            physicalMemoryBytes: 32 * HostMemoryProfile.gigabyte
        )
        let phone = HostMemoryProfile(
            platformClass: .mobile,
            physicalMemoryBytes: 8 * HostMemoryProfile.gigabyte
        )

        XCTAssertNil(mac.kvWindowTokenLimit)
        XCTAssertEqual(phone.kvWindowTokenLimit, 8_192)
        XCTAssertGreaterThan(mac.quantizedKVStartTokens, phone.quantizedKVStartTokens)
    }

    func testWiredMemoryBudgetIsOnlyRequestedWhereItIsSupported() {
        let weightBytes = 4 * Int(HostMemoryProfile.gigabyte)
        let budget = InferenceWiredMemory.budgetBytes(weightBytes: weightBytes)

        #if os(macOS)
        XCTAssertGreaterThan(budget ?? 0, weightBytes)
        #else
        XCTAssertNil(budget)
        #endif
        XCTAssertNil(InferenceWiredMemory.budgetBytes(weightBytes: nil))
        XCTAssertNil(InferenceWiredMemory.budgetBytes(weightBytes: 0))
    }
}
