# Stage Links (iOS) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tapping `https://honor.pilgrimapp.org/<route>/<stage>` opens Pilgrim on that stage: its overview with Begin if the route is on the phone, otherwise the route screen with the stage in view and the existing download prompt raised. An honor-host link this build can't read says "this link needs a newer Pilgrim" instead of doing nothing.

**Architecture:** `HonorLink.parse` returns a `HonorLinkDestination` (share, stage, or unrecognised) instead of a bare share id, and one coordinator entry point `open(_:)` routes it. A pure `StageLinkResolver` turns "what's installed" plus the catalog into an outcome; `MainCoordinator.openStage` gathers those inputs through injectable closures (so specs need no disk or network) and performs the outcome using the existing AF60 park-and-promote handoffs. The route screen is presented in its own sheet with a new `focusStage` input.

**Tech Stack:** Swift 5 (Xcode project, CocoaPods + SPM), SwiftUI, Combine, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-28-stage-links-design.md` (commit `b27c071`). §1–§3 and §7.1–§7.2 are this plan. Two refinements, both inside the spec's intent: `StageLinkOutcome.routeSheet` carries a whole `HonorRouteLink` (entry, release, focus) rather than `(entry, focus)`, because presenting the sheet needs the catalog's release too; and `HonorRouteLink.id` includes the focus, so a second link to another stage of an open route re-presents the sheet.

## Global Constraints

- Work in worktree `.worktrees/stage-links` on branch `feat/stage-links` (Task 1, Step 0 creates it). Never commit to `main`. Never bare `git stash`. PR opened on the owner's go. **No TestFlight dispatch without the owner explicitly saying go.**
- The worktree needs `Secrets.xcconfig` copied from the main checkout before the first build, or Mapbox 401s.
- New Swift files are registered with `ruby scripts/xcode-add.rb <Pilgrim|UnitTests> <path/from/repo/root.swift>` immediately after creation, and `Pilgrim.xcodeproj/project.pbxproj` is committed with them.
- Link shape: `https://honor.pilgrimapp.org/<route>/<stage>` with optional trailing slash; `<route>` passes `WayStore.isValidRouteId`; `<stage>` matches `\A[1-9][0-9]{0,2}\z` and is ≤ `PilgrimageWayImporter.maxStageCount` (200). Stage links parse on the honor host only. The URL counts from 1; `HonorLinkDestination.stage.index` counts from 0.
- Toast copy, verbatim, lowercase: `reaching for the route…`, `this route isn't in Pilgrim yet`, `this link needs a newer Pilgrim`, and the existing `finish this walk first`. Catalog failures use `PilgrimageCopy.line(for:)`.
- AF60: never two sheet presentations in one update. Anything asked for while the Ways sheet, a summary, an overview or the route sheet is up is parked and promoted from that sheet's dismiss.
- A Begin in flight (`pendingStartWay`) or a running walk (`activeWalkViewModel`) always wins over a link; the link is dropped silently once it resolves.
- Typography only via `Constants.Typography.*`. Comments explain why, never what. No commented-out code. No `= nil` initialisers on optionals (SwiftLint `implicit_optional_initialization`). `VStack(alignment: .leading, …)` for stacks with varying-width rows.
- Every commit message ends with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Tests run with: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/pilgrim-stage-dd -only-testing:UnitTests/<TestClass> 2>&1 | grep -E "error:|failed\)|Executed .* tests|\*\* TEST"`.

## Review Focus

- **A second stage link while the route sheet is already open** (same route, another stage) → the sheet re-presents focused on the new stage, not left on the old one. Pinned in Task 2 (`testASecondStageLinkSwapsTheOpenRouteSheet`) and Task 1 (`testFocusIsPartOfTheSheetIdentity`).
- **A stage link arriving while a share link is still importing** → the share import is cancelled, `honorImportState` goes back to `.idle`, and the share's overview never lands on top later. Pinned in Task 2 (`testStageLinkCancelsAShareImportInFlight`).
- **A downloaded stage with no network at all** → its overview still opens; the catalog is never needed. Pinned in Task 1 (`testInstalledWithTheStageNeedsNoCatalog`) and Task 2 (`testStageLinkForAnInstalledStageOpensItsOverview`, whose catalog load throws).
- **A stage link pasted into the Ways sheet** → the Ways sheet closes and the route sheet opens after it, never over it. Pinned in Task 2 (`testStageLinkOverTheWaysSheetParksUntilItCloses`) and Task 3 (paste test in `HonorLinkTests`).
- **A link whose path has a percent-encoded newline or other junk on the honor host** → "this link needs a newer Pilgrim", never a share id or a stage. Pinned in Task 3 (`testTrailingNewlineIsRejected`, updated).

---

### Task 1: The resolver

**Files:**
- Create: `Pilgrim/Models/Honor/StageLink.swift`
- Test: `UnitTests/Honor/StageLinkResolverTests.swift`

**Interfaces:**
- Consumes: `PilgrimageCatalog` (`release: String`, `routes: [PilgrimageCatalogEntry]`), `PilgrimageCatalogEntry` (`id`, `stageCount`; `Equatable`), `WayStore.stageWayId(routeId:stageIndex:) -> String`.
- Produces:
  - `struct HonorRouteLink: Identifiable, Equatable { let entry: PilgrimageCatalogEntry; let release: String; let focus: Int?; var id: String }`
  - `enum StageLinkOutcome: Equatable { case overview(wayId: String); case routeSheet(HonorRouteLink); case notInCatalog; case needsCatalog }`
  - `enum StageLinkResolver { static func resolve(routeId: String, index: Int, installedRouteId: String?, stageWayExists: Bool, catalog: PilgrimageCatalog?) -> StageLinkOutcome }`

- [ ] **Step 0: Create the worktree**

From the main checkout (currently on `feat/stage-links`, which holds the spec and this plan):

```bash
git switch main
git worktree add .worktrees/stage-links feat/stage-links
cp Secrets.xcconfig .worktrees/stage-links/Secrets.xcconfig
cd .worktrees/stage-links && pod install
```

Every later command runs inside `.worktrees/stage-links`.

- [ ] **Step 1: Write the failing tests**

Create `UnitTests/Honor/StageLinkResolverTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class StageLinkResolverTests: XCTestCase {

    private let frances = PilgrimageCatalogEntry(id: "camino-frances", name: "Camino Francés", names: [:],
                                                 country: "ES", region: "Europe", distanceKm: 780,
                                                 tradition: "christian", stageCount: 33, bytes: 1_000)

    private var catalog: PilgrimageCatalog { PilgrimageCatalog(release: "v1.12.0", routes: [frances]) }

    private func resolve(routeId: String = "camino-frances", index: Int = 13, installed: String? = nil,
                         wayExists: Bool = false, catalog: PilgrimageCatalog?) -> StageLinkOutcome {
        StageLinkResolver.resolve(routeId: routeId, index: index, installedRouteId: installed,
                                  stageWayExists: wayExists, catalog: catalog)
    }

    private func sheet(focus: Int?) -> StageLinkOutcome {
        .routeSheet(HonorRouteLink(entry: frances, release: "v1.12.0", focus: focus))
    }

    func testInstalledWithTheStageOpensTheOverview() {
        XCTAssertEqual(resolve(installed: "camino-frances", wayExists: true, catalog: catalog),
                       .overview(wayId: "pilgrimage:camino-frances:13"))
    }

    func testInstalledWithTheStageNeedsNoCatalog() {
        XCTAssertEqual(resolve(installed: "camino-frances", wayExists: true, catalog: nil),
                       .overview(wayId: "pilgrimage:camino-frances:13"))
    }

    func testInstalledButTheStageMissingOpensTheRouteFocused() {
        XCTAssertEqual(resolve(installed: "camino-frances", wayExists: false, catalog: catalog), sheet(focus: 13))
    }

    func testNotInstalledOpensTheRouteFocused() {
        XCTAssertEqual(resolve(catalog: catalog), sheet(focus: 13))
    }

    func testAnotherRouteInstalledOpensTheRouteFocused() {
        XCTAssertEqual(resolve(installed: "camino-norte", catalog: catalog), sheet(focus: 13),
                       "Replace is the route screen's question to ask, not the link's")
    }

    func testAStagePastTheEndOpensTheRouteUnfocused() {
        XCTAssertEqual(resolve(index: 33, catalog: catalog), sheet(focus: nil))
    }

    func testARouteAbsentFromTheCatalogSaysSo() {
        XCTAssertEqual(resolve(routeId: "camino-imaginario", catalog: catalog), .notInCatalog)
    }

    func testNoCatalogInHandAsksForOne() {
        XCTAssertEqual(resolve(catalog: nil), .needsCatalog)
    }

    func testFocusIsPartOfTheSheetIdentity() {
        let fourteen = HonorRouteLink(entry: frances, release: "v1.12.0", focus: 13)
        let twenty = HonorRouteLink(entry: frances, release: "v1.12.0", focus: 19)
        XCTAssertNotEqual(fourteen.id, twenty.id)
        XCTAssertNotEqual(HonorRouteLink(entry: frances, release: "v1.12.0", focus: nil).id, fourteen.id)
    }
}
```

Register it: `ruby scripts/xcode-add.rb UnitTests UnitTests/Honor/StageLinkResolverTests.swift`

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command with `-only-testing:UnitTests/StageLinkResolverTests`.
Expected: build error — `cannot find 'StageLinkResolver' in scope`.

- [ ] **Step 3: Write the resolver**

Create `Pilgrim/Models/Honor/StageLink.swift`:

```swift
import Foundation

