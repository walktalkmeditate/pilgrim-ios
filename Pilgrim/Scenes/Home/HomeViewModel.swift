import Foundation
import CoreStore
import Combine

struct WalkSnapshot: Identifiable {
    let id: UUID
    let startDate: Date
    let distance: Double
    let duration: TimeInterval
    let averagePace: Double
    let cumulativeDistance: Double
    let talkDuration: TimeInterval
    let meditateDuration: TimeInterval
    let favicon: String?

    var walkOnlyDuration: TimeInterval {
        max(0, duration - talkDuration - meditateDuration)
    }

    var hasTalk: Bool { talkDuration > 0 }
    var hasMeditate: Bool { meditateDuration > 0 }
}

class HomeViewModel: ObservableObject {

    @Published private(set) var walks: [Walk] = []
    @Published private(set) var walkSnapshots: [WalkSnapshot] = []
    private var cancellables: [AnyCancellable] = []

    init() {
        loadWalks()
    }

    func loadWalks() {
        do {
            walks = try DataManager.dataStack.fetchAll(
                From<Walk>()
                    .orderBy(.descending(\._startDate))
            )
            buildSnapshots()
            updateHemisphereIfNeeded()
        } catch {
            print("[HomeViewModel] Failed to fetch walks:", error.localizedDescription)
            walks = []
            walkSnapshots = []
        }
    }

    func walk(for snapshotID: UUID) -> Walk? {
        walks.first { $0.id == snapshotID }
    }

    var totalTalkDuration: TimeInterval {
        walkSnapshots.reduce(0) { $0 + $1.talkDuration }
    }

    var totalMeditateDuration: TimeInterval {
        walkSnapshots.reduce(0) { $0 + $1.meditateDuration }
    }

    var walksWithTalk: Int {
        walkSnapshots.filter { $0.hasTalk }.count
    }

    var walksWithMeditate: Int {
        walkSnapshots.filter { $0.hasMeditate }.count
    }

    private func buildSnapshots() {
        let reversed = walks.reversed()
        var cumulative: Double = 0
        var snapshots: [WalkSnapshot] = []

        for walk in reversed {
            cumulative += walk.distance
            let duration = walk.activeDuration
            let pace = duration > 0 && walk.distance > 0
                ? duration / (walk.distance / 1000.0)
                : 0
            snapshots.append(WalkSnapshot(
                id: walk.id,
                startDate: walk.startDate,
                distance: walk.distance,
                duration: duration,
                averagePace: pace,
                cumulativeDistance: cumulative,
                talkDuration: walk.talkDuration,
                meditateDuration: walk.meditateDuration,
                favicon: walk.favicon
            ))
        }

        walkSnapshots = snapshots.reversed()
    }

    private func updateHemisphereIfNeeded() {
        guard UserPreferences.hemisphereOverride.value == nil else { return }
        guard let recentWalk = walks.first else { return }

        let routeData = recentWalk.routeData
        guard let firstSample = routeData.first else { return }

        let hemisphere: Hemisphere = firstSample.latitude < 0 ? .southern : .northern
        UserPreferences.hemisphereOverride.value = hemisphere.rawValue
    }
}
