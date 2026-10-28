import XCTest
@testable import Pilgrim

final class HonorLinkTests: XCTestCase {

    private func url(_ s: String) -> URL { URL(string: s)! }

    func testAcceptedForms() {
        for s in ["https://honor.pilgrimapp.org/Qoi4YmPHLN", "https://honor.pilgrimapp.org/Qoi4YmPHLN/",
                  "https://honor.pilgrimapp.org/Qoi4YmPHLN?utm=x#m3", "https://walk.pilgrimapp.org/Qoi4YmPHLN",
                  "walk.pilgrimapp.org/Qoi4YmPHLN", "Qoi4YmPHLN", "  Qoi4YmPHLN\n"] {
            XCTAssertEqual(HonorLink.parse(text: s), .share(id: "Qoi4YmPHLN"), s)
        }
        XCTAssertEqual(HonorLink.parse(url("https://honor.pilgrimapp.org/Qoi4YmPHLN")), .share(id: "Qoi4YmPHLN"))
    }

    func testRejections() {
        for s in ["https://example.com/Qoi4YmPHLN", "https://walk.pilgrimapp.org/", "https://walk.pilgrimapp.org/short",
                  "https://walk.pilgrimapp.org/Qoi4YmPHLN/audio/1.m4a", "Qoi4YmPHL", "Qoi4YmPHLN1", ""] {
            XCTAssertNil(HonorLink.parse(text: s), s)
        }
    }

    func testHostIsCaseInsensitive() {
        XCTAssertEqual(HonorLink.parse(text: "https://HONOR.pilgrimapp.org/Qoi4YmPHLN"), .share(id: "Qoi4YmPHLN"))
        XCTAssertEqual(HonorLink.parse(url("https://HONOR.pilgrimapp.org/Qoi4YmPHLN")), .share(id: "Qoi4YmPHLN"))
    }

    func testStageLinksCountFromOne() {
        for s in ["https://honor.pilgrimapp.org/camino-frances/14", "https://honor.pilgrimapp.org/camino-frances/14/",
                  "https://honor.pilgrimapp.org/camino-frances/14?utm_source=pilgrimages#x"] {
            XCTAssertEqual(HonorLink.parse(url(s)), .stage(routeId: "camino-frances", index: 13), s)
        }
        XCTAssertEqual(HonorLink.parse(url("https://honor.pilgrimapp.org/shikoku-88-tosa/1")),
                       .stage(routeId: "shikoku-88-tosa", index: 0))
        XCTAssertEqual(HonorLink.parse(url("https://honor.pilgrimapp.org/camino-frances/200")),
                       .stage(routeId: "camino-frances", index: 199))
    }

    func testMalformedStageLinksOnTheHonorHostAreUnrecognised() {
        for s in ["https://honor.pilgrimapp.org/camino-frances/0", "https://honor.pilgrimapp.org/camino-frances/014",
                  "https://honor.pilgrimapp.org/camino-frances/201", "https://honor.pilgrimapp.org/Camino-Frances/14",
                  "https://honor.pilgrimapp.org/camino-frances", "https://honor.pilgrimapp.org/a/b/c",
                  "https://honor.pilgrimapp.org/Qoi4YmPHLN/extra"] {
            XCTAssertEqual(HonorLink.parse(url(s)), .unrecognised, s)
        }
    }

    func testStageLinksLiveOnlyOnTheHonorHost() {
        XCTAssertNil(HonorLink.parse(url("https://walk.pilgrimapp.org/camino-frances/14")))
        XCTAssertNil(HonorLink.parse(url("https://example.com/camino-frances/14")))
    }

    func testTheHonorHostRootIsNotALink() {
        XCTAssertNil(HonorLink.parse(url("https://honor.pilgrimapp.org/")))
        XCTAssertNil(HonorLink.parse(url("https://honor.pilgrimapp.org")))
    }

    func testPastedStageLinksAreAccepted() {
        XCTAssertEqual(HonorLink.parse(text: "honor.pilgrimapp.org/camino-frances/14"),
                       .stage(routeId: "camino-frances", index: 13))
        XCTAssertEqual(HonorLink.parse(text: " https://honor.pilgrimapp.org/camino-frances/14\n"),
                       .stage(routeId: "camino-frances", index: 13))
    }

    func testPastedTextNeverComesBackUnrecognised() {
        XCTAssertNil(HonorLink.parse(text: "https://honor.pilgrimapp.org/camino-frances/0"))
        XCTAssertNil(HonorLink.parse(text: "honor.pilgrimapp.org/whatever/else/here"))
    }

    /// A cold-launch link is stashed on `PilgrimApp` for `MainTabView.onAppear`
    /// to claim once mounted; reading it must also clear it, so the same link
    /// can't be replayed a second time.
    @MainActor
    func testPendingLinkIsDrainedOnce() {
        PilgrimApp.pendingLink = .stage(routeId: "camino-frances", index: 13)

        let drained = PilgrimApp.pendingLink
        PilgrimApp.pendingLink = nil

        XCTAssertEqual(drained, .stage(routeId: "camino-frances", index: 13))
        XCTAssertNil(PilgrimApp.pendingLink)
    }

    /// `$` in a regex matches before a trailing newline, so an id pasted with
    /// one used to pass every shape check in the pipeline.
    func testTrailingNewlineIsRejected() {
        // Pasted text is trimmed first, so the newline has to arrive by a
        // path that does not trim — an encoded one inside the URL itself.
        XCTAssertEqual(HonorLink.parse(url("https://honor.pilgrimapp.org/Qoi4YmPHLN%0A")), .unrecognised)
        XCTAssertEqual(HonorLink.parse(url("https://honor.pilgrimapp.org/camino-frances/14%0A")), .unrecognised)
        XCTAssertFalse(WayImporter.isShareId("Qoi4YmPHLN\n"))
        XCTAssertFalse(WayStore.isValidId("share:Qoi4YmPHLN\n"))
        XCTAssertFalse(WayStore.isValidId("walk:\(UUID().uuidString)\n"))
    }
}
