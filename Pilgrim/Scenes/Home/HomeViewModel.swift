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
    let isShared: Bool
    let weatherCondition: String?
    let isSeek: Bool
    /// Seek arrivals recorded on this walk — a found place earns the walk
    /// a cairn on the ink scroll.
    let foundPlaces: Int
    /// Once-ever gates (first walk, every tenth, first unknown, unknown
    /// milestones) — threshold walks earn a torii on the ink scroll.
    let isThreshold: Bool

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
        let seekWalkIDs = fetchSeekWalkIDs()
        let arrivalCounts = GoshuinMilestones.arrivalCounts(for: walks)
        let reversed = walks.reversed()
        var cumulative: Double = 0
        var arrivalsBefore = 0
        var snapshots: [WalkSnapshot] = []

        for (chronologicalIndex, walk) in reversed.enumerated() {
            cumulative += walk.distance
            let duration = walk.activeDuration
            let pace = duration > 0 && walk.distance > 0
                ? duration / (walk.distance / 1000.0)
                : 0
            let walkNumber = chronologicalIndex + 1
            let foundPlaces = walk.uuid.flatMap { arrivalCounts[$0] } ?? 0
            let isThreshold = walkNumber == 1
                || walkNumber % 10 == 0
                || !GoshuinMilestones.seekingMilestones(
                    arrivalsInWalk: foundPlaces, arrivalsBefore: arrivalsBefore
                ).isEmpty
            arrivalsBefore += foundPlaces

            snapshots.append(WalkSnapshot(
                id: walk.id,
                startDate: walk.startDate,
                distance: walk.distance,
                duration: duration,
                averagePace: pace,
                cumulativeDistance: cumulative,
                talkDuration: walk.talkDuration,
                meditateDuration: walk.meditateDuration,
                favicon: walk.favicon,
                isShared: ShareService.cachedShare(for: walk.id).map { !$0.isExpired } ?? false,
                weatherCondition: walk.weatherCondition,
                isSeek: walk.uuid.map(seekWalkIDs.contains) ?? false,
                foundPlaces: foundPlaces,
                isThreshold: isThreshold
            ))
        }

        walkSnapshots = snapshots.reversed()
    }

    /// Seek walks are marked by their `.seekMode` event (origin R18). One
    /// bulk fetch — the event count equals the seek-walk count — instead of
    /// faulting every walk's event list while building snapshots.
    private func fetchSeekWalkIDs() -> Set<UUID> {
        do {
            let events = try DataManager.dataStack.fetchAll(
                From<WalkEvent>().where(\._eventType == .seekMode)
            )
            return Set(events.compactMap { $0.workout?.uuid })
        } catch {
            print("[HomeViewModel] Failed to fetch seek events:", error.localizedDescription)
            return []
        }
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
