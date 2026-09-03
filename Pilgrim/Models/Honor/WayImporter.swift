import Foundation

enum WayError: Error, Equatable { case notFound, returnedToTrail, unavailable, diskFull }

struct WayImporter {

    static let maxRoutePoints = 2000
    static let maxEncounters = 200
    static let maxManifestBytes = 2 * 1024 * 1024
    static let baseURL = URL(string: "https://walk.pilgrimapp.org")!

    static let maxAltitudeMeters = 100_000.0
    static let maxUnixSeconds = 4_102_444_800  // year 2100
    static let maxVoiceDurationSeconds: Double = 108 * 60  // the app's 108-minute voice cap
    static let maxRestMinutes = 1440
    static let maxEncounterN = 10_000
    static let maxActiveDurationSeconds: Double = 7 * 24 * 3600
    static let maxTitlePlaceCharacters = 80
    /// Free-text fields from an untrusted manifest reach a map callout, a
    /// card, and the summary. Bounded here, once, so no consumer has to.
    static let maxLabelCharacters = 80
    static let maxIconCharacters = 64
    static let maxWeatherConditionCharacters = 64

    /// The importer enforces the id shape itself; it must never depend on a
    /// UI-layer parser having run first.
    static func isShareId(_ id: String) -> Bool {
        id.range(of: "\\A[A-Za-z0-9_-]{10}\\z", options: .regularExpression) != nil
    }

