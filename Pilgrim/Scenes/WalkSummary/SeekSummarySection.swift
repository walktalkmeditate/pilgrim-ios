import SwiftUI

/// The walk summary's seek story: which clearings were reached and which
/// signs (photos, voice notes, marks) belong to each. `nil` when the walk is
/// not a seek or no clearing was reached — zero-arrival seeks render the
/// standard summary untouched (plan Key Decision).
struct SeekSummaryData: Equatable {

    struct ClearingGroup: Equatable {
        let ordinal: Int
        let label: String
        let center: SeekPoint
        let arrivedAt: Date
        /// The sky's light at the arrival — golden hour, broad daylight,
        /// or night — computed from the sun's real elevation there and then.
        let foundUnder: SeekSkyLight.Daypart
        let photoIDs: [String]
        let voiceRecordingIDs: [String]
        let waypointIDs: [String]
    }

    struct AlongTheWay: Equatable {
        let photoIDs: [String]
        let voiceRecordingIDs: [String]
        let waypointIDs: [String]

        var isEmpty: Bool {
            photoIDs.isEmpty && voiceRecordingIDs.isEmpty && waypointIDs.isEmpty
        }
    }

    let groups: [ClearingGroup]
    let alongTheWay: AlongTheWay
    /// Counts only reached clearings — never totals, never "X of Y" (R19).
    let unknownsFoundText: String
}

enum SeekSummaryModel {

    /// Half the maximum region diameter (120 m) plus GPS slack, so a sign
    /// marked anywhere inside a clearing groups to it even when the fix
    /// wandered past the region edge.
    static let groupingRadiusMeters = 80.0

    /// Signs without any coordinate attribute to the preceding arrival only
    /// when marked within this window of the arrival itself.
    static let timestampFallbackWindow: TimeInterval = 5 * 60

    struct Arrival: Equatable {
        let label: String
        let center: SeekPoint
        let arrivedAt: Date
    }

    struct Sign: Equatable {
        enum Kind: Equatable {
            case photo, voiceRecording, waypoint
        }

        let kind: Kind
        let id: String
        let coordinate: SeekPoint?
        let timestamp: Date
    }

    static func isSeekWalk(events: [WalkEvent.EventType]) -> Bool {
        events.contains(.seekMode)
    }

    /// A sign exactly on the radius boundary belongs to the clearing.
    static func belongsToClearing(distanceMeters: Double) -> Bool {
        distanceMeters <= groupingRadiusMeters
    }

    static func summaryData(
        events: [WalkEvent.EventType],
        arrivals: [Arrival],
        signs: [Sign]
    ) -> SeekSummaryData? {
        guard isSeekWalk(events: events), !arrivals.isEmpty else { return nil }

        let ordered = arrivals.sorted { $0.arrivedAt < $1.arrivedAt }
        var grouped: [[Sign]] = Array(repeating: [], count: ordered.count)
        var strays: [Sign] = []

        for sign in signs {
            if let index = clearingIndex(for: sign, in: ordered) {
                grouped[index].append(sign)
            } else {
                strays.append(sign)
            }
        }

        let groups = ordered.enumerated().map { index, arrival in
            SeekSummaryData.ClearingGroup(
                ordinal: index + 1,
                label: arrival.label,
                center: arrival.center,
                arrivedAt: arrival.arrivedAt,
                foundUnder: foundUnderDaypart(center: arrival.center, arrivedAt: arrival.arrivedAt),
                photoIDs: ids(of: .photo, in: grouped[index]),
                voiceRecordingIDs: ids(of: .voiceRecording, in: grouped[index]),
                waypointIDs: ids(of: .waypoint, in: grouped[index])
            )
        }

        return SeekSummaryData(
            groups: groups,
            alongTheWay: SeekSummaryData.AlongTheWay(
                photoIDs: ids(of: .photo, in: strays),
                voiceRecordingIDs: ids(of: .voiceRecording, in: strays),
                waypointIDs: ids(of: .waypoint, in: strays)
            ),
            unknownsFoundText: unknownsFoundText(arrivalCount: ordered.count)
        )
    }

    /// The hour's light at an arrival, from the sun's real elevation at
    /// that place and moment. Shared by the summary captions and the
    /// summary map's halo tint.
    static func foundUnderDaypart(center: SeekPoint, arrivedAt: Date) -> SeekSkyLight.Daypart {
        SeekSkyLight.daypart(
            solarElevationDegrees: CelestialCalculator.solarElevationDegrees(
                at: center.coordinate, on: arrivedAt
            )
        )
    }

    static func unknownsFoundText(arrivalCount: Int) -> String {
        switch arrivalCount {
        case 1: return LS.seekSummaryFoundOne
        case 2: return LS.seekSummaryFoundTwo
        case 3: return LS.seekSummaryFoundThree
        default: return String(format: LS.seekSummaryFoundManyFormat, arrivalCount)
        }
    }

    private static func clearingIndex(for sign: Sign, in arrivals: [Arrival]) -> Int? {
        guard let coordinate = sign.coordinate else {
            return timestampFallbackIndex(for: sign.timestamp, in: arrivals)
        }
        guard let nearest = arrivals.enumerated().min(by: {
            SeekChainGenerator.distance(from: coordinate, to: $0.element.center)
                < SeekChainGenerator.distance(from: coordinate, to: $1.element.center)
        }) else { return nil }

        let distance = SeekChainGenerator.distance(from: coordinate, to: nearest.element.center)
        return belongsToClearing(distanceMeters: distance) ? nearest.offset : nil
    }

