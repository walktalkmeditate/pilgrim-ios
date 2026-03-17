import XCTest
@testable import Pilgrim

final class VoiceGuideHistoryTests: XCTestCase {

    private var historyURL: URL!

    override func setUp() {
        super.setUp()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("voiceguide_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        historyURL = tmp.appendingPathComponent("history.json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: historyURL.deletingLastPathComponent())
        super.tearDown()
    }

    func testWriteAndReadHistory() throws {
        let history: [String: [String]] = ["breeze": ["breeze_01", "breeze_02"]]
        let data = try JSONEncoder().encode(history)
        try data.write(to: historyURL)

        let readData = try Data(contentsOf: historyURL)
        let decoded = try JSONDecoder().decode([String: [String]].self, from: readData)
        XCTAssertEqual(Set(decoded["breeze"]!), Set(["breeze_01", "breeze_02"]))
    }

    func testMultiplePacksCoexist() throws {
        var history: [String: [String]] = [:]
        history["breeze"] = ["breeze_01"]
        history["sage"] = ["sage_01", "sage_02"]

        let data = try JSONEncoder().encode(history)
        try data.write(to: historyURL)

        let readData = try Data(contentsOf: historyURL)
        let decoded = try JSONDecoder().decode([String: [String]].self, from: readData)
        XCTAssertEqual(decoded["breeze"]?.count, 1)
        XCTAssertEqual(decoded["sage"]?.count, 2)
    }

    func testMissingFileReturnsEmpty() {
        let data = try? Data(contentsOf: historyURL)
        XCTAssertNil(data)
    }

    func testCorruptedFileHandledGracefully() throws {
        try "not json".data(using: .utf8)!.write(to: historyURL)

        let data = try Data(contentsOf: historyURL)
        let decoded = try? JSONDecoder().decode([String: [String]].self, from: data)
        XCTAssertNil(decoded)
    }

    func testHistoryMaxSize() throws {
        var history: [String: [String]] = [:]
        let ids = (1...100).map { "prompt_\($0)" }
        history["large_pack"] = ids

        let data = try JSONEncoder().encode(history)
        try data.write(to: historyURL)

        let readData = try Data(contentsOf: historyURL)
        let decoded = try JSONDecoder().decode([String: [String]].self, from: readData)
        XCTAssertEqual(decoded["large_pack"]?.count, 100)
    }
}
