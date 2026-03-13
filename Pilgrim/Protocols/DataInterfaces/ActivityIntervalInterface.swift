import Foundation

public protocol ActivityIntervalInterface: DataInterface {

    var activityType: ActivityInterval.ActivityType { get }
    var startDate: Date { get }
    var endDate: Date { get }

}

public extension ActivityIntervalInterface {

    var activityType: ActivityInterval.ActivityType { throwOnAccess() }
    var startDate: Date { throwOnAccess() }
    var endDate: Date { throwOnAccess() }

    var duration: TimeInterval {
        startDate.distance(to: endDate)
    }

}
