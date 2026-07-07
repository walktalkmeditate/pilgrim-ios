import CoreLocation
import Foundation

/// A plain coordinate for seek geometry — Codable (unlike
/// CLLocationCoordinate2D) so chains ride checkpoints unchanged.
struct SeekPoint: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A single fogged destination region within a seek. The center coordinate
/// lives only in the engine and map layers — it is never shown as a pin.
struct SeekClearing: Codable, Equatable {
    let center: SeekPoint
    let radiusMeters: Double
}

/// The ordered destination list a seek walks through. This shape is the
/// seam for a future pilgrimage mode: real route stages can feed the same
/// engine without rework, so nothing here may assume randomness.
struct SeekChain: Codable, Equatable {
    let clearings: [SeekClearing]
    let budgetMeters: Double

    /// R17: a reroll replaces the active clearing and regenerates everything
    /// downstream under the remaining budget, with the final clearing still
    /// landing near home (or reachable out-and-back when only one remains).
    func regeneratingRemainder<R: RandomNumberGenerator>(
        fromActiveIndex activeIndex: Int,
        current: SeekPoint,
        home: SeekPoint,
        remainingBudgetMeters: Double,
        using rng: inout R
    ) -> SeekChain {
        guard activeIndex >= 0, activeIndex < clearings.count else { return self }
        let kept = Array(clearings.prefix(activeIndex))
        let regenerated = SeekChainGenerator.placeChain(
            count: clearings.count - activeIndex,
            budgetMeters: max(remainingBudgetMeters, SeekEngineTuning.rerollMinBudgetMeters),
            from: current,
            home: home,
            using: &rng
        )
        return SeekChain(clearings: kept + regenerated, budgetMeters: budgetMeters)
    }
}
