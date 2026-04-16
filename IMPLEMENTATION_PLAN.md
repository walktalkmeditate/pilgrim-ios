# Photo Context for AI Prompts

## Context

The "Generate AI Prompts" feature builds a rich text prompt from walk data (GPS, duration, weather, transcriptions, waypoints, celestial data, intention) and presents it for the user to copy into ChatGPT or Claude. The prompts are specific to the walk but currently blind to what the walker SAW — they know where you went and how long, but not that you photographed a stone bridge, a moss-covered path, or a trail sign reading "1.5 miles."

Photo context bridges that gap. On-device Vision framework analysis runs on the user's pinned reliquary photos and produces structured metadata (scene tags, detected text, people count, animals, outdoor confirmation, dominant color). This metadata is formatted as a new section in the prompt, giving the external LLM enough visual context to generate dramatically more specific and personal reflection questions.

### Why this matters

Current prompt: "You walked 1.46 miles in overcast weather. How did you feel?"

With photo context: "You walked through a forest path, stopped at a stone bridge marked 'Public Footpath 1.5 miles,' and ended looking out over an open field. Your photos started focused on small details — moss and stone — and ended with wide landscapes. No one else appeared in your photos. What shifted in you during this solitary walk?"

## Architecture

### Vision analysis service

New file: `Pilgrim/Models/Vision/PhotoContextAnalyzer.swift`

A stateless service that takes a `PHAsset` (or `UIImage`) and returns a `PhotoContext` struct. Runs all Vision requests in parallel on a background queue.

**Requests (all on-device, no network):**
- `VNClassifyImageRequest` → top 5 tags above 0.3 confidence
- `VNRecognizeTextRequest` → detected text strings (filtered to ≤50 chars, no phone/email patterns)
- `VNDetectHumanRectanglesRequest` → people count (not identity)
- `VNRecognizeAnimalsRequest` → animal labels if present
- `VNDetectHorizonRequest` → outdoor confirmation + angle
- `VNGenerateAttentionBasedSaliencyImageRequest` → salient region (top/center/bottom × left/center/right)
- `CIAreaAverage` (Core Image) → dominant color as hex string

**Output struct:**
```swift
struct PhotoContext: Codable {
    let tags: [String]              // ["forest", "path", "moss"]
    let detectedText: [String]      // ["Public Footpath", "1.5 miles"]
    let people: Int                 // 0
    let animals: [String]           // ["dog"]
    let outdoor: Bool               // true
    let salientRegion: String       // "center", "top-left", etc.
    let dominantColor: String       // "#4A6741"
}
```

**Performance:** ~300-500ms per photo for all requests combined (parallel). For 5 photos: ~500ms total (pipeline parallelism across photos).

### Caching

Photo context is cached in `UserDefaults` keyed by `localIdentifier` (or a lightweight sidecar file). Avoids re-running Vision on every prompt generation.

**Cache key:** `photo_context_{localIdentifier_hash}`
**Cache format:** JSON-encoded `PhotoContext`
**Invalidation:** none needed — the photo doesn't change after pinning. If the user deletes and re-pins (different localIdentifier), the cache naturally misses.

UserDefaults is chosen over a CoreData entity because:
- No schema migration needed (V7 → V8 avoided)
- The data is derived (can be recomputed), not user-created
- Small payload (~200 bytes per photo)
- Fast lookup

### Narrative arc computation

New file: `Pilgrim/Models/Vision/PhotoNarrativeArc.swift`

Given an array of `(PhotoContext, capturedAt, distanceIntoWalk)` tuples (ordered chronologically), compute:

```swift
struct NarrativeArc {
    let attentionArc: String       // "detail_to_wide", "wide_to_detail", "mixed", "consistent"
    let solitude: String           // "alone", "with_others", "mixed"
    let recurringTheme: [String]   // tags that appear in ≥50% of photos
    let dominantColors: [String]   // ordered hex strings for visual mood strip
}
```

**Attention arc:** derived from salient region sequence. "center" + small salient area = detail shot. Wide salient area or "top" region = landscape. Track how this evolves across the photo sequence.

**Solitude:** if `people == 0` across all photos → "alone". If any photo has `people > 0` → "with_others" or "mixed".

**Recurring theme:** tags that appear in ≥50% of photos. "forest" in 4/5 photos → recurring. Tells the AI "this was a forest walk."

### Prompt integration

Modify: `Pilgrim/Models/Prompt/PromptAssembler.swift`

Add a new section between Waypoints and Transcriptions:

