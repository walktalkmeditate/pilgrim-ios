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

        let window = app.windows.firstMatch

        for yOffset in stride(from: 0.3, through: 0.7, by: 0.1) {
            let dot = window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: yOffset))
            dot.tap()
            Thread.sleep(forTimeInterval: 0.5)

            let detailsButton = app.buttons["walk_details_button"].firstMatch
            if detailsButton.exists {
                detailsButton.tap()
                Thread.sleep(forTimeInterval: 3)
                capture("04_walk_summary")

                app.swipeUp()
                Thread.sleep(forTimeInterval: 1)
                capture("05_walk_stats")

                app.swipeUp()
                Thread.sleep(forTimeInterval: 1)
                capture("06_walk_activity")
                return
            }
        }

        capture("04_walk_summary_fallback")
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
