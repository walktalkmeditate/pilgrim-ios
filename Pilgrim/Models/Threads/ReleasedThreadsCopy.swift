import Foundation

/// Every release/welcome-back string in one place: the card and the thread
/// view can never drift apart, and the pre-release gentleness pass (Task 9)
/// edits one file. The confirm leads with reversibility by design.
enum ReleasedThreadsCopy {

    static func releaseTitle(_ term: String) -> String { "Let '\(term)' go?" }
    static let releaseMessage = "You can welcome it back anytime."
    static let releaseConfirm = "Let it go"
    static let releaseCancel = "Not now"

    static func welcomeBackTitle(_ term: String) -> String { "Welcome '\(term)' back?" }
    static let welcomeBackMessage = "Threads will notice it again."
    static let welcomeBackConfirm = "Welcome it back"
    static let welcomeBackCancel = "Not now"

    static let caption = "long-press a theme to let it go"
    static let voiceOverActionName = "Let this go"
}
