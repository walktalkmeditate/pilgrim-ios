import XCTest

final class AppStoreScreenshots: ScreenshotTestCase {

    func test01_PathTab() {
        tapTab("tab_path")
        Thread.sleep(forTimeInterval: 2)
        capture("01_path_walk_start")
    }

    func test02_JournalTab() {
        tapTab("tab_journal")
        Thread.sleep(forTimeInterval: 2)
        capture("02_journal_walk_history")
    }

    func test03_WalkSummary() {
        tapTab("tab_journal")
        Thread.sleep(forTimeInterval: 2)

        let firstDot = app.otherElements.matching(identifier: "walk_dot").firstMatch
        if firstDot.waitForExistence(timeout: 3) {
            firstDot.tap()
            Thread.sleep(forTimeInterval: 0.5)
        }

        let detailsButton = app.buttons["walk_details_button"].firstMatch
        if detailsButton.waitForExistence(timeout: 3) {
            detailsButton.tap()
            Thread.sleep(forTimeInterval: 2)
            capture("03_walk_summary")

            app.swipeUp()
            Thread.sleep(forTimeInterval: 0.5)
            capture("03b_walk_summary_scrolled")
        }
    }

    func test04_Settings() {
        tapTab("tab_settings")
        Thread.sleep(forTimeInterval: 2)
        capture("04_settings")
    }
}
