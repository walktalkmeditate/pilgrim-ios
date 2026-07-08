import XCTest
@testable import Pilgrim

final class SeekWispVisibilityTests: XCTestCase {

    private let viewSize = CGSize(width: 400, height: 800)

    private func release(
        wasReleased: Bool = false,
        center: CGPoint?,
        radius: CGFloat = 50
    ) -> Bool {
        SeekWispVisibilityModel.shouldRelease(
            wasReleased: wasReleased,
            fogCenter: center,
            fogRadiusPoints: radius,
            viewSize: viewSize
        )
    }

    // MARK: - Release (fog enters view)

    func testFogCenteredOnScreen_releases() {
        XCTAssertTrue(release(center: CGPoint(x: 200, y: 400)))
    }

    func testFogFarOffScreen_staysShown() {
        XCTAssertFalse(release(center: CGPoint(x: 3000, y: 400)))
    }

    func testUnprojectableFog_neverReleases_andAlwaysReturns() {
        // Mapbox's point(for:) collapses every off-view coordinate to
        // (-1, -1); the renderer maps that to nil. Field regression: the
        // sentinel used to read as a circle grazing the top-left corner,
        // releasing the crescent on the first camera event and pinning it
        // released forever.
        XCTAssertFalse(release(wasReleased: false, center: nil), "off-screen fog must not release")
        XCTAssertFalse(release(wasReleased: true, center: nil), "off-screen fog must hand the crescent back")
    }

    func testFogEdgeOverlapCountsEvenWithCenterOffScreen() {
        // Center 40 pt past the right edge with a 100 pt radius: the rim
        // reaches well inside the release inset.
        XCTAssertTrue(release(center: CGPoint(x: 440, y: 400), radius: 100))
    }

    func testFogMustReachPastTheInsetToRelease() {
        // Rim touches the raw edge but not the inset rect — not yet "seen".
        XCTAssertFalse(release(center: CGPoint(x: 445, y: 400), radius: 50))
    }

    // MARK: - Return (fog leaves view) with hysteresis

    func testReleasedFogJustOutsideEdge_staysReleased() {
        // Inside the outset band: released state holds.
        XCTAssertTrue(release(wasReleased: true, center: CGPoint(x: 460, y: 400), radius: 50))
    }

    func testReleasedFogBeyondTheOutset_returns() {
        XCTAssertFalse(release(wasReleased: true, center: CGPoint(x: 600, y: 400), radius: 50))
    }

    func testDeadZonePositionKeepsWhicheverStateItHad() {
        // Between the release inset and the return outset, both states hold.
        let deadZoneCenter = CGPoint(x: 430, y: 400)
        XCTAssertFalse(release(wasReleased: false, center: deadZoneCenter))
        XCTAssertTrue(release(wasReleased: true, center: deadZoneCenter))
    }

    // MARK: - Degenerate inputs

    func testZeroViewSize_keepsCurrentState() {
        for wasReleased in [true, false] {
            XCTAssertEqual(
                SeekWispVisibilityModel.shouldRelease(
                    wasReleased: wasReleased,
                    fogCenter: CGPoint(x: 10, y: 10),
                    fogRadiusPoints: 50,
                    viewSize: .zero
                ),
                wasReleased
            )
        }
    }

    func testNonFiniteCenter_keepsCurrentState() {
        for wasReleased in [true, false] {
            XCTAssertEqual(
                SeekWispVisibilityModel.shouldRelease(
                    wasReleased: wasReleased,
                    fogCenter: CGPoint(x: CGFloat.nan, y: 400),
                    fogRadiusPoints: 50,
                    viewSize: viewSize
                ),
                wasReleased
            )
        }
    }

    func testTinyViewSmallerThanTheInset_neverReleases() {
        XCTAssertFalse(
            SeekWispVisibilityModel.shouldRelease(
                wasReleased: false,
                fogCenter: CGPoint(x: 10, y: 10),
                fogRadiusPoints: 50,
                viewSize: CGSize(width: 30, height: 30)
            )
        )
    }

    // MARK: - Circle/rect intersection

    func testCircleIntersects_cornerDistanceCountsDiagonally() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 100)
        // 30√2 ≈ 42.4 from the corner: outside a 40 radius, inside a 45.
        let corner = CGPoint(x: 130, y: 130)
        XCTAssertFalse(SeekWispVisibilityModel.circleIntersects(center: corner, radius: 40, rect: rect))
        XCTAssertTrue(SeekWispVisibilityModel.circleIntersects(center: corner, radius: 45, rect: rect))
    }

    func testCircleIntersects_nullRectNeverIntersects() {
        XCTAssertFalse(
            SeekWispVisibilityModel.circleIntersects(
                center: .zero, radius: 1000, rect: .null
            )
        )
    }

    // MARK: - Light theme (dawn vs constellation starlight)

    func testCrescentLight_followsThePuckUnderConstellation() {
        let original = UserPreferences.appearanceMode.value
        defer { UserPreferences.appearanceMode.value = original }

        UserPreferences.appearanceMode.value = "constellation"
        XCTAssertEqual(
            PilgrimMapView.SeekWispRendering.lightColor(),
            SeasonalColorEngine.seasonalColor(named: "stone", intensity: .full),
            "under the constellation sky the crescent is starlight - the puck's own color"
        )
        XCTAssertTrue(
            PilgrimMapView.SeekWispRendering.imageID(spanDegrees: 72).hasSuffix("starlight"),
            "the cached image key must change with the theme or a stale dawn crescent survives the switch"
        )

        UserPreferences.appearanceMode.value = "light"
        XCTAssertTrue(PilgrimMapView.SeekWispRendering.imageID(spanDegrees: 72).hasSuffix("dawn"))
    }
}
