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

    init(moments: [WayMoment], geometry: WayGeometry, voicesEnabled: Bool) {
        self.moments = moments.sorted { $0.frac < $1.frac }
        self.geometry = geometry
        self.voicesEnabled = voicesEnabled
    }

    mutating func update(
        location: CLLocationCoordinate2D,
        progressFrac: Double,
        gates: Gates,
        isStationary: Bool
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

    private func place(of moment: WayMoment) -> CLLocation {
        if let at = moment.at { return CLLocation(latitude: at.lat, longitude: at.lon) }
        let c = geometry.coordinate(atFrac: moment.frac)
        return CLLocation(latitude: c.latitude, longitude: c.longitude)
    }
}
