import Foundation

/// Mirrors `pilgrim-worker/src/types.ts` `TourManifest` (and `RoutePoint`,
/// `TourEncounter`) exactly enough for `WayImporter` to build a `Way` — only
/// the fields it reads are declared, and every field the worker marks
/// optional (or has promised to add later) stays `Optional` here so an old
/// or a not-yet-widened manifest still decodes.
struct TourManifest: Decodable {

    struct RoutePoint: Decodable, Equatable {
        let lat: Double
        let lon: Double
        let alt: Double
        let ts: Int

        enum CodingKeys: String, CodingKey { case lat, lon, alt, ts }
    }

    /// `type` decodes as a plain `String` (not an enum) so an encounter kind
    /// the worker adds after this build ships still decodes instead of
    /// failing the whole manifest; `WayImporter` skips kinds it doesn't know.
    struct Encounter: Decodable, Equatable {
        let type: String
        let frac: Double
        let end_frac: Double?
        let n: Int?
        let duration: Double?
        let label: String?
        let icon: String?
        let minutes: Int?
        let lat: Double?
        let lon: Double?
        let place: String?

        enum CodingKeys: String, CodingKey {
            case type, frac, end_frac, n, duration, label, icon, minutes, lat, lon, place
        }
    }

    struct Sitting: Decodable, Equatable {
        let start_frac: Double
        let end_frac: Double
        let duration: Double?

        enum CodingKeys: String, CodingKey { case start_frac, end_frac, duration }
    }

    struct Stats: Decodable, Equatable {
        let active_duration: Double?

        enum CodingKeys: String, CodingKey { case active_duration }
    }

    /// `kind` is a plain `String` for the same reason `Encounter.type` is.
    struct ActivitySegment: Decodable, Equatable {
        let kind: String
        let start_frac: Double
        let end_frac: Double

        enum CodingKeys: String, CodingKey { case kind, start_frac, end_frac }
    }

    let v: Int
    let place_start: String?
    let place_end: String?
    let weather_condition: String?
    let weather_temperature: Double?
    let start_date: String
    let tz_identifier: String?
    let expires: String
    let route: [RoutePoint]
    let encounters: [Encounter]
    let meditation: [Sitting]
    let activity_segments: [ActivitySegment]?
    let stats: Stats?

    enum CodingKeys: String, CodingKey {
        case v, place_start, place_end, weather_condition, weather_temperature,
             start_date, tz_identifier, expires, route, encounters, meditation, activity_segments, stats
    }
}