/// A route screen opened from a stage link, and the stage it should bring
/// into view. The id carries the focus, so a second link to another stage of
/// the same route re-presents the sheet rather than leaving it where it was.
struct HonorRouteLink: Identifiable, Equatable {
    let entry: PilgrimageCatalogEntry
    let release: String
    let focus: Int?

    var id: String { "\(entry.id):\(focus.map(String.init) ?? "-")" }
}

enum StageLinkOutcome: Equatable {
    case overview(wayId: String)
    case routeSheet(HonorRouteLink)
    case notInCatalog
    case needsCatalog
}

/// What a stage link does, decided without disk or network: the coordinator
/// gathers what is on the phone and what the catalog says, and this names
/// the screen. It is exactly what tapping that stage on the route screen
/// does, so a downloaded stage never waits on the catalog.
enum StageLinkResolver {

    static func resolve(routeId: String, index: Int, installedRouteId: String?,
                        stageWayExists: Bool, catalog: PilgrimageCatalog?) -> StageLinkOutcome {
        if installedRouteId == routeId, stageWayExists {
            return .overview(wayId: WayStore.stageWayId(routeId: routeId, stageIndex: index))
        }
        guard let catalog else { return .needsCatalog }
        guard let entry = catalog.routes.first(where: { $0.id == routeId }) else { return .notInCatalog }
        let focus = (0..<entry.stageCount).contains(index) ? index : nil
        return .routeSheet(HonorRouteLink(entry: entry, release: catalog.release, focus: focus))
    }
}
```

Register it: `ruby scripts/xcode-add.rb Pilgrim Pilgrim/Models/Honor/StageLink.swift`

- [ ] **Step 4: Run the tests to verify they pass**

Run the test command with `-only-testing:UnitTests/StageLinkResolverTests`.
Expected: `Executed 9 tests, with 0 failures`.

- [ ] **Step 5: Commit**

```bash
git add Pilgrim/Models/Honor/StageLink.swift UnitTests/Honor/StageLinkResolverTests.swift Pilgrim.xcodeproj/project.pbxproj
git commit -F - <<'EOF'
feat(honor): decide where a stage link leads

A pure resolver: a downloaded stage opens its overview with no network,
anything else opens the route screen with the stage in view, and a route
the catalog doesn't know says so. It is what tapping the stage on the
route screen already does.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 2: The coordinator opens a stage

**Files:**
- Modify: `Pilgrim/Scenes/Root/MainCoordinatorView.swift` (the `MainCoordinator` class: properties near line 18–41; `chooseWay` ~line 195; new `openStage` / `openRouteLink` after `openWay` ~line 212; `openOverview` ~line 247; `promotePendingHonorWay` ~line 312; `handleOverviewDismiss` ~line 325)
- Test: `UnitTests/Honor/MainCoordinatorHonorTests.swift` (new `extension MainCoordinatorHonorTests` above the file-private `AsyncGate`)

