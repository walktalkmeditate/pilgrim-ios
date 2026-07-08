import Foundation

/// Starting assumptions from the plan (origin R4) — tuned on real walks,
/// not commitments. Regions are 80–120 m across, so radii are 40–60 m.
enum SeekTuning {
    static let paceMinutesPerMile = 24.5
    static let reserveFraction = 0.25
    static let clearingRadiusRange = 40.0...60.0
    static let minStartDistanceMeters = 250.0
    static let minSpacingMeters = 300.0
    /// Streets aren't crow-flies: walked distance runs ~1.25× the straight
    /// line, so placement converts the walking budget into crow-flies reach.
    static let streetWindingFactor = 1.25
    /// The seek is one-way: the final clearing lands near the walking
    /// limit, and the way home belongs to the walker.
    static let finalClearingFraction = 0.85...1.0
    static let alongJitterFraction = 0.06
    static let lateralWanderFraction = 0.12
    static let metersPerMile = 1609.344
    static let placementAttempts = 12
}

/// Generates the random clearing chain for a seek. Pure and deterministic
/// under an injected generator; production callers pass
/// `SystemRandomNumberGenerator` (cryptographically secure, local — R5).
enum SeekChainGenerator {

    // MARK: - Derivation

    static func clearingCountBand(forDurationMinutes minutes: Int) -> ClosedRange<Int> {
        switch minutes {
        case ..<45: return 1...1
        case ..<90: return 1...2
        default: return 2...3
        }
    }

    static func walkableBudgetMeters(forDurationMinutes minutes: Int) -> Double {
        let walkingMinutes = Double(minutes) * (1 - SeekTuning.reserveFraction)
        return walkingMinutes / SeekTuning.paceMinutesPerMile * SeekTuning.metersPerMile
    }

    // MARK: - Generation

    static func generate<R: RandomNumberGenerator>(
        durationMinutes: Int,
        start: SeekPoint,
        using rng: inout R
    ) -> SeekChain {
        let clamped = min(max(durationMinutes, 1), 240)
        let budget = walkableBudgetMeters(forDurationMinutes: clamped)
        let count = Int.random(in: clearingCountBand(forDurationMinutes: clamped), using: &rng)
        let clearings = placeChain(count: count, budgetMeters: budget, from: start, using: &rng)
        return SeekChain(clearings: clearings, budgetMeters: budget)
    }

    // MARK: - Placement

    static func placeChain<R: RandomNumberGenerator>(
        count: Int,
        budgetMeters: Double,
        from: SeekPoint,
        using rng: inout R
    ) -> [SeekClearing] {
        var bestCandidate: [SeekClearing] = []
        var bestScore = -Double.infinity

        for _ in 0..<SeekTuning.placementAttempts {
            let candidate = placeOutbound(
                count: count, budgetMeters: budgetMeters, from: from, using: &rng
            )
            let score = constraintScore(of: candidate, budgetMeters: budgetMeters, from: from)
            if score >= 0 { return candidate }
            if score > bestScore {
                bestScore = score
                bestCandidate = candidate
            }
        }
        return bestCandidate
    }

    /// One construction for every case, fresh seek and reroll alike: the
    /// chain wanders outward along a random bearing with lateral drift,
    /// and the final clearing lands near the crow-flies reach of the
    /// walking budget. The seek is one-way — no leg home is budgeted.
    private static func placeOutbound<R: RandomNumberGenerator>(
        count: Int,
        budgetMeters: Double,
        from: SeekPoint,
        using rng: inout R
    ) -> [SeekClearing] {
        let reach = budgetMeters / SeekTuning.streetWindingFactor
        let heading = Double.random(in: 0..<360, using: &rng)
        let side: Double = Bool.random(using: &rng) ? 1 : -1
        let lastFraction = Double.random(in: SeekTuning.finalClearingFraction, using: &rng)

        return (1...count).map { index in
            let isLast = index == count
            let jitter = isLast
                ? 0
                : Double.random(
                    in: -SeekTuning.alongJitterFraction...SeekTuning.alongJitterFraction,
                    using: &rng
                )
            let along = max(
                (lastFraction * Double(index) / Double(count) + jitter) * reach,
                SeekTuning.minStartDistanceMeters
            )
            let lateral = isLast
                ? 0
                : side * Double.random(in: 0.2...1.0, using: &rng)
                    * reach * SeekTuning.lateralWanderFraction
            let onTrack = destination(from: from, bearingDegrees: heading, distanceMeters: along)
            let point = destination(from: onTrack, bearingDegrees: heading + 90, distanceMeters: lateral)
            return SeekClearing(
                center: point,
                radiusMeters: Double.random(in: SeekTuning.clearingRadiusRange, using: &rng)
            )
        }
    }

    /// Non-negative when every constraint holds; otherwise the (negative)
    /// worst violation, so a best-effort candidate can be kept when the
    /// attempt budget runs out. Generation must never fail outright.
    private static func constraintScore(
        of clearings: [SeekClearing],
        budgetMeters: Double,
        from: SeekPoint
    ) -> Double {
        var worst = 0.0

        for clearing in clearings {
            worst = min(worst, distance(from: from, to: clearing.center) - SeekTuning.minStartDistanceMeters)
        }
        for (index, first) in clearings.enumerated() {
            for second in clearings.dropFirst(index + 1) {
                worst = min(
                    worst,
                    distance(from: first.center, to: second.center) - SeekTuning.minSpacingMeters
                )
            }
        }

        var pathLength = 0.0
        var cursor = from
        for clearing in clearings {
            pathLength += distance(from: cursor, to: clearing.center)
            cursor = clearing.center
        }
        let reach = budgetMeters / SeekTuning.streetWindingFactor
        worst = min(worst, reach * 1.1 - pathLength)

        return worst
    }

    // MARK: - Spherical math (pure; no Turf/Mapbox dependency in this model)

    private static let earthRadiusMeters = 6_371_000.0

    static func distance(from: SeekPoint, to: SeekPoint) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let a = sin(dLat / 2) * sin(dLat / 2)
            + cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    static func destination(from: SeekPoint, bearingDegrees: Double, distanceMeters: Double) -> SeekPoint {
        let angular = distanceMeters / earthRadiusMeters
        let bearing = bearingDegrees * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lon1 = from.longitude * .pi / 180
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )
        return SeekPoint(latitude: lat2 * 180 / .pi, longitude: lon2 * 180 / .pi)
    }

    static func bearingDegrees(from: SeekPoint, to: SeekPoint) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLon = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return atan2(y, x) * 180 / .pi
    }
}
