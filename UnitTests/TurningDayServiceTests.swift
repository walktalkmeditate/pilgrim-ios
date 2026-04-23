import XCTest
import CoreLocation
@testable import Pilgrim

final class TurningDayServiceTests: XCTestCase {

    private func date(year: Int, month: Int, day: Int, hour: Int = 12) -> Date {
        var c = DateComponents()
        c.year = year; c.month = month; c.day = day; c.hour = hour
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // MARK: - Northern hemisphere: astronomical = seasonal

    func testMarchEquinox_northern_returnsSpringEquinox() {
        let coord = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        let d = date(year: 2024, month: 3, day: 20)
        XCTAssertEqual(TurningDayService.turning(for: d, at: coord), .springEquinox)
    }

    func testJuneSolstice_northern_returnsSummerSolstice() {
        let coord = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        let d = date(year: 2024, month: 6, day: 20)
        XCTAssertEqual(TurningDayService.turning(for: d, at: coord), .summerSolstice)
    }

    func testDecemberSolstice_northern_returnsWinterSolstice() {
        let coord = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        let d = date(year: 2024, month: 12, day: 21)
        XCTAssertEqual(TurningDayService.turning(for: d, at: coord), .winterSolstice)
    }

    // MARK: - Southern hemisphere: mirrored

    func testJuneSolstice_southern_returnsWinterSolstice() {
        let sydney = CLLocationCoordinate2D(latitude: -33.9, longitude: 151.2)
        let d = date(year: 2024, month: 6, day: 20)
        XCTAssertEqual(TurningDayService.turning(for: d, at: sydney), .winterSolstice)
    }

    func testDecemberSolstice_southern_returnsSummerSolstice() {
        let sydney = CLLocationCoordinate2D(latitude: -33.9, longitude: 151.2)
        let d = date(year: 2024, month: 12, day: 21)
        XCTAssertEqual(TurningDayService.turning(for: d, at: sydney), .summerSolstice)
    }

    func testMarchEquinox_southern_returnsAutumnEquinox() {
        let sydney = CLLocationCoordinate2D(latitude: -33.9, longitude: 151.2)
        let d = date(year: 2024, month: 3, day: 20)
        XCTAssertEqual(TurningDayService.turning(for: d, at: sydney), .autumnEquinox)
    }

    func testSeptemberEquinox_southern_returnsSpringEquinox() {
        let sydney = CLLocationCoordinate2D(latitude: -33.9, longitude: 151.2)
        let d = date(year: 2024, month: 9, day: 22)
        XCTAssertEqual(TurningDayService.turning(for: d, at: sydney), .springEquinox)
    }

    // MARK: - Non-turning

    func testNonTurningDay_returnsNil() {
        let coord = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        let d = date(year: 2024, month: 5, day: 15)
        XCTAssertNil(TurningDayService.turning(for: d, at: coord))
    }

    // MARK: - Cross-quarter markers excluded

    func testCrossQuarterDate_returnsNil() {
        let coord = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        // Beltane is around May 5-6 (sun at ecliptic longitude 45°)
        let d = date(year: 2024, month: 5, day: 5)
        XCTAssertNil(TurningDayService.turning(for: d, at: coord))
    }

    // MARK: - Nil coordinate defaults to northern

    func testNilCoordinate_defaultsToNorthern() {
        let d = date(year: 2024, month: 12, day: 21)
        XCTAssertEqual(TurningDayService.turning(for: d, at: nil), .winterSolstice)
    }
}
