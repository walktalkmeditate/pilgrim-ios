# Walk with Me — iOS Interactive Share Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the "Interactive" toggle to the walk share screen so a share can carry voice recordings, hi-res photos, and pauses to the already-deployed story-page worker.

**Architecture:** Everything is additive around the existing `WalkShareViewModel.buildPayload()` → `ShareService.share()` flow. A new `TourBuilder` classifies and selects recordings (wpm gate, caps, renumbering), `RouteTrimmer` shaves private meters off route ends, `ShareService.uploadMedia` PUTs media files sequentially after the share POST, and the share screen gains an Interactive section with a per-recording disclosure. The worker API is **frozen and live** — this plan conforms to it exactly; no worker changes.

**Tech Stack:** SwiftUI + existing share stack (`SharePayload`, `ShareService`), XCTest (`UnitTests/` target, `@testable import Pilgrim`, `DateFactory`/`WalkDataFactory` fixtures), PhotosKit for hi-res export.

## Global Constraints (frozen worker contract — verbatim)

- POST `https://walk.pilgrimapp.org/api/share` with `X-Device-Token`. Media upload AFTER the POST: `PUT /api/share/{id}/audio/{n}` and `PUT /api/share/{id}/photos/{n}` — `n` is **1-based**, same `X-Device-Token` as the POST, `Content-Length` required, audio `Content-Type: audio/mp4`, photos `image/jpeg`. Success = 201 `{ok:true}`.
- `tour.recordings[i].n` MUST equal `i + 1` (renumber after exclusions). `kind` ∈ `"spoken" | "ambient"`. `size_bytes` integer > 0 and ≤ 15,728,640 (15 MB). Σ`size_bytes` ≤ 62,914,560 (60 MB). Σ`duration` ≤ 2700 s. Max **12** recordings. `transcription` (≤ 60,000 chars) and `wpm` optional — the page never renders transcripts; kind classification happens on-device.
- `tour.trim_m` ∈ [0, 1000]. Max **20** photos. Interactive photos omit inline `data` (PUT the JPEG instead, ≤ 2 MB each); photos MUST be PUT **in index order 1..N** (the enrich pipeline HEADs only the last photo to detect completion).
- `pauses` ≤ 200, each `end_ts > start_ts`. `expiry_days` ∈ {30, 90, 365}. `journal` ≤ 140 chars. All payload keys snake_case.
- Missing/failed media uploads do NOT invalidate the share — the page renders those voices as "voice unavailable". Audio files are the app's recorded `.m4a` (AAC) served as `audio/mp4`.
- wpm gate (spec): a recording with a transcription is `ambient` when it has **< 8 words OR < 30 wpm**; otherwise `spoken`. **No transcription → `spoken`.** The walker can override per recording (voice ⇄ ambience).
- iOS-only plan. `tour-v1.js` is frozen; nothing here may require worker changes.
- Project rules: `Constants.Typography.*` only (never `.system()`); extract SwiftUI subviews before any struct nears 700 lines (SwiftLint `type_body_length` errors at 750); run full-repo SwiftLint before pushing; every commit compiles and passes tests.

---

### Task 1: SharePayload learns the tour vocabulary

**Files:**
- Modify: `Pilgrim/Models/Share/SharePayload.swift`
- Test: `UnitTests/SharePayloadTourTests.swift` (create)

**Interfaces:**
- Consumes: nothing new.
- Produces: `SharePayload.Tour`, `SharePayload.TourRecording`, `SharePayload.Pause`, `SharePayload.Photo.data: String?`, `SharePayload.tour: Tour?`, `SharePayload.pauses: [Pause]?` — exact shapes below; Tasks 2/6 build these.

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Pilgrim

final class SharePayloadTourTests: XCTestCase {

    private func encodeToJSON(_ payload: SharePayload) throws -> [String: Any] {
        let data = try JSONEncoder().encode(payload)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func minimalPayload(tour: SharePayload.Tour?, pauses: [SharePayload.Pause]? = nil, photos: [SharePayload.Photo]? = nil) -> SharePayload {
        var payload = SharePayload(
            stats: .init(distance: 1000, activeDuration: 600, elevationAscent: nil, elevationDescent: nil, steps: nil, meditateDuration: 0, talkDuration: 0, weatherCondition: nil, weatherTemperature: nil),
            route: [.init(lat: 35.68, lon: -105.94, alt: 2100, ts: 1000), .init(lat: 35.69, lon: -105.93, alt: 2110, ts: 1600)],
            activityIntervals: [],
            journal: nil,
            expiryDays: 90,
            units: "metric",
            startDate: "2026-08-11T08:00:00Z",
            tzIdentifier: "America/Denver",
            toggledStats: ["distance"],
            placeStart: nil, placeEnd: nil, mark: nil,
            waypoints: nil,
            photos: photos
        )
        payload.tour = tour
        payload.pauses = pauses
        return payload
    }

    func testTourEncodesSnakeCaseWithOrderedRecordings() throws {
        let tour = SharePayload.Tour(
            recordings: [
                .init(n: 1, startTs: 1100, endTs: 1400, duration: 300, kind: "spoken", transcription: nil, wpm: 120, sizeBytes: 2_400_000),
                .init(n: 2, startTs: 1450, endTs: 1500, duration: 50, kind: "ambient", transcription: nil, wpm: nil, sizeBytes: 800_000),
            ],
            trimM: 150
        )
        let json = try encodeToJSON(minimalPayload(tour: tour))
        let tourJSON = try XCTUnwrap(json["tour"] as? [String: Any])
        XCTAssertEqual(tourJSON["trim_m"] as? Int, 150)
        let recs = try XCTUnwrap(tourJSON["recordings"] as? [[String: Any]])
        XCTAssertEqual(recs.count, 2)
        XCTAssertEqual(recs[0]["n"] as? Int, 1)
        XCTAssertEqual(recs[0]["start_ts"] as? Int, 1100)
        XCTAssertEqual(recs[0]["end_ts"] as? Int, 1400)
        XCTAssertEqual(recs[0]["kind"] as? String, "spoken")
        XCTAssertEqual(recs[0]["size_bytes"] as? Int, 2_400_000)
        XCTAssertEqual(recs[1]["wpm"] as? Double, nil)
    }

    func testPausesEncodeSnakeCase() throws {
        let json = try encodeToJSON(minimalPayload(tour: nil, pauses: [.init(startTs: 1150, endTs: 1450)]))
        let pauses = try XCTUnwrap(json["pauses"] as? [[String: Any]])
        XCTAssertEqual(pauses[0]["start_ts"] as? Int, 1150)
        XCTAssertEqual(pauses[0]["end_ts"] as? Int, 1450)
    }

    func testAbsentTourAndPausesOmittedFromJSON() throws {
        let json = try encodeToJSON(minimalPayload(tour: nil))
        XCTAssertNil(json["tour"])
        XCTAssertNil(json["pauses"])
    }

    func testPhotoWithoutDataOmitsDataKey() throws {
        let photo = SharePayload.Photo(lat: 35.69, lon: -105.94, ts: 1200, data: nil)
        let json = try encodeToJSON(minimalPayload(tour: nil, photos: [photo]))
        let photos = try XCTUnwrap(json["photos"] as? [[String: Any]])
        XCTAssertNil(photos[0]["data"])
        XCTAssertEqual(photos[0]["ts"] as? Int, 1200)
    }
}
```

- [ ] **Step 2: Run to verify failure**

Run: `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/SharePayloadTourTests`
Expected: FAIL — `Tour`, `Pause` types don't exist; `Photo.data` is non-optional.

- [ ] **Step 3: Implement**

In `SharePayload.swift`:

```swift
struct Pause: Encodable {
    let startTs: Int
    let endTs: Int

