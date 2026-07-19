// UnitTests/CollectiveCounterServiceTests.swift
import XCTest
@testable import Pilgrim

/// `recordWalk` is where the walk-summary line stops being a reading of a
/// toggle and becomes a record of what a walk did.
///
/// The line asks `CollectiveContributionLog` whether *this* walk moved the
/// counter, and this method is the only thing that ever answers yes. A pilgrim
/// who contributes a walk and later turns the toggle off must keep the line on
/// that walk; one who turns it on afterwards must not gain a line on walks that
/// were never sent. Both depend entirely on the writes below.
///
/// The POST is stubbed in every test here. It increments a live shared counter,
/// so a test that reached it would publish phantom walks into every pilgrim's
/// total.
@MainActor
final class CollectiveCounterServiceRecordWalkTests: XCTestCase {

    private let suiteName = "CollectiveCounterServiceRecordWalkTests"
    /// Spelled out rather than read off the types, matching
    /// `CollectiveContributionLogTests`: a renamed key is a silent data loss on
    /// every installed device, so these should fail rather than follow it.
    private let pendingKey = "collectivePendingDelta"
    private let contributionKey = "collectiveContributedWalkUUIDs"
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        // The preference gate is the one input that is not injectable: it reads
        // the standard suite through `UserPreference`, so it has to be put back.
        UserPreferences.contributeToCollective.delete()
    }

    /// Stubbed to fail, which is also the quieter half of the branch: a failed
    /// POST leaves the pending delta on disk to ride along with the next one,
    /// and never reaches the refetch.
    private func makeService() -> CollectiveCounterService {
        CollectiveCounterService(defaults: defaults, postDelta: { _ in false })
    }

    private func log() -> CollectiveContributionLog {
        CollectiveContributionLog(defaults: defaults)
    }

    private func pending() -> CollectiveCounterService.PendingDelta? {
        defaults.data(forKey: pendingKey).flatMap {
            try? JSONDecoder().decode(CollectiveCounterService.PendingDelta.self, from: $0)
        }
    }

    private var recordedUUIDs: [String] {
        defaults.array(forKey: contributionKey) as? [String] ?? []
    }

    /// The delta is written inside a `DispatchQueue.main.async`, so it has not
    /// landed when `recordWalk` returns. Main-queue FIFO is what makes this a
    /// drain rather than a sleep: the service's block was enqueued first.
    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    // MARK: - The preference gate

    func testRecordWalk_whileContributing_recordsTheWalkAgainstTheLog() async {
        UserPreferences.contributeToCollective.value = true
        let walkUUID = UUID()

        makeService().recordWalk(walkUUID: walkUUID, distanceKm: 4.2, meditationMin: 10, talkMin: 3)
        await drainMainQueue()

        XCTAssertTrue(log().wasContributed(walkUUID: walkUUID.uuidString))
    }

    // AE1. Nothing is recorded and nothing is queued: a pilgrim who keeps their
    // walks to themselves leaves no trace to be sent later if they change their
    // mind, which is the privacy claim the toggle makes.
    func testRecordWalk_whileNotContributing_recordsNothingAndQueuesNothing() async {
        UserPreferences.contributeToCollective.value = false
        let walkUUID = UUID()

        makeService().recordWalk(walkUUID: walkUUID, distanceKm: 4.2, meditationMin: 10, talkMin: 3)
        await drainMainQueue()

        XCTAssertFalse(log().wasContributed(walkUUID: walkUUID.uuidString))
        XCTAssertNil(pending(), "A walk the pilgrim kept private must not sit in the outbound queue")
    }

    // The toggle is read once, when the walk ends. Turning it off afterwards
    // must not retract a walk that already counted, or the summary would lose a
    // line it truthfully earned.
    func testRecordWalk_contributionSurvivesTheToggleBeingTurnedOffLater() async {
        UserPreferences.contributeToCollective.value = true
        let walkUUID = UUID()

        makeService().recordWalk(walkUUID: walkUUID, distanceKm: 4.2, meditationMin: 0, talkMin: 0)
        await drainMainQueue()
        UserPreferences.contributeToCollective.value = false

        XCTAssertTrue(log().wasContributed(walkUUID: walkUUID.uuidString))
    }

    // MARK: - Ordering

    /// What `MainCoordinatorView` depends on without saying so: it calls
    /// `recordWalk` and then walks the pilgrim toward a summary that reads this
    /// log. Nothing awaits anything in between. If the write moved into the
    /// `DispatchQueue.main.async` below it — where the pending delta already
    /// lives — the summary could open first and read a walk that just
    /// contributed as one that did not.
    func testRecordWalk_writesTheLogBeforeReturningToItsCaller() async {
        UserPreferences.contributeToCollective.value = true
        let walkUUID = UUID()

        makeService().recordWalk(walkUUID: walkUUID, distanceKm: 4.2, meditationMin: 0, talkMin: 0)

        // Asserted before the first suspension point in this method, so no
        // other main-queue work can have run between the call and the read.
        XCTAssertTrue(log().wasContributed(walkUUID: walkUUID.uuidString),
                      "The log must be readable on the same main-queue turn that recorded it")

        await drainMainQueue()
    }

    // MARK: - The pending delta

    func testRecordWalk_whileContributing_queuesTheWalksNumbersForTheNextPost() async {
        UserPreferences.contributeToCollective.value = true

        makeService().recordWalk(walkUUID: UUID(), distanceKm: 4.2, meditationMin: 10, talkMin: 3)
        await drainMainQueue()

        let queued = pending()
        XCTAssertEqual(queued?.walks, 1)
        XCTAssertEqual(queued?.distanceKm ?? 0, 4.2, accuracy: 0.0001)
        XCTAssertEqual(queued?.meditationMin, 10)
        XCTAssertEqual(queued?.talkMin, 3)
    }

    // A failed POST must leave both walks queued rather than either overwriting
    // the first or dropping the second.
    func testRecordWalk_twoWalksWithNoNetwork_accumulateInOneDelta() async {
        UserPreferences.contributeToCollective.value = true
        let service = makeService()

        service.recordWalk(walkUUID: UUID(), distanceKm: 4.2, meditationMin: 10, talkMin: 3)
        await drainMainQueue()
        service.recordWalk(walkUUID: UUID(), distanceKm: 1.8, meditationMin: 5, talkMin: 0)
        await drainMainQueue()

        let queued = pending()
        XCTAssertEqual(queued?.walks, 2)
        XCTAssertEqual(queued?.distanceKm ?? 0, 6.0, accuracy: 0.0001)
        XCTAssertEqual(queued?.meditationMin, 15)
        XCTAssertEqual(queued?.talkMin, 3)
    }

    /// The nil case is reachable: `MainCoordinatorView` passes `snapshot.uuid`,
    /// which is whatever `DataManager.saveWalk` handed back, so a save that
    /// reported success without a usable object arrives here as nil.
    ///
    /// The split is deliberate in the safe direction rather than accidental. The
    /// distance is real and belongs to the collective's ledger, so it is queued;
    /// but with no identifier there is nothing a summary could match against, so
    /// no claim is recorded. The walk counts and stays silent — the app
    /// under-claims rather than showing a line it cannot substantiate.
    func testRecordWalk_withoutAWalkIdentifier_queuesTheDistanceButClaimsNothing() async {
        UserPreferences.contributeToCollective.value = true
        let before = recordedUUIDs

        makeService().recordWalk(walkUUID: nil, distanceKm: 4.2, meditationMin: 10, talkMin: 3)
        await drainMainQueue()

        XCTAssertEqual(pending()?.walks, 1, "The walk happened, so the collective's ledger still gets it")
        XCTAssertEqual(pending()?.distanceKm ?? 0, 4.2, accuracy: 0.0001)
        XCTAssertEqual(recordedUUIDs, before,
                       "With no identifier there is nothing a summary could match, so nothing is claimed")
    }
}
