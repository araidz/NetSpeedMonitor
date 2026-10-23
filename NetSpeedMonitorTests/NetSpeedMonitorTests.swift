import XCTest
@testable import NetSpeedMonitor

final class RateFormatTests: XCTestCase {
    private let mib = 1024.0 * 1024.0

    func testMegabytesAreBinary() {
        let format = RateFormat()
        XCTAssertEqual(format.compact(12.345 * mib), "12.3")
        XCTAssertEqual(format.compact(0.5 * mib), "0.50")
        XCTAssertEqual(format.full(150 * mib), "150 MB/s")
    }

    func testMegabitsAreDecimal() {
        // 12.5 MB (decimal) per second is a "100 Mbps" plan.
        XCTAssertEqual(RateFormat(unit: .megabits).full(12_500_000), "100 Mbps")
    }

    func testAutoScaleUsesKBelowOneMega() {
        let format = RateFormat(autoScale: true)
        XCTAssertEqual(format.compact(512 * 1024), "512K")
        XCTAssertEqual(format.compact(2 * mib), "2.00M")
        XCTAssertEqual(format.full(3 * 1024), "3.00 KB/s")
        XCTAssertEqual(RateFormat(unit: .megabits, autoScale: true).full(1_000), "8.00 Kbps")
    }
}

final class ParserTests: XCTestCase {
    func testSpeedTestConvertsBitsToBytes() throws {
        let json = #"{"dl_throughput": 800000000, "ul_throughput": 80000000, "responsiveness": 1234, "other": 1}"#
        let result = try SpeedTest.parse(Data(json.utf8))
        XCTAssertEqual(result.downloadBytesPerSec, 100_000_000)
        XCTAssertEqual(result.uploadBytesPerSec, 10_000_000)
        XCTAssertEqual(result.responsiveness, 1234)
    }

    func testNettopKeepsOnlyTheDeltaBlock() {
        let output = """
        ,bytes_in,bytes_out,
        com.apple.Safar.1438,999999,999999,
        ,bytes_in,bytes_out,
        com.apple.Safar.1438,5156,5657,
        launchd.1,0,0,
        garbage line
        """
        XCTAssertEqual(AppTraffic.parse(Data(output.utf8)), [
            .init(name: "com.apple.Safar", pid: 1438, downBytes: 5156, upBytes: 5657),
            .init(name: "launchd", pid: 1, downBytes: 0, upBytes: 0),
        ])
    }
}
