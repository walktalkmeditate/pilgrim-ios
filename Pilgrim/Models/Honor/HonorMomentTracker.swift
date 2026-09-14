import CoreLocation
import Foundation

/// Pure moment bookkeeping for an honor walk: which moments have been
/// reached, which voice is playing or waiting, and when a waiting voice is
/// abandoned. No Combine, no timers; the engine feeds it fixes and gates.
struct HonorMomentTracker {

    enum Action: Equatable {
        case reached(WayMoment)
        case voiceStart(WayMoment)
        case voicePause
        case voiceResume
        case voiceDropped(WayMoment)
        /// A water source `meters` ahead on the line.
        case markAhead(WayMark, meters: Double)
    }

    struct Gates: Equatable {
        var paused = false
        var meditating = false
        var recording = false
        var externalAudio = false
        var isClosed: Bool { paused || meditating || recording || externalAudio }
    }

    private let moments: [WayMoment]
    private let geometry: WayGeometry
    private let voicesEnabled: Bool
    private var reached: Set<String> = []
    private var queue: [WayMoment] = []
    private(set) var playing: WayMoment?
    private(set) var isVoicePaused = false
    private let marks: [WayMark]
    private var firedMarks: Set<String> = []
    /// Active seconds at the last water caption; nil means the first is free.
    private var lastMarkSeconds: TimeInterval?

    init(moments: [WayMoment], marks: [WayMark] = [], geometry: WayGeometry, voicesEnabled: Bool) {
        // A tiebreak on id keeps ordering deterministic when two moments
        // share a frac — the same rule `WayImporter` sorts by.
        self.moments = moments.sorted { $0.frac == $1.frac ? $0.id < $1.id : $0.frac < $1.frac }
        // Only on-way water speaks: a fountain 250 m off the trail is a
        // detour, not a drink. Filtering once here keeps the per-fix scan to
        // the handful that could ever fire.
        self.marks = marks
            .filter { $0.kind == .water && $0.offLineMeters <= HonorTuning.onWayMeters }
            .sorted { $0.frac < $1.frac }
        self.geometry = geometry
        self.voicesEnabled = voicesEnabled
    }

    mutating func update(
        location: CLLocationCoordinate2D,
        progressFrac: Double,
        gates: Gates,
        isStationary: Bool,
        activeSeconds: TimeInterval = 0,
        isOnWay: Bool = true
    ) -> [Action] {
        var actions: [Action] = []
        let here = CLLocation(latitude: location.latitude, longitude: location.longitude)

        for moment in moments where !reached.contains(moment.id) {
            guard progressFrac >= moment.frac - HonorTuning.momentFracTolerance else { continue }
            let radius = moment.isVoice ? HonorTuning.voiceRadiusMeters : HonorTuning.momentRadiusMeters
            guard here.distance(from: place(of: moment)) <= radius else { continue }
            reached.insert(moment.id)
            if moment.isVoice {
                if voicesEnabled { queue.append(moment) }
            } else {
                actions.append(.reached(moment))
            }
        }

        // Abandon voices the walker has left far behind, but never while a
        // voice is playing: listening to a long musing carries the walker
        // hundreds of metres, and the next voice must still be waiting.
        if !isStationary, playing == nil || isVoicePaused {
            let dropped = queue.filter { here.distance(from: place(of: $0)) > HonorTuning.voiceDropMeters }
            queue.removeAll { dropped.contains($0) }
            actions += dropped.map { .voiceDropped($0) }
            if let current = playing, isVoicePaused,
               here.distance(from: place(of: current)) > HonorTuning.voiceDropMeters {
                playing = nil
                isVoicePaused = false
                actions.append(.voiceDropped(current))
            }
        }

        actions += waterAhead(progressFrac: progressFrac, activeSeconds: activeSeconds, isOnWay: isOnWay)
        actions += startNextIfPossible(gates: gates)
        return actions
    }

    mutating func gatesDidChange(_ gates: Gates) -> [Action] {
        if playing != nil {
            if gates.isClosed, !isVoicePaused {
                isVoicePaused = true
                return [.voicePause]
            }
            if !gates.isClosed, isVoicePaused {
                isVoicePaused = false
                return [.voiceResume]
            }
            return []
        }
        return startNextIfPossible(gates: gates)
    }

    mutating func voiceDidFinish(gates: Gates) -> [Action] {
        playing = nil
        isVoicePaused = false
        return startNextIfPossible(gates: gates)
    }

    private mutating func startNextIfPossible(gates: Gates) -> [Action] {
        guard playing == nil, !gates.isClosed, !queue.isEmpty else { return [] }
        let next = queue.removeFirst()
        playing = next
        return [.voiceStart(next)]
    }

    /// The nearest unfired water source the walker is about to reach. Never
    /// one already behind them, never off the way, and at most one an hour
    /// of walking — the marks skipped inside the quiet hour stay silent pins.
    private mutating func waterAhead(progressFrac: Double, activeSeconds: TimeInterval, isOnWay: Bool) -> [Action] {
        guard isOnWay, !marks.isEmpty, geometry.totalMeters > 0 else { return [] }
        if let last = lastMarkSeconds, activeSeconds - last < HonorTuning.markQuietSeconds { return [] }
        for mark in marks where !firedMarks.contains(mark.id) {
            let ahead = (mark.frac - progressFrac) * geometry.totalMeters
            guard ahead >= 0 else { continue }
            guard ahead <= HonorTuning.markAheadMeters else { break }
            firedMarks.insert(mark.id)
            lastMarkSeconds = activeSeconds
            return [.markAhead(mark, meters: ahead)]
        }
        return []
    }

    private func place(of moment: WayMoment) -> CLLocation {
        if let at = moment.at { return CLLocation(latitude: at.lat, longitude: at.lon) }
        let c = geometry.coordinate(atFrac: moment.frac)
        return CLLocation(latitude: c.latitude, longitude: c.longitude)
    }
}
