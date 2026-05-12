# Archived walks — iOS support

**Release:** 1.6.0 (rolling additions to the constellation-mode-and-edit-link branch)
**Status:** Spec — pending review
**Date:** 2026-05-08
**Branch:** `feat/constellation-mode-and-edit-link`

## 1. Problem statement

The `pilgrim-viewer/edit` web app now lets users archive walks. When a
user clicks the X next to a walk in the editor and saves, the walk
moves out of `manifest.walks[]` and into `manifest.archived[]` with a
degraded `ArchivedWalk` schema:

```ts
interface ArchivedWalk {
  id: string                 // original walk UUID
  startDate: number          // epoch sec
  endDate: number            // epoch sec
  archivedAt: number         // epoch sec — when archived
  stats: {
    distance: number         // meters
    activeDuration: number   // seconds
    talkDuration: number     // seconds
    meditateDuration: number // seconds
    steps?: number
  }
}
```

GPS routes, photos, audio recordings, transcripts, intentions —
everything heavy is gone. Only surface stats remain.

The user's intent (per product owner): **cleanup + privacy**. The user
wants the heavy data actually deleted (filesize reduction + privacy
gesture). The walk record itself isn't deleted — the user wants the
*act of walking* preserved (counted, dated, with surface stats) while
the *trace* is released.

Currently iOS ignores `manifest.archived[]` on import and would not
emit `archived[]` on export. This spec covers iOS-side support.

`.pilgrim` is the authoritative source-of-truth across devices — any
device honoring the file format respects archive state and propagates
it on re-export.

## 2. Scope

### In

- **Importer** (`PilgrimPackageImporter.swift`): read `manifest.archived[]`.
  For each entry:
  - If a `Walk` exists in CoreStore by UUID, **strip its heavy data**
    (route points, photos, audio recordings, transcripts, intentions,
    notes, light readings — anything beyond the surface stats kept by
    the archived schema). Keep the bare `Walk` row with `startDate`,
    `endDate`, `distance`, `activeDuration`, `talkDuration`,
    `meditateDuration`, `steps`, `uuid`.
  - If no `Walk` exists by UUID, create a stub `Walk` with the
    archived stats and matching dates. This handles "pure shadow
    archive" — a walk that was never on this device but exists on
    another and got archived there.
  - In both cases, add the UUID to a new `UserPreferences.archivedWalkRegistry`
    sidecar (a `Set<String>` persisted via UserDefaults).
- **Exporter** (`PilgrimPackageBuilder.swift`): for each walk being
  exported, if its UUID is in `archivedWalkRegistry`, emit it to
  `manifest.archived[]` with the degraded schema. Otherwise emit to
  `manifest.walks[]` as today.
- **Sidecar pref** (`UserPreferences.swift`): new
  `archivedWalkRegistry: UserPreference.Required<[String: Double]>`
  mapping UUID string → archivedAt epoch seconds. Persists the
  archive timestamp the schema requires for round-trip-stable
  `archivedAt` on export.
- **Journey UI** (`InkScrollView` + `WalkDotView`): archived walks
  render as **hollow ring dots**, ~60% size of normal dots, in `.fog`
  stroke at 0.5 opacity. No animation. Tappable into the same
  expandCard.
