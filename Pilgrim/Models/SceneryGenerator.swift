import SwiftUI

enum ScenerySide {
    case left, right
}

enum SceneryType: CaseIterable {
    case tree, lantern, butterfly, mountain, grass, torii, moon, cairn

    var shape: AnyShape {
        switch self {
        case .tree: AnyShape(TreeShape())
        case .lantern: AnyShape(LanternShape())
        case .butterfly: AnyShape(ButterflyShape())
        case .mountain: AnyShape(MountainShape())
        case .grass: AnyShape(GrassShape())
        case .torii: AnyShape(ToriiGateShape())
        case .moon: AnyShape(MoonShape())
        case .cairn: AnyShape(CairnStonesShape())
        }
    }

    var tintColorName: String {
        switch self {
        case .tree: "moss"
        case .lantern: "stone"
        case .butterfly: "dawn"
        case .mountain: "fog"
        case .grass: "moss"
        case .torii: "stone"
        case .moon: "fog"
        case .cairn: "stone"
        }
    }

    /// Parallax drift in points at the viewport edge — depth of field for
    /// the scroll. Sky and horizon barely move; things at the walker's
    /// feet move most.
    var parallaxWeight: CGFloat {
        switch self {
        case .mountain: 3
        case .moon: 4
        case .torii: 6
        case .tree: 8
        case .lantern: 9
        case .cairn: 9
        case .grass: 12
        case .butterfly: 14
        }
    }
}

struct SceneryPlacement {
    let type: SceneryType
    let side: ScenerySide
    let offset: CGFloat
    /// Cairns only: stones in the stack — a two-stone base plus one per
    /// found place, capped at five.
    var stones: Int = 3
    var shape: AnyShape { type.shape }
    var tintColorName: String { type.tintColorName }
}

struct SceneryGenerator {

    private static let sceneryChance: Double = 0.35

    // The random torii is retired: gates now mark real thresholds only
    // (see the deterministic branch in `scenery(for:)`). Its old band
    // maps to tree so every other walk's rolled item stays exactly what
    // it has always been.
    private static let weights: [(SceneryType, Double)] = [
        (.tree, 0.27),
        (.lantern, 0.18),
        (.grass, 0.22),
        (.butterfly, 0.14),
        (.mountain, 0.11),
        (.tree, 0.05),
        (.moon, 0.03),
    ]

    static func scenery(for snapshot: WalkSnapshot) -> SceneryPlacement? {
        let seed = deterministicSeed(for: snapshot)
        let roll3 = seededRandom(seed: seed, salt: 3)
        let side: ScenerySide = roll3 < 0.5 ? .left : .right
        let roll4 = seededRandom(seed: seed, salt: 4)
        let offset = CGFloat(roll4 * 15 - 7.5)

        // Meaning outranks the lottery: threshold walks stand at a gate,
        // and a seek that found places raises a cairn.
        if snapshot.isThreshold {
            return SceneryPlacement(type: .torii, side: side, offset: offset)
        }
        if snapshot.isSeek && snapshot.foundPlaces > 0 {
            return SceneryPlacement(
                type: .cairn,
                side: side,
                offset: offset,
                stones: min(2 + snapshot.foundPlaces, 5)
            )
        }

        let roll1 = seededRandom(seed: seed, salt: 1)
        #if DEBUG
        // Diagnostics: the journal stress seed forces scenery on every walk
        // so depth-dependent rendering failures separate cleanly from the
        // ordinary 35% placement roll.
        let forceScenery = CommandLine.arguments.contains("--demo-journal-stress")
        #else
        let forceScenery = false
        #endif
        guard forceScenery || roll1 < sceneryChance else { return nil }

        let roll2 = seededRandom(seed: seed, salt: 2)
        let type = pickType(roll: roll2)

        return SceneryPlacement(type: type, side: side, offset: offset)
    }

    private static func pickType(roll: Double) -> SceneryType {
        var cumulative: Double = 0
        for (type, weight) in weights {
            cumulative += weight
            if roll < cumulative {
                return type
            }
        }
        return .tree
    }

    private static func deterministicSeed(for snapshot: WalkSnapshot) -> UInt64 {
        var h: UInt64 = 14695981039346656037
        func mix(_ v: UInt64) { h = (h ^ v) &* 1099511628211 }
        withUnsafeBytes(of: snapshot.id) { $0.forEach { mix(UInt64($0)) } }
        mix(UInt64(bitPattern: Int64(snapshot.startDate.timeIntervalSince1970)))
        mix(UInt64(bitPattern: Int64(snapshot.distance * 100)))
        mix(UInt64(bitPattern: Int64(snapshot.duration)))
        return h
    }

    private static func seededRandom(seed: UInt64, salt: UInt64) -> Double {
        var mixed = seed &+ salt &* 6364136223846793005
        mixed ^= mixed >> 33
        mixed = mixed &* 0xff51afd7ed558ccd
        mixed ^= mixed >> 33
        mixed = mixed &* 0xc4ceb9fe1a85ec53
        mixed ^= mixed >> 33
        return Double(mixed % 10000) / 10000.0
    }
}

struct AnyShape: Shape {
    private let _path: @Sendable (CGRect) -> Path

    init<S: Shape & Sendable>(_ shape: S) {
        _path = { rect in shape.path(in: rect) }
    }

    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}
