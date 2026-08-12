import XCTest
@testable import Pilgrim

@MainActor
final class WalkShareInteractiveTests: XCTestCase {

    override func tearDown() {
        super.tearDown()
        UserPreferences.walkReliquaryEnabled.delete()
    }

    /// ~111m per 0.001 degree of latitude — the same geometry `RouteTrimmerTests` uses, spanning well past the 4x trim-distance threshold `RouteTrimmer` requires before it will shorten a route.
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

    // MARK: - Review finding #17: excluded recordings leave no trace

    func testExcludedRecordingLeavesNoTalkInterval() {
        let keptCandidate = TourRecordingCandidate(id: 0, startTs: 1000, endTs: 1060, duration: 60, sizeBytes: 1_000_000, transcription: nil, wpm: nil, autoKind: .spoken, includeInShare: true, kindOverride: nil, fileURL: URL(fileURLWithPath: "/tmp/0.m4a"), unavailableReason: nil)
        let excludedCandidate = TourRecordingCandidate(id: 1, startTs: 2000, endTs: 2090, duration: 90, sizeBytes: 1_500_000, transcription: nil, wpm: nil, autoKind: .spoken, includeInShare: true, kindOverride: nil, fileURL: URL(fileURLWithPath: "/tmp/1.m4a"), unavailableReason: nil)
        let vm = WalkShareViewModel(walk: WalkDataFactory.makeWalk())
        vm.tourCandidates = [keptCandidate, excludedCandidate]
        vm.interactiveEnabled = true
        vm.toggleInclude(candidateID: excludedCandidate.id)
        let payload = vm.testBuildPayload()
        let talkIntervals = payload.activityIntervals.filter { $0.type == "talk" }
        XCTAssertEqual(talkIntervals.count, 1, "the excluded candidate's talk interval must not appear")
        XCTAssertEqual(talkIntervals.first?.startTs, keptCandidate.startTs)
        XCTAssertEqual(talkIntervals.first?.endTs, keptCandidate.endTs)
        XCTAssertEqual(payload.stats.talkDuration, keptCandidate.duration, "excluded duration must not count toward the total")
    }

