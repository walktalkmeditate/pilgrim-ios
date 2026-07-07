import Foundation

// This file is compiled into both the app and the widget extension: the
// Live Activity ContentState embeds SeekGlanceState, and the widget must
// decode it without pulling in the engine. Everything here is pure
// Foundation — no Combine, no CoreLocation, no engine dependencies.

enum SeekDirectionHint: String, Codable, CaseIterable {
    case ahead
    case left
    case right
    case behind
}

struct SeekGlanceState: Codable, Hashable {
    let distanceBucketMeters: Int
    let directionHint: SeekDirectionHint?
    let isComplete: Bool
}

/// Declared here rather than SeekEngine.swift so the widget-shared file is
/// self-contained; the engine (app target only) references it freely.
enum SeekEnginePhase: Equatable {
    case guiding
    case arrived
    /// Reserved for the reveal ritual choreography (U7); the engine commits
    /// reveals atomically and never parks here itself.
    case revealing
    case complete
}

/// Coarse lock-screen glance derived in the app process (the widget has no
/// sensors and only renders the state it is handed). Direction is relative
/// to course over ground — direction of travel, never compass (AE7).
enum SeekGlanceModel {

    static let bucketWidthMeters = 100.0
    static let maxBucketMeters = 2000
    /// Below this speed the course is stale noise, not a direction of
    /// travel — the hint hides rather than mislead (AE7).
    static let stationarySpeedFloor = 0.4
    static let aheadConeHalfAngle = 45.0
    static let behindConeHalfAngle = 135.0

    static func glance(
        distanceToActiveMeters: Double?,
        courseDegrees: Double?,
        speedMetersPerSecond: Double?,
        bearingToClearingDegrees: Double?,
        phase: SeekEnginePhase
    ) -> SeekGlanceState? {
        if phase == .complete {
            return SeekGlanceState(distanceBucketMeters: 0, directionHint: nil, isComplete: true)
        }
        guard let distance = distanceToActiveMeters else { return nil }

        var hint: SeekDirectionHint?
        if let course = courseDegrees, course >= 0,
           let speed = speedMetersPerSecond, speed >= stationarySpeedFloor,
           let bearing = bearingToClearingDegrees {
            hint = directionHint(courseDegrees: course, bearingDegrees: bearing)
        }
        return SeekGlanceState(
            distanceBucketMeters: distanceBucket(forMeters: distance),
            directionHint: hint,
            isComplete: false
        )
    }

    static func distanceBucket(forMeters meters: Double) -> Int {
        let clamped = max(0, meters)
        let bucket = Int((clamped / bucketWidthMeters).rounded(.down)) * Int(bucketWidthMeters)
        return min(bucket, maxBucketMeters)
    }

    static func directionHint(courseDegrees: Double, bearingDegrees: Double) -> SeekDirectionHint {
        let delta = normalizedDelta(from: courseDegrees, to: bearingDegrees)
        if abs(delta) <= aheadConeHalfAngle { return .ahead }
        if abs(delta) >= behindConeHalfAngle { return .behind }
        return delta > 0 ? .right : .left
    }

    private static func normalizedDelta(from course: Double, to bearing: Double) -> Double {
        ((bearing - course + 540).truncatingRemainder(dividingBy: 360)) - 180
    }
}
