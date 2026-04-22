import XCTest
@testable import Pilgrim

@MainActor
final class WebViewLoaderTests: XCTestCase {

    private let shareURL = URL(string: "https://walk.pilgrimapp.org/abc123")!

    func testInitialState_isLoading() {
        let loader = WebViewLoader(url: shareURL)
        XCTAssertEqual(loader.loadState, .loading)
    }

    func testDidFinish_transitionsToLoaded() {
        let loader = WebViewLoader(url: shareURL)
        loader.handleDidFinish()
        XCTAssertEqual(loader.loadState, .loaded)
    }

    func testDidFail_transitionsToFailed() {
        let loader = WebViewLoader(url: shareURL)
        loader.handleDidFail()
        XCTAssertEqual(loader.loadState, .failed)
    }

    func testRetry_afterFailure_returnsToLoading() {
        let loader = WebViewLoader(url: shareURL)
        loader.handleDidFail()
        loader.retry()
        XCTAssertEqual(loader.loadState, .loading)
    }

    func testShouldAllowNavigation_initialURL_returnsTrue() {
        let loader = WebViewLoader(url: shareURL)
        XCTAssertTrue(loader.shouldAllowNavigation(to: shareURL))
    }

    func testShouldAllowNavigation_differentURL_returnsFalse() {
        let loader = WebViewLoader(url: shareURL)
        let external = URL(string: "https://apple.com/")!
        XCTAssertFalse(loader.shouldAllowNavigation(to: external))
    }

    func testShouldAllowNavigation_differentPathSameHost_returnsTrue() {
        let loader = WebViewLoader(url: shareURL)
        let other = URL(string: "https://walk.pilgrimapp.org/xyz999")!
        XCTAssertTrue(loader.shouldAllowNavigation(to: other))
    }

    func testShouldAllowNavigation_trailingSlashVariant_returnsTrue() {
        let loader = WebViewLoader(url: shareURL)
        let redirected = URL(string: "https://walk.pilgrimapp.org/abc123/")!
        XCTAssertTrue(loader.shouldAllowNavigation(to: redirected))
    }
}
