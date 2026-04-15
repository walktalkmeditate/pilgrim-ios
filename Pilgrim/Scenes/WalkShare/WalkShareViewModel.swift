import Foundation
import CoreLocation

@MainActor
final class WalkShareViewModel: ObservableObject {

    let walk: WalkInterface

    @Published var toggleDistance = true
    @Published var toggleDuration = true
    @Published var toggleElevation = true
    @Published var toggleActivityBreakdown = true
    @Published var toggleSteps = false

    @Published var journal = ""
    @Published var selectedExpiry: ExpiryOption = .season

    @Published var shareState: ShareState = .idle
    private var cachedExpiryDate: Date?

    enum ExpiryOption: Int, CaseIterable {
        case moon = 30
        case season = 90
        case cycle = 365

        var label: String {
            switch self {
            case .moon: return "1 moon"
            case .season: return "1 season"
            case .cycle: return "1 cycle"
            }
        }

        var kanji: String {
            switch self {
            case .moon: return "\u{6708}"
            case .season: return "\u{5B63}"
            case .cycle: return "\u{5DE1}"
            }
        }

        var cacheKey: String {
            switch self {
            case .moon: return "moon"
            case .season: return "season"
            case .cycle: return "cycle"
            }
        }
    }

    enum ShareState: Equatable {
        case idle
        case uploading
        case success(url: String)
        case error(message: String)
    }

    var expiryDate: Date {
        cachedExpiryDate ?? Calendar.current.date(
            byAdding: .day,
            value: selectedExpiry.rawValue,
            to: Date()
        ) ?? Date()
    }

    var hasExistingShare: Bool {
        guard let uuid = walk.uuid else { return false }
        guard let cached = ShareService.cachedShare(for: uuid) else { return false }
        return !cached.isExpired
    }

    var formattedDistance: String? {
        guard walk.distance > 0 else { return nil }
        let isMetric = UserPreferences.distanceMeasurementType.safeValue == .kilometers
        if isMetric {
            return String(format: "%.1f km", walk.distance / 1000)
        }
        return String(format: "%.1f mi", walk.distance / 1609.344)
    }

    var formattedDuration: String? {
        guard walk.activeDuration > 0 else { return nil }
        let h = Int(walk.activeDuration) / 3600
        let m = (Int(walk.activeDuration) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    var formattedElevation: String? {
        guard walk.ascend > 1 else { return nil }
        let isMetric = UserPreferences.altitudeMeasurementType.safeValue == .meters
        if isMetric {
            return "\(Int(walk.ascend)) m"
        }
        return "\(Int(walk.ascend * 3.28084)) ft"
    }

    var formattedActivityBreakdown: String? {
        let parts = [
            walk.meditateDuration > 0 ? "\(Int(walk.meditateDuration / 60))m meditation" : nil,
            walk.talkDuration > 0 ? "\(Int(walk.talkDuration / 60))m reflection" : nil,
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var formattedSteps: String? {
        guard let steps = walk.steps, steps > 0 else { return nil }
        return "\(steps.formatted())"
    }

    init(walk: WalkInterface) {
        self.walk = walk
        if let uuid = walk.uuid, let cached = ShareService.cachedShare(for: uuid), !cached.isExpired {
            shareState = .success(url: cached.url)
            cachedExpiryDate = cached.expiry
        }
    }

    func share() async {
        shareState = .uploading

        let placeNames = await geocodeEndpoints()
        let payload = buildPayload(placeStart: placeNames.start, placeEnd: placeNames.end)

        do {
            let result = try await ShareService.share(payload: payload)
            if let uuid = walk.uuid {
                ShareService.cacheShare(result, walkID: uuid, expiryDays: selectedExpiry.rawValue, expiryOption: selectedExpiry.cacheKey)
            }
            shareState = .success(url: result.url)
        } catch {
            shareState = .error(message: error.localizedDescription)
        }
    }

    private func geocodeEndpoints() async -> (start: String?, end: String?) {
        let routeData = walk.routeData
        guard let first = routeData.first, let last = routeData.last else {
            return (nil, nil)
        }

        let startLoc = CLLocation(latitude: first.latitude, longitude: first.longitude)
        let endLoc = CLLocation(latitude: last.latitude, longitude: last.longitude)

        async let startName = geocodeSingle(geocoder: CLGeocoder(), location: startLoc)
        async let endName = geocodeSingle(geocoder: CLGeocoder(), location: endLoc)

        let (s, e) = await (startName, endName)
        if s != nil && e != nil && s == e { return (s, nil) }
        return (s, e)
    }

    private func geocodeSingle(geocoder: CLGeocoder, location: CLLocation) async -> String? {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first?.locality ?? placemarks.first?.subLocality ?? placemarks.first?.name
        } catch {
            return nil
        }
    }

    private func buildPayload(placeStart: String?, placeEnd: String?) -> SharePayload {
        let isMetric = UserPreferences.distanceMeasurementType.safeValue == .kilometers

        let routePoints = walk.routeData.map { sample in
            SharePayload.RoutePoint(
                lat: sample.latitude,
                lon: sample.longitude,
                alt: sample.altitude,
                ts: Int(sample.timestamp.timeIntervalSince1970)
            )
        }

        let downsampled = RouteDownsampler.downsample(routePoints)

        var intervals: [SharePayload.ActivityIntervalPayload] = []

        for interval in walk.activityIntervals where interval.activityType == .meditation {
            intervals.append(SharePayload.ActivityIntervalPayload(
                type: "meditation",
                startTs: Int(interval.startDate.timeIntervalSince1970),
                endTs: Int(interval.endDate.timeIntervalSince1970)
            ))
        }

        for recording in walk.voiceRecordings {
            intervals.append(SharePayload.ActivityIntervalPayload(
                type: "talk",
                startTs: Int(recording.startDate.timeIntervalSince1970),
                endTs: Int(recording.endDate.timeIntervalSince1970)
            ))
        }

        var toggledStats: [String] = []
        if toggleDistance { toggledStats.append("distance") }
        if toggleDuration { toggledStats.append("duration") }
        if toggleElevation { toggledStats.append("elevation") }
        if toggleActivityBreakdown { toggledStats.append("activity_breakdown") }
        if toggleSteps { toggledStats.append("steps") }

        let stats = SharePayload.Stats(
            distance: walk.distance,
            activeDuration: walk.activeDuration,
            elevationAscent: toggleElevation ? walk.ascend : nil,
            elevationDescent: toggleElevation ? walk.descend : nil,
            steps: toggleSteps ? walk.steps : nil,
            meditateDuration: walk.meditateDuration,
            talkDuration: walk.talkDuration,
            weatherCondition: walk.weatherCondition,
            weatherTemperature: walk.weatherTemperature
        )

        let markValue: String? = {
            guard let faviconStr = walk.favicon, let fav = WalkFavicon(rawValue: faviconStr) else { return nil }
            switch fav {
            case .flame: return "transformative"
            case .leaf:  return "peaceful"
            case .star:  return "extraordinary"
            }
        }()

        let formatter = ISO8601DateFormatter()

        return SharePayload(
            stats: stats,
            route: downsampled,
            activityIntervals: intervals,
            journal: journal.isEmpty ? nil : journal,
            expiryDays: selectedExpiry.rawValue,
            units: isMetric ? "metric" : "imperial",
            startDate: formatter.string(from: walk.startDate),
            tzIdentifier: TimeZone.current.identifier,
            toggledStats: toggledStats,
            placeStart: placeStart,
            placeEnd: placeEnd,
            mark: markValue
        )
    }
}