- **expandCard** (in `InkScrollView`): when the expanded walk's UUID
  is in `archivedWalkRegistry`, render the **degraded variant** described
  in §4.5 — same frame structure but ghost-styled. The "View details
  →" button is replaced by a non-tappable `Released — full record
  removed` text.
- **Goshuin** (`GoshuinShareRenderer.swift` + `selectSeals`):
  archived walks are **excluded from seal selection** but **included
  in the total-stats line** (count, total distance).
- **Goshuin milestones** (`GoshuinMilestones.swift`): archived walks
  are **excluded from milestone detection** (they can't earn a
  milestone label since their full data is gone).

### Out (explicit non-goals)

- **No new CoreStore entity.** No `ArchivedWalk` entity. No new field
  on `Walk` (would require V8 migration on top of the recently shipped
  V7 — risk pile-on rejected).
- **No iOS-native "archive this walk" gesture.** Archive is a
  web-editor-only operation in 1.6.0. iOS only consumes the archive
  state from `.pilgrim` files. (Future spike — could become a
  first-class iOS gesture in a later release.)
- **No unarchive flow in iOS.** Once a walk is archived (locally or
  via re-import), the heavy data is gone. There's no way to recover
  it. If the user wants the walk back, they have to do it from a
  backup `.pilgrim` file that still has the full data — an explicit
  "import this older backup" action.
- **No celestial/weather data preserved on archived walks.** These
  are stripped along with the rest. The expandCard does not render
  celestial info or weather icons for archived walks. Celestial
  recomputation requires latitude (for hemisphere/horizon math) which
  is gone with the route — `startDate` alone is insufficient. Even if
  it weren't, rendering recomputed celestial on released data feels
  like fake-completion.
- **No partial-export archive entries.** If the user exports only a
  subset of walks, the `manifest.archived[]` array contains entries
  for archived walks that exist *anywhere* in this user's CoreStore.
  Re-importing such a partial file does NOT cause iOS to drop walks
  it already has; it only updates archive state. Detection: importer
  reconciles by UUID; missing-from-walks-and-not-in-archived is left
  alone.
- **No unarchive UI / flow.** A walk that's been archived stays
  archived for the lifetime of this app install (sans manual import
  of a backup that has the full record).

## 3. Acceptance criteria

### Importer

- [ ] When importing a `.pilgrim` file with `manifest.archived[]`
      entries, for each entry whose UUID matches an existing Walk:
      route points, photos, audio recordings, transcripts, intentions,
      notes, light readings are deleted from CoreStore (and any
      on-disk audio files in the recording cache are removed).
- [ ] Surface stats (`distance`, `activeDuration`, `talkDuration`,
      `meditateDuration`, `steps`) on existing Walks are NOT
      overwritten by the archived entry's stats — the iOS-stored
      values stay (they came from the original walk and are likely
      higher-fidelity than the archived snapshot).
- [ ] When importing an archived entry whose UUID is NOT in
      CoreStore, a stub Walk is created with: UUID, startDate,
      endDate, archived stats. No route, no photos, no recordings.
- [ ] In all cases, the UUID is added to
      `UserPreferences.archivedWalkRegistry`.

### Exporter

- [ ] On export, every Walk whose UUID is in `archivedWalkRegistry` is
      written to `manifest.archived[]` with the degraded schema —
      NOT to `manifest.walks[]`.
- [ ] Non-archived walks export to `manifest.walks[]` as today.

### Journey UI

- [ ] Walks whose UUID is in `archivedWalkRegistry` render in `InkScrollView`
      as hollow rings (no fill), `.fog` stroke 1pt, ~60% the size of
      normal dots, 0.5 opacity, no twinkle/pulse animation.
- [ ] Tapping an archived dot opens the expandCard same as a regular
      walk.
- [ ] The expandCard for an archived walk renders the degraded
      variant per §4.5.
- [ ] The "View details →" button is replaced by a non-tappable
      `Released — full record removed` text in `.fog`.

### Goshuin

- [ ] When the Goshuin seal grid is generated, archived walks are
      excluded from `selectSeals` (no seal pinned for them).
- [ ] The Goshuin stats line ("N walks · M km") includes archived
      walks in both count and total-distance computations. **Stub
      walks** (created from pure-shadow archive entries — walks
      that never happened on this device) ARE counted too —
      consistent treatment of archive state regardless of provenance.
- [ ] `GoshuinMilestones.detect(...)` returns an empty array for
      archived walks (no milestones earnable). This is the full-
      exclusion philosophy: if the trace is gone, the milestone
      can't be carved. (Alternative philosophy considered: count
      toward N-walks milestones but never earn distance/route-based
      ones. Rejected for simpler mental model.)

### Privacy

- [ ] After importing a `.pilgrim` file with an archived walk that
      previously existed in CoreStore with route data, audio
      recordings, and photos: the device's storage usage drops by the
      size of those artifacts. Verified via Xcode → Devices →
      installed-app size before and after.
- [ ] No deleted audio files remain in the app's recordings
      directory after archive import.

### Roundtrip

- [ ] `.pilgrim` archive → import to iOS → re-export to new `.pilgrim`:
      the same archived walk appears in `manifest.archived[]` of the
      new file (not silently moved back to `manifest.walks[]`).

## 4. Architecture

### 4.1 Sidecar storage

The sidecar persists **UUID → archivedAt timestamp** (NOT just a flat
ID set). The timestamp is required by the `ArchivedWalk` schema on
export — without it, re-exports would have to fabricate `now()` or
use import-time, breaking roundtrip determinism.

`UserDefaults` doesn't support `Dictionary` natively as a typed
preference, but `[String: Double]` (UUID string → epoch seconds) is
plist-safe and round-trips cleanly. Add to
`Pilgrim/Models/Preferences/UserPreferences.swift`:

```swift
// Map of UUID string → archivedAt (epoch seconds).
// Empty default. Order doesn't matter; existence does.
static let archivedWalkRegistry = UserPreference.Required<[String: Double]>(
    key: "archivedWalkRegistry",
    defaultValue: [:]
)
```

A small helper extension on `UserPreferences` provides the call-site
ergonomics. **All read-modify-write paths must go through a serial
queue** to avoid the race when two `.pilgrim` files are imported
concurrently (e.g. via the Files share-sheet flow):

```swift
extension UserPreferences {
    /// Serializes mutations on the registry. Imports are typically
    /// sequential, but the Files share extension can dispatch two
    /// imports overlapping. Reads are lock-free (UserDefaults is
    /// per-key atomic); only the read-modify-write needs the queue.
    private static let archivedRegistryQueue = DispatchQueue(
        label: "org.walktalkmeditate.pilgrim.archivedRegistry"
    )

