import XCTest
@testable import Pilgrim

final class SeekFogStateTests: XCTestCase {

    private func makeChain(count: Int) -> SeekChain {
        let clearings = (0..<count).map { index in
            SeekClearing(
                center: SeekPoint(latitude: 42.0 + Double(index) * 0.01, longitude: -8.5),
                radiusMeters: 50
            )
        }
        return SeekChain(clearings: clearings, budgetMeters: 4000)
    }

    private func state(
        count: Int = 3,
        activeIndex: Int = 0,
        phase: SeekEnginePhase = .guiding,
        distance: Double? = nil,
        previousBucket: Int? = nil
    ) -> SeekFogState {
        SeekFogModel.fogState(
            chain: makeChain(count: count),
            activeIndex: activeIndex,
            phase: phase,
            distanceToActiveMeters: distance,
            previousActiveBucket: previousBucket
        )
    }

    // MARK: - Count-hiding invariant (origin R6)

    func testChainOfThreeWithFirstActive_exposesExactlyOneCircle() {
        let fog = state(count: 3, activeIndex: 0)
        XCTAssertEqual(fog.circles.count, 1)
        XCTAssertEqual(fog.circles[0].id, "seek-fog-0")
        XCTAssertFalse(fog.circles[0].isHalo)
    }

    func testUnrevealedFutureClearings_renderNothing() {
        let fog = state(count: 3, activeIndex: 1)
        XCTAssertEqual(fog.circles.map(\.id), ["seek-fog-0", "seek-fog-1"])
    }

    // MARK: - Active clearing fog

    func testActiveClearingBucket_derivedFromDistance() {
        let expectations: [(Double, Int)] = [
            (2000, 5), (1200, 5), (900, 4), (600, 4), (400, 3), (200, 2), (100, 1), (0, 1)
        ]
        for (distance, expected) in expectations {
            let fog = state(distance: distance)
            XCTAssertEqual(fog.circles[0].opacityBucket, expected, "distance \(distance)")
        }
    }

    func testActiveClearingWithNoFixYet_rendersThickestFog() {
        XCTAssertEqual(state(distance: nil).circles[0].opacityBucket, SeekFogModel.farthestBucket)
    }

    func testArrivedPhase_dissolvesActiveFog() {
        let fog = state(activeIndex: 0, phase: .arrived, distance: 20)
        XCTAssertEqual(fog.circles[0].opacityBucket, 0)
        XCTAssertFalse(fog.circles[0].isHalo)
        XCTAssertEqual(SeekFogModel.opacity(forBucket: 0, isHalo: false), SeekFogModel.dissolvedOpacity)
    }

    func testRevealingPhase_dissolvesActiveFog() {
        XCTAssertEqual(state(phase: .revealing, distance: 20).circles[0].opacityBucket, 0)
    }

    // MARK: - Halos

    func testFoundClearings_renderAsHalos() {
        let fog = state(count: 3, activeIndex: 2, distance: 500)
        XCTAssertEqual(fog.circles.filter(\.isHalo).map(\.id), ["seek-fog-0", "seek-fog-1"])
        XCTAssertFalse(fog.circles[2].isHalo)
    }

    func testCompletePhase_halosOnlyNoFog() {
        let fog = state(count: 3, activeIndex: 2, phase: .complete)
        XCTAssertEqual(fog.circles.count, 3)
        XCTAssertTrue(fog.circles.allSatisfy(\.isHalo))
    }

    func testEmptyChainComplete_rendersNothing() {
        let fog = SeekFogModel.fogState(
            chain: SeekChain(clearings: [], budgetMeters: 0),
            activeIndex: 0,
            phase: .complete,
            distanceToActiveMeters: nil
        )
        XCTAssertTrue(fog.circles.isEmpty)
    }

    // MARK: - Buckets

    func testOpacityBucket_monotonicInDistance() {
        var previous = 0
        for distance in stride(from: 0.0, through: 2500.0, by: 10.0) {
            let bucket = SeekFogModel.opacityBucket(forDistanceMeters: distance)
            XCTAssertGreaterThanOrEqual(bucket, previous, "distance \(distance)")
            previous = bucket
        }
    }

    func testOpacityBucket_nilDistance_isFarthest() {
        XCTAssertEqual(SeekFogModel.opacityBucket(forDistanceMeters: nil), SeekFogModel.farthestBucket)
    }

    // MARK: - Hysteresis

    func testOscillationAcrossBoundary_doesNotFlipBucket() {
        var bucket = SeekFogModel.bucketApplyingHysteresis(distanceMeters: 130, currentBucket: 2)
        XCTAssertEqual(bucket, 1, "beyond the margin, change applies")
        for distance in [145.0, 155.0, 148.0, 152.0, 160.0, 149.0] {
            bucket = SeekFogModel.bucketApplyingHysteresis(distanceMeters: distance, currentBucket: bucket)
            XCTAssertEqual(bucket, 1, "jitter at \(distance) m must not flip the bucket")
        }
    }

    func testCrossingBeyondMargin_flipsBucket() {
        XCTAssertEqual(SeekFogModel.bucketApplyingHysteresis(distanceMeters: 165, currentBucket: 1), 2)
        XCTAssertEqual(SeekFogModel.bucketApplyingHysteresis(distanceMeters: 135, currentBucket: 2), 1)
    }

    func testWithinMargin_keepsCurrentBucket() {
        XCTAssertEqual(SeekFogModel.bucketApplyingHysteresis(distanceMeters: 164, currentBucket: 1), 1)
        XCTAssertEqual(SeekFogModel.bucketApplyingHysteresis(distanceMeters: 136, currentBucket: 2), 2)
    }

