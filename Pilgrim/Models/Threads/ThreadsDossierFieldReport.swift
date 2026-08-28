import Foundation
import CoreStore

#if DEBUG
/// Ship-gate harnesses: iterate every walk with transcribed recordings,
/// evaluate uncapped, and print per-signal firing rates plus every emitted
/// line, so a human can judge degeneration (fires on nearly every walk) and
/// dead signals (nearly never) against a REAL device history. Launch the
/// dev build on the team device with `--senses-field-report` (senses,
/// `Noticed:`) or `--invariance-field-report` (invariants, `Unchanged:` —
/// Task 12 field gate item 1) and read the console. Both EVALUATE ONLY —
/// moon state passed as nil, no defaults write anywhere on either path — so
/// neither consumes the real once-per-lunation budget or any other stored
/// state.
///
/// Split from `ThreadsDossierBuilder.swift` to keep that file under the
/// file_length lint gate — this harness is a standalone DEBUG-only consumer
/// of the builder's internal-but-non-private senses-assembly seams
/// (`gatherSensesBundle`, `makeSensesInput`, `SensesAssemblyState`), not
/// part of the builder itself.
enum DossierSensesFieldReport {

    @MainActor
    static func runIfRequested() {
        guard NSClassFromString("XCTestCase") == nil else { return }
        if CommandLine.arguments.contains("--senses-field-report") {
            print(generate())
        }
        if CommandLine.arguments.contains("--invariance-field-report") {
            print(generateInvarianceReport())
        }
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

    // MARK: - Invariance field report (Task 12)

    /// Ship-gate harness (spec "Field gate" item 1): iterates every walk
    /// with transcribed recordings, evaluates every `DossierSenses.Invariant`
    /// UNCAPPED — no 3-line cap, no cross-signal lemma dedup — and prints
    /// per-signal firing rates plus each emitted line, so a human can judge
    /// degeneration and dead signals against a REAL device history, the
    /// same discipline `generate()` above applies to senses. EVALUATES
    /// ONLY: moon state passed as nil, no defaults write, no real state
    /// consumed.
    ///
    /// Reuses `ThreadsDossierBuilder.gatherSensesBundle`/`makeSensesInput` —
    /// the exact seams `evaluateWalk` already calls — rather than
    /// assembling a second `Input` per walk.
    @MainActor
    static func generateInvarianceReport(now: Date = Date()) -> String {
        guard let walks = try? DataManager.dataStack.fetchAll(
            From<Walk>().orderBy(.ascending(\._startDate))
        ) else { return "invariance field report: walk fetch failed" }
        let walkIndex = DataManager.voiceRecordingWalkIndex()
        let all = TranscriptContextStore.shared.loadAll()
        let context = FieldReportContext(
            contextsByUUID: Dictionary(uniqueKeysWithValues: all.map { ($0.recordingUUID, $0) }),
            threadsAll: ThreadStore.build(contexts: all, walks: walkIndex),
            walkIndex: walkIndex
        )
        var fired: [DossierSenses.Invariant: Int] = [:]
        var considered = 0
        var report = "\n===== DOSSIER INVARIANCE FIELD REPORT =====\n"
        if walks.isEmpty {
            report += "\n(no walk history on this device — nothing to report)\n"
            report += "============================================\n"
            return report
        }
        for walk in walks {
            guard let walkUUID = walk._uuid.value else { continue }
            let recordings = transcribedRecordings(for: walk)
            guard !recordings.isEmpty else { continue }
            considered += 1
            let result = evaluateWalkInvariance(
                walk, walkUUID: walkUUID, recordings: recordings, now: now, context: context
            )
            report += result.text
            for invariant in result.firingInvariants { fired[invariant, default: 0] += 1 }
        }
        if considered == 0 {
            report += "\n(no walk carries a transcribed recording — nothing to report)\n"
            report += "============================================\n"
            return report
        }
        report += "\nFiring rates over \(considered) walks with words:\n"
        for invariant in DossierSenses.Invariant.allCases {
            let count = fired[invariant] ?? 0
            let rate = Double(count) / Double(considered) * 100
            report += String(format: "  %@: %d/%d (%.1f%%)\n", String(describing: invariant), count, considered, rate)
        }
        report += "\nNote: [\(DossierSenses.Invariant.unarrivedIntention)] above BYPASSES "
        report += "pendingFieldGate — called directly so this report can judge the one signal "
        report += "production dispatch keeps dark. pendingFieldGate itself is untouched by this "
        report += "harness and stays true in production.\n"
        report += "============================================\n"
        return report
    }

    private struct WalkInvarianceReport {
        let text: String
        let firingInvariants: [DossierSenses.Invariant]
    }

    /// Evaluates every invariant for one walk, uncapped: each call passes an
    /// EMPTY `suppressed` set rather than accumulating one across signals
    /// the way `DossierSenses.invarianceLines` does for the real
    /// `Unchanged:` block — this report's job is to see what every signal
    /// would say on its own, not what survives the cap and cross-signal
    /// dedup a walker actually reads.
    ///
    /// Going through `evaluateInvariant` rather than `invarianceLines` also
    /// means this report is NOT held silent by the incomplete-backfill gate
    /// that guards the production block. That is deliberate and equally
    /// local: the gate exists so a walker is never told a coverage claim
    /// over a partly-analyzed record, while the field gate's whole job is to
    /// judge firing rates, and a report that returns nothing because a sweep
    /// was mid-flight would look like a dead signal. `backfillComplete` is
    /// still passed through on the `Input` above, so any signal that reads
    /// it directly still behaves exactly as it does in production.
    ///
    /// `.unarrivedIntention` calls `DossierSensesInvariance.unarrivedIntention`
    /// DIRECTLY, BYPASSING `pendingFieldGate`, instead of going through
    /// `DossierSenses.evaluateInvariant` — which returns nil for that case
    /// while the flag is true (see `DossierSensesInvariance.swift`). This is
    /// the one deliberate, local bypass in the codebase, made obvious here
    /// so nobody mistakes it for a leak: `pendingFieldGate` stays `true` in
    /// production: only this DEBUG report ever sees signal 5 fire.
    @MainActor
    private static func evaluateWalkInvariance(
        _ walk: Walk, walkUUID: UUID, recordings: [RecordingContext], now: Date, context: FieldReportContext
    ) -> WalkInvarianceReport {
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
        var text = "\nWalk \(walkUUID) (\(walk._startDate.value)):\n"
        var firingInvariants: [DossierSenses.Invariant] = []
        for invariant in DossierSenses.Invariant.allCases {
            let line: DossierSenses.SenseLine? = invariant == .unarrivedIntention
                ? DossierSensesInvariance.unarrivedIntention(input: input, suppressed: []) // BYPASS — see doc above
                : DossierSenses.evaluateInvariant(invariant, input: input, suppressed: [])
            guard let line else { continue }
            firingInvariants.append(invariant)
            text += "  [\(invariant)] \(line.text)\n"
        }
        return WalkInvarianceReport(text: text, firingInvariants: firingInvariants)
    }
}
#endif