    static func isArchivedWalk(uuid: UUID) -> Bool {
        archivedWalkRegistry.value[uuid.uuidString] != nil
    }

    static func archivedAt(uuid: UUID) -> Date? {
        guard let epoch = archivedWalkRegistry.value[uuid.uuidString] else {
            return nil
        }
        return Date(timeIntervalSince1970: epoch)
    }

    static func markWalkArchived(uuid: UUID, archivedAt: Date) {
        archivedRegistryQueue.sync {
            var registry = archivedWalkRegistry.value
            registry[uuid.uuidString] = archivedAt.timeIntervalSince1970
            archivedWalkRegistry.value = registry
        }
    }

    static func unmarkWalkArchived(uuid: UUID) {
        archivedRegistryQueue.sync {
            var registry = archivedWalkRegistry.value
            registry.removeValue(forKey: uuid.uuidString)
            archivedWalkRegistry.value = registry
        }
    }
}
```

**`UserPreference.Required<[String: Double]>` defaultValue check**
(per `feedback_userpreference_optional_default`): empty `[:]` is a
real value distinct from `nil`/unset. The user's recorded trap is
specifically about `Optional` prefs with defaults; `Required` with an
empty-collection default is the correct shape.

### 4.2 Schema (none)

**No CoreStore changes.** PilgrimV7 stays as-is. The archived state is
purely a sidecar set keyed by UUID.

### 4.3 Importer flow

`Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageImporter.swift`
gains a new step in its import pipeline:

1. Parse `manifest.archived[]` from the unzipped manifest JSON
   (gracefully default to `[]` if missing — preserves backwards
   compatibility with `.pilgrim` files written before the editor's
   archive feature).
2. **Inside the existing CoreStore import transaction**, for each
   `ArchivedWalkPayload`:
   - Look up `Walk` by UUID via `DataManager.dataStack.fetchOne(...)`.
   - If found, **strip heavy data on the Walk row**:
     - `routeData = nil`
     - `photos` relationship cleared (clearing the relationship from
       `Walk` side; this does not delete photos from the user's
       Photos library — those are user-owned, see §6)
     - `voiceRecordings` relationship cleared (CoreStore-side; the
       on-disk files are deleted in step 4 below, post-commit)
     - `transcript = ""` if non-nil
     - `intentionEntries` cleared
     - `notes = nil`
     - `lightReadings` cleared
     - **Surface stats are NOT overwritten with the archived
       payload's stats.** The iOS-stored values are higher-fidelity
       and stay as-is.
   - If not found, **create a stub Walk** in the same transaction
     with the field defaults enumerated in §4.3.5 below.
   - Capture the UUID and the payload's `archivedAt` epoch into a
     local `[String: Double]` map; do NOT mutate
     `UserPreferences.archivedWalkRegistry` yet.
   - **Capture the on-disk file paths** of the walk's
     `voiceRecordings` for post-commit deletion. Hold them in a local
     array of URLs.
3. **Backup-restore policy** (resolves §11.3): if a walk's UUID
   appears in BOTH `manifest.walks[]` (with full payload) AND in the
   local `archivedWalkRegistry`, the local archive flag wins. The
   walk's full payload from the file is **NOT applied** to a
   currently-archived local walk. This is the "archive is the user's
   privacy gesture; don't undo it from a stale backup file" model.
   Implement by checking `UserPreferences.isArchivedWalk(uuid:)`
   before applying any update from `manifest.walks[]` — skip if true,
   log to console.
4. **Commit the CoreStore transaction.** If the commit fails, the
   in-memory archivedAt map and file-path list are discarded; nothing
   is written to UserDefaults. The error propagates to the caller per
   `DataManager.deleteAll` rule (CLAUDE.md).
5. **Post-commit, on the import-coordinator's serial queue:**
   a. For each (UUID, archivedAt) in the captured map, call
      `UserPreferences.markWalkArchived(uuid:, archivedAt:)`. The
      helper itself is serialized; the call-site is inherently
      sequential here.
   b. For each captured file URL, attempt `FileManager.removeItem(at:)`.
      If a file delete fails, **log the error but do not throw** —
      the walk is correctly archived in CoreStore, the UserDefaults
      registry already reflects that, and a leftover audio file is a
      privacy issue but not a data-integrity issue. A sweep at next
      app launch (§4.3.6) cleans up any orphan files.

#### 4.3.5 Stub Walk required-field defaults

When creating a stub Walk for a pure-shadow archive entry (no
matching UUID in CoreStore), the following PilgrimV7.Walk required
fields must be defaulted explicitly (otherwise CoreStore throws on
`commit`):

| Field | Default for stub |
|---|---|
| `uuid` | from archived payload |
| `_workoutType` | `.walking` (rawValue 1; see CLAUDE.md note about rawValue mapping) |
| `_startDate` | from archived payload (epoch sec → Date) |
| `_endDate` | from archived payload |
| `_distance` | from archived payload's `stats.distance` |
| `_activeDuration` | from archived payload's `stats.activeDuration` |
| `_pauseDuration` | `0` |
| `_isUserModified` | `true` (the archive operation is a user-driven mod) |
| `_burnedEnergy` | `nil` |
| `_steps` | from archived payload's `stats.steps` (may be nil) |
| `_ascend` | `0` |
| `_descend` | `0` |
| `_dayCompleted` | `false` |
| `routeData` | `nil` |
| `pauses` relationship | empty |
| `events` relationship | empty |
| `heartRates` relationship | empty |
| `voiceRecordings` relationship | empty |
| `photos` relationship | empty |
| `intentionEntries` relationship | empty |
| `lightReadings` relationship | empty |
| `notes` | `nil` |
| `talkDuration` (if direct field) / via events relationship | derived to match payload |
| `meditateDuration` | derived to match payload |
| `healthKitUUID` | `nil` (per CLAUDE.md frozen field rule) |

For talk/meditate durations: if the schema stores these as derived
sums over `events` (rather than direct fields), inserting events
matching the payload's totals is acceptable but **the events have no
GPS/timestamp pairs** — they're flat duration markers only.
Implementation must verify which storage shape PilgrimV7 uses and
choose the matching path. Open item if unclear before code lands.

#### 4.3.6 Orphan-recording sweep

On every app launch, in `AppDelegate.application(_:didFinishLaunching...)`
or equivalent, run a quick sweep:

1. Read all walk UUIDs from CoreStore.
2. Read all `.m4a`/`.wav` files from the recordings directory.
3. For any file whose name's UUID prefix doesn't match a walk's
   `voiceRecordings` set, attempt to delete.

This catches files that survived a failed post-commit deletion in
§4.3.5b. Cheap (no file content inspection, just listing). Logs
deletions for diagnostic.

### 4.4 Exporter flow

`Pilgrim/Models/Data/PilgrimPackage/PilgrimPackageBuilder.swift` is
modified to:

1. Snapshot `archivedRegistry = UserPreferences.archivedWalkRegistry.value`
   once at the start of `buildPackage(...)` so the export sees a
   consistent state even if a concurrent import mutates the registry
   mid-build.
2. When building the `manifest.walks[]` and `manifest.archived[]`
   arrays:
   - For each walk being exported with UUID `uuid`:
     - If `archivedRegistry[uuid.uuidString]` is non-nil, emit a
       degraded `ArchivedWalkPayload` to `manifest.archived[]` with
       fields strictly limited to the schema:
       `{id, startDate, endDate, archivedAt, stats: {distance,
       activeDuration, talkDuration, meditateDuration, steps?}}`.
       Use the registry's stored `archivedAt` (NOT `Date()` — that
       would mutate the timestamp on every roundtrip).
     - Otherwise, append the full `PilgrimWalk` to `manifest.walks[]`
       as today.

### 4.5 expandCard degraded variant

The existing `expandCard` in `InkScrollView` is rewritten to branch on
archive state. A helper:

```swift
private var isExpandedArchived: Bool {
    guard let snapshot = expandedSnapshot else { return false }
    return UserPreferences.isArchivedWalk(uuid: snapshot.id)
}
```

Differences when `isExpandedArchived` is true:

| Element | Normal | Archived |
|---|---|---|
| Footprint shape | seasonal-color fill | hollow ring outline matching the dot, `.fog` stroke |
| Header date color | `.ink` | `.fog` |
| Favicon icon | rendered if set | omitted |
| Sharing link icon | rendered if set | omitted |
| Celestial info (moon sign) | rendered if available | **omitted** — no lat for celestial recomputation, and rendering it on released data feels false |
| Weather icon | rendered if set | omitted |
| Distance / Duration / Pace stats | full | **same** — all derivable from archived schema |
| `miniActivityBar` | rendered | **hidden** — needs per-second sample data |
| `activityPills` (Walk/Talk/Meditate) | rendered as segmented timeline | **rendered as flat presence pills** — for archived walks the pills only indicate "this walk had any talk / any meditate / any walking" (boolean per type, derived from the durations being > 0). No segment positions, no relative widths — the per-second sample data needed for that is gone. Visual: same colored dots ● + label, no segment bar |
| Footer button | "View details →" tappable, `.stone` bg, `.parchment` fg | **`Released — full record removed`** label in `.fog` caption, no tap target, centered |
| Card bg | `parchmentSecondary` (or its constellation-mode override) | same color but at `0.5` opacity |
| Card border | none / standard | dashed 1pt `.fog` outline at 0.4 opacity |
| Top-right corner | (none) | `Image(systemName: "circle.dotted") + Text("Released")` in `.fog` caption |

### 4.6 Dot styling in InkScrollView

`WalkDotView` (or its callsite in `InkScrollView.scrollContent`) gains
an `isArchived: Bool` parameter sourced from
`UserPreferences.isArchivedWalk(uuid: snapshot.id)`. When true:

- Draw a `Circle().stroke(Color.fog.opacity(0.5), lineWidth: 1)` of
  diameter `normalDiameter * 0.6`. NO fill.
- Skip any halo/glow/twinkle modifiers that normal dots receive.
- **Tap target stays a 44pt-diameter hit-testable area** (the same
  HIG-compliant area normal dots use). Wrap the visual in a
  `.frame(width: 44, height: 44).contentShape(Circle())` so the
  smaller visual doesn't shrink the touch zone below HIG minimum.
  Tap-to-expand works identically to normal dots.

### 4.7 Goshuin filter

`GoshuinShareRenderer.selectSeals(from: walks, ...)` filters its
input upfront:

```swift
let archivedRegistry = UserPreferences.archivedWalkRegistry.value
let candidates = walks.filter { walk in
    guard let uuid = walk.uuid?.uuidString else { return true }
    return archivedRegistry[uuid] == nil
}
// existing seal-selection logic over `candidates`
```

`computeStats(walks: walks)` keeps the unfiltered `walks` array for
the count and total-distance line.

`GoshuinMilestones.detect(...)` returns `[]` early when its `input`
walk's UUID is in the archived set.

## 5. Resource safety

- **Sidecar storage scaling:** `archivedWalkRegistry` is a flat array of
  UUID strings. At 36 chars per UUID, 1000 archived walks = 36 KB in
  UserDefaults — negligible. UserDefaults is loaded fully into memory
  by iOS at app launch; no incremental cost.
- **Importer transaction:** the heavy-data deletion happens inside
  the existing CoreStore import transaction. If the transaction
  fails mid-way, CoreStore rolls back — partial archive states won't
  be left on disk. **CLAUDE.md `DataManager.deleteAll` rule applies:
  errors must propagate so CoreStore rolls back. Do not silently
  swallow.**
- **Audio file deletion is OUT of the CoreStore transaction** (file
  I/O can't be rolled back by CoreStore). Order: commit the CoreStore
  delete first, then delete files on disk only after commit succeeds.
  If the file delete fails, the file lingers but the walk is correctly
  archived in CoreStore. Log the file error; don't fail the import.
- **No new timers, no new background subscriptions.** Sidecar reads/
  writes are synchronous via UserDefaults.

## 6. Privacy

The archive operation is the user's privacy gesture. The implementation
must honor that:

- Heavy data must be **actually deleted from disk**, not just hidden:
  - `Walk.routeData` set to nil, persisted via CoreStore transaction
  - **Photos**: PilgrimV7's `Photo` records carry a PHAsset
    `localIdentifier` referencing photos in the user's iOS Photos
    library, plus optional `embeddedPhotoFilename` pointing at a
    file inside the previously-exported `.pilgrim` archive. The
    archive operation:
    - clears the iOS-side `Photo` records (CoreStore relationship
      from `Walk` cleared) — removes the app's references to the
      user's library photos
    - does NOT delete photos from the user's Photos library —
      they're user-owned outside the app's scope; deleting on
      archive would be unauthorized scope expansion
    - does NOT need to clean up `embeddedPhotoFilename` artifacts
      because those live inside `.pilgrim` archive files, not in
      app sandbox storage. Confirm by inspecting the codebase that
      no other on-device path holds embedded photo bytes (if so,
      add to the deletion list).
  - Audio recording files in the app's recordings directory: deleted
    from disk in §4.3 step 5b. Orphan-sweep at next launch (§4.3.6)
    catches any post-commit failures.
  - Transcripts: stored as text on the Walk row, set to empty string
  - Intentions/notes/light readings: cleared (CoreStore-side)
- **The walk's existence is preserved** — the user wanted the act of
  walking remembered, just not the trace.
- **No telemetry** added for archive imports (project is
  privacy-first, no analytics).

## 7. UI summary

```
Normal walk on InkScrollView path:        Archived walk:
●  (filled, seasonal color, ~12pt)        ○  (hollow ring, .fog 0.5α, ~7pt)


