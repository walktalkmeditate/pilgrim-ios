import Foundation

enum GoshuinMilestones {

    enum Milestone: Equatable, Hashable {
        case firstWalk
        case nthWalk(Int)
        case longestWalk
        case longestMeditation
        case firstOfSeason(String)
        /// Seeking thresholds: the walk that carried the first found place,
        /// and the walks whose arrivals crossed a lifetime count.
        case firstUnknown
        case unknownsFound(Int)
    }

    /// Lifetime found-place counts that earn a seal.
    static let unknownThresholds = [10, 25, 50, 100]

    /// Caption order when a walk earns several milestones at once — Set
    /// iteration is per-process, so without a stable priority the seal
    /// caption and the share-image label shuffle between launches.
    /// Once-ever moments outrank threshold crossings outrank recurring
    /// and transient records; within threshold crossings the largest
    /// count is the headline.
    static func primaryMilestone(of milestones: Set<Milestone>) -> Milestone? {
        milestones.min { lhs, rhs in
            (displayPriority(lhs), -intraPriority(lhs)) < (displayPriority(rhs), -intraPriority(rhs))
        }
    }

    private static func displayPriority(_ milestone: Milestone) -> Int {
        switch milestone {
        case .firstWalk: return 0
        case .firstUnknown: return 1
        case .unknownsFound: return 2
        case .nthWalk: return 3
        case .firstOfSeason: return 4
        case .longestWalk: return 5
        case .longestMeditation: return 6
        }
    }

    private static func intraPriority(_ milestone: Milestone) -> Int {
        switch milestone {
        case .nthWalk(let n), .unknownsFound(let n): return n
        default: return 0
        }
    }

    /// One waypoint-fault pass for the whole book: callers look up arrival
    /// counts by uuid instead of re-faulting every prior walk's waypoint
    /// relationship per seal cell (which was O(walks²) on the main thread).
    static func arrivalCounts(for walks: [WalkInterface]) -> [UUID: Int] {
        var counts: [UUID: Int] = [:]
        for walk in walks {
            guard let uuid = walk.uuid else { continue }
            let count = walk.waypoints.filter(SeekPersistence.isArrivalWaypoint).count
            if count > 0 { counts[uuid] = count }
        }
        return counts
    }

    /// Strictly-before ordering with a stable uuid tie-break, so two walks
    /// sharing a startDate never both count as "before" each other (a
    /// crossing seal would double-award) nor neither (it would vanish).
    static func isOrderedBefore(
        _ lhsDate: Date, _ lhsID: String?,
        _ rhsDate: Date, _ rhsID: String?
    ) -> Bool {
        if lhsDate != rhsDate { return lhsDate < rhsDate }
        return (lhsID ?? "") < (rhsID ?? "")
    }

    /// Seeking milestones for a walk, from its own arrivals and the
    /// lifetime count before it. Awarded to the walk that crosses the
    /// threshold; a walk with no arrivals never earns one.
    static func seekingMilestones(arrivalsInWalk: Int, arrivalsBefore: Int) -> Set<Milestone> {
        guard arrivalsInWalk > 0 else { return [] }
        var milestones: Set<Milestone> = []
        if arrivalsBefore == 0 {
            milestones.insert(.firstUnknown)
        }
        let total = arrivalsBefore + arrivalsInWalk
        for threshold in unknownThresholds where arrivalsBefore < threshold && total >= threshold {
            milestones.insert(.unknownsFound(threshold))
        }
        return milestones
    }

