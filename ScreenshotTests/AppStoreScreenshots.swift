import XCTest

final class AppStoreScreenshots: ScreenshotTestCase {

    // MARK: - Light Mode Screens

    func test01_PathTab() {
        Thread.sleep(forTimeInterval: 2)
        capture("01_path_walk_start")
    }

    func test02_ActiveWalk() {
        startWalkAndCapture(prefix: "")
    }

    func test04_WalkSummary() {
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
                capture("05_walk_summary_voice")

                app.swipeUp()
                Thread.sleep(forTimeInterval: 0.5)
                capture("05b_walk_summary_details")
                return
            }
        }

        capture("04_walk_summary_fallback")
    }

    // MARK: - Dark Mode Screens (Meditation + Journal + Settings)

    func test03_Meditation_Dark() {
        switchToDarkMode()
        startWalkAndCapture(prefix: "dark_")
    }

    func test06_Journal_Dark() {
        switchToDarkMode()
        tapTab("Journal")
        Thread.sleep(forTimeInterval: 2)
        capture("06_journal_dark")
    }

    func test07_Settings_Dark() {
        switchToDarkMode()
        tapTab("Settings")
        Thread.sleep(forTimeInterval: 2)
        capture("07_settings_dark")
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
