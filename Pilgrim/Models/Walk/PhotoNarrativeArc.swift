import Foundation

/// Pre-computed narrative summary derived from a walk's photo
/// sequence. Fed into the AI prompt so the LLM can reference the
/// visual story arc without having to infer it from raw per-photo
/// metadata.
struct NarrativeArc: Equatable {
    let attentionArc: String
    let solitude: String
    let recurringTheme: [String]
    let dominantColors: [String]
}

/// Pure function: given an ordered array of photo contexts, computes
/// the narrative arc. No Vision dependency — this is downstream of
/// `PhotoContextAnalyzer` and operates on already-extracted metadata.
enum PhotoNarrativeArcBuilder {

    struct Entry {
        let context: PhotoContext
        let capturedAt: Date
        let distanceIntoWalk: Double
    }

    static func build(from entries: [Entry]) -> NarrativeArc {
        guard !entries.isEmpty else {
            return NarrativeArc(
                attentionArc: "none",
                solitude: "unknown",
                recurringTheme: [],
                dominantColors: []
            )
        }

        return NarrativeArc(
            attentionArc: computeAttentionArc(entries),
            solitude: computeSolitude(entries),
            recurringTheme: computeRecurringTheme(entries),
            dominantColors: entries.map(\.context.dominantColor)
        )
    }

    // MARK: - Attention arc

    private static func computeAttentionArc(_ entries: [Entry]) -> String {
        guard entries.count >= 2 else { return "single" }

        let regions = entries.map(\.context.salientRegion)
        let isDetail = { (region: String) -> Bool in
            region == "center" || region.contains("bottom")
        }
        let isWide = { (region: String) -> Bool in
            region.contains("top") || region == "left" || region == "right"
        }

        let first = regions.first!
        let last = regions.last!

        if isDetail(first) && isWide(last) { return "detail_to_wide" }
        if isWide(first) && isDetail(last) { return "wide_to_detail" }

        let detailCount = regions.filter(isDetail).count
        let wideCount = regions.filter(isWide).count

        if detailCount == regions.count { return "consistently_close" }
        if wideCount == regions.count { return "consistently_wide" }

        return "mixed"
    }

    // MARK: - Solitude

    private static func computeSolitude(_ entries: [Entry]) -> String {
        let totalPeople = entries.reduce(0) { $0 + $1.context.people }
        if totalPeople == 0 { return "alone" }

        let photosWithPeople = entries.filter { $0.context.people > 0 }.count
        if photosWithPeople == entries.count { return "with_others" }

        return "mixed"
    }

    // MARK: - Recurring theme

    private static func computeRecurringTheme(_ entries: [Entry]) -> [String] {
        let threshold = max(1, (entries.count + 1) / 2)
        var tagCounts: [String: Int] = [:]

        for entry in entries {
            for tag in entry.context.tags {
                tagCounts[tag, default: 0] += 1
            }
        }

        return tagCounts
            .filter { $0.value >= threshold }
            .sorted { $0.value > $1.value }
            .prefix(5)
            .map(\.key)
    }
}
