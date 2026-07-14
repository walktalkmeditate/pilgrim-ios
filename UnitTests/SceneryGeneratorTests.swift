import XCTest
@testable import Pilgrim

final class SceneryGeneratorTests: XCTestCase {

    private func snapshot(
        id: UUID = UUID(),
        daysAgo: Int = 10,
        distance: Double = 3_000,
        duration: Double = 1_800,
        isSeek: Bool = false,
        foundPlaces: Int = 0,
        threshold: WalkThreshold? = nil
    ) -> WalkSnapshot {
        WalkSnapshot(
            id: id,
            startDate: DateFactory.makeDate(2026, 6, 15, 9, 0, 0).addingTimeInterval(-Double(daysAgo) * 86_400),
            distance: distance,
            duration: duration,
            averagePace: 600,
            cumulativeDistance: distance,
            talkDuration: 0,
            meditateDuration: 0,
            favicon: nil,
            isShared: false,
            weatherCondition: nil,
            isSeek: isSeek,
            foundPlaces: foundPlaces,
            threshold: threshold
        )
    }

    // MARK: - Meaning outranks the lottery

    func testThresholdWalk_alwaysStandsAtAGate() {
        for _ in 0..<50 {
            let placement = SceneryGenerator.scenery(for: snapshot(threshold: .practice))
            XCTAssertEqual(placement?.type, .torii)
        }
    }

    func testGateKind_shapesTheGate() {
        let practice = SceneryGenerator.scenery(for: snapshot(threshold: .practice))
        XCTAssertEqual(practice?.gateKind, .practice)
        XCTAssertEqual(practice?.tintColorName, "rust", "practice gates stand vermilion")

        let seeking = SceneryGenerator.scenery(for: snapshot(threshold: .seeking))
        XCTAssertEqual(seeking?.gateKind, .seeking)
        XCTAssertEqual(seeking?.tintColorName, "stone", "seeking gates stand weathered stone")
    }

    func testDrift_livesInTheRetiredGateBand() {
        var sawDrift = false
        for _ in 0..<800 where SceneryGenerator.scenery(for: snapshot())?.type == .drift {
            sawDrift = true
        }
        XCTAssertTrue(sawDrift, "the season's breath must appear in the lottery")
    }

    func testSeekWithFoundPlaces_alwaysRaisesACairn() {
        for _ in 0..<50 {
            let placement = SceneryGenerator.scenery(for: snapshot(isSeek: true, foundPlaces: 2))
            XCTAssertEqual(placement?.type, .cairn)
        }
    }

    func testCairnStack_growsWithFoundPlaces_cappedAtFive() {
        XCTAssertEqual(SceneryGenerator.scenery(for: snapshot(isSeek: true, foundPlaces: 1))?.stones, 3)
        XCTAssertEqual(SceneryGenerator.scenery(for: snapshot(isSeek: true, foundPlaces: 2))?.stones, 4)
        XCTAssertEqual(SceneryGenerator.scenery(for: snapshot(isSeek: true, foundPlaces: 3))?.stones, 5)
        XCTAssertEqual(
            SceneryGenerator.scenery(for: snapshot(isSeek: true, foundPlaces: 9))?.stones, 5,
            "the stack tops out at five stones"
        )
    }

    func testThresholdOutranksCairn() {
        let placement = SceneryGenerator.scenery(
            for: snapshot(isSeek: true, foundPlaces: 1, threshold: .seeking)
        )
        XCTAssertEqual(placement?.type, .torii, "a gate marks the threshold even on a seek walk")
    }

    func testSeekWithoutArrivals_fallsBackToTheLottery() {
        var sawCairn = false
        for _ in 0..<200
        where SceneryGenerator.scenery(for: snapshot(isSeek: true, foundPlaces: 0))?.type == .cairn {
            sawCairn = true
        }
        XCTAssertFalse(sawCairn, "no cairn without a found place")
    }

    // MARK: - The lottery itself

    func testRandomToriiIsRetired_everyGateIsAThreshold() {
        for _ in 0..<800 {
            let placement = SceneryGenerator.scenery(for: snapshot())
            XCTAssertNotEqual(placement?.type, .torii, "the lottery must never mint a gate")
            XCTAssertNotEqual(placement?.type, .cairn, "the lottery must never raise a cairn")
        }
    }

    func testLotteryStaysDeterministicPerWalk() {
        let walk = snapshot()
        let first = SceneryGenerator.scenery(for: walk)
        let second = SceneryGenerator.scenery(for: walk)
        XCTAssertEqual(first?.type, second?.type)
        XCTAssertEqual(first?.offset, second?.offset)
    }

    func testRoughlyAThirdOfWalksGetScenery() {
        var count = 0
        let total = 600
        for _ in 0..<total where SceneryGenerator.scenery(for: snapshot()) != nil {
            count += 1
        }
        let fraction = Double(count) / Double(total)
        XCTAssertGreaterThan(fraction, 0.25)
        XCTAssertLessThan(fraction, 0.45)
    }
}