**Interfaces:**
- Consumes: `StageLinkResolver.resolve(...)`, `StageLinkOutcome`, `HonorRouteLink` (Task 1); existing `openOverview(for:)`, `showLinkToast(_:)`, `importTask`, `waitForImport()` (DEBUG).
- Produces (used by Tasks 3 and 4):
  - `@Published var honorRouteLink: HonorRouteLink?`
  - `var pendingRouteLink: HonorRouteLink?`
  - `var installedRouteId: @MainActor () -> String?`, `var loadStageWay: (String) -> Way?`, `var cachedCatalog: @MainActor () -> PilgrimageCatalog?`, `var loadCatalog: @MainActor () async throws -> PilgrimageCatalog`
  - `func openStage(routeId: String, index: Int)`
  - `func openRouteLink(_ link: HonorRouteLink)`
  - `promotePendingHonorWay()` now also promotes a parked route link.

- [ ] **Step 1: Write the failing tests**

Append to `UnitTests/Honor/MainCoordinatorHonorTests.swift`, directly above the `/// A one-shot gate:` comment for `AsyncGate`:

```swift
// MARK: - Stage links

extension MainCoordinatorHonorTests {

    private var frances: PilgrimageCatalogEntry {
        PilgrimageCatalogEntry(id: "camino-frances", name: "Camino Francés", names: [:], country: "ES",
                               region: "Europe", distanceKm: 780, tradition: "christian", stageCount: 33, bytes: 1_000)
    }

    private var catalog: PilgrimageCatalog { PilgrimageCatalog(release: "v1.12.0", routes: [frances]) }

    private func link(focus: Int?) -> HonorRouteLink {
        HonorRouteLink(entry: frances, release: "v1.12.0", focus: focus)
    }

    /// Everything `openStage` reads, answered without a package on disk or a
    /// network. The catalog load fails unless a spec says otherwise, so a
    /// spec that reaches it by accident shows up as a toast.
    private func stub(_ coordinator: MainCoordinator, installed: String? = nil, way: Way? = nil,
                      cached: PilgrimageCatalog? = nil,
                      load: @escaping @MainActor () async throws -> PilgrimageCatalog = { throw PilgrimageError.catalogUnreachable }) {
        coordinator.installedRouteId = { installed }
        coordinator.loadStageWay = { _ in way }
        coordinator.cachedCatalog = { cached }
        coordinator.loadCatalog = load
    }

    @MainActor
    func testStageLinkForAnInstalledStageOpensItsOverview() async throws {
        let coordinator = MainCoordinator()
        let way = try makeWay()
        stub(coordinator, installed: "camino-frances", way: way)

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.honorOverviewWay?.id, way.id, "a downloaded stage never waits on the catalog")
        XCTAssertNil(coordinator.honorRouteLink)
        XCTAssertNil(coordinator.pendingLinkToast)
    }

    @MainActor
    func testStageLinkForARouteNotOnThePhoneOpensTheRouteFocused() async {
        let coordinator = MainCoordinator()
        stub(coordinator, cached: catalog)

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
        XCTAssertNil(coordinator.honorOverviewWay)
    }

    @MainActor
    func testStageLinkLoadsTheCatalogWhenNoneIsInHand() async {
        let coordinator = MainCoordinator()
        let gate = AsyncGate()
        let catalog = self.catalog
        stub(coordinator, load: {
            await gate.wait()
            return catalog
        })

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await settle()
        XCTAssertEqual(coordinator.pendingLinkToast, "reaching for the route…")

        gate.open()
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
        XCTAssertNil(coordinator.pendingLinkToast)
    }

    @MainActor
    func testStageLinkForARouteTheCatalogLacksSaysSo() async {
        let coordinator = MainCoordinator()
        stub(coordinator, cached: PilgrimageCatalog(release: "v1.12.0", routes: []))

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.pendingLinkToast, "this route isn't in Pilgrim yet")
        XCTAssertNil(coordinator.honorRouteLink)
    }

    @MainActor
    func testStageLinkWithTheCatalogOutOfReachSaysSo() async {
        let coordinator = MainCoordinator()
        stub(coordinator)

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.pendingLinkToast, PilgrimageCopy.line(for: .catalogUnreachable))
        XCTAssertNil(coordinator.honorRouteLink)
    }

    func testStageLinkWhileWalkingSetsTheToast() throws {
        let coordinator = MainCoordinator()
        addTeardownBlock { coordinator.cancelWalk() }
        coordinator.startWalk()
        _ = try XCTUnwrap(coordinator.activeWalkViewModel, "the guard under test only means something with a walk running")

        coordinator.openStage(routeId: "camino-frances", index: 13)

        XCTAssertEqual(coordinator.pendingLinkToast, "finish this walk first")
        XCTAssertNil(coordinator.honorRouteLink)
        XCTAssertNil(coordinator.pendingRouteLink)
    }

    @MainActor
    func testStageLinkOverTheWaysSheetParksUntilItCloses() async {
        let coordinator = MainCoordinator()
        stub(coordinator, cached: catalog)
        coordinator.chooseWay()

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertFalse(coordinator.honorWaysPresented)
        XCTAssertNil(coordinator.honorRouteLink, "the route sheet must wait for the Ways sheet to finish closing")
        XCTAssertEqual(coordinator.pendingRouteLink, link(focus: 13))

        coordinator.promotePendingHonorWay()

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
        XCTAssertNil(coordinator.pendingRouteLink)
    }

    @MainActor
    func testStageLinkOverAnOverviewClosesItAndOpensOnDismiss() async throws {
        let coordinator = MainCoordinator()
        addTeardownBlock { coordinator.cancelWalk() }
        stub(coordinator, cached: catalog)
        coordinator.openOverview(for: try makeWay())

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertNil(coordinator.honorOverviewWay)
        XCTAssertNil(coordinator.honorRouteLink)
        XCTAssertEqual(coordinator.pendingRouteLink, link(focus: 13))

        coordinator.handleOverviewDismiss()

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
        XCTAssertNil(coordinator.activeWalkViewModel)
    }

    @MainActor
    func testABeginInFlightWinsOverAStageLink() async throws {
        let coordinator = MainCoordinator()
        addTeardownBlock { coordinator.cancelWalk() }
        stub(coordinator, cached: catalog)
        let way = try makeWay()
        coordinator.openOverview(for: way)
        coordinator.startHonor(way: way)

        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()

        XCTAssertNil(coordinator.honorRouteLink)
        XCTAssertNil(coordinator.pendingRouteLink)
        XCTAssertEqual(coordinator.pendingStartWay?.id, way.id)
    }

    func testChoosingAStageInsideTheRouteSheetParksTheWay() throws {
        let coordinator = MainCoordinator()
        let way = try makeWay()
        coordinator.honorRouteLink = link(focus: 13)

        coordinator.openOverview(for: way)

        XCTAssertNil(coordinator.honorRouteLink)
        XCTAssertNil(coordinator.honorOverviewWay, "the overview must wait for the route sheet to finish closing")
        XCTAssertEqual(coordinator.pendingHonorWay?.id, way.id)

        coordinator.promotePendingHonorWay()

        XCTAssertEqual(coordinator.honorOverviewWay?.id, way.id)
    }

    func testASecondStageLinkSwapsTheOpenRouteSheet() {
        let coordinator = MainCoordinator()
        coordinator.honorRouteLink = link(focus: 13)

        coordinator.openRouteLink(link(focus: 19))

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 19))
        XCTAssertNil(coordinator.pendingRouteLink)
    }

    @MainActor
    func testStageLinkCancelsAShareImportInFlight() async throws {
        let coordinator = MainCoordinator()
        let held = heldImport(try makeWay())
        coordinator.importShare = held.fetch
        stub(coordinator, cached: catalog)

        coordinator.openWay(shareId: "Qoi4YmPHLN")
        XCTAssertEqual(coordinator.honorImportState, .fetching)
        coordinator.openStage(routeId: "camino-frances", index: 13)
        await coordinator.waitForImport()
        held.release()
        await settle()

        XCTAssertEqual(coordinator.honorImportState, .idle)
        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
        XCTAssertNil(coordinator.honorOverviewWay, "the cancelled share import must land nothing")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command with `-only-testing:UnitTests/MainCoordinatorHonorTests`.
Expected: build error — `value of type 'MainCoordinator' has no member 'installedRouteId'` (and the other new members).

- [ ] **Step 3: Add the coordinator state and injectables**

In `MainCoordinator`, after `@Published var pendingLinkToast: String?`:

```swift
    @Published var honorRouteLink: HonorRouteLink?
