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

extension HonorWayRenderingTests {

    private func straightRoute() -> [WayPoint] {
        (0...10).map { i in WayPoint(lat: 0, lon: Double(i) * 0.000898, alt: nil, t: Double(i) * 60) }
    }

    func testSegmentsCutTheRouteAtSpanBoundariesAndStayContiguous() {
        let spans = [
            WaySpan(startFrac: 0.6, endFrac: 0.7, kind: .meditating),
            WaySpan(startFrac: 0.2, endFrac: 0.4, kind: .talking),
        ]
        let segments = PilgrimMapView.HonorWayRendering.segments(route: straightRoute(), spans: spans)
        XCTAssertEqual(segments.map(\.kind), ["walking", "talking", "walking", "meditating", "walking"])
        for (previous, next) in zip(segments, segments.dropFirst()) {
            XCTAssertEqual(previous.coordinates.last?.longitude ?? -1, next.coordinates.first?.longitude ?? -2, accuracy: 1e-9)
        }
        XCTAssertEqual(segments.first?.coordinates.first?.longitude ?? -1, 0, accuracy: 1e-9)
        XCTAssertEqual(segments.last?.coordinates.last?.longitude ?? -1, 10 * 0.000898, accuracy: 1e-9)
        XCTAssertEqual(segments[1].coordinates.first?.longitude ?? -1, 2 * 0.000898, accuracy: 1e-6)
    }

    func testNoSpansIsOneWalkingSegmentAndOverlapsNeverReachBack() {
        let route = straightRoute()
        let whole = PilgrimMapView.HonorWayRendering.segments(route: route, spans: [])
        XCTAssertEqual(whole.map(\.kind), ["walking"])
        XCTAssertEqual(whole.first?.coordinates.count, route.count)
        let overlapping = [
            WaySpan(startFrac: 0.1, endFrac: 0.5, kind: .talking),
            WaySpan(startFrac: 0.3, endFrac: 0.6, kind: .meditating),
        ]
        let segments = PilgrimMapView.HonorWayRendering.segments(route: route, spans: overlapping)
        XCTAssertEqual(segments.map(\.kind), ["walking", "talking", "meditating", "walking"])
    }

    func testStateFromAWayCarriesItsSpans() {
        let way = Way(id: "walk:t", source: .ownWalk(UUID()), title: "t", departedAt: Date(), tzIdentifier: nil, expires: nil,
                      route: straightRoute(), totalDistanceMeters: 1000, theirActiveSeconds: 600, moments: [], weather: nil,
                      spans: [WaySpan(startFrac: 0.5, endFrac: 0.8, kind: .talking)])
        XCTAssertEqual(HonorWayState(way: way).segments.map(\.kind), ["walking", "talking", "walking"])
    }
}

extension HonorWayRenderingTests {

    func testEveryWayPinKindNamesItsMoment() {
        XCTAssertEqual(PilgrimAnnotation.Kind.wayVoice(id: "voice-1", heard: false).wayMomentID, "voice-1")
        XCTAssertEqual(PilgrimAnnotation.Kind.wayPhoto(id: "photo-1").wayMomentID, "photo-1")
        XCTAssertEqual(PilgrimAnnotation.Kind.wayRest(id: "rest-1", minutes: 3).wayMomentID, "rest-1")
        XCTAssertEqual(PilgrimAnnotation.Kind.waySit(id: "sit-1", minutes: 9).wayMomentID, "sit-1")
        XCTAssertEqual(PilgrimAnnotation.Kind.wayWaypoint(id: "waypoint-1", label: "Oak", icon: "leaf").wayMomentID, "waypoint-1")
        XCTAssertNil(PilgrimAnnotation.Kind.photo(localIdentifier: "x").wayMomentID)
    }
}

extension HonorWayRenderingTests {

    func testRelationLineSaysHereWithinAFewStridesAndNamesThePlace() {
        XCTAssertEqual(WayMomentHeader.relation(distanceMeters: 12, place: nil), "here")
        XCTAssertEqual(WayMomentHeader.relation(distanceMeters: 29.6, place: nil), "here")
        XCTAssertEqual(WayMomentHeader.relation(distanceMeters: 40.4, place: nil), "40 m away")
        XCTAssertEqual(WayMomentHeader.relation(distanceMeters: 40, place: "Rúa do Franco"), "40 m away · Rúa do Franco")
        XCTAssertEqual(WayMomentHeader.relation(distanceMeters: nil, place: "Rúa do Franco"), "Rúa do Franco")
        XCTAssertNil(WayMomentHeader.relation(distanceMeters: nil, place: ""))
        XCTAssertNil(WayMomentHeader.relation(distanceMeters: nil, place: nil))
    }
}
