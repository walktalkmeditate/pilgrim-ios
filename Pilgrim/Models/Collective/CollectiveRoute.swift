// Pilgrim/Models/Collective/CollectiveRoute.swift
import Foundation

/// One entry in the shared collective-route artifact: either a real pilgrimage
/// route or a cosmic horizon.
///
/// The artifact ships the two as separate arrays. `CollectiveRouteCatalog`
/// folds them into a single list of this type so selection and phrasing never
/// have to infer what an entry is from the absence of a field.
struct CollectiveRoute: Equatable {

    /// What an entry is, carrying only the fields that entry actually has. A
    /// route has a name a pilgrim would recognise; a horizon has a preposition
    /// and an object — "around the Earth", "to the Sun" — and no name at all.
    enum Kind: Equatable {
        case route(nameEn: String)
        case cosmic(preposition: String, body: String)
    }

    let id: String
    let kind: Kind
    /// Length in kilometres. The artifact is metric throughout; conversion to
    /// the pilgrim's unit happens at render time.
    let km: Double
    /// A complete, unit-free sentence naming who has actually walked this
    /// entry. Baked upstream so a curator can edit it without an app release.
    let companyLine: String
    let bestMonths: [Int]
    let peakMonths: [Int]

    init(id: String,
         kind: Kind,
         km: Double,
         companyLine: String,
         bestMonths: [Int] = [],
         peakMonths: [Int] = []) {
        self.id = id
        self.kind = kind
        self.km = km
        self.companyLine = companyLine
        self.bestMonths = bestMonths
        self.peakMonths = peakMonths
    }

    var isCosmic: Bool {
        if case .cosmic = kind { return true }
        return false
    }
}

// MARK: - Seasonal weighting

extension CollectiveRoute {

    static let baseWeight = 1
    static let inSeasonBonus = 2
    static let peakBonus = 3

    /// How many slots this entry takes in the day's selection pool.
    ///
    /// Horizons weigh the same all year — they have no season. A route in one
    /// of its best months gains the season bonus, and only then can a peak
    /// month add more. Peak is an intensifier on being in season, never a
    /// boost of its own: a Camino whose peak months (July, August) fall
    /// outside its best months stays at base weight through the heat.
    func weight(inMonth month: Int) -> Int {
        guard !isCosmic else { return Self.baseWeight }
        guard bestMonths.contains(month) else { return Self.baseWeight }

        let inSeasonWeight = Self.baseWeight + Self.inSeasonBonus
        guard peakMonths.contains(month) else { return inSeasonWeight }
        return inSeasonWeight + Self.peakBonus
    }
}

// MARK: - Phrasing

extension CollectiveRoute {

    static let beginningLine = "The path is beginning."

    /// Below this a horizon's percentage rounds to something meaningless, so
    /// the remaining distance is stated instead.
    private static let horizonPercentFloor = 1.0

    /// `Int(_:)` traps above `Int.max`. A nonsense total from a bad API
    /// response should misprint, not crash a walk summary.
    private static let completionsCeiling = 1_000_000_000_000.0

    /// The Settings phrasing: the collective's total measured against this
    /// entry.
    ///
    /// Returns nil when the total is unknown, which it is until a counter
    /// fetch has ever landed. Rendering the beginning-of-path line then would
    /// tell a pilgrim the collective has walked nothing while it is several
    /// hundred kilometres in, so the surface renders no line at all. A total
    /// that is genuinely zero is a different answer, and does get that line.
    func dailyLine(collectiveKm: Double?) -> String? {
        guard let collectiveKm else { return nil }
        // The web guards only `> 0`, which lets an infinite total through to
        // print "Infinity times". Swift would trap converting it to Int, so
        // the finiteness check is deliberate divergence.
        guard collectiveKm > 0, collectiveKm.isFinite else { return Self.beginningLine }

        let times = collectiveKm / km
        switch kind {
        case .route(let nameEn):
            return routeLine(times: times, nameEn: nameEn)
        case .cosmic(let preposition, let body):
            return horizonLine(times: times,
                               remainingKm: km - collectiveKm,
                               preposition: preposition,
                               body: body)
        }
    }

