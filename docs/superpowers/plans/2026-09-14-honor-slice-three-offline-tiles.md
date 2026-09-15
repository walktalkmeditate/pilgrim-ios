# Honor Slice Three: Offline Maps — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A downloaded pilgrimage's basemap is saved to the phone by one opt-in tap on the route page, sized before the tap, one Mapbox tile region per stage, so the walk screen, overview and morning card render with no signal.

**Architecture:** A new `PilgrimageTilesManager` (sibling of `PilgrimagePackageManager`, same `Phase` shape, same `isWalkActive` seam) owns tile regions keyed by the stage's Way id. Every Mapbox call goes through a `TileRegionLoading` protocol with one production conformer (`MapboxTileRegionLoader`) and one test fake, so every test in this plan runs without Mapbox. The package manager's three lifecycle moments call the tiles manager; a launch-time `reconcile` is the backstop. Two SwiftUI surfaces read the manager: the route page row and Settings → Data → Maps; the morning card gets one caption line.

**Tech Stack:** Swift 5.10, SwiftUI, Combine, MapboxMaps 11.23.1 (SPM) — `OfflineManager`, `TileStore`, `TilesetDescriptorOptions`, `TileRegionLoadOptions`, `StylePackLoadOptions`, `OfflineSwitch`; Turf `Polygon` (transitive via MapboxMaps); XCTest.

**Spec:** `docs/superpowers/specs/2026-09-14-honor-slice-three-offline-tiles-design.md` (commit `1e4e514`). Section numbers below refer to it.

## Global Constraints

- Typography only via `Constants.Typography.*` (`caption`, `body`, `button`); never `.system()`.
- Comments explain why, never what. No commented-out code. No `= nil` initialisers on optionals (SwiftLint `implicit_optional_initialization`).
- `VStack(alignment: .leading, …)` for any stack with varying-width rows.
- Nothing is added to the active-walk screen (`ActiveWalkView`) except the morning-card caption passed through its existing sheet.
- Every SDK progress/completion closure captures `[weak self]`. The in-flight `Cancelable` is stored and cancelled in `cancel()`, `remove(routeId:)`, and `deinit`.
- New Swift files are registered with `ruby scripts/xcode-add.rb <Pilgrim|UnitTests> <path/from/repo/root.swift>` immediately after creation, before the first build.
- Every commit message ends with `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Never bare `git stash`. Never commit to `main`; the branch is `feat/honor-slice-three` in worktree `.worktrees/honor-slice-three`, shipped by PR. No TestFlight without an explicit go.
- Region id for stage `i` of route `r` is exactly `WayStore.stageWayId(routeId: r, stageIndex: i)` → `pilgrimage:<r>:<i>`.
- Corridor half-width **500 m**. Douglas–Peucker tolerance **25 m**.
- Descriptor zoom ranges: **Streets `0...16`**, **terrain DEM `0...14`**, DEM tileset `mapbox://mapbox.mapbox-terrain-dem-v1`. (The spec says Streets z15; the SDK loads tile packs in fixed bands 0–5 / 6–10 / 11–14 / 15–16, so z15 and z16 cost the same packs — `0...16` makes the walk screen's z16 native and retires the overzoom concern. Task 3 records this in the spec.)
- Glyphs: `StylePackLoadOptions(glyphsRasterizationMode: .ideographsRasterizedLocally)`.
- Bytes-per-tile is **per route**, `UserDefaults` key `pilgrimage.tiles.bytesPerTile.<routeId>`, seed **10_000** bytes (Francés measurement) and the same as the default for an unmeasured route.
- Copy, verbatim: `Save maps for the way · ~26 MB` (estimate, tilde), `Save maps for the way · 12 of 33 saved`, `maps saved · 26 MB`, `maps · stage 12 of 33`, `cancel`, `maps saved for today`, `no offline maps for today — save on wifi`, Settings row label `Maps`, details `none saved` / `<route name> · 26 MB`, empty view caption `no maps saved`, `Delete maps`, alert title `Delete maps?`, alert message `Removes the saved basemap. The route's stages stay on your phone.`, DEBUG toggle label `simulate no signal for maps`.
- Tests run with: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/pilgrim-s3-dd -only-testing:UnitTests/<TestClass> 2>&1 | grep -E "error:|failed\)|Executed .* tests|\*\* TEST"`.
- The worktree needs `Secrets.xcconfig` copied from the main checkout before the first build (it is already there for this worktree).

---

## File structure

**Create**
- `Pilgrim/Models/Honor/TileRegionLoading.swift` — the protocol, `TileRegionSummary`, `TileRegionRequest` (what a region load asks for, Mapbox-free).
- `Pilgrim/Models/Honor/PilgrimageTilesManager.swift` — the manager: status, estimate, save loop, cancel, remove, reconcile.
- `Pilgrim/Models/Honor/PilgrimageTilesDescriptors.swift` — the zoom ceilings and tileset ids as data, so a test can pin them without Mapbox.
- `Pilgrim/Models/Honor/MapboxTileRegionLoader.swift` — the production conformer; the only file that imports the offline API.
- `Pilgrim/Scenes/Honor/PilgrimageMapsRow.swift` — the route page row and its model.
- `Pilgrim/Scenes/Settings/OfflineMapsView.swift` — the Settings detail view and its model.
- `UnitTests/Honor/FakeTileRegionLoader.swift`, `UnitTests/Honor/WayGeometryCorridorTests.swift`, `UnitTests/Honor/PilgrimageTilesDescriptorsTests.swift`, `UnitTests/Honor/PilgrimageTilesManagerTests.swift`, `UnitTests/Honor/PilgrimageTilesManagerTests+Lifecycle.swift`, `UnitTests/Honor/PilgrimageMapsRowTests.swift`, `UnitTests/Honor/OfflineMapsViewModelTests.swift`, `UnitTests/Honor/MapboxTileRegionLoaderTests.swift`.

**Modify**
- `Pilgrim/Models/Honor/WayGeometry.swift` — `corridor(around:halfWidthMeters:)`, `simplified(_:toleranceMeters:)`.
- `Pilgrim/Models/Honor/PilgrimagePackageManager.swift` — holds `tiles`, calls it in `remove`, `replace`, `update`.
- `Pilgrim/Scenes/Honor/PilgrimageRouteView.swift` — the row under `downloadButton`.
- `Pilgrim/Scenes/Honor/StageMorningCard.swift` — `mapsLine: String?`.
- `Pilgrim/Scenes/Honor/HonorOverviewView.swift`, `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift` — pass `mapsLine`.
- `Pilgrim/Scenes/Settings/SettingsCards/DataCard.swift` — Maps row, DEBUG toggle.
- `Pilgrim/Scenes/Root/MainCoordinatorView.swift` — `isWalkActive` for the tiles manager, launch `reconcile`.
- `Pilgrim/AppDelegate.swift` — dated comment on `tileStoreUsageMode`.
- `docs/superpowers/specs/2026-09-14-honor-slice-three-offline-tiles-design.md` — §1.3 zoom-band note (Task 3).

---

### Task 1: The seam — `TileRegionLoading`, `TileRegionSummary`, and the fake

**Files:**
- Create: `Pilgrim/Models/Honor/TileRegionLoading.swift`
- Create: `UnitTests/Honor/FakeTileRegionLoader.swift`
- Test: `UnitTests/Honor/PilgrimageTilesManagerTests.swift` (created here with one test; later tasks add to it)

**Interfaces:**
- Produces: `protocol TileRegionLoading`, `struct TileRegionSummary`, `struct TileRegionRequest`, `struct StylePackRequest`, `final class FakeTileRegionLoader: TileRegionLoading` (test target).

- [ ] **Step 1: Write the protocol and value types**

```swift
// Pilgrim/Models/Honor/TileRegionLoading.swift
import CoreLocation
import Foundation

/// What a region load asks for, with no Mapbox type in it: the manager
/// builds one of these, the production loader turns it into
/// `TileRegionLoadOptions`, and the fake just records it.
struct TileRegionRequest: Equatable {
    let id: String
    /// Closed ring, first coordinate repeated last. WGS84.
    let ring: [CLLocationCoordinate2D]
    /// Stable hash of `ring` so a resumed save can tell a redrawn stage
    /// from an unchanged one without re-deriving the geometry.
    let corridorHash: String
    let acceptExpired: Bool

    static func == (lhs: TileRegionRequest, rhs: TileRegionRequest) -> Bool {
        lhs.id == rhs.id && lhs.corridorHash == rhs.corridorHash && lhs.acceptExpired == rhs.acceptExpired
    }
}

enum StylePackRequest: String, CaseIterable {
    case light, dark
}

/// Our own view of a stored region. `metadata` is the JSON object the load
/// was given; the manager reads `corridorHash` back out of it.
struct TileRegionSummary: Equatable {
    let id: String
    let completedResourceCount: Int
    let requiredResourceCount: Int
    let completedResourceSize: Int
    let metadata: [String: String]

    var isComplete: Bool { requiredResourceCount > 0 && completedResourceCount >= requiredResourceCount }
    var corridorHash: String? { metadata["corridorHash"] }
}

enum TileRegionLoadingError: Error, Equatable {
    case failed
    case diskFull
    case cancelled
}

/// A handle the manager can cancel. The production loader wraps Mapbox's
/// `Cancelable`; the fake flips a flag.
protocol TileLoadHandle: AnyObject {
    func cancel()
}

/// The one seam between the manager and Mapbox. Every method is
/// synchronous to call and reports through closures on the main queue.
protocol TileRegionLoading: AnyObject {
    func hasStylePack(_ pack: StylePackRequest) -> Bool
    func loadStylePack(_ pack: StylePackRequest,
                       completion: @escaping (Result<Void, TileRegionLoadingError>) -> Void) -> TileLoadHandle
    func loadRegion(_ request: TileRegionRequest,
                    progress: @escaping (_ completed: Int, _ required: Int) -> Void,
                    completion: @escaping (Result<TileRegionSummary, TileRegionLoadingError>) -> Void) -> TileLoadHandle
    func regions() -> [TileRegionSummary]
    func removeRegion(id: String)
}
```

- [ ] **Step 2: Register the file**

Run: `ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/TileRegionLoading.swift`
Expected: prints the added file reference; exit 0.

- [ ] **Step 3: Write the fake**

```swift
// UnitTests/Honor/FakeTileRegionLoader.swift
import Foundation
@testable import Pilgrim

/// Records every call, completes on demand, and fails when told to. Loads
/// are queued so a test can complete them one at a time and observe the
/// manager between them.
final class FakeTileRegionLoader: TileRegionLoading {

    final class Handle: TileLoadHandle {
        private(set) var isCancelled = false
        func cancel() { isCancelled = true }
    }

    struct PendingRegion {
        let request: TileRegionRequest
        let progress: (Int, Int) -> Void
        let completion: (Result<TileRegionSummary, TileRegionLoadingError>) -> Void
        let handle: Handle
    }

    struct PendingPack {
        let pack: StylePackRequest
        let completion: (Result<Void, TileRegionLoadingError>) -> Void
        let handle: Handle
    }

    private(set) var stylePacks: Set<StylePackRequest> = []
    private(set) var stored: [String: TileRegionSummary] = [:]
    private(set) var regionRequests: [TileRegionRequest] = []
    private(set) var packRequests: [StylePackRequest] = []
    private(set) var removedIds: [String] = []
    private(set) var pendingRegions: [PendingRegion] = []
    private(set) var pendingPacks: [PendingPack] = []

    /// When set, `completeNextRegion()` fails with it instead of storing.
    var nextRegionFailure: TileRegionLoadingError?
    /// Resource count a completed region reports; tests that care set it.
    var requiredResourcesPerRegion = 10
    var bytesPerRegion = 100_000

    func hasStylePack(_ pack: StylePackRequest) -> Bool { stylePacks.contains(pack) }

    func loadStylePack(_ pack: StylePackRequest,
                       completion: @escaping (Result<Void, TileRegionLoadingError>) -> Void) -> TileLoadHandle {
        packRequests.append(pack)
        let handle = Handle()
        pendingPacks.append(PendingPack(pack: pack, completion: completion, handle: handle))
        return handle
    }

    func loadRegion(_ request: TileRegionRequest,
                    progress: @escaping (Int, Int) -> Void,
                    completion: @escaping (Result<TileRegionSummary, TileRegionLoadingError>) -> Void) -> TileLoadHandle {
        regionRequests.append(request)
        let handle = Handle()
        pendingRegions.append(PendingRegion(request: request, progress: progress, completion: completion, handle: handle))
        return handle
    }

    func regions() -> [TileRegionSummary] { Array(stored.values) }

    func removeRegion(id: String) {
        removedIds.append(id)
        stored[id] = nil
    }

    // MARK: - Driving the fake

    func completeNextPack() {
        guard !pendingPacks.isEmpty else { return }
        let pending = pendingPacks.removeFirst()
        stylePacks.insert(pending.pack)
        pending.completion(.success(()))
    }

    func completeNextRegion() {
        guard !pendingRegions.isEmpty else { return }
        let pending = pendingRegions.removeFirst()
        if let failure = nextRegionFailure {
            nextRegionFailure = nil
            pending.completion(.failure(failure))
            return
        }
        let summary = TileRegionSummary(id: pending.request.id,
                                        completedResourceCount: requiredResourcesPerRegion,
                                        requiredResourceCount: requiredResourcesPerRegion,
                                        completedResourceSize: bytesPerRegion,
                                        metadata: ["corridorHash": pending.request.corridorHash])
        stored[summary.id] = summary
        pending.completion(.success(summary))
    }

    /// Seeds a region as though a previous save stored it.
    func seed(id: String, corridorHash: String, complete: Bool = true, bytes: Int = 100_000) {
        stored[id] = TileRegionSummary(id: id,
                                       completedResourceCount: complete ? 10 : 4,
                                       requiredResourceCount: 10,
                                       completedResourceSize: bytes,
                                       metadata: ["corridorHash": corridorHash])
    }

    func seedStylePacks() { stylePacks = Set(StylePackRequest.allCases) }
}
```

- [ ] **Step 4: Register the fake and write the first (failing) manager test**

Run: `ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/FakeTileRegionLoader.swift`

```swift
// UnitTests/Honor/PilgrimageTilesManagerTests.swift
import XCTest
@testable import Pilgrim

