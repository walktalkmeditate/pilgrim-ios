import Foundation

enum ThreadsDossierFormatter {

    static let densityFloorWords = 100
    static let baselineFloorRecordings = 5
    static let absenceWindow: TimeInterval = 30 * 86400
    static let minimumAbsenceWalks = 2
    static let maxAbsenceLines = 2
    static let paceDifferenceThreshold = 0.15

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

    static func dossier(
        currentRecordings: [(context: TranscriptContext, wordsPerMinute: Double?)],
        allContexts: [TranscriptContext],
        threads: [WalkThread],
        currentWalkUUID: UUID,
        backfillComplete: Bool
    ) -> String? {
        guard !currentRecordings.isEmpty else { return nil }
        let baseline = personalBaseline(from: allContexts)

        var section = "**Thought threads (on-device linguistic analysis):**"
        for (index, recording) in currentRecordings.enumerated() {
            section += "\nRecording \(index + 1): \(markerLine(for: recording.context, baseline: baseline))"
        }

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
        return section
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
