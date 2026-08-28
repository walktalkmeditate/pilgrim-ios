import Foundation

enum ThreadsDossierFormatter {

    static let densityFloorWords = 100
    static let baselineFloorRecordings = 5
    static let absenceWindow: TimeInterval = 30 * 86400
    static let minimumAbsenceWalks = 2
    static let maxAbsenceLines = 2
    static let paceDifferenceThreshold = 0.15
    /// Modal-lean baseline groups by WALK, not recording — a walker who
    /// talks in three short bursts on one walk isn't three "prior" data
    /// points for a per-walk state signal, unlike `baselineFloorRecordings`.
    static let modalBaselineFloorWalks = 3
    static let modalRemarkableMinCount = 10
    static let modalRemarkableRateMultiple = 2.0

    static func markerLine(for context: TranscriptContext, baseline: (absolutist: Double, firstPerson: Double)?) -> String {
        guard let markers = context.markers else {
            return "Markers unavailable (non-English recording)."
        }
        var parts: [String] = []
        if markers.wordCount >= densityFloorWords {
            let absolutist = Double(markers.absolutistCount) / Double(markers.wordCount) * 100
            var absolutistPart = String(format: "absolutist words %.1f%% over %d words", absolutist, markers.wordCount)
            if let baseline {
                absolutistPart += String(format: " (your usual walking baseline ~%.1f%%)", baseline.absolutist * 100)
            }
            parts.append(absolutistPart)
            let firstPerson = Double(markers.firstPersonCount) / Double(markers.wordCount) * 100
            parts.append(String(format: "self-focus %.1f%%", firstPerson))
        } else {
            parts.append("\(markers.wordCount) words — small sample, raw counts only: \(markers.absolutistCount) absolutist, \(markers.firstPersonCount) self-focus")
        }
        parts.append("insight \(markers.insightCount), causation \(markers.causationCount), discrepancy \(markers.discrepancyCount)")
        parts.append("temporal lean: \(markers.temporalLean) (coarse heuristic)")
        if let sentiment = markers.sentiment {
            parts.append(String(format: "sentiment %.2f", sentiment))
        }
        return parts.joined(separator: "; ")
    }

    static func personalBaseline(from contexts: [TranscriptContext]) -> (absolutist: Double, firstPerson: Double)? {
        let qualifying = contexts.compactMap { context -> MarkerPack? in
            guard let markers = context.markers, markers.wordCount >= densityFloorWords else { return nil }
            return markers
        }
        guard qualifying.count >= baselineFloorRecordings else { return nil }
        let totalWords = qualifying.reduce(0) { $0 + $1.wordCount }
        guard totalWords > 0 else { return nil }
        return (
            absolutist: Double(qualifying.reduce(0) { $0 + $1.absolutistCount }) / Double(totalWords),
            firstPerson: Double(qualifying.reduce(0) { $0 + $1.firstPersonCount }) / Double(totalWords)
        )
    }

    private struct ModalLeanSummary {
        let family: MarkerLexicons.ModalFamily
        let word: String
        let count: Int
        let familyCount: Int
        let familyRate: Double
    }

    struct ModalBaselineEntry {
        let rate: Double
        let averagePerWalk: Double
    }

    /// Today's dominant modal family and its dominant surface word, summed
    /// across the WALK's recordings (not one recording at a time — the
    /// clause speaks once per walk). Deterministic ties: `ModalFamily
    /// .allCases`/each family's word array are declaration-ordered, and only
    /// a STRICTLY greater count replaces the running best.
    private static func modalLeanSummary(for contexts: [TranscriptContext]) -> ModalLeanSummary? {
        let totalWords = contexts.reduce(0) { $0 + $1.wordCount }
        guard totalWords > 0 else { return nil }

        var familyTotals: [MarkerLexicons.ModalFamily: Int] = [:]
        var wordTotals: [String: Int] = [:]
        for context in contexts {
            guard let modalCounts = context.markers?.modalCounts else { continue }
            for (word, count) in modalCounts {
                wordTotals[word, default: 0] += count
                if let family = MarkerLexicons.modalFamily(of: word) {
                    familyTotals[family, default: 0] += count
                }
            }
        }

        var dominantFamily: (family: MarkerLexicons.ModalFamily, count: Int)?
        for family in MarkerLexicons.ModalFamily.allCases {
            let count = familyTotals[family] ?? 0
            guard count > 0, dominantFamily == nil || count > dominantFamily!.count else { continue }
            dominantFamily = (family, count)
        }
        guard let dominantFamily else { return nil }

        var dominantWord: (word: String, count: Int)?
        for word in MarkerLexicons.modalFamilies[dominantFamily.family] ?? [] {
            let count = wordTotals[word] ?? 0
            guard count > 0, dominantWord == nil || count > dominantWord!.count else { continue }
            dominantWord = (word, count)
        }
        guard let dominantWord else { return nil }

        return ModalLeanSummary(
            family: dominantFamily.family, word: dominantWord.word, count: dominantWord.count,
            familyCount: dominantFamily.count, familyRate: Double(dominantFamily.count) / Double(totalWords)
        )
    }