    static func detect(
        walkCount: Int,
        walkIndex: Int,
        walk: WalkInterface?,
        allWalks: [WalkInterface],
        arrivalCounts: [UUID: Int] = [:]
    ) -> Set<Milestone> {
        var milestones: Set<Milestone> = []
        let walkNumber = walkIndex + 1

        if walkNumber == 1 {
            milestones.insert(.firstWalk)
        }

        if walkNumber % 10 == 0 {
            milestones.insert(.nthWalk(walkNumber))
        }

        guard let walk = walk, !allWalks.isEmpty else { return milestones }

        if let longest = allWalks.max(by: { $0.distance < $1.distance }),
           let walkUUID = walk.uuid, let longestUUID = longest.uuid,
           walkUUID == longestUUID {
            milestones.insert(.longestWalk)
        }

        if let longestMed = allWalks.filter({ $0.meditateDuration > 0 })
            .max(by: { $0.meditateDuration < $1.meditateDuration }),
           let walkUUID = walk.uuid, let medUUID = longestMed.uuid,
           walkUUID == medUUID {
            milestones.insert(.longestMeditation)
        }

        let calendar = Calendar.current
        let walkYear = calendar.component(.year, from: walk.startDate)
        let latitude = walk.routeData.first?.latitude ?? 0
        let season = SealTimeHelpers.season(for: walk.startDate, latitude: latitude)

        let isFirstOfSeason = !allWalks.contains { other in
            guard let otherUUID = other.uuid, let walkUUID = walk.uuid,
                  otherUUID != walkUUID,
                  other.startDate < walk.startDate else { return false }
            let otherLat = other.routeData.first?.latitude ?? 0
            let otherSeason = SealTimeHelpers.season(for: other.startDate, latitude: otherLat)
            let otherYear = calendar.component(.year, from: other.startDate)
            return otherSeason == season && otherYear == walkYear
        }

        if isFirstOfSeason {
            milestones.insert(.firstOfSeason(season))
        }

        let arrivalsInWalk = walk.uuid.flatMap { arrivalCounts[$0] } ?? 0
        if arrivalsInWalk > 0 {
            let arrivalsBefore = allWalks.reduce(0) { sum, other in
                guard let otherID = other.uuid, otherID != walk.uuid,
                      isOrderedBefore(
                        other.startDate, otherID.uuidString,
                        walk.startDate, walk.uuid?.uuidString
                      )
                else { return sum }
                return sum + (arrivalCounts[otherID] ?? 0)
            }
            milestones.formUnion(
                seekingMilestones(arrivalsInWalk: arrivalsInWalk, arrivalsBefore: arrivalsBefore)
            )
        }

        return milestones
    }

    static func detect(
        walkCount: Int,
        walkIndex: Int,
        input: SealInput?,
        allInputs: [SealInput]
    ) -> Set<Milestone> {
        if let uuid = input?.uuid,
           UserPreferences.isArchivedWalk(uuidString: uuid) {
            return []
        }

        var milestones: Set<Milestone> = []
        let walkNumber = walkIndex + 1

        if walkNumber == 1 {
            milestones.insert(.firstWalk)
        }

        if walkNumber % 10 == 0 {
            milestones.insert(.nthWalk(walkNumber))
        }

        guard let input = input, !allInputs.isEmpty else { return milestones }

        if let longest = allInputs.max(by: { $0.distance < $1.distance }),
           let walkUUID = input.uuid, let longestUUID = longest.uuid,
           walkUUID == longestUUID {
            milestones.insert(.longestWalk)
        }

        if let longestMed = allInputs.filter({ $0.meditateDuration > 0 })
            .max(by: { $0.meditateDuration < $1.meditateDuration }),
           let walkUUID = input.uuid, let medUUID = longestMed.uuid,
           walkUUID == medUUID {
            milestones.insert(.longestMeditation)
        }

        let calendar = Calendar.current
        let walkYear = calendar.component(.year, from: input.startDate)
        let latitude = input.routePoints.first?.lat ?? 0
        let season = SealTimeHelpers.season(for: input.startDate, latitude: latitude)

        let isFirstOfSeason = !allInputs.contains { other in
            guard let otherUUID = other.uuid, let walkUUID = input.uuid,
                  otherUUID != walkUUID,
                  other.startDate < input.startDate else { return false }
            let otherLat = other.routePoints.first?.lat ?? 0
            let otherSeason = SealTimeHelpers.season(for: other.startDate, latitude: otherLat)
            let otherYear = calendar.component(.year, from: other.startDate)
            return otherSeason == season && otherYear == walkYear
        }

        if isFirstOfSeason {
            milestones.insert(.firstOfSeason(season))
        }

        if input.foundPlaceCount > 0 {
            let arrivalsBefore = allInputs
                .filter {
                    $0.uuid != input.uuid
                        && isOrderedBefore($0.startDate, $0.uuid, input.startDate, input.uuid)
                }
                .reduce(0) { $0 + $1.foundPlaceCount }
            milestones.formUnion(
                seekingMilestones(arrivalsInWalk: input.foundPlaceCount, arrivalsBefore: arrivalsBefore)
            )
        }

        return milestones
    }

    static func label(for milestone: Milestone) -> String {
        switch milestone {
        case .firstWalk: return "First Walk"
        case .nthWalk(let n): return "\(ordinal(n)) Walk"
        case .longestWalk: return "Longest Walk"
        case .longestMeditation: return "Longest Meditation"
        case .firstOfSeason(let s): return "First of \(s)"
        case .firstUnknown: return "First Unknown"
        case .unknownsFound(let n): return "\(n) Unknowns"
        }
    }

    private static func ordinal(_ n: Int) -> String {
        let suffix: String
        let ones = n % 10
        let tens = (n / 10) % 10
        if tens == 1 {
            suffix = "th"
        } else {
            switch ones {
            case 1: suffix = "st"
            case 2: suffix = "nd"
            case 3: suffix = "rd"
            default: suffix = "th"
            }
        }
        return "\(n)\(suffix)"
    }
}
