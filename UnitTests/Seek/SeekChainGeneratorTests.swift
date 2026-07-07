import XCTest
@testable import Pilgrim

/// SplitMix64 — deterministic RNG so generation is reproducible in tests.
struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

final class SeekChainGeneratorTests: XCTestCase {

    private let home = SeekPoint(latitude: 42.8782, longitude: -8.5448)

    private func chain(minutes: Int, seed: UInt64) -> SeekChain {
        var rng = SeededRNG(seed: seed)
        return SeekChainGenerator.generate(durationMinutes: minutes, start: home, using: &rng)
    }

    private func pathLength(_ clearings: [SeekClearing], from: SeekPoint, to: SeekPoint) -> Double {
        var total = 0.0
        var cursor = from
        for clearing in clearings {
            total += SeekChainGenerator.distance(from: cursor, to: clearing.center)
            cursor = clearing.center
        }
        return total + SeekChainGenerator.distance(from: cursor, to: to)
    }

    // MARK: - Clearing count bands (AE1)

    func testThirtyMinuteSeek_generatesExactlyOneClearing() {
        for seed in 0..<100 {
            XCTAssertEqual(chain(minutes: 30, seed: UInt64(seed)).clearings.count, 1)
        }
    }

    func testThreeHourSeek_generatesTwoOrThree() {
        var counts = Set<Int>()
        for seed in 0..<100 {
            let count = chain(minutes: 180, seed: UInt64(seed)).clearings.count
            XCTAssertTrue((2...3).contains(count), "seed \(seed) produced \(count)")
            counts.insert(count)
        }
        XCTAssertEqual(counts, [2, 3], "band should actually vary across seeds")
    }

    func testOneHourSeek_staysWithinBand() {
        var counts = Set<Int>()
        for seed in 0..<100 {
            counts.insert(chain(minutes: 60, seed: UInt64(seed)).clearings.count)
        }
        XCTAssertEqual(counts, [1, 2])
    }

    // MARK: - Chain geometry

    func testSingleClearing_isOutAndBackAtRoughlyTwoFifths() {
        for seed in 0..<50 {
            let result = chain(minutes: 30, seed: UInt64(seed))
            let fraction = SeekChainGenerator.distance(from: result.clearings[0].center, to: home)
                / result.budgetMeters
            XCTAssertGreaterThanOrEqual(fraction, 0.38, "seed \(seed)")
            XCTAssertLessThanOrEqual(fraction, 0.47, "seed \(seed)")
        }
    }

    func testMultiClearingChain_finalLandsNearHome() {
        for seed in 0..<50 {
            let result = chain(minutes: 180, seed: UInt64(seed))
            guard let last = result.clearings.last else { return XCTFail("empty chain") }
            XCTAssertLessThanOrEqual(
                SeekChainGenerator.distance(from: last.center, to: home),
                result.budgetMeters * 0.22,
                "seed \(seed): final clearing should land near the start"
            )
        }
    }

    func testSeededGeneration_isDeterministic() {
        XCTAssertEqual(chain(minutes: 120, seed: 7), chain(minutes: 120, seed: 7))
        XCTAssertNotEqual(chain(minutes: 120, seed: 7), chain(minutes: 120, seed: 8))
    }

    // MARK: - Constraints across seeds, durations, latitudes

    func testConstraints_holdAcrossSeedsDurationsAndLatitudes() {
        for latitude in [0.0, 45.5, 60.2] {
            let start = SeekPoint(latitude: latitude, longitude: -8.5)
            for duration in [30, 60, 120, 180] {
                for seed in 0..<80 {
                    var rng = SeededRNG(seed: UInt64(seed))
                    let result = SeekChainGenerator.generate(
                        durationMinutes: duration, start: start, using: &rng
                    )
                    assertConstraints(result, home: start, context: "lat \(latitude) dur \(duration) seed \(seed)")
                }
            }
        }
    }

