import Foundation

/// What can go wrong on the way to a walkable route. Distinct from
/// `WayError` because each of these has its own line on screen.
enum PilgrimageError: Error, Equatable {
    case notWalkable
    case incomplete
    case diskFull
    case walkInProgress
    case catalogUnreachable
}

enum PilgrimageCopy {
    static func line(for error: PilgrimageError) -> String {
        switch error {
        case .notWalkable: return "this route isn't walkable yet"
        case .incomplete: return "the download didn't finish"
        case .diskFull: return HonorImportCopy.line(for: .failed(.diskFull)) ?? "not enough space on this phone"
        case .walkInProgress: return "finish your walk first"
        case .catalogUnreachable: return "the routes are out of reach right now"
        }
    }
}

struct PilgrimageRouteStage: Equatable {
    let index: Int
    let name: String
    let distanceKm: Double
    let gainMeters: Double
    let hours: WayStageHours
    let difficulty: String
}

struct PilgrimageRoute: Equatable {
    let id: String
    let name: String
    let names: [String: String]
    let country: String?
    let region: String?
    let distanceKm: Double
    let stageCount: Int
    let tradition: String?
    let summary: String?
    let stages: [PilgrimageRouteStage]
}

/// The sibling of `WayImporter` for the dataset's packaged stages: it decodes
/// the build's wire format and hands back the `Way` the engine already walks.
/// Every number is range-checked before any `Int(_:)` conversion and every
/// string capped, before anything reaches a view.
enum PilgrimageWayImporter {

    static let maxStageBytes = 2 * 1024 * 1024
    static let maxRouteBytes = 512 * 1024
    /// A town stage can carry over a hundred service points; four hundred is
    /// far past anything the dataset produces and still bounds the parse.
    static let maxMarks = 400
    static let maxThemeCharacters = 80
    static let maxNarrativeCharacters = 2_000
    static let maxClosingCharacters = 400
    static let maxWarningCharacters = 300
    static let maxStageNameCharacters = 120
    static let maxMarkNameCharacters = 80
    static let maxSummaryCharacters = 600
    static let maxWarnings = 20
    static let maxLocalNames = 20
    static let maxDistanceKm = 10_000.0
    static let maxStageCount = 200
    static let maxGainMeters = 30_000.0
    static let maxHours = 100.0

    // MARK: - Wire format

    private struct Coordinate: Decodable {
        let lat: Double
        let lon: Double
    }

    private struct StageFile: Decodable {
        struct Point: Decodable {
            let lat: Double
            let lon: Double
            let alt: Double?
            let t: Double
        }
        struct Moment: Decodable {
            let id: String
            let frac: Double
            let kind: String
            let label: String?
            let icon: String?
            let text: String?
            let names: [String: String]?
            let sitMinutes: Int?
            let at: Coordinate?
            let pin: Coordinate?
        }
        struct Mark: Decodable {
            let id: String
            let kind: String
            let name: String
            let at: Coordinate
            let frac: Double
            let offLineMeters: Double
        }
        struct Hours: Decodable {
            let min: Double
            let max: Double
        }
        struct Place: Decodable {
            let name: String
            let at: Coordinate
        }
        struct Stage: Decodable {
            let routeId: String
            let index: Int
            let count: Int
            let name: String
            let theme: String
            let narrative: String
            let closing: String
            let warnings: [String]
            let distanceKm: Double
            let gainMeters: Double
            let hours: Hours
            let difficulty: String
            let start: Place
            let end: Place
        }
        let id: String
        let title: String
        let departedAt: String
        let tzIdentifier: String?
        let route: [Point]
        let totalDistanceMeters: Double
        let theirActiveSeconds: Double
        let moments: [Moment]
        let marks: [Mark]
        let stage: Stage
    }

