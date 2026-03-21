import XCTest

final class VideoWalkthrough: ScreenshotTestCase {

    func test_AppPreviewVideo() {

        // === ACT 1: The Threshold (0-6s) ===

        // Hold on walk start screen — this is the poster frame
        Thread.sleep(forTimeInterval: 3)

        // Set intention
        let intentionButton = app.buttons["Set intention"]
        if intentionButton.waitForExistence(timeout: 2) {
            intentionButton.tap()
            Thread.sleep(forTimeInterval: 1)

            let textField = app.textFields.firstMatch
            if textField.waitForExistence(timeout: 2) {
                textField.tap()
                textField.typeText("Walk slowly today. Notice what you usually miss.")
                Thread.sleep(forTimeInterval: 1)

                let doneButton = app.buttons["Done"]
                if doneButton.exists { doneButton.tap() }
            }
            Thread.sleep(forTimeInterval: 1)
        }

        // Tap Wander to enter walk screen
        var walkButton = app.buttons["start_walk_button"]
        if !walkButton.waitForExistence(timeout: 2) {
            walkButton = app.buttons["Wander"]
        }
        if !walkButton.waitForExistence(timeout: 2) {
            walkButton = app.buttons["Begin your journey"]
        }
        guard walkButton.waitForExistence(timeout: 2), walkButton.isHittable else { return }
        walkButton.tap()

        handlePermissionAlerts()
        Thread.sleep(forTimeInterval: 2)
        handlePermissionAlerts()

        // === ACT 2: The Walk (6-12s) ===

        // Tap Start to begin recording
        let startButton = app.buttons["Start"]
        if startButton.waitForExistence(timeout: 5) {
            startButton.tap()
        }

        // Let the walk run — stats tick up, route draws
        Thread.sleep(forTimeInterval: 8)

        // === ACT 3: Stillness (12-16s) ===

        let meditateButton = app.buttons["Meditate"]
        if meditateButton.waitForExistence(timeout: 3) {
            meditateButton.tap()

            // Hold on the breathing circle
            Thread.sleep(forTimeInterval: 5)

            // Close meditation
            let closeButton = app.buttons["Close"]
            if closeButton.waitForExistence(timeout: 2) {
                closeButton.tap()
            } else {
                app.swipeDown()
            }
            Thread.sleep(forTimeInterval: 1)
        }

        // === ACT 4: Voice (16-19s) ===

        let recordButton = app.buttons["Record"]
        if recordButton.waitForExistence(timeout: 2) {
            recordButton.tap()
            Thread.sleep(forTimeInterval: 3)
            recordButton.tap()
            Thread.sleep(forTimeInterval: 1)
        }

        // === ACT 5: The Return (19-27s) ===

        // End the walk
        let endButton = app.buttons["End"]
        if endButton.waitForExistence(timeout: 2) {
            endButton.tap()
            let confirmEnd = app.buttons["End Walk"]
            if confirmEnd.waitForExistence(timeout: 2) {
                confirmEnd.tap()
            }
        }

        // Goshuin seal reveal — let it breathe
        Thread.sleep(forTimeInterval: 4)

        // Dismiss seal to see summary
        let sealDismiss = app.buttons["Done"].firstMatch
        if sealDismiss.waitForExistence(timeout: 3) {
            sealDismiss.tap()
        } else {
            app.tap()
        }
        Thread.sleep(forTimeInterval: 2)

        // Scroll through the summary slowly
        app.swipeUp(velocity: .slow)
        Thread.sleep(forTimeInterval: 2)

        app.swipeUp(velocity: .slow)
        Thread.sleep(forTimeInterval: 2)

        app.swipeUp(velocity: .slow)
        Thread.sleep(forTimeInterval: 3)

        // === ACT 6: Rest (27-30s) ===

        // Final hold
        Thread.sleep(forTimeInterval: 3)
    }
}