```

After `var pendingStartWay: Way?`:

```swift
    /// A route screen waiting for the sheet in front of it to finish closing.
    /// AF60 again: see `openRouteLink(_:)`.
    var pendingRouteLink: HonorRouteLink?
```

After `var pilgrimageLedgers = PilgrimageLedgerStore()`:

```swift
    /// Injectable so a spec can say what is on the phone and what the
    /// catalog holds without a package on disk or a network. Production
    /// reads the real managers.
    var installedRouteId: @MainActor () -> String? = { PilgrimagePackageManager.shared.installed()?.routeId }
    var loadStageWay: (String) -> Way? = { WayStore.shared.load(id: $0) }
    var cachedCatalog: @MainActor () -> PilgrimageCatalog? = { PilgrimageCatalogService.shared.catalog }
    var loadCatalog: @MainActor () async throws -> PilgrimageCatalog = { try await PilgrimageCatalogService.shared.load() }
```

- [ ] **Step 4: Share the managers' wiring between both doors into the route screen**

Replace `chooseWay()` with:

```swift
    /// Resets the import state and any toast left over from a previous link
    /// so a stale failure line never greets the next opening of the sheet.
    func chooseWay() {
        wirePilgrimageManagers()
        honorImportState = .idle
        showLinkToast(nil)
        honorWaysPresented = true
    }

    /// Downloading a second route, Replace, Update, and Remove are all
    /// refused while a walk is on; this is where the managers learn what
    /// "on" means, and where Replace and Remove learn to take the maps with
    /// them. A stage link reaches the route screen without the Ways sheet,
    /// so both doors call this.
    private func wirePilgrimageManagers() {
        Task { @MainActor in
            PilgrimagePackageManager.shared.isWalkActive = { [weak self] in self?.activeWalkViewModel != nil }
            PilgrimageTilesManager.shared.isWalkActive = { [weak self] in self?.activeWalkViewModel != nil }
            PilgrimagePackageManager.shared.tiles = PilgrimageTilesManager.shared
        }
    }
```

- [ ] **Step 5: Add `openStage` and `openRouteLink`**

Directly after `openWay(shareId:)`:

```swift
    /// A stage link does what tapping that stage on the route screen does:
    /// its overview if the route is on the phone, otherwise the route screen
    /// with the stage in view. It shares `importTask` with share links, so
    /// the newest link of either kind wins.
    func openStage(routeId: String, index: Int) {
        guard activeWalkViewModel == nil else { showLinkToast("finish this walk first"); return }
        importTask?.cancel()
        // The share import this replaces will never land, so its spinner
        // must not wait for the Ways sheet's next opening.
        if honorImportState == .fetching { honorImportState = .idle }
        wirePilgrimageManagers()
        importTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let installed = self.installedRouteId()
            let way = installed == routeId
                ? self.loadStageWay(WayStore.stageWayId(routeId: routeId, stageIndex: index))
                : nil
            func resolve(_ catalog: PilgrimageCatalog?) -> StageLinkOutcome {
                StageLinkResolver.resolve(routeId: routeId, index: index, installedRouteId: installed,
                                          stageWayExists: way != nil, catalog: catalog)
            }
            var outcome = resolve(self.cachedCatalog())
            if outcome == .needsCatalog {
                self.showLinkToast("reaching for the route…")
                do {
                    let catalog = try await self.loadCatalog()
                    guard !Task.isCancelled else { return }
                    outcome = resolve(catalog)
                } catch {
                    guard !Task.isCancelled else { return }
                    self.importTask = nil
                    self.showLinkToast(PilgrimageCopy.line(for: (error as? PilgrimageError) ?? .catalogUnreachable))
                    return
                }
            }
            self.importTask = nil
            // A Begin already in flight, or a walk started while the catalog
            // loaded, wins: nothing may interrupt it.
            guard self.activeWalkViewModel == nil, self.pendingStartWay == nil else {
                self.showLinkToast(nil)
                return
            }
            switch outcome {
            case .overview:
                self.showLinkToast(nil)
                if let way { self.openOverview(for: way) }
            case .routeSheet(let link):
                self.showLinkToast(nil)
                self.openRouteLink(link)
            case .notInCatalog, .needsCatalog:
                self.showLinkToast("this route isn't in Pilgrim yet")
            }
        }
    }

    /// AF60: a route screen asked for while the Ways sheet, a summary or an
    /// overview is up waits for that sheet to close, and its dismiss
    /// promotes it. An open route sheet is simply swapped, since the link's
    /// id carries its focus.
    func openRouteLink(_ link: HonorRouteLink) {
        if honorWaysPresented || completedSnapshot != nil || honorOverviewWay != nil {
            pendingRouteLink = link
            honorWaysPresented = false
            honorOverviewWay = nil
        } else {
            honorRouteLink = link
        }
    }
