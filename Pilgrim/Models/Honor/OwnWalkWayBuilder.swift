import Foundation

/// A Way from one of the walker's own walks. Nothing is copied: voices
/// reference their recording files and photos their PhotoKit assets.
enum OwnWalkWayBuilder {

    static let maxRoutePoints = 4000
    static let minRestSeconds = 180.0
    /// Below this a "Way" is a cluster of jitter around one spot: every frac
    /// collapses onto the same place, the companion cannot move, and arrival
    /// is either instant or unreachable. Shared with `WayImporter`.
    static let minLengthMeters = 20.0

    static func make(from walk: WalkInterface) -> Way? {
        let samples = walk.routeData.sorted { $0.timestamp < $1.timestamp }
        guard samples.count >= 2, let first = samples.first, let uuid = walk.uuid else { return nil }
        let t0 = first.timestamp
        let full = samples.map {
            WayPoint(lat: $0.latitude, lon: $0.longitude, alt: $0.altitude,
                     t: $0.timestamp.timeIntervalSince(t0))
        }
        let fullGeometry = WayGeometry(route: full)
        guard fullGeometry.totalMeters >= minLengthMeters else { return nil }
        let route = full.count > maxRoutePoints ? strideSample(full, target: maxRoutePoints) : full

        var moments: [WayMoment] = []
        // Positions come from the FULL-resolution samples, before any
        // downsampling, so a voice lands where it was spoken.
        func place(_ date: Date) -> (frac: Double, at: WayCoordinate) {
            let nearest = samples.min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) } ?? first
            let frac = fullGeometry.frac(atElapsed: nearest.timestamp.timeIntervalSince(t0))
            return (frac, WayCoordinate(lat: nearest.latitude, lon: nearest.longitude))
        }

        // Recordings are deletable in-app while their rows stay; a Way must
        // not promise a voice whose file is gone (TourBuilder.candidates
        // makes the same check).
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let present = walk.voiceRecordings
            .filter { !$0.fileRelativePath.isEmpty }
            .filter {
                let size = (try? FileManager.default.attributesOfItem(atPath: docs.appendingPathComponent($0.fileRelativePath).path)[.size]) as? Int
                return (size ?? 0) > 0
            }
            .sorted { $0.startDate < $1.startDate }
        for (n, rec) in present.enumerated() {
            let start = place(rec.startDate)
            let end = place(rec.endDate)
            moments.append(WayMoment(
                id: "voice-\(n + 1)", frac: start.frac, at: start.at,
                kind: .voice(endFrac: max(end.frac, start.frac), duration: rec.duration,
                             kind: TourBuilder.classify(transcription: rec.transcription) == .spoken ? .spoken : .ambient,
                             media: .recording(relativePath: rec.fileRelativePath))))
        }
        for (n, photo) in walk.walkPhotos.sorted(by: { $0.capturedAt < $1.capturedAt }).enumerated() {
            let p = place(photo.capturedAt)
            moments.append(WayMoment(
                id: "photo-\(n + 1)", frac: p.frac,
                at: WayCoordinate(lat: photo.capturedLat, lon: photo.capturedLng),
                kind: .photo(media: .photoAsset(localIdentifier: photo.localIdentifier))))
        }
        let userWaypoints = walk.waypoints
            .filter { !SeekPersistence.isArrivalWaypoint($0) && !HonorPersistence.isArrivalWaypoint($0) }
            .sorted { $0.timestamp < $1.timestamp }
        for (n, wp) in userWaypoints.enumerated() {
            moments.append(WayMoment(
                id: "waypoint-\(n + 1)", frac: place(wp.timestamp).frac,
                at: WayCoordinate(lat: wp.latitude, lon: wp.longitude),
                kind: .waypoint(label: wp.label, icon: wp.icon)))
        }
        let rests = walk.pauses
            .filter { $0.endDate.timeIntervalSince($0.startDate) >= minRestSeconds }
            .sorted { $0.startDate < $1.startDate }
        for (n, pause) in rests.enumerated() {
            let p = place(pause.startDate)
            moments.append(WayMoment(
                id: "rest-\(n + 1)", frac: p.frac, at: p.at,
                kind: .rest(minutes: Int((pause.endDate.timeIntervalSince(pause.startDate) / 60).rounded()))))
        }
        let sittings = walk.activityIntervals
            .filter { $0.activityType == .meditation }
            .sorted { $0.startDate < $1.startDate }
        for (n, sit) in sittings.enumerated() {
            let p = place(sit.startDate)
            moments.append(WayMoment(
                id: "sit-\(n + 1)", frac: p.frac, at: p.at,
                kind: .meditation(minutes: Int((sit.endDate.timeIntervalSince(sit.startDate) / 60).rounded()),
                                  isEstimate: false)))
        }
        moments.sort { $0.frac == $1.frac ? $0.id < $1.id : $0.frac < $1.frac }

        // The same stretches the walk's own route colors: a recording is a
        // talking span, a sitting a meditating span.
        let spans = Self.spans(
            talking: present.map { ($0.startDate, $0.endDate) },
            meditating: sittings.map { ($0.startDate, $0.endDate) },
            frac: { place($0).frac })

        let title: String
        if let comment = walk.comment?.trimmingCharacters(in: .whitespacesAndNewlines), !comment.isEmpty {
            title = comment
        } else {
            title = DateFormatter.localizedString(from: walk.startDate, dateStyle: .medium, timeStyle: .none)
        }
        let weather = walk.weatherCondition.map { WayWeather(condition: $0, temperatureC: walk.weatherTemperature) }

        return Way(
            id: "walk:\(uuid.uuidString)", source: .ownWalk(uuid), title: title,
            departedAt: walk.startDate, tzIdentifier: TimeZone.current.identifier, expires: nil,
            route: route, totalDistanceMeters: fullGeometry.totalMeters,
            theirActiveSeconds: walk.activeDuration, moments: moments, weather: weather, spans: spans)
    }

    private static func spans(
        talking: [(start: Date, end: Date)],
        meditating: [(start: Date, end: Date)],
        frac: (Date) -> Double
    ) -> [WaySpan] {
        func spans(_ intervals: [(start: Date, end: Date)], kind: WaySpanKind) -> [WaySpan] {
            intervals.compactMap { interval in
                let start = frac(interval.start), end = frac(interval.end)
                return end > start ? WaySpan(startFrac: start, endFrac: end, kind: kind) : nil
            }
        }
        return (spans(talking, kind: .talking) + spans(meditating, kind: .meditating))
            .sorted { $0.startFrac < $1.startFrac }
    }

    private static func strideSample(_ points: [WayPoint], target: Int) -> [WayPoint] {
        let step = Double(points.count - 1) / Double(target - 1)
        var result = (0..<(target - 1)).map { points[Int((Double($0) * step).rounded())] }
        result.append(points[points.count - 1])
        return result
    }
}
