import Foundation
import CoreLocation

/// Pure sense engine for the dossier's `Noticed:` block. Binding purity
/// contract (spec principle 8): no DataManager, CoreStore, or singleton
/// access — every input arrives as an argument, fetched by the builder, so
/// every line stays traceable to enumerable, deterministic inputs. `Date()`
/// is never called here; time arrives as data.
enum DossierSenses {

    static let lineCap = 3
    static let placeClusterRadius: CLLocationDistance = 150
    static let placeCandidateThemeCap = 4
    static let hygieneMaxGap: TimeInterval = 90
    static let hygieneMaxAccuracy: Double = 100
    static let photoTieRadius: CLLocationDistance = 75
    static let photoTieMaxInterval: TimeInterval = 600
    static let climbMinTotalAscent: Double = 50
    static let climbMinRunGain: Double = 20
    static let climbSmoothingWindow = 5
    static let climbTopDecile = 0.9
    static let markerWindowRadius = 15
    static let markerMinWindowAbsolutist = 3
    static let markerMinDensityRatio = 2.0
    static let speechShapeMinWordlessRemainder: TimeInterval = 30 * 60
    static let lineageMinWalks = 3

    struct Coordinate: Equatable {
        let latitude: Double
        let longitude: Double
    }

    struct RouteFix: Equatable {
        let coordinate: Coordinate
        let horizontalAccuracy: Double
        let gapSeconds: TimeInterval
    }

    struct ElevationSample: Equatable {
        let timestamp: Date
        let altitude: Double
    }

    struct PhotoPin: Equatable {
        let capturedAt: Date
        let coordinate: Coordinate?
    }

    struct CurrentRecording {
        let uuid: UUID
        let start: Date
        let end: Date
        let text: String
        let wordCount: Int
        let themes: [Theme]
    }

    struct WalkSnapshotRow: Equatable {
        let walkUUID: UUID
        let startDate: Date
        let intention: String?
        let weatherCondition: String?
    }

    struct MoonInput {
        let lunationIndex: Int
        let moonName: String
        let start: Date
        let end: Date
        let lastReportedIndex: Int?
        let currentWalkHasWords: Bool
        let allWalkDates: [Date]
        let wordedWalkDates: [Date]
    }

    struct Input {
        let currentWalkUUID: UUID
        let walkStart: Date
        let walkEnd: Date
        let totalAscent: Double
        let elevationSeries: [ElevationSample]
        let photos: [PhotoPin]
        let currentRecordings: [CurrentRecording]
        /// Every TranscriptContext the builder loaded, current walk
        /// included, so invariance signals can reach historical marker and
        /// modal data by `recordingUUID`. Wired from the fetch the builder
        /// already performs for ThreadsDossierFormatter — never a new query.
        let historicalContexts: [TranscriptContext]
        let threads: [WalkThread]
        let backfillComplete: Bool
        let walkSnapshots: [WalkSnapshotRow]
        let recordingTimestamps: [UUID: Date]
        let fixes: [UUID: RouteFix]
        let moon: MoonInput?
    }

    struct SenseLine: Equatable {
        let text: String
        let lemma: String?
    }

    struct Output: Equatable {
        let lines: [String]
        let reportedLunationIndex: Int?
    }

    /// Declaration order IS the spec's binding priority order — reordering
    /// cases reorders the block. `questionDensity` was cut at the ship gate
    /// (2026-08-25): real-device history fired it once, and the line was a
    /// Whisper punctuation artifact ("151 of today's sentences were
    /// questions"), not genuine question density — the spec's own
    /// contingency was to cut at the gate, not patch.
    enum Sense: CaseIterable {
        case placeResonance, moonLine, markerColoring, intentionLineage,
             climbAnchoring, weatherWeave, photoAdjacency, speechShape
    }

    /// `evaluate` is a test seam (same style as ThreadsBackfill's
    /// `snapshotProvider`); production callers use the default dispatch.
    static func lines(
        input: Input,
        evaluate: (Sense, Input, Set<String>) -> SenseLine? = { DossierSenses.evaluate($0, input: $1, suppressed: $2) }
    ) -> Output {
        var used = Set<String>()
        var lines: [String] = []
        var reportedLunationIndex: Int?
        for sense in Sense.allCases {
            guard lines.count < lineCap else { break }
            guard let line = evaluate(sense, input, used) else { continue }
            // Belt over the senses' own suppression: a theme named at a
            // higher rank never reappears, whatever a sense returns.
            if let lemma = line.lemma {
                guard !used.contains(lemma) else { continue }
                used.insert(lemma)
            }
            lines.append(line.text)
            if sense == .moonLine {
                reportedLunationIndex = input.moon?.lunationIndex
            }
        }
        return Output(lines: lines, reportedLunationIndex: reportedLunationIndex)
    }

    static func evaluate(_ sense: Sense, input: Input, suppressed: Set<String>) -> SenseLine? {
        switch sense {
        case .placeResonance: return placeResonance(input: input, suppressed: suppressed)
        case .moonLine: return moonLine(input: input, suppressed: suppressed)
        case .markerColoring: return markerColoring(input: input, suppressed: suppressed)
        case .intentionLineage: return intentionLineage(input: input, suppressed: suppressed)
        case .climbAnchoring: return climbAnchoring(input: input, suppressed: suppressed)
        case .weatherWeave: return weatherWeave(input: input, suppressed: suppressed)
        case .photoAdjacency: return photoAdjacency(input: input, suppressed: suppressed)
        case .speechShape: return speechShape(input: input, suppressed: suppressed)
        }
    }
}

// MARK: - Shared helpers

extension DossierSenses {

    /// Threads with an appearance on the current walk, in the dossier thread
    /// section's own order (ThreadStore.build sorts by lemma).
    static func activeThreads(in input: Input) -> [WalkThread] {
        input.threads.filter { thread in
            thread.appearances.contains { $0.walkUUID == input.currentWalkUUID }
        }
    }

    static func qualifies(_ fix: RouteFix) -> Bool {
        fix.gapSeconds <= hygieneMaxGap && fix.horizontalAccuracy < hygieneMaxAccuracy
    }

    static func distance(_ a: Coordinate, _ b: Coordinate) -> CLLocationDistance {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        guard !sorted.isEmpty else { return 0 }
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    private static let spelledSmall = [
        3: "three", 4: "four", 5: "five", 6: "six", 7: "seven", 8: "eight", 9: "nine"
    ]
    private static let ordinalWords = [
        3: "Third", 4: "Fourth", 5: "Fifth", 6: "Sixth", 7: "Seventh",
        8: "Eighth", 9: "Ninth", 10: "Tenth", 11: "Eleventh", 12: "Twelfth"
    ]

    static func timesPhrase(_ n: Int) -> String {
        if n == 2 { return "twice" }
        if let word = spelledSmall[n] { return "\(word) times" }
        return "\(n) times"
    }

    static func ordinalWord(_ n: Int) -> String {
        if let word = ordinalWords[n] { return word }
        if (11...13).contains(n % 100) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }
}