```

- [ ] **Step 6: Park around the route sheet and promote route links**

In `openOverview(for:)`, change the parking branch so the route sheet counts as a sheet in front:

```swift
        if honorWaysPresented || honorRouteLink != nil || completedSnapshot != nil {
            pendingHonorWay = way
            honorWaysPresented = false
            honorRouteLink = nil
        } else {
```

(Keep the existing comment above it, and add one sentence to it: "Choosing a stage inside the route sheet lands here too.")

Replace `promotePendingHonorWay()` with:

```swift
    func promotePendingHonorWay() {
        if let way = pendingHonorWay {
            pendingHonorWay = nil
            honorOverviewWay = way
            gather(way)
        } else {
            promotePendingRouteLink()
        }
    }

    private func promotePendingRouteLink() {
        guard let link = pendingRouteLink else { return }
        pendingRouteLink = nil
        honorRouteLink = link
    }
```

In `handleOverviewDismiss()`, replace the `if let way = pendingStartWay { … }` block with:

```swift
        if let way = pendingStartWay {
            pendingStartWay = nil
            pendingRouteLink = nil
            startWalk(mode: .honor, way: way)
        } else if honorOverviewWay == nil {
            // Not on an item swap: the incoming overview is already showing.
            promotePendingRouteLink()
        }
```

- [ ] **Step 7: Run the tests to verify they pass**

Run the test command with `-only-testing:UnitTests/MainCoordinatorHonorTests`.
Expected: all tests pass, the existing AF60 and import-race tests included.

- [ ] **Step 8: Commit**

```bash
git add Pilgrim/Scenes/Root/MainCoordinatorView.swift UnitTests/Honor/MainCoordinatorHonorTests.swift
git commit -F - <<'EOF'
feat(honor): the coordinator opens a stage from a link

openStage gathers what is on the phone and what the catalog says, asks the
resolver, and opens either the stage's overview or the route sheet. The
route sheet joins the AF60 handoffs: it waits for the Ways sheet, a
summary or an overview to close, and a stage chosen inside it waits for
it to close. A Begin in flight always wins.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 3: Links become destinations

**Files:**
- Modify: `Pilgrim/Models/Honor/HonorLink.swift` (whole file)
- Modify: `Pilgrim/PilgrimApp.swift:30-64` (`pendingShareId` → `pendingLink`, `route(_:)`)
- Modify: `Pilgrim/Scenes/Root/MainCoordinatorView.swift` (new `open(_:)` before `openWay`)
- Modify: `Pilgrim/Scenes/Root/MainTabView.swift:64-106` (paste closure, `.onReceive`, `.onAppear`, new private `open(_:)`)
- Test: `UnitTests/Honor/HonorLinkTests.swift`, `UnitTests/Honor/MainCoordinatorHonorTests.swift`

**Interfaces:**
- Consumes: `openWay(shareId:)`, `openStage(routeId:index:)` (Task 2), `WayStore.isValidRouteId(_:)`, `PilgrimageWayImporter.maxStageCount`.
- Produces:
  - `enum HonorLinkDestination: Equatable { case share(id: String); case stage(routeId: String, index: Int); case unrecognised }`
  - `HonorLink.parse(_ url: URL) -> HonorLinkDestination?`, `HonorLink.parse(text: String) -> HonorLinkDestination?` (never `.unrecognised`)
  - `@MainActor static var PilgrimApp.pendingLink: HonorLinkDestination?`
  - Notification `.pilgrimOpenWay` with `userInfo["link"]: HonorLinkDestination`
  - `MainCoordinator.open(_ link: HonorLinkDestination)`

- [ ] **Step 1: Rewrite the link tests**

Replace the body of `UnitTests/Honor/HonorLinkTests.swift` with:

```swift
import XCTest
@testable import Pilgrim

final class HonorLinkTests: XCTestCase {

    private func url(_ s: String) -> URL { URL(string: s)! }

    func testAcceptedForms() {
        for s in ["https://honor.pilgrimapp.org/Qoi4YmPHLN", "https://honor.pilgrimapp.org/Qoi4YmPHLN/",
                  "https://honor.pilgrimapp.org/Qoi4YmPHLN?utm=x#m3", "https://walk.pilgrimapp.org/Qoi4YmPHLN",
                  "walk.pilgrimapp.org/Qoi4YmPHLN", "Qoi4YmPHLN", "  Qoi4YmPHLN\n"] {
            XCTAssertEqual(HonorLink.parse(text: s), .share(id: "Qoi4YmPHLN"), s)
        }
        XCTAssertEqual(HonorLink.parse(url("https://honor.pilgrimapp.org/Qoi4YmPHLN")), .share(id: "Qoi4YmPHLN"))
    }

    func testRejections() {
        for s in ["https://example.com/Qoi4YmPHLN", "https://walk.pilgrimapp.org/", "https://walk.pilgrimapp.org/short",
                  "https://walk.pilgrimapp.org/Qoi4YmPHLN/audio/1.m4a", "Qoi4YmPHL", "Qoi4YmPHLN1", ""] {
            XCTAssertNil(HonorLink.parse(text: s), s)
        }
    }

    func testHostIsCaseInsensitive() {
        XCTAssertEqual(HonorLink.parse(text: "https://HONOR.pilgrimapp.org/Qoi4YmPHLN"), .share(id: "Qoi4YmPHLN"))
        XCTAssertEqual(HonorLink.parse(url("https://HONOR.pilgrimapp.org/Qoi4YmPHLN")), .share(id: "Qoi4YmPHLN"))
    }

    func testStageLinksCountFromOne() {
        for s in ["https://honor.pilgrimapp.org/camino-frances/14", "https://honor.pilgrimapp.org/camino-frances/14/",
                  "https://honor.pilgrimapp.org/camino-frances/14?utm_source=pilgrimages#x"] {
            XCTAssertEqual(HonorLink.parse(url(s)), .stage(routeId: "camino-frances", index: 13), s)
        }
        XCTAssertEqual(HonorLink.parse(url("https://honor.pilgrimapp.org/shikoku-88-tosa/1")),
                       .stage(routeId: "shikoku-88-tosa", index: 0))
        XCTAssertEqual(HonorLink.parse(url("https://honor.pilgrimapp.org/camino-frances/200")),
                       .stage(routeId: "camino-frances", index: 199))
    }

    func testMalformedStageLinksOnTheHonorHostAreUnrecognised() {
        for s in ["https://honor.pilgrimapp.org/camino-frances/0", "https://honor.pilgrimapp.org/camino-frances/014",
                  "https://honor.pilgrimapp.org/camino-frances/201", "https://honor.pilgrimapp.org/Camino-Frances/14",
                  "https://honor.pilgrimapp.org/camino-frances", "https://honor.pilgrimapp.org/a/b/c",
                  "https://honor.pilgrimapp.org/Qoi4YmPHLN/extra"] {
            XCTAssertEqual(HonorLink.parse(url(s)), .unrecognised, s)
        }
    }

    func testStageLinksLiveOnlyOnTheHonorHost() {
        XCTAssertNil(HonorLink.parse(url("https://walk.pilgrimapp.org/camino-frances/14")))
        XCTAssertNil(HonorLink.parse(url("https://example.com/camino-frances/14")))
    }

    func testTheHonorHostRootIsNotALink() {
        XCTAssertNil(HonorLink.parse(url("https://honor.pilgrimapp.org/")))
        XCTAssertNil(HonorLink.parse(url("https://honor.pilgrimapp.org")))
    }

    func testPastedStageLinksAreAccepted() {
        XCTAssertEqual(HonorLink.parse(text: "honor.pilgrimapp.org/camino-frances/14"),
                       .stage(routeId: "camino-frances", index: 13))
        XCTAssertEqual(HonorLink.parse(text: " https://honor.pilgrimapp.org/camino-frances/14\n"),
                       .stage(routeId: "camino-frances", index: 13))
    }

    func testPastedTextNeverComesBackUnrecognised() {
        XCTAssertNil(HonorLink.parse(text: "https://honor.pilgrimapp.org/camino-frances/0"))
        XCTAssertNil(HonorLink.parse(text: "honor.pilgrimapp.org/whatever/else/here"))
    }

    /// A cold-launch link is stashed on `PilgrimApp` for `MainTabView.onAppear`
    /// to claim once mounted; reading it must also clear it, so the same link
    /// can't be replayed a second time.
    @MainActor
    func testPendingLinkIsDrainedOnce() {
        PilgrimApp.pendingLink = .stage(routeId: "camino-frances", index: 13)

        let drained = PilgrimApp.pendingLink
        PilgrimApp.pendingLink = nil

        XCTAssertEqual(drained, .stage(routeId: "camino-frances", index: 13))
        XCTAssertNil(PilgrimApp.pendingLink)
    }

    /// `$` in a regex matches before a trailing newline, so an id pasted with
    /// one used to pass every shape check in the pipeline.
    func testTrailingNewlineIsRejected() {
        // Pasted text is trimmed first, so the newline has to arrive by a
        // path that does not trim — an encoded one inside the URL itself.
        XCTAssertEqual(HonorLink.parse(url("https://honor.pilgrimapp.org/Qoi4YmPHLN%0A")), .unrecognised)
        XCTAssertEqual(HonorLink.parse(url("https://honor.pilgrimapp.org/camino-frances/14%0A")), .unrecognised)
        XCTAssertFalse(WayImporter.isShareId("Qoi4YmPHLN\n"))
        XCTAssertFalse(WayStore.isValidId("share:Qoi4YmPHLN\n"))
        XCTAssertFalse(WayStore.isValidId("walk:\(UUID().uuidString)\n"))
    }
}
```

Append to the `// MARK: - Stage links` extension in `UnitTests/Honor/MainCoordinatorHonorTests.swift`:

```swift
    func testAnUnrecognisedLinkSaysANewerPilgrimIsNeeded() {
        let coordinator = MainCoordinator()

        coordinator.open(.unrecognised)

        XCTAssertEqual(coordinator.pendingLinkToast, "this link needs a newer Pilgrim")
        XCTAssertNil(coordinator.honorRouteLink)
        XCTAssertEqual(coordinator.honorImportState, .idle)
    }

    @MainActor
    func testAStageDestinationOpensTheStage() async {
        let coordinator = MainCoordinator()
        stub(coordinator, cached: catalog)

        coordinator.open(.stage(routeId: "camino-frances", index: 13))
        await coordinator.waitForImport()

        XCTAssertEqual(coordinator.honorRouteLink, link(focus: 13))
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run the test command with `-only-testing:UnitTests/HonorLinkTests -only-testing:UnitTests/MainCoordinatorHonorTests`.
Expected: build errors — `cannot find 'HonorLinkDestination'`-style mismatches (`.share(id:)` against `String?`), `PilgrimApp` has no `pendingLink`, `MainCoordinator` has no `open`.

- [ ] **Step 3: Rewrite `HonorLink.swift`**

Replace the whole of `Pilgrim/Models/Honor/HonorLink.swift` with:

```swift
import Foundation

/// Where a link leads. `unrecognised` is an honor-host address this build
/// can't read, most likely a shape a newer Pilgrim knows, so the walker is
/// told instead of met with silence.
enum HonorLinkDestination: Equatable {
    case share(id: String)
    case stage(routeId: String, index: Int)
    case unrecognised
}

/// The one place a link becomes a destination, for both a universal link
/// the OS hands us and text the walker pasted.
enum HonorLink {

    static let hosts: Set<String> = ["honor.pilgrimapp.org", "walk.pilgrimapp.org"]
    /// Stage links live only where their fallback page does.
    static let stageHost = "honor.pilgrimapp.org"
    private static let idPattern = "\\A[A-Za-z0-9_-]{10}\\z"
    private static let stageNumberPattern = "\\A[1-9][0-9]{0,2}\\z"

    static func parse(_ url: URL) -> HonorLinkDestination? {
        guard let host = url.host?.lowercased(), hosts.contains(host) else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard !parts.isEmpty else { return nil }
        if parts.count == 1, isID(parts[0]) { return .share(id: parts[0]) }
        guard host == stageHost else { return nil }
        if parts.count == 2, let index = stageIndex(routeId: parts[0], number: parts[1]) {
            return .stage(routeId: parts[0], index: index)
        }
        return .unrecognised
    }

    /// Pasted text that isn't a link Pilgrim can open is simply not a link:
    /// the paste field already has its own way of saying so.
    static func parse(text: String) -> HonorLinkDestination? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if isID(trimmed) { return .share(id: trimmed) }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), let link = parse(url), link != .unrecognised else { return nil }
        return link
    }

    private static func isID(_ s: String) -> Bool {
        s.range(of: idPattern, options: .regularExpression) != nil
    }

    /// The link counts stages from 1, as the route screen shows them; the
    /// data counts from 0.
    private static func stageIndex(routeId: String, number: String) -> Int? {
        guard WayStore.isValidRouteId(routeId),
              number.range(of: stageNumberPattern, options: .regularExpression) != nil,
              let n = Int(number), n <= PilgrimageWayImporter.maxStageCount else { return nil }
        return n - 1
    }
}