    /// The walk-summary phrasing: this walk's distance placed against the
    /// day's entry, followed by the entry's own sentence about who has walked
    /// it. Depends on no collective total, so it renders on a fresh offline
    /// install and for every entry kind alike.
    func contributionLine(walkKm: Double) -> String {
        let walk = Self.formatted(km: walkKm, rounding: .oneDigit)

        switch kind {
        case .route(let nameEn):
            return "Your \(walk) against the \(nameEn). \(companyLine)"
        case .cosmic(let preposition, let body):
            // A horizon has no name a pilgrim would recognise, so its
            // magnitude carries the contrast instead.
            let magnitude = Self.formatted(km: km, rounding: .wholeNumbers)
            return "Your \(walk) against \(magnitude) \(preposition) \(body). \(companyLine)"
        }
    }

    private func routeLine(times: Double, nameEn: String) -> String {
        let completed = Self.wholeCompletions(times)
        if completed >= 2 { return "Together, we've walked the \(nameEn) \(completed) times." }
        if completed == 1 { return "Together, one \(nameEn) complete." }

        let rawPercent = times * 100
        let roundedPercent = Int(rawPercent.rounded())
        // Reading 100% before the route is actually complete would be a lie.
        let percent = min(99, roundedPercent)
        return "We are \(percent)% of the way to one \(nameEn)."
    }

    private func horizonLine(times: Double, remainingKm: Double, preposition: String, body: String) -> String {
        if times >= 1 {
            let completed = Self.wholeCompletions(times)
            if completed >= 2 { return "Together, \(completed) times \(preposition) \(body)." }
            return "Together, once \(preposition) \(body)."
        }

        let percent = times * 100
        if percent >= Self.horizonPercentFloor {
            let formattedPercent = String(format: "%.1f", percent)
            return "We are \(formattedPercent)% of the way \(preposition) \(body)."
        }

        // The one branch in the whole feature that states a raw distance, and
        // so the one that has to honour the pilgrim's unit.
        let remaining = Self.formatted(km: remainingKm, rounding: .wholeNumbers)
        return "\(remaining) \(preposition) \(body)."
    }

    private static func wholeCompletions(_ times: Double) -> Int {
        Int(min(times.rounded(.down), completionsCeiling))
    }

    private static func formatted(km: Double,
                                  rounding: CustomMeasurementFormatting.FormattingRoundingType) -> String {
        StatsHelper.string(for: km, unit: UnitLength.kilometers, type: .distance, rounding: rounding)
    }
}

// MARK: - Decoding

extension CollectiveRoute: Decodable {

    private enum CodingKeys: String, CodingKey {
        case id, kind, km, companyLine, nameEn, preposition, body, bestMonths, peakMonths
    }

    /// Decoding the marker as an enum is what drops entries the app does not
    /// understand: an unrecognised value throws, and the catalog's lossy array
    /// decode swallows the failure while keeping every sibling.
    private enum KindMarker: String, Decodable {
        case route
        case cosmic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        // An entry with nobody to name cannot satisfy the walk-summary line,
        // so it is not an entry this app can render.
        companyLine = try container.decode(String.self, forKey: .companyLine)
        bestMonths = try container.decodeIfPresent([Int].self, forKey: .bestMonths) ?? []
        peakMonths = try container.decodeIfPresent([Int].self, forKey: .peakMonths) ?? []

        let distance = try container.decode(Double.self, forKey: .km)
        // A zero or non-finite length divides by zero in the phrasing and then
        // traps converting the ratio to Int. Rejecting it at the boundary
        // keeps every downstream call site free of the guard.
        guard distance.isFinite, distance > 0 else {
            throw DecodingError.dataCorruptedError(
                forKey: .km,
                in: container,
                debugDescription: "Entry length must be a positive, finite number of kilometres"
            )
        }
        km = distance

        switch try container.decode(KindMarker.self, forKey: .kind) {
        case .route:
            let nameEn = try container.decode(String.self, forKey: .nameEn)
            kind = .route(nameEn: nameEn)
        case .cosmic:
            let preposition = try container.decode(String.self, forKey: .preposition)
            let body = try container.decode(String.self, forKey: .body)
            kind = .cosmic(preposition: preposition, body: body)
        }
    }
}