    func testMultiBucketJump_appliesImmediately() {
        XCTAssertEqual(SeekFogModel.bucketApplyingHysteresis(distanceMeters: 100, currentBucket: 5), 1)
        XCTAssertEqual(SeekFogModel.bucketApplyingHysteresis(distanceMeters: 2000, currentBucket: 1), 5)
    }

    func testNoCurrentBucket_usesRawBucket() {
        XCTAssertEqual(SeekFogModel.bucketApplyingHysteresis(distanceMeters: 155, currentBucket: nil), 2)
    }

    func testInvalidCurrentBucket_fallsBackToRaw() {
        XCTAssertEqual(SeekFogModel.bucketApplyingHysteresis(distanceMeters: 155, currentBucket: 0), 2)
        XCTAssertEqual(SeekFogModel.bucketApplyingHysteresis(distanceMeters: 155, currentBucket: 99), 2)
    }

    func testFogState_respectsPreviousActiveBucket() {
        let held = state(distance: 155, previousBucket: 1)
        XCTAssertEqual(held.circles[0].opacityBucket, 1)
        XCTAssertEqual(held.activeFogBucket, 1)
        let flipped = state(distance: 165, previousBucket: 1)
        XCTAssertEqual(flipped.circles[0].opacityBucket, 2)
    }

    // MARK: - Opacity

    func testOpacity_monotonicAcrossBuckets() {
        var previous = SeekFogModel.opacity(forBucket: 0, isHalo: false)
        for bucket in 1...SeekFogModel.farthestBucket {
            let opacity = SeekFogModel.opacity(forBucket: bucket, isHalo: false)
            XCTAssertGreaterThan(opacity, previous, "bucket \(bucket)")
            previous = opacity
        }
    }

    func testHaloOpacity_belowAnyActiveFog() {
        let halo = SeekFogModel.opacity(forBucket: 0, isHalo: true)
        XCTAssertEqual(halo, SeekFogModel.haloOpacity)
        for bucket in 1...SeekFogModel.farthestBucket {
            XCTAssertLessThan(halo, SeekFogModel.opacity(forBucket: bucket, isHalo: false))
        }
    }

    func testBucketZero_isDissolved() {
        XCTAssertEqual(SeekFogModel.opacity(forBucket: 0, isHalo: false), 0)
    }

    // MARK: - Equality (the render early-return key)

    func testIdenticalStates_compareEqual() {
        let first = state(count: 3, activeIndex: 1, distance: 500, previousBucket: 3)
        let second = state(count: 3, activeIndex: 1, distance: 500, previousBucket: 3)
        XCTAssertEqual(first, second)
    }

    func testDifferentBuckets_compareNotEqual() {
        XCTAssertNotEqual(state(distance: 2000), state(distance: 100))
    }
    // MARK: - Celestial tint (#5)

    func testFogState_carriesTint_andEqualityHonorsIt() {
        let chain = SeekChain(
            clearings: [SeekClearing(center: SeekPoint(latitude: 42, longitude: -8), radiusMeters: 50)],
            budgetMeters: 3000
        )
        let plain = SeekFogModel.fogState(
            chain: chain, activeIndex: 0, phase: .guiding, distanceToActiveMeters: 500
        )
        let tinted = SeekFogModel.fogState(
            chain: chain, activeIndex: 0, phase: .guiding, distanceToActiveMeters: 500,
            tintHex: "#2377A4"
        )
        XCTAssertNil(plain.tintHex)
        XCTAssertEqual(tinted.tintHex, "#2377A4")
        XCTAssertNotEqual(plain, tinted)
    }

    // MARK: - Wisp

    private var wispChain: SeekChain {
        SeekChain(
            clearings: [SeekClearing(center: SeekPoint(latitude: 42.01, longitude: -8), radiusMeters: 50)],
            budgetMeters: 3000
        )
    }

    private let walker = SeekPoint(latitude: 42.0, longitude: -8.0)

    private func wispState(distance: Double?, phase: SeekEnginePhase = .guiding) -> SeekFogState {
        SeekFogModel.fogState(
            chain: wispChain, activeIndex: 0, phase: phase,
            distanceToActiveMeters: distance, walkerPosition: walker
        )
    }

    func testWisp_visibleFarAway_pointsTowardClearingAtOffset() {
        let state = wispState(distance: 900)
        guard let wisp = state.wisp else { return XCTFail("wisp should show beyond 150 m") }
        let offset = SeekChainGenerator.distance(from: walker, to: wisp)
        XCTAssertEqual(offset, SeekFogModel.wispOffsetMeters, accuracy: 1.0)
        XCTAssertGreaterThan(
            wisp.latitude, walker.latitude,
            "clearing is due north; the wisp must lean north"
        )
    }

    func testWisp_hidesInsideTheHandoffBucket() {
        XCTAssertNil(wispState(distance: 120).wisp, "fog is on-screen below 150 m")
    }

    func testWisp_hidesWhenArrivedOrRevealing() {
        XCTAssertNil(wispState(distance: 900, phase: .arrived).wisp)
        XCTAssertNil(wispState(distance: 900, phase: .revealing).wisp)
    }

    func testWisp_hidesWithoutAWalkerPosition() {
        let state = SeekFogModel.fogState(
            chain: wispChain, activeIndex: 0, phase: .guiding,
            distanceToActiveMeters: 900, walkerPosition: nil
        )
        XCTAssertNil(state.wisp)
    }

    func testWisp_movesWithTheWalker_andEqualityNoticesIt() {
        let there = SeekFogModel.fogState(
            chain: wispChain, activeIndex: 0, phase: .guiding,
            distanceToActiveMeters: 900,
            walkerPosition: SeekPoint(latitude: 42.001, longitude: -8.0)
        )
        XCTAssertNotEqual(wispState(distance: 900), there)
    }

}
