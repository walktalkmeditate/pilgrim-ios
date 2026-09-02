import Foundation

struct SealInput {
    let uuid: String?
    let distance: Double
    let ascend: Double
    let activeDuration: Double
    let meditateDuration: Double
    let talkDuration: Double
    let startDate: Date
    let routePoints: [(lat: Double, lon: Double)]
    let altitudes: [Double]
    let favicon: String?
    let weatherCondition: String?
    let comment: String?
    let routeTimestamps: [Date]
    let activityIntervals: [(type: ActivityInterval.ActivityType, startDate: Date, endDate: Date)]
    let voiceRecordingStartDates: [Date]
    /// Seek arrivals recorded on this walk (reserved-icon waypoints), for
    /// the seeking milestones.
    let foundPlaceCount: Int
    /// Ways walked to their end on this walk, for the honor milestones.
    let honorArrivalCount: Int
    /// The Way this walk honored, for the second ghost line under the seal.
    /// Nil for every walk that was not an honor.
    let wayPoints: [(lat: Double, lon: Double)]?

    init(walk: WalkInterface) {
        self.uuid = walk.uuid?.uuidString
        self.distance = walk.distance
        self.ascend = walk.ascend
        self.activeDuration = walk.activeDuration
        self.meditateDuration = walk.meditateDuration
        self.talkDuration = walk.talkDuration
        self.startDate = walk.startDate
        self.routePoints = walk.routeData.map { (lat: $0.latitude, lon: $0.longitude) }
        self.altitudes = walk.routeData.map(\.altitude)
        self.favicon = walk.favicon
        self.weatherCondition = walk.weatherCondition
        self.comment = walk.comment
        self.routeTimestamps = walk.routeData.map(\.timestamp)
        self.activityIntervals = walk.activityIntervals.map {
            (type: $0.activityType, startDate: $0.startDate, endDate: $0.endDate)
        }
        self.voiceRecordingStartDates = walk.voiceRecordings.map(\.startDate)
        self.foundPlaceCount = walk.waypoints.filter(SeekPersistence.isArrivalWaypoint).count
        self.honorArrivalCount = walk.waypoints.filter(HonorPersistence.isArrivalWaypoint).count
        // One disk read, and only for a walk whose events say it honored a
        // Way — every other seal is built without touching the store.
        let isHonor = walk.workoutEvents.contains { $0.eventType == .honorMode }
        self.wayPoints = isHonor
            ? walk.uuid.flatMap(WayStore.shared.way(forWalk:))?.route.map { (lat: $0.lat, lon: $0.lon) }
            : nil
    }
}
