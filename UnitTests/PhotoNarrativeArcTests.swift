import XCTest
@testable import Pilgrim

final class PhotoNarrativeArcTests: XCTestCase {

    // MARK: - Attention arc

    func testAttentionArc_detailToWide() {
        let entries = [
            entry(salientRegion: "center"),
            entry(salientRegion: "center"),
            entry(salientRegion: "top")
        ]

        let arc = PhotoNarrativeArcBuilder.build(from: entries)

        XCTAssertEqual(arc.attentionArc, "detail_to_wide")
    }

    func testAttentionArc_wideToDetail() {
        let entries = [
            entry(salientRegion: "top"),
            entry(salientRegion: "center"),
            entry(salientRegion: "bottom")
        ]

        let arc = PhotoNarrativeArcBuilder.build(from: entries)

        XCTAssertEqual(arc.attentionArc, "wide_to_detail")
    }

    func testAttentionArc_consistentlyClose() {
        let entries = [
            entry(salientRegion: "center"),
            entry(salientRegion: "center"),
            entry(salientRegion: "bottom")
        ]

        let arc = PhotoNarrativeArcBuilder.build(from: entries)

        XCTAssertEqual(arc.attentionArc, "consistently_close")
    }

    func testAttentionArc_singlePhoto() {
        let entries = [entry(salientRegion: "center")]

        let arc = PhotoNarrativeArcBuilder.build(from: entries)

        XCTAssertEqual(arc.attentionArc, "single")
    }

    func testAttentionArc_emptyReturnsNone() {
        let arc = PhotoNarrativeArcBuilder.build(from: [])

        XCTAssertEqual(arc.attentionArc, "none")
    }

    // MARK: - Solitude

    func testSolitude_aloneWhenNoPeople() {
        let entries = [
            entry(people: 0),
            entry(people: 0)
        ]

        let arc = PhotoNarrativeArcBuilder.build(from: entries)

        XCTAssertEqual(arc.solitude, "alone")
    }

    func testSolitude_withOthersWhenAllHavePeople() {
        let entries = [
            entry(people: 2),
            entry(people: 1)
        ]

        let arc = PhotoNarrativeArcBuilder.build(from: entries)

        XCTAssertEqual(arc.solitude, "with_others")
    }

    func testSolitude_mixedWhenSomeHavePeople() {
        let entries = [
            entry(people: 0),
            entry(people: 3),
            entry(people: 0)
        ]

        let arc = PhotoNarrativeArcBuilder.build(from: entries)

        XCTAssertEqual(arc.solitude, "mixed")
    }

    // MARK: - Recurring theme

    func testRecurringTheme_tagsAppearingInHalfOrMore() {
        let entries = [
            entry(tags: ["forest", "path", "moss"]),
            entry(tags: ["forest", "bridge", "stone"]),
            entry(tags: ["forest", "field", "sky"])
        ]

        let arc = PhotoNarrativeArcBuilder.build(from: entries)

        XCTAssertTrue(arc.recurringTheme.contains("forest"))
        XCTAssertFalse(arc.recurringTheme.contains("moss"))
    }

    func testRecurringTheme_emptyWhenNoRepeats() {
        let entries = [
            entry(tags: ["a"]),
            entry(tags: ["b"]),
            entry(tags: ["c"])
        ]

        let arc = PhotoNarrativeArcBuilder.build(from: entries)

        XCTAssertTrue(arc.recurringTheme.isEmpty)
    }

    // MARK: - Dominant colors

    func testDominantColors_preservesOrderFromEntries() {
        let entries = [
            entry(dominantColor: "#FF0000"),
            entry(dominantColor: "#00FF00"),
            entry(dominantColor: "#0000FF")
        ]

        let arc = PhotoNarrativeArcBuilder.build(from: entries)

        XCTAssertEqual(arc.dominantColors, ["#FF0000", "#00FF00", "#0000FF"])
    }

    // MARK: - Helpers

    private func entry(
        tags: [String] = [],
        salientRegion: String = "center",
        people: Int = 0,
        dominantColor: String = "#808080"
    ) -> PhotoNarrativeArcBuilder.Entry {
        PhotoNarrativeArcBuilder.Entry(
            context: PhotoContext(
                tags: tags,
                detectedText: [],
                people: people,
                animals: [],
                outdoor: true,
                salientRegion: salientRegion,
                dominantColor: dominantColor
            ),
            capturedAt: Date(),
            distanceIntoWalk: 0
        )
    }
}
