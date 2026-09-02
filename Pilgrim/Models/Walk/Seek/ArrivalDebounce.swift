import Foundation

/// Consecutive-inside-fix arrival gate shared by Seek and Honor. Fixes worse
/// than the accuracy gate neither advance nor reset the count: a momentary
/// multipath fix must not erase honest progress, and must never fake it.
struct ArrivalDebounce {
    let requiredFixes: Int
    let accuracyMeters: Double
    private(set) var consecutiveInside = 0

    init(requiredFixes: Int, accuracyMeters: Double) {
        self.requiredFixes = requiredFixes
        self.accuracyMeters = accuracyMeters
    }

    /// True on the fix that completes the count.
    mutating func register(distance: Double, radius: Double, accuracy: Double) -> Bool {
        guard accuracy >= 0, accuracy <= accuracyMeters else { return false }
        consecutiveInside = distance <= radius ? consecutiveInside + 1 : 0
        return consecutiveInside >= requiredFixes
    }

    mutating func reset() { consecutiveInside = 0 }
}
