import XCTest
@testable import Pilgrim

@MainActor
final class WalkShareInteractiveTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        UserPreferences.walkReliquaryEnabled.delete()
    }

    /// ~111m per 0.001 degree of latitude — the same geometry
    /// `RouteTrimmerTests` uses, spanning well past the 4x trim-distance
    /// threshold `RouteTrimmer` requires before it will shorten a route.
    private func longRoute(points: Int, baseDate: Date = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)) -> [TempV4.RouteDataSample] {
        (0..<points).map { i in
            WalkDataFactory.makeRouteDataSample(
                timestamp: baseDate.addingTimeInterval(Double(i) * 30),
                latitude: 48.8566 + Double(i) * 0.001,
                longitude: 2.3522
            )
        }
    }

    // MARK: - Brief's authoritative tests

    func testPayloadWithoutInteractiveHasNoTour() {
        let vm = WalkShareViewModel(walk: WalkDataFactory.makeWalk())
        let payload = vm.testBuildPayload()
        XCTAssertNil(payload.tour)
        XCTAssertNil(payload.pauses)
    }

    func testInteractivePayloadCarriesTourPausesAndTrim() {
        let walk = WalkDataFactory.makeWalk(
            routeData: longRoute(points: 20),
            pauses: [WalkDataFactory.makePause()],
            voiceRecordings: [WalkDataFactory.makeVoiceRecording()]
        )
        let vm = WalkShareViewModel(walk: walk)
        vm.interactiveEnabled = true
        vm.prepareInteractive()
        let payload = vm.testBuildPayload()
        XCTAssertNotNil(payload.tour)
        XCTAssertEqual(payload.tour?.trimM, 150)
        XCTAssertNotNil(payload.pauses)
    }

    func testTrimTogglePassesZero() {
        let walk = WalkDataFactory.makeWalk()
        let vm = WalkShareViewModel(walk: walk)
        vm.interactiveEnabled = true
        vm.trimEnabled = false
        vm.prepareInteractive()
        XCTAssertEqual(vm.testBuildPayload().tour?.trimM, 0)
    }

    func testInteractiveAutoEnablesPhotosOnce() {
        UserPreferences.walkReliquaryEnabled.value = true
        let walk = WalkDataFactory.makeWalk()
        let vm = WalkShareViewModel(walk: walk, pinnedPhotos: [PhotoCandidate.fixture()], isPhotosGranted: { true })
        vm.interactiveEnabled = true
        vm.prepareInteractive()
        XCTAssertTrue(vm.includePhotos)
        vm.includePhotos = false
        vm.prepareInteractive()
        XCTAssertFalse(vm.includePhotos, "auto-enable happens once; the walker's off stays off")
    }

    func testSubSecondPauseDroppedAfterTruncation() {
        let goodPause = WalkDataFactory.makePause(
            startDate: DateFactory.makeDate(2024, 6, 15, 9, 10, 0),
            endDate: DateFactory.makeDate(2024, 6, 15, 9, 15, 0)
        )
        let blipStart = DateFactory.makeDate(2024, 6, 15, 9, 20, 0)
        let subSecondPause = WalkDataFactory.makePause(startDate: blipStart, endDate: blipStart.addingTimeInterval(0.5))
        let walk = WalkDataFactory.makeWalk(pauses: [goodPause, subSecondPause])
        let vm = WalkShareViewModel(walk: walk)
        vm.interactiveEnabled = true
        vm.prepareInteractive()
        let payload = vm.testBuildPayload()
        XCTAssertEqual(payload.pauses?.count, 1, "the truncated-to-zero-length pause must be dropped, not just the good one kept")
        XCTAssertEqual(payload.pauses?.contains(where: { $0.endTs <= $0.startTs }), false)
    }

    func testFlipKindTogglesOverride() {
        let vm = WalkShareViewModel(walk: WalkDataFactory.makeWalk())
        vm.tourCandidates = [TourRecordingCandidate(id: 0, startTs: 1, endTs: 2, duration: 1, sizeBytes: 1, transcription: nil, wpm: nil, autoKind: .spoken, includeInShare: true, kindOverride: nil, fileURL: nil, unavailableReason: nil)]
        vm.flipKind(candidateID: 0)
        XCTAssertEqual(vm.tourCandidates[0].effectiveKind, .ambient)
        vm.flipKind(candidateID: 0)
        XCTAssertEqual(vm.tourCandidates[0].effectiveKind, .spoken)
    }

    // MARK: - Supplementary coverage

    func testToggleIncludeSkipsUnavailableCandidates() {
        let vm = WalkShareViewModel(walk: WalkDataFactory.makeWalk())
        let unavailable = TourRecordingCandidate(id: 0, startTs: 1, endTs: 2, duration: 1, sizeBytes: 0, transcription: nil, wpm: nil, autoKind: .spoken, includeInShare: false, kindOverride: nil, fileURL: nil, unavailableReason: "audio removed")
        let available = TourRecordingCandidate(id: 1, startTs: 1, endTs: 2, duration: 1, sizeBytes: 100, transcription: nil, wpm: nil, autoKind: .spoken, includeInShare: true, kindOverride: nil, fileURL: URL(fileURLWithPath: "/tmp/1.m4a"), unavailableReason: nil)
        vm.tourCandidates = [unavailable, available]

        vm.toggleInclude(candidateID: 0)
        XCTAssertFalse(vm.tourCandidates[0].includeInShare, "an unavailable candidate can never be toggled on")

        vm.toggleInclude(candidateID: 1)
        XCTAssertFalse(vm.tourCandidates[1].includeInShare)
        vm.toggleInclude(candidateID: 1)
        XCTAssertTrue(vm.tourCandidates[1].includeInShare)
    }

    func testCanTrimRouteReflectsRouteLength() {
        let shortWalk = WalkDataFactory.makeWalk(routeData: longRoute(points: 4))
        XCTAssertFalse(WalkShareViewModel(walk: shortWalk).canTrimRoute)

        let longWalk = WalkDataFactory.makeWalk(routeData: longRoute(points: 20))
        XCTAssertTrue(WalkShareViewModel(walk: longWalk).canTrimRoute)
    }

    func testNonInteractiveKeptWindowIsNil() {
        let vm = WalkShareViewModel(walk: WalkDataFactory.makeWalk(routeData: longRoute(points: 20)))
        XCTAssertNil(vm.interactiveKeptWindow())
    }

    func testInteractiveKeptWindowExcludesTrimmedWaypoints() {
        let route = longRoute(points: 20)
        let doorstep = TempV4.Waypoint(uuid: nil, latitude: 48.8566, longitude: 2.3522, label: "Doorstep", icon: "flag", timestamp: route[0].timestamp)
        let midpoint = TempV4.Waypoint(uuid: nil, latitude: 48.87, longitude: 2.3522, label: "Midpoint", icon: "flag", timestamp: route[10].timestamp)
        let walk = WalkDataFactory.makeWalk(routeData: route, waypoints: [doorstep, midpoint])
        let vm = WalkShareViewModel(walk: walk)
        vm.interactiveEnabled = true
        vm.includeWaypoints = true
        vm.prepareInteractive()

        XCTAssertNotNil(vm.interactiveKeptWindow())

        let labels = vm.testBuildPayload().waypoints?.map(\.label) ?? []
        XCTAssertFalse(labels.contains("Doorstep"), "trim excludes waypoints outside the kept route window")
        XCTAssertTrue(labels.contains("Midpoint"), "waypoints inside the kept window still ride along")
    }

    func testInteractiveKeptWindowIncludesWaypointsAtExactBoundary() {
        let route = longRoute(points: 20)
        let routePoints = route.map {
            SharePayload.RoutePoint(lat: $0.latitude, lon: $0.longitude, alt: $0.altitude, ts: Int($0.timestamp.timeIntervalSince1970))
        }
        let trimmed = RouteTrimmer.trim(routePoints, meters: Double(WalkShareViewModel.trimMeters))
        let atLowerBound = TempV4.Waypoint(uuid: nil, latitude: 48.86, longitude: 2.3522, label: "AtLowerBound", icon: "flag", timestamp: Date(timeIntervalSince1970: Double(trimmed.first!.ts)))
        let atUpperBound = TempV4.Waypoint(uuid: nil, latitude: 48.86, longitude: 2.3522, label: "AtUpperBound", icon: "flag", timestamp: Date(timeIntervalSince1970: Double(trimmed.last!.ts)))
        let walk = WalkDataFactory.makeWalk(routeData: route, waypoints: [atLowerBound, atUpperBound])
        let vm = WalkShareViewModel(walk: walk)
        vm.interactiveEnabled = true
        vm.includeWaypoints = true
        vm.prepareInteractive()

        let labels = vm.testBuildPayload().waypoints?.map(\.label) ?? []
        XCTAssertTrue(labels.contains("AtLowerBound"), "a waypoint exactly at the kept window's lower bound must be included — ClosedRange.contains is inclusive")
        XCTAssertTrue(labels.contains("AtUpperBound"), "a waypoint exactly at the kept window's upper bound must be included — ClosedRange.contains is inclusive")
    }

    func testInteractivePhotoMetaUsesOnlyExportedPhotos() {
        UserPreferences.walkReliquaryEnabled.value = true
        let walk = WalkDataFactory.makeWalk()
        let vm = WalkShareViewModel(walk: walk, pinnedPhotos: [PhotoCandidate.fixture()], isPhotosGranted: { true })
        vm.interactiveEnabled = true
        vm.includePhotos = true
        vm.prepareInteractive()

        let exported = [SharePayload.Photo(lat: 1, lon: 2, ts: 999, data: nil)]
        let withExport = vm.testBuildPayload(tourPhotoMeta: exported)
        XCTAssertEqual(withExport.photos?.count, 1)
        XCTAssertEqual(withExport.photos?.first?.ts, 999, "metadata must come from the export, not from pinnedPhotos")

        let withoutExport = vm.testBuildPayload(tourPhotoMeta: [])
        XCTAssertNil(withoutExport.photos, "the interactive branch must never fall back to mapping pinnedPhotos")
    }

    // MARK: - Task 8: share orchestration

    func testShareButtonDisabledWhenTourInvalid() {
        let vm = WalkShareViewModel(walk: WalkDataFactory.makeWalk())
        vm.interactiveEnabled = true
        vm.tourCandidates = (0..<13).map { i in
            TourRecordingCandidate(id: i, startTs: i, endTs: i + 1, duration: 60, sizeBytes: 1_000_000, transcription: nil, wpm: nil, autoKind: .spoken, includeInShare: true, kindOverride: nil, fileURL: nil, unavailableReason: nil)
        }
        XCTAssertNotNil(vm.tourValidationError)
        XCTAssertFalse(vm.canShare)
    }

    func testInteractivePayloadPhotoCountMatchesExportedMeta() {
        UserPreferences.walkReliquaryEnabled.value = true
        let walk = WalkDataFactory.makeWalk()
        let vm = WalkShareViewModel(walk: walk, pinnedPhotos: [PhotoCandidate.fixture()], isPhotosGranted: { true })
        vm.interactiveEnabled = true
        vm.includePhotos = true
        vm.prepareInteractive()

        let meta = [
            SharePayload.Photo(lat: 1, lon: 2, ts: 3, data: nil),
            SharePayload.Photo(lat: 4, lon: 5, ts: 6, data: nil),
            SharePayload.Photo(lat: 7, lon: 8, ts: 9, data: nil)
        ]
        let payload = vm.testBuildPayload(tourPhotoMeta: meta)
        XCTAssertEqual(payload.photos?.count, meta.count, "declared payload count must match the exported byte count — that's what authorizes each PUT index")
    }

    func testPartialAndSuccessBothCountAsShared() {
        let successID = UUID()
        addTeardownBlock { UserDefaults.standard.removeObject(forKey: "share:\(successID.uuidString)") }
        let successWalk = WalkDataFactory.makeWalk(uuid: successID)
        ShareService.cacheShare(
            ShareService.ShareResult(url: "https://walk.pilgrimapp.org/success1", id: "success1"),
            walkID: successID,
            expiryDays: 90,
            expiryOption: "season"
        )
        let successVM = WalkShareViewModel(walk: successWalk)
        XCTAssertTrue(successVM.isShared)
        guard case .success = successVM.shareState else {
            return XCTFail("expected .success when no media failed")
        }

        let partialID = UUID()
        addTeardownBlock {
            UserDefaults.standard.removeObject(forKey: "share:\(partialID.uuidString)")
            ShareService.cacheFailedMedia([], walkID: partialID)
        }
        let partialWalk = WalkDataFactory.makeWalk(uuid: partialID)
        ShareService.cacheShare(
            ShareService.ShareResult(url: "https://walk.pilgrimapp.org/partial1", id: "partial1"),
            walkID: partialID,
            expiryDays: 90,
            expiryOption: "season"
        )
        ShareService.cacheFailedMedia(
            [ShareService.FailedMediaItem(kind: "audio", n: 1, audioStartTs: 100, photoLocalID: nil, photoTs: nil)],
            walkID: partialID
        )
        let partialVM = WalkShareViewModel(walk: partialWalk)
        XCTAssertTrue(partialVM.isShared, ".partial must count as shared — the page is already live")
        guard case .partial(_, let failedCount) = partialVM.shareState else {
            return XCTFail("expected .partial when media failed")
        }
        XCTAssertEqual(failedCount, 1)
    }

    // MARK: - resolveRetryItems (pure identity resolution)

    func testResolveRetryItemsMatchesPhotoByIdentityNotIndex() {
        // Cached failure says n=1 for "photo-B" (captured at ts 500). In the
        // CURRENT export, photo-B sits at array position 1 (index 1), not 0
        // — an export-order shift. A naive index-based lookup
        // (currentPhotos[n-1] == currentPhotos[0]) would grab photo-A's
        // bytes instead and upload them under photo-B's old slot.
        let cached = [ShareService.FailedMediaItem(kind: "photos", n: 1, audioStartTs: nil, photoLocalID: "photo-B", photoTs: 500)]
        let photos = [
            TourPhoto(meta: SharePayload.Photo(lat: 0, lon: 0, ts: 100, data: nil), jpegData: Data([0xAA]), sourceLocalIdentifier: "photo-A"),
            TourPhoto(meta: SharePayload.Photo(lat: 1, lon: 2, ts: 500, data: nil), jpegData: Data([0xBB]), sourceLocalIdentifier: "photo-B")
        ]

        let (uploadable, remaining) = WalkShareViewModel.resolveRetryItems(
            cached: cached,
            currentRecordings: [],
            currentAudioFiles: [],
            currentPhotos: photos
        )

        XCTAssertTrue(remaining.isEmpty)
        guard let resolved = uploadable.first else { return XCTFail("expected photo-B to resolve by identity") }
        XCTAssertEqual(resolved.n, 1, "must upload under the CACHED slot n, not photo-B's current array position")
        XCTAssertEqual(try? resolved.data(), Data([0xBB]), "must upload photo-B's bytes (matched by identity), never photo-A's (which sat at the naive index)")
    }

    func testResolveRetryItemsPhotoMissingIdentityGoesToRemaining() {
        // "photo-gone" was unpinned between the original share and this retry
        // — it no longer appears anywhere in the current export.
        let cached = [ShareService.FailedMediaItem(kind: "photos", n: 1, audioStartTs: nil, photoLocalID: "photo-gone", photoTs: 500)]
        let photos = [TourPhoto(meta: SharePayload.Photo(lat: 0, lon: 0, ts: 999, data: nil), jpegData: Data([0xAA]), sourceLocalIdentifier: "photo-other")]

        let (uploadable, remaining) = WalkShareViewModel.resolveRetryItems(
            cached: cached,
            currentRecordings: [],
            currentAudioFiles: [],
            currentPhotos: photos
        )

        XCTAssertTrue(uploadable.isEmpty)
        XCTAssertEqual(remaining, cached, "an unresolved item must be carried forward unchanged, not dropped")
    }

    func testResolveRetryItemsAudioStartTsMismatchGoesToRemaining() {
        // recordings[0] is now a DIFFERENT recording (startTs 200, not the
        // cached 100) — the candidate set shifted since the original share.
        let cached = [ShareService.FailedMediaItem(kind: "audio", n: 1, audioStartTs: 100, photoLocalID: nil, photoTs: nil)]
        let recordings = [SharePayload.TourRecording(n: 1, startTs: 200, endTs: 260, duration: 60, kind: "spoken", transcription: nil, wpm: nil, sizeBytes: 1_000)]
        let audioFiles = [URL(fileURLWithPath: "/tmp/audio1.m4a")]

        let (uploadable, remaining) = WalkShareViewModel.resolveRetryItems(
            cached: cached,
            currentRecordings: recordings,
            currentAudioFiles: audioFiles,
            currentPhotos: []
        )

        XCTAssertTrue(uploadable.isEmpty)
        XCTAssertEqual(remaining, cached)
    }

    func testResolveRetryItemsAudioMatchesWhenStartTsAgrees() {
        let cached = [ShareService.FailedMediaItem(kind: "audio", n: 1, audioStartTs: 100, photoLocalID: nil, photoTs: nil)]
        let recordings = [SharePayload.TourRecording(n: 1, startTs: 100, endTs: 160, duration: 60, kind: "spoken", transcription: nil, wpm: nil, sizeBytes: 1_000)]
        let fileURL = URL(fileURLWithPath: "/tmp/audio1.m4a")

        let (uploadable, remaining) = WalkShareViewModel.resolveRetryItems(
            cached: cached,
            currentRecordings: recordings,
            currentAudioFiles: [fileURL],
            currentPhotos: []
        )

        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(uploadable.first?.n, 1)
        XCTAssertEqual(uploadable.first?.kind, .audio)
    }
}