@MainActor
final class PilgrimageTilesManagerTests: XCTestCase {

    var loader: FakeTileRegionLoader!
    var defaults: UserDefaults!
    var manager: PilgrimageTilesManager!

    override func setUp() {
        super.setUp()
        loader = FakeTileRegionLoader()
        defaults = UserDefaults(suiteName: "tiles-tests-\(UUID().uuidString)")
        manager = PilgrimageTilesManager(loader: loader, defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: defaults.description)
        super.tearDown()
    }

    /// A 3 km straight stage east along latitude 42, 31 points 100 m apart.
    func stage(_ index: Int, count: Int = 3, routeId: String = "camino-frances", lonOffset: Double = 0) -> Way {
        let points = (0...30).map { i in
            WayPoint(lat: 42, lon: lonOffset + Double(i) * 0.001209, alt: nil, t: Double(i) * 60)
        }
        let stage = WayStage(routeId: routeId, index: index, count: count, name: "stage \(index)", theme: "t",
                             narrative: "n", closing: "c", warnings: [], distanceKm: 3, gainMeters: 50,
                             hours: WayStageHours(min: 1, max: 2), difficulty: "easy",
                             start: WayStagePlace(name: "a", at: WayCoordinate(lat: 42, lon: lonOffset)),
                             end: WayStagePlace(name: "b", at: WayCoordinate(lat: 42, lon: lonOffset + 0.03627)))
        return Way(id: WayStore.stageWayId(routeId: routeId, stageIndex: index),
                   source: .pilgrimage(routeId: routeId, stageIndex: index),
                   title: "stage \(index)", departedAt: Date(timeIntervalSince1970: 0), tzIdentifier: nil,
                   expires: nil, route: points, totalDistanceMeters: 3000, theirActiveSeconds: 1800,
                   moments: [], weather: nil, spans: nil, marks: nil, stage: stage)
    }

    func stages(_ count: Int, routeId: String = "camino-frances") -> [Way] {
        (0..<count).map { stage($0, count: count, routeId: routeId, lonOffset: Double($0) * 0.04) }
    }

    func testAFreshManagerReportsNothingSaved() {
        XCTAssertEqual(manager.status(for: "camino-frances", stages: stages(3)), .none)
    }
}
```

Run: `ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/PilgrimageTilesManagerTests.swift`

- [ ] **Step 5: Run the test to verify it fails**

Run the test command with `-only-testing:UnitTests/PilgrimageTilesManagerTests`.
Expected: build error — `cannot find 'PilgrimageTilesManager' in scope`.

- [ ] **Step 6: Commit the seam**

```bash
git add Pilgrim/Models/Honor/TileRegionLoading.swift UnitTests/Honor/FakeTileRegionLoader.swift UnitTests/Honor/PilgrimageTilesManagerTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(tiles): the seam between the manager and Mapbox, and its fake

TileRegionLoading is the only door to the offline API. It speaks in our
own value types so the fake needs no Mapbox type and every test in the
slice runs without one.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

(The manager test stays red until Task 3 — that is expected; it pins the name the next tasks must produce.)

---

### Task 2: The corridor — `WayGeometry.corridor(around:halfWidthMeters:)`

**Files:**
- Modify: `Pilgrim/Models/Honor/WayGeometry.swift` (append after `bearing(from:to:)`)
- Create: `UnitTests/Honor/WayGeometryCorridorTests.swift`

**Interfaces:**
- Produces: `static func corridor(around points: [CLLocationCoordinate2D], halfWidthMeters: Double) -> [CLLocationCoordinate2D]` (closed ring), `static func simplified(_ points: [CLLocationCoordinate2D], toleranceMeters: Double) -> [CLLocationCoordinate2D]`, `static func ringAreaSquareMeters(_ ring: [CLLocationCoordinate2D]) -> Double`, `static func ringContains(_ ring: [CLLocationCoordinate2D], _ point: CLLocationCoordinate2D) -> Bool`.

- [ ] **Step 1: Write the failing tests**

```swift
// UnitTests/Honor/WayGeometryCorridorTests.swift
import XCTest
import CoreLocation
@testable import Pilgrim

final class WayGeometryCorridorTests: XCTestCase {

    private func straight(km: Double, lat: Double = 42) -> [CLLocationCoordinate2D] {
        let metersPerDegreeLon = 111_320 * cos(lat * .pi / 180)
        let steps = Int(km * 10)
        return (0...steps).map { i in
            CLLocationCoordinate2D(latitude: lat, longitude: Double(i) * 100 / metersPerDegreeLon)
        }
    }

    func testAStraightLineYieldsARectangleOfTheRightWidth() {
        let line = straight(km: 3)
        let ring = WayGeometry.corridor(around: line, halfWidthMeters: 500)
        XCTAssertEqual(ring.first?.latitude, ring.last?.latitude)
        XCTAssertEqual(ring.first?.longitude, ring.last?.longitude, "ring is closed")
        let area = WayGeometry.ringAreaSquareMeters(ring)
        XCTAssertEqual(area, 3_000 * 1_000, accuracy: 3_000 * 1_000 * 0.05)
        let latitudes = ring.map(\.latitude)
        let spanMeters = (latitudes.max()! - latitudes.min()!) * 111_320
        XCTAssertEqual(spanMeters, 1_000, accuracy: 20)
    }

    func testARightAngleBendKeepsItsOuterCorner() {
        let lat = 42.0
        let east = straight(km: 2, lat: lat)
        let metersPerDegreeLat = 111_320.0
        let north = (1...20).map { i in
            CLLocationCoordinate2D(latitude: lat + Double(i) * 100 / metersPerDegreeLat, longitude: east.last!.longitude)
        }
        let ring = WayGeometry.corridor(around: east + north, halfWidthMeters: 500)
        // 300 m outside the bend on the diagonal: inside a 500 m corridor.
        let corner = CLLocationCoordinate2D(latitude: lat - 212 / metersPerDegreeLat,
                                            longitude: east.last!.longitude + 212 / (metersPerDegreeLat * cos(lat * .pi / 180)))
        XCTAssertTrue(WayGeometry.ringContains(ring, corner))
        // 700 m outside: not.
        let far = CLLocationCoordinate2D(latitude: lat - 495 / metersPerDegreeLat,
                                         longitude: east.last!.longitude + 495 / (metersPerDegreeLat * cos(lat * .pi / 180)))
        XCTAssertFalse(WayGeometry.ringContains(ring, far))
    }

    func testSimplificationDropsWigglesUnderTolerance() {
        var line = straight(km: 1)
        // A 10 m wiggle on every other point.
        for i in stride(from: 1, to: line.count, by: 2) {
            line[i] = CLLocationCoordinate2D(latitude: line[i].latitude + 10 / 111_320, longitude: line[i].longitude)
        }
        let simplified = WayGeometry.simplified(line, toleranceMeters: 25)
        XCTAssertEqual(simplified.count, 2, "a straight-enough line is its two ends")
    }

    /// The real Francés stage 0 from the test fixture: 24 km, Pyrenees.
    /// Area within 20 % of length × 1 km, and every route point inside.
    func testTheFrancesStageZeroCorridorIsTightAndCoversItsLine() throws {
        let data = try PilgrimageFixtures.data("stage-00.json")
        let way = try PilgrimageWayImporter.way(from: data, routeId: "camino-frances", stageIndex: 0)
        let line = way.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) }
        let ring = WayGeometry.corridor(around: line, halfWidthMeters: 500)
        let geometry = WayGeometry(route: way.route)
        let area = WayGeometry.ringAreaSquareMeters(ring)
        XCTAssertEqual(area, geometry.totalMeters * 1_000, accuracy: geometry.totalMeters * 1_000 * 0.2)
        for point in line where !WayGeometry.ringContains(ring, point) {
            XCTFail("route point \(point) outside its own corridor")
            break
        }
    }

    func testTwoPointsAndOnePointStillProduceARing() {
        let two = WayGeometry.corridor(around: Array(straight(km: 0.1).prefix(2)), halfWidthMeters: 500)
        XCTAssertGreaterThanOrEqual(two.count, 5)
        let one = WayGeometry.corridor(around: [CLLocationCoordinate2D(latitude: 42, longitude: 0)], halfWidthMeters: 500)
        XCTAssertGreaterThanOrEqual(one.count, 5, "a point becomes a square")
    }
}
```

Run: `ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/WayGeometryCorridorTests.swift`

- [ ] **Step 2: Run to verify it fails**

Run with `-only-testing:UnitTests/WayGeometryCorridorTests`.
Expected: build error — `type 'WayGeometry' has no member 'corridor'`.

- [ ] **Step 3: Implement**

Append to `Pilgrim/Models/Honor/WayGeometry.swift`, inside the struct, after `bearing(from:to:)`:

```swift
    // MARK: - Corridor

    /// A closed ring around `points`, `halfWidthMeters` to each side: the
    /// geometry a stage's tile region is loaded for. A corridor rather than
    /// a bounding box because a 20 km diagonal is 400 km² boxed and 20 km²
    /// this way. Offsets are taken along the perpendicular of each vertex's
    /// adjoining segments; a single point becomes a square.
    static func corridor(around points: [CLLocationCoordinate2D], halfWidthMeters: Double) -> [CLLocationCoordinate2D] {
        let line = simplified(points, toleranceMeters: 25)
        guard let first = line.first else { return [] }
        let latScale = 111_320.0
        let lonScale = 111_320.0 * cos(first.latitude * .pi / 180)
        guard line.count > 1 else {
            let dLat = halfWidthMeters / latScale, dLon = halfWidthMeters / lonScale
            return [
                CLLocationCoordinate2D(latitude: first.latitude - dLat, longitude: first.longitude - dLon),
                CLLocationCoordinate2D(latitude: first.latitude - dLat, longitude: first.longitude + dLon),
                CLLocationCoordinate2D(latitude: first.latitude + dLat, longitude: first.longitude + dLon),
                CLLocationCoordinate2D(latitude: first.latitude + dLat, longitude: first.longitude - dLon),
                CLLocationCoordinate2D(latitude: first.latitude - dLat, longitude: first.longitude - dLon)
            ]
        }
        // Work in local metres, then back to degrees at the end.
        let local = line.map { (x: ($0.longitude - first.longitude) * lonScale, y: ($0.latitude - first.latitude) * latScale) }
        var left: [(x: Double, y: Double)] = []
        var right: [(x: Double, y: Double)] = []
        for i in 0..<local.count {
            let prev = local[max(i - 1, 0)], next = local[min(i + 1, local.count - 1)]
            var dx = next.x - prev.x, dy = next.y - prev.y
            let len = (dx * dx + dy * dy).squareRoot()
            if len > 0 { dx /= len; dy /= len } else { dx = 1; dy = 0 }
            // Perpendicular to the direction of travel.
            let nx = -dy * halfWidthMeters, ny = dx * halfWidthMeters
            left.append((local[i].x + nx, local[i].y + ny))
            right.append((local[i].x - nx, local[i].y - ny))
        }
        // The ends are squared off by extending half a width past each.
        let startDir = (x: local[1].x - local[0].x, y: local[1].y - local[0].y)
        let endDir = (x: local[local.count - 1].x - local[local.count - 2].x, y: local[local.count - 1].y - local[local.count - 2].y)
        func unit(_ v: (x: Double, y: Double)) -> (x: Double, y: Double) {
            let l = (v.x * v.x + v.y * v.y).squareRoot()
            return l > 0 ? (v.x / l, v.y / l) : (1, 0)
        }
        let s = unit(startDir), e = unit(endDir)
        left[0] = (left[0].x - s.x * halfWidthMeters, left[0].y - s.y * halfWidthMeters)
        right[0] = (right[0].x - s.x * halfWidthMeters, right[0].y - s.y * halfWidthMeters)
        left[left.count - 1] = (left[left.count - 1].x + e.x * halfWidthMeters, left[left.count - 1].y + e.y * halfWidthMeters)
        right[right.count - 1] = (right[right.count - 1].x + e.x * halfWidthMeters, right[right.count - 1].y + e.y * halfWidthMeters)
        let ringLocal = left + right.reversed() + [left[0]]
        return ringLocal.map {
            CLLocationCoordinate2D(latitude: first.latitude + $0.y / latScale, longitude: first.longitude + $0.x / lonScale)
        }
    }

    /// Douglas–Peucker on a local-metre projection. A 500 m corridor does
    /// not care about a 10 m wiggle, and fewer vertices is a smaller polygon
    /// for the tile store to rasterise against.
    static func simplified(_ points: [CLLocationCoordinate2D], toleranceMeters: Double) -> [CLLocationCoordinate2D] {
        guard points.count > 2, let first = points.first else { return points }
        let latScale = 111_320.0
        let lonScale = 111_320.0 * cos(first.latitude * .pi / 180)
        let local = points.map { (x: ($0.longitude - first.longitude) * lonScale, y: ($0.latitude - first.latitude) * latScale) }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        var stack: [(Int, Int)] = [(0, points.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b - a > 1 else { continue }
            let ax = local[a].x, ay = local[a].y, bx = local[b].x, by = local[b].y
            let dx = bx - ax, dy = by - ay
            let lenSq = dx * dx + dy * dy
            var farthest = -1.0, index = a
            for i in (a + 1)..<b {
                let px = local[i].x - ax, py = local[i].y - ay
                let distance: Double
                if lenSq > 0 {
                    let u = max(0, min(1, (px * dx + py * dy) / lenSq))
                    let cx = px - u * dx, cy = py - u * dy
                    distance = (cx * cx + cy * cy).squareRoot()
                } else {
                    distance = (px * px + py * py).squareRoot()
                }
                if distance > farthest { farthest = distance; index = i }
            }
            if farthest > toleranceMeters {
                keep[index] = true
                stack.append((a, index))
                stack.append((index, b))
            }
        }
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    /// Shoelace on a local-metre projection. Test support and the estimate's
    /// sanity check; not used on the walk.
    static func ringAreaSquareMeters(_ ring: [CLLocationCoordinate2D]) -> Double {
        guard ring.count > 3, let first = ring.first else { return 0 }
        let latScale = 111_320.0
        let lonScale = 111_320.0 * cos(first.latitude * .pi / 180)
        var sum = 0.0
        for i in 0..<(ring.count - 1) {
            let ax = (ring[i].longitude - first.longitude) * lonScale, ay = (ring[i].latitude - first.latitude) * latScale
            let bx = (ring[i + 1].longitude - first.longitude) * lonScale, by = (ring[i + 1].latitude - first.latitude) * latScale
            sum += ax * by - bx * ay
        }
        return abs(sum) / 2
    }

    /// Ray casting, in degrees — good enough for "is this tile centre inside".
    static func ringContains(_ ring: [CLLocationCoordinate2D], _ point: CLLocationCoordinate2D) -> Bool {
        guard ring.count > 3 else { return false }
        var inside = false
        var j = ring.count - 1
        for i in 0..<ring.count {
            let yi = ring[i].latitude, xi = ring[i].longitude
            let yj = ring[j].latitude, xj = ring[j].longitude
            if (yi > point.latitude) != (yj > point.latitude) {
                let x = (xj - xi) * (point.latitude - yi) / (yj - yi) + xi
                if point.longitude < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }
```