    /// The overview's toast promises a quick answer ("reaching for the
    /// walk…") and expires at 5 s — `.shared`'s default multi-minute
    /// timeouts would leave a hung request outliving both the copy and the
    /// toast, so a share fetch gets its own short-lived, tightly-timed
    /// session instead.
    private static let defaultSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        return URLSession(configuration: config)
    }()

    let session: URLSession
    let store: WayStore
    let now: () -> Date

    init(session: URLSession = WayImporter.defaultSession, store: WayStore = .shared, now: @escaping () -> Date = { Date() }) {
        self.session = session; self.store = store; self.now = now
    }

    func importShare(id: String) async throws -> Way {
        guard Self.isShareId(id) else { throw WayError.notFound }
        let url = Self.baseURL.appendingPathComponent(id).appendingPathComponent("tour.json")
        let data: Data
        do {
            let (bytes, response) = try await session.bytes(from: url)
            // Checked before draining: a 404 or an oversized declared length
            // must not cost a full download first.
            guard let http = response as? HTTPURLResponse else { throw WayError.unavailable }
            if http.statusCode == 404 { throw WayError.notFound }
            guard http.statusCode == 200 else { throw WayError.unavailable }
            guard http.expectedContentLength <= Int64(Self.maxManifestBytes) else { throw WayError.unavailable }
            // Streamed with a cap: a manifest is tens of kilobytes; anything
            // approaching the cap is not a manifest and must not be buffered.
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
        let manifest: TourManifest
        do {
            manifest = try JSONDecoder().decode(TourManifest.self, from: data)
        } catch {
            print("[WayImporter] manifest decode failed: \(error)")
            throw WayError.unavailable
        }
        let way = try Self.way(from: manifest, shareId: id, now: now())
        try store.save(way)
        return way
    }

    /// The manifest is untrusted input from a public share link: `Int(_:)` traps on
    /// an out-of-range `Double`, and `Int` subtraction traps on overflow, so every
    /// field that later feeds either operation is range-checked here first.
    private static func validate(_ m: TourManifest) -> Bool {
        func inLat(_ v: Double) -> Bool { (-90...90).contains(v) }
        func inLon(_ v: Double) -> Bool { (-180...180).contains(v) }
        func inFrac(_ v: Double) -> Bool { (0...1).contains(v) }

        guard m.route.allSatisfy({ point in
            inLat(point.lat) && inLon(point.lon) && abs(point.alt) < maxAltitudeMeters
                && (0...maxUnixSeconds).contains(point.ts)
        }) else { return false }
        for i in m.route.indices.dropFirst() where m.route[i].ts < m.route[i - 1].ts { return false }

        for e in m.encounters {
            guard inFrac(e.frac) else { return false }
            if let v = e.end_frac, !inFrac(v) { return false }
            if let v = e.duration, !(0...maxVoiceDurationSeconds).contains(v) { return false }
            if let v = e.minutes, !(0...maxRestMinutes).contains(v) { return false }
            if let v = e.n, !(1...maxEncounterN).contains(v) { return false }
            if let v = e.lat, !inLat(v) { return false }
            if let v = e.lon, !inLon(v) { return false }
        }

        for sit in m.meditation {
            guard inFrac(sit.start_frac), inFrac(sit.end_frac) else { return false }
            if let v = sit.duration, !(0...maxVoiceDurationSeconds).contains(v) { return false }
        }

        if let v = m.stats?.active_duration, !(0...maxActiveDurationSeconds).contains(v) { return false }
        if let v = m.weather_temperature, !(-100...100).contains(v) { return false }

        return true
    }

    static func way(from m: TourManifest, shareId: String, now: Date) throws -> Way {
        guard let expires = isoDate(m.expires), let departed = isoDate(m.start_date) else { throw WayError.unavailable }
        guard expires > now else { throw WayError.returnedToTrail }
        guard m.route.count >= 2, m.route.count <= maxRoutePoints,
              m.encounters.count <= maxEncounters, m.meditation.count <= maxEncounters else { throw WayError.unavailable }
        guard validate(m) else { throw WayError.unavailable }
        let ts0 = m.route[0].ts
        let route = m.route.map { WayPoint(lat: $0.lat, lon: $0.lon, alt: $0.alt, t: Double($0.ts - ts0)) }
        let geometry = try validGeometry(for: route)

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
                    kind: .waypoint(label: capped(e.label, maxLabelCharacters), icon: capped(e.icon, maxIconCharacters, or: "mappin"))))
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
        // A tiebreak on id keeps ordering deterministic when two moments share a frac.
        moments.sort { $0.frac == $1.frac ? $0.id < $1.id : $0.frac < $1.frac }

        let wayTitle = title(placeStart: m.place_start, placeEnd: m.place_end, departed: departed)
        return Way(
            id: "share:\(shareId)",
            source: .share(id: shareId, pageURL: baseURL.appendingPathComponent(shareId)),
            title: wayTitle, departedAt: departed, tzIdentifier: m.tz_identifier, expires: expires,
            route: route, totalDistanceMeters: geometry.totalMeters,
            theirActiveSeconds: m.stats?.active_duration ?? geometry.totalSeconds,
            moments: moments,
            weather: m.weather_condition.map { WayWeather(condition: capped($0, maxWeatherConditionCharacters), temperatureC: m.weather_temperature) })
    }

    /// A route with no real length is not a Way anyone can follow: the same
    /// floor `OwnWalkWayBuilder` applies to the walker's own walks.
    private static func validGeometry(for route: [WayPoint]) throws -> WayGeometry {
        let geometry = WayGeometry(route: route)
        guard geometry.totalMeters >= OwnWalkWayBuilder.minLengthMeters else { throw WayError.unavailable }
        return geometry
    }

    /// Bounds one free-text field from an untrusted manifest.
    private static func capped(_ value: String?, _ max: Int, or fallback: String = "") -> String {
        String((value ?? fallback).prefix(max))
    }

    /// Drops place strings that are empty after trimming and caps each at
    /// `maxTitlePlaceCharacters`, falling back to the departure date when
    /// neither place survived.
    private static func title(placeStart: String?, placeEnd: String?, departed: Date) -> String {
        let places = [placeStart, placeEnd].compactMap { place -> String? in
            guard let trimmed = place?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
            return String(trimmed.prefix(maxTitlePlaceCharacters))
        }
        return places.isEmpty ? DateFormatter.localizedString(from: departed, dateStyle: .medium, timeStyle: .none)
            : places.joined(separator: " → ")
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