extension Notification.Name {
    static let pilgrimOpenWay = Notification.Name("pilgrimOpenWay")
}
```

- [ ] **Step 4: Carry the destination through `PilgrimApp`**

In `Pilgrim/PilgrimApp.swift`, replace `@MainActor static var pendingShareId: String?` with `@MainActor static var pendingLink: HonorLinkDestination?` (the doc comment above it stays, with "a link tapped" unchanged), and replace `route(_:)` and its doc comment with:

```swift
    /// Broadcast rather than routed directly: `MainTabView` owns the
    /// coordinator, and a link arriving before setup finishes has no
    /// `MainTabView` mounted to hear it. Stashing the link in `pendingLink`
    /// too means that cold-launch case isn't just broadcast into silence —
    /// `MainTabView.onAppear` drains it once mounted.
    @MainActor
    private static func route(_ url: URL) {
        guard let link = HonorLink.parse(url) else { return }
        pendingLink = link
        NotificationCenter.default.post(name: .pilgrimOpenWay, object: nil, userInfo: ["link": link])
    }
```

- [ ] **Step 5: One coordinator entry point**

In `MainCoordinator`, directly before `openWay(shareId:)`:

```swift
    /// Every link, from the OS or the paste field, arrives here.
    func open(_ link: HonorLinkDestination) {
        switch link {
        case .share(let id): openWay(shareId: id)
        case .stage(let routeId, let index): openStage(routeId: routeId, index: index)
        case .unrecognised: showLinkToast("this link needs a newer Pilgrim")
        }
    }