    private static func timestampFallbackIndex(for timestamp: Date, in arrivals: [Arrival]) -> Int? {
        guard let preceding = arrivals.lastIndex(where: { $0.arrivedAt <= timestamp }) else { return nil }
        let sinceArrival = timestamp.timeIntervalSince(arrivals[preceding].arrivedAt)
        return sinceArrival <= timestampFallbackWindow ? preceding : nil
    }

    private static func ids(of kind: Sign.Kind, in signs: [Sign]) -> [String] {
        signs.filter { $0.kind == kind }.map(\.id)
    }
}

// MARK: - Walk Adapter

extension SeekSummaryModel {

    /// Maps a stored walk onto plain model inputs. Coordinate support per
    /// sign type: photos carry their own capture fix (the matcher drops
    /// location-less photos), waypoints were marked at the walker's position,
    /// and voice recordings store no location — their coordinate resolves to
    /// the route sample nearest the recording start (the same rule that
    /// places their map pin), falling back to timestamp grouping when the
    /// walk has no route data.
    static func summaryData(for walk: WalkInterface) -> SeekSummaryData? {
        let events = walk.workoutEvents.map(\.eventType)
        guard isSeekWalk(events: events) else { return nil }

        let arrivals = walk.waypoints
            .filter(SeekPersistence.isArrivalWaypoint)
            .map { waypoint in
                Arrival(
                    label: waypoint.label,
                    center: SeekPoint(latitude: waypoint.latitude, longitude: waypoint.longitude),
                    arrivedAt: waypoint.timestamp
                )
            }

        let routeSamples = walk.routeData
        var signs: [Sign] = walk.walkPhotos.map { photo in
            Sign(
                kind: .photo,
                id: photo.localIdentifier,
                coordinate: SeekPoint(latitude: photo.capturedLat, longitude: photo.capturedLng),
                timestamp: photo.capturedAt
            )
        }
        signs += walk.voiceRecordings.map { recording in
            Sign(
                kind: .voiceRecording,
                id: recording.uuid?.uuidString ?? recording.fileRelativePath,
                coordinate: nearestRouteCoordinate(to: recording.startDate, in: routeSamples),
                timestamp: recording.startDate
            )
        }
        signs += walk.waypoints
            .filter { !SeekPersistence.isArrivalWaypoint($0) }
            .map { waypoint in
                Sign(
                    kind: .waypoint,
                    id: waypoint.uuid?.uuidString
                        ?? "\(waypoint.label)-\(waypoint.timestamp.timeIntervalSinceReferenceDate)",
                    coordinate: SeekPoint(latitude: waypoint.latitude, longitude: waypoint.longitude),
                    timestamp: waypoint.timestamp
                )
            }

        return summaryData(events: events, arrivals: arrivals, signs: signs)
    }

    private static func nearestRouteCoordinate(
        to date: Date,
        in samples: [RouteDataSampleInterface]
    ) -> SeekPoint? {
        samples
            .min { abs($0.timestamp.timeIntervalSince(date)) < abs($1.timestamp.timeIntervalSince(date)) }
            .map { SeekPoint(latitude: $0.latitude, longitude: $0.longitude) }
    }
}

// MARK: - View

struct SeekSummarySection: View {

    let data: SeekSummaryData

    private static let arrivalTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            header
            Text(data.unknownsFoundText)
                .font(Constants.Typography.body)
                .foregroundColor(.fog)
            ForEach(data.groups, id: \.ordinal) { group in
                clearingRow(group)
            }
            if !data.alongTheWay.isEmpty {
                alongTheWayRow
            }
        }
        .padding(Constants.UI.Padding.normal)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    private var header: some View {
        HStack {
            Image(systemName: SeekPersistence.arrivalWaypointIcon)
                .foregroundColor(.stone)
            Text(LS.seekSummaryHeader)
                .font(Constants.Typography.heading)
                .foregroundColor(.ink)
        }
    }

    private func clearingRow(_ group: SeekSummaryData.ClearingGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(group.label)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Spacer()
                Text(Self.arrivalTimeFormatter.string(from: group.arrivedAt))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
            Text(Self.foundUnderText(group.foundUnder))
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
            if let signs = signsLine(
                photos: group.photoIDs.count,
                voices: group.voiceRecordingIDs.count,
                marks: group.waypointIDs.count
            ) {
                Text(signs)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
        .padding(.top, Constants.UI.Padding.xs)
    }

    private var alongTheWayRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LS.seekSummaryAlongTheWay)
                .font(Constants.Typography.body)
                .foregroundColor(.ink)
            if let signs = signsLine(
                photos: data.alongTheWay.photoIDs.count,
                voices: data.alongTheWay.voiceRecordingIDs.count,
                marks: data.alongTheWay.waypointIDs.count
            ) {
                Text(signs)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
        .padding(.top, Constants.UI.Padding.xs)
    }

    static func foundUnderText(_ daypart: SeekSkyLight.Daypart) -> String {
        switch daypart {
        case .golden: return LS.seekSummaryFoundGolden
        case .midday: return LS.seekSummaryFoundMidday
        case .night: return LS.seekSummaryFoundNight
        }
    }

    private func signsLine(photos: Int, voices: Int, marks: Int) -> String? {
        var parts: [String] = []
        if photos == 1 {
            parts.append(LS.seekSummarySignPhotoOne)
        } else if photos > 1 {
            parts.append(String(format: LS.seekSummarySignPhotosFormat, photos))
        }
        if voices == 1 {
            parts.append(LS.seekSummarySignVoiceOne)
        } else if voices > 1 {
            parts.append(String(format: LS.seekSummarySignVoicesFormat, voices))
        }
        if marks == 1 {
            parts.append(LS.seekSummarySignMarkOne)
        } else if marks > 1 {
            parts.append(String(format: LS.seekSummarySignMarksFormat, marks))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
