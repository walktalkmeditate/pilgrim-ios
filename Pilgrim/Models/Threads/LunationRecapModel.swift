import Foundation

struct LunationRecapTheme: Equatable, Identifiable, Hashable {
    let displayTerm: String
    let lemmas: [String]
    let walkCount: Int
    let isNewThisMoon: Bool

    var id: String { displayTerm }
}

struct LunationRecapModel: Equatable {
    let moonName: String
    let walkCount: Int
    let themes: [LunationRecapTheme]
    let textureLine: String?
    let quietLine: String?
}

enum LunationRecapCopy {

    /// Lunation-scoped counts — deliberately a different sentence shape
    /// from the card's trailing-window ordinals ("third walk now"), so the
    /// two scopes never read as the same metric disagreeing. Always
    /// "walks", even for one (spec sparse state: "in 1 of 1 walks").
    static func themeLine(term: String, walkCount: Int, totalWalks: Int) -> String {
        "'\(term)' — walked with you in \(walkCount) of \(totalWalks) walks"
    }

    /// The headline counts only walks with analyzed transcripts, so the
    /// copy scopes the claim: a walker with fifteen journal walks and three
    /// transcribed must never read "3 walks this moon" as the journal
    /// disagreeing with itself. The zero state ("no recorded words walked
    /// this moon") already carries the same frame.
    static func headline(walkCount: Int) -> String {
        walkCount == 1
            ? "1 walk with recorded words this moon"
            : "\(walkCount) walks with recorded words this moon"
    }

    static let newThisMoon = "new this moon"
    static let nothingHeld = "nothing held on to name this time"
    static let noWords = "no recorded words walked this moon"

    static func invitation(moonName: String) -> String {
        "The \(moonName) has set — see what walked with you."
    }
}

enum LunationRecapModelBuilder {

    static let maxThemes = 6
    static let insightFloor = 3

    /// Pure and live-computed at sheet open — its counts may exceed the
    /// invitation moment's, by design. Window is [start, end): the close
    /// instant belongs to the next moon.
    static func model(
        lunation: Lunation,
        moonName: String,
        contexts: [TranscriptContext],
        walkIndex: [UUID: (walkUUID: UUID, date: Date)],
        paceByRecording: [UUID: Double],
        released: Set<String>,
        backfillComplete: Bool
    ) -> LunationRecapModel {
        let inMoon: (Date) -> Bool = { $0 >= lunation.start && $0 < lunation.end }
        let analyzed = Set(contexts.map(\.recordingUUID))
        let moonRecordings = walkIndex.filter { analyzed.contains($0.key) && inMoon($0.value.date) }
        let totalWalks = Set(moonRecordings.values.map(\.walkUUID)).count

        guard totalWalks > 0 else {
            return LunationRecapModel(
                moonName: moonName, walkCount: 0, themes: [],
                textureLine: nil, quietLine: LunationRecapCopy.noWords
            )
        }

        // ThreadStore no longer filters released lemmas (Task 2 unwired the
        // engine seam); the filter moves here so the release gesture — still
        // live in the UI until Task 3 — keeps dropping its theme from the
        // recap the same walk it's released on.
        let threads = ThreadStore.build(contexts: contexts, walks: walkIndex)
            .filter { !released.contains($0.lemma) }
        // Cohorts group over ALL threads first — a sibling lemma whose
        // appearances all predate the moon still joins its cohort, so
        // isNewThisMoon judges the cohort's full history (mirroring the
        // card builder) — then only cohorts with at least one appearance
        // inside the moon are named.
        let cohorts = Dictionary(grouping: threads, by: \.displayTerm)
            .filter { $0.value.contains { $0.appearances.contains { inMoon($0.date) } } }

        let themes = cohorts
            .map { term, cohort -> LunationRecapTheme in
                let appearances = cohort.flatMap(\.appearances)
                let walkCount = Set(appearances.filter { inMoon($0.date) }.map(\.walkUUID)).count
                let earliest = appearances.map(\.date).min()
                return LunationRecapTheme(
                    displayTerm: term,
                    lemmas: cohort.map(\.lemma).sorted(),
                    walkCount: walkCount,
                    isNewThisMoon: backfillComplete && earliest.map(inMoon) == true
                )
            }
            .sorted { ($0.walkCount, $1.displayTerm) > ($1.walkCount, $0.displayTerm) }
            .prefix(maxThemes)

        let moonRecordingSet = Set(moonRecordings.keys)
        let insightTotal = contexts
            .filter { moonRecordingSet.contains($0.recordingUUID) }
            .compactMap(\.markers)
            .reduce(0) { $0 + $1.insightCount }
        let wpms = moonRecordingSet.compactMap { paceByRecording[$0] }
        let meanWPM = wpms.isEmpty ? nil : wpms.reduce(0, +) / Double(wpms.count)

        return LunationRecapModel(
            moonName: moonName,
            walkCount: totalWalks,
            themes: Array(themes),
            textureLine: ThreadsTexture.line(
                meanWordsPerMinute: meanWPM,
                hasInsight: insightTotal >= insightFloor
            ),
            quietLine: themes.isEmpty ? LunationRecapCopy.nothingHeld : nil
        )
    }
}
