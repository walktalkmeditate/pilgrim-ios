import XCTest
import CryptoKit
@testable import Pilgrim

final class SealHashComputerTests: XCTestCase {

    func testEmptyRoute_producesConsistentHash() {
        let hash = SealHashComputer.computeHash(
            routePoints: [],
            distance: 0,
            activeDuration: 0,
            meditateDuration: 0,
            talkDuration: 0,
            startDate: "2026-03-19T10:00:00Z"
        )
        XCTAssertEqual(hash.count, 64)
        let hash2 = SealHashComputer.computeHash(
            routePoints: [],
            distance: 0,
            activeDuration: 0,
            meditateDuration: 0,
            talkDuration: 0,
            startDate: "2026-03-19T10:00:00Z"
        )
        XCTAssertEqual(hash, hash2)
    }

    func testKnownInput_matchesWorkerOutput() {
        // Pre-computed from the TypeScript worker (Node.js crypto):
        // Input: "35.68100,139.76700|5000|3600|600|300|2026-03-19T10:00:00Z"
        let hash = SealHashComputer.computeHash(
            routePoints: [(lat: 35.681, lon: 139.767)],
            distance: 5000,
            activeDuration: 3600,
            meditateDuration: 600,
            talkDuration: 300,
            startDate: "2026-03-19T10:00:00Z"
        )
        XCTAssertEqual(hash, "df938304dc11bf893d38df12738f9e8b6a81353f56d534a371e16d84a89cad1f")
    }

    func testHexToBytes_roundtrip() {
        let hex = "ab01ff"
        let bytes = SealHashComputer.hexToBytes(hex)
        XCTAssertEqual(bytes, [0xAB, 0x01, 0xFF])
    }

    func testRouteFormatting_fiveDecimalPlaces() {
        let hash1 = SealHashComputer.computeHash(
            routePoints: [(lat: 35.681, lon: 139.767)],
            distance: 0, activeDuration: 0, meditateDuration: 0, talkDuration: 0,
            startDate: "2026-01-01T00:00:00Z"
        )
        let hash2 = SealHashComputer.computeHash(
            routePoints: [(lat: 35.68100, lon: 139.76700)],
            distance: 0, activeDuration: 0, meditateDuration: 0, talkDuration: 0,
            startDate: "2026-01-01T00:00:00Z"
        )
        XCTAssertEqual(hash1, hash2)
    }

    func testFormatNumber_integersMatchJS() {
        // JS: String(5000) → "5000", String(0) → "0"
        XCTAssertEqual(SealHashComputer.formatNumber(5000.0), "5000")
        XCTAssertEqual(SealHashComputer.formatNumber(0.0), "0")
        XCTAssertEqual(SealHashComputer.formatNumber(3600.0), "3600")
    }

    func testFormatNumber_decimalsMatchJS() {
        // JS: String(3600.5) → "3600.5"
        XCTAssertEqual(SealHashComputer.formatNumber(3600.5), "3600.5")
    }
}