    enum CodingKeys: String, CodingKey {
        case startTs = "start_ts"
        case endTs = "end_ts"
    }
}

struct Tour: Encodable {
    let recordings: [TourRecording]
    let trimM: Int

    enum CodingKeys: String, CodingKey {
        case recordings
        case trimM = "trim_m"
    }
}

struct TourRecording: Encodable {
    let n: Int
    let startTs: Int
    let endTs: Int
    let duration: Double
    let kind: String
    let transcription: String?
    let wpm: Double?
    let sizeBytes: Int

    enum CodingKeys: String, CodingKey {
        case n, duration, kind, transcription, wpm
        case startTs = "start_ts"
        case endTs = "end_ts"
        case sizeBytes = "size_bytes"
    }
}
```

Change `Photo.data` to `let data: String?`, add `var tour: Tour? = nil` and `var pauses: [Pause]? = nil` stored properties, and add `tour`, `pauses` to the top-level `CodingKeys`. (Swift's default Encodable emits `nil` optionals as absent keys for these because encoding uses `encodeIfPresent` only with custom conformance — verify the "omitted" tests pass; if `NSNull` appears, add a custom `encode(to:)` for the two new fields using `encodeIfPresent`.)

The one existing `Photo(...)` construction site (`WalkShareViewModel.loadSharePhoto`) passes `data:` explicitly, so the optional change compiles without edits there.

- [ ] **Step 4: Run tests to verify pass** (same command)
- [ ] **Step 5: Commit** — `feat(share): payload learns tour, pauses, and PUT-uploaded photos`

---

### Task 2: TourBuilder — classification, caps, renumbering

**Files:**
- Create: `Pilgrim/Models/Share/TourBuilder.swift`
- Test: `UnitTests/TourBuilderTests.swift` (create)

**Interfaces:**
- Consumes: `VoiceRecordingInterface` (`startDate`, `endDate`, `duration`, `fileRelativePath`, `transcription`, `wordsPerMinute`).
- Produces (used by Tasks 6–8):

```swift
struct TourRecordingCandidate: Identifiable, Equatable {
    let id: Int                    // stable index into the walk's recordings, sorted by startDate
    let startTs: Int
    let endTs: Int
    let duration: Double
    let sizeBytes: Int             // file size on disk; 0 = file missing (excluded, not offerable)
    let transcription: String?
    let wpm: Double?
    let autoKind: TourRecordingKind
    var includeInShare: Bool
    var kindOverride: TourRecordingKind?
    var effectiveKind: TourRecordingKind { kindOverride ?? autoKind }
    var fileURL: URL?
}

enum TourRecordingKind: String { case spoken, ambient }

enum TourBuilder {
    static func candidates(for walk: WalkInterface) -> [TourRecordingCandidate]
    static func classify(transcription: String?, wpm: Double?) -> TourRecordingKind
    static func totals(of candidates: [TourRecordingCandidate]) -> (count: Int, bytes: Int, seconds: Double)
    static func validationError(for candidates: [TourRecordingCandidate]) -> String?
    static func tourPayload(candidates: [TourRecordingCandidate], trimM: Int) -> SharePayload.Tour
    static func includedFileURLs(candidates: [TourRecordingCandidate]) -> [URL]  // same order as payload n=1..N
}
```

Caps as constants: `maxRecordings = 12`, `maxFileBytes = 15 * 1024 * 1024`, `maxTotalBytes = 60 * 1024 * 1024`, `maxTotalSeconds: Double = 2700`.

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class TourBuilderTests: XCTestCase {

    func testClassify_noTranscriptionIsSpoken() {
        XCTAssertEqual(TourBuilder.classify(transcription: nil, wpm: nil), .spoken)
    }

    func testClassify_fewWordsIsAmbient() {
        XCTAssertEqual(TourBuilder.classify(transcription: "wind and birds", wpm: 200), .ambient)
    }

    func testClassify_slowSpeechIsAmbient() {
        let words = Array(repeating: "word", count: 20).joined(separator: " ")
        XCTAssertEqual(TourBuilder.classify(transcription: words, wpm: 12), .ambient)
    }

    func testClassify_realSpeechIsSpoken() {
        let words = Array(repeating: "word", count: 20).joined(separator: " ")
        XCTAssertEqual(TourBuilder.classify(transcription: words, wpm: 110), .spoken)
    }

    func testClassify_transcriptionWithoutWpmUsesWordCountOnly() {
        let words = Array(repeating: "word", count: 20).joined(separator: " ")
        XCTAssertEqual(TourBuilder.classify(transcription: words, wpm: nil), .spoken)
    }

    private func candidate(id: Int, bytes: Int = 1_000_000, seconds: Double = 60, included: Bool = true, kind: TourRecordingKind = .spoken) -> TourRecordingCandidate {
        TourRecordingCandidate(id: id, startTs: 1000 + id * 100, endTs: 1050 + id * 100, duration: seconds, sizeBytes: bytes, transcription: nil, wpm: nil, autoKind: kind, includeInShare: included, kindOverride: nil, fileURL: URL(fileURLWithPath: "/tmp/\(id).m4a"))
    }

    func testTourPayload_renumbersAfterExclusion() {
        let candidates = [candidate(id: 0), candidate(id: 1, included: false), candidate(id: 2)]
        let tour = TourBuilder.tourPayload(candidates: candidates, trimM: 150)
        XCTAssertEqual(tour.recordings.map(\.n), [1, 2])
        XCTAssertEqual(tour.recordings[1].startTs, 1200)
        XCTAssertEqual(tour.trimM, 150)
    }

    func testTourPayload_kindOverrideWins() {
        var flipped = candidate(id: 0, kind: .spoken)
        flipped.kindOverride = .ambient
        let tour = TourBuilder.tourPayload(candidates: [flipped], trimM: 0)
        XCTAssertEqual(tour.recordings[0].kind, "ambient")
    }

    func testValidation_overTwelveRecordingsFails() {
        let candidates = (0..<13).map { candidate(id: $0) }
        XCTAssertNotNil(TourBuilder.validationError(for: candidates))
        XCTAssertNil(TourBuilder.validationError(for: Array(candidates.prefix(12))))
    }

    func testValidation_totalBytesAndSecondsCaps() {
        let heavy = (0..<5).map { candidate(id: $0, bytes: 14_000_000) }   // 70MB
        XCTAssertNotNil(TourBuilder.validationError(for: heavy))
        let long = (0..<3).map { candidate(id: $0, seconds: 1000) }        // 3000s
        XCTAssertNotNil(TourBuilder.validationError(for: long))
    }

    func testValidation_excludedRecordingsDoNotCount() {
        let candidates = (0..<13).map { candidate(id: $0, included: $0 < 12) }
        XCTAssertNil(TourBuilder.validationError(for: candidates))
    }

    func testIncludedFileURLs_matchPayloadOrder() {
        let candidates = [candidate(id: 0), candidate(id: 1, included: false), candidate(id: 2)]
        let urls = TourBuilder.includedFileURLs(candidates: candidates)
        XCTAssertEqual(urls.map(\.lastPathComponent), ["0.m4a", "2.m4a"])
    }
}
```

- [ ] **Step 2: Run to verify failure** (`-only-testing:UnitTests/TourBuilderTests`)

- [ ] **Step 3: Implement `TourBuilder.swift`**

```swift
import Foundation

enum TourRecordingKind: String { case spoken, ambient }

struct TourRecordingCandidate: Identifiable, Equatable {
    let id: Int
    let startTs: Int
    let endTs: Int
    let duration: Double
    let sizeBytes: Int
    let transcription: String?
    let wpm: Double?
    let autoKind: TourRecordingKind
    var includeInShare: Bool
    var kindOverride: TourRecordingKind?
    var fileURL: URL?

    var effectiveKind: TourRecordingKind { kindOverride ?? autoKind }
}

enum TourBuilder {

    static let maxRecordings = 12
    static let maxFileBytes = 15 * 1024 * 1024
    static let maxTotalBytes = 60 * 1024 * 1024
    static let maxTotalSeconds: Double = 2700

    /// A deliberate recording is presumed to be a voice: only a transcription
    /// that reads as non-speech (too few words, or implausibly slow) files
    /// the recording as ambience. The walker can override either way.
    static func classify(transcription: String?, wpm: Double?) -> TourRecordingKind {
        guard let text = transcription?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return .spoken
        }
        let wordCount = text.split(whereSeparator: \.isWhitespace).count
        if wordCount < 8 { return .ambient }
        if let wpm, wpm < 30 { return .ambient }
        return .spoken
    }

    static func candidates(for walk: WalkInterface) -> [TourRecordingCandidate] {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let sorted = walk.voiceRecordings.sorted { $0.startDate < $1.startDate }
        return sorted.enumerated().compactMap { index, rec in
            guard !rec.fileRelativePath.isEmpty else { return nil }
            let url = docs.appendingPathComponent(rec.fileRelativePath)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? Int
            guard let size, size > 0, size <= maxFileBytes else { return nil }
            return TourRecordingCandidate(
                id: index,
                startTs: Int(rec.startDate.timeIntervalSince1970),
                endTs: Int(rec.endDate.timeIntervalSince1970),
                duration: rec.duration,
                sizeBytes: size,
                transcription: rec.transcription,
                wpm: rec.wordsPerMinute,
                autoKind: classify(transcription: rec.transcription, wpm: rec.wordsPerMinute),
                includeInShare: true,
                kindOverride: nil,
                fileURL: url
            )
        }
    }

    static func totals(of candidates: [TourRecordingCandidate]) -> (count: Int, bytes: Int, seconds: Double) {
        let included = candidates.filter(\.includeInShare)
        return (included.count,
                included.reduce(0) { $0 + $1.sizeBytes },
                included.reduce(0) { $0 + $1.duration })
    }

    static func validationError(for candidates: [TourRecordingCandidate]) -> String? {
        let (count, bytes, seconds) = totals(of: candidates)
        if count > maxRecordings { return "A walk page carries at most \(maxRecordings) recordings — leave some out." }
        if bytes > maxTotalBytes { return "Recordings total \(bytes / 1_048_576) MB — the page carries at most 60 MB." }
        if seconds > maxTotalSeconds { return "Recordings total \(Int(seconds / 60)) minutes — the page carries at most 45." }
        return nil
    }

    static func tourPayload(candidates: [TourRecordingCandidate], trimM: Int) -> SharePayload.Tour {
        let included = candidates.filter(\.includeInShare)
        let recordings = included.enumerated().map { index, c in
            SharePayload.TourRecording(
                n: index + 1,
                startTs: c.startTs,
                endTs: c.endTs,
                duration: c.duration,
                kind: c.effectiveKind.rawValue,
                transcription: nil,
                wpm: c.wpm,
                sizeBytes: c.sizeBytes
            )
        }
        return SharePayload.Tour(recordings: recordings, trimM: trimM)
    }

    static func includedFileURLs(candidates: [TourRecordingCandidate]) -> [URL] {
        candidates.filter(\.includeInShare).compactMap(\.fileURL)
    }
}
```

Note `transcription: nil` in the payload: the page never renders transcripts and omitting them keeps the POST body small (transcripts of a 45-minute walk approach the 2 MB payload cap).

- [ ] **Step 4: Run tests to verify pass**
- [ ] **Step 5: Commit** — `feat(share): TourBuilder classifies, caps, and renumbers recordings`

---

### Task 3: RouteTrimmer — private meters off both ends

**Files:**
- Create: `Pilgrim/Models/Share/RouteTrimmer.swift`
- Test: `UnitTests/RouteTrimmerTests.swift` (create)

**Interfaces:**
- Produces: `RouteTrimmer.trim(_ route: [SharePayload.RoutePoint], meters: Double) -> [SharePayload.RoutePoint]` — used by Task 6. Trims cumulative haversine distance from each end; always returns at least the innermost 2 points when the route is long enough to trim, and returns the route unchanged when `meters <= 0` or total distance `< 4 * meters` (a walk too short to trim meaningfully shares untrimmed — matches the spec's "trim is a courtesy, not a guarantee").

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class RouteTrimmerTests: XCTestCase {

    /// ~111m per 0.001 degrees latitude.
    private func straightRoute(points: Int, stepDegrees: Double = 0.001) -> [SharePayload.RoutePoint] {
        (0..<points).map { i in
            SharePayload.RoutePoint(lat: 35.0 + Double(i) * stepDegrees, lon: -105.0, alt: 2000, ts: 1000 + i * 30)
        }
    }

    func testTrimZeroReturnsRouteUnchanged() {
        let route = straightRoute(points: 10)
        XCTAssertEqual(RouteTrimmer.trim(route, meters: 0).count, 10)
    }

    func testTrimRemovesBothEnds() {
        let route = straightRoute(points: 20)   // ~2.1km total, 111m steps
        let trimmed = RouteTrimmer.trim(route, meters: 150)
        XCTAssertLessThan(trimmed.count, 20)
        XCTAssertGreaterThan(trimmed.first!.lat, route.first!.lat)
        XCTAssertLessThan(trimmed.last!.lat, route.last!.lat)
        XCTAssertGreaterThanOrEqual(trimmed.count, 2)
    }

    func testShortWalkSharesUntrimmed() {
        let route = straightRoute(points: 4)    // ~333m total < 4 * 150
        XCTAssertEqual(RouteTrimmer.trim(route, meters: 150).count, 4)
    }
}
```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement**

```swift
import Foundation

enum RouteTrimmer {

    /// Shaves `meters` of walked distance off each end of the route so a
    /// shared page never reveals a doorstep. Walks shorter than 4x the trim
    /// distance share untrimmed — mid-walk geometry is all they have.
    static func trim(_ route: [SharePayload.RoutePoint], meters: Double) -> [SharePayload.RoutePoint] {
        guard meters > 0, route.count > 3 else { return route }
        var cumulative: [Double] = [0]
        for i in 1..<route.count {
            cumulative.append(cumulative[i - 1] + haversineMeters(route[i - 1], route[i]))
        }
        let total = cumulative[route.count - 1]
        guard total >= meters * 4 else { return route }

        var start = 0
        while start < route.count - 1 && cumulative[start] < meters { start += 1 }
        var end = route.count - 1
        while end > 0 && total - cumulative[end] < meters { end -= 1 }
        guard end > start else { return route }
        return Array(route[start...end])
    }

    private static func haversineMeters(_ a: SharePayload.RoutePoint, _ b: SharePayload.RoutePoint) -> Double {
        let r = 6_371_000.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let la = a.lat * .pi / 180
        let lb = b.lat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2) + cos(la) * cos(lb) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(sqrt(h))
    }
}
```

- [ ] **Step 4: Run tests to verify pass**
- [ ] **Step 5: Commit** — `feat(share): RouteTrimmer keeps doorsteps off shared pages`

---

### Task 4: Hi-res tour photo export

**Files:**
- Create: `Pilgrim/Models/Share/TourPhotoExporter.swift`
- Test: `UnitTests/TourPhotoExporterTests.swift` (create — tests the quality ladder only; PHAsset loading is manual-verified)

**Interfaces:**
- Consumes: `PhotoCandidate` (`localIdentifier`, `capturedLat`, `capturedLng`, `capturedAt`) — same type the view model already holds.
- Produces (Task 8 uploads `jpegData`; Task 6 puts `meta` in the payload):

```swift
struct TourPhoto {
    let meta: SharePayload.Photo   // data == nil
    let jpegData: Data             // <= 2MB, uploaded via PUT
}

enum TourPhotoExporter {
    static func export(_ candidates: [PhotoCandidate]) async -> [TourPhoto]
    static func jpegDataUnder(cap: Int, image: UIImage) -> Data?   // quality ladder, testable
}
```

- [ ] **Step 1: Write the failing test**

```swift
import XCTest
@testable import Pilgrim

final class TourPhotoExporterTests: XCTestCase {

