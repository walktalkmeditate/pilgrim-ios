import Foundation
import CoreStore

#if DEBUG
/// Ship-gate harness (spec Ship gate item 1): iterates every walk with
/// transcribed recordings, evaluates every sense uncapped, and prints
/// per-sense firing rates plus each emitted line, so a human can judge
/// degeneration (fires on nearly every walk) and dead senses (nearly never)
/// against a REAL device history. Launch the dev build on the team device
/// with `--senses-field-report` and read the console. The report only
/// EVALUATES senses (moon state passed as nil, no defaults write anywhere
/// on this path) — it never consumes the real once-per-lunation budget.
///
/// Split from `ThreadsDossierBuilder.swift` to keep that file under the
/// file_length lint gate — this harness is a standalone DEBUG-only consumer
/// of the builder's internal-but-non-private senses-assembly seams
/// (`gatherSensesBundle`, `makeSensesInput`, `SensesAssemblyState`), not
/// part of the builder itself.
enum DossierSensesFieldReport {

    @MainActor
    static func runIfRequested() {
        guard CommandLine.arguments.contains("--senses-field-report"),
              NSClassFromString("XCTestCase") == nil else { return }
        print(generate())
    }

    @MainActor
    static func generate(now: Date = Date()) -> String {
        guard let walks = try? DataManager.dataStack.fetchAll(
            From<Walk>().orderBy(.ascending(\._startDate))
        ) else { return "senses field report: walk fetch failed" }
        let walkIndex = DataManager.voiceRecordingWalkIndex()
        let all = TranscriptContextStore.shared.loadAll()
        let context = FieldReportContext(
            contextsByUUID: Dictionary(uniqueKeysWithValues: all.map { ($0.recordingUUID, $0) }),
            threadsAll: ThreadStore.build(contexts: all, walks: walkIndex),
            walkIndex: walkIndex
        )
        var firing: [DossierSenses.Sense: Int] = [:]
        var eligible = 0
        var buildDurations: [TimeInterval] = []
        var report = "\n===== DOSSIER SENSES FIELD REPORT =====\n"
        if walks.isEmpty {
            report += "\n(no walk history on this device — nothing to report)\n"
            report += "=======================================\n"
            return report
        }
        for walk in walks {
            guard let walkUUID = walk._uuid.value else { continue }
            let recordings = transcribedRecordings(for: walk)
            guard !recordings.isEmpty else { continue }
            eligible += 1
            let result = evaluateWalk(walk, walkUUID: walkUUID, recordings: recordings, now: now, context: context)
            report += result.text
            for sense in result.firingSenses { firing[sense, default: 0] += 1 }
            buildDurations.append(result.buildSeconds)
        }
        if eligible == 0 {
            report += "\n(no walk carries a transcribed recording — nothing to report)\n"
            report += "=======================================\n"
            return report
        }
        report += "\nFiring rates over \(eligible) walks with words:\n"
        for sense in DossierSenses.Sense.allCases {
            report += "  \(sense): \(firing[sense] ?? 0)/\(eligible)\n"
        }
        let sortedDurations = buildDurations.sorted()
        let midpoint = sortedDurations.count / 2
        let medianSeconds = sortedDurations.count.isMultiple(of: 2)
            ? (sortedDurations[midpoint - 1] + sortedDurations[midpoint]) / 2
            : sortedDurations[midpoint]
        let maxSeconds = sortedDurations.last ?? 0
        report += String(format: "\nBuild time — median: %.3fs, max: %.3fs\n", medianSeconds, maxSeconds)
        report += "=======================================\n"
        return report
    }

    /// Bundled so `evaluateWalk` stays under the function-parameter-count
    /// lint gate — same rationale as `ThreadsDossierBuilder.SensesAssemblyState`.
    private struct FieldReportContext {
        let contextsByUUID: [UUID: TranscriptContext]
        let threadsAll: [WalkThread]
        let walkIndex: [UUID: (walkUUID: UUID, date: Date)]
    }

    private struct WalkSensesReport {
        let text: String
        let firingSenses: [DossierSenses.Sense]
        let buildSeconds: TimeInterval
    }

    private static func transcribedRecordings(for walk: Walk) -> [RecordingContext] {
        walk._voiceRecordings.value.compactMap { recording in
            guard let uuid = recording._uuid.value,
                  let text = recording._transcription.value, !text.isEmpty else { return nil }
            return RecordingContext(
                text: text, timestamp: recording._startDate.value,
                startCoordinate: nil, endCoordinate: nil,
                wordsPerMinute: recording._wordsPerMinute.value,
                recordingUUID: uuid, endTimestamp: recording._endDate.value
            )
        }
    }

    /// Evaluates every sense for one walk and prints its per-walk build
    /// wall-clock (ship-gate item: judge per-walk cost, not just firing
    /// rates). Wall-clock, not ContinuousClock — this DEBUG harness prints a
    /// human-facing diagnostic, not a pure-module measurement; the pure
    /// senses functions themselves stay Date()-free.
    @MainActor
    private static func evaluateWalk(
        _ walk: Walk, walkUUID: UUID, recordings: [RecordingContext], now: Date, context: FieldReportContext
    ) -> WalkSensesReport {
        let buildStart = Date()
        let bundle = ThreadsDossierBuilder.gatherSensesBundle(walk: walk, now: now)
        let input = ThreadsDossierBuilder.makeSensesInput(
            senses: bundle,
            state: ThreadsDossierBuilder.SensesAssemblyState(
                walkUUID: walkUUID, recordings: recordings, contextsByUUID: context.contextsByUUID,
                threads: context.threadsAll, walkIndex: context.walkIndex,
                backfillComplete: ThreadsBackfill.isComplete, moonState: nil
            ),
            resolveRouteFix: DataManager.routeFixNear
        )
        var text = "\nWalk \(walk._startDate.value):\n"
        var firingSenses: [DossierSenses.Sense] = []
        for sense in DossierSenses.Sense.allCases {
            guard let line = DossierSenses.evaluate(sense, input: input, suppressed: []) else { continue }
            firingSenses.append(sense)
            text += "  [\(sense)] \(line.text)\n"
        }
        let buildSeconds = Date().timeIntervalSince(buildStart)
        text += String(format: "  build: %.3fs\n", buildSeconds)
        return WalkSensesReport(text: text, firingSenses: firingSenses, buildSeconds: buildSeconds)
    }
}
#endif
