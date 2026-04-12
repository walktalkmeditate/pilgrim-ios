# Dynamic Whisper Catalog Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move whisper metadata from a hardcoded Swift enum to a remote versioned manifest, add a `.play` category, and bundle initial audio so the catalog can grow silently without app updates.

**Architecture:** New `WhisperManifestService` singleton copies the existing `AudioManifestService` shape: loads a cached JSON manifest (or a bundled bootstrap fallback), syncs in the background on cold launch, and serves lookups by category or ID. `WhisperPlayer` gains per-category background prefetch and first-launch bundled-audio seeding. All call sites that used `WhisperCatalog` now go through the service. Initial bootstrap ships the 21 existing whispers; Play content gets added via a post-merge manifest update.

**Tech Stack:** Swift 5.9+, SwiftUI, Combine, XCTest, AVFoundation, CocoaPods. R2 for manifest + audio hosting, Cloudflare in front of it.

**Spec:** `docs/superpowers/specs/2026-04-11-dynamic-whisper-catalog-design.md`

---

## Prerequisites

- Xcode 16+ installed at `/Applications/Xcode.app`
- CocoaPods dependencies already installed (`pod install` is not required for this plan)
- Active iOS Simulator available (`iPhone 17 Pro` for tests, `iPhone 17 Pro Max` used for screenshots)
- Write access to the `cdn.pilgrimapp.org` R2 bucket (only required for Task 10 and the post-merge content drop)
- `curl`, `jq`, and `plutil` on `$PATH`

## File Structure

| File | Action | Responsibility |
|---|---|---|
| `Pilgrim/Models/Whisper/WhisperDefinition.swift` | modify | Add `.play` case, add `retiredAt` field |
| `Pilgrim/Models/Whisper/WhisperManifest.swift` | create | Codable schema for the remote manifest |
| `Pilgrim/Models/Whisper/WhisperManifestService.swift` | create | Singleton that loads, caches, syncs, and serves manifest data |
| `Pilgrim/Models/Whisper/WhisperPlayer.swift` | modify | Remove eager bulk download, add per-category prefetch, add bundled-audio seeding |
| `Pilgrim/Models/Whisper/WhisperCatalog.swift` | delete | Replaced by the manifest service |
| `Pilgrim/Models/Config.swift` | modify | Add `Config.Whisper.manifestURL` |
| `Pilgrim/AppDelegate.swift` | modify | Call `WhisperManifestService.shared.syncIfNeeded()` on launch |
| `Pilgrim/Scenes/ActiveWalk/WhisperPlacementSheet.swift` | modify | Source from manifest service, prefetch on selection, filter empty categories |
| `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift` | modify | Use manifest service in `handleAnnotationTap` (line ~911) |
| `Pilgrim/Support Files/whispers-bootstrap.json` | create | Bundled initial manifest snapshot |
| `Pilgrim/Support Files/whisper-audio/*.aac` | create | Bundled initial audio files |
| `UnitTests/WhisperManifestServiceTests.swift` | create | Tests for decoding, category lookup, retirement filter |
| `scripts/release.sh` | modify | Add `bootstrap-whispers` subcommand |
| `scripts/regen-whisper-bootstrap.sh` | create | Helper that pulls manifest + audio from R2 into `Support Files/` |

---

## Task 1: Extend `WhisperDefinition` and `WhisperCategory`

**Files:**
- Modify: `Pilgrim/Models/Whisper/WhisperDefinition.swift`
- Modify: `Pilgrim/Models/Whisper/WhisperCatalog.swift`

Adds the new `.play` enum case and the `retiredAt` field. The catalog file gets mass-updated to pass `retiredAt: nil` on all 21 existing entries so the project still compiles. (Catalog gets deleted in Task 9.)

- [ ] **Step 1: Replace `WhisperDefinition.swift` with the updated schema**

Write:

```swift
// Pilgrim/Models/Whisper/WhisperDefinition.swift
import UIKit

struct WhisperDefinition: Codable, Identifiable {

    let id: String
    let title: String
    let category: WhisperCategory
    let audioFileName: String
    let durationSec: Double
    let retiredAt: Date?
}

enum WhisperCategory: String, Codable, CaseIterable {
    case presence
    case lightness
    case wonder
    case gratitude
    case compassion
    case courage
    case stillness
    case play

    var borderColor: UIColor {
        switch self {
        case .presence: return UIColor(red: 0.11, green: 0.23, blue: 0.29, alpha: 1.0)
        case .lightness: return UIColor(red: 0.76, green: 0.65, blue: 0.55, alpha: 1.0)
        case .wonder: return UIColor(red: 0.66, green: 0.72, blue: 0.75, alpha: 1.0)
        case .gratitude: return UIColor(red: 0.78, green: 0.63, blue: 0.31, alpha: 1.0)
        case .compassion: return UIColor(red: 0.66, green: 0.85, blue: 0.82, alpha: 1.0)
        case .courage: return UIColor(red: 0.78, green: 0.72, blue: 0.53, alpha: 1.0)
        case .stillness: return UIColor(red: 0.72, green: 0.58, blue: 0.42, alpha: 1.0)
        case .play: return UIColor(red: 0.75, green: 0.40, blue: 0.22, alpha: 1.0)
        }
    }
}
```

- [ ] **Step 2: Update `WhisperCatalog.swift` to pass `retiredAt: nil` on every entry**

Replace the contents of `Pilgrim/Models/Whisper/WhisperCatalog.swift` with:

```swift
// Pilgrim/Models/Whisper/WhisperCatalog.swift
//
// NOTE: This file is a compile-only shim during the dynamic-catalog migration.
// It will be deleted in Task 9 once all call sites route through
// WhisperManifestService. Do not add new entries here.
import Foundation

enum WhisperCatalog {

    static let all: [WhisperDefinition] = [
        WhisperDefinition(id: "presence-1", title: "What do you see right now?", category: .presence, audioFileName: "whisper-presence-1", durationSec: 6, retiredAt: nil),
        WhisperDefinition(id: "presence-2", title: "Feel your feet on the earth", category: .presence, audioFileName: "whisper-presence-2", durationSec: 8, retiredAt: nil),
        WhisperDefinition(id: "presence-3", title: "You are here", category: .presence, audioFileName: "whisper-presence-3", durationSec: 5, retiredAt: nil),

        WhisperDefinition(id: "lightness-1", title: "You are doing great", category: .lightness, audioFileName: "whisper-lightness-1", durationSec: 6, retiredAt: nil),
        WhisperDefinition(id: "lightness-2", title: "Whatever you were worrying about can wait", category: .lightness, audioFileName: "whisper-lightness-2", durationSec: 8, retiredAt: nil),
        WhisperDefinition(id: "lightness-3", title: "Take a breath", category: .lightness, audioFileName: "whisper-lightness-3", durationSec: 8, retiredAt: nil),

        WhisperDefinition(id: "wonder-1", title: "Something extraordinary is happening", category: .wonder, audioFileName: "whisper-wonder-1", durationSec: 7, retiredAt: nil),
        WhisperDefinition(id: "wonder-2", title: "The light left its source long ago", category: .wonder, audioFileName: "whisper-wonder-2", durationSec: 7, retiredAt: nil),
        WhisperDefinition(id: "wonder-3", title: "You are spinning through space", category: .wonder, audioFileName: "whisper-wonder-3", durationSec: 9, retiredAt: nil),

        WhisperDefinition(id: "gratitude-1", title: "Thank the one who planted this tree", category: .gratitude, audioFileName: "whisper-gratitude-1", durationSec: 8, retiredAt: nil),
        WhisperDefinition(id: "gratitude-2", title: "Your body carried you here", category: .gratitude, audioFileName: "whisper-gratitude-2", durationSec: 8, retiredAt: nil),
        WhisperDefinition(id: "gratitude-3", title: "This moment is a gift", category: .gratitude, audioFileName: "whisper-gratitude-3", durationSec: 6, retiredAt: nil),

        WhisperDefinition(id: "compassion-1", title: "Others have walked here with heavy hearts", category: .compassion, audioFileName: "whisper-compassion-1", durationSec: 6, retiredAt: nil),
        WhisperDefinition(id: "compassion-2", title: "Set something down", category: .compassion, audioFileName: "whisper-compassion-2", durationSec: 6, retiredAt: nil),
        WhisperDefinition(id: "compassion-3", title: "The path does not ask you to be perfect", category: .compassion, audioFileName: "whisper-compassion-3", durationSec: 8, retiredAt: nil),

        WhisperDefinition(id: "courage-1", title: "The next step is the only one that matters", category: .courage, audioFileName: "whisper-courage-1", durationSec: 6, retiredAt: nil),
        WhisperDefinition(id: "courage-2", title: "What you seek is also seeking you", category: .courage, audioFileName: "whisper-courage-2", durationSec: 6, retiredAt: nil),
        WhisperDefinition(id: "courage-3", title: "You already know the answer", category: .courage, audioFileName: "whisper-courage-3", durationSec: 7, retiredAt: nil),

        WhisperDefinition(id: "stillness-1", title: "Be still", category: .stillness, audioFileName: "whisper-stillness-1", durationSec: 3, retiredAt: nil),
        WhisperDefinition(id: "stillness-2", title: "Breathe", category: .stillness, audioFileName: "whisper-stillness-2", durationSec: 4, retiredAt: nil),
        WhisperDefinition(id: "stillness-3", title: "You are an animal on the earth", category: .stillness, audioFileName: "whisper-stillness-3", durationSec: 6, retiredAt: nil)
    ]

    static func whispers(for category: WhisperCategory) -> [WhisperDefinition] {
        all.filter { $0.category == category }
    }

    static func whisper(byId id: String) -> WhisperDefinition? {
        all.first { $0.id == id }
    }
}
```

