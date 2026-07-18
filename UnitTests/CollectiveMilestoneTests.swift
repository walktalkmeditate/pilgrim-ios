// UnitTests/CollectiveMilestoneTests.swift
import XCTest
@testable import Pilgrim

/// Pins the walk-count milestone messages across the move that split this type
/// out of the deleted `PilgrimageProgress.swift`.
///
/// Every string asserted here is what shipped before the move. The type had no
/// coverage while it shared a file with the route table, which is what made the
/// deletion risky: nothing would have caught a message lost in the split.
final class CollectiveMilestoneTests: XCTestCase {

    func testForNumber_108_namesTheBeadsOfTheMala() {
        XCTAssertEqual(CollectiveMilestone.forNumber(108).message,
                       "108 walks. One for each bead on the mala.")
    }

    func testForNumber_1080_turnsTheMalaTenTimes() {
        XCTAssertEqual(CollectiveMilestone.forNumber(1_080).message,
                       "1,080 walks. The mala, turned ten times.")
    }

    func testForNumber_2160_namesTheAgeOfTheZodiac() {
        XCTAssertEqual(CollectiveMilestone.forNumber(2_160).message,
                       "2,160 walks. One full age of the zodiac.")
    }

    func testForNumber_10000_namesAllThings() {
        XCTAssertEqual(CollectiveMilestone.forNumber(10_000).message,
                       "10,000 walks. 万 — all things.")
    }

    func testForNumber_33333_namesTheSaigokuPilgrimage() {
        XCTAssertEqual(CollectiveMilestone.forNumber(33_333).message,
                       "33,333 walks. The Saigoku pilgrimage, a thousandfold.")
    }

    func testForNumber_88000_namesShikokusTemples() {
        XCTAssertEqual(CollectiveMilestone.forNumber(88_000).message,
                       "88,000 walks. Shikoku's 88 temples, a thousand times over.")
    }

    func testForNumber_108000_completesTheGreatMala() {
        XCTAssertEqual(CollectiveMilestone.forNumber(108_000).message,
                       "108,000 walks. The great mala, complete.")
    }

    /// Interpolating `.formatted()` rather than writing "5,000" keeps the
    /// assertion about the sentence template instead of the test runner's locale.
    func testForNumber_unnamedNumber_fallsBackToThePlainCount() {
        XCTAssertEqual(CollectiveMilestone.forNumber(5_000).message,
                       "\(5_000.formatted()) walks. You were one of them.")
    }

    /// One short of the first sacred number. Guards against a `case` becoming a
    /// range or a comparison during some future edit of the switch.
    func testForNumber_justBelowASacredNumber_doesNotBorrowItsMessage() {
        XCTAssertEqual(CollectiveMilestone.forNumber(107).message,
                       "\(107.formatted()) walks. You were one of them.")
    }

    func testForNumber_carriesTheNumberItWasAskedAbout() {
        XCTAssertEqual(CollectiveMilestone.forNumber(2_160).number, 2_160)
        XCTAssertEqual(CollectiveMilestone.forNumber(5_000).number, 5_000)
    }
}