    private func noisyImage(side: CGFloat) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: side, height: side))
        return renderer.image { ctx in
            for x in stride(from: 0 as CGFloat, to: side, by: 8) {
                for y in stride(from: 0 as CGFloat, to: side, by: 8) {
                    UIColor(hue: .random(in: 0...1), saturation: 0.8, brightness: 0.9, alpha: 1).setFill()
                    ctx.fill(CGRect(x: x, y: y, width: 8, height: 8))
                }
            }
        }
    }

    func testLadderProducesDataUnderCap() throws {
        let data = try XCTUnwrap(TourPhotoExporter.jpegDataUnder(cap: 300_000, image: noisyImage(side: 1600)))
        XCTAssertLessThanOrEqual(data.count, 300_000)
        XCTAssertGreaterThan(data.count, 0)
    }

    func testLadderReturnsNilWhenImpossible() {
        XCTAssertNil(TourPhotoExporter.jpegDataUnder(cap: 10, image: noisyImage(side: 1600)))
    }
}
```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement**

```swift
import Photos
import UIKit

struct TourPhoto {
    let meta: SharePayload.Photo
    let jpegData: Data
}

enum TourPhotoExporter {

    static let maxBytes = 2 * 1024 * 1024
    static let targetPixels: CGFloat = 1600