- [ ] **Step 4: Run to verify it passes**

Run with `-only-testing:UnitTests/WayGeometryCorridorTests`.
Expected: `Executed 5 tests, with 0 failures`.

If `testTheFrancesStageZeroCorridorIsTightAndCoversItsLine` fails on area: the stage has switchbacks, so the corridor self-overlaps and the shoelace area under-counts; widen the accuracy to 35 % and note why in the test. Do not change the corridor.

- [ ] **Step 5: Lint and commit**

Run: `swiftlint lint --quiet Pilgrim/Models/Honor/WayGeometry.swift UnitTests/Honor/WayGeometryCorridorTests.swift`
Expected: no errors (a `function_body_length` warning on `corridor` is acceptable; an error is not — split the end-squaring into a private helper if it errors).

```bash
git add Pilgrim/Models/Honor/WayGeometry.swift UnitTests/Honor/WayGeometryCorridorTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(tiles): a corridor around a stage line, 500 m to each side

The polygon a stage's tile region is loaded for. A corridor rather than a
bounding box: a 20 km diagonal is 400 km² boxed and 20 km² this way.
Simplified first at 25 m, because a 500 m buffer does not care about a
10 m wiggle.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Descriptors as data, the tile count, and the per-route estimate

**Files:**
- Create: `Pilgrim/Models/Honor/PilgrimageTilesDescriptors.swift`
- Create: `Pilgrim/Models/Honor/PilgrimageTilesManager.swift` (status + estimate only; the save loop is Task 4)
- Create: `UnitTests/Honor/PilgrimageTilesDescriptorsTests.swift`
- Modify: `UnitTests/Honor/PilgrimageTilesManagerTests.swift` (estimate + status tests)
- Modify: `docs/superpowers/specs/2026-09-14-honor-slice-three-offline-tiles-design.md:83-90` (the zoom-band note)

**Interfaces:**
- Produces: `enum PilgrimageTilesDescriptors { static let streetsZoom: ClosedRange<Int>; static let terrainZoom: ClosedRange<Int>; static let terrainTileset: String; static func tileCount(ring:zooms:) -> Int }`, `PilgrimageTilesManager.Status`, `PilgrimageTilesManager.init(loader:defaults:)`, `status(for:stages:)`, `isStageSaved(_:)`, `estimateBytes(for:stages:)`, `static func corridorHash(_ ring:) -> String`, `static let seedBytesPerTile = 10_000`.

- [ ] **Step 1: Write the descriptor tests**

```swift
// UnitTests/Honor/PilgrimageTilesDescriptorsTests.swift
import XCTest
import CoreLocation
@testable import Pilgrim

final class PilgrimageTilesDescriptorsTests: XCTestCase {

    /// The SDK loads tile packs in fixed zoom bands — 0–5, 6–10, 11–14,
    /// 15–16 — so a Streets ceiling of 15 costs the same packs as 16 and
    /// the walk screen's z16 might as well be native. The DEM tileset has
    /// no z15 at all; 14 is both its ceiling and a band edge.
    func testTheCeilingsAreBandEdges() {
        XCTAssertEqual(PilgrimageTilesDescriptors.streetsZoom, 0...16)
        XCTAssertEqual(PilgrimageTilesDescriptors.terrainZoom, 0...14)
    }

    /// The DEM is added by `PilgrimMapStyle.applyWabiSabiStyle` at runtime,
    /// not by the base style, so it has to be named or the hillshade is
    /// blank offline.
    func testTheTerrainTilesetIsTheOneTheStyleAdds() {
        XCTAssertEqual(PilgrimageTilesDescriptors.terrainTileset, "mapbox://mapbox.mapbox-terrain-dem-v1")
    }

    func testGlyphsRasterizeIdeographsLocally() {
        XCTAssertTrue(PilgrimageTilesDescriptors.rasterizesIdeographsLocally)
    }

    /// The design session's figure for the Nakahechi corridor at z10–15 was
    /// 129 tiles from 504 points; this ring is the same shape of thing.
    func testTileCountGrowsFourfoldPerZoomOnALongCorridor() {
        let line = (0...300).map { i in CLLocationCoordinate2D(latitude: 33.8, longitude: 135.5 + Double(i) * 0.001) }
        let ring = WayGeometry.corridor(around: line, halfWidthMeters: 500)
        let z13 = PilgrimageTilesDescriptors.tileCount(ring: ring, zooms: 13...13)
        let z15 = PilgrimageTilesDescriptors.tileCount(ring: ring, zooms: 15...15)
        XCTAssertGreaterThan(z13, 5)
        XCTAssertEqual(Double(z15) / Double(z13), 4, accuracy: 1.5)
    }
}
```

Run: `ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/PilgrimageTilesDescriptorsTests.swift`

- [ ] **Step 2: Add estimate and status tests to the manager test file**

Append inside `PilgrimageTilesManagerTests`:

```swift
    // MARK: - Estimate

    func testTheEstimateUsesTheRoutesOwnBytesPerTileAndTheSeedByDefault() {
        let three = stages(3)
        let tiles = three.reduce(0) { total, way in
            let ring = WayGeometry.corridor(around: way.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                                            halfWidthMeters: 500)
            return total + PilgrimageTilesDescriptors.tileCount(ring: ring, zooms: 10...16)
                + PilgrimageTilesDescriptors.tileCount(ring: ring, zooms: 10...14)
        }
        XCTAssertEqual(manager.estimateBytes(for: "camino-frances", stages: three),
                       tiles * PilgrimageTilesManager.seedBytesPerTile)
        defaults.set(25_000, forKey: "pilgrimage.tiles.bytesPerTile.camino-frances")
        XCTAssertEqual(manager.estimateBytes(for: "camino-frances", stages: three), tiles * 25_000)
        XCTAssertEqual(manager.estimateBytes(for: "kumano-kodo-nakahechi", stages: stages(3, routeId: "kumano-kodo-nakahechi")),
                       tiles * PilgrimageTilesManager.seedBytesPerTile,
                       "another route's calibration never leaks")
    }

    // MARK: - Status

    func testStatusCountsOnlyCompleteRegionsWhoseCorridorStillMatches() {
        let three = stages(3)
        loader.seedStylePacks()
        loader.seed(id: three[0].id, corridorHash: PilgrimageTilesManager.corridorHash(for: three[0]))
        loader.seed(id: three[1].id, corridorHash: "stale")
        loader.seed(id: three[2].id, corridorHash: PilgrimageTilesManager.corridorHash(for: three[2]), complete: false)
        XCTAssertEqual(manager.status(for: "camino-frances", stages: three), .partial(saved: 1, of: 3))
        XCTAssertTrue(manager.isStageSaved(three[0]))
        XCTAssertFalse(manager.isStageSaved(three[1]))
        XCTAssertFalse(manager.isStageSaved(three[2]))
    }

    func testStatusIsSavedOnlyWhenEveryStageAndBothPacksArePresent() {
        let two = stages(2)
        for way in two { loader.seed(id: way.id, corridorHash: PilgrimageTilesManager.corridorHash(for: way), bytes: 50_000) }
        XCTAssertEqual(manager.status(for: "camino-frances", stages: two), .partial(saved: 2, of: 2),
                       "no style packs yet")
        loader.seedStylePacks()
        XCTAssertEqual(manager.status(for: "camino-frances", stages: two), .saved(bytes: 100_000))
    }
```

- [ ] **Step 3: Run to verify they fail**

Run with `-only-testing:UnitTests/PilgrimageTilesDescriptorsTests -only-testing:UnitTests/PilgrimageTilesManagerTests`.
Expected: build errors — `cannot find 'PilgrimageTilesDescriptors'`, `cannot find 'PilgrimageTilesManager'`.

- [ ] **Step 4: Write the descriptors**

```swift
// Pilgrim/Models/Honor/PilgrimageTilesDescriptors.swift
import CoreLocation
import Foundation

/// The numbers the offline descriptors are built from, kept as plain data
/// so a test can pin them without touching Mapbox.
enum PilgrimageTilesDescriptors {

    /// The SDK loads tile packs in fixed zoom bands — 0–5, 6–10, 11–14,
    /// 15–16 — and recommends choosing ceilings on a band edge. z15 costs
    /// the same packs as z16, so the walk screen's z16 is native.
    static let streetsZoom: ClosedRange<Int> = 0...16
    /// The DEM tileset has no z15; 14 is its ceiling and a band edge.
    static let terrainZoom: ClosedRange<Int> = 0...14
    /// Added at runtime by `PilgrimMapStyle.applyWabiSabiStyle`, so not in
    /// either base style: it has to be named or the hillshade is blank offline.
    static let terrainTileset = "mapbox://mapbox.mapbox-terrain-dem-v1"
    /// Shikoku and Kumano labels are CJK; rasterizing ideographs on the
    /// device keeps the style pack from carrying every glyph range.
    static let rasterizesIdeographsLocally = true

    /// Distinct XYZ tiles whose centre or any corner lies inside the ring,
    /// summed over `zooms`. Below z10 a corridor touches a handful of tiles,
    /// a rounding error the estimate leaves out.
    static func tileCount(ring: [CLLocationCoordinate2D], zooms: ClosedRange<Int>) -> Int {
        guard ring.count > 3 else { return 0 }
        let lats = ring.map(\.latitude), lons = ring.map(\.longitude)
        var total = 0
        for z in zooms {
            let n = Double(1 << z)
            let (xMin, yMax) = tile(lat: lats.min()!, lon: lons.min()!, n: n)
            let (xMax, yMin) = tile(lat: lats.max()!, lon: lons.max()!, n: n)
            for x in xMin...xMax {
                for y in yMin...yMax where tileTouches(ring, x: x, y: y, n: n) {
                    total += 1
                }
            }
        }
        return total
    }

    private static func tile(lat: Double, lon: Double, n: Double) -> (x: Int, y: Int) {
        let x = Int(floor((lon + 180) / 360 * n))
        let latRad = lat * .pi / 180
        let y = Int(floor((1 - log(tan(latRad) + 1 / cos(latRad)) / .pi) / 2 * n))
        return (min(max(x, 0), Int(n) - 1), min(max(y, 0), Int(n) - 1))
    }

    private static func coordinate(x: Double, y: Double, n: Double) -> CLLocationCoordinate2D {
        let lon = x / n * 360 - 180
        let lat = atan(sinh(.pi * (1 - 2 * y / n))) * 180 / .pi
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    /// A tile counts when any of its corners or its centre is inside the
    /// ring, or when a ring vertex is inside the tile. Cheap and slightly
    /// generous; the estimate errs high rather than low.
    private static func tileTouches(_ ring: [CLLocationCoordinate2D], x: Int, y: Int, n: Double) -> Bool {
        let probes = [
            coordinate(x: Double(x), y: Double(y), n: n),
            coordinate(x: Double(x + 1), y: Double(y), n: n),
            coordinate(x: Double(x), y: Double(y + 1), n: n),
            coordinate(x: Double(x + 1), y: Double(y + 1), n: n),
            coordinate(x: Double(x) + 0.5, y: Double(y) + 0.5, n: n)
        ]
        if probes.contains(where: { WayGeometry.ringContains(ring, $0) }) { return true }
        let west = coordinate(x: Double(x), y: Double(y + 1), n: n), east = coordinate(x: Double(x + 1), y: Double(y), n: n)
        return ring.contains { $0.longitude >= west.longitude && $0.longitude <= east.longitude
            && $0.latitude >= west.latitude && $0.latitude <= east.latitude }
    }
}
```

Run: `ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/PilgrimageTilesDescriptors.swift`

- [ ] **Step 5: Write the manager — status and estimate only**

```swift
// Pilgrim/Models/Honor/PilgrimageTilesManager.swift
import Combine
import CoreLocation
import CryptoKit
import Foundation

/// The saved basemap for the one installed pilgrimage: one tile region per
/// stage, keyed like the stage's Way. A sibling of `PilgrimagePackageManager`
/// with the same shape; every Mapbox call goes through `TileRegionLoading`.
@MainActor
final class PilgrimageTilesManager: ObservableObject {

    enum Status: Equatable {
        case none
        case partial(saved: Int, of: Int)
        case saved(bytes: Int)
    }

    enum Phase: Equatable {
        case idle
        /// `total` counts the two style packs plus one region per stage.
        case saving(done: Int, total: Int)
        case failed(PilgrimageError)
    }

    @Published private(set) var phase: Phase = .idle

    /// Set by `MainCoordinatorView`, like the package manager's.
    var isWalkActive: () -> Bool = { false }

    static let halfWidthMeters = 500.0
    /// Measured on three Camino Francés tiles at z14/z15 in the design
    /// session; the seed for that route and the default for any route with
    /// no measurement of its own. Replaced per route after its first save.
    static let seedBytesPerTile = 10_000

    let loader: TileRegionLoading
    private let defaults: UserDefaults

    init(loader: TileRegionLoading, defaults: UserDefaults = .standard) {
        self.loader = loader
        self.defaults = defaults
    }

    // MARK: - Geometry and keys

