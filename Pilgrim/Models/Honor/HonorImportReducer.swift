import Foundation

enum HonorImportState: Equatable {
    case idle, fetching, gathering(progress: Double), ready, mediaMissing([String]), failed(WayError)
}

/// Pure mapping from the downloader's published sets to the overview state,
/// so the state machine is testable without a session.
enum HonorImportReducer {
    static func state(
        wayId: String,
        progress: [String: Double],
        active: Set<String>,
        failures: [String: [String]],
        diskFull: Set<String>
    ) -> HonorImportState {
        if diskFull.contains(wayId) { return .failed(.diskFull) }
        if active.contains(wayId) { return .gathering(progress: progress[wayId] ?? 0) }
        if let missing = failures[wayId], !missing.isEmpty { return .mediaMissing(missing) }
        return .ready
    }
}

enum HonorImportCopy {
    static func line(for state: HonorImportState) -> String? {
        switch state {
        case .idle, .ready: return nil
        case .fetching: return "reaching for the walk…"
        case .gathering(let p): return "gathering their voices · \(Int((p * 100).rounded()))%"
        case .mediaMissing: return "some voices didn't arrive"
        case .failed(.notFound): return "couldn't find that walk. Check the link, or it may have returned to the trail."
        case .failed(.returnedToTrail): return "This walk has returned to the trail"
        case .failed(.unavailable): return "couldn't reach the walk"
        case .failed(.diskFull): return "not enough space on this phone to save these voices"
        }
    }
}
