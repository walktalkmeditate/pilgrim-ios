import Foundation

struct SharePayload: Encodable {

    let stats: Stats
    let route: [RoutePoint]
    let activityIntervals: [ActivityIntervalPayload]
    let journal: String?
    let expiryDays: Int
    let units: String
    let startDate: String
    let toggledStats: [String]
    let placeStart: String?
    let placeEnd: String?

    struct Stats: Encodable {
        let distance: Double?
        let activeDuration: Double?
        let elevationAscent: Double?
        let elevationDescent: Double?
        let steps: Int?
        let meditateDuration: Double?
        let talkDuration: Double?
        let weatherCondition: String?
        let weatherTemperature: Double?

        enum CodingKeys: String, CodingKey {
            case distance
            case activeDuration = "active_duration"
            case elevationAscent = "elevation_ascent"
            case elevationDescent = "elevation_descent"
            case steps
            case meditateDuration = "meditate_duration"
            case talkDuration = "talk_duration"
            case weatherCondition = "weather_condition"
            case weatherTemperature = "weather_temperature"
        }
    }

    struct RoutePoint: Encodable {
        let lat: Double
        let lon: Double
        let alt: Double
        let ts: Int
    }

    struct ActivityIntervalPayload: Encodable {
        let type: String
        let startTs: Int
        let endTs: Int

        enum CodingKeys: String, CodingKey {
            case type
            case startTs = "start_ts"
            case endTs = "end_ts"
        }
    }

    enum CodingKeys: String, CodingKey {
        case stats, route, journal, units
        case activityIntervals = "activity_intervals"
        case expiryDays = "expiry_days"
        case startDate = "start_date"
        case toggledStats = "toggled_stats"
        case placeStart = "place_start"
        case placeEnd = "place_end"
    }
}
