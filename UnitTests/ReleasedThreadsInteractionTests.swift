import XCTest
@testable import Pilgrim

final class ReleasedThreadsInteractionTests: XCTestCase {

    func testReleaseConfirmCopy_exactStrings() {
        XCTAssertEqual(ReleasedThreadsCopy.releaseTitle("my father"), "Let 'my father' go?")
        XCTAssertEqual(ReleasedThreadsCopy.releaseMessage, "You can welcome it back anytime.")
        XCTAssertEqual(ReleasedThreadsCopy.releaseConfirm, "Let it go")
        XCTAssertEqual(ReleasedThreadsCopy.releaseCancel, "Not now")
    }

    func testWelcomeBackConfirmCopy_exactStrings() {
        XCTAssertEqual(ReleasedThreadsCopy.welcomeBackTitle("my father"), "Welcome 'my father' back?")
        XCTAssertEqual(ReleasedThreadsCopy.welcomeBackMessage, "Threads will notice it again.")
        XCTAssertEqual(ReleasedThreadsCopy.welcomeBackConfirm, "Welcome it back")
        XCTAssertEqual(ReleasedThreadsCopy.welcomeBackCancel, "Not now")
    }

    func testCaptionCopy_exactString() {
        XCTAssertEqual(ReleasedThreadsCopy.caption, "long-press a theme to let it go")
    }

    func testVoiceOverActionName_exactString() {
        XCTAssertEqual(ReleasedThreadsCopy.voiceOverActionName, "Let this go")
    }

    private func model(terms: [String]) -> ThreadsCardModel {
        ThreadsCardModel(
            themes: terms.map { ThreadsCardTheme(displayTerm: $0, lemmas: [$0], statusNote: nil) },
            textureLine: nil,
            insightWords: [],
            hasInsight: false
        )
    }

    func testRemoving_dropsOnlyTheReleasedCohort() {
        let after = ThreadsCardModelBuilder.removing(displayTerm: "the move", from: model(terms: ["the move", "father"]))
        XCTAssertEqual(after?.themes.map(\.displayTerm), ["father"])
    }

    func testRemoving_lastThemeCollapsesTheCard() {
        XCTAssertNil(ThreadsCardModelBuilder.removing(displayTerm: "father", from: model(terms: ["father"])),
                     "an emptied card fades out and the summary reflows to its no-card state")
    }
}
