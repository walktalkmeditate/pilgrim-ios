import Foundation

/// Starting assumptions from the plan (origin R4) — tuned on real walks,
/// not commitments. Regions are 80–120 m across, so radii are 40–60 m.
enum SeekTuning {
    static let paceMinutesPerMile = 24.5
    static let reserveFraction = 0.25
    static let clearingRadiusRange = 40.0...60.0
    static let minStartDistanceMeters = 250.0
    static let minSpacingMeters = 300.0
    static let singleClearingFraction = 0.40...0.45
    static let homeArcFraction = 0.80...0.90
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
        let clearings = placeChain(count: count, budgetMeters: budget, from: start, home: start, using: &rng)
        return SeekChain(clearings: clearings, budgetMeters: budget)
    }

    // MARK: - Placement

    static func placeChain<R: RandomNumberGenerator>(
        count: Int,
        budgetMeters: Double,
        from: SeekPoint,
        home: SeekPoint,
        using rng: inout R
    ) -> [SeekClearing] {
        var bestCandidate: [SeekClearing] = []
        var bestScore = -Double.infinity

        for _ in 0..<SeekTuning.placementAttempts {
            let candidate: [SeekClearing]
            if count <= 1 {
                candidate = placeSingle(budgetMeters: budgetMeters, from: from, home: home, using: &rng)
            } else if distance(from: from, to: home) < 1.0 {
                candidate = placeLoop(count: count, budgetMeters: budgetMeters, from: from, using: &rng)
            } else {
                candidate = placeCorridor(
                    count: count, budgetMeters: budgetMeters, from: from, home: home, using: &rng
                )
            }
            let score = constraintScore(of: candidate, budgetMeters: budgetMeters, from: from, home: home)
            if score >= 0 { return candidate }
            if score > bestScore {
                bestScore = score
                bestCandidate = candidate
            }
        }
        return bestCandidate
    }

    private static func placeSingle<R: RandomNumberGenerator>(
        budgetMeters: Double,
        from: SeekPoint,
        home: SeekPoint,
        using rng: inout R
    ) -> [SeekClearing] {
        let isOutAndBack = distance(from: from, to: home) < 1.0

        let bearing: Double
        let distanceOut: Double
        if isOutAndBack {
            bearing = Double.random(in: 0..<360, using: &rng)
            distanceOut = Double.random(in: SeekTuning.singleClearingFraction, using: &rng) * budgetMeters
        } else {
            // Rerolled final clearing: bend toward home so current → clearing → home
            // stays inside the remaining budget.
            bearing = bearingDegrees(from: from, to: home) + Double.random(in: -55...55, using: &rng)
            distanceOut = Double.random(in: 0.30...0.45, using: &rng) * budgetMeters
        }
        let point = destination(
            from: from,
            bearingDegrees: bearing,
            distanceMeters: max(distanceOut, SeekTuning.minStartDistanceMeters)
        )
        return [SeekClearing(
            center: point,
            radiusMeters: Double.random(in: SeekTuning.clearingRadiusRange, using: &rng)
        )]
    }

    private static func placeLoop<R: RandomNumberGenerator>(
        count: Int,
        budgetMeters: Double,
        from: SeekPoint,
        using rng: inout R
    ) -> [SeekClearing] {
        // Clearings sit on a circle whose circumference matches the budget and
        // which passes through the start; walking the arc visits each clearing
        // and the final one lands most of the way around, near home.
        let radius = budgetMeters / (2 * .pi)
        let centerBearing = Double.random(in: 0..<360, using: &rng)
        let center = destination(from: from, bearingDegrees: centerBearing, distanceMeters: radius)
        let startAngle = centerBearing + 180
        let direction: Double = Bool.random(using: &rng) ? 1 : -1
        let lastFraction = Double.random(in: SeekTuning.homeArcFraction, using: &rng)

        return (1...count).map { index in
            let evenFraction = lastFraction * Double(index) / Double(count)
            let jitter = index == count ? 0 : Double.random(in: -0.05...0.05, using: &rng)
            let angle = startAngle + direction * (evenFraction + jitter) * 360
            let point = destination(from: center, bearingDegrees: angle, distanceMeters: radius)
            return SeekClearing(
                center: point,
                radiusMeters: Double.random(in: SeekTuning.clearingRadiusRange, using: &rng)
            )
        }
    }

    /// Reroll with 2+ clearings remaining: current position and home differ,
    /// so clearings step along the current → home corridor with lateral
    /// wander, the last landing most of the way home.
    private static func placeCorridor<R: RandomNumberGenerator>(
        count: Int,
        budgetMeters: Double,
        from: SeekPoint,
        home: SeekPoint,
        using rng: inout R
    ) -> [SeekClearing] {
        let direct = distance(from: from, to: home)
        let homeward = bearingDegrees(from: from, to: home)
        let slack = max(budgetMeters - direct, 0)
        let lateralBound = min(slack / 3, budgetMeters * 0.25)
        let lastFraction = Double.random(in: 0.75...0.85, using: &rng)
        let side: Double = Bool.random(using: &rng) ? 1 : -1

        return (1...count).map { index in
            let along = lastFraction * Double(index) / Double(count) * max(direct, budgetMeters * 0.3)
            let lateral = side * Double.random(in: 0.3...1.0, using: &rng) * lateralBound
            let onTrack = destination(from: from, bearingDegrees: homeward, distanceMeters: along)
            let point = destination(from: onTrack, bearingDegrees: homeward + 90, distanceMeters: lateral)
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
        from: SeekPoint,
        home: SeekPoint
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
        pathLength += distance(from: cursor, to: home)
        worst = min(worst, budgetMeters * 1.05 - pathLength)

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
