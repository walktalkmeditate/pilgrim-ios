// Pilgrim/Models/Collective/CollectiveRouteCatalog.swift
import Foundation

/// The decoded collective-route artifact, plus the daily selection and the
/// phrasing both surfaces read from.
///
/// Selection and phrasing live here rather than on the service, following the
/// convention `WhisperManifest` sets: tests then exercise the exact code the
/// service uses, with no network and no file system in the way.
struct CollectiveRouteCatalog: Equatable {

    /// Content-derived, compared for inequality rather than order so a
    /// rollback to an earlier artifact also applies.
    let version: String

    /// The selection pool in canonical order: routes sorted by identifier
    /// ascending, then horizons in the order the artifact lists them.
    ///
    /// Stated explicitly because a curator may reorder either array at any
    /// time. Consuming the artifact's own order would make iOS agree with the
    /// web by coincidence, and only until the next bake.
    let entries: [CollectiveRoute]

    static let empty = CollectiveRouteCatalog(version: "", entries: [])

    init(version: String, entries: [CollectiveRoute]) {
        self.version = version
        self.entries = Self.canonicallyOrdered(entries)
    }

    /// Routes first, sorted by identifier; horizons after, in the order given.
    ///
    /// The sort compares UTF-16 code units because that is what JavaScript's
    /// `<` on strings does. Swift's own `<` agrees for the ASCII identifiers
    /// the artifact ships today and would diverge the first time a curator
    /// adds an accented one — which is exactly the kind of drift nobody would
    /// notice until the two surfaces disagreed.
    static func canonicallyOrdered(_ entries: [CollectiveRoute]) -> [CollectiveRoute] {
        let routes = entries
            .filter { !$0.isCosmic }
            .sorted { $0.id.utf16.lexicographicallyPrecedes($1.id.utf16) }
        let horizons = entries.filter(\.isCosmic)
        return routes + horizons
    }
}

// MARK: - Daily selection

extension CollectiveRouteCatalog {

    /// The single entry every pilgrim on earth sees for this UTC day.
    ///
    /// Each entry claims as many slots as its seasonal weight, and the day's
    /// scrambled seed picks one. The scramble is the point: without it,
    /// consecutive dates walk contiguous runs of the same entry.
    ///
    /// Walked as a running total rather than by materialising the pool. Both
    /// surfaces call this from a view body, and building the array meant
    /// copying every entry up to six times — each carrying refcounted strings
    /// and month arrays — only to index once and discard it.
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

    /// The Settings line. Nil when there is no catalog yet or no known
    /// collective total — both surfaces render nothing rather than a guess.
    func dailyLine(for date: Date, collectiveKm: Double?) -> String? {
        entry(for: date).flatMap { $0.dailyLine(collectiveKm: collectiveKm) }
    }

    /// The walk-summary line, anchored to the walk's own date so reopening an
    /// old walk shows what it showed the day it ended.
    func contributionLine(for date: Date, walkKm: Double) -> String? {
        entry(for: date).map { $0.contributionLine(walkKm: walkKm) }
    }
}

// MARK: - Decoding

extension CollectiveRouteCatalog: Decodable {

    private enum CodingKeys: String, CodingKey {
        case version, pilgrimages, horizons
    }

    /// Entries that fail to decode are dropped and the rest of the catalog
    /// still renders, so the bake can add fields or entry kinds without
    /// bricking clients already in the wild.
    ///
    /// Both arrays are optional for the same reason: a bake that emitted only
    /// one of them should cost the pilgrim half the rotation, not all of it.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(String.self, forKey: .version)
        let routes = try container.decodeIfPresent([LossyDecodable<CollectiveRoute>].self, forKey: .pilgrimages) ?? []
        let horizons = try container.decodeIfPresent([LossyDecodable<CollectiveRoute>].self, forKey: .horizons) ?? []

        self.init(version: version, entries: routes.compactMap(\.value) + horizons.compactMap(\.value))
    }
}

// MARK: - LossyDecodable

/// Wraps a `Decodable` so a failed decode stores nil instead of throwing.
///
/// Deliberately duplicated from `WhisperManifest.swift` rather than promoted to
/// a shared type. The whisper schema and the route schema should be free to
/// move apart; sharing the wrapper would couple one contract's tolerance to
/// the other's.
private struct LossyDecodable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        self.value = try? T(from: decoder)
    }
}

// MARK: - Seeding

/// The deterministic generator behind the daily rotation, ported from the web's
/// `utcSeed` and `hashSeed` so both surfaces land on the same entry.
///
/// Deliberately not `Pilgrim/Models/SeededRNG.swift`, for the same reason
/// `LightReading` keeps its own generator: the contract here is "this UTC day
/// resolves to this entry forever, on every platform". A change to a shared RNG
/// would silently reshuffle everyone's day and desync iOS from pilgrimapp.org.
enum CollectiveRouteSeed {

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// The packed seed and the month from one calendar lookup.
    ///
    /// Selection needs both, and asking the calendar twice for the same instant
    /// is exactly the repeated work a view body cannot afford — these are
    /// ICU-backed calls, not arithmetic.
    static func utcDay(of date: Date) -> (seed: UInt32, month: Int) {
        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 1
        let day = components.day ?? 0
        let packed = year * 10_000 + month * 100 + day
        return (UInt32(truncatingIfNeeded: packed), month)
    }

    /// The UTC date packed as YYYYMMDD, matching the web's seed exactly.
    /// Truncating rather than trapping mirrors JavaScript's `>>> 0`.
    static func utcSeed(for date: Date) -> UInt32 {
        utcDay(of: date).seed
    }

    static func utcMonth(of date: Date) -> Int {
        utcDay(of: date).month
    }

    /// The fmix32 finalizer the web scrambles its date seed with.
    ///
    /// Both multiplies must use the overflow operator: `UInt32` multiplication
    /// traps for essentially every input here, where JavaScript's `Math.imul`
    /// simply keeps the low 32 bits.
    static func hash(_ seed: UInt32) -> UInt32 {
        let multiplier: UInt32 = 0x45d9_f3b
        var hashed = seed
        hashed = (hashed ^ (hashed >> 16)) &* multiplier
        hashed = (hashed ^ (hashed >> 16)) &* multiplier
        return hashed ^ (hashed >> 16)
    }
}
