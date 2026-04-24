import XCTest
import CoreLocation
@testable import Pilgrim

final class HemisphereTests: XCTestCase {

    func testNorthern_positiveLatitude() {
        let coord = CLLocationCoordinate2D(latitude: 40.7, longitude: -74.0)
        XCTAssertEqual(Hemisphere(coordinate: coord), .northern)
    }

    func testSouthern_negativeLatitude() {
        let coord = CLLocationCoordinate2D(latitude: -33.9, longitude: 151.2)
        XCTAssertEqual(Hemisphere(coordinate: coord), .southern)
    }

    func testEquator_returnsNorthern() {
        let coord = CLLocationCoordinate2D(latitude: 0, longitude: 0)
        XCTAssertEqual(Hemisphere(coordinate: coord), .northern)
    }

    func testNil_returnsNorthern() {
        XCTAssertEqual(Hemisphere(coordinate: nil), .northern)
    }
}