    /// Interactive pages show photography full-bleed: export at 1600px
    /// (vs the classic page's 600px inline thumbnails), walking quality
    /// down until the file fits the worker's 2MB per-photo cap.
    static func jpegDataUnder(cap: Int, image: UIImage) -> Data? {
        for quality in [0.8, 0.65, 0.5, 0.35, 0.2] {
            if let data = image.jpegData(compressionQuality: quality), data.count <= cap {
                return data
            }
        }
        return nil
    }

    static func export(_ candidates: [PhotoCandidate]) async -> [TourPhoto] {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let photos = candidates.compactMap(loadOne)
                continuation.resume(returning: photos)
            }
        }
    }

    private static func loadOne(_ candidate: PhotoCandidate) -> TourPhoto? {
        let fetch = PHAsset.fetchAssets(withLocalIdentifiers: [candidate.localIdentifier], options: nil)
        guard let asset = fetch.firstObject else { return nil }

        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.isNetworkAccessAllowed = true
        options.isSynchronous = true
        options.resizeMode = .exact

        var result: TourPhoto?
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: targetPixels, height: targetPixels),
            contentMode: .aspectFit,
            options: options
        ) { image, _ in
            guard let image, let data = jpegDataUnder(cap: maxBytes, image: image) else { return }
            result = TourPhoto(
                meta: SharePayload.Photo(
                    lat: candidate.capturedLat,
                    lon: candidate.capturedLng,
                    ts: Int(candidate.capturedAt.timeIntervalSince1970),
                    data: nil
                ),
                jpegData: data
            )
        }
        return result
    }
}
```

Notes: `isNetworkAccessAllowed = true` (unlike the classic 600px path) because interactive shares are deliberate enough to wait for iCloud originals; the whole export runs on a background queue — never on main (resource-safety rule).

- [ ] **Step 4: Run tests to verify pass**
- [ ] **Step 5: Commit** — `feat(share): hi-res tour photo export with 2MB quality ladder`

---

### Task 5: ShareService media uploads — sequential PUTs with progress

**Files:**
- Modify: `Pilgrim/Models/Share/ShareService.swift`
- Test: `UnitTests/ShareMediaUploadTests.swift` (create)

**Interfaces:**
- Produces (Task 8 drives this):

```swift
extension ShareService {
    struct MediaProgress: Equatable {
        let completed: Int
        let total: Int
    }
    enum MediaKind: String { case audio, photos }