```

- [ ] **Step 6: Wire `MainTabView`**

In the `HonorWaysSheet(...)` call, replace the `onPaste` closure with:

```swift
                onPaste: { text in
                    if let link = HonorLink.parse(text: text) { coordinator.open(link) }
                }
```

Replace the `.onReceive(NotificationCenter.default.publisher(for: .pilgrimOpenWay))` and `.onAppear` blocks with:

```swift
        .onReceive(NotificationCenter.default.publisher(for: .pilgrimOpenWay)) { note in
            guard let link = note.userInfo?["link"] as? HonorLinkDestination else { return }
            // Consumed here too so a warm-launch link (this view already
            // mounted) doesn't sit in `pendingLink` for a later onAppear to
            // replay a second time.
            PilgrimApp.pendingLink = nil
            open(link)
        }
        .onAppear {
            // A link tapped on a cold launch posted before this view existed
            // to receive it (see `PilgrimApp.route`) — claim it exactly once.
            if let link = PilgrimApp.pendingLink {
                PilgrimApp.pendingLink = nil
                open(link)
            }
        }
```

Add to `MainTabView`, after `body`:

```swift
    /// Mid-walk the coordinator refuses and says so with a toast, so the tab
    /// must not switch out from under the walker for a link that is about to
    /// go nowhere. A link this build can't read goes nowhere either.
    private func open(_ link: HonorLinkDestination) {
        if coordinator.activeWalkViewModel == nil, link != .unrecognised { selectedTab = .path }
        coordinator.open(link)
    }
```

- [ ] **Step 7: Run the tests and a full build**

Run the test command with `-only-testing:UnitTests/HonorLinkTests -only-testing:UnitTests/MainCoordinatorHonorTests`.
Expected: all pass.
Then: `grep -rn "pendingShareId" Pilgrim UnitTests` prints nothing.

- [ ] **Step 8: Commit**

```bash
git add Pilgrim/Models/Honor/HonorLink.swift Pilgrim/PilgrimApp.swift Pilgrim/Scenes/Root/MainCoordinatorView.swift Pilgrim/Scenes/Root/MainTabView.swift UnitTests/Honor/HonorLinkTests.swift UnitTests/Honor/MainCoordinatorHonorTests.swift
git commit -F - <<'EOF'
feat(honor): read stage links, and say when a link needs a newer Pilgrim

A link is now a destination: a shared walk, a stage
(honor.pilgrimapp.org/<route>/<stage>, counted from 1), or an honor-host
address this build can't read. That last one says "this link needs a
newer Pilgrim" instead of opening the app to nothing, so the next new
link shape won't dead-end the way stage links do on today's builds.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 4: The route sheet

**Files:**
- Modify: `Pilgrim/Scenes/Honor/PilgrimageRouteView.swift` (properties ~line 66–100, `body` ~line 110, `stageSection` ~line 262, new `applyFocus()` in `// MARK: - Actions`)
- Modify: `Pilgrim/Scenes/Root/MainTabView.swift` (new `.sheet(item: $coordinator.honorRouteLink …)` after the `honorOverviewWay` sheet)

**Interfaces:**
- Consumes: `coordinator.honorRouteLink`, `coordinator.openOverview(for:)`, `coordinator.promotePendingHonorWay()` (Task 2).
- Produces: `PilgrimageRouteView(entry:release:onChoose:focusStage:)`, with `focusStage: Int?` defaulting to nil so `PilgrimageCatalogView`'s call is unchanged.

- [ ] **Step 1: Give the route screen a stage to focus**

In `PilgrimageRouteView`, after `let onChoose: (Way) -> Void`:

```swift
    /// From a stage link: the stage to bring into view, and the download
    /// question to ask about it. Nil from the catalog.
    var focusStage: Int?
```

With the other `@State` properties:

```swift
    /// The focus is applied once, so returning to the screen never asks the
    /// download question a second time.
    @State private var focusApplied = false
    @State private var scrollTarget: Int?
```

