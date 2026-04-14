import XCTest
@testable import Pilgrim

final class WalkPhotoMatcherTests: XCTestCase {

    private let walkStart = Date(timeIntervalSince1970: 1700000000)
    private let walkEnd = Date(timeIntervalSince1970: 1700003600) // +1 hour

    private func source(
        id: String = "id",
        creationDate: Date?,
        latitude: Double? = 35.0116,
        longitude: Double? = 135.7681,
        isScreenshot: Bool = false
    ) -> PhotoCandidateSource {
        PhotoCandidateSource(
            localIdentifier: id,
            creationDate: creationDate,
            latitude: latitude,
            longitude: longitude,
            isScreenshot: isScreenshot
        )
    }

    func testFilter_keepsPhotoWithinTimeWindow() {
        let mid = Date(timeIntervalSince1970: 1700001800)
        let result = WalkPhotoMatcher.filterCandidates(
            sources: [source(creationDate: mid)],
            walkStartDate: walkStart,
            walkEndDate: walkEnd,
            pinnedIdentifiers: []
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.localIdentifier, "id")
    }

    func testFilter_dropsPhotoBeforeWalkStart() {
        let tooEarly = Date(timeIntervalSince1970: 1699999000)
        let result = WalkPhotoMatcher.filterCandidates(
            sources: [source(creationDate: tooEarly)],
            walkStartDate: walkStart,
            walkEndDate: walkEnd,
            pinnedIdentifiers: []
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testFilter_dropsPhotoAfterWalkEnd() {
        let tooLate = Date(timeIntervalSince1970: 1700004000)
        let result = WalkPhotoMatcher.filterCandidates(
            sources: [source(creationDate: tooLate)],
            walkStartDate: walkStart,
            walkEndDate: walkEnd,
            pinnedIdentifiers: []
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testFilter_dropsPhotoWithoutCreationDate() {
        let result = WalkPhotoMatcher.filterCandidates(
            sources: [source(creationDate: nil)],
            walkStartDate: walkStart,
            walkEndDate: walkEnd,
            pinnedIdentifiers: []
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testFilter_dropsPhotoWithoutLocation() {
        let mid = Date(timeIntervalSince1970: 1700001800)
        let result = WalkPhotoMatcher.filterCandidates(
            sources: [source(creationDate: mid, latitude: nil, longitude: nil)],
            walkStartDate: walkStart,
            walkEndDate: walkEnd,
            pinnedIdentifiers: []
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testFilter_dropsScreenshot() {
        let mid = Date(timeIntervalSince1970: 1700001800)
        let result = WalkPhotoMatcher.filterCandidates(
            sources: [source(creationDate: mid, isScreenshot: true)],
            walkStartDate: walkStart,
            walkEndDate: walkEnd,
            pinnedIdentifiers: []
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testFilter_marksPinnedPhotos() {
        let mid = Date(timeIntervalSince1970: 1700001800)
        let result = WalkPhotoMatcher.filterCandidates(
            sources: [source(id: "pinned", creationDate: mid)],
            walkStartDate: walkStart,
            walkEndDate: walkEnd,
            pinnedIdentifiers: ["pinned"]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result.first?.isPinned ?? false)
    }

    func testFilter_unpinnedPhotos_isPinnedFalse() {
        let mid = Date(timeIntervalSince1970: 1700001800)
        let result = WalkPhotoMatcher.filterCandidates(
            sources: [source(id: "candidate", creationDate: mid)],
            walkStartDate: walkStart,
            walkEndDate: walkEnd,
            pinnedIdentifiers: ["some-other-id"]
        )
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result.first?.isPinned ?? true)
    }

    func testFilter_sortsByCapturedAtAscending() {
        let early = Date(timeIntervalSince1970: 1700001000)
        let late = Date(timeIntervalSince1970: 1700003000)
        let result = WalkPhotoMatcher.filterCandidates(
            sources: [
                source(id: "late", creationDate: late),
                source(id: "early", creationDate: early)
            ],
            walkStartDate: walkStart,
            walkEndDate: walkEnd,
            pinnedIdentifiers: []
        )
        XCTAssertEqual(result.map { $0.localIdentifier }, ["early", "late"])
    }

    func testFilter_keepsPhotoExactlyAtStart() {
        let result = WalkPhotoMatcher.filterCandidates(
            sources: [source(creationDate: walkStart)],
            walkStartDate: walkStart,
            walkEndDate: walkEnd,
            pinnedIdentifiers: []
        )
        XCTAssertEqual(result.count, 1)
    }

    func testFilter_keepsPhotoExactlyAtEnd() {
        let result = WalkPhotoMatcher.filterCandidates(
            sources: [source(creationDate: walkEnd)],
            walkStartDate: walkStart,
            walkEndDate: walkEnd,
            pinnedIdentifiers: []
        )
        XCTAssertEqual(result.count, 1)
    }

    func testFilter_emptySources_returnsEmpty() {
        let result = WalkPhotoMatcher.filterCandidates(
            sources: [],
            walkStartDate: walkStart,
            walkEndDate: walkEnd,
            pinnedIdentifiers: []
        )
        XCTAssertTrue(result.isEmpty)
    }

    func testFilter_populatesCoordinateFields() {
        let mid = Date(timeIntervalSince1970: 1700001800)
        let result = WalkPhotoMatcher.filterCandidates(
            sources: [source(creationDate: mid, latitude: 43.7696, longitude: 11.2558)],
            walkStartDate: walkStart,
            walkEndDate: walkEnd,
            pinnedIdentifiers: []
        )
        XCTAssertEqual(result.first?.capturedLat, 43.7696)
        XCTAssertEqual(result.first?.capturedLng, 11.2558)
        XCTAssertEqual(result.first?.capturedAt, mid)
    }
}
