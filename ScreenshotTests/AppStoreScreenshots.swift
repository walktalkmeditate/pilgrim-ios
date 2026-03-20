import XCTest

final class AppStoreScreenshots: ScreenshotTestCase {

    func test01_WalkStart() {
        Thread.sleep(forTimeInterval: 2)
        capture("01_walk_start")
    }

    func test02_ActiveWalkAndMeditation() {
        switchToDarkMode()
        startWalkAndCapture(prefix: "")
    }

    func test03_WalkSummary() {
        tapTab("Journal")
        Thread.sleep(forTimeInterval: 2)

        let dots = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'walk_dot_'"))
        guard dots.count > 0 else {
            capture("04_walk_summary_fallback")
            return
        }

        dots.element(boundBy: 0).tap()
        Thread.sleep(forTimeInterval: 1)

        let detailsButton = app.buttons["walk_details_button"].firstMatch
        guard detailsButton.waitForExistence(timeout: 3) else {
            capture("04_walk_summary_fallback")
            return
        }

        detailsButton.tap()
        Thread.sleep(forTimeInterval: 3)
        capture("04_walk_summary")

        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        capture("05_walk_stats")

        app.swipeUp()
        Thread.sleep(forTimeInterval: 1)
        capture("06_walk_activity")
    }

    func test04_JournalAndGoshuin() {
        switchToDarkMode()

        tapTab("Journal")
        Thread.sleep(forTimeInterval: 2)
        capture("07_journal")

        let goshuinFab = app.buttons["goshuin_fab"]
        if goshuinFab.waitForExistence(timeout: 3) {
            goshuinFab.tap()
            Thread.sleep(forTimeInterval: 3)
            capture("08_goshuin")

            app.buttons["Done"].firstMatch.tap()
            Thread.sleep(forTimeInterval: 1)
        }
    }

    func test05_Settings() {
        switchToDarkMode()
        tapTab("Settings")
        Thread.sleep(forTimeInterval: 2)
        capture("09_settings")
    }

    private func switchToDarkMode() {
        tapTab("Settings")
        Thread.sleep(forTimeInterval: 1)
        let darkButton = app.buttons["Dark"]
        if darkButton.waitForExistence(timeout: 3) {
            darkButton.tap()
            Thread.sleep(forTimeInterval: 1)
        }
    }
}
