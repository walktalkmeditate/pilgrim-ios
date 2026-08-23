import Foundation

enum ThreadsDossierFormatter {

    static let densityFloorWords = 100
    static let baselineFloorRecordings = 5

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
        currentRecordingContexts: [TranscriptContext],
        allContexts: [TranscriptContext],
        threads: [WalkThread],
        currentWalkUUID: UUID,
        backfillComplete: Bool
    ) -> String? {
        guard !currentRecordingContexts.isEmpty else { return nil }
        let baseline = personalBaseline(from: allContexts)

        var section = "**Thought threads (on-device linguistic analysis):**"
        for (index, context) in currentRecordingContexts.enumerated() {
            section += "\nRecording \(index + 1): \(markerLine(for: context, baseline: baseline))"
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
                section += line
            }
        }
        return section
    }
}
