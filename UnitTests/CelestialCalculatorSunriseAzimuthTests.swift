import XCTest
import CoreLocation
@testable import Pilgrim

final class CelestialCalculatorSunriseAzimuthTests: XCTestCase {

    private let azimuthTolerance: Double = 3.0

    private func date(year: Int, month: Int, day: Int) -> Date {
        var c = DateComponents()
        c.year = year
        c.month = month
        c.day = day
        c.hour = 12
        c.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    // MARK: - Equinox at equator: sunrise due east (~90°)

    func testEquinox_atEquator_risesDueEast() {
        let equator = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        let marchEquinox = date(year: 2024, month: 3, day: 20)
        guard let azimuth = CelestialCalculator.sunriseAzimuth(at: equator, on: marchEquinox) else {
            return XCTFail("expected non-nil azimuth at equator on equinox")
        }
        XCTAssertEqual(azimuth, 90.0, accuracy: azimuthTolerance)
    }

    // MARK: - Summer solstice at mid-latitude: north of east

    func testSummerSolstice_atNewYork_northOfEast() {
        let nyc = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        let juneSolstice = date(year: 2024, month: 6, day: 20)
        guard let azimuth = CelestialCalculator.sunriseAzimuth(at: nyc, on: juneSolstice) else {
            return XCTFail("expected non-nil azimuth")
        }
        // Summer solstice at ~41°N: sunrise azimuth ~57-60° (well north of due east)
        XCTAssertLessThan(azimuth, 70.0)
        XCTAssertGreaterThan(azimuth, 50.0)
    }

    // MARK: - Winter solstice at mid-latitude: south of east

    func testWinterSolstice_atNewYork_southOfEast() {
        let nyc = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        let decSolstice = date(year: 2024, month: 12, day: 21)
        guard let azimuth = CelestialCalculator.sunriseAzimuth(at: nyc, on: decSolstice) else {
            return XCTFail("expected non-nil azimuth")
        }
        // Winter solstice at ~41°N: sunrise azimuth ~120-123° (south of due east)
        XCTAssertGreaterThan(azimuth, 115.0)
        XCTAssertLessThan(azimuth, 130.0)
    }

    // MARK: - Polar: sun doesn't rise

    func testWinterSolstice_aboveArcticCircle_returnsNil() {
        // 78°N, December solstice: polar night, sun doesn't rise.
        let svalbard = CLLocationCoordinate2D(latitude: 78.0, longitude: 15.0)
        let decSolstice = date(year: 2024, month: 12, day: 21)
        XCTAssertNil(CelestialCalculator.sunriseAzimuth(at: svalbard, on: decSolstice))
    }

    // MARK: - Azimuth always in [0, 360)

    func testAzimuth_alwaysInValidRange() {
        let coords = [
            CLLocationCoordinate2D(latitude: 40, longitude: 0),
            CLLocationCoordinate2D(latitude: -33, longitude: 151),
            CLLocationCoordinate2D(latitude: 60, longitude: -120),
        ]
        let dates = [
            date(year: 2024, month: 3, day: 20),
            date(year: 2024, month: 6, day: 20),
            date(year: 2024, month: 9, day: 22),
            date(year: 2024, month: 12, day: 21),
        ]
        for coord in coords {
            for d in dates {
                if let az = CelestialCalculator.sunriseAzimuth(at: coord, on: d) {
                    XCTAssertGreaterThanOrEqual(az, 0.0)
                    XCTAssertLessThan(az, 360.0)
                }
            }
        }
    }

    // MARK: - seasonalMarker(for:) parity with snapshot(for:).seasonalMarker

    /// The lightweight `seasonalMarker(for:)` helper must return the same
    /// marker as the full `snapshot(for:)` for any date — they share the
    /// same underlying calculation. This guards against future refactors
    /// that might desync the two paths.
    func testSeasonalMarker_matchesSnapshotResult_acrossYear() {
        let testDates = [
            date(year: 2024, month: 1, day: 15),   // mid-winter — nil expected
            date(year: 2024, month: 3, day: 20),   // spring equinox
            date(year: 2024, month: 5, day: 5),    // beltane (cross-quarter)
            date(year: 2024, month: 6, day: 20),   // summer solstice
            date(year: 2024, month: 8, day: 7),    // lughnasadh (cross-quarter)
            date(year: 2024, month: 9, day: 22),   // autumn equinox
            date(year: 2024, month: 11, day: 7),   // samhain (cross-quarter)
            date(year: 2024, month: 12, day: 21),  // winter solstice
        ]
        for d in testDates {
            let lightweight = CelestialCalculator.seasonalMarker(for: d)
            let full = CelestialCalculator.snapshot(for: d).seasonalMarker
            XCTAssertEqual(
                lightweight, full,
                "seasonalMarker(for: \(d)) returned \(String(describing: lightweight)) but snapshot returned \(String(describing: full))"
            )
        }
    }
}
