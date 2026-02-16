import XCTest
@testable import RamBar

final class ByteFormattingTests: XCTestCase {
    func testGigabyteFormatting() {
        let bytes: UInt64 = 12_400_000_000 // ~11.55 GB
        let result = bytes.formattedBytes
        XCTAssertTrue(result.hasSuffix("GB"))
    }

    func testMegabyteFormatting() {
        let bytes: UInt64 = 890_000_000 // ~849 MB
        let result = bytes.formattedBytes
        XCTAssertTrue(result.hasSuffix("MB"))
    }

    func testExactOneGB() {
        let bytes: UInt64 = 1_073_741_824 // exactly 1 GiB
        XCTAssertEqual(bytes.formattedBytes, "1.0 GB")
    }

    func testSmallMB() {
        let bytes: UInt64 = 52_428_800 // 50 MiB
        XCTAssertEqual(bytes.formattedBytes, "50 MB")
    }

    func testZeroBytes() {
        let bytes: UInt64 = 0
        XCTAssertEqual(bytes.formattedBytes, "0 MB")
    }
}
