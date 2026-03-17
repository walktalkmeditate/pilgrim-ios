import XCTest
@testable import Pilgrim

final class IntentionHistoryStoreTests: XCTestCase {

    private var store: IntentionHistoryStore!
    private let testKey = "TestIntentionHistory"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: testKey)
        store = IntentionHistoryStore(userDefaultsKey: testKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    func testInitialState_empty() {
        XCTAssertTrue(store.intentions.isEmpty)
    }

    func testAdd_insertsAtFront() {
        store.add("Walk with gratitude")
        XCTAssertEqual(store.intentions, ["Walk with gratitude"])
    }

    func testAdd_deduplicates() {
        store.add("Be present")
        store.add("Find peace")
        store.add("Be present")
        XCTAssertEqual(store.intentions, ["Be present", "Find peace"])
    }

    func testAdd_capsAtMax() {
        for i in 0..<7 {
            store.add("Intention \(i)")
        }
        XCTAssertEqual(store.intentions.count, IntentionHistoryStore.maxIntentions)
        XCTAssertEqual(store.intentions.first, "Intention 6")
    }

    func testAdd_ignoresBlankStrings() {
        store.add("")
        store.add("   ")
        XCTAssertTrue(store.intentions.isEmpty)
    }

    func testAdd_trimsWhitespace() {
        store.add("  Walk mindfully  ")
        XCTAssertEqual(store.intentions.first, "Walk mindfully")
    }

    func testAdd_persistsToUserDefaults() {
        store.add("Persisted intention")
        let reloaded = IntentionHistoryStore(userDefaultsKey: testKey)
        XCTAssertEqual(reloaded.intentions, ["Persisted intention"])
    }

    func testClear_removesAll() {
        store.add("One")
        store.add("Two")
        store.clear()
        XCTAssertTrue(store.intentions.isEmpty)
    }

    func testClear_persistsEmptyState() {
        store.add("One")
        store.clear()
        let reloaded = IntentionHistoryStore(userDefaultsKey: testKey)
        XCTAssertTrue(reloaded.intentions.isEmpty)
    }
}