```
PHOTOS ALONG THE WALK
Photo 1 (0.3 mi in, 8:14 AM, near 42.87°N 8.51°W):
  Scene: forest, path, moss, stone
  Focal area: center (close-up detail)
  Text found: "Public Footpath", "1.5 miles"
  People: none
  Outdoor: yes

Photo 2 (0.8 mi in, 10:22 AM, near 42.88°N 8.52°W):
  Scene: bridge, river, stone, architecture
  Focal area: center-left
  People: none
  Outdoor: yes

Photo 3 (1.2 mi in, 10:31 AM, near 42.89°N 8.53°W):
  Scene: field, sky, grass, landscape
  Focal area: top-center (wide view)
  People: none
  Animals: dog
  Outdoor: yes

Visual narrative: Attention progressed from close-up detail (moss, stone)
to wider views (field, sky). A solitary walk through forest into open land.
Recurring theme: stone, outdoor.
Color progression: #4A6741 → #7B8E6F → #A8B8A0
```

This format matches the existing sections (Waypoints has GPS + timestamp + label, Transcriptions has timestamp + GPS + text). The AI receives structured visual context alongside everything else.

### ActivityContext extension

Modify: `Pilgrim/Models/Prompt/ActivityContext.swift`

Add:
```swift
struct PhotoContextEntry {
    let index: Int
    let distanceIntoWalk: String    // "0.3 mi in"
    let time: String                // "8:14 AM"
    let coordinate: String          // "42.87°N 8.51°W"
    let context: PhotoContext
}

// On ActivityContext:
var photoContexts: [PhotoContextEntry]
var narrativeArc: NarrativeArc?
```

### PromptListView changes

Modify: `Pilgrim/Scenes/Prompts/PromptListView.swift`

The view already receives `walk` and `transcriptions`. Add `photoCandidates: [PhotoCandidate]` parameter. In `buildActivityContext()`, run `PhotoContextAnalyzer` on each pinned candidate (lazy, cached), compute `NarrativeArc`, and populate the new fields on `ActivityContext`.

## Files to create

| Path | Purpose |
|---|---|
| `Pilgrim/Models/Vision/PhotoContextAnalyzer.swift` | Runs all Vision requests on a photo, returns PhotoContext |
| `Pilgrim/Models/Vision/PhotoNarrativeArc.swift` | Computes attention arc, solitude, theme from photo sequence |
| `UnitTests/PhotoContextAnalyzerTests.swift` | Tests for the analyzer (using synthetic test images) |
| `UnitTests/PhotoNarrativeArcTests.swift` | Tests for arc computation (pure function, no Vision dependency) |

## Files to modify

| Path | Change |
|---|---|
| `Pilgrim/Models/Prompt/ActivityContext.swift` | Add `photoContexts` + `narrativeArc` fields |
| `Pilgrim/Models/Prompt/PromptAssembler.swift` | Add photo context section to prompt output |
| `Pilgrim/Scenes/Prompts/PromptListView.swift` | Accept photoCandidates, run analysis in buildActivityContext |
| `Pilgrim/Scenes/WalkSummary/WalkSummaryView.swift` | Pass photoCandidates to PromptListView |
| `Pilgrim.xcodeproj/project.pbxproj` | Register new files |

## Implementation stages

### Stage 1 — Vision analyzer + cache
**Goal:** PhotoContextAnalyzer runs all 6 Vision requests + CIAreaAverage on a single photo, returns PhotoContext, caches in UserDefaults.

**Success criteria:**
- Analyzer produces correct tags for a test photo (outdoor scene with text)
- Cache hit returns instantly on second call
- ~300-500ms per photo on a real device
- All processing on-device, no network

**Tests:** Synthetic test image (solid color + drawn text) → verify tags array is non-empty, dominant color matches, detected text includes the drawn text.

### Stage 2 — Narrative arc + prompt integration
**Goal:** NarrativeArc computed from photo sequence. PromptAssembler includes photo context section. PromptListView passes photos through the pipeline.

**Success criteria:**
- Prompt output includes "PHOTOS ALONG THE WALK" section with per-photo details
- Narrative arc summary appears at the end of the section
- Empty photos (no reliquary) → section omitted entirely
- Prompt quality: pasting into Claude/ChatGPT produces noticeably more specific reflections

**Tests:** NarrativeArc pure-function tests (given N PhotoContexts, verify arc/solitude/theme). PromptAssembler test with mock photo contexts → verify section appears in output.

## Verification

**Manual QA:**
1. Pin 3-5 photos on a walk with varied scenes (trail, bridge, field)
2. Open walk summary → tap "Generate AI Prompts"
3. Verify the prompt includes photo context section with correct tags, text, coordinates
4. Copy prompt → paste in Claude → verify the reflection references specific photos
5. Test with a walk that has zero photos → verify no photo section in prompt
6. Test with a walk where all photos are dark/blurry → verify graceful handling (sparse tags)
7. Second prompt generation → verify cache hit (no delay)

**Performance:**
- First generation with 5 photos: ≤3s total (analysis + prompt building)
- Cached generation: ≤200ms
