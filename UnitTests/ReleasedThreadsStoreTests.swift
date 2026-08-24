import XCTest
@testable import Pilgrim

final class ReleasedThreadsStoreTests: XCTestCase {

    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: ReleasedThreadsStore!
    private let released = DateFactory.makeDate(2026, 8, 20, 9, 0, 0)

    override func setUpWithError() throws {
        suiteName = "ReleasedThreadsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = ReleasedThreadsStore(defaults: defaults)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testRelease_persistsAcrossInstances() {
        store.release(displayTerm: "the move", lemmas: ["move", "moving"], releasedAt: released)
        let reopened = ReleasedThreadsStore(defaults: defaults)
        XCTAssertEqual(reopened.all, [
            ReleasedThread(displayTerm: "the move", lemmas: ["move", "moving"], releasedAt: released)
        ])
    }

    func testRelease_mergesCohortForSameTermKeepingFirstDate() {
        store.release(displayTerm: "the move", lemmas: ["move"], releasedAt: released)
        store.release(displayTerm: "the move", lemmas: ["moving"],
                      releasedAt: released.addingTimeInterval(86400))
        XCTAssertEqual(store.all, [
            ReleasedThread(displayTerm: "the move", lemmas: ["move", "moving"], releasedAt: released)
        ])
    }

    func testWelcomeBack_removesCohortAtomically() {
        store.release(displayTerm: "the move", lemmas: ["move", "moving"], releasedAt: released)
        store.release(displayTerm: "father", lemmas: ["father"], releasedAt: released)
        store.welcomeBack(displayTerm: "the move")
        XCTAssertEqual(store.all.map(\.displayTerm), ["father"])
        XCTAssertEqual(store.releasedLemmas, ["father"])
    }

    func testReleasedLemmas_unionAcrossEntries() {
        store.release(displayTerm: "the move", lemmas: ["move", "moving"], releasedAt: released)
        store.release(displayTerm: "father", lemmas: ["father"], releasedAt: released)
        XCTAssertEqual(store.releasedLemmas, ["move", "moving", "father"])
    }

    func testChangeCount_bumpsOnEveryMutation() {
        let before = store.changeCount
        store.release(displayTerm: "a", lemmas: ["a"], releasedAt: released)
        store.welcomeBack(displayTerm: "a")
        store.clear()
        XCTAssertEqual(store.changeCount, before + 3)
    }

    func testAll_sortedNewestFirstThenTerm() {
        store.release(displayTerm: "b", lemmas: ["b"], releasedAt: released)
        store.release(displayTerm: "a", lemmas: ["a"], releasedAt: released)
        store.release(displayTerm: "c", lemmas: ["c"], releasedAt: released.addingTimeInterval(86400))
        XCTAssertEqual(store.all.map(\.displayTerm), ["c", "a", "b"])
    }

    func testMerge_unionsByTermKeepingEarliestDate() {
        store.release(displayTerm: "the move", lemmas: ["move"], releasedAt: released)
        store.merge(released: [
            ReleasedThread(displayTerm: "the move", lemmas: ["moving"],
                           releasedAt: released.addingTimeInterval(-86400)),
            ReleasedThread(displayTerm: "father", lemmas: ["father"], releasedAt: released)
        ], welcomedBack: [])
        XCTAssertEqual(Set(store.all.map(\.displayTerm)), ["the move", "father"])
        let move = store.all.first { $0.displayTerm == "the move" }
        XCTAssertEqual(move?.lemmas, ["move", "moving"])
        XCTAssertEqual(move?.releasedAt, released.addingTimeInterval(-86400))
    }

    func testMerge_staleImportedRelease_doesNotUndoWelcomeBack() {
        store.release(displayTerm: "father", lemmas: ["father"], releasedAt: released)
        store.welcomeBack(displayTerm: "father", at: released.addingTimeInterval(7 * 86400))
        store.merge(released: [
            ReleasedThread(displayTerm: "father", lemmas: ["father"], releasedAt: released)
        ], welcomedBack: [])
        XCTAssertTrue(store.all.isEmpty,
                      "the walker's welcome-back is the later decision — importing an old backup never silently re-releases")
        XCTAssertEqual(store.welcomedBack.map(\.displayTerm), ["father"])
    }

    func testMerge_staleImportedWelcomeBack_doesNotUndoRelease() {
        store.release(displayTerm: "father", lemmas: ["father"], releasedAt: released)
        store.merge(released: [], welcomedBack: [
            WelcomedBackThread(displayTerm: "father",
                               welcomedBackAt: released.addingTimeInterval(-86400))
        ])
        XCTAssertEqual(store.all.map(\.displayTerm), ["father"],
                       "released again after that welcome-back — the newer local release stands")
    }

    func testClear_emptiesEverything() {
        store.release(displayTerm: "a", lemmas: ["a"], releasedAt: released)
        store.welcomeBack(displayTerm: "a")
        store.release(displayTerm: "b", lemmas: ["b"], releasedAt: released)
        store.clear()
        XCTAssertTrue(store.isEmpty)
        XCTAssertTrue(store.welcomedBack.isEmpty)
        XCTAssertTrue(ReleasedThreadsStore(defaults: defaults).isEmpty)
    }
}