    /// Per-family baseline, grouped by WALK (`modalBaselineFloorWalks`
    /// prior, contexted walks required) rather than by recording — mirrors
    /// `personalBaseline`'s density-floor qualification and its reuse of
    /// already-persisted `MarkerPack` counts (never a fresh transcript
    /// re-read), but the walk-grouping is this signal's own: a state lean is
    /// a per-walk fact, not a per-recording one.
    static func modalBaseline(
        from contexts: [TranscriptContext],
        walkIndex: [UUID: UUID],
        excluding currentWalkUUID: UUID
    ) -> [MarkerLexicons.ModalFamily: ModalBaselineEntry]? {
        let qualifying = contexts.filter { context in
            guard let markers = context.markers, markers.wordCount >= densityFloorWords,
                  let walkUUID = walkIndex[context.recordingUUID], walkUUID != currentWalkUUID else { return false }
            return true
        }
        let walksRepresented = Set(qualifying.compactMap { walkIndex[$0.recordingUUID] })
        guard walksRepresented.count >= modalBaselineFloorWalks else { return nil }
        let totalWords = qualifying.reduce(0) { $0 + $1.wordCount }
        guard totalWords > 0 else { return nil }

        var entries: [MarkerLexicons.ModalFamily: ModalBaselineEntry] = [:]
        for family in MarkerLexicons.ModalFamily.allCases {
            let words = MarkerLexicons.modalFamilies[family] ?? []
            let total = qualifying.reduce(0) { sum, context in
                sum + words.reduce(0) { $0 + (context.markers?.modalCounts[$1] ?? 0) }
            }
            entries[family] = ModalBaselineEntry(
                rate: Double(total) / Double(totalWords),
                averagePerWalk: Double(total) / Double(walksRepresented.count)
            )
        }
        return entries
    }

    /// At most one clause, naming the dominant modal family and word — a
    /// state signal, not a topic (design decision: modals live here with
    /// word identity, never as a recurring-word theme). Silent by default:
    /// fires only when the dominant family is both large on its own terms
    /// (`modalRemarkableMinCount`) and elevated against the walker's own
    /// per-walk baseline rate (`modalRemarkableRateMultiple`) — mirrors the
    /// vs-baseline ratio shape `DossierSensesTracks.markerLine` already
    /// uses (guard the baseline is nonzero before dividing by it). No
    /// baseline at all means silence, not a fallback phrasing — first walks
    /// never speak here, unlike the always-on absolutist line.
    private static func modalLeanLine(
        currentRecordings: [(context: TranscriptContext, wordsPerMinute: Double?)],
        allContexts: [TranscriptContext],
        walkIndex: [UUID: UUID],
        currentWalkUUID: UUID
    ) -> String? {
        guard let summary = modalLeanSummary(for: currentRecordings.map(\.context)),
              summary.familyCount >= modalRemarkableMinCount else { return nil }
        guard let baseline = modalBaseline(from: allContexts, walkIndex: walkIndex, excluding: currentWalkUUID),
              let entry = baseline[summary.family], entry.rate > 0,
              summary.familyRate >= modalRemarkableRateMultiple * entry.rate else { return nil }
        return "modal lean: \(summary.family.rawValue) — '\(summary.word)' ×\(summary.count)" +
            " (your usual ~\(Int(entry.averagePerWalk.rounded())) per walk)"
    }

