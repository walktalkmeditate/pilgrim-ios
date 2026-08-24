import Foundation
import CoreLocation

struct ThreadHistoryEntry: Equatable {
    let recordingUUID: UUID
    let walkUUID: UUID
    let date: Date
    let excerpt: String?
    let isOrigin: Bool
}

enum ThreadHistoryModelBuilder {

    static let excerptRadius = 60

    /// Newest first; the oldest entry carries the origin label — but only
    /// once the one-time backfill has completed. Until then "where it began"
    /// would be a claim about walks not yet analyzed, so origin flags are
    /// suppressed rather than risked (spec), hiding both the footer and the
    /// origin-map action. One entry per recording — when two cohort lemmas
    /// appear in the same recording, the strongest theme (mention count,
    /// then lemma) provides the excerpt.
    static func entries(
        cohort: [WalkThread],
        contextsByRecording: [UUID: TranscriptContext],
        transcriptsByRecording: [UUID: String],
        backfillComplete: Bool
    ) -> [ThreadHistoryEntry] {
        let lemmas = Set(cohort.map(\.lemma))
        let appearancesByRecording = Dictionary(
            grouping: cohort.flatMap(\.appearances), by: \.recordingUUID
        )

        let sorted: [ThreadHistoryEntry] = appearancesByRecording
            .map { recordingUUID, appearances in
                // Same recording ⇒ same walk and date; the excerpt picks the
                // strongest cohort theme itself, so any element serves.
                let appearance = appearances[0]
                return ThreadHistoryEntry(
                    recordingUUID: recordingUUID,
                    walkUUID: appearance.walkUUID,
                    date: appearance.date,
                    excerpt: excerpt(
                        for: lemmas,
                        context: contextsByRecording[recordingUUID],
                        transcript: transcriptsByRecording[recordingUUID]
                    ),
                    isOrigin: false
                )
            }
            .sorted { ($0.date, $0.recordingUUID.uuidString) > ($1.date, $1.recordingUUID.uuidString) }

        guard let oldest = sorted.last else { return [] }
        guard backfillComplete else { return sorted }
        return Array(sorted.dropLast()) + [ThreadHistoryEntry(
            recordingUUID: oldest.recordingUUID,
            walkUUID: oldest.walkUUID,
            date: oldest.date,
            excerpt: oldest.excerpt,
            isOrigin: true
        )]
    }

    static func excerpt(
        for lemmas: Set<String>,
        context: TranscriptContext?,
        transcript: String?
    ) -> String? {
        guard let context, let transcript,
              context.transcriptHash == TranscriptContextStore.hash(of: transcript),
              let theme = context.themes
                .filter({ lemmas.contains($0.lemma) })
                .sorted(by: { ($0.mentionCount, $1.lemma) > ($1.mentionCount, $0.lemma) })
                .first,
              let mention = theme.mentions.first else { return nil }
        return slice(transcript, around: mention, radius: excerptRadius)
    }

    /// Mention offsets are Character (grapheme) counts, produced by
    /// `text.distance` at analysis time — sliced back with `limitedBy:` so
    /// emoji and combining marks can never push an index past either end.
    static func slice(_ transcript: String, around mention: ThemeMention, radius: Int) -> String? {
        guard mention.start >= 0, mention.length > 0,
              let mentionStart = transcript.index(
                transcript.startIndex, offsetBy: mention.start, limitedBy: transcript.endIndex
              ),
              let mentionEnd = transcript.index(
                mentionStart, offsetBy: mention.length, limitedBy: transcript.endIndex
              ) else { return nil }

        let start = transcript.index(mentionStart, offsetBy: -radius, limitedBy: transcript.startIndex)
            ?? transcript.startIndex
        let end = transcript.index(mentionEnd, offsetBy: radius, limitedBy: transcript.endIndex)
            ?? transcript.endIndex

        var excerpt = String(transcript[start..<end])
        if start > transcript.startIndex {
            excerpt = "…" + String(excerpt.drop(while: { !$0.isWhitespace }))
                .trimmingCharacters(in: .whitespaces)
        }
        if end < transcript.endIndex {
            excerpt = String(String(excerpt.reversed()).drop(while: { !$0.isWhitespace }).reversed())
                .trimmingCharacters(in: .whitespaces) + "…"
        }
        return excerpt
    }
}

enum ThreadOriginResolver {

    static let tolerance: TimeInterval = 120

    /// The route sample nearest the recording's start, within tolerance —
    /// beyond it the fix is a guess, and the origin-map action hides
    /// instead of guessing (spec: Return to where it began).
    static func coordinate(
        recordingStart: Date,
        samples: [(timestamp: Date, latitude: Double, longitude: Double)]
    ) -> CLLocationCoordinate2D? {
        guard let nearest = samples.min(by: {
            abs($0.timestamp.timeIntervalSince(recordingStart))
                < abs($1.timestamp.timeIntervalSince(recordingStart))
        }), abs(nearest.timestamp.timeIntervalSince(recordingStart)) <= tolerance else { return nil }
        return CLLocationCoordinate2D(latitude: nearest.latitude, longitude: nearest.longitude)
    }
}