    private struct RouteFile: Decodable {
        struct Stage: Decodable {
            let index: Int
            let name: String
            let distanceKm: Double
            let gainMeters: Double
            let hours: StageFile.Hours
            let difficulty: String
        }
        let id: String
        let name: String
        let names: [String: String]?
        let country: String?
        let region: String?
        let distanceKm: Double
        let stageCount: Int
        let tradition: String?
        let summary: String?
        let stages: [Stage]
    }

    // MARK: - Stage

    static func way(from data: Data, routeId: String, stageIndex: Int) throws -> Way {
        guard WayStore.isValidRouteId(routeId), (0..<maxStageCount).contains(stageIndex) else {
            throw PilgrimageError.notWalkable
        }
        guard data.count <= maxStageBytes, let file = try? JSONDecoder().decode(StageFile.self, from: data) else {
            throw PilgrimageError.notWalkable
        }
        // The file must be the one that was asked for: a package is only ever
        // as trustworthy as the path it came from.
        let expectedId = WayStore.stageWayId(routeId: routeId, stageIndex: stageIndex)
        guard file.id == expectedId, file.stage.routeId == routeId, file.stage.index == stageIndex else {
            throw PilgrimageError.notWalkable
        }
        guard validate(file) else { throw PilgrimageError.notWalkable }
        guard let departed = WayImporter.isoDate(file.departedAt) else { throw PilgrimageError.notWalkable }

        let route = file.route.map { WayPoint(lat: $0.lat, lon: $0.lon, alt: $0.alt, t: $0.t) }
        let geometry = WayGeometry(route: route)
        guard geometry.totalMeters >= OwnWalkWayBuilder.minLengthMeters else { throw PilgrimageError.notWalkable }

        var way = Way(
            id: expectedId,
            source: .pilgrimage(routeId: routeId, stageIndex: stageIndex),
            title: capped(file.title, maxStageNameCharacters),
            departedAt: departed,
            tzIdentifier: file.tzIdentifier.map { capped($0, WayImporter.maxLabelCharacters) },
            expires: nil,
            route: route,
            totalDistanceMeters: geometry.totalMeters,
            theirActiveSeconds: file.theirActiveSeconds,
            moments: moments(from: file.moments),
            weather: nil)
        way.marks = marks(from: file.marks)
        way.stage = stage(from: file.stage)
        return way
    }

    /// Unknown moment kinds are skipped, like unknown encounter types in a
    /// share manifest; a stage that packaged only unknown kinds is a quiet
    /// stage, not a broken one.
    private static func moments(from raw: [StageFile.Moment]) -> [WayMoment] {
        var built: [WayMoment] = []
        for entry in raw where entry.kind == "waypoint" {
            var moment = WayMoment(
                id: capped(entry.id, WayImporter.maxLabelCharacters),
                frac: entry.frac,
                at: entry.at.map { WayCoordinate(lat: $0.lat, lon: $0.lon) },
                kind: .waypoint(label: capped(entry.label ?? "", WayImporter.maxLabelCharacters),
                                icon: capped(entry.icon ?? "mappin", WayImporter.maxIconCharacters)))
            moment.text = trimmed(entry.text, WayMoment.maxTranscriptCharacters)
            moment.names = localNames(entry.names)
            moment.sitMinutes = entry.sitMinutes
            moment.pin = entry.pin.map { WayCoordinate(lat: $0.lat, lon: $0.lon) }
            built.append(moment)
        }
        // A tiebreak on id keeps ordering deterministic when two moments
        // share a frac — the rule `WayImporter` and the tracker both sort by.
        return built.sorted { $0.frac == $1.frac ? $0.id < $1.id : $0.frac < $1.frac }
    }

    private static func marks(from raw: [StageFile.Mark]) -> [WayMark] {
        raw.compactMap { entry in
            guard let kind = WayMarkKind(rawValue: entry.kind) else { return nil }
            return WayMark(id: capped(entry.id, WayImporter.maxLabelCharacters), kind: kind,
                           name: capped(entry.name, maxMarkNameCharacters),
                           at: WayCoordinate(lat: entry.at.lat, lon: entry.at.lon),
                           frac: entry.frac, offLineMeters: entry.offLineMeters)
        }
    }

