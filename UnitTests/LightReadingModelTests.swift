import XCTest
@testable import Pilgrim

final class LightReadingModelTests: XCTestCase {

    // MARK: - Tier Comparable

    func testTierOrderingByRarity() {
        XCTAssertLessThan(LightReading.Tier.lunarEclipse, .supermoon)
        XCTAssertLessThan(LightReading.Tier.supermoon, .seasonalMarker)
        XCTAssertLessThan(LightReading.Tier.seasonalMarker, .meteorShowerPeak)
        XCTAssertLessThan(LightReading.Tier.meteorShowerPeak, .fullMoon)
        XCTAssertLessThan(LightReading.Tier.fullMoon, .newMoon)
        XCTAssertLessThan(LightReading.Tier.newMoon, .deepNight)
        XCTAssertLessThan(LightReading.Tier.deepNight, .sunriseSunset)
        XCTAssertLessThan(LightReading.Tier.sunriseSunset, .goldenHour)
        XCTAssertLessThan(LightReading.Tier.goldenHour, .twilight)
        XCTAssertLessThan(LightReading.Tier.twilight, .moonPhase)
        XCTAssertLessThan(LightReading.Tier.moonPhase, .daylight)
    }

    // MARK: - stableSeed

    func testStableSeedFromFixedUUID() {
        let uuid = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!
        let seed1 = LightReading.stableSeed(from: uuid)
        let seed2 = LightReading.stableSeed(from: uuid)
        XCTAssertEqual(seed1, seed2, "Same UUID must always produce same seed")
    }

    func testStableSeedKnownValue() {
        // The UUID bytes are known: 12 34 56 78 12 34 56 78 ...
        let uuid = UUID(uuidString: "12345678-1234-5678-1234-567812345678")!
        let seed = LightReading.stableSeed(from: uuid)
        // First 8 bytes packed big-endian: 0x12 34 56 78 12 34 56 78
        let expected: UInt64 = 0x1234_5678_1234_5678
        XCTAssertEqual(seed, expected)
    }

    func testStableSeedDifferentUUIDsDifferSeeds() {
        let uuid1 = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        let uuid2 = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        XCTAssertNotEqual(LightReading.stableSeed(from: uuid1), LightReading.stableSeed(from: uuid2))
    }

    // MARK: - SeededGenerator

    func testSeededGeneratorDeterministic() {
        var rng1 = SeededGenerator(seed: 42)
        var rng2 = SeededGenerator(seed: 42)
        for _ in 0..<10 {
            XCTAssertEqual(rng1.next(), rng2.next())
        }
    }

    func testSeededGeneratorDifferentSeedsDiffer() {
        var rng1 = SeededGenerator(seed: 42)
        var rng2 = SeededGenerator(seed: 43)
        XCTAssertNotEqual(rng1.next(), rng2.next())
    }
}