    private func assertConstraints(_ result: SeekChain, home: SeekPoint, context: String) {
        for clearing in result.clearings {
            XCTAssertTrue(
                SeekTuning.clearingRadiusRange.contains(clearing.radiusMeters),
                "\(context): radius \(clearing.radiusMeters)"
            )
            XCTAssertGreaterThanOrEqual(
                SeekChainGenerator.distance(from: home, to: clearing.center),
                SeekTuning.minStartDistanceMeters * 0.9,
                "\(context): clearing too close to start"
            )
        }
        for (index, first) in result.clearings.enumerated() {
            for second in result.clearings.dropFirst(index + 1) {
                XCTAssertGreaterThanOrEqual(
                    SeekChainGenerator.distance(from: first.center, to: second.center),
                    SeekTuning.minSpacingMeters * 0.9,
                    "\(context): clearings too close together"
                )
            }
        }
        XCTAssertLessThanOrEqual(
            pathLength(result.clearings, from: home, to: home),
            result.budgetMeters * 1.1,
            "\(context): chain not walkable within budget"
        )
    }

    // MARK: - Reroll (R17)

    func testReroll_keepsPrefixAndReplacesActiveAndDownstream() {
        let original = chain(minutes: 180, seed: 11)
        let current = SeekPoint(latitude: home.latitude + 0.01, longitude: home.longitude)
        var rng = SeededRNG(seed: 99)
        let rerolled = original.regeneratingRemainder(
            fromActiveIndex: 1,
            current: current,
            home: home,
            remainingBudgetMeters: original.budgetMeters * 0.6,
            using: &rng
        )
        XCTAssertEqual(rerolled.clearings.count, original.clearings.count)
        XCTAssertEqual(Array(rerolled.clearings.prefix(1)), Array(original.clearings.prefix(1)))
        XCTAssertNotEqual(rerolled.clearings[1], original.clearings[1])
    }

    func testReroll_remainderIsWalkableWithinRemainingBudget() {
        for seed in 0..<50 {
            let original = chain(minutes: 180, seed: UInt64(seed))
            let current = SeekPoint(latitude: home.latitude + 0.008, longitude: home.longitude - 0.004)
            let remaining = original.budgetMeters * 0.6
            var rng = SeededRNG(seed: UInt64(seed) &+ 1000)
            let rerolled = original.regeneratingRemainder(
                fromActiveIndex: 1,
                current: current,
                home: home,
                remainingBudgetMeters: remaining,
                using: &rng
            )
            let path = pathLength(Array(rerolled.clearings.dropFirst(1)), from: current, to: home)
            XCTAssertLessThanOrEqual(path, remaining * 1.15, "seed \(seed)")
        }
    }

    func testReroll_singleClearingSeek_yieldsReachableNonDegenerateClearing() {
        for seed in 0..<50 {
            let original = chain(minutes: 30, seed: UInt64(seed))
            let current = SeekPoint(latitude: home.latitude + 0.004, longitude: home.longitude + 0.002)
            var rng = SeededRNG(seed: UInt64(seed) &+ 2000)
            let rerolled = original.regeneratingRemainder(
                fromActiveIndex: 0,
                current: current,
                home: home,
                remainingBudgetMeters: original.budgetMeters * 0.7,
                using: &rng
            )
            XCTAssertEqual(rerolled.clearings.count, 1)
            XCTAssertGreaterThanOrEqual(
                SeekChainGenerator.distance(from: current, to: rerolled.clearings[0].center),
                SeekTuning.minStartDistanceMeters * 0.9,
                "seed \(seed): rerolled clearing degenerate at walker's feet"
            )
        }
    }

    func testReroll_invalidIndex_returnsChainUnchanged() {
        let original = chain(minutes: 60, seed: 3)
        var rng = SeededRNG(seed: 4)
        let result = original.regeneratingRemainder(
            fromActiveIndex: original.clearings.count,
            current: home,
            home: home,
            remainingBudgetMeters: 1000,
            using: &rng
        )
        XCTAssertEqual(result, original)
    }

    // MARK: - Codable (checkpoint ride-along)

    func testChain_roundTripsThroughCodable() throws {
        let original = chain(minutes: 120, seed: 21)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(SeekChain.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}