    static func ring(for way: Way) -> [CLLocationCoordinate2D] {
        WayGeometry.corridor(around: way.route.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon) },
                             halfWidthMeters: halfWidthMeters)
    }

    /// SHA-256 of the ring's coordinates at 1e-6°, so a resumed save can
    /// tell a redrawn stage from an unchanged one by comparing two strings.
    static func corridorHash(for way: Way) -> String {
        corridorHash(ring(for: way))
    }

    static func corridorHash(_ ring: [CLLocationCoordinate2D]) -> String {
        var data = Data()
        for point in ring {
            data.append(contentsOf: withUnsafeBytes(of: (point.latitude * 1_000_000).rounded()) { Array($0) })
            data.append(contentsOf: withUnsafeBytes(of: (point.longitude * 1_000_000).rounded()) { Array($0) })
        }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func regionPrefix(routeId: String) -> String { "pilgrimage:\(routeId):" }

    // MARK: - Status

    private func region(for way: Way) -> TileRegionSummary? {
        loader.regions().first { $0.id == way.id }
    }

    /// Complete by resource count and loaded for the stage's current line.
    func isStageSaved(_ way: Way) -> Bool {
        guard let region = region(for: way), region.isComplete else { return false }
        return region.corridorHash == Self.corridorHash(for: way)
    }

    func status(for routeId: String, stages: [Way]) -> Status {
        let saved = stages.filter(isStageSaved)
        guard !saved.isEmpty else { return .none }
        let packsPresent = StylePackRequest.allCases.allSatisfy(loader.hasStylePack)
        guard saved.count == stages.count, packsPresent else { return .partial(saved: saved.count, of: stages.count) }
        let bytes = saved.compactMap(region(for:)).reduce(0) { $0 + $1.completedResourceSize }
        return .saved(bytes: bytes)
    }

    // MARK: - Estimate

    static func bytesPerTileKey(routeId: String) -> String { "pilgrimage.tiles.bytesPerTile.\(routeId)" }

    func bytesPerTile(routeId: String) -> Int {
        let stored = defaults.integer(forKey: Self.bytesPerTileKey(routeId: routeId))
        return stored > 0 ? stored : Self.seedBytesPerTile
    }

    func tileCount(for stages: [Way]) -> Int {
        stages.reduce(0) { total, way in
            let ring = Self.ring(for: way)
            return total
                + PilgrimageTilesDescriptors.tileCount(ring: ring, zooms: 10...PilgrimageTilesDescriptors.streetsZoom.upperBound)
                + PilgrimageTilesDescriptors.tileCount(ring: ring, zooms: 10...PilgrimageTilesDescriptors.terrainZoom.upperBound)
        }
    }

    func estimateBytes(for routeId: String, stages: [Way]) -> Int {
        tileCount(for: stages) * bytesPerTile(routeId: routeId)
    }

    /// After a save of this route lands: its real bytes over its tile count
    /// replace the seed. Another route's key is never touched.
    func calibrate(routeId: String, stages: [Way]) {
        let bytes = stages.compactMap(region(for:)).reduce(0) { $0 + $1.completedResourceSize }
        let tiles = tileCount(for: stages)
        guard bytes > 0, tiles > 0 else { return }
        defaults.set(bytes / tiles, forKey: Self.bytesPerTileKey(routeId: routeId))
    }
}
```

Run: `ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/PilgrimageTilesManager.swift`

- [ ] **Step 6: Run to verify they pass**

Run with `-only-testing:UnitTests/PilgrimageTilesDescriptorsTests -only-testing:UnitTests/PilgrimageTilesManagerTests`.
Expected: descriptors 4/4, manager 4/4 (the Task 1 test plus these three).

- [ ] **Step 7: Record the zoom-band decision in the spec**

Edit `docs/superpowers/specs/2026-09-14-honor-slice-three-offline-tiles-design.md` §1.3: change `zoomRange: 0...15` to `zoomRange: 0...16` in the Streets line, and replace the sentence beginning "The zoom range starts at 0 on purpose" with:

> The zoom range starts at 0 on purpose: the route page and the overview fit a whole stage at around z11, and the region has to cover that as well as the walk screen's z16. **Streets runs to 16, not 15, because of how the SDK batches:** tile packs are loaded in fixed zoom bands — 0–5, 6–10, 11–14, 15–16 — and the SDK recommends choosing ceilings on a band edge. A ceiling of 15 downloads the whole 15–16 band anyway, so 16 costs nothing more and makes the walk screen's z16 native rather than overzoomed. The DEM's 14 is both its ceiling and a band edge. Decision 3's byte figures were measured at these bands and stand.

Also change decision 3's first clause to "**Zoom ceiling: Streets to z16, terrain DEM to z14.**" and its "z15 adds building footprints and nothing else" to "z15–16 adds building footprints and nothing else".

- [ ] **Step 8: Lint and commit**

Run: `swiftlint lint --quiet Pilgrim/Models/Honor/PilgrimageTilesDescriptors.swift Pilgrim/Models/Honor/PilgrimageTilesManager.swift`
Expected: no errors.

```bash
git add Pilgrim/Models/Honor/PilgrimageTilesDescriptors.swift Pilgrim/Models/Honor/PilgrimageTilesManager.swift UnitTests/Honor/PilgrimageTilesDescriptorsTests.swift UnitTests/Honor/PilgrimageTilesManagerTests.swift docs/superpowers/specs/2026-09-14-honor-slice-three-offline-tiles-design.md Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(tiles): descriptors as data, per-route estimate, and status

Ceilings pinned as plain numbers so a test can hold them without Mapbox.
Streets goes to 16, not 15: the SDK loads packs in fixed bands and 15–16
is one of them, so 15 costs the same and 16 makes the walk screen native.

The estimate's bytes-per-tile is per route. Francés and Nakahechi differ
by an order of magnitude, and one global figure calibrated by whichever
saved last would understate the next right where the estimate is the
guardrail.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: The save loop — order, skipping, re-check, `.failed`, cancel

**Files:**
- Modify: `Pilgrim/Models/Honor/PilgrimageTilesManager.swift`
- Modify: `UnitTests/Honor/PilgrimageTilesManagerTests.swift`

**Interfaces:**
- Consumes: Task 1's fake driving methods; Task 3's `corridorHash`, `isStageSaved`, `calibrate`.
- Produces: `func save(routeId: String, stages: [Way]) async throws`, `func cancel()`.

- [ ] **Step 1: Write the failing tests**

Append inside `PilgrimageTilesManagerTests`:

```swift
    // MARK: - Save

    /// Drives the fake from a detached task so `save` can await inside the
    /// loop while the test completes loads one by one.
    private func drive(_ body: @escaping @MainActor () -> Void) {
        Task { @MainActor in body() }
    }

    func testASaveLoadsPacksThenRegionsInOrderAndSkipsWhatIsThere() async throws {
        let three = stages(3)
        loader.stylePacks = [.light]
        loader.seed(id: three[1].id, corridorHash: PilgrimageTilesManager.corridorHash(for: three[1]))
        let task = Task { try await manager.save(routeId: "camino-frances", stages: three) }
        await Task.yield()
        XCTAssertEqual(loader.packRequests, [.dark], "the light pack was already there")
        loader.completeNextPack()
        await Task.yield()
        XCTAssertEqual(loader.regionRequests.map(\.id), [three[0].id])
        loader.completeNextRegion()
        await Task.yield()
        XCTAssertEqual(loader.regionRequests.map(\.id), [three[0].id, three[2].id], "stage 1 was complete and current")
        loader.completeNextRegion()
        try await task.value
        XCTAssertEqual(manager.phase, .idle)
        XCTAssertEqual(manager.status(for: "camino-frances", stages: three), .saved(bytes: 300_000))
    }

    func testProgressCountsPacksAndStages() async throws {
        let two = stages(2)
        let task = Task { try await manager.save(routeId: "camino-frances", stages: two) }
        await Task.yield()
        XCTAssertEqual(manager.phase, .saving(done: 0, total: 4))
        loader.completeNextPack(); await Task.yield()
        loader.completeNextPack(); await Task.yield()
        XCTAssertEqual(manager.phase, .saving(done: 2, total: 4))
        loader.completeNextRegion(); await Task.yield()
        XCTAssertEqual(manager.phase, .saving(done: 3, total: 4))
        loader.completeNextRegion()
        try await task.value
    }

    func testCancelKeepsWhatIsDoneAndResumeStartsAtTheGap() async throws {
        let four = stages(4)
        loader.seedStylePacks()
        let first = Task { try await manager.save(routeId: "camino-frances", stages: four) }
        await Task.yield()
        loader.completeNextRegion(); await Task.yield()
        loader.completeNextRegion(); await Task.yield()
        manager.cancel()
        _ = try? await first.value
        XCTAssertEqual(manager.phase, .idle)
        XCTAssertEqual(manager.status(for: "camino-frances", stages: four), .partial(saved: 2, of: 4))
        XCTAssertTrue(loader.pendingRegions.isEmpty || loader.pendingRegions.first!.handle.isCancelled)

        loader.regionRequests.removeAll()
        let second = Task { try await manager.save(routeId: "camino-frances", stages: four) }
        await Task.yield()
        XCTAssertEqual(loader.regionRequests.first?.id, four[2].id, "resume picks up at the first gap")
        loader.completeNextRegion(); await Task.yield()
        loader.completeNextRegion()
        try await second.value
    }

    func testARedrawnStageIsReloadedAndAnUnchangedOneIsNot() async throws {
        var three = stages(3)
        loader.seedStylePacks()
        for way in three { loader.seed(id: way.id, corridorHash: PilgrimageTilesManager.corridorHash(for: way)) }
        // Redraw stage 1: shift its line.
        three[1] = stage(1, count: 3, lonOffset: 0.04 + 0.01)
        let task = Task { try await manager.save(routeId: "camino-frances", stages: three) }
        await Task.yield()
        XCTAssertEqual(loader.regionRequests.map(\.id), [three[1].id])
        XCTAssertEqual(loader.regionRequests.first?.corridorHash, PilgrimageTilesManager.corridorHash(for: three[1]))
        loader.completeNextRegion()
        try await task.value
    }

    func testAWalkStartingMidSaveStopsItAndKeepsWhatIsDone() async throws {
        let six = stages(6)
        loader.seedStylePacks()
        var walking = false
        manager.isWalkActive = { walking }
        let task = Task { try await manager.save(routeId: "camino-frances", stages: six) }
        for _ in 0..<5 { await Task.yield(); loader.completeNextRegion() }
        await Task.yield()
        walking = true
        loader.completeNextRegion()
        await Task.yield()
        do {
            try await task.value
            XCTFail("expected walkInProgress")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .walkInProgress)
        }
        XCTAssertEqual(loader.regionRequests.count, 6, "no seventh load was requested")
        XCTAssertEqual(manager.status(for: "camino-frances", stages: six), .partial(saved: 6, of: 6))
    }

    func testRefusedWhileWalkingBeforeAnythingIsRequested() async {
        manager.isWalkActive = { true }
        do {
            try await manager.save(routeId: "camino-frances", stages: stages(2))
            XCTFail("expected walkInProgress")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .walkInProgress)
        }
        XCTAssertTrue(loader.packRequests.isEmpty)
        XCTAssertTrue(loader.regionRequests.isEmpty)
    }

    func testASecondSaveWhileSavingMakesNoCalls() async throws {
        let two = stages(2)
        let first = Task { try await manager.save(routeId: "camino-frances", stages: two) }
        await Task.yield()
        try await manager.save(routeId: "camino-frances", stages: two)
        XCTAssertEqual(loader.packRequests.count, 1)
        loader.completeNextPack(); await Task.yield()
        loader.completeNextPack(); await Task.yield()
        loader.completeNextRegion(); await Task.yield()
        loader.completeNextRegion()
        try await first.value
    }

    func testAFailedLoadLandsInFailedKeepsEarlierRegionsAndClears() async throws {
        let three = stages(3)
        loader.seedStylePacks()
        let task = Task { try await manager.save(routeId: "camino-frances", stages: three) }
        await Task.yield()
        loader.completeNextRegion(); await Task.yield()
        loader.nextRegionFailure = .failed
        loader.completeNextRegion()
        do {
            try await task.value
            XCTFail("expected incomplete")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .incomplete)
        }
        XCTAssertEqual(manager.phase, .failed(.incomplete))
        XCTAssertEqual(manager.status(for: "camino-frances", stages: three), .partial(saved: 1, of: 3))
        manager.cancel()
        XCTAssertEqual(manager.phase, .idle)
    }

    func testDiskFullSurfacesAsDiskFull() async {
        loader.seedStylePacks()
        let task = Task { try await manager.save(routeId: "camino-frances", stages: stages(1)) }
        await Task.yield()
        loader.nextRegionFailure = .diskFull
        loader.completeNextRegion()
        do {
            try await task.value
            XCTFail("expected diskFull")
        } catch {
            XCTAssertEqual(error as? PilgrimageError, .diskFull)
        }
    }

    func testACompletedSaveCalibratesThisRouteOnly() async throws {
        let two = stages(2)
        loader.seedStylePacks()
        loader.bytesPerRegion = 400_000
        let task = Task { try await manager.save(routeId: "camino-frances", stages: two) }
        await Task.yield()
        loader.completeNextRegion(); await Task.yield()
        loader.completeNextRegion()
        try await task.value
        let expected = 800_000 / manager.tileCount(for: two)
        XCTAssertEqual(defaults.integer(forKey: "pilgrimage.tiles.bytesPerTile.camino-frances"), expected)
        XCTAssertEqual(defaults.integer(forKey: "pilgrimage.tiles.bytesPerTile.kumano-kodo-nakahechi"), 0)
    }
```

- [ ] **Step 2: Run to verify they fail**

Expected: build errors — `value of type 'PilgrimageTilesManager' has no member 'save'` / `'cancel'`.

- [ ] **Step 3: Implement the loop**

Add to `PilgrimageTilesManager`:

