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
        handlePermissionAlerts()
        let tabBar = app.tabBars.firstMatch
        let exists = tabBar.waitForExistence(timeout: 15)
        XCTAssertTrue(exists, "App should launch to main tabs in demo mode")
    }

    func handlePermissionAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow While Using App"]
        if allowButton.waitForExistence(timeout: 3) {
            allowButton.tap()
        }
    }

    func startWalkAndCapture(prefix: String) {
        tapTab("Path")
        Thread.sleep(forTimeInterval: 1)

        let wanderButton = app.buttons["Wander"]
        guard wanderButton.waitForExistence(timeout: 3) else { return }
        wanderButton.tap()

        handlePermissionAlerts()

        Thread.sleep(forTimeInterval: 5)
        capture("\(prefix)05_active_walk")

        let meditateButton = app.buttons["Meditate"]
        if meditateButton.waitForExistence(timeout: 3) {
            meditateButton.tap()
            Thread.sleep(forTimeInterval: 3)
            capture("\(prefix)06_meditation")

            let closeButton = app.buttons["Close"]
            if closeButton.waitForExistence(timeout: 2) {
                closeButton.tap()
            } else {
                app.swipeDown()
            }
            Thread.sleep(forTimeInterval: 1)
        }

        let endButton = app.buttons["End"]
        if endButton.waitForExistence(timeout: 2) {
            endButton.tap()
            let confirmEnd = app.buttons["End Walk"]
            if confirmEnd.waitForExistence(timeout: 2) {
                confirmEnd.tap()
            }
        }
    }

    func capture(_ name: String) {
        let screenshot = app.windows.firstMatch.screenshot()

        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let dir = "/tmp/pilgrim-screenshots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = "\(dir)/\(name).png"
        try? screenshot.pngRepresentation.write(to: URL(fileURLWithPath: path))
        print("[Screenshot] Saved: \(path)")
    }

    func tapTab(_ label: String) {
        let tab = app.tabBars.buttons[label]
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "Tab '\(label)' should exist")
        tab.tap()
        Thread.sleep(forTimeInterval: 0.5)
    }
}