    private static func stage(from raw: StageFile.Stage) -> WayStage {
        WayStage(
            routeId: raw.routeId, index: raw.index, count: raw.count,
            name: capped(raw.name, maxStageNameCharacters),
            theme: capped(raw.theme, maxThemeCharacters),
            narrative: capped(raw.narrative, maxNarrativeCharacters),
            closing: capped(raw.closing, maxClosingCharacters),
            warnings: raw.warnings.prefix(maxWarnings).map { capped($0, maxWarningCharacters) },
            distanceKm: raw.distanceKm, gainMeters: raw.gainMeters,
            hours: WayStageHours(min: raw.hours.min, max: raw.hours.max),
            difficulty: capped(raw.difficulty, WayImporter.maxLabelCharacters),
            start: WayStagePlace(name: capped(raw.start.name, maxStageNameCharacters),
                                 at: WayCoordinate(lat: raw.start.at.lat, lon: raw.start.at.lon)),
            end: WayStagePlace(name: capped(raw.end.name, maxStageNameCharacters),
                               at: WayCoordinate(lat: raw.end.at.lat, lon: raw.end.at.lon)))
    }

    // MARK: - Route

    static func route(from data: Data) throws -> PilgrimageRoute {
        guard data.count <= maxRouteBytes, let file = try? JSONDecoder().decode(RouteFile.self, from: data) else {
            throw PilgrimageError.notWalkable
        }
        guard WayStore.isValidRouteId(file.id),
              isSaneDistance(file.distanceKm),
              (1...maxStageCount).contains(file.stageCount),
              file.stages.count <= maxStageCount,
              file.stages.allSatisfy(isSaneStageRow) else { throw PilgrimageError.notWalkable }
        // The manager saves each stage positionally — download loop index 0,
        // 1, 2… becomes the Way at that same stage index — and the route
        // screen keys a tapped row on this file's own `index`. Anything but
        // the exact run 0..<count (1-based, a duplicate, a gap) would hand a
        // tapped row a different stage than the one saved at that position.
        guard file.stages.map(\.index).sorted() == Array(0..<file.stages.count) else {
            throw PilgrimageError.notWalkable
        }
        return PilgrimageRoute(
            id: file.id,
            name: capped(file.name, maxStageNameCharacters),
            names: localNames(file.names) ?? [:],
            country: file.country.map { capped($0, WayImporter.maxLabelCharacters) },
            region: file.region.map { capped($0, WayImporter.maxLabelCharacters) },
            distanceKm: file.distanceKm,
            stageCount: file.stageCount,
            tradition: file.tradition.map { capped($0, WayImporter.maxLabelCharacters) },
            summary: trimmed(file.summary, maxSummaryCharacters),
            stages: file.stages
                .sorted { $0.index < $1.index }
                .map { PilgrimageRouteStage(index: $0.index, name: capped($0.name, maxStageNameCharacters),
                                            distanceKm: $0.distanceKm, gainMeters: $0.gainMeters,
                                            hours: WayStageHours(min: $0.hours.min, max: $0.hours.max),
                                            difficulty: capped($0.difficulty, WayImporter.maxLabelCharacters)) })
    }

    private static func isSaneStageRow(_ row: RouteFile.Stage) -> Bool {
        (0..<maxStageCount).contains(row.index)
            && isSaneDistance(row.distanceKm)
            && isSaneGain(row.gainMeters)
            && isSaneHours(row.hours)
    }

    // MARK: - Validation

