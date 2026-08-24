import XCTest
@testable import Pilgrim

final class LunationRecapStateTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var state: LunationRecapState!
    private var savedToggle = true

    /// A fixed lunation grid: `closed` = lunation 300, `now` one day after
    /// it closed, `walkAfter` a walk dated after the boundary.
    private let closed = LunationCalendar.lunation(at: 300)
    private var now: Date { closed.end.addingTimeInterval(86400) }
    private var walkAfter: Date { closed.end.addingTimeInterval(3600) }

    override func setUpWithError() throws {
        suiteName = "LunationRecapStateTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        state = LunationRecapState(defaults: defaults)
        savedToggle = UserPreferences.threadsAfterWalks.value
        UserPreferences.threadsAfterWalks.value = true
    }

    override func tearDownWithError() throws {
        UserPreferences.threadsAfterWalks.value = savedToggle
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func showFirstCard(before boundary: Date) {
        state.markFirstCardShown(now: boundary.addingTimeInterval(-10 * 86400))
    }

    func testInvitation_requiresFirstCardShown() {
        XCTAssertNil(state.invitation(forWalkDated: walkAfter, now: now),
                     "the recap must never be a walker's first contact with the feature")
        showFirstCard(before: closed.end)
        XCTAssertNotNil(state.invitation(forWalkDated: walkAfter, now: now))
    }

    func testInvitation_boundaryInsideBackfilledHistoryNeverInvites() {
        state.markFirstCardShown(now: closed.end.addingTimeInterval(3600))
        XCTAssertNil(state.invitation(forWalkDated: walkAfter, now: now),
                     "a lunation that closed before the first card belongs to backfilled history")
    }

    func testInvitation_walkDatedBeforeBoundary_neverInvites() {
        showFirstCard(before: closed.end)
        XCTAssertNil(state.invitation(
            forWalkDated: closed.end.addingTimeInterval(-3600), now: now
        ), "old summaries read the same whenever opened")
    }

    func testInvitation_reEvaluatesUntilActedOn() {
        showFirstCard(before: closed.end)
        XCTAssertNotNil(state.invitation(forWalkDated: walkAfter, now: now))
        XCTAssertNotNil(state.invitation(forWalkDated: walkAfter, now: now),
                        "the flag records acted-on, not first opportunity — pending transcriptions don't cost the month")
        state.markActedOn(closed)
        XCTAssertNil(state.invitation(forWalkDated: walkAfter, now: now))
    }

    func testInvitation_nextLunationSupersedes() {
        showFirstCard(before: closed.end)
        state.markActedOn(closed)
        let next = LunationCalendar.lunation(at: 301)
        let laterNow = next.end.addingTimeInterval(86400)
        let laterWalk = next.end.addingTimeInterval(3600)
        XCTAssertEqual(state.invitation(forWalkDated: laterWalk, now: laterNow)?.index, 301,
                       "acting on one moon never silences the next")
    }

    func testInvitation_onlyTheMostRecentClosedLunationInvites() {
        showFirstCard(before: closed.end)
        let next = LunationCalendar.lunation(at: 301)
        let laterNow = next.end.addingTimeInterval(86400)
        XCTAssertEqual(state.invitation(forWalkDated: walkAfter, now: laterNow), nil,
                       "once the next lunation closes, a walk dated inside the previous one no longer invites — Past recaps keeps it reachable")
    }

    func testMarkFirstCardShown_setOnce() {
        let first = DateFactory.makeDate(2026, 8, 1, 9, 0, 0)
        state.markFirstCardShown(now: first)
        state.markFirstCardShown(now: first.addingTimeInterval(86400))
        XCTAssertEqual(state.firstCardShownAt, first)
    }

    func testInvitation_toggleOffMeansOff() {
        showFirstCard(before: closed.end)
        UserPreferences.threadsAfterWalks.value = false
        XCTAssertNil(state.invitation(forWalkDated: walkAfter, now: now))
    }

    func testInvitation_futureActedIndexIsIgnored() {
        showFirstCard(before: closed.end)
        state.markActedOn(LunationCalendar.lunation(at: 305))
        XCTAssertEqual(state.invitation(forWalkDated: walkAfter, now: now)?.index, 300,
                       "an acted index from a forward-set clock is ignored — it cannot silence months of real invitations")
    }

    func testMarkActedOn_isMonotonic() {
        state.markActedOn(closed)
        state.markActedOn(LunationCalendar.lunation(at: 298))
        XCTAssertEqual(state.lastActedLunationIndex, 300,
                       "opening an older moon from Past recaps never regresses the acted index")
    }
}
