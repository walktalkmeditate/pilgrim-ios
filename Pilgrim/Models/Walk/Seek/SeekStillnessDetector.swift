import CoreLocation
import CoreMotion
import Foundation

/// Seam over CMMotionActivityManager so stillness tests can inject a fake.
protocol SeekMotionActivityProviding: AnyObject {
    var authorizationDenied: Bool { get }
    func startUpdates(handler: @escaping (Bool) -> Void)
    func stopUpdates()
}

final class SeekMotionActivityProvider: SeekMotionActivityProviding {

    private let manager = CMMotionActivityManager()

    var authorizationDenied: Bool {
        let status = CMMotionActivityManager.authorizationStatus()
        return status == .denied || status == .restricted
    }

    func startUpdates(handler: @escaping (Bool) -> Void) {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        manager.startActivityUpdates(to: .main) { activity in
            guard let activity else { return }
            let confident = activity.confidence.rawValue >= CMMotionActivityConfidence.medium.rawValue
            handler(activity.stationary && confident)
        }
    }

    func stopUpdates() {
        manager.stopActivityUpdates()
    }
}

/// Two-of-three stillness voting (origin R15): zero step delta, stationary
/// motion activity at ≥ medium confidence, and low net displacement across
/// accuracy-gated fixes. Displacement is both a vote and a veto — confident
/// movement overrides the other two signals. With Motion & Fitness denied,
/// the detector runs on displacement alone over a lengthened window so the
/// reveal ritual still fires.
final class SeekStillnessDetector {

    enum Update: Equatable {
        case none
        case began
        case completed
    }

    static let displacementThresholdMeters = 15.0
    static let accuracyGateMeters = 50.0
    static let deniedWindowMultiplier = 1.5

    let windowDuration: TimeInterval
    let isDisplacementOnly: Bool

    private let motion: SeekMotionActivityProviding

    private var isMonitoring = false
    private var isSuspended = false
    private var hasCompleted = false
    private var stillSince: Date?

    private var baselineStepCount: Int?
    private var latestStepCount: Int?
    private var motionSaysStill = false
    private var anchorFix: CLLocation?
    private var lastGoodFix: CLLocation?
    private var goodFixCount = 0
    private var maxDisplacementMeters = 0.0

    init(motion: SeekMotionActivityProviding, windowDuration: TimeInterval) {
        self.motion = motion
        let displacementOnly = motion.authorizationDenied
        self.isDisplacementOnly = displacementOnly
        self.windowDuration = displacementOnly
            ? windowDuration * Self.deniedWindowMultiplier
            : windowDuration
    }

    deinit {
        motion.stopUpdates()
    }

    func start() {
        isMonitoring = true
        startMotionUpdatesIfAuthorized()
    }

    func stop() {
        isMonitoring = false
        stillSince = nil
        motion.stopUpdates()
    }

    /// Suspension freezes detection entirely; the window restarts from zero
    /// on resume — a paused walk banks no partial stillness credit.
    func suspend() {
        guard !isSuspended else { return }
        isSuspended = true
        stillSince = nil
        motion.stopUpdates()
    }

    func resume() {
        guard isSuspended else { return }
        isSuspended = false
        resetSignals()
        startMotionUpdatesIfAuthorized()
    }

    func recordSteps(_ count: Int) {
        latestStepCount = count
        if baselineStepCount == nil { baselineStepCount = count }
    }

    func recordLocation(_ location: CLLocation) {
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= Self.accuracyGateMeters else { return }
        lastGoodFix = location
        if let anchorFix {
            maxDisplacementMeters = max(maxDisplacementMeters, location.distance(from: anchorFix))
        } else {
            anchorFix = location
        }
        goodFixCount += 1
    }

    func evaluate(at date: Date) -> Update {
        guard isMonitoring, !isSuspended, !hasCompleted else { return .none }

        guard assessStillness() else {
            stillSince = nil
            return .none
        }
        guard let since = stillSince else {
            stillSince = date
            return .began
        }
        guard date.timeIntervalSince(since) >= windowDuration else { return .none }
        hasCompleted = true
        return .completed
    }

    private func assessStillness() -> Bool {
        let stepsStill = consumeStepDelta()
        let displacement = consumeDisplacement()
        if displacement.veto { return false }
        if isDisplacementOnly { return displacement.still }
        let votes = [stepsStill, motionSaysStill, displacement.still].filter { $0 }.count
        return votes >= 2
    }

    private func consumeStepDelta() -> Bool {
        guard let baseline = baselineStepCount, let latest = latestStepCount else { return false }
        guard latest == baseline else {
            baselineStepCount = latest
            return false
        }
        return true
    }

    /// Net displacement is measured from an anchor fix; a veto re-anchors at
    /// the newest fix so a walker who stops after moving can still settle
    /// into a fresh window.
    private func consumeDisplacement() -> (still: Bool, veto: Bool) {
        guard maxDisplacementMeters < Self.displacementThresholdMeters else {
            anchorFix = lastGoodFix
            goodFixCount = lastGoodFix == nil ? 0 : 1
            maxDisplacementMeters = 0
            return (still: false, veto: true)
        }
        return (still: goodFixCount >= 2, veto: false)
    }

    private func resetSignals() {
        baselineStepCount = latestStepCount
        motionSaysStill = false
        anchorFix = nil
        lastGoodFix = nil
        goodFixCount = 0
        maxDisplacementMeters = 0
    }

    private func startMotionUpdatesIfAuthorized() {
        guard !isDisplacementOnly else { return }
        motion.startUpdates { [weak self] still in
            self?.motionSaysStill = still
        }
    }
}
