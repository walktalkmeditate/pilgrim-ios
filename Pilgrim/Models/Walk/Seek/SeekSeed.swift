import CryptoKit
import Foundation

/// The seed of a seek: the walker's intention and the moment they crossed
/// the gateway, folded together with OS entropy — all local (R5), nothing
/// communal. The intention is one voice in the seed, never the whole of it:
/// mixed with the moment and fresh entropy so a repeated question never
/// repeats a way, and it enters only as a one-way hash, so nothing personal
/// is derivable from the seed. Statistically this changes nothing —
/// SystemRandomNumberGenerator was already cryptographic — it changes what
/// the randomness *is*: the way is shaped by what was asked, and when.
enum SeekSeed {

    static func make(
        intention: String?,
        moment: Date = Date(),
        fix: TempRouteDataSample? = nil,
        entropy: UInt64 = .random(in: .min ... .max)
    ) -> UInt64 {
        var hasher = SHA256()
        if let intention, !intention.isEmpty {
            hasher.update(data: Data(intention.utf8))
        }
        update(&hasher, with: moment.timeIntervalSince1970)
        if let fix {
            update(&hasher, with: fix.latitude)
            update(&hasher, with: fix.longitude)
            update(&hasher, with: fix.altitude)
            update(&hasher, with: fix.horizontalAccuracy)
        }
        withUnsafeBytes(of: entropy) { hasher.update(bufferPointer: $0) }

        return hasher.finalize().prefix(8).enumerated().reduce(UInt64(0)) {
            $0 | (UInt64($1.element) << (8 * UInt64($1.offset)))
        }
    }

    private static func update(_ hasher: inout SHA256, with value: Double) {
        withUnsafeBytes(of: value.bitPattern) { hasher.update(bufferPointer: $0) }
    }
}

/// SplitMix64 — a full-period generator whose whole state is the 64-bit
/// seed, so one seed is one seek. Not for cryptography; the secrecy budget
/// is spent inside SeekSeed's hash, this only has to be deterministic and
/// well-mixed.
struct SeekSeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}