Normal expandCard:                         Archived expandCard:
┌─────────────────────────────┐            ┌╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴┐
│ ▶ ☀  May 8, 2026   ☁ 59°F   │            ╎ ○  May 8, 2026  ⌒ Released ╎
│ ─────────────────────────── │            ╎ ─────────────────────────── ╎
│  3.2km    45min    8'30"    │            ╎  3.2km    45min    8'30"   ╎
│ ▰▰▰▱▱ activity bar ▱▱▱▰▰  │            ╎ (no activity bar)            ╎
│ ● Walk  ● Talk  ● Meditate  │            ╎ ● Walk  ● Talk  ● Meditate  ╎
│ [   View details →   ]      │            ╎ Released — full record removed ╎
└─────────────────────────────┘            └╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴╴┘
```

## 8. Testing

### Unit

- `PilgrimPackageImporterArchivedTests` (new file)
  - `testArchivedEntryWithLocalWalkStripsHeavyData` — fixture has a
    walk in CoreStore with route + photos + recordings. Import
    `.pilgrim` containing only `archived[]` entry for that UUID
    (NOT also in `walks[]` — the editor's actual output shape).
    Assertions: walk still exists, `routeData == nil`, `photos`
    relationship empty, `voiceRecordings` empty, recordings
    directory contains zero files for that UUID, registry has UUID
    with the payload's `archivedAt`. Surface stats unchanged from
    pre-import values.
  - `testAdversarialDuplicateInWalksAndArchived` — fixture has same
    UUID in BOTH `walks[]` (full payload) AND `archived[]` (degraded).
    The web editor never emits this, but a hand-edited file or
    out-of-order merge could. Assertions: archive flag wins; full
    payload from `walks[]` is NOT applied; heavy data from CoreStore
    is stripped per archive rules.
  - `testBackupRestoreSkipsAlreadyArchivedWalk` — local Walk with
    UUID U is currently archived (in registry). Import `.pilgrim`
    containing the same UUID U in `walks[]` with full route +
    photos. Assertions: local walk's route stays nil, photos stay
    empty (the backup file did NOT restore them), UUID stays in
    registry.
  - `testArchivedEntryCreatesStubWalkWhenNoMatch` — fixture has
    `archived[]` entry, no matching walk in CoreStore. After import,
    a stub Walk exists with the spec'd defaults from §4.3.5,
    registry has the UUID + archivedAt.
  - `testSurfaceStatsNotOverwritten` — local walk has
    distance=3200m. Import archived entry with the same UUID and
    distance=3000m in payload. Assertions: post-import,
    `walk.distance == 3200` (NOT 3000).
  - `testArchivedExportEmitsToManifestArchivedArray` — Walk in
    CoreStore, UUID in registry with archivedAt=T. Export to
    `.pilgrim`, parse manifest: walk appears in `archived[]` with
    `archivedAt == T` (NOT Date.now), walk does NOT appear in
    `walks[]`.
  - `testNonArchivedWalkExportEmitsToManifestWalksArray` — control.
  - `testRoundtripPreservesArchivedAtAndExcludesHeavyData` — import
    file → re-export → reparse manifest → assert: archivedAt
    timestamp stable across roundtrip; the re-exported `archived[]`
    entry's keys are a subset of `{id, startDate, endDate,
    archivedAt, stats}` — no leaked heavy-data keys.
- `UserPreferencesArchivedTests` (new file)
  - `testIsArchivedWalkReturnsTrueAfterMark`
  - `testArchivedAtRoundtripsThroughRegistry` — mark with date D,
    read back via `archivedAt(uuid:)`, assert epoch matches within
    1ms.
  - `testUnmarkRemovesFromRegistry`
  - `testMarkIsIdempotent` — calling mark twice updates timestamp,
    doesn't duplicate.
  - `testConcurrentMarkCallsRaceFree` — fire 10 concurrent
    `markWalkArchived` from `DispatchQueue.concurrentPerform`,
    assert post-state has all 10 UUIDs (not lost-update).
- `ArchivedWalkPrivacyTests` (new file)
  - `testHeavyDataDeletionAfterImport` — programmatic AC for §3
    privacy criteria. Pre-import: count files in recordings dir,
    snapshot `Walk.routeData != nil ? routeData!.count : 0`. Import
    archive entry. Post-import assert: file count for that walk's
    UUID is 0, `walk.routeData == nil`.

### Manual visual QA (gates ship)

1. iPhone 17 Pro sim. Seed walks via debug menu. Pick one, use
   pilgrim-viewer to archive it, save the file. Re-import to iOS.
   Confirm:
   - Dot in InkScrollView changes to hollow ring
   - Tap → expandCard renders degraded variant correctly
   - "Released — full record removed" footer is visible, not tappable
   - Goshuin sheet shows the walk in count + distance but no seal
     pinned for it
2. Privacy: same flow, but check via `du -sh` on the simulator's
   recordings directory before and after — should drop by the audio
   file size.
3. Visual regression: confirm normal walks still render normally
   (no accidental ghost styling on regular dots).

## 9. Localization

`en` only for new strings:

- `walk.archive.released` — "Released"
- `walk.archive.full_record_removed` — "Released — full record removed"

Hardcoded literals consistent with the rest of the codebase (per the
previous spec's i18n decision).

## 10. Risks accepted

| Risk | Decision |
|---|---|
| User archives walk on web, never re-exports the file → iOS never knows | Accept; that's the user's choice. iOS only knows what it's told via `.pilgrim` import. |
| Two devices' UserDefaults can disagree about archived state until both import the same `.pilgrim` | Accept; `.pilgrim` is the authoritative source-of-truth. State converges via shared file. |
| User imports an archived walk's file, then later imports a backup `.pilgrim` with the full data of the same walk | Open question — see §11.3 |
| Stub walks (created from pure shadow archive entries) have very minimal data and may surprise users who expect to see route etc. | Accept; the expandCard's degraded variant explains it. |
| Goshuin total-distance line includes archived walks; user might wonder why their seal grid has fewer seals than implied | Accept; the stats line is explicit ("17 walks · 23 km"), the seal grid is selective by design. |

## 11. Open items requiring confirmation before merge

1. Confirm `pilgrim-viewer/edit` actually emits the expected
   `manifest.archived[]` shape — sample file via the editor UI and
   inspect before writing the importer.
2. Confirm the project's `UserPreference.Required<[String]>` type
   parameter actually serializes to UserDefaults correctly (it should
   — UserDefaults supports `[String]` natively — but verify with a
   round-trip unit test).
3. **Resolved in §4.3 step 3 — option (b) "archive flag wins."** A
   future spike could add option (c) (prompt the user) if user
   feedback indicates the silent-skip is confusing.
4. Confirm seal/milestone exclusion is the right philosophical call
   (vs. "archived walks count toward 100-walk milestone but no seal
   pinned"). The spec assumes exclusion is full — no milestone
   counting either. Owner confirm.
5. Confirm the constellation-mode parchmentSecondary fallback for
   archived expandCard backgrounds reads correctly. (May need a
   tweak when the indigo bg sits behind a translucent card.)

## 12. Release plan

- Branch: continue on `feat/constellation-mode-and-edit-link` (1.6.0
  is rolling on this branch)
- Implementation phased:
  1. Sidecar pref + helpers
  2. Importer changes + tests
  3. Exporter changes + tests
  4. InkScrollView dot styling + isArchived param plumbing
  5. expandCard degraded variant
  6. Goshuin selectSeals + milestones filter
  7. **`xcodebuild test -only-testing:UnitTests` full pass** — gate
     before manual QA. All new + existing tests must pass.
  8. Manual visual QA matrix
  9. Build green + visual QA green → ready for TestFlight (per user
     instruction, hold TF until explicit approval)
- TestFlight only after the user explicitly says ready (per
  `feedback_testflight_approval.md` and the earlier instruction to
  hold TF until everything is done).
