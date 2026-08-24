import Foundation

struct ThreadAppearance: Equatable {
    let recordingUUID: UUID
    let walkUUID: UUID
    let date: Date
    let mentionCount: Int
    let salience: Double
}

struct WalkThread: Equatable {
    let lemma: String
    let displayTerm: String
    let appearances: [ThreadAppearance]
}

enum ThreadStatus: Equatable {
    case firstTime
    case recurring(walksInWindow: Int)
}

/// Dossier-only: a trend fitted to few noisy points never reaches UI
/// (spec principle 1).
enum SalienceDirection: String {
    case rising, steady, fading
}

enum ThreadStore {

    static let recurrenceWindow: TimeInterval = 30 * 86400
    static let directionFloor = 3
    static let directionThreshold = 0.25

    static func build(
        contexts: [TranscriptContext],
        walks: [UUID: (walkUUID: UUID, date: Date)]
    ) -> [WalkThread] {
        var appearancesByLemma: [String: [ThreadAppearance]] = [:]
        var displayCounts: [String: [String: Int]] = [:]

        for context in contexts {
            guard let walk = walks[context.recordingUUID] else { continue }
            for theme in context.themes {
                appearancesByLemma[theme.lemma, default: []].append(ThreadAppearance(
                    recordingUUID: context.recordingUUID,
                    walkUUID: walk.walkUUID,
                    date: walk.date,
                    mentionCount: theme.mentionCount,
                    salience: theme.salience
                ))
                displayCounts[theme.lemma, default: [:]][theme.displayTerm, default: 0] += theme.mentionCount
            }
        }

        return appearancesByLemma
            .map { lemma, appearances in
                WalkThread(
                    lemma: lemma,
                    displayTerm: displayCounts[lemma]?
                        .min { ($0.value, $1.key) > ($1.value, $0.key) }?.key ?? lemma,
                    appearances: appearances.sorted { ($0.date, $0.recordingUUID.uuidString) < ($1.date, $1.recordingUUID.uuidString) }
                )
            }
            .sorted { $0.lemma < $1.lemma }
    }

    static func status(
        of thread: WalkThread,
        atWalk walkUUID: UUID,
        backfillComplete: Bool
    ) -> ThreadStatus? {
        guard let current = thread.appearances.first(where: { $0.walkUUID == walkUUID }) else { return nil }
        let earlier = thread.appearances.filter { $0.date < current.date && $0.walkUUID != walkUUID }
        if earlier.isEmpty {
            return backfillComplete ? .firstTime : nil
        }
        let windowStart = current.date.addingTimeInterval(-recurrenceWindow)
        let walksInWindow = Set(
            thread.appearances
                .filter { $0.date >= windowStart && $0.date <= current.date }
                .map(\.walkUUID)
        ).count
        return .recurring(walksInWindow: walksInWindow)
    }

    static func salienceDirection(of thread: WalkThread) -> SalienceDirection? {
        let saliences = thread.appearances.map(\.salience)
        guard saliences.count >= directionFloor else { return nil }
        let third = max(1, saliences.count / 3)
        let early = saliences.prefix(third).reduce(0, +) / Double(third)
        let late = saliences.suffix(third).reduce(0, +) / Double(third)
        guard early > 0 else { return .steady }
        let change = (late - early) / early
        if change >= directionThreshold { return .rising }
        if change <= -directionThreshold { return .fading }
        return .steady
    }
}