    /// Sequential by contract: photos MUST land in index order (enrich
    /// HEADs only the last one), and one-at-a-time keeps memory flat for
    /// 15MB audio files. Each item gets one retry. Returns the indices
    /// (1-based, per kind) that ultimately failed.
    static func uploadAllMedia(
        shareID: String,
        audioFiles: [URL],
        photos: [Data],
        progress: @escaping (MediaProgress) -> Void
    ) async -> [(kind: MediaKind, n: Int)]
}
```

Internally, one requestable unit — injectable for tests:

```swift
static func mediaUploadRequest(shareID: String, kind: MediaKind, n: Int, contentLength: Int) -> URLRequest
```

- [ ] **Step 1: Write the failing tests**

```swift
import XCTest
@testable import Pilgrim

final class ShareMediaUploadTests: XCTestCase {

    func testRequestShapeMatchesWorkerContract() {
        let req = ShareService.mediaUploadRequest(shareID: "abc123defg", kind: .audio, n: 3, contentLength: 12345)
        XCTAssertEqual(req.url?.absoluteString, "https://walk.pilgrimapp.org/api/share/abc123defg/audio/3")
        XCTAssertEqual(req.httpMethod, "PUT")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "audio/mp4")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Length"), "12345")
        XCTAssertNotNil(req.value(forHTTPHeaderField: "X-Device-Token"))
    }

    func testPhotoRequestUsesJpegContentType() {
        let req = ShareService.mediaUploadRequest(shareID: "abc123defg", kind: .photos, n: 1, contentLength: 500)
        XCTAssertEqual(req.url?.absoluteString, "https://walk.pilgrimapp.org/api/share/abc123defg/photos/1")
        XCTAssertEqual(req.value(forHTTPHeaderField: "Content-Type"), "image/jpeg")
    }
}
```

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement** in `ShareService.swift`:

```swift
// MARK: - Interactive media uploads

extension ShareService {

    struct MediaProgress: Equatable {
        let completed: Int
        let total: Int
    }

    enum MediaKind: String { case audio, photos }

    static func mediaUploadRequest(shareID: String, kind: MediaKind, n: Int, contentLength: Int) -> URLRequest {
        let url = URL(string: "\(baseURL)/api/share/\(shareID)/\(kind.rawValue)/\(n)")!
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue(kind == .audio ? "audio/mp4" : "image/jpeg", forHTTPHeaderField: "Content-Type")
        request.setValue("\(contentLength)", forHTTPHeaderField: "Content-Length")
        request.setValue(deviceToken(), forHTTPHeaderField: "X-Device-Token")
        request.timeoutInterval = 120
        return request
    }