- [ ] **Step 2: Scroll and prompt**

Rename the current `var body: some View {` to `private var routeList: some View {` (its contents unchanged except the `.task` below), and add above it:

```swift
    var body: some View {
        ScrollViewReader { proxy in
            routeList
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation { proxy.scrollTo(target, anchor: .center) }
                }
        }
    }
```

Change the `.task` inside `routeList` to:

```swift
        .task {
            reload()
            await loadStagesIfNeeded()
            applyFocus()
        }
```

In `stageSection`, give each stage row an explicit scroll id:

```swift
            ForEach(stages, id: \.index) { stage in
                Button { open(stage) } label: { stageRow(stage) }
                    .id(stage.index)
            }
```

In `// MARK: - Actions`, after `open(index:)`:

```swift
    /// Asks the question tapping the stage row would ask: with the route not
    /// on the phone, whether to download it. An installed route whose
    /// stage is missing (an older release) asks nothing; its Update button
    /// is the answer.
    private func applyFocus() {
        guard let focusStage, !focusApplied else { return }
        focusApplied = true
        if stages.contains(where: { $0.index == focusStage }) { scrollTarget = focusStage }
        if !isInstalled { promptDownload = true }
    }
```

- [ ] **Step 3: Present the route sheet**

In `MainTabView`, directly after the `.sheet(item: $coordinator.honorOverviewWay, …) { … }` modifier:

```swift
        .sheet(item: $coordinator.honorRouteLink, onDismiss: coordinator.promotePendingHonorWay) { link in
            NavigationStack {
                PilgrimageRouteView(entry: link.entry, release: link.release,
                                    onChoose: { coordinator.openOverview(for: $0) }, focusStage: link.focus)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { coordinator.honorRouteLink = nil }
                                .font(Constants.Typography.button)
                                .foregroundColor(.stone)
                        }
                    }
            }
        }
```

- [ ] **Step 4: Build, and run the Honor tests**

Run the test command with `-only-testing:UnitTests/MainCoordinatorHonorTests -only-testing:UnitTests/StageLinkResolverTests -only-testing:UnitTests/HonorLinkTests`.
Expected: all pass, and the app target builds.

- [ ] **Step 5: See it on the simulator**

Boot the iPhone 17 Pro simulator, install and launch the Debug build, then:

```bash
xcrun simctl openurl booted "https://honor.pilgrimapp.org/camino-frances/14"
```

If the simulator opens Safari instead (associated domains not verified on this simulator), use the paste field: Path → Honor → paste `honor.pilgrimapp.org/camino-frances/14`. It runs the same coordinator path.

Check each, and write down what you saw:
1. Nothing downloaded: the route sheet opens on Camino Francés, scrolled so "14. Hornillos del Camino to Castrojeriz" is in view, and "Download this route first?" is raised. "Not now" leaves the sheet up; Close closes it.
2. Download it, then open the link again: the stage's overview opens directly with Begin, and no route sheet appears.
3. With Camino Francés downloaded, open `/camino-norte/3`: the route sheet for Norte, the prompt, and Download → the Replace confirmation.
4. `/camino-frances/99`: the route sheet unfocused, no prompt.
5. `/camino-imaginario/1`: toast "this route isn't in Pilgrim yet".
6. `/camino-frances/0` (via `simctl openurl`): toast "this link needs a newer Pilgrim".
7. Mid-walk (start a Wander walk first): toast "finish this walk first" on the walk screen; the tab doesn't change.
8. Cold launch: terminate the app, then `simctl openurl` the link from case 1. Same result as case 1.
9. With the Ways sheet open, paste the link: the Ways sheet closes, then the route sheet opens.

If case 1 shows the sheet but not the prompt (Xcode console: "Attempt to present … while a presentation is in progress"), the alert raced the sheet's presentation. In `applyFocus()` move the prompt behind the sheet's animation: make `applyFocus` `async` and put `try? await Task.sleep(for: .milliseconds(400))` before `if !isInstalled { promptDownload = true }`, keeping the `await` in `.task` (which cancels the sleep if the sheet closes). Re-check case 1.

- [ ] **Step 6: Commit**

```bash
git add Pilgrim/Scenes/Honor/PilgrimageRouteView.swift Pilgrim/Scenes/Root/MainTabView.swift
git commit -F - <<'EOF'
feat(honor): a stage link lands on its route, with the stage in view

The route screen opens in its own sheet from a link, scrolls to the
named stage, and asks the download question tapping that stage would
ask. Choosing a stage there closes the sheet and opens the overview,
exactly as it does from the catalog.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
EOF
```

---

### Task 5: The whole suite, lint, and the PR

**Files:** none new.

- [ ] **Step 1: Run every unit test**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath /tmp/pilgrim-stage-dd -only-testing:UnitTests 2>&1 | grep -E "error:|failed\)|Executed .* tests|\*\* TEST"
```

Expected: `** TEST SUCCEEDED **`. If a test fails, report it with its output; don't skip it.

- [ ] **Step 2: Lint the whole repo**

The pre-commit hook only lints staged files, and this branch adds lines to existing functions.

Run: `swiftlint lint --quiet`
Expected: no errors. Fix any warnings in files this branch touched.

- [ ] **Step 3: Push and open the PR (on the owner's go)**

```bash
git push -u origin feat/stage-links
gh pr create --title "Stage links: open a pilgrimage stage from a link" --body-file - <<'EOF'
`https://honor.pilgrimapp.org/<route>/<stage>` now opens Pilgrim on that stage: its overview with Begin if the route is downloaded, otherwise the route screen scrolled to the stage with "Download this route first?" raised (Replace still asks first). An honor-host link this build can't read now says "this link needs a newer Pilgrim" instead of opening the app to nothing.

- `HonorLink.parse` returns a destination (share, stage, unrecognised); `MainCoordinator.open(_:)` routes it.
- `StageLinkResolver` is pure; `openStage` gathers its inputs through injectable closures.
- The route sheet joins the AF60 park-and-promote handoffs.

Spec: `docs/superpowers/specs/2026-10-28-stage-links-design.md`. The worker's stage page and the open-pilgrimages numbering check are separate PRs in those repos. pilgrimag.es buttons wait until this build and the Android port are both live.

Manual checks: see Task 4 Step 5 of `docs/superpowers/plans/2026-10-28-stage-links-ios.md`. Real-iPhone universal links are the owner's check.

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
```