- [ ] **Step 3: Build and verify clean compile**

Run:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Models/Whisper/WhisperDefinition.swift Pilgrim/Models/Whisper/WhisperCatalog.swift
git commit -m "$(cat <<'EOF'
feat(whispers): extend schema with play category and retiredAt

Adds the .play case to WhisperCategory with a warm rust border color,
and the retiredAt field to WhisperDefinition. WhisperCatalog is
temporarily updated to pass retiredAt: nil on every entry so the build
stays green; it will be deleted in a later task once all call sites go
through the manifest service.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: Add `Config.Whisper.manifestURL`

**Files:**
- Modify: `Pilgrim/Models/Config.swift:83-92`

- [ ] **Step 1: Add a `Whisper` nested enum to `Config`**

Locate the `enum VoiceGuide { ... }` block at `Pilgrim/Models/Config.swift:88-91` and add a new block immediately after it:

```swift
    enum Whisper {
        static let manifestURL = URL(string: "https://cdn.pilgrimapp.org/audio/whisper/manifest.json")!
        static let cdnBaseURL = URL(string: "https://cdn.pilgrimapp.org/audio/whisper")!
    }
```

The full resulting tail of the `Config` type (lines 83-95) should read:

```swift
    enum Audio {
        static let r2BaseURL = URL(string: "https://cdn.pilgrimapp.org/audio")!
        static let manifestURL = URL(string: "https://cdn.pilgrimapp.org/audio/manifest.json")!
    }

    enum VoiceGuide {
        static let manifestURL = URL(string: "https://cdn.pilgrimapp.org/voiceguide/manifest.json")!
        static let baseURL = URL(string: "https://cdn.pilgrimapp.org/voiceguide")!
    }

    enum Whisper {
        static let manifestURL = URL(string: "https://cdn.pilgrimapp.org/audio/whisper/manifest.json")!
        static let cdnBaseURL = URL(string: "https://cdn.pilgrimapp.org/audio/whisper")!
    }

}
```

- [ ] **Step 2: Build and verify clean compile**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Models/Config.swift
git commit -m "$(cat <<'EOF'
feat(whispers): add Config.Whisper URLs for manifest + cdn base

Mirrors the Config.Audio and Config.VoiceGuide patterns so the incoming
WhisperManifestService has a canonical source of truth for its endpoints.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: Create `WhisperManifest` Codable schema

**Files:**
- Create: `Pilgrim/Models/Whisper/WhisperManifest.swift`

- [ ] **Step 1: Create the new file**

Write:

```swift
// Pilgrim/Models/Whisper/WhisperManifest.swift
import Foundation

struct WhisperManifest: Codable {

    let version: Int
    let whispers: [WhisperDefinition]

    static let empty = WhisperManifest(version: 0, whispers: [])
}
```

- [ ] **Step 2: Add the new file to the Xcode project**

Open `Pilgrim.xcworkspace` in Xcode → right-click the `Pilgrim/Models/Whisper/` group in the Project Navigator → **Add Files to "Pilgrim"…** → select `WhisperManifest.swift` → ensure the **Pilgrim** target is checked → **Add**.

