import XCTest
@testable import Pilgrim

final class HonorWayRenderingTests: XCTestCase {

    func testWayPinsMapEveryMomentKindAndUseTrueCoordinates() {
        let at = WayCoordinate(lat: 42.1, lon: -8.2)
        let moments = [
            WayMoment(id: "voice-1", frac: 0.1, at: at, kind: .voice(endFrac: 0.2, duration: 5, kind: .spoken, media: .file("audio/1.m4a"))),
            WayMoment(id: "photo-1", frac: 0.2, at: at, kind: .photo(media: .file("photos/1.jpg"))),
            WayMoment(id: "rest-1", frac: 0.3, at: at, kind: .rest(minutes: 4)),
            WayMoment(id: "sit-1", frac: 0.4, at: at, kind: .meditation(minutes: 9, isEstimate: true)),
            WayMoment(id: "waypoint-1", frac: 0.5, at: nil, kind: .waypoint(label: "Oak", icon: "leaf"))
        ]
        let route = [WayPoint(lat: 0, lon: 0, alt: nil, t: 0), WayPoint(lat: 0, lon: 0.001, alt: nil, t: 60)]
        let way = Way(id: "walk:t", source: .ownWalk(UUID()), title: "t", departedAt: Date(), tzIdentifier: nil, expires: nil,
                      route: route, totalDistanceMeters: 111, theirActiveSeconds: 60, moments: moments, weather: nil)
        let pins = PilgrimMapView.wayPins(for: way, heardVoiceIDs: ["voice-1"])
        XCTAssertEqual(pins.count, 5)
        XCTAssertEqual(pins[0].kind, .wayVoice(id: "voice-1", heard: true))
        XCTAssertEqual(pins[0].coordinate.latitude, 42.1)
        XCTAssertEqual(pins[1].kind, .wayPhoto(id: "photo-1"))
        XCTAssertEqual(pins[2].kind, .wayRest(id: "rest-1", minutes: 4))
        XCTAssertEqual(pins[3].kind, .waySit(id: "sit-1", minutes: 9))
        XCTAssertEqual(pins[4].kind, .wayWaypoint(id: "waypoint-1", label: "Oak", icon: "leaf"))
        XCTAssertEqual(pins[4].coordinate.longitude, 0.0005, accuracy: 0.00001, "frac fallback when `at` is nil")
    }

    func testWayPinsMarkVoiceUnheardWhenIDMissingFromHeardSet() {
        let at = WayCoordinate(lat: 42.1, lon: -8.2)
        let moments = [
            WayMoment(id: "voice-1", frac: 0.1, at: at, kind: .voice(endFrac: 0.2, duration: 5, kind: .spoken, media: .file("audio/1.m4a")))
        ]
        let route = [WayPoint(lat: 0, lon: 0, alt: nil, t: 0), WayPoint(lat: 0, lon: 0.001, alt: nil, t: 60)]
        let way = Way(id: "walk:t", source: .ownWalk(UUID()), title: "t", departedAt: Date(), tzIdentifier: nil, expires: nil,
                      route: route, totalDistanceMeters: 111, theirActiveSeconds: 60, moments: moments, weather: nil)
        let pins = PilgrimMapView.wayPins(for: way, heardVoiceIDs: [])
        XCTAssertEqual(pins[0].kind, .wayVoice(id: "voice-1", heard: false))
    }
}

extension HonorWayRenderingTests {

    func testGhostStyleBrightensOnTheDarkMapStyle() {
        let light = PilgrimMapView.HonorWayRendering.ghostStyle(dark: false)
        let dark = PilgrimMapView.HonorWayRendering.ghostStyle(dark: true)
        XCTAssertGreaterThan(dark.lineOpacity, light.lineOpacity)
        XCTAssertGreaterThan(dark.companionOpacity, light.companionOpacity)
        var white: CGFloat = 0
        XCTAssertTrue(dark.color.getWhite(&white, alpha: nil))
        XCTAssertGreaterThan(white, 0.7, "the dark-style ghost must be light enough to read on the ink ground")
    }
}
