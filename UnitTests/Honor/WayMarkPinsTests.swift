import XCTest
import CoreLocation
@testable import Pilgrim

final class WayMarkPinsTests: XCTestCase {

    /// `count` water marks strung east along the equator, 100 m apart.
    private func marks(_ count: Int) -> [WayMark] {
        (0..<count).map { index in
            WayMark(id: "m\(index)", kind: .water, name: "f\(index)",
                    at: WayCoordinate(lat: 0, lon: Double(index) * 0.000898),
                    frac: Double(index) / Double(max(count - 1, 1)), offLineMeters: 10)
        }
    }

    func testEveryKindHasItsOwnGlyph() {
        XCTAssertEqual(WayMarkPins.symbol(for: .water), "drop.fill")
        XCTAssertEqual(WayMarkPins.symbol(for: .food), "fork.knife")
        XCTAssertEqual(WayMarkPins.symbol(for: .bed), "bed.double.fill")
        XCTAssertEqual(WayMarkPins.symbol(for: .transport), "bus.fill")
        XCTAssertEqual(WayMarkPins.symbol(for: .supply), "bag.fill")
        XCTAssertEqual(WayMarkPins.symbol(for: .medical), "cross.case.fill")
    }

    func testNothingIsDrawnBelowZoomThirteen() {
        XCTAssertTrue(WayMarkPins.pins(marks: marks(5), zoom: 12.9, near: nil).isEmpty)
        XCTAssertEqual(WayMarkPins.pins(marks: marks(5), zoom: 13, near: nil).count, 5)
    }

    func testTheScreenNeverCarriesMoreThanFortyNearestFirst() {
        let all = marks(200)
        // Standing at the 150th mark: the forty nearest run 130 to 169.
        let here = CLLocationCoordinate2D(latitude: 0, longitude: 150 * 0.000898)
        let pins = WayMarkPins.pins(marks: all, zoom: 15, near: here)
        XCTAssertEqual(pins.count, WayMarkPins.maxPerScreen)
        let ids = Set(pins.compactMap { pin -> String? in
            if case .wayMark(let id, _) = pin.kind { return id }
            return nil
        })
        XCTAssertTrue(ids.contains("m150"))
        XCTAssertTrue(ids.contains("m131"))
        XCTAssertTrue(ids.contains("m169"))
        XCTAssertFalse(ids.contains("m0"))
        XCTAssertFalse(ids.contains("m199"))
    }

    func testWithoutAFixTheFirstFortyAlongTheStageAreDrawn() {
        let pins = WayMarkPins.pins(marks: marks(100), zoom: 15, near: nil)
        XCTAssertEqual(pins.count, 40)
        guard case .wayMark(let first, _) = pins[0].kind else { return XCTFail("kind") }
        XCTAssertEqual(first, "m0")
    }

    func testAMarkIsNeverAMomentAndNeverTappable() {
        let pin = PilgrimAnnotation(coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
                                    kind: .wayMark(id: "m1", kind: .water))
        XCTAssertNil(pin.kind.wayMomentID, "a mark has no card to open")
    }

    func testAPinLandsOnItsMarksOwnCoordinate() {
        // Distinct, differently-signed lat and lon: a swap between them draws
        // every fountain on the Camino into the Atlantic, and passes every
        // count-and-order assertion above.
        let fountain = WayMark(id: "m1", kind: .water, name: "fuente",
                               at: WayCoordinate(lat: 42.881, lon: -8.545), frac: 0.5, offLineMeters: 10)
        guard let pin = WayMarkPins.pins(marks: [fountain], zoom: 15, near: nil).first else {
            return XCTFail("a mark above the draw zoom must produce a pin")
        }
        XCTAssertEqual(pin.coordinate.latitude, 42.881, accuracy: 1e-9)
        XCTAssertEqual(pin.coordinate.longitude, -8.545, accuracy: 1e-9)
    }
}
