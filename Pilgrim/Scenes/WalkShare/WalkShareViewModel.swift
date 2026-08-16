import Foundation
import CoreLocation
import Photos

@MainActor
final class WalkShareViewModel: ObservableObject {

    let walk: WalkInterface
    let pinnedPhotos: [PhotoCandidate]

    @Published var toggleDistance = true
    @Published var toggleDuration = true
    @Published var toggleElevation = true
    @Published var toggleActivityBreakdown = true
    @Published var toggleSteps = false
    @Published var includeWaypoints = false
    @Published var includePhotos = false

    var waypointCount: Int { walk.waypoints.count }
    var hasWaypoints: Bool { waypointCount > 0 }

    /// Injected rather than read straight off `PermissionManager.standard` (defaults to the real check): the OS permission prompt can't be driven from a unit test, so `prepareInteractive()`'s auto-enable-once branch needs a seam a test can force true or false deterministically.
    private let isPhotosGranted: () -> Bool

    var pinnedPhotoCount: Int { pinnedPhotos.count }
    var hasPinnedPhotos: Bool {
        pinnedPhotoCount > 0
            && UserPreferences.walkReliquaryEnabled.value
            && isPhotosGranted()
    }

    @Published var interactiveEnabled = false
    @Published var tourCandidates: [TourRecordingCandidate] = []
    @Published var trimEnabled = true

    static let trimMeters = 150

    var hasRecordings: Bool { !tourCandidates.isEmpty }

    var tourValidationError: String? {
        interactiveEnabled ? TourBuilder.validationError(for: tourCandidates) : nil
    }

    /// Gates the Share button: an over-cap tour must be trimmed before POSTing, never silently clipped.
    var canShare: Bool { tourValidationError == nil }

    var tourTotalsLabel: String {
        let (count, bytes, seconds) = TourBuilder.totals(of: tourCandidates)
        let photoCount = includePhotos ? interactivePhotoExportList().count : 0
        var parts: [String] = []
        if count > 0 {
            let mb = Double(bytes) / 1_048_576
            parts.append("\(count) recording\(count == 1 ? "" : "s") · \(String(format: "%.1f", mb)) MB · \(Int(seconds / 60)) min")
        }
        if photoCount > 0 {
            parts.append("\(photoCount) hi-res photo\(photoCount == 1 ? "" : "s")")
        }
        return parts.isEmpty ? "no recordings included" : parts.joined(separator: " · ")
    }

    /// Judges trim against the same points `computeInteractiveRoute()` would actually hand `RouteTrimmer.trim` — both read `downsampledRoutePoints()` so a route long enough to trim can never disagree with a route the UI was told could be trimmed.
    var canTrimRoute: Bool {
        RouteTrimmer.canTrim(downsampledRoutePoints(), meters: Double(Self.trimMeters))
    }

    private var didAutoEnablePhotos = false

    @Published var journal = ""
    @Published var selectedExpiry: ExpiryOption = .season