    static func dossier(
        currentRecordings: [(context: TranscriptContext, wordsPerMinute: Double?)],
        allContexts: [TranscriptContext],
        threads: [WalkThread],
        currentWalkUUID: UUID,
        backfillComplete: Bool,
        walkIndex: [UUID: UUID] = [:],
        includeMarkerLines: Bool = true
    ) -> String? {
        guard !currentRecordings.isEmpty else { return nil }

        var section = "**Thought threads (on-device linguistic analysis):**"
        let heading = section

        if includeMarkerLines {
            // Scoped to this branch: the marker-free variant is rendered in
            // the same pass, and computing a baseline it never reads means
            // scanning every historical context twice per screen-open.
            let baseline = personalBaseline(from: allContexts)
            for (index, recording) in currentRecordings.enumerated() {
                section += "\nRecording \(index + 1): \(markerLine(for: recording.context, baseline: baseline))"
            }
            if let modalLine = modalLeanLine(
                currentRecordings: currentRecordings, allContexts: allContexts,
                walkIndex: walkIndex, currentWalkUUID: currentWalkUUID
            ) {
                section += "\n\(modalLine)"
            }
        }

        // No `includeThreadAnalysis` switch here: the thread-suppressed
        // voices (Creative, Gratitude) never call this at all — the builder
        // hands them `dossierSensesOnly`, which is assembled from the
        // `Noticed:` block directly and never passes through this function.
        let activeThreads = threads.filter { thread in
            thread.appearances.contains { $0.walkUUID == currentWalkUUID }
        }
        if !activeThreads.isEmpty {
            section += "\n\n**Threads across recent walks:**"
            for thread in activeThreads {
                var line = "\n'\(thread.displayTerm)'"
                switch ThreadStore.status(of: thread, atWalk: currentWalkUUID, backfillComplete: backfillComplete) {
                case .firstTime:
                    line += " — first appearance in the record"
                case .recurring(let walks):
                    line += " — \(walks) walk\(walks == 1 ? "" : "s") in the last 30 days"
                case nil:
                    break
                }
                if let direction = ThreadStore.salienceDirection(of: thread) {
                    line += ", \(direction.rawValue) across appearances"
                }
                if let origin = thread.appearances.first, backfillComplete {
                    line += " (first spoken \(ContextFormatter.shortDateFormatter.string(from: origin.date)))"
                }
                if let paceNote = paceCorrelation(of: thread, in: currentRecordings) {
                    line += paceNote
                }
                section += line
            }
        }

        if backfillComplete, let quiet = quietLines(threads: threads, currentWalkUUID: currentWalkUUID) {
            section += "\n\n**Quiet this walk:**"
            section += quiet
        }

        return section == heading ? nil : section
    }

    /// Absence is a history claim ("this recurred without you") — as risky
    /// as an origin claim, so it waits on the same backfill gate.
    private static func quietLines(threads: [WalkThread], currentWalkUUID: UUID) -> String? {
        let allAppearances = threads.flatMap(\.appearances)
        let currentWalkDates = allAppearances.filter { $0.walkUUID == currentWalkUUID }.map(\.date)
        guard let anchor = currentWalkDates.max() else { return nil }
        let windowStart = anchor.addingTimeInterval(-absenceWindow)

        let absent = threads
            .filter { thread in !thread.appearances.contains { $0.walkUUID == currentWalkUUID } }
            .compactMap { thread -> (thread: WalkThread, walks: Int)? in
                let walksInWindow = Set(
                    thread.appearances
                        .filter { $0.date >= windowStart && $0.date <= anchor }
                        .map(\.walkUUID)
                ).count
                guard walksInWindow >= minimumAbsenceWalks else { return nil }
                return (thread, walksInWindow)
            }
            .sorted { ($0.walks, $1.thread.lemma) > ($1.walks, $0.thread.lemma) }
            .prefix(maxAbsenceLines)

        guard !absent.isEmpty else { return nil }
        return absent
            .map { "\nNotably quiet this walk: '\($0.thread.displayTerm)' — present in \($0.walks) of the walker's recent walks." }
            .joined()
    }

    /// Mechanical, not editorial: a relative gap between the theme group's
    /// mean pace and the rest of the walk's, with no numbers in the phrasing
    /// (spec principle 1 — trajectory/correlation language stays dossier-only).
    private static func paceCorrelation(
        of thread: WalkThread,
        in recordings: [(context: TranscriptContext, wordsPerMinute: Double?)]
    ) -> String? {
        let inTheme = recordings
            .filter { $0.context.themes.contains { $0.lemma == thread.lemma } }
            .compactMap(\.wordsPerMinute)
        let rest = recordings
            .filter { !$0.context.themes.contains { $0.lemma == thread.lemma } }
            .compactMap(\.wordsPerMinute)
        guard !inTheme.isEmpty, !rest.isEmpty else { return nil }

        let themeMean = inTheme.reduce(0, +) / Double(inTheme.count)
        let restMean = rest.reduce(0, +) / Double(rest.count)
        guard restMean > 0 else { return nil }
        let change = (themeMean - restMean) / restMean

        if change <= -paceDifferenceThreshold { return ", spoken more slowly than the rest of this walk" }
        if change >= paceDifferenceThreshold { return ", spoken more quickly than the rest of this walk" }
        return nil
    }
}
