// Pilgrim/Models/Collective/CollectiveRoute.swift
import Foundation

/// One entry in the shared collective-route artifact: either a real pilgrimage
/// route or a cosmic horizon.
struct CollectiveRoute: Equatable {

    /// A horizon has no name a pilgrim would recognise, only a preposition and
    /// an object: "around the Earth", "to the Sun".
    enum Kind: Equatable {
        case route(nameEn: String)
        case cosmic(preposition: String, body: String)
    }

    let id: String
    let kind: Kind
    /// Length in kilometres — the artifact is metric throughout, converted to the pilgrim's unit at render time.
    let km: Double
    /// A complete, unit-free sentence naming who has walked this entry, baked upstream so a curator can edit it without an app release.
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
    /// Peak is an intensifier on being in season, never a boost of its own: a
    /// route whose peak months fall outside its best months stays at base weight.
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

    /// Below this a horizon's percentage rounds to something meaningless, so the remaining distance is stated instead.
    private static let horizonPercentFloor = 1.0

    /// `Int(_:)` traps above `Int.max`; a nonsense total from a bad API response should misprint, not crash a walk summary.
    private static let completionsCeiling = 1_000_000_000_000.0

    /// The Settings phrasing: the collective's total measured against this entry.
    /// Nil when the total is merely unknown (no counter fetch has landed), because
    /// the beginning-of-path line would claim the collective has walked nothing
    /// while it is hundreds of kilometres in. A genuinely zero total does get it.
    func dailyLine(collectiveKm: Double?) -> String? {
        guard let collectiveKm else { return nil }
        // Deliberate divergence: the web guards only `> 0` and prints "Infinity
        // times", where Swift would trap converting that total to Int.
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

    /// The walk-summary phrasing: this walk's distance against the day's entry,
    /// then the entry's own sentence about who has walked it. Needs no collective
    /// total, so it renders on a fresh offline install.
    func contributionLine(walkKm: Double) -> String {
        let walk = Self.formatted(km: walkKm, rounding: .oneDigit)

        switch kind {
        case .route(let nameEn):
            return "Your \(walk) against the \(nameEn). \(companyLine)"
        case .cosmic(let preposition, let body):
            // Nameless, so its magnitude carries the contrast instead.
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

        // The one branch that states a raw distance, so the one that must honour the pilgrim's unit.
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

    /// Decoding as an enum is what drops entries the app does not understand: an
    /// unrecognised value throws, and the catalog's lossy array decode absorbs it.
    private enum KindMarker: String, Decodable {
        case route
        case cosmic
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(String.self, forKey: .id)
        // Required: an entry with nobody to name cannot render the walk-summary line.
        companyLine = try container.decode(String.self, forKey: .companyLine)
        bestMonths = try container.decodeIfPresent([Int].self, forKey: .bestMonths) ?? []
        peakMonths = try container.decodeIfPresent([Int].self, forKey: .peakMonths) ?? []

        let distance = try container.decode(Double.self, forKey: .km)
        // A zero or non-finite length divides by zero in the phrasing and then
        // traps converting the ratio to Int. Rejected here so no call site guards.
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
