import Foundation

actor WaveformCache {

    static let shared = WaveformCache()

    private var cache: [UUID: [Float]] = [:]
    private var inFlight: Set<UUID> = []

    func samples(for id: UUID) -> [Float]? {
        cache[id]
    }

    func store(_ samples: [Float], for id: UUID) {
        cache[id] = samples
        inFlight.remove(id)
    }

    func markInFlight(_ id: UUID) -> Bool {
        guard !inFlight.contains(id), cache[id] == nil else { return false }
        inFlight.insert(id)
        return true
    }

    func clearInFlight(_ id: UUID) {
        inFlight.remove(id)
    }
}
