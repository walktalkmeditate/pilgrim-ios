import Foundation

struct SharePayload: Encodable {

    let stats: Stats
    let route: [RoutePoint]
    let activityIntervals: [ActivityIntervalPayload]
    let journal: String?
    let expiryDays: Int
    let units: String
    let startDate: String
    let tzIdentifier: String?
    let toggledStats: [String]
    let placeStart: String?
    let placeEnd: String?
    let mark: String?
    let waypoints: [Waypoint]?
    let photos: [Photo]?
    var turningDay: String? = nil

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

    struct Waypoint: Encodable {
        let lat: Double
        let lon: Double
        let label: String
        let icon: String
        let ts: Int
    }

    struct Photo: Encodable {
        let lat: Double
        let lon: Double
        let ts: Int
        let data: String?
    }

    struct Pause: Encodable {
        let startTs: Int
        let endTs: Int

        enum CodingKeys: String, CodingKey {
            case startTs = "start_ts"
            case endTs = "end_ts"
        }
    }

    struct Tour: Encodable {
        let recordings: [TourRecording]
        let trimM: Int
        /// The walker's own meditation soundscape (cdn URL). nil when the
        /// walker sits in silence — the page then stays silent too.
        let soundscapeUrl: String?

        enum CodingKeys: String, CodingKey {
            case recordings
            case trimM = "trim_m"
            case soundscapeUrl = "soundscape_url"
        }
    }

    struct TourRecording: Encodable {
        let n: Int
        let startTs: Int
        let endTs: Int
        let duration: Double
        let kind: String
        let transcription: String?
        let wpm: Double?
        let sizeBytes: Int
        /// The route sample nearest the recording's start — nil when the walk
        /// carried no route (e.g. an own-walk Way with GPS off).
        let lat: Double?
        let lon: Double?

        enum CodingKeys: String, CodingKey {
            case n, duration, kind, transcription, wpm, lat, lon
            case startTs = "start_ts"
            case endTs = "end_ts"
            case sizeBytes = "size_bytes"
        }
    }

    var tour: Tour? = nil
    var pauses: [Pause]? = nil

    enum CodingKeys: String, CodingKey {
        case stats, route, journal, units, waypoints, mark, photos, tour, pauses
        case activityIntervals = "activity_intervals"
        case expiryDays = "expiry_days"
        case startDate = "start_date"
        case tzIdentifier = "tz_identifier"
        case toggledStats = "toggled_stats"
        case placeStart = "place_start"
        case placeEnd = "place_end"
        case turningDay = "turning_day"
    }
}
