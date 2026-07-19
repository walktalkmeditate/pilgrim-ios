// Pilgrim/Models/Collective/CollectiveRouteCatalog.swift
import Foundation

/// The decoded collective-route artifact, plus the daily selection and the
/// phrasing both surfaces read from.
struct CollectiveRouteCatalog: Equatable {

    /// Content-derived, so it carries no ordering — compared for inequality
    /// rather than `>` so a rollback to an earlier artifact also reaches devices.
    let version: String

    /// The selection pool in canonical order: routes by identifier ascending, then
    /// horizons as the artifact lists them — re-derived, never trusted from the wire.
    let entries: [CollectiveRoute]

    static let empty = CollectiveRouteCatalog(version: "", entries: [])

    init(version: String, entries: [CollectiveRoute]) {
        self.version = version
        self.entries = Self.canonicallyOrdered(entries)
    }

    /// The decode path, which keeps the artifact's two arrays apart. Which array an
    /// entry arrived in is the contract, not its decoded `kind`: the web sorts
    /// `pilgrimages` and appends `horizons` untouched, so a mis-filed cosmic entry
    /// among the pilgrimages would sort here and not there, desyncing every date.
    private init(version: String, pilgrimages: [CollectiveRoute], horizons: [CollectiveRoute]) {
        self.version = version
        self.entries = Self.sortedById(pilgrimages) + horizons
    }

    /// Kind stands in for provenance where a caller holds one flat list and the arrays are gone.
    static func canonicallyOrdered(_ entries: [CollectiveRoute]) -> [CollectiveRoute] {
        sortedById(entries.filter { !$0.isCosmic }) + entries.filter(\.isCosmic)
    }

    /// UTF-16 code units, because that is what JavaScript's `<` compares. Swift's
    /// native `<` agrees on today's ASCII ids and diverges on the first accented one.
    private static func sortedById(_ entries: [CollectiveRoute]) -> [CollectiveRoute] {
        entries.sorted { $0.id.utf16.lexicographicallyPrecedes($1.id.utf16) }
    }
}

// MARK: - Daily selection

extension CollectiveRouteCatalog {

    /// The single entry every pilgrim on earth sees for this UTC day, weighted by
    /// season. Without the scramble, consecutive dates walk runs of the same entry.
    func entry(for date: Date) -> CollectiveRoute? {
        let day = CollectiveRouteSeed.utcDay(of: date)

        var totalWeight = 0
        for entry in entries {
            totalWeight += entry.weight(inMonth: day.month)
        }
        guard totalWeight > 0 else { return nil }

        let scrambled = CollectiveRouteSeed.hash(day.seed)
        var remaining = Int(scrambled % UInt32(totalWeight))
        for entry in entries {
            remaining -= entry.weight(inMonth: day.month)
            if remaining < 0 { return entry }
        }
        return entries.last
    }

    func dailyLine(for date: Date, collectiveKm: Double?) -> String? {
        entry(for: date).flatMap { $0.dailyLine(collectiveKm: collectiveKm) }
    }

    /// Anchored to the walk's own date, so reopening an old walk shows what it showed the day it ended.
    func contributionLine(for date: Date, walkKm: Double) -> String? {
        entry(for: date).map { $0.contributionLine(walkKm: walkKm) }
    }
}

// MARK: - Decoding

extension CollectiveRouteCatalog: Decodable {

    private enum CodingKeys: String, CodingKey {
        case version, pilgrimages, horizons
    }

    /// A dropped entry is damage limitation, not graceful degradation: every entry
    /// feeds the day's total weight and the seed is taken modulo it, so losing one
    /// silently re-resolves *every* date. A new `kind` is therefore the worst case,
    /// not the safe one, and has to reach the app before it reaches the artifact.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .version)
        let routes = try container.decodeIfPresent([LossyDecodable<CollectiveRoute>].self, forKey: .pilgrimages) ?? []
        let horizons = try container.decodeIfPresent([LossyDecodable<CollectiveRoute>].self, forKey: .horizons) ?? []

        self.init(version: version,
                  pilgrimages: routes.compactMap(\.value),
                  horizons: horizons.compactMap(\.value))
    }
}

// MARK: - LossyDecodable

/// Wraps a `Decodable` so a failed decode stores nil instead of throwing. Duplicated
/// from `WhisperManifest.swift` so neither schema's tolerance constrains the other's.
private struct LossyDecodable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        self.value = try? T(from: decoder)
    }
}

// MARK: - Seeding

/// The deterministic generator behind the daily rotation, ported from the web's
/// `utcSeed` and `hashSeed`. Deliberately not `SeededRNG`: a UTC day must resolve to
/// the same entry forever on every platform, so a shared RNG could never change.
enum CollectiveRouteSeed {

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Seed and month from one calendar lookup — selection needs both, and these are ICU calls, not arithmetic.
    static func utcDay(of date: Date) -> (seed: UInt32, month: Int) {
        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let day = components.day ?? 0
        let packed = year * 10_000 + month * 100 + day
        return (UInt32(truncatingIfNeeded: packed), month)
    }

    /// The UTC date packed as YYYYMMDD; truncating rather than trapping mirrors JavaScript's `>>> 0`.
    static func utcSeed(for date: Date) -> UInt32 {
        utcDay(of: date).seed
    }

    static func utcMonth(of date: Date) -> Int {
        utcDay(of: date).month
    }

    /// The fmix32 finalizer the web scrambles its date seed with. Both multiplies
    /// must use `&*`: plain `UInt32` multiplication traps for essentially every
    /// input here, where JavaScript's `Math.imul` keeps the low 32 bits.
    static func hash(_ seed: UInt32) -> UInt32 {
        let multiplier: UInt32 = 0x45d9_f3b
        var hashed = seed
        hashed = (hashed ^ (hashed >> 16)) &* multiplier
        hashed = (hashed ^ (hashed >> 16)) &* multiplier
        return hashed ^ (hashed >> 16)
    }
}
