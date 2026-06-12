import XCTest
import Combine
import CoreLocation
@testable import Pilgrim

/// AF9/AF46: the walk-path pipeline must do bounded work per GPS sample —
/// no full route remap, no full segment rebuild, no full GeoJSON re-upload.
/// AF14: the battery tier must survive a meditation start/end cycle.
final class RoutePipelineTests: XCTestCase {

    // MARK: - Helpers

    private static let baseDate = Date(timeIntervalSince1970: 1_750_000_000)

    private func makeLocation(index: Int) -> CLLocation {
        CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 48.8566 + Double(index) * 0.00002, longitude: 2.3522),
            altitude: 35,
            horizontalAccuracy: 5,
            verticalAccuracy: 3,
            course: 0,
            speed: 1.4,
            timestamp: Self.baseDate.addingTimeInterval(Double(index))
        )
    }

    private func startRecording(_ vm: ActiveWalkViewModel) {
        vm.builder.setStatus(.ready)
        vm.builder.setStatus(.recording)
    }

    private func feed(_ vm: ActiveWalkViewModel, indices: Range<Int>, manager: CLLocationManager) {
        for index in indices {
            vm.locationManagement.locationManager(manager, didUpdateLocations: [makeLocation(index: index)])
        }
    }

    private func waitUntil(
        timeout: TimeInterval = 30,
        message: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: () -> Bool
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        XCTAssertTrue(condition(), message, file: file, line: line)
    }

    // MARK: - Incremental route pipeline (AF9/AF46)

    func testTenThousandSampleWalk_neverTriggersFullRouteRebuild() {
        let vm = ActiveWalkViewModel()
        defer { vm.cancel() }

        var fullRebuilds = 0
        vm._test_onFullRouteRebuild = { fullRebuilds += 1 }

        startRecording(vm)
        let manager = CLLocationManager()
        let sampleCount = 10_000
        feed(vm, indices: 0..<sampleCount, manager: manager)

        waitUntil(message: "all samples must reach the view model") {
            vm.routeCoordinates.count == sampleCount
        }

        XCTAssertEqual(fullRebuilds, 0, "steady-state growth must never re-map the whole route")
        XCTAssertEqual(vm.routeSegments.count, 1, "uninterrupted walking is a single segment")
        XCTAssertEqual(vm.routeSegments.first?.coordinates.count, sampleCount)
        XCTAssertEqual(vm.routeSegments.first?.activityType, "walking")
        XCTAssertEqual(vm.locationManagement.recordedSamples.count, sampleCount)
    }

    func testCheckpointSync_doesNotRebuildRoute() {
        let vm = ActiveWalkViewModel()
        defer { vm.cancel() }

        var fullRebuilds = 0
        vm._test_onFullRouteRebuild = { fullRebuilds += 1 }

        startRecording(vm)
        let manager = CLLocationManager()
        feed(vm, indices: 0..<5, manager: manager)
        waitUntil(message: "samples must land") { vm.routeCoordinates.count == 5 }

        // The 10–30 s checkpoint timer pulls the canonical route into the
        // builder relay; the resulting full-array echo must not cost O(n)
        // in the view model.
        vm.locationManagement.syncRouteToBuilder()
        settleCombineSchedulers()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))

        XCTAssertEqual(fullRebuilds, 0, "a checkpoint sync echo must be skipped, not rebuilt")
        XCTAssertEqual(vm.routeCoordinates.count, 5)
    }

    func testPauseResume_keepsRouteContinuousAndSingleSegment() {
        let vm = ActiveWalkViewModel()
        defer { vm.cancel() }

        startRecording(vm)
        let manager = CLLocationManager()
        feed(vm, indices: 0..<3, manager: manager)

        vm.builder.setStatus(.paused)
        feed(vm, indices: 3..<5, manager: manager)

        vm.builder.setStatus(.recording)
        feed(vm, indices: 5..<6, manager: manager)

        waitUntil(message: "all samples must land") { vm.routeCoordinates.count == 6 }
        XCTAssertEqual(vm.routeSegments.count, 1, "pause is not an activity boundary")
        XCTAssertEqual(vm.routeSegments.first?.coordinates.count, 6)
    }

    func testMeditationBoundary_opensSegmentWithSharedBoundaryCoordinate() {
        let vm = ActiveWalkViewModel()
        defer { vm.cancel() }

        startRecording(vm)
        let manager = CLLocationManager()
        feed(vm, indices: 0..<3, manager: manager)
        waitUntil(message: "walking samples must land") { vm.routeCoordinates.count == 3 }

        vm._test_setMeditationStart(Self.baseDate.addingTimeInterval(2.5))
        feed(vm, indices: 3..<5, manager: manager)
        waitUntil(message: "meditation samples must land") { vm.routeCoordinates.count == 5 }

        XCTAssertEqual(vm.routeSegments.map(\.activityType), ["walking", "meditating"])
        XCTAssertEqual(vm.routeSegments[0].coordinates.count, 4, "boundary sample closes the walking segment")
        XCTAssertEqual(vm.routeSegments[1].coordinates.count, 2, "boundary sample also opens the meditating segment")
        XCTAssertEqual(
            vm.routeSegments[0].coordinates.last?.latitude,
            vm.routeSegments[1].coordinates.first?.latitude,
            "segments must share the boundary coordinate so the line stays continuous"
        )
    }

    func testContinueWalkSeed_rebuildsRouteOnce() {
        let vm = ActiveWalkViewModel()
        defer { vm.cancel() }

        var fullRebuilds = 0
        vm._test_onFullRouteRebuild = { fullRebuilds += 1 }

        let routeData = (0..<4).map { index in
            WalkDataFactory.makeRouteDataSample(
                timestamp: Self.baseDate.addingTimeInterval(Double(index)),
                latitude: 48.85 + Double(index) * 0.0001
            )
        }
        let snapshot = WalkDataFactory.makeWalk(routeData: routeData)
        vm.builder.continueWalk(from: snapshot)

        waitUntil(message: "seeded route must reach the view model") {
            vm.routeCoordinates.count == 4
        }
        XCTAssertEqual(fullRebuilds, 1, "a recovery/continue seed is the one legitimate full rebuild")
        XCTAssertEqual(vm.locationManagement.recordedSamples.count, 4)
        XCTAssertEqual(vm.routeSegments.first?.coordinates.count, 4)
    }

    // MARK: - Battery tier survives meditation (AF14)

    func testLowBatteryTier_persistsThroughMeditationCycle() throws {
        let vm = ActiveWalkViewModel()
        defer { vm.cancel() }

        let sessionGuard = try XCTUnwrap(vm._test_sessionGuard)

        func waitForTierRecalc(after action: () -> Void) {
            let recalculated = expectation(description: "tier recalculated")
            recalculated.assertForOverFulfill = false
            sessionGuard._test_onRecalculateTier = { recalculated.fulfill() }
            action()
            wait(for: [recalculated], timeout: 2.0)
            sessionGuard._test_onRecalculateTier = nil
        }

        sessionGuard._test_batteryLevelOverride = 0.15
        waitForTierRecalc {
            NotificationCenter.default.post(name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        }
        XCTAssertEqual(
            vm.locationManagement._test_appliedAccuracy,
            kCLLocationAccuracyNearestTenMeters,
            "15% battery must apply the low-power tier"
        )

        waitForTierRecalc { vm.isMeditating = true }
        XCTAssertEqual(
            vm.locationManagement._test_appliedAccuracy,
            kCLLocationAccuracyNearestTenMeters,
            "low battery outranks meditation in the tier system"
        )

        waitForTierRecalc { vm.endMeditationSilently() }
        XCTAssertEqual(
            vm.locationManagement._test_appliedAccuracy,
            kCLLocationAccuracyNearestTenMeters,
            "ending meditation on low battery must NOT restore full-power GPS (AF14)"
        )

        sessionGuard._test_batteryLevelOverride = 1.0
        waitForTierRecalc {
            NotificationCenter.default.post(name: UIDevice.batteryLevelDidChangeNotification, object: nil)
        }
        XCTAssertEqual(
            vm.locationManagement._test_appliedAccuracy,
            kCLLocationAccuracyBest,
            "recovering battery must restore the normal tier"
        )
    }

    // MARK: - Proximity pin computation (AF43)

    func testComputeProximityPins_appliesRadiusAndSeparation() {
        let user = CLLocation(latitude: 48.0, longitude: 2.0)
        let near = CachedWhisper(
            id: "w-near", latitude: 48.001, longitude: 2.0,
            whisperId: "x", category: "presence", expiresAt: ""
        )
        let crowded = CachedWhisper(
            id: "w-crowded", latitude: 48.00105, longitude: 2.0,
            whisperId: "x", category: "wonder", expiresAt: ""
        )
        let far = CachedWhisper(
            id: "w-far", latitude: 48.1, longitude: 2.0,
            whisperId: "x", category: "presence", expiresAt: ""
        )
        let cairn = CachedCairn(
            id: "c-1", latitude: 48.001, longitude: 2.0,
            stoneCount: 3, lastPlacedAt: ""
        )

        let pins = ActiveWalkViewModel.computeProximityPins(
            around: user,
            whispers: [near, crowded, far],
            cairns: [cairn]
        )

        XCTAssertEqual(pins.count, 2, "far whisper excluded by radius, crowded whisper by min separation")
        let kinds = pins.map { pin -> String in
            switch pin.kind {
            case .whisper: return "whisper"
            case .cairn: return "cairn"
            default: return "other"
            }
        }
        XCTAssertEqual(Set(kinds), ["whisper", "cairn"], "different kinds may share a location")
    }

    // MARK: - RouteSourcePlanner (Mapbox-side AF9)

    /// Mirrors how PilgrimMapView applies plans to the GeoJSON source, so
    /// the tests can verify the reconstructed geometry matches the route.
    private struct SourceSimulator {
        var features: [String: RouteSourcePlanner.Chunk] = [:]
        var violations: [String] = []

        mutating func apply(_ plan: RouteSourcePlanner.Plan) {
            switch plan {
            case .noChange:
                break
            case .fullRebuild(let chunks):
                features = Dictionary(uniqueKeysWithValues: chunks.map { ($0.id, $0) })
            case .incremental(let addedChunks, let tailAction):
                for chunk in addedChunks {
                    if features[chunk.id] != nil {
                        violations.append("added chunk \(chunk.id) already exists")
                    }
                    features[chunk.id] = chunk
                }
                switch tailAction {
                case .none:
                    break
                case .set(let tail, let isNew):
                    if isNew && features[tail.id] != nil {
                        violations.append("tail marked new but feature exists")
                    }
                    if !isNew && features[tail.id] == nil {
                        violations.append("tail update without existing feature")
                    }
                    features[tail.id] = tail
                case .remove:
                    if features[RouteSourcePlanner.tailFeatureID] == nil {
                        violations.append("tail removal without existing feature")
                    }
                    features.removeValue(forKey: RouteSourcePlanner.tailFeatureID)
                }
            }
        }

        func flattenedCoordinates() -> [CLLocationCoordinate2D] {
            let chunkIndex: (String) -> Int? = { id in
                guard id.hasPrefix("route-chunk-") else { return nil }
                return Int(id.dropFirst("route-chunk-".count))
            }
            var ordered = features.values
                .compactMap { chunk in chunkIndex(chunk.id).map { (index: $0, chunk: chunk) } }
                .sorted { $0.index < $1.index }
                .map(\.chunk)
            if let tail = features[RouteSourcePlanner.tailFeatureID] {
                ordered.append(tail)
            }

            var coords: [CLLocationCoordinate2D] = []
            for chunk in ordered {
                for coord in chunk.coordinates {
                    if let last = coords.last,
                       last.latitude == coord.latitude, last.longitude == coord.longitude {
                        continue
                    }
                    coords.append(coord)
                }
            }
            return coords
        }
    }

    private func makeCoords(_ range: Range<Int>) -> [CLLocationCoordinate2D] {
        range.map { CLLocationCoordinate2D(latitude: 48.0 + Double($0) * 0.0001, longitude: 2.0) }
    }

    func testPlanner_noChangeForIdenticalSegments() {
        var planner = RouteSourcePlanner(chunkSize: 4)
        let segments = [RouteSegment(coordinates: makeCoords(0..<3), activityType: "walking")]
        _ = planner.plan(for: segments)
        XCTAssertEqual(planner.plan(for: segments), .noChange)
    }

    func testPlanner_perSampleGrowth_isBoundedAndReconstructs() {
        let chunkSize = 4
        var planner = RouteSourcePlanner(chunkSize: chunkSize)
        var sim = SourceSimulator()
        let total = 23

        for count in 2...total {
            let segments = [RouteSegment(coordinates: makeCoords(0..<count), activityType: "walking")]
            let plan = planner.plan(for: segments)

            if case .fullRebuild = plan, count > 2 {
                XCTFail("append-only growth must never trigger a full rebuild (count \(count))")
            }
            if case .incremental(let added, let tailAction) = plan {
                for chunk in added {
                    XCTAssertLessThanOrEqual(chunk.coordinates.count, chunkSize + 1)
                }
                if case .set(let tail, _) = tailAction {
                    XCTAssertLessThanOrEqual(
                        tail.coordinates.count, chunkSize + 1,
                        "tail must stay bounded by the chunk size"
                    )
                }
            }
            sim.apply(plan)
        }

        XCTAssertEqual(sim.violations, [])
        let reconstructed = sim.flattenedCoordinates()
        let expected = makeCoords(0..<total)
        XCTAssertEqual(reconstructed.count, expected.count)
        for (lhs, rhs) in zip(reconstructed, expected) {
            XCTAssertEqual(lhs.latitude, rhs.latitude, accuracy: 1e-12)
        }
    }

    func testPlanner_activityTransition_sealsClosingSegmentAndReconstructs() {
        var planner = RouteSourcePlanner(chunkSize: 4)
        var sim = SourceSimulator()

        let walking = makeCoords(0..<4)
        sim.apply(planner.plan(for: [RouteSegment(coordinates: walking, activityType: "walking")]))

        // Transition: boundary coordinate closes walking AND opens meditating.
        let boundary = makeCoords(4..<5)[0]
        let closedWalking = RouteSegment(coordinates: walking + [boundary], activityType: "walking")
        let transition = [closedWalking, RouteSegment(coordinates: [boundary], activityType: "meditating")]
        let plan = planner.plan(for: transition)
        guard case .incremental(let added, let tailAction) = plan else {
            return XCTFail("transition must stay incremental, got \(plan)")
        }
        XCTAssertEqual(added.count, 1, "closing segment seals into one chunk")
        XCTAssertEqual(added.first?.activityType, "walking")
        XCTAssertEqual(tailAction, .remove, "a single-coordinate open segment cannot be a LineString yet")
        sim.apply(plan)

        // Growth of the new segment re-creates the tail.
        let grown = [closedWalking, RouteSegment(coordinates: [boundary, makeCoords(5..<6)[0]], activityType: "meditating")]
        let growthPlan = planner.plan(for: grown)
        guard case .incremental(_, .set(let tail, let isNew)) = growthPlan else {
            return XCTFail("growth after transition must set a tail, got \(growthPlan)")
        }
        XCTAssertTrue(isNew, "tail was removed at the transition, so it must be re-added")
        XCTAssertEqual(tail.activityType, "meditating")
        sim.apply(growthPlan)

        XCTAssertEqual(sim.violations, [])
        XCTAssertEqual(sim.flattenedCoordinates().count, 6, "5 walking coords + 1 meditating, boundary deduped")
    }

    func testPlanner_structuralChange_triggersFullRebuild() {
        var planner = RouteSourcePlanner(chunkSize: 4)
        _ = planner.plan(for: [RouteSegment(coordinates: makeCoords(0..<5), activityType: "walking")])

        let shrunk = [RouteSegment(coordinates: makeCoords(0..<3), activityType: "walking")]
        guard case .fullRebuild = planner.plan(for: shrunk) else {
            return XCTFail("a shrinking route must fall back to a full rebuild")
        }
    }

    func testPlanner_resetForcesFullRebuild() {
        var planner = RouteSourcePlanner(chunkSize: 4)
        let segments = [RouteSegment(coordinates: makeCoords(0..<5), activityType: "walking")]
        _ = planner.plan(for: segments)

        planner.reset()
        guard case .fullRebuild(let chunks) = planner.plan(for: segments) else {
            return XCTFail("after reset the next plan must rebuild the source")
        }
        XCTAssertFalse(chunks.isEmpty)
    }
}
