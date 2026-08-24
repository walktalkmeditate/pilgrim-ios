import XCTest
@testable import Pilgrim

final class LunationCalendarTests: XCTestCase {

    func testLunation_boundariesAreContiguous() {
        let lunation = LunationCalendar.lunation(at: 300)
        XCTAssertEqual(LunationCalendar.lunation(containing: lunation.start).index, 300)
        XCTAssertEqual(LunationCalendar.lunation(containing: lunation.end.addingTimeInterval(-1)).index, 300)
        XCTAssertEqual(LunationCalendar.lunation(containing: lunation.end).index, 301,
                       "the close instant belongs to the next lunation")
        XCTAssertEqual(lunation.end, LunationCalendar.lunation(at: 301).start)
    }

    func testMostRecentClosed_isThePreviousLunation() {
        let lunation = LunationCalendar.lunation(at: 300)
        let closed = LunationCalendar.mostRecentClosed(asOf: lunation.start.addingTimeInterval(86400))
        XCTAssertEqual(closed.index, 299)
    }

    func testFullMoon_isTheMidpoint() {
        let lunation = LunationCalendar.lunation(at: 300)
        XCTAssertEqual(
            lunation.fullMoon.timeIntervalSince(lunation.start),
            lunation.end.timeIntervalSince(lunation.fullMoon),
            accuracy: 1
        )
    }

    func testMoonName_derivesFromFullMoonMonthInTimezone() {
        let nearMonthEdge = Lunation(
            index: 0,
            start: DateFactory.makeDate(2024, 8, 17, 11, 0, 0),
            end: DateFactory.makeDate(2024, 9, 15, 23, 0, 0),
            fullMoon: DateFactory.makeDate(2024, 8, 31, 23, 0, 0)
        )
        XCTAssertEqual(
            LunationCalendar.moonName(for: nearMonthEdge, in: TimeZone(identifier: "UTC")!),
            "Sturgeon Moon"
        )
        XCTAssertEqual(
            LunationCalendar.moonName(for: nearMonthEdge, in: TimeZone(identifier: "Pacific/Auckland")!),
            "Corn Moon",
            "the same instant is already September in Auckland — the name follows the device's timezone"
        )
    }

    func testMoonName_allTwelveMonthsCovered() {
        for month in 1...12 {
            let lunation = Lunation(
                index: 0,
                start: DateFactory.makeDate(2024, month, 1),
                end: DateFactory.makeDate(2024, month, 29),
                fullMoon: DateFactory.makeDate(2024, month, 15, 12, 0, 0)
            )
            let name = LunationCalendar.moonName(for: lunation, in: TimeZone(identifier: "UTC")!)
            XCTAssertTrue(name.hasSuffix("Moon"))
        }
    }
}