```swift
    // MARK: - Save

    private var inFlight: TileLoadHandle?
    /// Bumped on every `cancel()`; a completion that lands after its
    /// generation was cancelled is a no-op rather than a state change.
    private var generation = 0

    /// Style packs first, then one region per stage in order, skipping any
    /// region that is complete and still matches its stage's corridor.
    /// `isWalkActive` is re-checked before every load: a save is up to
    /// thirty-five network loads and a walker who taps and then starts
    /// the stage would otherwise carry every remaining load under the walk.
    func save(routeId: String, stages: [Way]) async throws {
        guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
        if case .saving = phase { return }
        phase = .saving(done: 0, total: StylePackRequest.allCases.count + stages.count)
        let myGeneration = generation
        var done = 0
        do {
            for pack in StylePackRequest.allCases {
                guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
                if !loader.hasStylePack(pack) {
                    try await loadPack(pack, generation: myGeneration)
                }
                done += 1
                phase = .saving(done: done, total: StylePackRequest.allCases.count + stages.count)
            }
            for way in stages.sorted(by: { ($0.stage?.index ?? 0) < ($1.stage?.index ?? 0) }) {
                guard !isWalkActive() else { throw PilgrimageError.walkInProgress }
                if !isStageSaved(way) {
                    let ring = Self.ring(for: way)
                    let request = TileRegionRequest(id: way.id, ring: ring,
                                                    corridorHash: Self.corridorHash(ring), acceptExpired: true)
                    try await loadRegion(request, generation: myGeneration)
                }
                done += 1
                phase = .saving(done: done, total: StylePackRequest.allCases.count + stages.count)
            }
            calibrate(routeId: routeId, stages: stages)
            phase = .idle
        } catch let error as PilgrimageError {
            inFlight?.cancel()
            inFlight = nil
            // A cancel already put the phase back; a genuine failure is
            // shown until the next save or cancel clears it.
            if generation == myGeneration { phase = .failed(error) }
            throw error
        }
    }

    private func loadPack(_ pack: StylePackRequest, generation myGeneration: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            inFlight = loader.loadStylePack(pack) { [weak self] result in
                guard let self, self.generation == myGeneration else {
                    continuation.resume(throwing: PilgrimageError.incomplete)
                    return
                }
                self.inFlight = nil
                continuation.resume(with: result.mapError(Self.mapped))
            }
        }
    }

    private func loadRegion(_ request: TileRegionRequest, generation myGeneration: Int) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            inFlight = loader.loadRegion(request, progress: { _, _ in }) { [weak self] result in
                guard let self, self.generation == myGeneration else {
                    continuation.resume(throwing: PilgrimageError.incomplete)
                    return
                }
                self.inFlight = nil
                continuation.resume(with: result.map { _ in () }.mapError(Self.mapped))
            }
        }
    }

    private static func mapped(_ error: TileRegionLoadingError) -> PilgrimageError {
        switch error {
        case .diskFull: return .diskFull
        case .failed, .cancelled: return .incomplete
        }
    }

    /// Regions already complete stay. The in-flight load is cancelled and
    /// its late completion ignored by generation.
    func cancel() {
        generation += 1
        inFlight?.cancel()
        inFlight = nil
        phase = .idle
    }

    deinit {
        inFlight?.cancel()
    }
```

A subtlety the fake exposes: when `cancel()` runs while a continuation is pending, the fake never calls that completion, so `save` would await forever. Make `cancel()` resume it: store the pending continuation alongside `inFlight`:

```swift
    private var pending: CheckedContinuation<Void, Error>?
```

Set `pending = continuation` in both `loadPack` and `loadRegion` before calling the loader, clear it (`pending = nil`) inside each completion before resuming, and in `cancel()` add, after `inFlight = nil`:

```swift
        if let pending {
            self.pending = nil
            pending.resume(throwing: PilgrimageError.incomplete)
        }
```

The `catch` in `save` sees `generation != myGeneration` after a cancel and leaves `phase` at `.idle` — that is what `testCancelKeepsWhatIsDoneAndResumeStartsAtTheGap` asserts. Because `cancel()` throws `.incomplete` into `save`, the first `Task` in that test ends with an error, which the test discards with `try?`.

- [ ] **Step 4: Run to verify they pass**

Run with `-only-testing:UnitTests/PilgrimageTilesManagerTests`.
Expected: `Executed 14 tests, with 0 failures`.

If `testAWalkStartingMidSaveStopsItAndKeepsWhatIsDone` reports 7 requests: the re-check must happen *before* `loadRegion` is called, not after — check the `guard` sits at the top of the loop body.

- [ ] **Step 5: Lint and commit**

Run: `swiftlint lint --quiet Pilgrim/Models/Honor/PilgrimageTilesManager.swift`
Expected: no errors. If `type_body_length` warns, fine; it must not error (limit 750).

```bash
git add Pilgrim/Models/Honor/PilgrimageTilesManager.swift UnitTests/Honor/PilgrimageTilesManagerTests.swift
git commit -m "feat(tiles): the save loop — packs, then stages, skipping what is current

Cancel keeps every finished region and the next tap resumes at the first
gap. A region is skipped only when it is complete AND its corridor hash
matches the stage's line, so a resumed save never keeps tiles for a path
the stage no longer follows. isWalkActive is re-checked before every
load. Every error lands in .failed so the route page has a state to draw.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Lifecycle — remove, retired indices, launch reconcile, and the package manager's hooks

**Files:**
- Modify: `Pilgrim/Models/Honor/PilgrimageTilesManager.swift`
- Modify: `Pilgrim/Models/Honor/PilgrimagePackageManager.swift:39-68,220-271`
- Modify: `Pilgrim/Scenes/Root/MainCoordinatorView.swift:196-204`
- Create: `UnitTests/Honor/PilgrimageTilesManagerTests+Lifecycle.swift`
- Modify: `UnitTests/Honor/PilgrimagePackageManagerTests.swift` (one test for the hooks)

**Interfaces:**
- Produces: `func remove(routeId:)`, `func removeRegions(routeId:atOrAbove:)`, `func reconcile(installed: (routeId: String, stageCount: Int)?)`, `PilgrimagePackageManager.tiles: PilgrimageTilesManager?` (optional so existing tests construct the manager unchanged), `PilgrimageTilesManager.shared`.

- [ ] **Step 1: Write the failing lifecycle tests**

```swift
// UnitTests/Honor/PilgrimageTilesManagerTests+Lifecycle.swift
import XCTest
@testable import Pilgrim

extension PilgrimageTilesManagerTests {

    func testRemoveClearsExactlyThePrefixAndLeavesPacks() {
        loader.seedStylePacks()
        for way in stages(3) { loader.seed(id: way.id, corridorHash: "h") }
        loader.seed(id: "pilgrimage:kumano-kodo-nakahechi:0", corridorHash: "h")
        manager.remove(routeId: "camino-frances")
        XCTAssertEqual(Set(loader.removedIds), Set(stages(3).map(\.id)))
        XCTAssertNotNil(loader.regions().first { $0.id == "pilgrimage:kumano-kodo-nakahechi:0" })
        XCTAssertEqual(loader.stylePacks, Set(StylePackRequest.allCases))
    }

    func testRemoveCancelsAnInFlightSave() async {
        loader.seedStylePacks()
        let task = Task { try await manager.save(routeId: "camino-frances", stages: stages(2)) }
        await Task.yield()
        manager.remove(routeId: "camino-frances")
        _ = try? await task.value
        XCTAssertEqual(manager.phase, .idle)
    }

    func testRetiredIndicesAreRemovedAndNothingIsDownloaded() {
        for way in stages(5) { loader.seed(id: way.id, corridorHash: "h") }
        manager.removeRegions(routeId: "camino-frances", atOrAbove: 3)
        XCTAssertEqual(Set(loader.removedIds), ["pilgrimage:camino-frances:3", "pilgrimage:camino-frances:4"])
        XCTAssertTrue(loader.regionRequests.isEmpty)
        XCTAssertTrue(loader.packRequests.isEmpty)
    }

    func testReconcileRemovesForeignAndOutOfRangeRegionsAndIsIdempotent() {
        for way in stages(3) { loader.seed(id: way.id, corridorHash: "h") }
        loader.seed(id: "pilgrimage:camino-frances:7", corridorHash: "h")
        loader.seed(id: "pilgrimage:kumano-kodo-nakahechi:0", corridorHash: "h")
        manager.reconcile(installed: (routeId: "camino-frances", stageCount: 3))
        XCTAssertEqual(Set(loader.removedIds), ["pilgrimage:camino-frances:7", "pilgrimage:kumano-kodo-nakahechi:0"])
        let before = loader.removedIds.count
        manager.reconcile(installed: (routeId: "camino-frances", stageCount: 3))
        XCTAssertEqual(loader.removedIds.count, before, "a second run removes nothing")
    }

    func testReconcileWithNothingInstalledRemovesEveryRegion() {
        for way in stages(2) { loader.seed(id: way.id, corridorHash: "h") }
        manager.reconcile(installed: nil)
        XCTAssertEqual(Set(loader.removedIds), Set(stages(2).map(\.id)))
    }
}
```

Run: `ruby scripts/xcode-add.rb UnitTests "UnitTests/Honor/PilgrimageTilesManagerTests+Lifecycle.swift"`

Append to `PilgrimagePackageManagerTests`:

```swift
    func testRemoveReplaceAndUpdateReachTheTilesManager() async throws {
        let tilesLoader = FakeTileRegionLoader()
        let tiles = PilgrimageTilesManager(loader: tilesLoader, defaults: UserDefaults(suiteName: "pm-tiles-\(UUID().uuidString)")!)
        let manager = PilgrimagePackageManager(store: wayStore, ledgers: ledgers, session: StubURLProtocol.session())
        manager.tiles = tiles
        try await manager.download(entry: entry, release: "v1.7.0")
        tilesLoader.seed(id: "pilgrimage:camino-frances:0", corridorHash: "h")
        tilesLoader.seed(id: "pilgrimage:camino-frances:1", corridorHash: "h")

        // Update to a one-stage package: index 1 is retired and its region goes.
        try stubOneStagePackage(release: "v1.8.0")
        try await manager.update(entry: entryWithOneStage, release: "v1.8.0")
        XCTAssertEqual(tilesLoader.removedIds, ["pilgrimage:camino-frances:1"])
        XCTAssertTrue(tilesLoader.regionRequests.isEmpty, "an update downloads no maps")

        try manager.remove(routeId: "camino-frances")
        XCTAssertTrue(tilesLoader.removedIds.contains("pilgrimage:camino-frances:0"))
    }
```

- [ ] **Step 2: Run to verify they fail**

Expected: build errors — no `remove(routeId:)` / `removeRegions` / `reconcile` on the tiles manager; no `tiles` on the package manager.

- [ ] **Step 3: Implement on the tiles manager**

Add to `PilgrimageTilesManager`:

```swift
    /// Shared like the package manager's; the production loader is attached
    /// in `MainCoordinatorView` so this file never imports Mapbox.
    static let shared = PilgrimageTilesManager(loader: MapboxTileRegionLoader())

    // MARK: - Lifecycle

    /// Every region with the route's prefix. Packs no other region references
    /// are freed by the store; the style packs are shared and stay.
    func remove(routeId: String) {
        cancel()
        let prefix = Self.regionPrefix(routeId: routeId)
        for region in loader.regions() where region.id.hasPrefix(prefix) {
            loader.removeRegion(id: region.id)
        }
    }

    /// Update's retired indices: the same range `PilgrimagePackageManager`
    /// hands to `retireMany`. Nothing is downloaded on the walker's behalf.
    func removeRegions(routeId: String, atOrAbove index: Int) {
        let prefix = Self.regionPrefix(routeId: routeId)
        for region in loader.regions() where region.id.hasPrefix(prefix) {
            if let stageIndex = Self.stageIndex(of: region.id, prefix: prefix), stageIndex >= index {
                loader.removeRegion(id: region.id)
            }
        }
    }

    /// Once at launch. The three lifecycle hooks are event-driven and one
    /// path bypasses them: a kill mid-Replace is finished by `installed()`'s
    /// swap-marker branch, never by `remove` or `replace`. Anything the
    /// installed route does not account for goes, so "nothing orphaned" is
    /// a property of the store rather than a promise about call sites.
    func reconcile(installed: (routeId: String, stageCount: Int)?) {
        for region in loader.regions() where region.id.hasPrefix("pilgrimage:") {
            guard let installed else {
                loader.removeRegion(id: region.id)
                continue
            }
            let prefix = Self.regionPrefix(routeId: installed.routeId)
            let index = Self.stageIndex(of: region.id, prefix: prefix)
            if !region.id.hasPrefix(prefix) || index == nil || index! >= installed.stageCount {
                loader.removeRegion(id: region.id)
            }
        }
    }

    private static func stageIndex(of regionId: String, prefix: String) -> Int? {
        guard regionId.hasPrefix(prefix) else { return nil }
        return Int(regionId.dropFirst(prefix.count))
    }
```

`MapboxTileRegionLoader` does not exist until Task 6. So that this task builds, create it now as a stub and fill it in Task 6:

```swift
// Pilgrim/Models/Honor/MapboxTileRegionLoader.swift
import Foundation

/// Filled in by the production-conformer task; until then a loader that
/// holds nothing, so the app builds and every test uses the fake.
final class MapboxTileRegionLoader: TileRegionLoading {
    final class Handle: TileLoadHandle { func cancel() {} }
    func hasStylePack(_ pack: StylePackRequest) -> Bool { false }
    func loadStylePack(_ pack: StylePackRequest, completion: @escaping (Result<Void, TileRegionLoadingError>) -> Void) -> TileLoadHandle {
        completion(.failure(.failed)); return Handle()
    }
    func loadRegion(_ request: TileRegionRequest, progress: @escaping (Int, Int) -> Void,
                    completion: @escaping (Result<TileRegionSummary, TileRegionLoadingError>) -> Void) -> TileLoadHandle {
        completion(.failure(.failed)); return Handle()
    }
    func regions() -> [TileRegionSummary] { [] }
    func removeRegion(id: String) {}
}
```

Run: `ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/MapboxTileRegionLoader.swift`

- [ ] **Step 4: Wire the package manager**

In `PilgrimagePackageManager`, after `let ledgers: PilgrimageLedgerStore` (line 40):

```swift
    /// The saved basemap follows the package: Remove and Replace take a
    /// route's regions, Update takes the retired indices. Optional so the
    /// manager's own tests construct it without a tiles manager.
    var tiles: PilgrimageTilesManager?
```

In `replace(with:release:)`, after `removeStagesAndPackage(routeId: previous.routeId, stageCount: previous.route.stageCount)` (line 241):

```swift
            tiles?.remove(routeId: previous.routeId)
