import XCTest
@testable import iMLX

final class HostMemoryPolicyTests: XCTestCase {
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
}
