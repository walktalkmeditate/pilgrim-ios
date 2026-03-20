import XCTest

class ScreenshotTestCase: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--demo-mode"]
        app.launch()
        waitForDemoData()
    }

    private func waitForDemoData() {
        let journalTab = app.buttons["tab_journal"]
        let exists = journalTab.waitForExistence(timeout: 15)
        XCTAssertTrue(exists, "App should launch to main tabs in demo mode")
    }

    func capture(_ name: String) {
        let screenshot = app.windows.firstMatch.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func tapTab(_ identifier: String) {
        let tab = app.buttons[identifier]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Tab \(identifier) should exist")
        tab.tap()
        Thread.sleep(forTimeInterval: 0.5)
    }
}
