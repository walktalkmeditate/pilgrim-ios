import XCTest
@testable import Pilgrim

/// Not a correctness test — a harness for the spec's field gate between
/// Stages 2 and 3. Prints the analyzer's real output over representative
/// walk monologues so a human can judge theme quality before any card UI
/// is planned. Extend `fixtures` with real dogfood transcripts (pasted
/// locally, never committed) when running the gate for real.
final class FieldGateReportTests: XCTestCase {

    private let fixtures: [String] = [
        "Still circling the move today. If the move happens in fall we lose the garden, and moving means telling her father before the holidays. I keep rehearsing that conversation on every hill.",
        "Dad called last night. He sounded smaller. I noticed I talk about him in the past tense already and I hate that. The river was loud today and I let it be louder than the thought.",
        "Work again. The deadline moved twice and I said yes twice. I should have said something real. Next walk I want to figure out what saying something real would even sound like.",
        "Nothing much today. Cold hands. A dog followed me half a kilometer. I named him Bruno in my head and felt better than I have all week.",
        "I realized on the bridge that the move and dad are the same worry wearing two coats. If we go, who sits with him on Sundays? That is the whole question under everything."
    ]

    func testPrintFieldGateReport() {
        var report = "\n===== THOUGHT THREADS FIELD GATE REPORT =====\n"
        var contexts: [TranscriptContext] = []
        var walks: [UUID: (walkUUID: UUID, date: Date)] = [:]
        let base = DateFactory.makeDate(2024, 6, 1, 9, 0, 0)

        for (index, transcript) in fixtures.enumerated() {
            let context = TranscriptContextAnalyzer.analyze(
                recordingUUID: UUID(), transcript: transcript, flaggedFragments: []
            )
            contexts.append(context)
            walks[context.recordingUUID] = (UUID(), base.addingTimeInterval(Double(index) * 3 * 86400))
            report += "\nWalk \(index + 1) themes: "
            report += context.themes.map { "\($0.displayTerm) (\($0.mentionCount)×)" }.joined(separator: ", ")
            report += "\n  markers: \(ThreadsDossierFormatter.markerLine(for: context, baseline: nil))\n"
        }

        let threads = ThreadStore.build(contexts: contexts, walks: walks)
        report += "\nThreads across the corpus:\n"
        for thread in threads where thread.appearances.count >= 2 {
            report += "  '\(thread.displayTerm)' — \(thread.appearances.count) appearances\n"
        }
        report += "=============================================\n"
        print(report)
        XCTAssertFalse(contexts.isEmpty)
    }

    /// Senses over the same corpus, uncapped, with synthetic ground: a
    /// printed rehearsal of the on-device report so template phrasing gets
    /// human eyes before the real-history pass.
    func testPrintSensesFieldGateReport() {
        var contexts: [TranscriptContext] = []
        var walks: [UUID: (walkUUID: UUID, date: Date)] = [:]
        let base = DateFactory.makeDate(2024, 6, 1, 9, 0, 0)
        for (index, transcript) in fixtures.enumerated() {
            let context = TranscriptContextAnalyzer.analyze(
                recordingUUID: UUID(), transcript: transcript, flaggedFragments: []
            )
            contexts.append(context)
            walks[context.recordingUUID] = (UUID(), base.addingTimeInterval(Double(index) * 3 * 86400))
        }
        let threads = ThreadStore.build(contexts: contexts, walks: walks)
        let current = contexts.last!
        let currentWalk = walks[current.recordingUUID]!
        let input = DossierSenses.Input(
            currentWalkUUID: currentWalk.walkUUID,
            walkStart: currentWalk.date,
            walkEnd: currentWalk.date.addingTimeInterval(5400),
            totalAscent: 60,
            elevationSeries: [], photos: [],
            currentRecordings: [DossierSenses.CurrentRecording(
                uuid: current.recordingUUID, start: currentWalk.date.addingTimeInterval(300),
                end: currentWalk.date.addingTimeInterval(600),
                text: fixtures.last!, wordCount: current.wordCount, themes: current.themes
            )],
            threads: threads, backfillComplete: true,
            walkSnapshots: walks.values.map {
                DossierSenses.WalkSnapshotRow(walkUUID: $0.walkUUID, startDate: $0.date,
                                              intention: nil, weatherCondition: nil)
            },
            historyTranscripts: [], recordingTimestamps: [:], walkIndex: walks,
            fixes: [:], moon: nil
        )
        var report = "\n===== SENSES FIELD GATE REPORT (fixtures) =====\n"
        for sense in DossierSenses.Sense.allCases {
            let line = DossierSenses.evaluate(sense, input: input, suppressed: [])
            report += "  \(sense): \(line?.text ?? "—")\n"
        }
        report += "===============================================\n"
        print(report)
        XCTAssertFalse(threads.isEmpty)
    }
}
