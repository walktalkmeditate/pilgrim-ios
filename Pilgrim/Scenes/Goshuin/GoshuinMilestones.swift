import Foundation

enum GoshuinMilestones {

    enum Milestone: Equatable, Hashable {
        case firstWalk
        case nthWalk(Int)
        case longestWalk
        case longestMeditation
        case firstOfSeason(String)
    }

    static func detect(
        walkCount: Int,
        walkIndex: Int,
        walk: WalkInterface?,
        allWalks: [WalkInterface]
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

        return milestones
    }

    static func label(for milestone: Milestone) -> String {
        switch milestone {
        case .firstWalk: return "First Walk"
        case .nthWalk(let n): return "\(ordinal(n)) Walk"
        case .longestWalk: return "Longest Walk"
        case .longestMeditation: return "Longest Meditation"
        case .firstOfSeason(let s): return "First of \(s)"
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
