import XCTest
@testable import Pilgrim

final class TranscriptContextAnalyzerTests: XCTestCase {

    private let transcript = """
        Still circling the move today. If the move happens in fall we lose the \
        garden. The move keeps returning whenever the morning is quiet, and I \
        always feel it will never settle until we decide something real.
        """

    func testAnalyze_producesThemesMarkersAndHash() {
        let uuid = UUID()
        let context = TranscriptContextAnalyzer.analyze(
            recordingUUID: uuid, transcript: transcript, flaggedFragments: []
        )
        XCTAssertEqual(context.recordingUUID, uuid)
        XCTAssertEqual(context.transcriptHash, TranscriptContextStore.hash(of: transcript))
        XCTAssertEqual(context.languageCode, "en")
        XCTAssertTrue(context.themes.contains { $0.lemma == "move" })
        XCTAssertNotNil(context.markers)
        XCTAssertGreaterThanOrEqual(context.markers!.absolutistCount, 2)  // always, never
    }

    func testFlaggedFragments_cannotFoundATheme() {
        let hallucination = "thanks for watching thanks for watching thanks for watching"
        let text = "A quiet morning with nothing much to say beyond the weather being kind today, honestly just glad the rain held off and the streets stayed empty enough to hear my own breathing for once. " + hallucination
        let context = TranscriptContextAnalyzer.analyze(
            recordingUUID: UUID(), transcript: text, flaggedFragments: [hallucination]
        )
        XCTAssertFalse(context.themes.contains { ["watch", "thank", "thanks"].contains($0.lemma) })
    }

    func testRepeatedFlaggedFragment_everyOccurrenceExcluded() {
        let fragment = "thanks for watching"
        let base = "A long quiet reflection about the garden and the fall and whether the move makes sense for both of us this year, spoken slowly. "
        let text = base + fragment + ". " + fragment + ". " + fragment + "."
        let context = TranscriptContextAnalyzer.analyze(
            recordingUUID: UUID(), transcript: text, flaggedFragments: [fragment]
        )
        XCTAssertFalse(context.themes.contains { ["watch", "thank", "thanks"].contains($0.lemma) })
    }

    func testPartiallyFlaggedTheme_survives() {
        let flagged = "the move the move the move"
        let text = "Still circling the move today and what the move would cost us, more than twenty-five honest words about the whole question spoken here. " + flagged
        let context = TranscriptContextAnalyzer.analyze(
            recordingUUID: UUID(), transcript: text, flaggedFragments: [flagged]
        )
        XCTAssertTrue(context.themes.contains { $0.lemma == "move" },
                      "a theme with at least one unflagged mention survives")
    }

    func testAnalyzeAndStore_persists() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AnalyzerTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = TranscriptContextStore(directory: directory)
        let uuid = UUID()
        TranscriptContextAnalyzer.analyzeAndStore(
            recordingUUID: uuid, transcript: transcript, flaggedFragments: [], store: store
        )
        XCTAssertNotNil(store.context(for: uuid, matching: TranscriptContextStore.hash(of: transcript)))
    }
}