    static func uploadAllMedia(
        shareID: String,
        audioFiles: [URL],
        photos: [Data],
        progress: @escaping (MediaProgress) -> Void
    ) async -> [(kind: MediaKind, n: Int)] {
        var failures: [(kind: MediaKind, n: Int)] = []
        let total = audioFiles.count + photos.count
        var completed = 0

        func report() { progress(MediaProgress(completed: completed, total: total)) }
        report()

        for (index, fileURL) in audioFiles.enumerated() {
            let ok = await putWithRetry(shareID: shareID, kind: .audio, n: index + 1) {
                try Data(contentsOf: fileURL)
            }
            if !ok { failures.append((.audio, index + 1)) }
            completed += 1
            report()
        }

        for (index, data) in photos.enumerated() {
            let ok = await putWithRetry(shareID: shareID, kind: .photos, n: index + 1) { data }
            if !ok { failures.append((.photos, index + 1)) }
            completed += 1
            report()
        }
        return failures
    }

    private static func putWithRetry(
        shareID: String,
        kind: MediaKind,
        n: Int,
        body: () throws -> Data
    ) async -> Bool {
        for attempt in 0..<2 {
            do {
                let data = try body()
                let request = mediaUploadRequest(shareID: shareID, kind: kind, n: n, contentLength: data.count)
                let (_, response) = try await URLSession.shared.upload(for: request, from: data)
                if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) {
                    return true
                }
            } catch {
                // fall through to retry
            }
            if attempt == 0 {
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
        return false
    }
}
```

Make the existing `private static let baseURL` and `private static func deviceToken()` accessible to the extension (same file — already fine).

- [ ] **Step 4: Run tests to verify pass**
- [ ] **Step 5: Commit** — `feat(share): sequential media PUTs with per-file retry and progress`

---

### Task 6: WalkShareViewModel — interactive state and payload integration

**Files:**
- Modify: `Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift`
- Test: `UnitTests/WalkShareInteractiveTests.swift` (create)

**Interfaces:**
- Consumes: Tasks 1–4 types.
- Produces (Task 7 renders these; Task 8 consumes `buildPayload` output + `tourPhotoData`):

```swift
// New published state on WalkShareViewModel:
@Published var interactiveEnabled = false
@Published var tourCandidates: [TourRecordingCandidate] = []
@Published var trimEnabled = true                    // 150m, default ON (spec)
var hasRecordings: Bool { !tourCandidates.isEmpty }
var tourValidationError: String? { interactiveEnabled ? TourBuilder.validationError(for: tourCandidates) : nil }
var tourTotalsLabel: String                          // "3 recordings · 8.2 MB · 14 min"
func toggleInclude(candidateID: Int)
func flipKind(candidateID: Int)
static let trimMeters = 150
```

- [ ] **Step 1: Write the failing tests**

Use `WalkDataFactory` (existing fixtures) to make a walk with voice recordings and pauses. If the factory lacks a recordings-capable maker, extend the test with the factory's existing `makeVoiceRecording`/`makeWalk` helpers (check `UnitTests/Support/` for the factory before writing; follow its patterns exactly).

```swift
import XCTest
@testable import Pilgrim

final class WalkShareInteractiveTests: XCTestCase {

    func testPayloadWithoutInteractiveHasNoTour() {
        let vm = WalkShareViewModel(walk: WalkDataFactory.makeWalk())
        let payload = vm.testBuildPayload()
        XCTAssertNil(payload.tour)
    }

