import XCTest
@testable import Pilgrim

final class CustomPromptStyleStoreTests: XCTestCase {

    private var store: CustomPromptStyleStore!
    private let testKey = "TestCustomPromptStyles"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: testKey)
        store = CustomPromptStyleStore(userDefaultsKey: testKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: testKey)
        super.tearDown()
    }

    func testInitialState_empty() {
        XCTAssertTrue(store.styles.isEmpty)
        XCTAssertTrue(store.canAddMore)
    }

    func testSave_addsStyle() {
        let style = CustomPromptStyle(id: UUID(), title: "Test", icon: "star", instruction: "Do a thing")
        store.save(style)
        XCTAssertEqual(store.styles.count, 1)
        XCTAssertEqual(store.styles.first?.title, "Test")
    }

    func testSave_persistsToUserDefaults() {
        let style = CustomPromptStyle(id: UUID(), title: "Persisted", icon: "star", instruction: "Persist")
        store.save(style)
        let reloaded = CustomPromptStyleStore(userDefaultsKey: testKey)
        XCTAssertEqual(reloaded.styles.count, 1)
        XCTAssertEqual(reloaded.styles.first?.title, "Persisted")
    }

    func testCanAddMore_falseAtMax() {
        for i in 0..<CustomPromptStyleStore.maxStyles {
            store.save(CustomPromptStyle(id: UUID(), title: "Style \(i)", icon: "star", instruction: "Inst"))
        }
        XCTAssertFalse(store.canAddMore)
    }

    func testDelete_removesStyle() {
        let style = CustomPromptStyle(id: UUID(), title: "Delete Me", icon: "star", instruction: "Inst")
        store.save(style)
        store.delete(style)
        XCTAssertTrue(store.styles.isEmpty)
    }

    func testSave_existingId_updatesInPlace() {
        let id = UUID()
        store.save(CustomPromptStyle(id: id, title: "Original", icon: "star", instruction: "V1"))
        store.save(CustomPromptStyle(id: id, title: "Updated", icon: "star", instruction: "V2"))
        XCTAssertEqual(store.styles.count, 1)
        XCTAssertEqual(store.styles.first?.title, "Updated")
    }
}