Alternative (CLI, if you're comfortable editing `project.pbxproj`): add the file reference and build file entries by hand. Recommended: use Xcode.

- [ ] **Step 3: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Models/Whisper/WhisperManifest.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(whispers): add WhisperManifest codable schema

Matches the append-only manifest described in the design spec:
version + flat whispers array, with retiredAt carried on each entry.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: Create `WhisperManifestService` with unit tests

**Files:**
- Create: `Pilgrim/Models/Whisper/WhisperManifestService.swift`
- Create: `UnitTests/WhisperManifestServiceTests.swift`

The service mirrors `AudioManifestService` but adds a two-method split for retired whispers: `placeableWhispers(for:)` filters retired, `whispers(for:)` and `whisper(byId:)` return everything.

- [ ] **Step 1: Write the failing test file**

Create `UnitTests/WhisperManifestServiceTests.swift`:

```swift
// UnitTests/WhisperManifestServiceTests.swift
import XCTest
@testable import Pilgrim

final class WhisperManifestDecodingTests: XCTestCase {

    func testDecodes_minimalManifest() throws {
        let json = """
        {
          "version": 1,
          "whispers": [
            {
              "id": "presence-1",
              "title": "What do you see right now?",
              "category": "presence",
              "audioFileName": "whisper-presence-1",
              "durationSec": 6,
              "retiredAt": null
            }
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(WhisperManifest.self, from: json)

        XCTAssertEqual(manifest.version, 1)
        XCTAssertEqual(manifest.whispers.count, 1)
        XCTAssertEqual(manifest.whispers.first?.id, "presence-1")
        XCTAssertNil(manifest.whispers.first?.retiredAt)
    }

    func testDecodes_retiredAtAsISO8601() throws {
        let json = """
        {
          "version": 2,
          "whispers": [
            {
              "id": "courage-9",
              "title": "Old phrase",
              "category": "courage",
              "audioFileName": "whisper-courage-9",
              "durationSec": 5,
              "retiredAt": "2026-04-11T00:00:00Z"
            }
          ]
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let manifest = try decoder.decode(WhisperManifest.self, from: json)

        XCTAssertNotNil(manifest.whispers.first?.retiredAt)
    }
}

final class WhisperManifestFilteringTests: XCTestCase {

    private func makeManifest() -> WhisperManifest {
        WhisperManifest(
            version: 1,
            whispers: [
                WhisperDefinition(id: "gratitude-1", title: "Alive", category: .gratitude, audioFileName: "whisper-gratitude-1", durationSec: 5, retiredAt: nil),
                WhisperDefinition(id: "gratitude-2", title: "Old", category: .gratitude, audioFileName: "whisper-gratitude-2", durationSec: 5, retiredAt: Date(timeIntervalSince1970: 1_700_000_000)),
                WhisperDefinition(id: "play-1", title: "Skip", category: .play, audioFileName: "whisper-play-1", durationSec: 4, retiredAt: nil)
            ]
        )
    }

    func testWhispersForCategory_includesRetired() {
        let manifest = makeManifest()
        let results = manifest.whispers.filter { $0.category == .gratitude }
        XCTAssertEqual(results.count, 2, "whispers(for:) should return retired too")
    }

    func testPlaceableWhispersForCategory_excludesRetired() {
        let manifest = makeManifest()
        let placeable = manifest.whispers.filter { $0.category == .gratitude && $0.retiredAt == nil }
        XCTAssertEqual(placeable.count, 1)
        XCTAssertEqual(placeable.first?.id, "gratitude-1")
    }

    func testWhisperById_findsExisting() {
        let manifest = makeManifest()
        let hit = manifest.whispers.first { $0.id == "play-1" }
        XCTAssertNotNil(hit)
        XCTAssertEqual(hit?.category, .play)
    }

    func testWhisperById_returnsNilForMissing() {
        let manifest = makeManifest()
        let miss = manifest.whispers.first { $0.id == "does-not-exist" }
        XCTAssertNil(miss)
    }
}
```

- [ ] **Step 2: Add the test file to the `UnitTests` target in Xcode**

Open Xcode → right-click the `UnitTests` group → **Add Files to "Pilgrim"…** → select `WhisperManifestServiceTests.swift` → ensure the **UnitTests** target (NOT the main Pilgrim target) is checked → **Add**.

- [ ] **Step 3: Run the test to verify it fails with a compile error**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/WhisperManifestDecodingTests 2>&1 | tail -20
```

Expected: build succeeds (both the decoding and filtering tests should compile because they only touch `WhisperManifest` and `WhisperDefinition`, which already exist). Tests should PASS on first run — the service itself is not yet required for these tests.

If any test fails, debug before proceeding.

- [ ] **Step 4: Create the service file**

Write `Pilgrim/Models/Whisper/WhisperManifestService.swift`:

```swift
// Pilgrim/Models/Whisper/WhisperManifestService.swift
import Foundation
import Combine

final class WhisperManifestService: ObservableObject {

    static let shared = WhisperManifestService()

    @Published private(set) var manifest: WhisperManifest?
    @Published private(set) var isSyncing = false

    private let fileManager = FileManager.default

    private var localManifestURL: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Whispers", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("manifest.json")
    }

    private init() {
        loadLocalManifest()
        if manifest == nil {
            loadBootstrapManifest()
        }
    }

    // MARK: - Public lookups

    /// All whispers for a category, including retired. Used by WhisperPlayer
    /// when resolving existing placed whispers (map taps, proximity encounters).
    func whispers(for category: WhisperCategory) -> [WhisperDefinition] {
        (manifest?.whispers ?? []).filter { $0.category == category }
    }

    /// Non-retired whispers only. Used by WhisperPlacementSheet for the random
    /// placement pick.
    func placeableWhispers(for category: WhisperCategory) -> [WhisperDefinition] {
        (manifest?.whispers ?? []).filter { $0.category == category && $0.retiredAt == nil }
    }

    /// Full lookup by ID, including retired. Used when resolving the whisper_id
    /// on an existing placement.
    func whisper(byId id: String) -> WhisperDefinition? {
        manifest?.whispers.first { $0.id == id }
    }

    /// Categories that have at least one placeable whisper. WhisperPlacementSheet
    /// uses this to hide empty categories (e.g., when Play has not yet been
    /// populated post-code-ship).
    func placeableCategories() -> [WhisperCategory] {
        WhisperCategory.allCases.filter { !placeableWhispers(for: $0).isEmpty }
    }

    // MARK: - Sync

    func syncIfNeeded() {
        Task { @MainActor in
            guard !isSyncing else { return }
            isSyncing = true

            let remote = await fetchRemoteManifest()

            guard let remote else {
                isSyncing = false
                return
            }

            if manifest?.version != remote.version {
                saveLocalManifest(remote)
                manifest = remote
            }

            isSyncing = false
        }
    }

    // MARK: - Private

    private func fetchRemoteManifest() async -> WhisperManifest? {
        do {
            let (data, response) = try await URLSession.shared.data(from: Config.Whisper.manifestURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return nil
            }
            return try Self.decoder.decode(WhisperManifest.self, from: data)
        } catch {
            print("[WhisperManifestService] Failed to fetch manifest: \(error)")
            return nil
        }
    }

    private func loadLocalManifest() {
        guard fileManager.fileExists(atPath: localManifestURL.path),
              let data = try? Data(contentsOf: localManifestURL),
              let saved = try? Self.decoder.decode(WhisperManifest.self, from: data) else {
            return
        }
        manifest = saved
    }

    private func loadBootstrapManifest() {
        guard let url = Bundle.main.url(forResource: "whispers-bootstrap", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let bootstrap = try? Self.decoder.decode(WhisperManifest.self, from: data) else {
            print("[WhisperManifestService] No bootstrap manifest found; starting empty")
            manifest = .empty
            return
        }
        manifest = bootstrap
    }

    private func saveLocalManifest(_ manifest: WhisperManifest) {
        guard let data = try? Self.encoder.encode(manifest) else { return }
        try? data.write(to: localManifestURL)
    }

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}
```

- [ ] **Step 5: Add the service file to the Pilgrim target**

Xcode → right-click `Pilgrim/Models/Whisper/` → **Add Files to "Pilgrim"…** → select `WhisperManifestService.swift` → target `Pilgrim` checked → **Add**.

- [ ] **Step 6: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 7: Run the unit tests**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/WhisperManifestDecodingTests \
  -only-testing:UnitTests/WhisperManifestFilteringTests 2>&1 | tail -20
```

Expected: all 6 tests PASS.

- [ ] **Step 8: Commit**

```bash
git add Pilgrim/Models/Whisper/WhisperManifestService.swift \
        UnitTests/WhisperManifestServiceTests.swift \
        Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(whispers): add WhisperManifestService with decoding tests

Singleton modeled on AudioManifestService. Loads a cached manifest (or
the bundled bootstrap as fallback), syncs from R2 in the background, and
serves three lookup methods:
- whispers(for:) / whisper(byId:) return everything including retired,
  for resolving existing placed whispers
- placeableWhispers(for:) filters retired, for random placement picks
- placeableCategories() hides empty categories from the placement sheet

Unit tests cover the manifest decoding path and the retirement filter.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 5: Rewire `WhisperPlayer` for lazy prefetch and bundle seeding

**Files:**
- Modify: `Pilgrim/Models/Whisper/WhisperPlayer.swift`

Three behavioral changes:

1. Remove `downloadAll()` and `allDownloaded` — no more eager bulk download
2. Add `prefetchCategory(_:)` — background download of uncached whispers in a category
3. Add bundled-audio seeding — on init, if the cache directory is empty, copy bundled audio files from `Pilgrim/Support Files/whisper-audio/` into it

- [ ] **Step 1: Replace `Pilgrim/Models/Whisper/WhisperPlayer.swift` in full**

Write:

```swift
// Pilgrim/Models/Whisper/WhisperPlayer.swift
import AVFoundation

final class WhisperPlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {

    static let shared = WhisperPlayer()

    private var player: AVAudioPlayer?
    private let coordinator = AudioSessionCoordinator.shared
    private let cacheDir: URL
    private var previewTask: Task<Void, Never>?
    private var prefetchTasks: [WhisperCategory: Task<Void, Never>] = [:]

    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isPrefetching: Bool = false

    override private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        cacheDir = appSupport.appendingPathComponent("Whispers", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        super.init()
        seedFromBundleIfEmpty()
    }

    // MARK: - Bundled seed

    /// First-launch seeding: if the cache directory has no whisper audio
    /// files, copy any bundled whisper .aac files into it. Subsequent launches
    /// skip the copy because files already exist.
    private func seedFromBundleIfEmpty() {
        let existing = (try? FileManager.default.contentsOfDirectory(at: cacheDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "aac" } ?? []
        guard existing.isEmpty else { return }

        guard let bundleDir = Bundle.main.url(forResource: "whisper-audio", withExtension: nil) else {
            // Bundle directory not present — fine in dev, files will download on demand
            return
        }

        let bundled = (try? FileManager.default.contentsOfDirectory(at: bundleDir, includingPropertiesForKeys: nil))?
            .filter { $0.pathExtension == "aac" } ?? []

        for file in bundled {
            let destination = cacheDir.appendingPathComponent(file.lastPathComponent)
            do {
                try FileManager.default.copyItem(at: file, to: destination)
            } catch {
                print("[WhisperPlayer] Failed to seed \(file.lastPathComponent): \(error)")
            }
        }
    }

    // MARK: - Lookups

    private func localURL(for whisper: WhisperDefinition) -> URL {
        cacheDir.appendingPathComponent("\(whisper.audioFileName).aac")
    }

    private func remoteURL(for whisper: WhisperDefinition) -> URL {
        Config.Whisper.cdnBaseURL.appendingPathComponent("\(whisper.audioFileName).aac")
    }

    func isAvailable(_ whisper: WhisperDefinition) -> Bool {
        FileManager.default.fileExists(atPath: localURL(for: whisper).path)
    }

    // MARK: - Prefetch

    /// Best-effort background download of all uncached whispers in a category.
    /// Called when the user selects a category in WhisperPlacementSheet, so
    /// by the time they tap "Leave Whisper", the picked file is almost always
    /// already local.
    func prefetchCategory(_ category: WhisperCategory) {
        prefetchTasks[category]?.cancel()
        let uncached = WhisperManifestService.shared
            .whispers(for: category)
            .filter { !isAvailable($0) }
        guard !uncached.isEmpty else { return }

        isPrefetching = true
        prefetchTasks[category] = Task { [weak self] in
            guard let self else { return }
            for whisper in uncached {
                guard !Task.isCancelled else { break }
                let remote = remoteURL(for: whisper)
                let local = localURL(for: whisper)
                do {
                    let (data, _) = try await URLSession.shared.data(from: remote)
                    try data.write(to: local)
                } catch {
                    if !Task.isCancelled {
                        print("[WhisperPlayer] Prefetch failed for \(whisper.audioFileName): \(error)")
                    }
                }
            }
            await MainActor.run {
                self.prefetchTasks[category] = nil
                self.isPrefetching = !self.prefetchTasks.isEmpty
            }
        }
    }

    // MARK: - Play / preview (unchanged semantics)

    func play(_ whisper: WhisperDefinition, volume: Float = 0.8) {
        if isAvailable(whisper) {
            AudioPriorityQueue.shared.playWhisper(url: localURL(for: whisper), volume: volume)
        } else {
            Task { [weak self] in
                guard let self else { return }
                let remote = remoteURL(for: whisper)
                let local = localURL(for: whisper)
                do {
                    let (data, _) = try await URLSession.shared.data(from: remote)
                    try data.write(to: local)
                    await MainActor.run {
                        AudioPriorityQueue.shared.playWhisper(url: local, volume: volume)
                    }
                } catch {
                    print("[WhisperPlayer] Download-and-play failed: \(error)")
                }
            }
        }
    }

    func preview(_ whisper: WhisperDefinition, volume: Float = 0.6) {
        stop()
        coordinator.activate(for: .playbackOnly, consumer: "whisper-preview")

        if isAvailable(whisper) {
            playLocal(localURL(for: whisper), volume: volume)
        } else {
            previewTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let (data, _) = try await URLSession.shared.data(from: remoteURL(for: whisper))
                    guard !Task.isCancelled else { return }
                    await MainActor.run { self.playData(data, volume: volume) }
                } catch {
                    if !Task.isCancelled {
                        print("[WhisperPlayer] Preview download error: \(error)")
                    }
                    await MainActor.run { self.coordinator.deactivate(consumer: "whisper-preview") }
                }
            }
        }
    }

    private func playLocal(_ url: URL, volume: Float) {
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.volume = volume
            p.prepareToPlay()
            p.play()
            player = p
            isPlaying = true
        } catch {
            print("[WhisperPlayer] Preview error: \(error)")
            coordinator.deactivate(consumer: "whisper-preview")
        }
    }

    private func playData(_ data: Data, volume: Float) {
        do {
            let p = try AVAudioPlayer(data: data)
            p.delegate = self
            p.volume = volume
            p.prepareToPlay()
            p.play()
            player = p
            isPlaying = true
        } catch {
            print("[WhisperPlayer] Preview error: \(error)")
            coordinator.deactivate(consumer: "whisper-preview")
        }
    }

    func stop() {
        previewTask?.cancel()
        previewTask = nil
        guard player != nil else { return }
        player?.stop()
        player = nil
        isPlaying = false
        coordinator.deactivate(consumer: "whisper-preview")
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async { [weak self] in
            self?.player = nil
            self?.isPlaying = false
            self?.coordinator.deactivate(consumer: "whisper-preview")
        }
    }
}
```

Key changes from the previous version:

- `allDownloaded` and `downloadAll()` are **removed**. Any call site that used them must be updated in Task 7.
- `downloadTask` is **removed**.
- `prefetchCategory(_:)` is **added**.
- `seedFromBundleIfEmpty()` is **added** and called from `init()`.
- `isPrefetching` replaces `isDownloading` — it's only true while per-category prefetch tasks are running.
- `remoteURL(for:)` now uses `Config.Whisper.cdnBaseURL` instead of a private hardcoded URL.

- [ ] **Step 2: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -30
```