    func testClassicTalkIntervalsUnchangedByExclusions() {
        let rec1 = WalkDataFactory.makeVoiceRecording(startDate: DateFactory.makeDate(2024, 6, 15, 9, 5, 0), endDate: DateFactory.makeDate(2024, 6, 15, 9, 6, 0), duration: 60)
        let rec2 = WalkDataFactory.makeVoiceRecording(startDate: DateFactory.makeDate(2024, 6, 15, 9, 10, 0), endDate: DateFactory.makeDate(2024, 6, 15, 9, 11, 30), duration: 90)
        let walk = WalkDataFactory.makeWalk(talkDuration: 999, voiceRecordings: [rec1, rec2])
        let vm = WalkShareViewModel(walk: walk)
        // interactiveEnabled left false — classic share must ignore tourCandidates exclusions entirely.
        vm.tourCandidates = [rec1, rec2].enumerated().map { i, rec in
            TourRecordingCandidate(id: i, startTs: Int(rec.startDate.timeIntervalSince1970), endTs: Int(rec.endDate.timeIntervalSince1970), duration: rec.duration, sizeBytes: 1_000_000, transcription: nil, wpm: nil, autoKind: .spoken, includeInShare: true, kindOverride: nil, fileURL: nil, unavailableReason: nil)
        }
        vm.toggleInclude(candidateID: 1)
        let payload = vm.testBuildPayload()
        let talkIntervals = payload.activityIntervals.filter { $0.type == "talk" }
        XCTAssertEqual(talkIntervals.count, 2, "classic path reads walk.voiceRecordings directly — candidate exclusions must have zero effect")
        XCTAssertEqual(talkIntervals.map(\.startTs).sorted(), [rec1, rec2].map { Int($0.startDate.timeIntervalSince1970) }.sorted())
        XCTAssertEqual(payload.stats.talkDuration, walk.talkDuration)
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

    func testInteractivePayloadJSONContainsNoTranscription() throws {
        // Guards the whole payload path, not just TourBuilder.tourItems: even an offerable, transcript-bearing candidate must never put the transcript's text — or the "transcription" key itself — on the wire.
        let vm = WalkShareViewModel(walk: WalkDataFactory.makeWalk())
        vm.tourCandidates = [
            TourRecordingCandidate(id: 0, startTs: 1000, endTs: 1060, duration: 60, sizeBytes: 1_000_000, transcription: "some real speech", wpm: 120, autoKind: .spoken, includeInShare: true, kindOverride: nil, fileURL: URL(fileURLWithPath: "/tmp/0.m4a"), unavailableReason: nil)
        ]
        vm.interactiveEnabled = true
        vm.prepareInteractive()

        let data = try JSONEncoder().encode(vm.testBuildPayload())
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        XCTAssertFalse(json.contains("some real speech"), "transcript content must never leave the device")
        XCTAssertFalse(json.contains("transcription"), "the transcription key itself must never appear in the payload")
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

    func testShortRouteTrimIsHonestAndLeavesWaypointsUnfiltered() {
        let route = longRoute(points: 4) // ~333m total — well under the 4x-150m trim threshold
        let early = TempV4.Waypoint(
            uuid: nil,
            latitude: 48.8566,
            longitude: 2.3522,
            label: "Before the first fix",
            icon: "flag",
            timestamp: route[0].timestamp.addingTimeInterval(-3600)
        )
        let walk = WalkDataFactory.makeWalk(routeData: route, waypoints: [early])
        let vm = WalkShareViewModel(walk: walk)
        vm.interactiveEnabled = true
        vm.trimEnabled = true
        vm.includeWaypoints = true
        vm.prepareInteractive()

        let payload = vm.testBuildPayload()

        XCTAssertEqual(payload.tour?.trimM, 0, "a route too short to actually trim must report trimM 0, not the requested 150 — RouteTrimmer silently no-ops on it")
        let labels = payload.waypoints?.map(\.label) ?? []
        XCTAssertTrue(labels.contains("Before the first fix"), "no real trim happened, so nothing should be filtered out — not even a waypoint before the first GPS fix")
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

    func testTourTotalsLabelWording() {
        let emptyVM = WalkShareViewModel(walk: WalkDataFactory.makeWalk())
        XCTAssertEqual(emptyVM.tourTotalsLabel, "no recordings included")

        let singularVM = WalkShareViewModel(walk: WalkDataFactory.makeWalk())
        singularVM.tourCandidates = [
            TourRecordingCandidate(id: 0, startTs: 1000, endTs: 1060, duration: 60, sizeBytes: 1_000_000, transcription: nil, wpm: nil, autoKind: .spoken, includeInShare: true, kindOverride: nil, fileURL: URL(fileURLWithPath: "/tmp/0.m4a"), unavailableReason: nil)
        ]
        XCTAssertTrue(singularVM.tourTotalsLabel.hasPrefix("1 recording ·"), "singular wording must not add a trailing s")
        XCTAssertFalse(singularVM.tourTotalsLabel.contains("1 recordings"))

        UserPreferences.walkReliquaryEnabled.value = true
        let walkStart = DateFactory.makeDate(2024, 6, 15, 9, 0, 0)
        let walkEnd = DateFactory.makeDate(2024, 6, 15, 9, 30, 0)
        let manyPhotos = (0..<25).map { i in
            PhotoCandidate.fixture(localIdentifier: "photo-\(i)", capturedAt: walkStart.addingTimeInterval(Double(i) * 30))
        }
        let walk = WalkDataFactory.makeWalk(startDate: walkStart, endDate: walkEnd)
        let cappedVM = WalkShareViewModel(walk: walk, pinnedPhotos: manyPhotos, isPhotosGranted: { true })
        cappedVM.includePhotos = true

        XCTAssertEqual(cappedVM.interactivePhotoExportList().count, 20, "the export list itself caps at 20")
        XCTAssertTrue(cappedVM.tourTotalsLabel.contains("20 hi-res photos"), "the label's photo count must cap at the export list's count, not the full pinned count")
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

    // MARK: - geocodeAnchorPoints

    func testGeocodeAnchorPointsInteractiveUsesTrimmedRouteEnds() throws {
        let route = longRoute(points: 20)
        let walk = WalkDataFactory.makeWalk(routeData: route)
        let vm = WalkShareViewModel(walk: walk)
        vm.interactiveEnabled = true
        vm.prepareInteractive()

        let anchors = try XCTUnwrap(vm.geocodeAnchorPoints())

        let rawFirstTs = Int(route[0].timestamp.timeIntervalSince1970)
        let rawLastTs = Int(route[route.count - 1].timestamp.timeIntervalSince1970)
        XCTAssertNotEqual(anchors.start.ts, rawFirstTs, "interactive anchors must come from the TRIMMED route, not the raw ends")
        XCTAssertNotEqual(anchors.end.ts, rawLastTs)

        let expectedTrimmed = RouteTrimmer.trim(
            route.map { SharePayload.RoutePoint(lat: $0.latitude, lon: $0.longitude, alt: $0.altitude, ts: Int($0.timestamp.timeIntervalSince1970)) },
            meters: Double(WalkShareViewModel.trimMeters)
        )
        XCTAssertEqual(anchors.start.ts, expectedTrimmed.first?.ts)
        XCTAssertEqual(anchors.end.ts, expectedTrimmed.last?.ts)
    }

    func testGeocodeAnchorPointsClassicUsesRawRouteEnds() throws {
        let route = longRoute(points: 20)
        let walk = WalkDataFactory.makeWalk(routeData: route)
        let vm = WalkShareViewModel(walk: walk)
        // interactiveEnabled left false — classic share.

        let anchors = try XCTUnwrap(vm.geocodeAnchorPoints())

        XCTAssertEqual(anchors.start.ts, Int(route.first!.timestamp.timeIntervalSince1970))
        XCTAssertEqual(anchors.end.ts, Int(route.last!.timestamp.timeIntervalSince1970))
    }

    // MARK: - resolveRetryItems (pure identity resolution)

    func testResolveRetryItemsMatchesPhotoByIdentityNotIndex() {
        // Cached failure says n=1 for "photo-B" (captured at ts 500). In the CURRENT export, photo-B sits at array position 1 (index 1), not 0 — an export-order shift. A naive index-based lookup (currentPhotos[n-1] == currentPhotos[0]) would grab photo-A's bytes instead and upload them under photo-B's old slot.
        let cached = [ShareService.FailedMediaItem(kind: "photos", n: 1, audioStartTs: nil, photoLocalID: "photo-B", photoTs: 500)]
        let photos = [
            TourPhoto(meta: SharePayload.Photo(lat: 0, lon: 0, ts: 100, data: nil), jpegData: Data([0xAA]), sourceLocalIdentifier: "photo-A"),
            TourPhoto(meta: SharePayload.Photo(lat: 1, lon: 2, ts: 500, data: nil), jpegData: Data([0xBB]), sourceLocalIdentifier: "photo-B")
        ]

        let (uploadable, remaining) = WalkShareViewModel.resolveRetryItems(cached: cached, currentRecordings: [], currentAudioFiles: [], currentPhotos: photos)

        XCTAssertTrue(remaining.isEmpty)
        guard let resolved = uploadable.first else { return XCTFail("expected photo-B to resolve by identity") }
        XCTAssertEqual(resolved.n, 1, "must upload under the CACHED slot n, not photo-B's current array position")
        XCTAssertEqual(try? resolved.data(), Data([0xBB]), "must upload photo-B's bytes (matched by identity), never photo-A's (which sat at the naive index)")
    }

    func testResolveRetryItemsPhotoMissingIdentityGoesToRemaining() {
        // "photo-gone" was unpinned between the original share and this retry — it no longer appears anywhere in the current export.
        let cached = [ShareService.FailedMediaItem(kind: "photos", n: 1, audioStartTs: nil, photoLocalID: "photo-gone", photoTs: 500)]
        let photos = [TourPhoto(meta: SharePayload.Photo(lat: 0, lon: 0, ts: 999, data: nil), jpegData: Data([0xAA]), sourceLocalIdentifier: "photo-other")]

        let (uploadable, remaining) = WalkShareViewModel.resolveRetryItems(cached: cached, currentRecordings: [], currentAudioFiles: [], currentPhotos: photos)

        XCTAssertTrue(uploadable.isEmpty)
        XCTAssertEqual(remaining, cached, "an unresolved item must be carried forward unchanged, not dropped")
    }

    func testResolveRetryItemsUnrecognizedKindGoesToRemaining() {
        let cached = [ShareService.FailedMediaItem(kind: "video", n: 1, audioStartTs: nil, photoLocalID: nil, photoTs: nil)]

        let (uploadable, remaining) = WalkShareViewModel.resolveRetryItems(cached: cached, currentRecordings: [], currentAudioFiles: [], currentPhotos: [])

        XCTAssertTrue(uploadable.isEmpty)
        XCTAssertEqual(remaining, cached, "a kind this build no longer recognizes must be carried forward, not dropped or crashed on")
    }

    func testResolveRetryItemsAudioStartTsMismatchGoesToRemaining() {
        // The cached startTs (100) is absent from EVERY current recording — not just shifted position, but genuinely gone. Two recordings (not one) so this can't accidentally pass just because index 0 mismatches.
        let cached = [ShareService.FailedMediaItem(kind: "audio", n: 1, audioStartTs: 100, photoLocalID: nil, photoTs: nil)]
        let recordings = [
            SharePayload.TourRecording(n: 1, startTs: 200, endTs: 260, duration: 60, kind: "spoken", transcription: nil, wpm: nil, sizeBytes: 1_000),
            SharePayload.TourRecording(n: 2, startTs: 300, endTs: 360, duration: 60, kind: "spoken", transcription: nil, wpm: nil, sizeBytes: 1_000)
        ]
        let audioFiles = [URL(fileURLWithPath: "/tmp/audio1.m4a"), URL(fileURLWithPath: "/tmp/audio2.m4a")]

        let (uploadable, remaining) = WalkShareViewModel.resolveRetryItems(cached: cached, currentRecordings: recordings, currentAudioFiles: audioFiles, currentPhotos: [])

        XCTAssertTrue(uploadable.isEmpty)
        XCTAssertEqual(remaining, cached)
    }

    func testResolveRetryItemsAudioFoundAtShiftedIndex() {
        // The cached failure originally pointed at slot n=3, whose recording had startTs 500. Since then an earlier recording dropped out of the candidate set, so that SAME recording (still startTs 500) now sits at index 0 — an index-locked lookup (index 2) would miss it entirely.
        let cached = [ShareService.FailedMediaItem(kind: "audio", n: 3, audioStartTs: 500, photoLocalID: nil, photoTs: nil)]
        let recordings = [
            SharePayload.TourRecording(n: 1, startTs: 500, endTs: 560, duration: 60, kind: "spoken", transcription: nil, wpm: nil, sizeBytes: 1_000),
            SharePayload.TourRecording(n: 2, startTs: 600, endTs: 660, duration: 60, kind: "spoken", transcription: nil, wpm: nil, sizeBytes: 1_000)
        ]
        let audioFiles = [URL(fileURLWithPath: "/tmp/shifted-0.m4a"), URL(fileURLWithPath: "/tmp/shifted-1.m4a")]

        let (uploadable, remaining) = WalkShareViewModel.resolveRetryItems(cached: cached, currentRecordings: recordings, currentAudioFiles: audioFiles, currentPhotos: [])

        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(uploadable.first?.n, 3, "must upload under the CACHED slot n, not the recording's shifted array position")
        XCTAssertEqual(uploadable.first?.kind, .audio)
    }

    func testResolveRetryItemsAudioMatchesWhenStartTsAgrees() {
        let cached = [ShareService.FailedMediaItem(kind: "audio", n: 1, audioStartTs: 100, photoLocalID: nil, photoTs: nil)]
        let recordings = [SharePayload.TourRecording(n: 1, startTs: 100, endTs: 160, duration: 60, kind: "spoken", transcription: nil, wpm: nil, sizeBytes: 1_000)]
        let fileURL = URL(fileURLWithPath: "/tmp/audio1.m4a")

        let (uploadable, remaining) = WalkShareViewModel.resolveRetryItems(cached: cached, currentRecordings: recordings, currentAudioFiles: [fileURL], currentPhotos: [])

        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(uploadable.first?.n, 1)
        XCTAssertEqual(uploadable.first?.kind, .audio)
    }

    // MARK: - expectedFailureRecords (kill-safe repair record)

    func testExpectedFailureRecordsMatchIdentityMapping() {
        let recordings = [
            SharePayload.TourRecording(n: 1, startTs: 100, endTs: 160, duration: 60, kind: "spoken", transcription: nil, wpm: nil, sizeBytes: 1_000),
            SharePayload.TourRecording(n: 2, startTs: 200, endTs: 260, duration: 60, kind: "ambient", transcription: nil, wpm: nil, sizeBytes: 2_000)
        ]
        let photos = [TourPhoto(meta: SharePayload.Photo(lat: 1, lon: 2, ts: 999, data: nil), jpegData: Data([0xAA]), sourceLocalIdentifier: "photo-1")]

        let records = WalkShareViewModel.expectedFailureRecords(recordings: recordings, photos: photos)

        XCTAssertEqual(records.count, 3, "one record per recording plus one per photo — the FULL upload, not just failures")

        XCTAssertEqual(records[0].kind, "audio")
        XCTAssertEqual(records[0].n, 1)
        XCTAssertEqual(records[0].audioStartTs, 100)
        XCTAssertNil(records[0].photoLocalID)
        XCTAssertNil(records[0].photoTs)

        XCTAssertEqual(records[1].kind, "audio")
        XCTAssertEqual(records[1].n, 2)
        XCTAssertEqual(records[1].audioStartTs, 200)

        XCTAssertEqual(records[2].kind, "photos")
        XCTAssertEqual(records[2].n, 1)
        XCTAssertNil(records[2].audioStartTs)
        XCTAssertEqual(records[2].photoLocalID, "photo-1")
        XCTAssertEqual(records[2].photoTs, 999)
    }

    // MARK: - Fix #11: dropped-photo consent moment
    // (testPhotosDroppedCountsAsInFlightForFormFreeze omitted: `isShareInFlight` is `private` on `WalkShareView`, not VM-exposed — nothing here to assert against.)

    func testCancelDroppedPhotoShareReturnsToIdle() {
        let vm = WalkShareViewModel(walk: WalkDataFactory.makeWalk())
        vm.shareState = .photosDropped(prepared: 2, dropped: 1)
        vm.cancelDroppedPhotoShare()
        XCTAssertEqual(vm.shareState, .idle)
    }
}
