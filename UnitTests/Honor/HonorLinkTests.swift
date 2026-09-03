import XCTest
@testable import Pilgrim

final class HonorLinkTests: XCTestCase {

    func testAcceptedForms() {
        for s in ["https://honor.pilgrimapp.org/Qoi4YmPHLN", "https://honor.pilgrimapp.org/Qoi4YmPHLN/",
                  "https://honor.pilgrimapp.org/Qoi4YmPHLN?utm=x#m3", "https://walk.pilgrimapp.org/Qoi4YmPHLN",
                  "walk.pilgrimapp.org/Qoi4YmPHLN", "Qoi4YmPHLN", "  Qoi4YmPHLN\n"] {
            XCTAssertEqual(HonorLink.parse(text: s), "Qoi4YmPHLN", s)
        }
        XCTAssertEqual(HonorLink.parse(URL(string: "https://honor.pilgrimapp.org/Qoi4YmPHLN")!), "Qoi4YmPHLN")
    }

    func testRejections() {
        for s in ["https://example.com/Qoi4YmPHLN", "https://walk.pilgrimapp.org/", "https://walk.pilgrimapp.org/short",
                  "https://walk.pilgrimapp.org/Qoi4YmPHLN/audio/1.m4a", "Qoi4YmPHL", "Qoi4YmPHLN1", ""] {
            XCTAssertNil(HonorLink.parse(text: s), s)
        }
    }

    func testHostIsCaseInsensitive() {
        XCTAssertEqual(HonorLink.parse(text: "https://HONOR.pilgrimapp.org/Qoi4YmPHLN"), "Qoi4YmPHLN")
        XCTAssertEqual(HonorLink.parse(URL(string: "https://HONOR.pilgrimapp.org/Qoi4YmPHLN")!), "Qoi4YmPHLN")
    }

    /// A cold-launch link is stashed on `PilgrimApp` for `MainTabView.onAppear`
    /// to claim once mounted; reading it must also clear it, so the same id
    /// can't be replayed a second time.
    @MainActor
    func testPendingShareIdIsDrainedOnce() {
        PilgrimApp.pendingShareId = "Qoi4YmPHLN"

        let drained = PilgrimApp.pendingShareId
        PilgrimApp.pendingShareId = nil

        XCTAssertEqual(drained, "Qoi4YmPHLN")
        XCTAssertNil(PilgrimApp.pendingShareId)
    }
}