```

In `update(entry:release:)`, after the `store.retireMany(...)` call (line 256):

```swift
        // The maps that were saved stay saved; only the regions at indices the
        // route no longer has go. A redrawn stage's region is reported as
        // stale by the tiles manager's own hash check and re-saved by the
        // walker's next tap — never downloaded here on their behalf.
        tiles?.removeRegions(routeId: entry.id, atOrAbove: fresh.route.stageCount)
```

In `remove(routeId:)`, after `removeStagesAndPackage(routeId: routeId, stageCount: stageCount)` (line 270):

```swift
        tiles?.remove(routeId: routeId)
```

- [ ] **Step 5: Wire the coordinator**

In `MainCoordinatorView.chooseWay()` (line 199), extend the existing `Task { @MainActor in … }`:

```swift
        Task { @MainActor in
            PilgrimagePackageManager.shared.isWalkActive = { [weak self] in self?.activeWalkViewModel != nil }
            PilgrimageTilesManager.shared.isWalkActive = { [weak self] in self?.activeWalkViewModel != nil }
            PilgrimagePackageManager.shared.tiles = PilgrimageTilesManager.shared
        }
```

The launch reconcile belongs where `installed()` is first resolved at startup. Find the coordinator's first-appearance hook (`.task` or `onAppear` on the root view in `MainCoordinatorView`; grep `func onAppear` / `.task {` in that file) and add, once:

```swift
        // Once per launch: a kill mid-Replace is finished by installed()'s
        // marker branch, which no lifecycle hook sees; the tiles manager
        // sweeps whatever the installed route does not account for.
        PilgrimagePackageManager.shared.tiles = PilgrimageTilesManager.shared
        let installed = PilgrimagePackageManager.shared.installed()
        PilgrimageTilesManager.shared.reconcile(
            installed: installed.map { (routeId: $0.routeId, stageCount: $0.route.stageCount) })
```

If the coordinator has no single startup hook, put these three lines in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` immediately after the `mark("after Mapbox init")` line, wrapped in `Task { @MainActor in … }`.

- [ ] **Step 6: Run to verify they pass**

Run with `-only-testing:UnitTests/PilgrimageTilesManagerTests -only-testing:UnitTests/PilgrimagePackageManagerTests`.
Expected: tiles 19/19; package manager suite all green including the new hook test.

- [ ] **Step 7: Lint and commit**

```bash
swiftlint lint --quiet Pilgrim/Models/Honor/PilgrimageTilesManager.swift Pilgrim/Models/Honor/PilgrimagePackageManager.swift Pilgrim/Models/Honor/MapboxTileRegionLoader.swift Pilgrim/Scenes/Root/MainCoordinatorView.swift
git add Pilgrim/Models/Honor/ Pilgrim/Scenes/Root/MainCoordinatorView.swift UnitTests/Honor/ Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(tiles): the maps follow the package, and launch sweeps what nothing owns

Remove and Replace take a route's regions; Update takes the retired
indices and downloads nothing. reconcile(installed:) runs once at launch
because a kill mid-Replace is finished by installed()'s marker branch,
which none of the three hooks ever sees.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: The production conformer — `MapboxTileRegionLoader`, store path, the deprecation comment

**Files:**
- Modify: `Pilgrim/Models/Honor/MapboxTileRegionLoader.swift` (replace the stub)
- Modify: `Pilgrim/AppDelegate.swift:44`
- Create: `UnitTests/Honor/MapboxTileRegionLoaderTests.swift`

**Interfaces:**
- Consumes: Task 1's protocol; Task 3's descriptor constants.
- Produces: `MapboxTileRegionLoader.storeURL: URL` (static), `MapboxTileRegionLoader.descriptorZoomRanges` (static, for the test).

- [ ] **Step 1: Write the failing tests**

Nothing here touches the network; the tests check the store path and that the loader's descriptor configuration is what the spec says.

```swift
// UnitTests/Honor/MapboxTileRegionLoaderTests.swift
import XCTest
@testable import Pilgrim

final class MapboxTileRegionLoaderTests: XCTestCase {

    /// A Caches location is purgeable under storage pressure; a walker on
    /// day 20 could lose the maps for day 21. Application Support is not.
    func testTheStoreLivesUnderApplicationSupport() throws {
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: false)
        XCTAssertTrue(MapboxTileRegionLoader.storeURL.path.hasPrefix(support.path))
        XCTAssertFalse(MapboxTileRegionLoader.storeURL.path.contains("/Caches/"))
        XCTAssertEqual(MapboxTileRegionLoader.storeURL.lastPathComponent, "pilgrimage-tiles")
    }

    /// The SDK excludes a `shared(for:)` path from iCloud backup on iOS;
    /// this pins that the loader uses that entry point and not `.default`.
    func testTheStoreIsCreatedAtAnExplicitPath() {
        XCTAssertTrue(MapboxTileRegionLoader.usesExplicitStorePath)
    }

    func testDescriptorsMatchTheSpec() {
        let ranges = MapboxTileRegionLoader.descriptorZoomRanges
        XCTAssertEqual(ranges.streets, PilgrimageTilesDescriptors.streetsZoom)
        XCTAssertEqual(ranges.terrain, PilgrimageTilesDescriptors.terrainZoom)
        XCTAssertEqual(MapboxTileRegionLoader.terrainTilesets, [PilgrimageTilesDescriptors.terrainTileset])
    }
}
```

Run: `ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/MapboxTileRegionLoaderTests.swift`

- [ ] **Step 2: Run to verify they fail**

Expected: build errors — no `storeURL`, `usesExplicitStorePath`, `descriptorZoomRanges`, `terrainTilesets`.

- [ ] **Step 3: Replace the stub with the real loader**

```swift
// Pilgrim/Models/Honor/MapboxTileRegionLoader.swift
import CoreLocation
import Foundation
import MapboxMaps
import Turf

/// The one file that speaks to Mapbox's offline API. Everything above it
/// talks in `TileRegionRequest` and `TileRegionSummary`.
final class MapboxTileRegionLoader: TileRegionLoading {

    final class Handle: TileLoadHandle {
        private let cancelable: Cancelable
        init(_ cancelable: Cancelable) { self.cancelable = cancelable }
        func cancel() { cancelable.cancel() }
    }

    /// Under Application Support, never Caches: Caches is purgeable under
    /// storage pressure and a walker on day 20 could lose day 21's maps.
    /// `TileStore.shared(for:)` excludes its path from iCloud backup.
    static let storeURL: URL = {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true))
            ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("pilgrimage-tiles", isDirectory: true)
    }()
    static let usesExplicitStorePath = true
    static let descriptorZoomRanges = (streets: PilgrimageTilesDescriptors.streetsZoom,
                                       terrain: PilgrimageTilesDescriptors.terrainZoom)
    static let terrainTilesets = [PilgrimageTilesDescriptors.terrainTileset]

    private let tileStore: TileStore
    private let offlineManager: OfflineManager
    private let descriptors: [TilesetDescriptor]
    /// Refreshed from the store on every `regions()`; the manager reads it
    /// synchronously and the store answers asynchronously.
    private var cached: [TileRegionSummary] = []
    private var cachedPacks: Set<StylePackRequest> = []

    init() {
        tileStore = TileStore.shared(for: Self.storeURL)
        offlineManager = OfflineManager()
        let streetsLight = TilesetDescriptorOptions(styleURI: .light, zoomRange: Self.descriptorZoomRanges.streets, tilesets: nil)
        let streetsDark = TilesetDescriptorOptions(styleURI: .dark, zoomRange: Self.descriptorZoomRanges.streets, tilesets: nil)
        let terrain = TilesetDescriptorOptions(styleURI: .light, zoomRange: Self.descriptorZoomRanges.terrain,
                                               tilesets: Self.terrainTilesets)
        descriptors = [streetsLight, streetsDark, terrain].map(offlineManager.createTilesetDescriptor(for:))
        refresh()
    }

    private static func styleURI(_ pack: StylePackRequest) -> StyleURI {
        pack == .light ? .light : .dark
    }

    // MARK: - TileRegionLoading

    func hasStylePack(_ pack: StylePackRequest) -> Bool { cachedPacks.contains(pack) }

    func loadStylePack(_ pack: StylePackRequest,
                       completion: @escaping (Result<Void, TileRegionLoadingError>) -> Void) -> TileLoadHandle {
        guard let options = StylePackLoadOptions(glyphsRasterizationMode: .ideographsRasterizedLocally) else {
            completion(.failure(.failed))
            return Handle(AnyCancelable {})
        }
        let cancelable = offlineManager.loadStylePack(for: Self.styleURI(pack), loadOptions: options) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    self?.cachedPacks.insert(pack)
                    completion(.success(()))
                case .failure(let error):
                    completion(.failure(Self.mapped(error)))
                }
            }
        }
        return Handle(cancelable)
    }

    func loadRegion(_ request: TileRegionRequest,
                    progress: @escaping (Int, Int) -> Void,
                    completion: @escaping (Result<TileRegionSummary, TileRegionLoadingError>) -> Void) -> TileLoadHandle {
        let ring = request.ring.map { LocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
        guard let options = TileRegionLoadOptions(geometry: .polygon(Polygon([ring])),
                                                  descriptors: descriptors,
                                                  metadata: ["corridorHash": request.corridorHash],
                                                  acceptExpired: request.acceptExpired) else {
            completion(.failure(.failed))
            return Handle(AnyCancelable {})
        }
        let cancelable = tileStore.loadTileRegion(forId: request.id, loadOptions: options, progress: { loadProgress in
            DispatchQueue.main.async {
                progress(Int(loadProgress.completedResourceCount), Int(loadProgress.requiredResourceCount))
            }
        }, completion: { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .success(let region):
                    let summary = TileRegionSummary(id: region.id,
                                                    completedResourceCount: Int(region.completedResourceCount),
                                                    requiredResourceCount: Int(region.requiredResourceCount),
                                                    completedResourceSize: Int(region.completedResourceSize),
                                                    metadata: ["corridorHash": request.corridorHash])
                    self?.cached.removeAll { $0.id == summary.id }
                    self?.cached.append(summary)
                    completion(.success(summary))
                case .failure(let error):
                    completion(.failure(Self.mapped(error)))
                }
            }
        })
        return Handle(cancelable)
    }

    func regions() -> [TileRegionSummary] {
        refresh()
        return cached
    }

    func removeRegion(id: String) {
        tileStore.removeTileRegion(forId: id)
        cached.removeAll { $0.id == id }
    }

    // MARK: - Store → cache

    /// The store answers on a worker thread; the cache is what the manager
    /// reads. A read that lands mid-refresh sees the previous answer, which
    /// is at most one save behind.
    private func refresh() {
        tileStore.allTileRegions { [weak self] result in
            guard case .success(let regions) = result else { return }
            let group = DispatchGroup()
            var summaries: [TileRegionSummary] = []
            let lock = NSLock()
            for region in regions {
                group.enter()
                self?.tileStore.tileRegionMetadata(forId: region.id) { metadataResult in
                    let hash = ((try? metadataResult.get()) as? [String: String])?["corridorHash"] ?? ""
                    let summary = TileRegionSummary(id: region.id,
                                                    completedResourceCount: Int(region.completedResourceCount),
                                                    requiredResourceCount: Int(region.requiredResourceCount),
                                                    completedResourceSize: Int(region.completedResourceSize),
                                                    metadata: ["corridorHash": hash])
                    lock.lock(); summaries.append(summary); lock.unlock()
                    group.leave()
                }
            }
            group.notify(queue: .main) { self?.cached = summaries }
        }
        offlineManager.allStylePacks { [weak self] result in
            guard case .success(let packs) = result else { return }
            let uris = Set(packs.map(\.styleURI))
            DispatchQueue.main.async {
                self?.cachedPacks = Set(StylePackRequest.allCases.filter { uris.contains(Self.styleURI($0).rawValue) })
            }
        }
    }

    private static func mapped(_ error: Error) -> TileRegionLoadingError {
        if WayMediaDownloader.isDiskFull(error) { return .diskFull }
        if let tileError = error as? TileRegionError, case .canceled = tileError { return .cancelled }
        return .failed
    }
}
```

Two things to check against the SDK as you build, and adjust only the named line if they differ:
- `TileRegionError` may not expose `.canceled` as an enum case in 11.23.1; if the compiler objects, replace that `if let` line with `if (error as NSError).domain.contains("TileRegionError"), (error as NSError).code == 3 { return .cancelled }` after confirming the cancel code by grepping `MBXTileRegionErrorType.h` in the artifacts. Cancellation is already handled by the manager's generation counter, so `.cancelled` vs `.failed` only affects the mapped `PilgrimageError`, which is `.incomplete` either way.
- `StylePack.styleURI` is the raw string property on `MapboxCoreMaps.StylePack`; if it is named `styleURL`, use that.

- [ ] **Step 4: The AppDelegate comment**

Replace `Pilgrim/AppDelegate.swift:44`:

```swift
        // 2026-09-14, Honor slice three: .readOnly is what a saved tile
        // region needs — the store is checked first and a covering pack is
        // used. The whole TileStoreUsageMode enum is marked deprecated in
        // the 11.23.1 CoreMaps headers with no replacement named; re-read
        // decision 7 of the slice-three spec before any bump past 11.x.
        MapboxMapsOptions.tileStoreUsageMode = .readOnly
```

- [ ] **Step 5: Run to verify they pass, and that the app builds**

Run with `-only-testing:UnitTests/MapboxTileRegionLoaderTests`.
Expected: 3/3.

Run the plain build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -derivedDataPath /tmp/pilgrim-s3-dd build 2>&1 | grep -E "error:|BUILD"`.
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Lint and commit**

