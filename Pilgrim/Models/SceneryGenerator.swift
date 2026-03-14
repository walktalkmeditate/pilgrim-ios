import SwiftUI

enum ScenerySide {
    case left, right
}

enum SceneryType: CaseIterable {
    case tree, lantern, butterfly, mountain, grass, torii, moon

    var shape: AnyShape {
        switch self {
        case .tree: AnyShape(TreeShape())
        case .lantern: AnyShape(LanternShape())
        case .butterfly: AnyShape(ButterflyShape())
        case .mountain: AnyShape(MountainShape())
        case .grass: AnyShape(GrassShape())
        case .torii: AnyShape(ToriiGateShape())
        case .moon: AnyShape(MoonShape())
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
        }
    }
}

struct SceneryPlacement {
    let type: SceneryType
    let side: ScenerySide
    let offset: CGFloat
    var shape: AnyShape { type.shape }
    var tintColorName: String { type.tintColorName }
}

struct SceneryGenerator {

    private static let sceneryChance: Double = 0.35

    private static let weights: [(SceneryType, Double)] = [
        (.tree, 0.27),
        (.lantern, 0.18),
        (.grass, 0.22),
        (.butterfly, 0.14),
        (.mountain, 0.11),
        (.torii, 0.05),
        (.moon, 0.03),
    ]

    static func scenery(for snapshot: WalkSnapshot) -> SceneryPlacement? {
        let seed = deterministicSeed(for: snapshot)

        let roll1 = seededRandom(seed: seed, salt: 1)
        guard roll1 < sceneryChance else { return nil }

        let roll2 = seededRandom(seed: seed, salt: 2)
        let type = pickType(roll: roll2)

        let roll3 = seededRandom(seed: seed, salt: 3)
        let side: ScenerySide = roll3 < 0.5 ? .left : .right

        let roll4 = seededRandom(seed: seed, salt: 4)
        let offset = CGFloat(roll4 * 15 - 7.5)

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
        var hasher = Hasher()
        hasher.combine(snapshot.id)
        hasher.combine(Int(snapshot.startDate.timeIntervalSince1970))
        hasher.combine(Int(snapshot.distance * 100))
        hasher.combine(Int(snapshot.duration))
        return UInt64(abs(hasher.finalize()))
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
    private let _path: (CGRect) -> Path

    init<S: Shape>(_ shape: S) {
        _path = shape.path(in:)
    }

    func path(in rect: CGRect) -> Path {
        _path(rect)
    }
}
