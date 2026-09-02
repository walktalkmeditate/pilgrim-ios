import Foundation

enum WayError: Error, Equatable { case notFound, returnedToTrail, unavailable, diskFull }

struct WayImporter {

    static let maxRoutePoints = 2000
    static let maxEncounters = 200
    static let maxManifestBytes = 2 * 1024 * 1024
    static let baseURL = URL(string: "https://walk.pilgrimapp.org")!

    /// The importer enforces the id shape itself; it must never depend on a
    /// UI-layer parser having run first.
    static func isShareId(_ id: String) -> Bool {
        id.range(of: "^[A-Za-z0-9_-]{10}$", options: .regularExpression) != nil
    }

    let session: URLSession
    let store: WayStore
    let now: () -> Date

    init(session: URLSession = .shared, store: WayStore = .shared, now: @escaping () -> Date = { Date() }) {
        self.session = session; self.store = store; self.now = now
    }

    func importShare(id: String) async throws -> Way {
        guard Self.isShareId(id) else { throw WayError.notFound }
        let url = Self.baseURL.appendingPathComponent(id).appendingPathComponent("tour.json")
        let data: Data
        let response: URLResponse
        do {
            // Streamed with a cap: a manifest is tens of kilobytes; anything
            // approaching the cap is not a manifest and must not be buffered.
            let (bytes, resp) = try await session.bytes(from: url)
            response = resp
            var buffer = Data()
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count > Self.maxManifestBytes { throw WayError.unavailable }
            }
            data = buffer
        } catch let error as WayError {
            throw error
        } catch {
            throw WayError.unavailable
        }
        guard let http = response as? HTTPURLResponse else { throw WayError.unavailable }
        if http.statusCode == 404 { throw WayError.notFound }
        guard http.statusCode == 200 else { throw WayError.unavailable }
        let decoder = JSONDecoder()
        guard let manifest = try? decoder.decode(TourManifest.self, from: data) else { throw WayError.unavailable }
        let way = try Self.way(from: manifest, shareId: id, now: now())
        try store.save(way)
        return way
    }

    static func way(from m: TourManifest, shareId: String, now: Date) throws -> Way {
        guard let expires = isoDate(m.expires), let departed = isoDate(m.start_date) else { throw WayError.unavailable }
        guard expires > now else { throw WayError.returnedToTrail }
        guard m.route.count >= 2, m.route.count <= maxRoutePoints, m.encounters.count <= maxEncounters else { throw WayError.unavailable }
        let ts0 = m.route[0].ts
        let route = m.route.map { WayPoint(lat: $0.lat, lon: $0.lon, alt: $0.alt, t: Double($0.ts - ts0)) }
        let geometry = WayGeometry(route: route)

        var moments: [WayMoment] = []
        var voiceN = 0, photoN = 0, waypointN = 0, restN = 0
        for e in m.encounters {
            let at: WayCoordinate?
            if let lat = e.lat, let lon = e.lon {
                at = WayCoordinate(lat: lat, lon: lon)
            } else {
                at = nil
            }
            switch e.type {
            case "voice", "ambience":
                guard let n = e.n else { continue }
                voiceN += 1
                moments.append(WayMoment(id: "voice-\(voiceN)", frac: e.frac, at: at,
                    kind: .voice(endFrac: e.end_frac ?? e.frac, duration: e.duration ?? 0,
                                 kind: e.type == "voice" ? .spoken : .ambient, media: .file("audio/\(n).m4a"))))
            case "photo":
                guard let n = e.n else { continue }
                photoN += 1
                moments.append(WayMoment(id: "photo-\(photoN)", frac: e.frac, at: at, kind: .photo(media: .file("photos/\(n).jpg"))))
            case "waypoint":
                waypointN += 1
                moments.append(WayMoment(id: "waypoint-\(waypointN)", frac: e.frac, at: at,
                                         kind: .waypoint(label: e.label ?? "", icon: e.icon ?? "mappin")))
            case "rest":
                restN += 1
                moments.append(WayMoment(id: "rest-\(restN)", frac: e.frac, at: at, kind: .rest(minutes: e.minutes ?? 0)))
            default:
                continue
            }
        }
        for (index, sit) in m.meditation.enumerated() {
            let minutes: Int
            let isEstimate: Bool
            if let seconds = sit.duration {
                minutes = Int((seconds / 60).rounded()); isEstimate = false
            } else {
                minutes = Int((gapSeconds(around: sit.start_frac, geometry: geometry) / 60).rounded()); isEstimate = true
            }
            moments.append(WayMoment(id: "sit-\(index + 1)", frac: sit.start_frac, at: nil,
                                     kind: .meditation(minutes: minutes, isEstimate: isEstimate)))
        }
        moments.sort { $0.frac < $1.frac }

        let places = [m.place_start, m.place_end].compactMap { $0 }
        let title = places.isEmpty ? DateFormatter.localizedString(from: departed, dateStyle: .medium, timeStyle: .none)
            : places.joined(separator: " → ")
        return Way(
            id: "share:\(shareId)",
            source: .share(id: shareId, pageURL: baseURL.appendingPathComponent(shareId)),
            title: title, departedAt: departed, tzIdentifier: m.tz_identifier, expires: expires,
            route: route, totalDistanceMeters: geometry.totalMeters,
            theirActiveSeconds: m.stats?.active_duration ?? geometry.totalSeconds,
            moments: moments,
            weather: m.weather_condition.map { WayWeather(condition: $0, temperatureC: m.weather_temperature) })
    }

    /// The worker writes `expires` through Date.toISOString(), which always
    /// carries milliseconds; iOS writes `start_date` without them. Try both.
    static func isoDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    /// Time between the two route points bracketing `frac`: a sitting collapses
    /// to a single frac on a downsampled route, so the gap holds the sit plus
    /// whatever walking the RDP pass folded into that segment. Rendered "about".
    static func gapSeconds(around frac: Double, geometry: WayGeometry) -> Double {
        let points = geometry.points
        guard points.count > 1, geometry.totalMeters > 0 else { return 0 }
        let target = frac * geometry.totalMeters
        for i in 0..<(points.count - 1) where geometry.cumulative[i] <= target && target <= geometry.cumulative[i + 1] {
            return points[i + 1].t - points[i].t
        }
        return 0
    }
}
