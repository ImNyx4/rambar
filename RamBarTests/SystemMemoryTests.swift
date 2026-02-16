import XCTest
@testable import RamBar

final class SystemMemoryTests: XCTestCase {
    func testUsedPercentageCalculation() {
        let mem = SystemMemory(total: 16_000_000_000, used: 12_000_000_000, free: 4_000_000_000, pressure: .normal)
        XCTAssertEqual(mem.usedPercentage, 75)
    }

    func testUsedPercentageZeroTotal() {
        let mem = SystemMemory(total: 0, used: 0, free: 0, pressure: .normal)
        XCTAssertEqual(mem.usedPercentage, 0)
    }

    func testUsedPercentageRounding() {
        // 10/30 = 33.33...% → 33
        let mem = SystemMemory(total: 30_000_000_000, used: 10_000_000_000, free: 20_000_000_000, pressure: .normal)
        XCTAssertEqual(mem.usedPercentage, 33)
    }

    func testZeroMemory() {
        let mem = SystemMemory.zero
        XCTAssertEqual(mem.total, 0)
        XCTAssertEqual(mem.usedPercentage, 0)
    }
}