    @Published var shareState: ShareState = .idle
    /// Set when `retryFailedMedia()` can't re-identify any cached failure against current data — `.partial` still holds, but `ShareStatusSection` swaps the retry button for an explanation. Reset at the top of both `share()` and `retryFailedMedia()`. Not `private(set)`: both live in the orchestration extension file, and Swift's private access is file-scoped, not type-scoped — same reason `shareState` above is unrestricted.
    @Published var repairUnavailable = false
    /// Owns the in-flight `share()`/`completeShare()` attempt — nil whenever nothing is running, so `beginShare()` can guard a double-tap and `cancelShare()` has something to cancel. Not `@Published` (nothing renders off it directly) and not `private`, same file-scoped-access reasoning as `shareState` above.
    var shareTask: Task<Void, Never>?
    /// Photos already exported when `.photosDropped` paused the share for consent — "Share without them" resumes with these, "Don't share yet" discards them. Same access reasoning as `shareTask`.
    var pendingTourPhotos: [TourPhoto] = []
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
        case preparingPhotos(completed: Int, total: Int) // hi-res export (pre-POST)
        case photosDropped(prepared: Int, dropped: Int)  // export done short; pre-POST consent pause
        case uploading                                   // POST phase
        case uploadingMedia(completed: Int, total: Int)  // PUT phase
        case success(url: String)
        case partial(url: String, failedCount: Int)      // page live, some media missing
        case error(message: String)
    }

    /// VM-level source of truth for "this walk has a live page" — `.partial`
    /// counts the same as `.success`. Exists so the distinction is testable
    /// without SwiftUI (the view mirrors this locally).
    var isShared: Bool {
        switch shareState {
        case .success, .partial: return true
        default: return false
        }
    }

    var expiryDate: Date {
        cachedExpiryDate ?? Calendar.current.date(
            byAdding: .day,
            value: selectedExpiry.rawValue,
            to: Date()
        ) ?? Date()
    }

    /// Shared by both the pre-share expiry picker and the post-share card so "Expires..." and "Returns to the trail on..." always agree.
    var formattedExpiry: String {
        Self.expiryFormatter.string(from: expiryDate)
    }

    private static let expiryFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        return f
    }()

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
            walk.talkDuration > 0 ? "\(Int(walk.talkDuration / 60))m reflection" : nil
        ].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    var formattedSteps: String? {
        guard let steps = walk.steps, steps > 0 else { return nil }
        return "\(steps.formatted())"
    }

    init(
        walk: WalkInterface,
        pinnedPhotos: [PhotoCandidate] = [],
        isPhotosGranted: @escaping () -> Bool = { PermissionManager.standard.isPhotosGranted }
    ) {
        self.walk = walk
        self.pinnedPhotos = pinnedPhotos
        self.isPhotosGranted = isPhotosGranted
        if let uuid = walk.uuid, let cached = ShareService.cachedShare(for: uuid), !cached.isExpired {
            cachedExpiryDate = cached.expiry
            // A share with un-landed media PUTs still has a live page —
            // restore .partial so "Carry the missing files" survives
            // leaving and returning here, not a quiet .success.
            let failedCount = ShareService.failedMedia(for: uuid).count
            shareState = failedCount > 0
                ? .partial(url: cached.url, failedCount: failedCount)
                : .success(url: cached.url)
        }
    }

    // share(), retryFailedMedia(), and their private helpers live in WalkShareViewModel+ShareOrchestration.swift.

    func prepareInteractive() {
        if tourCandidates.isEmpty {
            tourCandidates = TourBuilder.candidates(for: walk)
        }
        // Interactive means "carry the media": the first enable brings photos
        // along automatically (the spec's auto-enable); the walker can still
        // switch them off afterwards and we never re-flip.
        if hasPinnedPhotos && !didAutoEnablePhotos {
            didAutoEnablePhotos = true
            includePhotos = true
        }
    }

    func toggleInclude(candidateID: Int) {
        guard let i = tourCandidates.firstIndex(where: { $0.id == candidateID }),
              tourCandidates[i].unavailableReason == nil else { return }
        tourCandidates[i].includeInShare.toggle()
    }

    func flipKind(candidateID: Int) {
        guard let i = tourCandidates.firstIndex(where: { $0.id == candidateID }) else { return }
        let current = tourCandidates[i].effectiveKind
        let flipped: TourRecordingKind = current == .spoken ? .ambient : .spoken
        tourCandidates[i].kindOverride = flipped == tourCandidates[i].autoKind ? nil : flipped
    }

    /// Task 8's `share()` must filter `pinnedPhotos` to this same window before exporting hi-res
    /// bytes — otherwise the export, the declared photo metadata, and the trimmed route would each tell a different story about which photos belong to the shared page.
    func interactiveKeptWindow() -> ClosedRange<Int>? {
        computeInteractiveRoute().keptWindow
    }

    // Called from WalkShareViewModel+ShareOrchestration.swift's `share()`.
    func geocodeEndpoints() async -> (start: String?, end: String?) {
        guard let anchors = geocodeAnchorPoints() else { return (nil, nil) }

        let startLoc = CLLocation(latitude: anchors.start.lat, longitude: anchors.start.lon)
        let endLoc = CLLocation(latitude: anchors.end.lat, longitude: anchors.end.lon)

        async let startName = geocodeSingle(geocoder: CLGeocoder(), location: startLoc)
        async let endName = geocodeSingle(geocoder: CLGeocoder(), location: endLoc)

        let (s, e) = await (startName, endName)
        if s != nil && e != nil && s == e { return (s, nil) }
        return (s, e)
    }

    /// The coordinates `geocodeEndpoints()` reverse-geocodes: the shipped, post-trim route when interactive, the walk's raw route ends otherwise.
    func geocodeAnchorPoints() -> (start: SharePayload.RoutePoint, end: SharePayload.RoutePoint)? {
        if interactiveEnabled {
            let route = computeInteractiveRoute().route
            guard let first = route.first, let last = route.last else { return nil }
            return (first, last)
        }
        guard let first = walk.routeData.first, let last = walk.routeData.last else { return nil }
        return (routePoint(first), routePoint(last))
    }

    /// Loads a pinned photo as a low-res base64 JPEG for the share
    /// payload. Synchronous (blocks main ~10-50ms per local photo).
    /// Returns nil for deleted or iCloud-only photos, which are
    /// silently dropped from the share.
    private static func loadSharePhoto(
        localIdentifier: String,
        lat: Double,
        lon: Double,
        capturedAt: Date
    ) -> SharePayload.Photo? {
        let fetchResult = PHAsset.fetchAssets(
            withLocalIdentifiers: [localIdentifier],
            options: nil
        )
        guard let asset = fetchResult.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = false
        options.isSynchronous = true
        options.resizeMode = .exact

        let targetSize = CGSize(width: 600, height: 600)

        var result: SharePayload.Photo?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: targetSize,
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            guard let image = image,
                  let jpegData = image.jpegData(compressionQuality: 0.5) else { return }
            let base64 = jpegData.base64EncodedString()
            result = SharePayload.Photo(
                lat: lat,
                lon: lon,
                ts: Int(capturedAt.timeIntervalSince1970),
                data: base64
            )
        }
        return result
    }

    private func geocodeSingle(geocoder: CLGeocoder, location: CLLocation) async -> String? {
        do {
            let placemarks = try await geocoder.reverseGeocodeLocation(location)
            return placemarks.first?.locality ?? placemarks.first?.subLocality ?? placemarks.first?.name
        } catch {
            return nil
        }
    }

    func buildPayload(placeStart: String?, placeEnd: String?, tourPhotoMeta: [SharePayload.Photo] = []) -> SharePayload {
        let isMetric = UserPreferences.distanceMeasurementType.safeValue == .kilometers
        let interactive = interactiveEnabled
        let (finalRoute, trimM, keptWindow) = computeInteractiveRoute()

        var intervals: [SharePayload.ActivityIntervalPayload] = []

        for interval in walk.activityIntervals where interval.activityType == .meditation {
            intervals.append(SharePayload.ActivityIntervalPayload(
                type: "meditation",
                startTs: Int(interval.startDate.timeIntervalSince1970),
                endTs: Int(interval.endDate.timeIntervalSince1970)
            ))
        }

        // Consent follows the checkbox: an excluded recording leaves no trace — no talk interval, no rust on the route, no minutes in the total.
        let includedTalkCandidates = tourCandidates.filter { $0.includeInShare && $0.unavailableReason == nil }
        let talkIntervals: [SharePayload.ActivityIntervalPayload] = interactive
            ? includedTalkCandidates.map { SharePayload.ActivityIntervalPayload(type: "talk", startTs: $0.startTs, endTs: $0.endTs) }
            : walk.voiceRecordings.map { SharePayload.ActivityIntervalPayload(type: "talk", startTs: Int($0.startDate.timeIntervalSince1970), endTs: Int($0.endDate.timeIntervalSince1970)) }
        intervals.append(contentsOf: talkIntervals)

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
            // Recordings outrun active time by design (a talk can run through a pause); NewWalk clamps talkDuration to activeDuration for the same reason, and the worker 400s on meditate+talk > active — clamp the included-candidate sum the same way.
            talkDuration: interactive ? min(includedTalkCandidates.reduce(0) { $0 + $1.duration }, walk.talkDuration) : walk.talkDuration,
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

        var payload = SharePayload(
            stats: stats,
            route: finalRoute,
            activityIntervals: intervals,
            journal: journal.isEmpty ? nil : journal,
            expiryDays: selectedExpiry.rawValue,
            units: isMetric ? "metric" : "imperial",
            startDate: formatter.string(from: walk.startDate),
            tzIdentifier: TimeZone.current.identifier,
            toggledStats: toggledStats,
            placeStart: placeStart,
            placeEnd: placeEnd,
            mark: markValue,
            waypoints: waypointPayload(keptWindow: keptWindow),
            photos: photoPayload(interactive: interactive, tourPhotoMeta: tourPhotoMeta)
        )
        if interactive {
            applyInteractiveTourAndPauses(to: &payload, trimM: trimM)
        }
        payload.turningDay = turningDayCode()
        return payload
    }

    /// Test-only passthrough so specs can build a payload without geocoding.
    func testBuildPayload(tourPhotoMeta: [SharePayload.Photo] = []) -> SharePayload {
        buildPayload(placeStart: nil, placeEnd: nil, tourPhotoMeta: tourPhotoMeta)
    }

    private func waypointPayload(keptWindow: ClosedRange<Int>?) -> [SharePayload.Waypoint]? {
        guard includeWaypoints, hasWaypoints else { return nil }
        return walk.waypoints
            .filter { wp in keptWindow.map { $0.contains(Int(wp.timestamp.timeIntervalSince1970)) } ?? true }
            .map { wp in
                SharePayload.Waypoint(
                    lat: wp.latitude,
                    lon: wp.longitude,
                    label: wp.label,
                    icon: wp.icon,
                    ts: Int(wp.timestamp.timeIntervalSince1970)
                )
            }
    }

    private func photoPayload(interactive: Bool, tourPhotoMeta: [SharePayload.Photo]) -> [SharePayload.Photo]? {
        guard includePhotos, hasPinnedPhotos else { return nil }
        if interactive {
            // Metadata comes ONLY from the export (same array, same order), so
            // declared photo n always matches the uploaded file n. Never map
            // pinnedPhotos here — a failed export would orphan map markers.
            return tourPhotoMeta.isEmpty ? nil : tourPhotoMeta
        }
        return pinnedPhotos.compactMap { photo in
            Self.loadSharePhoto(
                localIdentifier: photo.localIdentifier,
                lat: photo.capturedLat,
                lon: photo.capturedLng,
                capturedAt: photo.capturedAt
            )
        }
    }

    private func applyInteractiveTourAndPauses(to payload: inout SharePayload, trimM: Int) {
        payload.tour = TourBuilder.tourItems(
            candidates: tourCandidates,
            trimM: trimM,
            soundscapeUrl: TourBuilder.soundscapeUrl(
                selectedId: UserPreferences.selectedSoundscapeId.value,
                manifest: AudioManifestService.shared.manifest
            )
        ).tour
        // The worker validates TRUNCATED integers: filter after truncation or a
        // sub-second pause 400s the whole share.
        payload.pauses = Array(
            walk.pauses
                .map { (start: Int($0.startDate.timeIntervalSince1970), end: Int($0.endDate.timeIntervalSince1970)) }
                .filter { $0.end > $0.start }
                .prefix(200)
        ).map { SharePayload.Pause(startTs: $0.start, endTs: $0.end) }
    }

    /// Shared by `canTrimRoute` and `computeInteractiveRoute()` so the route
    /// judged for trimmability and the route actually trimmed can never be
    /// two different arrays — the same divergence class Task 3 closed for
    /// `RouteTrimmer.canTrim`/`.trim` themselves.
    private func downsampledRoutePoints() -> [SharePayload.RoutePoint] {
        RouteDownsampler.downsample(walk.routeData.map(routePoint))
    }

    /// The `RouteDataSampleInterface` → `SharePayload.RoutePoint` field mapping shared by `downsampledRoutePoints()` and `geocodeAnchorPoints()`'s classic branch.
    private func routePoint(_ sample: RouteDataSampleInterface) -> SharePayload.RoutePoint {
        SharePayload.RoutePoint(lat: sample.latitude, lon: sample.longitude, alt: sample.altitude, ts: Int(sample.timestamp.timeIntervalSince1970))
    }

    /// Single source of truth for the trimmed route: `buildPayload` and `interactiveKeptWindow()`
    /// must never compute this independently, or the payload's route and the filter window could drift apart.
    private func computeInteractiveRoute() -> (route: [SharePayload.RoutePoint], trimM: Int, keptWindow: ClosedRange<Int>?) {
        let downsampled = downsampledRoutePoints()
        guard interactiveEnabled && trimEnabled else { return (downsampled, 0, nil) }

        // Report the trim by OUTCOME, not intent: RouteTrimmer silently no-ops on a route too short to trim, so trimM/keptWindow must reflect what actually happened — never claim a 150m trim while shipping the full, untrimmed route.
        let trimmed = RouteTrimmer.trim(downsampled, meters: Double(Self.trimMeters))
        let didTrim = trimmed.count < downsampled.count
        let trimM = didTrim ? Self.trimMeters : 0
        // Trim's promise covers everything with a coordinate: waypoints and photo metadata outside the kept route window are excluded too — a doorstep photo must not pin the doorstep trim just hid.
        let keptWindow: ClosedRange<Int>? = (didTrim && trimmed.count >= 2)
            ? trimmed.first!.ts...trimmed.last!.ts
            : nil
        return (trimmed, trimM, keptWindow)
    }

    private func turningDayCode() -> String? {
        let firstCoord = walk.routeData.first.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        guard let marker = TurningDayService.turning(for: walk.startDate, at: firstCoord) else {
            return nil
        }
        switch marker {
        case .winterSolstice: return "winter-solstice"
        case .summerSolstice: return "summer-solstice"
        case .springEquinox:  return "spring-equinox"
        case .autumnEquinox:  return "autumn-equinox"
        case .imbolc, .beltane, .lughnasadh, .samhain: return nil
        }
    }
}