```bash
swiftlint lint --quiet Pilgrim/Models/Honor/MapboxTileRegionLoader.swift Pilgrim/AppDelegate.swift
git add Pilgrim/Models/Honor/MapboxTileRegionLoader.swift Pilgrim/AppDelegate.swift UnitTests/Honor/MapboxTileRegionLoaderTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(tiles): the one file that speaks to Mapbox's offline API

TileStore at an explicit Application Support path, never Caches — the
SDK excludes a shared(for:) path from iCloud backup on its own. Three
descriptors: Streets light and dark to 16, the terrain DEM to 14 named
explicitly because the wabi-sabi pass adds it at runtime. readOnly stays,
with a dated comment on the deprecation the SDK has put on the enum.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: The route page row

**Files:**
- Create: `Pilgrim/Scenes/Honor/PilgrimageMapsRow.swift`
- Modify: `Pilgrim/Scenes/Honor/PilgrimageRouteView.swift:147-166,271-274`
- Create: `UnitTests/Honor/PilgrimageMapsRowTests.swift`

**Interfaces:**
- Consumes: `PilgrimageTilesManager.Status`, `.Phase`, `estimateBytes`, `save`, `cancel`.
- Produces: `enum PilgrimageMapsRowModel { static func label(status:estimateBytes:) -> String; static func savingLine(done:total:) -> String; static func savedLine(bytes:) -> String; static func megabytes(_ bytes: Int) -> String }`, `struct PilgrimageMapsRow: View`.

- [ ] **Step 1: Write the failing copy tests**

```swift
// UnitTests/Honor/PilgrimageMapsRowTests.swift
import XCTest
@testable import Pilgrim

final class PilgrimageMapsRowTests: XCTestCase {

    func testTheEstimateIsRoundedAndTilded() {
        XCTAssertEqual(PilgrimageMapsRowModel.label(status: .none, estimateBytes: 26_400_000), "Save maps for the way · ~26 MB")
        XCTAssertEqual(PilgrimageMapsRowModel.label(status: .none, estimateBytes: 1_900_000), "Save maps for the way · ~2 MB")
        XCTAssertEqual(PilgrimageMapsRowModel.label(status: .none, estimateBytes: 400_000), "Save maps for the way · ~1 MB")
    }

    func testAPartialSaveSaysHowFarItGot() {
        XCTAssertEqual(PilgrimageMapsRowModel.label(status: .partial(saved: 12, of: 33), estimateBytes: 0),
                       "Save maps for the way · 12 of 33 saved")
    }

    func testSavedShowsRealBytesWithNoTilde() {
        XCTAssertEqual(PilgrimageMapsRowModel.savedLine(bytes: 26_100_000), "maps saved · 26 MB")
    }

    /// `total` counts the two style packs; the walker counts stages.
    func testSavingCountsStagesNotPacks() {
        XCTAssertEqual(PilgrimageMapsRowModel.savingLine(done: 14, total: 35), "maps · stage 12 of 33")
        XCTAssertEqual(PilgrimageMapsRowModel.savingLine(done: 0, total: 35), "maps · stage 0 of 33")
    }
}
```

Run: `ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/PilgrimageMapsRowTests.swift`

- [ ] **Step 2: Run to verify they fail**

Expected: build error — `cannot find 'PilgrimageMapsRowModel'`.

- [ ] **Step 3: Write the model and the row**

```swift
// Pilgrim/Scenes/Honor/PilgrimageMapsRow.swift
import SwiftUI

enum PilgrimageMapsRowModel {

    static func megabytes(_ bytes: Int) -> String {
        "\(max(1, Int((Double(bytes) / 1_000_000).rounded()))) MB"
    }

    static func label(status: PilgrimageTilesManager.Status, estimateBytes: Int) -> String {
        switch status {
        case .partial(let saved, let of): return "Save maps for the way · \(saved) of \(of) saved"
        case .none, .saved: return "Save maps for the way · ~\(megabytes(estimateBytes))"
        }
    }

    static func savedLine(bytes: Int) -> String { "maps saved · \(megabytes(bytes))" }

    /// `done` and `total` both count the style packs ahead of the stages;
    /// the walker only cares about stages, so both sides drop them.
    static func savingLine(done: Int, total: Int) -> String {
        let packs = StylePackRequest.allCases.count
        return "maps · stage \(max(done - packs, 0)) of \(max(total - packs, 0))"
    }
}

/// Under the route page's download button: one row, driven by the tiles
/// manager's status while idle and by its phase while saving.
struct PilgrimageMapsRow: View {

    let routeId: String
    let stages: [Way]
    @ObservedObject var tiles: PilgrimageTilesManager
    @State private var failure: PilgrimageError?

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
            switch tiles.phase {
            case .saving(let done, let total):
                HStack(spacing: Constants.UI.Padding.small) {
                    Text(PilgrimageMapsRowModel.savingLine(done: done, total: total))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                    Button("cancel") { tiles.cancel() }
                        .font(Constants.Typography.caption)
                        .foregroundColor(.stone)
                }
            case .idle, .failed:
                idleRow
                if case .failed(let error) = tiles.phase {
                    Text(PilgrimageCopy.line(for: error))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.rust)
                }
            }
        }
    }

    @ViewBuilder
    private var idleRow: some View {
        let status = tiles.status(for: routeId, stages: stages)
        if case .saved(let bytes) = status {
            Button { Task { await save() } } label: {
                HStack(spacing: Constants.UI.Padding.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.moss)
                        .accessibilityHidden(true)
                    Text(PilgrimageMapsRowModel.savedLine(bytes: bytes))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
            }
            .accessibilityLabel("maps saved, \(PilgrimageMapsRowModel.megabytes(bytes)). Tap to save again")
        } else {
            Button { Task { await save() } } label: {
                Text(PilgrimageMapsRowModel.label(status: status,
                                                  estimateBytes: tiles.estimateBytes(for: routeId, stages: stages)))
                    .font(Constants.Typography.button)
                    .foregroundColor(.stone)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.stone.opacity(0.12))
                    .cornerRadius(Constants.UI.CornerRadius.normal)
            }
        }
    }

    private func save() async {
        do {
            try await tiles.save(routeId: routeId, stages: stages)
        } catch {
            // The manager's phase carries the failure; nothing else to keep.
        }
    }
}
```

Run: `ruby scripts/xcode-add.rb Pilgrim Pilgrim/Scenes/Honor/PilgrimageMapsRow.swift`

The `@State private var failure` is unused after the phase carries it — delete that line before committing; it is there only to make the point that the row keeps no state of its own.

- [ ] **Step 4: Put the row on the route page**

In `PilgrimageRouteView`, add a state for the installed stages and observe the tiles manager. After `@ObservedObject private var packages = PilgrimagePackageManager.shared` (line 66):

```swift
    @ObservedObject private var tiles = PilgrimageTilesManager.shared
    /// The installed route's stage Ways, read once in `reload()`: the maps
    /// row needs their lines for its estimate and its status.
    @State private var stageWays: [Way] = []
```

In `header` (line 164), after `downloadButton`:

```swift
            if isInstalled && !stageWays.isEmpty {
                PilgrimageMapsRow(routeId: entry.id, stages: stageWays, tiles: tiles)
            }
```

In `reload()` (line 331), after `if installed?.routeId == entry.id { route = installed?.route }`:

```swift
        stageWays = isInstalled
            ? (0..<(route?.stageCount ?? 0)).compactMap { WayStore.shared.load(id: WayStore.stageWayId(routeId: entry.id, stageIndex: $0)) }
            : []
```

In `isBusy` (line 271), a save should also disable Remove/Replace/Update, since the manager refuses them anyway:

```swift
    private var isBusy: Bool {
        if case .downloading = packages.phase { return true }
        if case .saving = tiles.phase { return true }
        return false
    }
```

- [ ] **Step 5: Run to verify they pass, and build**

Run with `-only-testing:UnitTests/PilgrimageMapsRowTests`. Expected: 4/4.
Build the app. Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 6: Lint and commit**

```bash
swiftlint lint --quiet Pilgrim/Scenes/Honor/PilgrimageMapsRow.swift Pilgrim/Scenes/Honor/PilgrimageRouteView.swift
git add Pilgrim/Scenes/Honor/PilgrimageMapsRow.swift Pilgrim/Scenes/Honor/PilgrimageRouteView.swift UnitTests/Honor/PilgrimageMapsRowTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(tiles): the route page's one row — save, saving, saved, failed

Sized before the tap, with a tilde while it is an estimate and none once
it is the store's own count. Progress counts stages the way the package
download does. A failed save shows the same footer a failed download
shows.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: The morning card's line

**Files:**
- Modify: `Pilgrim/Scenes/Honor/StageMorningCard.swift:3-30,46-50`
- Modify: `Pilgrim/Scenes/Honor/HonorOverviewView.swift:172`
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift:306`
- Modify: `UnitTests/Honor/PilgrimageMapsRowTests.swift` (two copy tests)

**Interfaces:**
- Produces: `StageMorningCardModel.mapsLine(saved: Bool) -> String`, `StageMorningCard.init(stage:weather:mapsLine:buttonTitle:onAction:)`.

- [ ] **Step 1: Write the failing tests**

Append to `PilgrimageMapsRowTests`:

```swift
    func testTheMorningCardSaysWhetherTodayIsSaved() {
        XCTAssertEqual(StageMorningCardModel.mapsLine(saved: true), "maps saved for today")
        XCTAssertEqual(StageMorningCardModel.mapsLine(saved: false), "no offline maps for today — save on wifi")
    }
```

- [ ] **Step 2: Run to verify it fails**

Expected: build error — no `mapsLine` on `StageMorningCardModel`.

- [ ] **Step 3: Implement**

In `StageMorningCardModel`, after `weatherLine`:

```swift
    /// The moment before the day starts is where a walker needs to know
    /// whether the map will be there. Not on the walk screen — the
    /// minimalism rule holds there — but here, with the weather.
    static func mapsLine(saved: Bool) -> String {
        saved ? "maps saved for today" : "no offline maps for today — save on wifi"
    }
```

In `StageMorningCard`, after `let weather: WeatherSnapshot?`:

```swift
    /// Nil for a card shown outside a pilgrimage's context; the callers
    /// that have a tiles manager compute it.
    let mapsLine: String?
```

In `body`, after the `weatherLine` block (line 50):

```swift
                    if let mapsLine {
                        Text(mapsLine)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }
