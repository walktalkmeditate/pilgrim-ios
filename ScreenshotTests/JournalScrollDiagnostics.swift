import XCTest

/// Diagnostic (not a shipping screenshot test): reproduces the reported
/// ink-scroll bug where dots vanish while scrolling a deep journal. Seeds
/// 90 walks via --demo-journal-stress, scrolls the Journal in steps, and
/// logs how many walk dots exist in the hierarchy at each depth. A healthy
/// culling window keeps a steady handful of dots alive at every depth; the
/// bug shows up as the count collapsing to zero partway down.
final class JournalScrollDiagnostics: XCTestCase {

    func testDotsSurviveDeepScroll() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--demo-mode",
            "--demo-journal-stress",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow While Using App"]
        if allowButton.waitForExistence(timeout: 5) {
            allowButton.tap()
        }

        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 90), "app should reach main tabs (90-walk stress seed takes a while)")
        app.tabBars.buttons["Journal"].tap()
        Thread.sleep(forTimeInterval: 3)

        var counts: [Int] = []
        for step in 0..<24 {
            let dotCount = app.descendants(matching: .any)
                .matching(NSPredicate(format: "identifier BEGINSWITH 'walk_dot_'"))
                .count
            counts.append(dotCount)
            print("JOURNAL-DIAG step \(step): \(dotCount) dots alive")
            if step % 6 == 0 {
                let attachment = XCTAttachment(image: XCUIScreen.main.screenshot().image)
                attachment.name = "depth-step-\(step)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            app.swipeUp(velocity: .fast)
        }
        Thread.sleep(forTimeInterval: 1)
        let finalCount = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'walk_dot_'"))
            .count
        print("JOURNAL-DIAG final: \(finalCount) dots alive; history: \(counts)")

        // Round trip: dots near the top were culled while we were deep and
        // remount OFF-screen on the way back. If scenery mounted off-screen
        // never draws (TimelineView pause heuristic), the top's previously
        // visible items will now be missing too.
        for _ in 0..<26 {
            app.swipeDown(velocity: .fast)
        }
        Thread.sleep(forTimeInterval: 1.5)
        let returnShot = XCTAttachment(image: XCUIScreen.main.screenshot().image)
        returnShot.name = "back-at-top-after-deep-scroll"
        returnShot.lifetime = .keepAlways
        add(returnShot)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "journal-deep-scroll"
        attachment.lifetime = .keepAlways
        add(attachment)

        XCTAssertGreaterThan(
            finalCount, 0,
            "after deep scrolling, the culling window must still contain dots — zero means the window lost the scroll position"
        )
    }

    /// Catches the transient form of the bug: XCUIScreen screenshots do not
    /// wait for app quiescence, so shots taken right after launching a hard
    /// fling capture the journal mid-deceleration — where a lagging render
    /// window shows as blank parchment scrolling in where dots should be.
    func testDotsDuringHardFling() throws {
        let app = XCUIApplication()
        app.launchArguments += [
            "--demo-mode",
            "--demo-journal-stress",
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
        ]
        app.launch()

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allowButton = springboard.buttons["Allow While Using App"]
        if allowButton.waitForExistence(timeout: 5) {
            allowButton.tap()
        }
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 90))
        app.tabBars.buttons["Journal"].tap()
        Thread.sleep(forTimeInterval: 3)

        for round in 0..<3 {
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            start.press(forDuration: 0.02, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)

            for shot in 0..<4 {
                let attachment = XCTAttachment(image: XCUIScreen.main.screenshot().image)
                attachment.name = "fling-\(round)-shot-\(shot)"
                attachment.lifetime = .keepAlways
                add(attachment)
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
    }
}
