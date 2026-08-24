import Foundation

/// One synodic month: the stretch between two new-moon instants, indexed
/// from the same 2000-01-06 reference LunarPhase uses, so phase math and
/// lunation arithmetic can never disagree.
struct Lunation: Equatable, Identifiable {
    let index: Int
    let start: Date
    let end: Date
    let fullMoon: Date

    var id: Int { index }
}

enum LunationCalendar {

    private static let lunationLength = LunarPhase.synodicMonth * 86400

    /// Every boundary Date is minted by this one expression, so
    /// `lunation(at: n).end == lunation(at: n + 1).start` holds exactly —
    /// never `start + length`, which drifts by a ulp and splits boundaries.
    private static func newMoonDate(at index: Int) -> Date {
        LunarPhase.knownNewMoon.addingTimeInterval(Double(index) * lunationLength)
    }

    static func lunation(at index: Int) -> Lunation {
        Lunation(
            index: index,
            start: newMoonDate(at: index),
            end: newMoonDate(at: index + 1),
            fullMoon: newMoonDate(at: index).addingTimeInterval(lunationLength / 2)
        )
    }

    /// The floor division can land one off at exact boundary instants
    /// (Double round-off) — the two correction guards make the close
    /// instant belong to the next lunation, deterministically.
    static func lunation(containing date: Date) -> Lunation {
        var index = Int(floor(date.timeIntervalSince(LunarPhase.knownNewMoon) / lunationLength))
        if date >= newMoonDate(at: index + 1) { index += 1 }
        if date < newMoonDate(at: index) { index -= 1 }
        return lunation(at: index)
    }

    /// The lunation that most recently closed — the only moon that may
    /// invite. Once the next one closes, the previous moves to Past recaps.
    static func mostRecentClosed(asOf date: Date) -> Lunation {
        lunation(at: lunation(containing: date).index - 1)
    }

    /// Traditional full-moon month names, January through December.
    static let monthMoonNames = [
        "Wolf Moon", "Snow Moon", "Worm Moon", "Pink Moon",
        "Flower Moon", "Strawberry Moon", "Buck Moon", "Sturgeon Moon",
        "Corn Moon", "Hunter's Moon", "Beaver Moon", "Cold Moon"
    ]

    /// The moon's name derives from the calendar month of its full-moon
    /// instant in the given timezone (spec: timezone moon naming) — the
    /// same set moon can honestly carry different names in Lisbon and
    /// Auckland, because the walker's sky is the one that counts.
    static func moonName(for lunation: Lunation, in timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return monthMoonNames[calendar.component(.month, from: lunation.fullMoon) - 1]
    }
}
