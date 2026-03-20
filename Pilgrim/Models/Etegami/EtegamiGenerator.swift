import UIKit

enum EtegamiGenerator {

    static func generate(for walk: WalkInterface) -> UIImage {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: walk.startDate)
        let latitude = walk.routeData.first?.latitude ?? 0

        let season = SealTimeHelpers.season(for: walk.startDate, latitude: latitude)
        let timeOfDay = SealTimeHelpers.timeOfDay(for: hour)
        let (paperColor, inkColor) = colors(for: hour)

        let routePoints: [(lat: Double, lon: Double)] = walk.routeData.map {
            (lat: $0.latitude, lon: $0.longitude)
        }
        let altitudes = walk.routeData.map(\.altitude)

        let routeBounds = CGRect(x: 100, y: 200, width: 880, height: 900)
        let projectedPoints = EtegamiRouteStroke.projectRoute(routePoints, into: routeBounds)

        let activityMarkers = buildActivityMarkers(
            walk: walk, projectedPoints: projectedPoints
        )

        let sealImage = SealGenerator.generate(for: walk, size: 160)
        let sealPosition = CGPoint(x: 160, y: 1200)

        let primaryActivity = determinePrimaryActivity(walk: walk)
        let moonPhase: LunarPhase? = UserPreferences.celestialAwarenessEnabled.value
            ? LunarPhase.current(date: walk.startDate) : nil

        let haikuText = EtegamiTextGenerator.generate(
            intention: walk.comment,
            reflection: nil,
            season: season,
            timeOfDay: timeOfDay,
            durationMinutes: Int(walk.activeDuration / 60),
            moonPhaseName: moonPhase?.name,
            weatherCondition: walk.weatherCondition,
            primaryActivity: primaryActivity
        )

        let distanceKm = walk.distance / 1000
        let isImperial = UserPreferences.distanceMeasurementType.safeValue == .miles
        let distanceText = isImperial
            ? String(format: "%.1f mi", distanceKm * 0.621371)
            : String(format: "%.1f km", distanceKm)

        let durationMinutes = Int(walk.activeDuration / 60)
        let durationText = durationMinutes < 60
            ? "\(durationMinutes) min"
            : String(format: "%dh %dm", durationMinutes / 60, durationMinutes % 60)

        let elevationText: String? = walk.ascend > 1
            ? (isImperial
                ? String(format: "%.0fft \u{2191}", walk.ascend * 3.28084)
                : String(format: "%.0fm \u{2191}", walk.ascend))
            : nil

        let input = EtegamiRenderer.Input(
            routePoints: routePoints,
            altitudes: altitudes,
            activityMarkers: activityMarkers,
            sealImage: sealImage,
            sealPosition: sealPosition,
            haikuText: haikuText,
            moonPhase: moonPhase,
            timeOfDay: timeOfDay,
            inkColor: inkColor,
            paperColor: paperColor,
            distanceText: distanceText,
            durationText: durationText,
            elevationText: elevationText
        )

        return EtegamiRenderer.render(input: input)
    }

    // MARK: - Time-of-day palette

    private static func colors(for hour: Int) -> (paper: UIColor, ink: UIColor) {
        let standardInk = UIColor(hex: "#2C241E")
        switch hour {
        case 5...7:
            return (UIColor(hex: "#F5E6C8"), standardInk)
        case 8...10:
            return (UIColor(hex: "#F5F0E8"), standardInk)
        case 11...13:
            return (UIColor(hex: "#FAF8F3"), standardInk)
        case 14...16:
            return (UIColor(hex: "#F0E4C8"), standardInk)
        case 17...19:
            return (UIColor(hex: "#E8D0C0"), standardInk)
        default:
            return (UIColor(hex: "#1A1E2E"), UIColor(hex: "#D0C8B8"))
        }
    }

    // MARK: - Activity markers

    private static func buildActivityMarkers(
        walk: WalkInterface,
        projectedPoints: [CGPoint]
    ) -> [EtegamiRouteStroke.ActivityMarker] {
        let routeData = walk.routeData
        guard !routeData.isEmpty, !projectedPoints.isEmpty else { return [] }

        let timestamps = routeData.map(\.timestamp)
        let projected = projectedPoints

        var markers: [EtegamiRouteStroke.ActivityMarker] = []

        for interval in walk.activityIntervals where interval.activityType == .meditation {
            let midDate = Date(
                timeIntervalSince1970: (interval.startDate.timeIntervalSince1970
                    + interval.endDate.timeIntervalSince1970) / 2
            )
            if let idx = closestIndex(for: midDate, in: timestamps) {
                markers.append(.init(type: .meditation, position: projected[idx]))
            }
        }

        for recording in walk.voiceRecordings {
            if let idx = closestIndex(for: recording.startDate, in: timestamps) {
                markers.append(.init(type: .voice, position: projected[idx]))
            }
        }

        return markers
    }

    private static func closestIndex(for target: Date, in timestamps: [Date]) -> Int? {
        guard !timestamps.isEmpty else { return nil }
        let targetInterval = target.timeIntervalSince1970
        var bestIdx = 0
        var bestDelta = abs(timestamps[0].timeIntervalSince1970 - targetInterval)
        for i in 1..<timestamps.count {
            let delta = abs(timestamps[i].timeIntervalSince1970 - targetInterval)
            if delta < bestDelta {
                bestDelta = delta
                bestIdx = i
            }
        }
        return bestIdx
    }

    // MARK: - Primary activity

    private static func determinePrimaryActivity(
        walk: WalkInterface
    ) -> EtegamiTextGenerator.PrimaryActivity {
        let active = walk.activeDuration
        guard active > 0 else { return .walking }

        let meditateRatio = walk.meditateDuration / active
        let talkRatio = walk.talkDuration / active
        let threshold = 0.3

        if meditateRatio > talkRatio, meditateRatio > threshold {
            return .meditation
        } else if talkRatio > meditateRatio, talkRatio > threshold {
            return .voice
        }
        return .walking
    }

}