    /// The whole stage file, checked before a single value is converted or
    /// shown. `Int(_:)` traps on an out-of-range or non-finite `Double`, so
    /// finiteness is checked everywhere a number can reach a formatter.
    private static func validate(_ file: StageFile) -> Bool {
        func inLat(_ v: Double) -> Bool { v.isFinite && (-90...90).contains(v) }
        func inLon(_ v: Double) -> Bool { v.isFinite && (-180...180).contains(v) }
        func inFrac(_ v: Double) -> Bool { v.isFinite && (0...1).contains(v) }

        guard file.route.count >= 2, file.route.count <= WayImporter.maxRoutePoints,
              file.moments.count <= WayImporter.maxEncounters,
              file.marks.count <= maxMarks else { return false }
        guard file.route.allSatisfy({ point in
            inLat(point.lat) && inLon(point.lon) && point.t.isFinite && (0...WayImporter.maxActiveDurationSeconds).contains(point.t)
                && (point.alt.map { $0.isFinite && abs($0) < WayImporter.maxAltitudeMeters } ?? true)
        }) else { return false }
        for i in file.route.indices.dropFirst() where file.route[i].t < file.route[i - 1].t { return false }
        guard file.totalDistanceMeters.isFinite, file.totalDistanceMeters >= 0,
              file.theirActiveSeconds.isFinite,
              (0...WayImporter.maxActiveDurationSeconds).contains(file.theirActiveSeconds) else { return false }

        for moment in file.moments {
            guard inFrac(moment.frac) else { return false }
            if let at = moment.at, !(inLat(at.lat) && inLon(at.lon)) { return false }
            if let pin = moment.pin, !(inLat(pin.lat) && inLon(pin.lon)) { return false }
            if let minutes = moment.sitMinutes, !(0...WayImporter.maxRestMinutes).contains(minutes) { return false }
        }
        for mark in file.marks {
            guard inFrac(mark.frac), inLat(mark.at.lat), inLon(mark.at.lon),
                  mark.offLineMeters.isFinite, (0...100_000).contains(mark.offLineMeters) else { return false }
        }

        let stage = file.stage
        guard (0..<maxStageCount).contains(stage.index),
              (1...maxStageCount).contains(stage.count),
              stage.index < stage.count,
              isSaneDistance(stage.distanceKm), isSaneGain(stage.gainMeters), isSaneHours(stage.hours),
              stage.warnings.count <= maxWarnings,
              inLat(stage.start.at.lat), inLon(stage.start.at.lon),
              inLat(stage.end.at.lat), inLon(stage.end.at.lon) else { return false }
        return true
    }

    private static func isSaneDistance(_ km: Double) -> Bool { km.isFinite && (0...maxDistanceKm).contains(km) }
    private static func isSaneGain(_ meters: Double) -> Bool { meters.isFinite && (0...maxGainMeters).contains(meters) }
    private static func isSaneHours(_ hours: StageFile.Hours) -> Bool {
        hours.min.isFinite && hours.max.isFinite
            && (0...maxHours).contains(hours.min) && (0...maxHours).contains(hours.max) && hours.max >= hours.min
    }

    // MARK: - Strings

    private static func capped(_ value: String, _ max: Int) -> String { String(value.prefix(max)) }

    private static func trimmed(_ raw: String?, _ max: Int) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return String(trimmed.prefix(max))
    }

    /// Language codes come from an untrusted file and end up as dictionary
    /// keys a card reads; both halves are bounded and the map itself capped.
    private static func localNames(_ raw: [String: String]?) -> [String: String]? {
        guard let raw, !raw.isEmpty else { return nil }
        let pairs = raw.sorted { $0.key < $1.key }.prefix(maxLocalNames).compactMap { key, value -> (String, String)? in
            guard key.range(of: "\\A[a-z]{2,3}\\z", options: .regularExpression) != nil else { return nil }
            guard let name = trimmed(value, maxStageNameCharacters) else { return nil }
            return (key, name)
        }
        return pairs.isEmpty ? nil : Dictionary(uniqueKeysWithValues: pairs)
    }
}
