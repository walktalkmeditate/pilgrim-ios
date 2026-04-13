import Foundation

/// A single astronomical "light reading" for a walk — one true sentence
/// describing the sky conditions at the moment of the walk. Generated
/// deterministically per walk UUID by the `LightReadingGenerator`
/// priority ladder (Task 7), rendered by `WalkLightReadingCard` (Task 9).
struct LightReading: Equatable {
    let sentence: String
    let tier: Tier
    /// SF Symbol name, e.g. `"moon.stars.fill"` or `"sunrise"`. Rendered
    /// as an `Image(systemName:)` in the card view.
    let symbolName: String

    /// Rarity-ordered tiers. Lower raw value = higher priority = fires
    /// first in the generator's evaluation ladder. The baseline tier
    /// `moonPhase` always fires so every walk gets a valid reading.
    enum Tier: Int, Comparable, CaseIterable {
        case lunarEclipse      // ~1-3% of walks
        case supermoon         // ~5-7%
        case seasonalMarker    // ~4%
        case meteorShowerPeak  // ~5-7%
        case fullMoon          // ~10%
        case newMoon           // ~10%
        case deepNight         // ~5-15%
        case sunriseSunset     // ~15-25%
        case twilight          // ~15-25%
        case goldenHour        // ~20-30%
        case moonPhase         // 100% baseline

        // Swift does NOT synthesize Comparable for Int-raw enums.
        static func < (lhs: Tier, rhs: Tier) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Derive a stable UInt64 seed from a UUID's raw bytes. Swift's
    /// built-in `UUID.hashValue` is randomized per process launch for
    /// DoS resistance, so using it as a seed produces non-deterministic
    /// results across app restarts. Packing the first 8 bytes of the
    /// UUID directly guarantees a stable seed for the same walk forever.
    static func stableSeed(from uuid: UUID) -> UInt64 {
        let bytes = uuid.uuid
        var seed: UInt64 = 0
        seed = (seed << 8) | UInt64(bytes.0)
        seed = (seed << 8) | UInt64(bytes.1)
        seed = (seed << 8) | UInt64(bytes.2)
        seed = (seed << 8) | UInt64(bytes.3)
        seed = (seed << 8) | UInt64(bytes.4)
        seed = (seed << 8) | UInt64(bytes.5)
        seed = (seed << 8) | UInt64(bytes.6)
        seed = (seed << 8) | UInt64(bytes.7)
        return seed
    }
}

/// A simple seeded random number generator for deterministic template
/// selection. Uses a linear congruential generator because we only need
/// "different numbers for different seeds", not cryptographic quality.
/// Constants are from Donald Knuth's MMIX LCG.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        // Ensure seed is nonzero (LCG with state=0 is stuck).
        self.state = seed == 0 ? 1 : seed
    }

    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