    func testInteractivePayloadCarriesTourPausesAndTrim() {
        let walk = WalkDataFactory.makeWalk()   // extend factory: >= 1 recording, >= 1 pause, route > 1km
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

    func testFlipKindTogglesOverride() {
        let vm = WalkShareViewModel(walk: WalkDataFactory.makeWalk())
        vm.tourCandidates = [TourRecordingCandidate(id: 0, startTs: 1, endTs: 2, duration: 1, sizeBytes: 1, transcription: nil, wpm: nil, autoKind: .spoken, includeInShare: true, kindOverride: nil, fileURL: nil)]
        vm.flipKind(candidateID: 0)
        XCTAssertEqual(vm.tourCandidates[0].effectiveKind, .ambient)
        vm.flipKind(candidateID: 0)
        XCTAssertEqual(vm.tourCandidates[0].effectiveKind, .spoken)
    }
}
```

Expose `func testBuildPayload() -> SharePayload` as an internal passthrough to `buildPayload(placeStart:placeEnd:)` guarded by `#if DEBUG` if needed (tests import `@testable`, so plain `internal` suffices — just drop the `private` on `buildPayload` instead; simplest and honest).

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Implement in the view model**

```swift
@Published var interactiveEnabled = false
@Published var tourCandidates: [TourRecordingCandidate] = []
@Published var trimEnabled = true

static let trimMeters = 150

var hasRecordings: Bool { !tourCandidates.isEmpty }

var tourValidationError: String? {
    interactiveEnabled ? TourBuilder.validationError(for: tourCandidates) : nil
}

var tourTotalsLabel: String {
    let (count, bytes, seconds) = TourBuilder.totals(of: tourCandidates)
    guard count > 0 else { return "no recordings included" }
    let mb = Double(bytes) / 1_048_576
    return "\(count) recording\(count == 1 ? "" : "s") · \(String(format: "%.1f", mb)) MB · \(Int(seconds / 60)) min"
}

func prepareInteractive() {
    guard tourCandidates.isEmpty else { return }
    tourCandidates = TourBuilder.candidates(for: walk)
}

func toggleInclude(candidateID: Int) {
    guard let i = tourCandidates.firstIndex(where: { $0.id == candidateID }) else { return }
    tourCandidates[i].includeInShare.toggle()
}

func flipKind(candidateID: Int) {
    guard let i = tourCandidates.firstIndex(where: { $0.id == candidateID }) else { return }
    let current = tourCandidates[i].effectiveKind
    let flipped: TourRecordingKind = current == .spoken ? .ambient : .spoken
    tourCandidates[i].kindOverride = flipped == tourCandidates[i].autoKind ? nil : flipped
}
```

In `buildPayload` (now `internal`), after `downsampled`:

```swift
let interactive = interactiveEnabled
let trimM = interactive && trimEnabled ? Self.trimMeters : 0
let finalRoute = interactive && trimM > 0
    ? RouteTrimmer.trim(downsampled, meters: Double(trimM))
    : downsampled
```

Use `finalRoute` in the payload's `route:`. After constructing `payload`:

```swift
if interactive {
    payload.tour = TourBuilder.tourPayload(candidates: tourCandidates, trimM: trimM)
    payload.pauses = walk.pauses
        .filter { $0.endDate > $0.startDate }
        .prefix(200)
        .map { SharePayload.Pause(startTs: Int($0.startDate.timeIntervalSince1970), endTs: Int($0.endDate.timeIntervalSince1970)) }
}
```

Interactive photo metadata (classic path untouched): in the `photoPayload` closure, when `interactive`, return the pinned photos as data-less metadata (actual bytes travel via Task 8's export+PUT):

```swift
let photoPayload: [SharePayload.Photo]? = {
    guard includePhotos, hasPinnedPhotos else { return nil }
    if interactiveEnabled {
        return pinnedPhotos.prefix(20).map {
            SharePayload.Photo(lat: $0.capturedLat, lon: $0.capturedLng, ts: Int($0.capturedAt.timeIntervalSince1970), data: nil)
        }
    }
    return pinnedPhotos.compactMap { /* existing classic 600px base64 path unchanged */ }
}()
```

(Check `walk.pauses` element type for the exact date property names — `WalkPauseInterface` — and adjust `startDate/endDate` accessors to what the interface actually exposes before writing; the factory tests will catch a mismatch.)

- [ ] **Step 4: Run tests to verify pass**
- [ ] **Step 5: Commit** — `feat(share): view model builds interactive payloads — tour, pauses, trim, hi-res photo metadata`

---

### Task 7: The Interactive section in WalkShareView

**Files:**
- Modify: `Pilgrim/Scenes/WalkShare/WalkShareView.swift`
- Create: `Pilgrim/Scenes/WalkShare/InteractiveShareSection.swift` (new subview file — the share view is 493 lines; per project rule, new UI goes in its own struct file, not inline)

**Interfaces:**
- Consumes: Task 6's published state.
- Produces: UI only.

- [ ] **Step 1: Build `InteractiveShareSection`**

```swift
import SwiftUI

/// The Interactive toggle and its disclosure: recordings with per-item
/// include/kind controls, totals, trim. Lives in its own file to keep
/// WalkShareView under the type-body-length ceiling.
struct InteractiveShareSection: View {

    @ObservedObject var viewModel: WalkShareViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            Toggle(isOn: $viewModel.interactiveEnabled.animation()) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Interactive")
                        .font(Constants.Typography.body)
                    Text("Viewers walk your route on a living map — your recordings play where you made them, photos appear where you took them.")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: viewModel.interactiveEnabled) { _, on in
                if on { viewModel.prepareInteractive() }
            }

            if viewModel.interactiveEnabled {
                if viewModel.hasRecordings {
                    recordingsList
                    Text(viewModel.tourTotalsLabel)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("No recordings on this walk — the page will carry your route, photos, and moments.")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.secondary)
                }

                if let error = viewModel.tourValidationError {
                    Text(error)
                        .font(Constants.Typography.caption)
                        .foregroundColor(Color("rust"))
                }

                Toggle(isOn: $viewModel.trimEnabled) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Trim start & end")
                            .font(Constants.Typography.body)
                        Text("Keeps the first and last 150 m off the shared map.")
                            .font(Constants.Typography.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var recordingsList: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.xs) {
            ForEach(viewModel.tourCandidates) { candidate in
                TourRecordingRow(
                    candidate: candidate,
                    onToggleInclude: { viewModel.toggleInclude(candidateID: candidate.id) },
                    onFlipKind: { viewModel.flipKind(candidateID: candidate.id) }
                )
            }
        }
    }
}

private struct TourRecordingRow: View {

    let candidate: TourRecordingCandidate
    let onToggleInclude: () -> Void
    let onFlipKind: () -> Void

    private var durationLabel: String {
        let s = Int(candidate.duration)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    private var sizeLabel: String {
        String(format: "%.1f MB", Double(candidate.sizeBytes) / 1_048_576)
    }

    var body: some View {
        HStack(spacing: Constants.UI.Padding.small) {
            Button(action: onToggleInclude) {
                Image(systemName: candidate.includeInShare ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(candidate.includeInShare ? Color("moss") : .secondary)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text("Recording \(candidate.id + 1) · \(durationLabel)")
                    .font(Constants.Typography.body)
                Text(sizeLabel)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onFlipKind) {
                Text(candidate.effectiveKind == .spoken ? "voice" : "ambience")
                    .font(Constants.Typography.caption)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Capsule().strokeBorder(Color.secondary.opacity(0.4)))
            }
            .buttonStyle(.plain)
            .opacity(candidate.includeInShare ? 1 : 0.35)
        }
        .opacity(candidate.includeInShare ? 1 : 0.6)
    }
}
```

Adjust color names (`moss`, `rust`) to the asset-catalog names actually present (grep `Color("` in the project and match); same for `Constants.UI.Padding` members.

- [ ] **Step 2: Insert into WalkShareView**

In the main VStack after `statToggles` (before `journalSection`):

```swift
InteractiveShareSection(viewModel: viewModel)
```

with the same section framing the neighbors use (`sectionLabel("Walk with me")` above it if the design reads better with the label — match `statToggles`' visual rhythm).

- [ ] **Step 3: Build**

Run: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 4: Visual check** — simulator, demo mode (`--demo-mode` seeds walks with recordings): open a walk → share → flip Interactive on → recordings list shows with sizes; exclusion dims a row; kind chip flips voice ⇄ ambience; totals update; over-cap state shows the rust message and the share button disables (Task 8 wires the disable).

- [ ] **Step 5: Commit** — `feat(share): Interactive section — recordings disclosure, kind flip, trim`

---

### Task 8: Share orchestration — POST, then media, with progress

**Files:**
- Modify: `Pilgrim/Scenes/WalkShare/WalkShareViewModel.swift` (share flow + state)
- Modify: `Pilgrim/Scenes/WalkShare/WalkShareView.swift` (progress + partial-failure UI)
- Test: `UnitTests/WalkShareInteractiveTests.swift` (extend)

**Interfaces:**
- Consumes: Tasks 4–6.
- Produces: extended `ShareState`:

```swift
enum ShareState: Equatable {
    case idle
    case uploading                                  // POST phase (existing)
    case uploadingMedia(completed: Int, total: Int) // PUT phase
    case success(url: String)
    case partial(url: String, failedCount: Int)     // page live, some media missing
    case error(message: String)
}
```

- [ ] **Step 1: Write the failing test** — state math only (network stays untested here):

```swift
func testShareButtonDisabledWhenTourInvalid() {
    let vm = WalkShareViewModel(walk: WalkDataFactory.makeWalk())
    vm.interactiveEnabled = true
    vm.tourCandidates = (0..<13).map { i in
        TourRecordingCandidate(id: i, startTs: i, endTs: i + 1, duration: 60, sizeBytes: 1_000_000, transcription: nil, wpm: nil, autoKind: .spoken, includeInShare: true, kindOverride: nil, fileURL: nil)
    }
    XCTAssertNotNil(vm.tourValidationError)
    XCTAssertFalse(vm.canShare)
}
```

Add `var canShare: Bool { tourValidationError == nil }` to the view model.

- [ ] **Step 2: Run to verify failure**

- [ ] **Step 3: Extend `share()`**

```swift
func share() async {
    guard canShare else { return }
    shareState = .uploading

    let tourPhotos: [TourPhoto]
    if interactiveEnabled, includePhotos, hasPinnedPhotos {
        tourPhotos = await TourPhotoExporter.export(Array(pinnedPhotos.prefix(20)))
    } else {
        tourPhotos = []
    }

    let placeNames = await geocodeEndpoints()
    let payload = buildPayload(
        placeStart: placeNames.start,
        placeEnd: placeNames.end,
        tourPhotoMeta: tourPhotos.map(\.meta)
    )

    do {
        let result = try await ShareService.share(payload: payload)
        if let uuid = walk.uuid {
            ShareService.cacheShare(result, walkID: uuid, expiryDays: selectedExpiry.rawValue, expiryOption: selectedExpiry.cacheKey)
        }

        if interactiveEnabled {
            let audioFiles = TourBuilder.includedFileURLs(candidates: tourCandidates)
            let failures = await ShareService.uploadAllMedia(
                shareID: result.id,
                audioFiles: audioFiles,
                photos: tourPhotos.map(\.jpegData)
            ) { [weak self] progress in
                Task { @MainActor in
                    self?.shareState = .uploadingMedia(completed: progress.completed, total: progress.total)
                }
            }
            shareState = failures.isEmpty
                ? .success(url: result.url)
                : .partial(url: result.url, failedCount: failures.count)
        } else {
            shareState = .success(url: result.url)
        }
    } catch {
        shareState = .error(message: error.localizedDescription)
    }
}
```

`buildPayload` gains the `tourPhotoMeta: [SharePayload.Photo]` parameter (default `[]`) and uses it for the interactive photo branch from Task 6 — exported metadata and uploaded bytes must come from the SAME export, in the SAME order, so index `n` matches file `n` (the payload photo count is what authorizes each PUT index).

Photo/audio ordering invariants (worker contract): audio URLs are already payload-ordered by `TourBuilder`; `tourPhotos` order defines both `payload.photos` and the PUT sequence 1..N — never reorder between the two.

- [ ] **Step 4: Progress + partial UI in WalkShareView**

Where the view switches on `shareState`, add:
- `.uploadingMedia(let completed, let total)`: the existing uploading spinner with `Text("Carrying your recordings… \(completed)/\(total)")` (`Constants.Typography.caption`).
- `.partial(let url, let failedCount)`: the success layout plus a one-line note: `Text("\(failedCount) file\(failedCount == 1 ? "" : "s") didn't make it — those voices show as unavailable on the page.")` — the share URL still presents and copies.
- Share button `.disabled(!viewModel.canShare)` alongside its existing conditions.

- [ ] **Step 5: Run all new unit tests + build**

Run: `xcodebuild test ... -only-testing:UnitTests/SharePayloadTourTests -only-testing:UnitTests/TourBuilderTests -only-testing:UnitTests/RouteTrimmerTests -only-testing:UnitTests/TourPhotoExporterTests -only-testing:UnitTests/WalkShareInteractiveTests`
Expected: PASS.

- [ ] **Step 6: Commit** — `feat(share): interactive share flow — POST, sequential media, progress, partial results`

---

### Task 9: End-to-end verification and polish

**Files:**
- Modify: only what the checklist shakes out.

- [ ] **Step 1: Full unit test suite** — `xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro'` → all green.
- [ ] **Step 2: Full-repo SwiftLint** (per project memory: pre-commit only checks staged files) — `swiftlint --strict` clean, especially `type_body_length` on `WalkShareView` and `WalkShareViewModel`.
- [ ] **Step 3: Simulator end-to-end against production worker** — demo-mode walk with recordings → Interactive on → share → watch progress → open the returned URL in Safari: story page renders, voices play at their places (macOS Safari on the shared URL is acceptable here; the phone hardware pass is deferred by decision 2026-08-11).
- [ ] **Step 4: Privacy sanity** — confirm the payload omits transcriptions (`tour.recordings[].transcription == nil` in a captured request body), classic (non-interactive) shares are byte-identical to before (no `tour`, no `pauses` keys), and trim actually shortens the route in the page.
- [ ] **Step 5: Commit any fixes; update `docs/superpowers/plans/2026-08-11-walk-with-me-tour-ios.md` statuses; remove plan file only when shipped.**

---

## Deferred (explicitly out of scope)

- Real-device hardware pass (user decision 2026-08-11: after iOS work completes) — gesture unlock, Range playback, audible fades on hardware.
- Prime-all vs metadata preload: page behavior is frozen (prime-all); revisit only if TestFlight feedback flags cell-data cost.
- Localization of new strings (share screen is currently unlocalized inline English; follow suit).
- TestFlight build: needs explicit user approval per standing rule — never dispatch the workflow without it.
