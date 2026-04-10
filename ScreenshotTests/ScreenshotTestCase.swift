import XCTest

class ScreenshotTestCase: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += [
            "--demo-mode",
            // Force default Dynamic Type so screenshots render consistently
            // regardless of whatever accessibility text size the simulator
            // happens to be configured with.
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ]
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

        var walkButton = app.buttons["start_walk_button"]
        if !walkButton.waitForExistence(timeout: 3) {
            walkButton = app.buttons["Wander"]
        }
        if !walkButton.waitForExistence(timeout: 3) {
            walkButton = app.buttons["Begin your journey"]
        }
        guard walkButton.waitForExistence(timeout: 3), walkButton.isHittable else {
            capture("\(prefix)02_walk_start_fallback")
            return
        }
        walkButton.tap()

        handlePermissionAlerts()
        Thread.sleep(forTimeInterval: 2)
        handlePermissionAlerts()

        let startButton = app.buttons["Start"]
        if startButton.waitForExistence(timeout: 5) {
            startButton.tap()
            Thread.sleep(forTimeInterval: 8)
        }

        capture("\(prefix)02_active_walk")

        let meditateButton = app.buttons["Meditate"]
        if meditateButton.waitForExistence(timeout: 3) {
            meditateButton.tap()
            Thread.sleep(forTimeInterval: 3)
            capture("\(prefix)03_meditation")

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
            Thread.sleep(forTimeInterval: 3)
            capture("\(prefix)08_goshuin_seal")
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