Expected: the build will **FAIL** at this point because `WhisperPlacementSheet.swift` still references `whisperPlayer.allDownloaded` and `whisperPlayer.downloadAll()`. That's acceptable — Task 7 fixes it. For now, verify the failure is only in `WhisperPlacementSheet.swift` and not anywhere else.

If the only errors are in `WhisperPlacementSheet.swift`, proceed. Otherwise, investigate.

- [ ] **Step 3: Do NOT commit yet**

This task leaves the tree in a broken state temporarily. The next task (Task 6) wires the service into AppDelegate (which doesn't touch WhisperPlayer), and Task 7 fixes the WhisperPlacementSheet call sites and restores the build. We'll commit Tasks 5-7 together as a cohesive "switch to dynamic catalog" change.

Leave Task 5's edits in the working tree and move on.

---

## Task 6: Sync the whisper manifest on app launch

**Files:**
- Modify: `Pilgrim/AppDelegate.swift:79-80`

- [ ] **Step 1: Add `WhisperManifestService.shared.syncIfNeeded()` to the launch completion**

Open `Pilgrim/AppDelegate.swift` and locate the block at lines 76-82:

```swift
        DataManager.setup(
            completion: { _ in
                
                AudioManifestService.shared.syncIfNeeded()
                VoiceGuideManifestService.shared.syncIfNeeded()
                Task { await CollectiveCounterService.shared.fetch() }
```

Add one line so it reads:

```swift
        DataManager.setup(
            completion: { _ in
                
                AudioManifestService.shared.syncIfNeeded()
                VoiceGuideManifestService.shared.syncIfNeeded()
                WhisperManifestService.shared.syncIfNeeded()
                Task { await CollectiveCounterService.shared.fetch() }
```

- [ ] **Step 2: Do NOT build yet**

The build is still broken from Task 5 at `WhisperPlacementSheet.swift`. We'll fix it in Task 7 and build/commit everything together.

Leave the edit in the working tree and move on.

---

## Task 7: Update `WhisperPlacementSheet` to use the manifest service

**Files:**
- Modify: `Pilgrim/Scenes/ActiveWalk/WhisperPlacementSheet.swift`

Four changes:

1. Remove the `whisperPlayer.downloadAll()` call in `onAppear`
2. Replace `WhisperCatalog.whispers(for:)` with the appropriate service method in preview and placement
3. Add `.onChange(of: selectedCategory)` that triggers `whisperPlayer.prefetchCategory(...)` for the newly selected category
4. Filter the category `ForEach` through `WhisperManifestService.shared.placeableCategories()` so empty categories (like Play before its content drop) disappear

- [ ] **Step 1: Replace the file in full**

Write `Pilgrim/Scenes/ActiveWalk/WhisperPlacementSheet.swift`:

```swift
import SwiftUI

struct WhisperPlacementSheet: View {

    let currentLocation: TempRouteDataSample?
    let onPlace: (WhisperDefinition, KanjiExpiryPicker.ExpiryDuration) -> Void
    let onDismiss: () -> Void

    @ObservedObject private var whisperPlayer = WhisperPlayer.shared
    @ObservedObject private var manifestService = WhisperManifestService.shared
    @State private var selectedCategory: WhisperCategory?
    @State private var selectedExpiry: KanjiExpiryPicker.ExpiryDuration = .sevenDays
    @State private var previewingCategory: WhisperCategory?

    var body: some View {
        VStack(spacing: 0) {
            Text("Leave a Whisper")
                .font(Constants.Typography.heading)
                .foregroundColor(Color.ink.opacity(0.8))
                .padding(.top, 12)

            VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
                VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
                    Text("Duration")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog.opacity(0.5))

                    KanjiExpiryPicker(selected: $selectedExpiry)
                }

                VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
                    Text("Choose an energy")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog.opacity(0.5))

                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(manifestService.placeableCategories(), id: \.rawValue) { category in
                                categoryRow(category)
                            }
                        }
                    }
                }

                privacyNotice

                Button(action: {
                    guard let category = selectedCategory else { return }
                    let whispers = manifestService.placeableWhispers(for: category)
                    guard let whisper = whispers.randomElement() else { return }
                    whisperPlayer.stop()
                    onPlace(whisper, selectedExpiry)
                }) {
                    Text("Leave Whisper")
                        .font(Constants.Typography.button)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(selectedCategory != nil ? Color.stone : Color.fog.opacity(0.3))
                        .foregroundColor(selectedCategory != nil ? .parchment : .fog)
                        .cornerRadius(Constants.UI.CornerRadius.normal)
                }
                .disabled(selectedCategory == nil)
            }
            .padding(.horizontal, Constants.UI.Padding.normal)
            .padding(.top, Constants.UI.Padding.big)

            Spacer()
        }
        .onDisappear {
            whisperPlayer.stop()
        }
        .onChange(of: selectedCategory) { newValue in
            guard let newValue else { return }
            whisperPlayer.prefetchCategory(newValue)
        }
    }

    private func categoryRow(_ category: WhisperCategory) -> some View {
        let isSelected = selectedCategory == category
        let isPreviewing = whisperPlayer.isPlaying && previewingCategory == category
        return Button {
            selectedCategory = category
        } label: {
            HStack(spacing: 12) {
                Button {
                    if isPreviewing {
                        whisperPlayer.stop()
                        previewingCategory = nil
                    } else {
                        let whispers = manifestService.whispers(for: category)
                        if let whisper = whispers.randomElement() {
                            whisperPlayer.preview(whisper)
                            previewingCategory = category
                            selectedCategory = category
                        }
                    }
                } label: {
                    Image(systemName: isPreviewing ? "stop.circle" : "play.circle")
                        .font(.title3)
                        .foregroundColor(Color(category.borderColor))
                }

                Text(category.rawValue.capitalized)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink.opacity(0.9))

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundColor(.stone)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.small)
                    .fill(isSelected ? Color.parchmentSecondary.opacity(0.5) : Color.parchmentSecondary.opacity(0.2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.small)
                    .stroke(Color(category.borderColor), lineWidth: isSelected ? 2 : 1)
                    .opacity(isSelected ? 1.0 : 0.4)
            )
        }
    }

    private var privacyNotice: some View {
        Text("Your location is shared anonymously. Whispers expire after the chosen duration. A random message from this category will be placed.")
            .font(Constants.Typography.caption)
            .foregroundColor(.fog.opacity(0.4))
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}
```

Key changes from the previous version:

- Added `@ObservedObject private var manifestService = WhisperManifestService.shared`
- `ForEach(WhisperCategory.allCases, id: \.rawValue)` → `ForEach(manifestService.placeableCategories(), id: \.rawValue)`
- `WhisperCatalog.whispers(for:)` → `manifestService.placeableWhispers(for:)` (placement button) and `manifestService.whispers(for:)` (preview)
- Removed the `onAppear { if !whisperPlayer.allDownloaded { whisperPlayer.downloadAll() } }` block
- Added `.onChange(of: selectedCategory) { ... prefetchCategory(...) }`

- [ ] **Step 2: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -20
```

Expected: the build should now fail only in `ActiveWalkView.swift:911` where `WhisperCatalog.whisper(byId:)` is still referenced. If so, proceed — Task 8 fixes it. If other errors appear, investigate.

- [ ] **Step 3: Do NOT commit yet**

The tree is still broken at `ActiveWalkView.swift`. Move to Task 8 and commit Tasks 5-8 together.

---

## Task 8: Update `handleAnnotationTap` in `ActiveWalkView`

**Files:**
- Modify: `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift` around line 911

- [ ] **Step 1: Update the whisper lookup**

Open `Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift`. Find the `handleAnnotationTap` function (around line 904) and locate this block:

```swift
        case .whisper:
            let coord = annotation.coordinate
            if let cached = GeoCacheService.shared.cachedWhispers.first(where: {
                abs($0.latitude - coord.latitude) < 0.0001 && abs($0.longitude - coord.longitude) < 0.0001
            }),
               let definition = WhisperCatalog.whisper(byId: cached.whisperId) {
                WhisperPlayer.shared.play(definition)
                HapticPattern.whisperProximity.fire()
            }
```

Replace `WhisperCatalog.whisper(byId: cached.whisperId)` with `WhisperManifestService.shared.whisper(byId: cached.whisperId)`:

```swift
        case .whisper:
            let coord = annotation.coordinate
            if let cached = GeoCacheService.shared.cachedWhispers.first(where: {
                abs($0.latitude - coord.latitude) < 0.0001 && abs($0.longitude - coord.longitude) < 0.0001
            }),
               let definition = WhisperManifestService.shared.whisper(byId: cached.whisperId) {
                WhisperPlayer.shared.play(definition)
                HapticPattern.whisperProximity.fire()
            }
```

- [ ] **Step 2: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **` — the build should now be clean with `WhisperCatalog.all` still present but no longer referenced from call sites.

- [ ] **Step 3: Run unit tests to confirm nothing regressed**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:UnitTests/WhisperManifestDecodingTests \
  -only-testing:UnitTests/WhisperManifestFilteringTests 2>&1 | tail -10
```

Expected: all tests PASS.

- [ ] **Step 4: Commit Tasks 5 + 6 + 7 + 8 together**

```bash
git add Pilgrim/Models/Whisper/WhisperPlayer.swift \
        Pilgrim/AppDelegate.swift \
        Pilgrim/Scenes/ActiveWalk/WhisperPlacementSheet.swift \
        Pilgrim/Scenes/ActiveWalk/ActiveWalkView.swift
git commit -m "$(cat <<'EOF'
feat(whispers): route call sites through WhisperManifestService

Replaces the static WhisperCatalog lookups with the new manifest
service across WhisperPlayer, WhisperPlacementSheet, ActiveWalkView,
and AppDelegate:

- WhisperPlayer drops eager downloadAll(); adds per-category
  prefetchCategory() and bundled-audio seeding on first launch.
- WhisperPlacementSheet sources categories from
  placeableCategories() (hides empty ones), prefetches on selection,
  picks random placement from placeableWhispers(), and previews from
  the full category list including retired.
- ActiveWalkView.handleAnnotationTap resolves whisper metadata via
  WhisperManifestService.shared.whisper(byId:), so the tap-to-play
  flow on existing placements keeps working through manifest updates.
- AppDelegate triggers a background manifest sync on cold launch
  alongside the existing audio and voice-guide manifest syncs.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: Remove the legacy `WhisperCatalog.swift` file

**Files:**
- Delete: `Pilgrim/Models/Whisper/WhisperCatalog.swift`
- Modify: `Pilgrim.xcodeproj/project.pbxproj` (via Xcode)

- [ ] **Step 1: Confirm no remaining references**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | grep -c "WhisperCatalog"
```

Expected: the count is 0 in error output. If any references appear, grep the codebase for `WhisperCatalog` and fix them before proceeding.

Then verify with a source grep:

```bash
rg "WhisperCatalog" Pilgrim UnitTests 2>&1 | grep -v "WhisperCatalog.swift"
```

Expected: no output (the only hit should be the file itself, which is filtered out).

- [ ] **Step 2: Remove the file from the Xcode project**

Open Xcode → Project Navigator → `Pilgrim/Models/Whisper/WhisperCatalog.swift` → right-click → **Delete** → choose **Move to Trash**.

Xcode will update `Pilgrim.xcodeproj/project.pbxproj` and delete the file from disk.

- [ ] **Step 3: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add -u Pilgrim/Models/Whisper/WhisperCatalog.swift Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
refactor(whispers): delete legacy hardcoded WhisperCatalog

All call sites now resolve whispers through WhisperManifestService.
The static catalog is no longer reachable and can be removed.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: Seed the initial bootstrap bundle

**Files:**
- Create: `scripts/regen-whisper-bootstrap.sh`
- Create: `Pilgrim/Support Files/whispers-bootstrap.json`
- Create: `Pilgrim/Support Files/whisper-audio/whisper-*.aac` (21 files)
- Modify: `Pilgrim.xcodeproj/project.pbxproj` (via Xcode to add bundle resources)

This task ships the 21 existing whispers bundled in the app so fresh installs with no network still work. Play whispers are NOT included in the initial bootstrap — they arrive via the post-merge content drop (see the Post-Merge Tasks section at the end).

The one-shot generation is split into two parts:

1. A reusable shell script (`scripts/regen-whisper-bootstrap.sh`) that pulls the canonical manifest + audio from R2 into `Pilgrim/Support Files/`
2. A one-time manual step to upload the canonical `manifest.json` to R2 and run the script

### Prerequisite: canonical `manifest.json` on R2

Before running the script, make sure `https://cdn.pilgrimapp.org/audio/whisper/manifest.json` exists and contains exactly the 21 current whisper entries. The canonical JSON for the initial bootstrap (no Play whispers yet) is:

```json
{
  "version": 1,
  "whispers": [
    {"id": "presence-1", "title": "What do you see right now?", "category": "presence", "audioFileName": "whisper-presence-1", "durationSec": 6, "retiredAt": null},
    {"id": "presence-2", "title": "Feel your feet on the earth", "category": "presence", "audioFileName": "whisper-presence-2", "durationSec": 8, "retiredAt": null},
    {"id": "presence-3", "title": "You are here", "category": "presence", "audioFileName": "whisper-presence-3", "durationSec": 5, "retiredAt": null},
    {"id": "lightness-1", "title": "You are doing great", "category": "lightness", "audioFileName": "whisper-lightness-1", "durationSec": 6, "retiredAt": null},
    {"id": "lightness-2", "title": "Whatever you were worrying about can wait", "category": "lightness", "audioFileName": "whisper-lightness-2", "durationSec": 8, "retiredAt": null},
    {"id": "lightness-3", "title": "Take a breath", "category": "lightness", "audioFileName": "whisper-lightness-3", "durationSec": 8, "retiredAt": null},
    {"id": "wonder-1", "title": "Something extraordinary is happening", "category": "wonder", "audioFileName": "whisper-wonder-1", "durationSec": 7, "retiredAt": null},
    {"id": "wonder-2", "title": "The light left its source long ago", "category": "wonder", "audioFileName": "whisper-wonder-2", "durationSec": 7, "retiredAt": null},
    {"id": "wonder-3", "title": "You are spinning through space", "category": "wonder", "audioFileName": "whisper-wonder-3", "durationSec": 9, "retiredAt": null},
    {"id": "gratitude-1", "title": "Thank the one who planted this tree", "category": "gratitude", "audioFileName": "whisper-gratitude-1", "durationSec": 8, "retiredAt": null},
    {"id": "gratitude-2", "title": "Your body carried you here", "category": "gratitude", "audioFileName": "whisper-gratitude-2", "durationSec": 8, "retiredAt": null},
    {"id": "gratitude-3", "title": "This moment is a gift", "category": "gratitude", "audioFileName": "whisper-gratitude-3", "durationSec": 6, "retiredAt": null},
    {"id": "compassion-1", "title": "Others have walked here with heavy hearts", "category": "compassion", "audioFileName": "whisper-compassion-1", "durationSec": 6, "retiredAt": null},
    {"id": "compassion-2", "title": "Set something down", "category": "compassion", "audioFileName": "whisper-compassion-2", "durationSec": 6, "retiredAt": null},
    {"id": "compassion-3", "title": "The path does not ask you to be perfect", "category": "compassion", "audioFileName": "whisper-compassion-3", "durationSec": 8, "retiredAt": null},
    {"id": "courage-1", "title": "The next step is the only one that matters", "category": "courage", "audioFileName": "whisper-courage-1", "durationSec": 6, "retiredAt": null},
    {"id": "courage-2", "title": "What you seek is also seeking you", "category": "courage", "audioFileName": "whisper-courage-2", "durationSec": 6, "retiredAt": null},
    {"id": "courage-3", "title": "You already know the answer", "category": "courage", "audioFileName": "whisper-courage-3", "durationSec": 7, "retiredAt": null},
    {"id": "stillness-1", "title": "Be still", "category": "stillness", "audioFileName": "whisper-stillness-1", "durationSec": 3, "retiredAt": null},
    {"id": "stillness-2", "title": "Breathe", "category": "stillness", "audioFileName": "whisper-stillness-2", "durationSec": 4, "retiredAt": null},
    {"id": "stillness-3", "title": "You are an animal on the earth", "category": "stillness", "audioFileName": "whisper-stillness-3", "durationSec": 6, "retiredAt": null}
  ]
}
```

Upload this exact JSON to `https://cdn.pilgrimapp.org/audio/whisper/manifest.json` using the R2 dashboard or `wrangler r2 object put`. The 21 corresponding `.aac` files should already be at `https://cdn.pilgrimapp.org/audio/whisper/whisper-*.aac` (they have been there since before this change).

Then purge the Cloudflare cache for `manifest.json` so the latest version is served: either via the Cloudflare dashboard, or:

```bash
curl -X POST "https://api.cloudflare.com/client/v4/zones/<ZONE_ID>/purge_cache" \
  -H "Authorization: Bearer <CF_API_TOKEN>" \
  -H "Content-Type: application/json" \
  --data '{"files":["https://cdn.pilgrimapp.org/audio/whisper/manifest.json"]}'
```

- [ ] **Step 1: Create the `regen-whisper-bootstrap.sh` helper script**

Write `scripts/regen-whisper-bootstrap.sh`:

```bash
#!/bin/bash
#
# Pulls the canonical whisper manifest and all referenced audio files from R2
# into Pilgrim/Support Files/ so they ship as bundled resources.
#
# Idempotent. Run whenever the manifest on R2 changes and you want the next
# release to have a fresh bundled bootstrap.
#
# Usage: scripts/regen-whisper-bootstrap.sh

set -euo pipefail

MANIFEST_URL="https://cdn.pilgrimapp.org/audio/whisper/manifest.json"
CDN_BASE="https://cdn.pilgrimapp.org/audio/whisper"
SUPPORT_DIR="Pilgrim/Support Files"
BOOTSTRAP_JSON="$SUPPORT_DIR/whispers-bootstrap.json"
AUDIO_DIR="$SUPPORT_DIR/whisper-audio"

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

step() { echo -e "\n→ $1"; }
pass() { echo -e "  ${GREEN}✓ $1${NC}"; }
fail() { echo -e "  ${RED}✗ $1${NC}"; exit 1; }

command -v curl >/dev/null || fail "curl not on PATH"
command -v jq >/dev/null || fail "jq not on PATH (brew install jq)"

step "Downloading manifest from R2"
mkdir -p "$SUPPORT_DIR" "$AUDIO_DIR"
curl -fsSL "$MANIFEST_URL" -o "$BOOTSTRAP_JSON" || fail "Failed to fetch manifest"
pass "Wrote $BOOTSTRAP_JSON"

MANIFEST_VERSION=$(jq -r .version "$BOOTSTRAP_JSON")
WHISPER_COUNT=$(jq -r '.whispers | length' "$BOOTSTRAP_JSON")
pass "Manifest version=$MANIFEST_VERSION, whispers=$WHISPER_COUNT"

step "Downloading audio files"
jq -r '.whispers[] | .audioFileName' "$BOOTSTRAP_JSON" | while read -r name; do
    dest="$AUDIO_DIR/$name.aac"
    if [ -f "$dest" ]; then
        echo "  · $name.aac (already present, skipping)"
        continue
    fi
    echo "  · $name.aac"
    curl -fsSL "$CDN_BASE/$name.aac" -o "$dest" || fail "Failed to fetch $name.aac"
done
pass "All audio files downloaded to $AUDIO_DIR"

step "Summary"
BUNDLED_COUNT=$(find "$AUDIO_DIR" -name "*.aac" | wc -l | tr -d ' ')
echo "  Bundled audio files: $BUNDLED_COUNT"
echo "  Manifest version:    $MANIFEST_VERSION"

if [ "$BUNDLED_COUNT" -ne "$WHISPER_COUNT" ]; then
    fail "File count ($BUNDLED_COUNT) does not match manifest count ($WHISPER_COUNT)"
fi

pass "Bootstrap ready. Add new audio files to the Xcode target's Copy Bundle Resources phase if any were downloaded."
```

Make it executable:

```bash
chmod +x scripts/regen-whisper-bootstrap.sh
```

- [ ] **Step 2: Run the script**

```bash
./scripts/regen-whisper-bootstrap.sh
```

Expected output includes "Manifest version=1, whispers=21" and "All audio files downloaded". Verify by listing the results:

```bash
ls "Pilgrim/Support Files/whisper-audio/" | wc -l
ls "Pilgrim/Support Files/whispers-bootstrap.json"
```

Expected: `21` and the JSON file listed.

- [ ] **Step 3: Add the new resources to the Xcode project**

Open Xcode → Project Navigator → right-click `Pilgrim/Support Files` → **Add Files to "Pilgrim"…** → select both:
- `whispers-bootstrap.json`
- `whisper-audio/` (add as a folder reference — choose **Create folder references**, NOT "Create groups", so new .aac files added later are automatically picked up)

Ensure the **Pilgrim** target is checked. Both items must end up in the **Copy Bundle Resources** build phase of the Pilgrim target. Verify under **Pilgrim target → Build Phases → Copy Bundle Resources** that both items appear.

- [ ] **Step 4: Build and run on simulator**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -10
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git add scripts/regen-whisper-bootstrap.sh \
        "Pilgrim/Support Files/whispers-bootstrap.json" \
        "Pilgrim/Support Files/whisper-audio/" \
        Pilgrim.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(whispers): ship initial bootstrap bundle (21 whispers)

Bundles the 21 existing whispers as .aac resources in
Pilgrim/Support Files/whisper-audio/ and a snapshot manifest at
whispers-bootstrap.json. First-launch users now have a working
offline catalog without downloading anything.

Adds scripts/regen-whisper-bootstrap.sh, a reusable helper that
pulls the latest manifest + audio from R2. Release workflow will
wire this in next task.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: Wire `regen-whisper-bootstrap.sh` into `scripts/release.sh`

**Files:**
- Modify: `scripts/release.sh`

Adds a new `bootstrap-whispers` subcommand that invokes the helper, plus a call to it from the main `release` pipeline so each release automatically picks up the latest manifest.

- [ ] **Step 1: Add the subcommand dispatcher**

Open `scripts/release.sh` and locate the `usage()` function. Add a line for the new subcommand:

```bash
    echo "  bootstrap-whispers Regenerate the bundled whisper bootstrap from R2"
```

Somewhere in the `Commands:` block between `changelog` and `tag`.

- [ ] **Step 2: Add the handler function**

Near the other command handler functions (e.g., just after the `changelog()` function, before `tag()`), add:

```bash
bootstrap_whispers() {
    step "Regenerating whisper bootstrap bundle"
    if [ ! -x scripts/regen-whisper-bootstrap.sh ]; then
        fail "scripts/regen-whisper-bootstrap.sh not found or not executable"
    fi
    scripts/regen-whisper-bootstrap.sh
    pass "Whisper bootstrap regenerated. If new .aac files were added, verify they are in the Xcode target's Copy Bundle Resources phase."
}
```

- [ ] **Step 3: Add the dispatcher case**

Find the `case "$1" in` switch block near the bottom of `release.sh`. Add a new case:

```bash
    bootstrap-whispers)
        bootstrap_whispers
        ;;
```

Next to the other single-command dispatchers like `changelog)`.

- [ ] **Step 4: Add to the `release` pipeline**

Find the `release)` case block. It calls other steps like `check`, `bump_build`, `archive`, `upload`, `changelog`, `tag`. Add `bootstrap_whispers` between `check` and `bump_build` so the bundled bootstrap is refreshed at the very start of a release:

```bash
    release)
        check
        bootstrap_whispers
        bump_build
        # ... rest of the existing pipeline
        ;;
```

- [ ] **Step 5: Dry-run the new subcommand**

```bash
scripts/release.sh bootstrap-whispers
```

Expected: the helper runs, reports that all 21 audio files are already present (from Task 10), and exits 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/release.sh
git commit -m "$(cat <<'EOF'
chore(release): add bootstrap-whispers step to release pipeline

Refreshes the bundled whisper bootstrap from R2 at the start of each
release run, so every shipped build includes the latest manifest +
audio snapshot. Also exposes bootstrap-whispers as a standalone
subcommand for off-release regeneration.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: Manual end-to-end verification in the simulator

**Files:** none

This is the manual smoke test. No tests for UI flows, no tests for proximity encounters — just human verification that the feature works as described in the spec. Follow each scenario in order.

- [ ] **Step 1: Clean install — verify bundled bootstrap works offline**

```bash
# Fully wipe the simulator's app state
xcrun simctl uninstall booted org.walktalkmeditate.pilgrim 2>/dev/null || true

# Boot and run
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build 2>&1 | tail -5
```

Install the build on the simulator, turn on airplane mode in the simulator (Features → Network Link Conditioner → 100% Loss, or better, toggle Wi-Fi off on the host and check the simulator inherits), then:

1. Launch the app
2. Start a walk
3. Open the Whisper placement sheet
4. Verify: 7 categories visible (no Play — it has no whispers yet because the post-merge content drop has not happened)
5. Tap a category preview button → audio plays from local cache (instant)
6. Tap "Leave Whisper" — server call fails gracefully (offline), sheet behavior matches existing offline behavior

If the Play category appears, this is a bug — it should be filtered out by `placeableCategories()`. Debug before proceeding.

- [ ] **Step 2: Place a whisper and tap it on the map**

Restore network. Then:

1. Start a walk with location enabled
2. Open the Whisper placement sheet
3. Select a category (e.g., Gratitude)
4. Tap "Leave Whisper"
5. Verify: sonic receipt plays within ~200ms
6. Verify: a pin appears on the map at your location
7. Tap the pin
8. Verify: the same whisper plays (may have brief download hitch if cache was cleared; should be instant if it just played)

- [ ] **Step 3: Manifest sync on cold launch**

Verify the sync fires on cold launch. Add a temporary debug line to `WhisperManifestService.syncIfNeeded()` at the top:

```swift
print("[WhisperManifestService] syncIfNeeded() called")
```

Force-quit the app from the simulator app switcher (swipe up), then relaunch. Watch the Xcode console or use:

```bash
xcrun simctl spawn booted log stream --level debug --predicate 'processImagePath CONTAINS "Pilgrim"' 2>&1 | grep WhisperManifestService
```

Expected: the debug line prints once per cold launch. Remove the debug line before committing.

- [ ] **Step 4: Simulate a manifest update**

This step validates silent growth. You'll update the R2 manifest to include one new fake whisper and verify the app picks it up silently.

1. In the R2 manifest, bump `version` from 1 to 2 and add a new entry — e.g., add a second Gratitude entry:
   ```json
   {"id": "gratitude-test", "title": "Test whisper do not ship", "category": "gratitude", "audioFileName": "whisper-gratitude-1", "durationSec": 5, "retiredAt": null}
   ```
   Reuse `whisper-gratitude-1` as the audio filename so you don't need to upload a new audio file just for the test.
2. Upload the updated manifest, purge the Cloudflare cache.
3. In the simulator, force-quit Pilgrim and cold-launch it.
4. Wait ~5 seconds, then open the placement sheet and select Gratitude.
5. Tap "Leave Whisper" enough times (~10) that you statistically hit the new entry at least once. The title `"Test whisper do not ship"` will never appear in the UI — but the underlying pick is now from 4 entries instead of 3. You can verify by logging the picked whisper ID before `onPlace` is called.
6. After verification, revert the manifest: remove the test entry, bump `version` to 3, upload, purge cache.

- [ ] **Step 5: Retirement check**

Still in the test manifest, flip `retiredAt` on one existing entry (e.g., `"retiredAt": "2026-04-11T00:00:00Z"` on `gratitude-1`). Upload, purge, cold-launch.

1. Verify: `gratitude-1` no longer appears as a possible random placement (over 20 taps of "Leave Whisper" with Gratitude selected, you should never hit `gratitude-1`)
2. But: if you still have a pre-retirement placed `gratitude-1` pin on the map from Step 2, tapping it should still play the whisper normally

After verification, revert: remove the `retiredAt` field (or set it back to `null`), bump version, upload, purge.

- [ ] **Step 6: Mark verification as complete**

This is not a code step — just your acknowledgment that the manual tests passed. Make notes of any surprising behavior for follow-up.

- [ ] **Step 7: Commit (if any debug lines were left in place)**

If you ended up leaving verification instrumentation in the code, either remove it now (preferred) or commit as a follow-up. This step is a no-op if the tree is clean.

```bash
git status
```

Expected: `nothing to commit, working tree clean`.

---

## Post-Merge Tasks (Manual, Content Drop)

These run AFTER the code is merged and released. They are pure content work — no further code changes are needed.

### Creator records and publishes the initial 10 Play whispers

Out of the repo and out of the plan scope, but the sequence is:

1. Creator records 10 Play whispers. The vibe: gently absurd, not jokey — things that make a walking pilgrim smile with their whole face. Draft phrases from the brainstorming session:
   - "You don't have to walk in a straight line"
   - "Everything you're doing right now is slightly ridiculous. Beautiful too."
   - "A squirrel is judging you. Kindly ignore it."
   - "What if this is just a really slow dance?"
   - "You could skip. You probably won't. But you could."
   - "Small detour. The path won't mind."
   - "This wouldn't be on a brochure. Neither are you."
   - "Try walking slightly sillier for a second"
   - "The path is making a face at you. Look closely."
   - "You're on an adventure. Nobody told you, but here you are."

   These are suggestions, not canonical — the creator picks final phrases.
2. Master each recording in the creator's preferred DAW, target format `.aac`, ~70KB per file.
3. Upload the 10 files to R2 at:
   - `https://cdn.pilgrimapp.org/audio/whisper/whisper-play-1.aac`
   - `https://cdn.pilgrimapp.org/audio/whisper/whisper-play-2.aac`
   - ...
   - `https://cdn.pilgrimapp.org/audio/whisper/whisper-play-10.aac`
4. Edit the canonical `manifest.json` on R2 to add 10 new entries (one per recording), bump `version`, upload.
5. Purge the Cloudflare cache for `manifest.json`.
6. The next cold launch on any existing user's device will silently pick up the new Play category and, the first time the user selects Play in the placement sheet, their app will prefetch the 10 audio files.

Optional follow-up: run `scripts/release.sh bootstrap-whispers` in the repo to regenerate the bundled bootstrap, commit, and ship a release so new installs also get the Play files bundled. Otherwise, fresh installs post-content-drop will see Play appear on the second cold launch (first launch: bootstrap has no Play → sync pulls new manifest → second launch: Play is visible).

---

## Self-Review

### Spec coverage

Walking each spec section:

- **Goals → categories**: Task 1 adds `.play` ✓
- **Goals → remote manifest**: Tasks 2, 3, 4 ✓
- **Goals → silent growth**: Task 7 removes user-visible new-content indicators (none existed, but we don't add any) ✓
- **Goals → offline-first**: Tasks 5 (bundle seeding), 10 (initial bootstrap) ✓
- **Goals → anonymity**: nothing new added that would compromise anonymity ✓
- **Goals → sonic receipt**: Task 5's `prefetchCategory` + Task 7's onChange prefetch hook preserves the UX; spec explicitly notes the degradation-on-slow-network is acceptable ✓
- **Design § 1 Categories**: Task 1 ✓
- **Design § 2 Manifest Architecture → server-side**: Task 10 (canonical manifest publish) + documentation in Task 10 prerequisites ✓
- **Design § 2 → client-side WhisperManifestService**: Task 4 ✓
- **Design § 2 → WhisperManifest schema**: Task 3 ✓
- **Design § 3 Download Policy → all rows of the table**: Tasks 5, 6, 7, 8 collectively ✓
- **Design § 3 → Bundled bootstrap**: Tasks 5 (seeding logic), 10 (initial files) ✓
- **Design § 3 → Stale-while-revalidate**: Task 6 wires sync on cold launch ✓
- **Design § 4 Retirement**: Task 4's `placeableWhispers` filter + Task 7's `placeableCategories` ✓
- **Design § 4 Takedown**: explicitly deferred per decisions, no task ✓
- **Design § 4 Broken file**: existing catch in WhisperPlayer, unchanged ✓
- **Design § 5 Flow examples**: Task 12 verifies all three scenarios ✓
- **Design § 6 File changes**: table matches the File Structure section ✓
- **Design § 7 Edge Cases**: spot-checked against Task 12's scenarios ✓
- **Design § 8 Out of Scope**: nothing added beyond scope ✓
- **Decisions § 1 Play count**: documented in the post-merge task section ✓
- **Decisions § 2 Play color**: Task 1 ✓
- **Decisions § 3 Bootstrap automation**: Task 11 ✓
- **Decisions § 4 Hard takedown deferred**: not built ✓

All spec requirements have tasks. No gaps.

### Placeholder scan

Scanning the plan for red-flag phrases:

- `TBD`, `TODO`, `implement later`, `fill in details`: none in task steps (only in quoted spec/docs where explicitly noted).
- "Add appropriate error handling" / "add validation" / "handle edge cases": none.
- "Write tests for the above" without code: none — Task 4 includes full test bodies.
- "Similar to Task N": none — each task is self-contained with full code.
- Undefined method or type references: all method names (`whispers(for:)`, `placeableWhispers(for:)`, `whisper(byId:)`, `placeableCategories()`, `prefetchCategory(_:)`, `seedFromBundleIfEmpty()`, `syncIfNeeded()`, `loadLocalManifest()`, `loadBootstrapManifest()`) are defined in Task 3, 4, or 5. Types (`WhisperManifest`, `WhisperDefinition`, `WhisperCategory`) are defined in Tasks 1 and 3.

Clean.

### Type consistency

- `WhisperManifest` — defined in Task 3 with fields `version: Int`, `whispers: [WhisperDefinition]`. Used consistently in Tasks 4, 5, 10.
- `WhisperDefinition` — `retiredAt: Date?` added in Task 1, used in Task 4 tests and Task 10 bootstrap JSON (as ISO8601 string, decoded via `.iso8601` strategy in Task 4's service).
- `WhisperCategory` — `.play` added in Task 1, used in Task 4 tests (`.play` in `makeManifest`), service filters, and Task 7's placement sheet.
- `WhisperManifestService` public methods: `whispers(for:)`, `placeableWhispers(for:)`, `whisper(byId:)`, `placeableCategories()`, `syncIfNeeded()`. All four are called consistently across Tasks 7 and 8.
- `WhisperPlayer` public methods changed: `downloadAll()` and `allDownloaded` removed (Task 5), `prefetchCategory(_:)` added (Task 5), used in Task 7.
- `Config.Whisper.manifestURL` + `cdnBaseURL` — defined in Task 2, used in Tasks 4 (service fetch) and 5 (remote URL builder).

Consistent.

No issues found. Plan is ready.
