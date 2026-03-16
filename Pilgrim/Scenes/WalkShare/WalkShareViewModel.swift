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
    }

    enum ShareState: Equatable {
        case idle
        case uploading
        case success(url: String)
        case error(message: String)
    }

    var expiryDate: Date {
        Calendar.current.date(
            byAdding: .day,
            value: selectedExpiry.rawValue,
            to: Date()
        ) ?? Date()
    }

    var hasExistingShare: Bool {
        guard let uuid = walk.uuid else { return false }
        return ShareService.cachedShare(for: uuid) != nil
    }

    init(walk: WalkInterface) {
        self.walk = walk
        if let uuid = walk.uuid, let cached = ShareService.cachedShare(for: uuid) {
            shareState = .success(url: cached.url)
        }
    }

    func share() async {
        shareState = .uploading

        let placeNames = await geocodeEndpoints()
        let payload = buildPayload(placeStart: placeNames.start, placeEnd: placeNames.end)

        do {
            let result = try await ShareService.share(payload: payload)
            if let uuid = walk.uuid {
                ShareService.cacheShare(result, walkID: uuid, expiryDays: selectedExpiry.rawValue)
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
            distance: toggleDistance ? walk.distance : nil,
            activeDuration: toggleDuration ? walk.activeDuration : nil,
            elevationAscent: toggleElevation ? walk.ascend : nil,
            elevationDescent: toggleElevation ? walk.descend : nil,
            steps: toggleSteps ? walk.steps : nil,
            meditateDuration: toggleActivityBreakdown ? walk.meditateDuration : nil,
            talkDuration: toggleActivityBreakdown ? walk.talkDuration : nil
        )

        let formatter = ISO8601DateFormatter()

        return SharePayload(
            stats: stats,
            route: downsampled,
            activityIntervals: intervals,
            journal: journal.isEmpty ? nil : journal,
            expiryDays: selectedExpiry.rawValue,
            units: isMetric ? "metric" : "imperial",
            startDate: formatter.string(from: walk.startDate),
            toggledStats: toggledStats,
            placeStart: placeStart,
            placeEnd: placeEnd
        )
    }
}