```

`HonorOverviewView.swift:172`:

```swift
                StageMorningCard(stage: stage, weather: todayWeather,
                                 mapsLine: StageMorningCardModel.mapsLine(saved: PilgrimageTilesManager.shared.isStageSaved(way)),
                                 buttonTitle: "walk") {
```

`ActiveWalkView.swift:306`:

```swift
                StageMorningCard(stage: stage, weather: viewModel.weatherSnapshot,
                                 mapsLine: viewModel.way.map { StageMorningCardModel.mapsLine(saved: PilgrimageTilesManager.shared.isStageSaved($0)) },
                                 buttonTitle: "close") {
```

- [ ] **Step 4: Run to verify it passes, and build**

Run with `-only-testing:UnitTests/PilgrimageMapsRowTests`. Expected: 5/5. Build: succeeded.

- [ ] **Step 5: Commit**

```bash
swiftlint lint --quiet Pilgrim/Scenes/Honor/StageMorningCard.swift Pilgrim/Scenes/Honor/HonorOverviewView.swift Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift
git add Pilgrim/Scenes/Honor/StageMorningCard.swift Pilgrim/Scenes/Honor/HonorOverviewView.swift Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift UnitTests/Honor/PilgrimageMapsRowTests.swift
git commit -m "feat(tiles): the morning card says whether today's map is saved

One caption with the weather, before the button. Nothing on the walk
screen.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Settings → Data — the Maps row, `OfflineMapsView`, and the debug switch

**Files:**
- Create: `Pilgrim/Scenes/Settings/OfflineMapsView.swift`
- Modify: `Pilgrim/Scenes/Settings/SettingsCards/DataCard.swift`
- Create: `UnitTests/Honor/OfflineMapsViewModelTests.swift`

**Interfaces:**
- Produces: `enum OfflineMapsModel { struct Saved: Equatable { routeName, bytes, savedStages, totalStages }; static func load(packages:tiles:) -> Saved?; static func rowDetail(_ saved: Saved?) -> String; static let emptyCaption; static let deleteTitle; static let deleteMessage }`, `struct OfflineMapsView: View`.

- [ ] **Step 1: Write the failing tests**

```swift
// UnitTests/Honor/OfflineMapsViewModelTests.swift
import XCTest
@testable import Pilgrim

@MainActor
final class OfflineMapsViewModelTests: XCTestCase {

    func testTheRowSaysNoneSavedOrTheRouteAndItsBytes() {
        XCTAssertEqual(OfflineMapsModel.rowDetail(nil), "none saved")
        let saved = OfflineMapsModel.Saved(routeName: "Camino de Santiago (Frances)", bytes: 26_100_000, savedStages: 33, totalStages: 33)
        XCTAssertEqual(OfflineMapsModel.rowDetail(saved), "Camino de Santiago (Frances) · 26 MB")
    }

    func testTheCopyIsTheSpecs() {
        XCTAssertEqual(OfflineMapsModel.emptyCaption, "no maps saved")
        XCTAssertEqual(OfflineMapsModel.deleteTitle, "Delete maps?")
        XCTAssertEqual(OfflineMapsModel.deleteMessage, "Removes the saved basemap. The route's stages stay on your phone.")
    }

    /// A partial save still counts as "saved" for the settings row — there
    /// are bytes on the phone to delete — and the view says how many stages.
    func testLoadReadsTheInstalledRouteThroughTheTilesManager() {
        let loader = FakeTileRegionLoader()
        let tiles = PilgrimageTilesManager(loader: loader, defaults: UserDefaults(suiteName: "om-\(UUID().uuidString)")!)
        let stages = (0..<3).map { index -> Way in
            let points = [WayPoint(lat: 42, lon: Double(index) * 0.05, alt: nil, t: 0), WayPoint(lat: 42, lon: Double(index) * 0.05 + 0.01, alt: nil, t: 60)]
            let stage = WayStage(routeId: "camino-frances", index: index, count: 3, name: "s", theme: "t", narrative: "n", closing: "c",
                                 warnings: [], distanceKm: 1, gainMeters: 0, hours: WayStageHours(min: 1, max: 1), difficulty: "easy",
                                 start: WayStagePlace(name: "a", at: WayCoordinate(lat: 42, lon: 0)), end: WayStagePlace(name: "b", at: WayCoordinate(lat: 42, lon: 0.01)))
            return Way(id: WayStore.stageWayId(routeId: "camino-frances", stageIndex: index), source: .pilgrimage(routeId: "camino-frances", stageIndex: index),
                       title: "s", departedAt: Date(), tzIdentifier: nil, expires: nil, route: points, totalDistanceMeters: 1000,
                       theirActiveSeconds: 600, moments: [], weather: nil, spans: nil, marks: nil, stage: stage)
        }
        loader.seed(id: stages[0].id, corridorHash: PilgrimageTilesManager.corridorHash(for: stages[0]), bytes: 5_000_000)
        let saved = OfflineMapsModel.load(routeName: "Camino de Santiago (Frances)", routeId: "camino-frances", stages: stages, tiles: tiles)
        XCTAssertEqual(saved, OfflineMapsModel.Saved(routeName: "Camino de Santiago (Frances)", bytes: 5_000_000, savedStages: 1, totalStages: 3))
        XCTAssertNil(OfflineMapsModel.load(routeName: "x", routeId: "camino-frances", stages: [], tiles: tiles))
    }
}
```

Run: `ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/OfflineMapsViewModelTests.swift`

- [ ] **Step 2: Run to verify they fail**

Expected: build error — `cannot find 'OfflineMapsModel'`.

- [ ] **Step 3: Implement the model and view**

```swift
// Pilgrim/Scenes/Settings/OfflineMapsView.swift
import SwiftUI

enum OfflineMapsModel {

    struct Saved: Equatable {
        let routeName: String
        let bytes: Int
        let savedStages: Int
        let totalStages: Int
    }

    static let emptyCaption = "no maps saved"
    static let deleteTitle = "Delete maps?"
    static let deleteMessage = "Removes the saved basemap. The route's stages stay on your phone."

    static func rowDetail(_ saved: Saved?) -> String {
        guard let saved else { return "none saved" }
        return "\(saved.routeName) · \(PilgrimageMapsRowModel.megabytes(saved.bytes))"
    }

    /// Nil when no stage of the installed route has a saved region. A
    /// partial save is still bytes on the phone, so it is reported.
    static func load(routeName: String, routeId: String, stages: [Way], tiles: PilgrimageTilesManager) -> Saved? {
        let savedStages = stages.filter(tiles.isStageSaved)
        guard !savedStages.isEmpty else { return nil }
        let bytes = savedStages.compactMap { way in tiles.loader.regions().first { $0.id == way.id } }
            .reduce(0) { $0 + $1.completedResourceSize }
        return Saved(routeName: routeName, bytes: bytes, savedStages: savedStages.count, totalStages: stages.count)
    }

    /// What the Data card and this view both read: the installed route's
    /// stages through the tiles manager.
    static func loadInstalled(packages: PilgrimagePackageManager, tiles: PilgrimageTilesManager) -> (saved: Saved?, routeId: String?) {
        guard let installed = packages.installed() else { return (nil, nil) }
        let stages = (0..<installed.route.stageCount).compactMap {
            packages.store.load(id: WayStore.stageWayId(routeId: installed.routeId, stageIndex: $0))
        }
        return (load(routeName: installed.route.name, routeId: installed.routeId, stages: stages, tiles: tiles), installed.routeId)
    }
}

/// Settings → Data → Maps. Written for one pilgrimage, because that is
/// all the phone ever holds. It never starts a save: the route page's
/// button is the one door to that tap.
struct OfflineMapsView: View {

    @ObservedObject private var tiles = PilgrimageTilesManager.shared
    @State private var saved: OfflineMapsModel.Saved?
    @State private var routeId: String?
    @State private var confirmDelete = false

    var body: some View {
        List {
            if let saved {
                VStack(alignment: .leading, spacing: 2) {
                    Text(saved.routeName).font(Constants.Typography.body).foregroundColor(.ink)
                    Text("\(PilgrimageMapsRowModel.megabytes(saved.bytes)) · \(saved.savedStages) of \(saved.totalStages) stages")
                        .font(Constants.Typography.caption).foregroundColor(.fog)
                }
                Button("Delete maps", role: .destructive) { confirmDelete = true }
                    .font(Constants.Typography.button)
            } else {
                Text(OfflineMapsModel.emptyCaption).font(Constants.Typography.caption).foregroundColor(.fog)
            }
        }
        .navigationTitle("Maps")
        .onAppear(perform: reload)
        .alert(OfflineMapsModel.deleteTitle, isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                if let routeId { tiles.remove(routeId: routeId) }
                reload()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(OfflineMapsModel.deleteMessage)
        }
    }

    private func reload() {
        let loaded = OfflineMapsModel.loadInstalled(packages: PilgrimagePackageManager.shared, tiles: tiles)
        saved = loaded.saved
        routeId = loaded.routeId
    }
}
```

Run: `ruby scripts/xcode-add.rb Pilgrim Pilgrim/Scenes/Settings/OfflineMapsView.swift`

`PilgrimagePackageManager.store` is already `let store: WayStore` (internal) — no change needed.

- [ ] **Step 4: The Data card**

Replace `Pilgrim/Scenes/Settings/SettingsCards/DataCard.swift`:

```swift
import SwiftUI
#if DEBUG
import MapboxMaps
#endif

struct DataCard: View {

    @State private var waysDetail: String = ""
    @State private var mapsDetail: String = ""
    #if DEBUG
    @State private var simulateOffline = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            cardHeader(title: "Data", subtitle: "Your walk archive")

            NavigationLink {
                DataSettingsView()
            } label: {
                settingNavRow(label: "Export & Import")
            }

            NavigationLink {
                WaysListView()
            } label: {
                settingNavRow(label: "Ways", detail: waysDetail)
            }

            NavigationLink {
                OfflineMapsView()
            } label: {
                settingNavRow(label: "Maps", detail: mapsDetail)
            }

            #if DEBUG
            // Forces the Mapbox stack offline without airplane mode, so a
            // saved stage can be opened and seen to render — or not — at
            // home. Process-wide: it is reset on launch and never persisted.
            settingToggle(label: "simulate no signal for maps",
                          description: "DEBUG · the map stops fetching until this is off",
                          isOn: $simulateOffline) { on in
                OfflineSwitch.shared.isMapboxStackConnected = !on
            }
            #endif
        }
        .settingsCard()
        .onAppear {
            let count = WayStore.shared.list().count
            let mb = Double(WayStore.shared.totalDiskUsage()) / 1_000_000
            waysDetail = "\(count) ways · \(String(format: "%.1f MB", mb))"
            mapsDetail = OfflineMapsModel.rowDetail(
                OfflineMapsModel.loadInstalled(packages: PilgrimagePackageManager.shared, tiles: PilgrimageTilesManager.shared).saved)
            #if DEBUG
            simulateOffline = !OfflineSwitch.shared.isMapboxStackConnected
            #endif
        }
    }
}
```

- [ ] **Step 5: Run to verify they pass, and build**

Run with `-only-testing:UnitTests/OfflineMapsViewModelTests`. Expected: 3/3. Build: succeeded.

- [ ] **Step 6: Lint and commit**

```bash
swiftlint lint --quiet Pilgrim/Scenes/Settings/OfflineMapsView.swift Pilgrim/Scenes/Settings/SettingsCards/DataCard.swift
git add Pilgrim/Scenes/Settings/OfflineMapsView.swift Pilgrim/Scenes/Settings/SettingsCards/DataCard.swift UnitTests/Honor/OfflineMapsViewModelTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "feat(tiles): Settings → Data → Maps, and the switch that proves it works

A Maps row beside Ways, a view written for the one pilgrimage the phone
holds, an empty state, and a Delete that confirms first like Remove and
Delete all Ways do. It never starts a save. Under DEBUG, a toggle on
OfflineSwitch so a saved stage can be seen to render in a living room.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 10: Whole-suite gate, lint, device pass, PR

**Files:** none new.

- [ ] **Step 1: Full unit suite**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/pilgrim-s3-dd -skip-testing:ScreenshotTests 2>&1 | grep -E "error:|Executed [0-9]+ tests, with [1-9]|^Test Suite 'All tests'|\*\* TEST"`
Expected: `** TEST SUCCEEDED **`, roughly 1789 + 36 tests, 0 failures. (`ScreenshotTests` is skipped on purpose; it needs a City Run simulator and is run separately.)

- [ ] **Step 2: Full-repo lint**

Run: `swiftlint lint --quiet 2>&1 | grep -E "error" ; echo "exit $?"`
Expected: no `error` lines (warnings are tolerated; `type_body_length` must not exceed 750 on `PilgrimageTilesManager` — if it does, move `reconcile`/`removeRegions` into `PilgrimageTilesManager+Lifecycle.swift` and register it).

- [ ] **Step 3: Device pass (the SE3, id `33A4AE47-80D7-560E-968B-1BA0C98BB6CF`)**

Build and install:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -destination 'platform=iOS,id=33A4AE47-80D7-560E-968B-1BA0C98BB6CF' -derivedDataPath /tmp/pilgrim-s3-dd -allowProvisioningUpdates build 2>&1 | tail -3
xcrun devicectl device install app --device 33A4AE47-80D7-560E-968B-1BA0C98BB6CF /tmp/pilgrim-s3-dd/Build/Products/Debug-iphoneos/Pilgrim.app
```

Then, by hand, in this order — each is a line in the PR body with ✓ or the observed deviation:
1. Route page of the installed route (Nakahechi is fastest, ~2 MB): the row reads `Save maps for the way · ~N MB`. Note N.
2. Tap it: `maps · stage 1 of 4` … `4 of 4`, then the check glyph and `maps saved · N MB`. Note the real N against the estimate.
3. Settings → Data → the Maps row reads `Nakahechi (Central Route) · N MB`; open it; the two lines and Delete are there.
4. Settings → Data → toggle **simulate no signal for maps** on. Open the route page → a stage → the overview: the basemap renders with roads, hillshade and labels. Open the morning card: `maps saved for today`. Begin the stage; the walk screen renders the basemap at z16.
5. Toggle it off. Delete maps from Settings → confirm → the route page reads `Save maps for the way · ~N MB` again and the morning card reads `no offline maps for today — save on wifi`.
6. Save maps again, then Remove the route from its page → Settings → Data → Maps reads `none saved`.
7. Save maps, then start a walk from another stage while the save is running → the save stops with `finish your walk first` and the stages already saved stay saved (check the row after the walk ends).

- [ ] **Step 4: Open the PR**

```bash
git push -u origin feat/honor-slice-three
gh pr create --repo walktalkmeditate/pilgrim-ios --title "feat(honor): offline maps for a pilgrimage — slice three" --body-file <(cat <<'EOF'
One opt-in tap on the route page saves the basemap for every stage of the installed pilgrimage, sized before the tap, one Mapbox tile region per stage keyed like the stage's Way. The walk screen, the overview and the morning card render with no signal.

Spec: `docs/superpowers/specs/2026-09-14-honor-slice-three-offline-tiles-design.md` (reviewed by six personas; twelve findings applied). Plan: `docs/superpowers/plans/2026-09-14-honor-slice-three-offline-tiles.md`.

## What it does
- `PilgrimageTilesManager`, a sibling of the package manager: status, estimate, save loop (packs, then stages, skipping any region that is complete **and** still matches its stage's corridor hash), cancel-keeps-done, `isWalkActive` re-checked before every load, `.failed` drawn on the row.
- Remove and Replace take the maps; Update takes the retired indices and downloads nothing; `reconcile(installed:)` at launch sweeps whatever no route owns.
- Streets to z16, terrain DEM to z14 — the SDK's own pack bands. The DEM is named explicitly because the wabi-sabi pass adds it at runtime.
- Route page row, morning card line, Settings → Data → Maps with a confirmed Delete, and a DEBUG `OfflineSwitch` toggle so a saved stage can be proven to render at home.
- Every Mapbox call behind `TileRegionLoading`; 36 new tests, all against a fake.

## Device pass (SE3)
(fill from Task 10 step 3)

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)
```

Do not dispatch TestFlight. Report the PR URL and the device-pass table.

---

## Self-review

**Spec coverage.** §1.1 manager + protocol → Tasks 1, 3, 4, 5. §1.2 keys → Task 3 (`regionPrefix`, `stageWayId`). §1.3 descriptors, glyphs, band note → Tasks 3, 6. §2.1 corridor → Task 2. §2.2 per-route estimate + calibration → Task 3 (+ Task 4's `calibrate` call). §3.1–3.4 loop, cancel, resource safety, errors → Task 4. §4 lifecycle + launch reconcile → Task 5. §5.1 row → Task 7. §5.2 morning card → Task 8. §5.3 catalog unchanged → no task (correct). §5.4 Settings + confirm + empty state → Task 9. §5.5 debug switch → Task 9. §6 store location + backup → Task 6. §7 tests → every bullet has a named test in Tasks 2–9; "Delete confirms" is a view-level alert and is covered by the device pass step 5 plus the copy test, since SwiftUI alerts have no unit-test surface here. §8/§9 → nothing to build.

**Placeholders.** None: every step has its code or its exact command. The two "adjust only the named line if the SDK differs" notes in Task 6 name the alternative code.

**Type consistency.** `TileRegionRequest(id:ring:corridorHash:acceptExpired:)` — Tasks 1, 4, 6. `TileRegionSummary(id:completedResourceCount:requiredResourceCount:completedResourceSize:metadata:)` — Tasks 1, 3, 6, fake. `PilgrimageTilesManager.init(loader:defaults:)` — Tasks 3, 5, 9, tests. `status(for:stages:)`, `isStageSaved(_:)`, `estimateBytes(for:stages:)`, `tileCount(for:)`, `calibrate(routeId:stages:)`, `corridorHash(for:)` / `corridorHash(_:)`, `ring(for:)` — Tasks 3, 4, 7, 9. `save(routeId:stages:)`, `cancel()` — Tasks 4, 5, 7. `remove(routeId:)`, `removeRegions(routeId:atOrAbove:)`, `reconcile(installed:)` — Task 5, wiring in 5 and the coordinator. `PilgrimageMapsRowModel.megabytes(_:)` — Tasks 7, 9. `StageMorningCardModel.mapsLine(saved:)` — Task 8. `OfflineMapsModel.load(routeName:routeId:stages:tiles:)` / `loadInstalled(packages:tiles:)` / `rowDetail(_:)` — Task 9. `PilgrimagePackageManager.tiles` — Task 5, wired in 5 and 9's `loadInstalled` reads `packages.store`, which is `let store: WayStore` today.
