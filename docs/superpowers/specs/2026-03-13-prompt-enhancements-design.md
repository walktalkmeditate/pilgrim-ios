# Prompt Enhancements Design

Enhance the AI prompt generation system with richer context, sharing options, and user customization.

## Features

### 1. Reverse Geocoding

Convert GPS coordinates to human-readable place names using `CLGeocoder`.

**Data source:** Existing route GPS samples — no new storage.

**Geocoding targets:**
- Start location (first route sample)
- End location (last route sample, only if > 500m from start)
- Midpoint (middle route sample, only if walk > 2km)

**Implementation:**
- `PromptListView.generatePrompts()` becomes async
- Geocodes 1–3 points sequentially (CLGeocoder rate limit: ~1 req/sec)
- Extracts neighborhood + city from `CLPlacemark`
- Passes `[PlaceContext]` to `PromptGenerator.generate()`

**New type:**
```swift
struct PlaceContext {
    let name: String
    let coordinate: (lat: Double, lon: Double)
    let role: PlaceRole // .start, .end, .midpoint
}

enum PlaceRole { case start, end, midpoint }
```

**Prompt output:**
```
**Location:** Started near Riverside Park, Manhattan → ended near Central Park West
```
Loop walk (start ≈ end):
```
**Location:** Near Riverside Park, Manhattan
```

**Offline behavior:** Best-effort. CLGeocoder may use cached data offline. If geocoding fails, the section is omitted — GPS coordinates on individual recordings still appear (local data, no network). No error state, no loading spinner that hangs.

**New PromptGenerator method:** `formatPlaceNames(_ places: [PlaceContext]) -> String?` — returns `nil` when empty.

---

### 2. Pace Context

Include walking pace and per-recording speed changes in prompt context.

**Data source:** `RouteDataSampleInterface.speed` (meters/second) on existing GPS samples.

**Computed metrics:**
- Average pace (min/km or min/mi based on locale)
- Pace range (slowest/fastest, excluding stops)
- Per-recording pace: average speed in 30-second window before and after each voice recording

**Filtering:** Samples with speed < 0.3 m/s treated as stationary, excluded from calculations.

**Prompt output:**
```
**Pace:** Average 12:30 min/km (range: 9:45–18:20)
[9:05 AM] Recording 1: pace slowed from 11:00 to 15:30 min/km
[9:12 AM] Recording 2: walking steadily at 12:00 min/km
```

**Graceful degradation:** Sparse GPS data (e.g., future battery-saver mode) produces simpler output — just average pace if < 10 samples, nothing if no speed data. Same `nil`-return pattern as other optional sections.

**New PromptGenerator method:** `formatPaceContext(routeData: [RouteDataSampleInterface], recordings: [RecordingContext]) -> String?`

---

### 3. Walk-to-Walk Threading

Include transcription snippets from recent walks so the AI can identify patterns across walks.

**Data source:** CoreStore query of recent walks with transcriptions. No new storage.

**Query:** Up to 3 most recent completed walks (before current walk's start date) that have at least one voice recording with a non-nil transcription.

```swift
From<Walk>()
    .orderBy(.descending(\._startDate))
    .where(\._startDate < currentWalk.startDate)
```

Filter to walks with transcribed recordings, take first 3.

**Truncation:** 200 characters per walk, cut at nearest word boundary, append ellipsis.

**Prompt output:**
```
**Recent Walk Context (for continuity):**

[Jun 12 – Riverside Park] "I keep thinking about how the river reminds me of home. There's something about water that..."

[Jun 10 – Central Park] "Today I noticed I was walking faster than usual. Maybe it's the anxiety about..."
```

Place name included if reverse geocoding is available for that walk (from its route data start point). Falls back to date only.

**No prior walks:** Section omitted.

**New PromptGenerator parameter:** `recentWalkSnippets: [WalkSnippet]`

```swift
struct WalkSnippet {
    let date: Date
    let placeName: String?
    let transcriptionPreview: String // truncated to ~200 chars
}
```

**New method:** `formatRecentWalks(_ snippets: [WalkSnippet]) -> String?`

---

### 4. Copy-to-Clipboard with AI Deep Links

Replace single Copy button behavior with progressive disclosure of AI app shortcuts.

**Layout:** Keep existing Copy + Share buttons side by side (unchanged). After tapping Copy:
1. Prompt text copies to clipboard immediately
2. Copy button shows "Copied!" with checkmark
3. Below the buttons, hint pills animate in: "Paste in your favorite AI" label with "ChatGPT" and "Claude" pill buttons
4. Pills auto-hide after ~8 seconds, Copy button resets

**Deep link behavior:**
- ChatGPT pill: `UIApplication.shared.open(URL(string: "https://chat.openai.com/")!)`
- Claude pill: `UIApplication.shared.open(URL(string: "https://claude.ai/new")!)`
- If app installed → opens app. If not → opens Safari.
- Prompt is already on clipboard — user pastes manually.

**Styling:**
- Pills use `parchmentSecondary` background, `stone` text, `Constants.Typography.caption` font
- Pill shape: `Capsule()` clip with horizontal padding
- Slide-in animation: `.transition(.move(edge: .bottom).combined(with: .opacity))`

**Share button:** Unchanged — still opens native `UIActivityViewController`.

**Files modified:** `Pilgrim/Scenes/Prompts/PromptDetailView.swift` only.

---

### 5. Custom Prompt Styles

Let users create up to 3 custom prompt styles with their own instruction.

**Storage:** `[CustomPromptStyle]` JSON-encoded in UserDefaults via `CustomPromptStyleStore`.

```swift
struct CustomPromptStyle: Codable, Identifiable {
    let id: UUID
    var title: String
    var icon: String        // SF Symbol name
    var instruction: String
}
```

```swift
final class CustomPromptStyleStore: ObservableObject {
    static let maxStyles = 3
    @Published var styles: [CustomPromptStyle]

    func save(_ style: CustomPromptStyle) { ... }
    func delete(_ style: CustomPromptStyle) { ... }
    func canAddMore: Bool { styles.count < Self.maxStyles }
}
```

**Prompt generation:** Custom styles use a generic preamble:
> "These are voice recordings captured during a walk, transcribed as spoken. They represent unfiltered thoughts, observations, and feelings that surfaced while moving."

The user's `instruction` field replaces the style-specific instruction block. All context sections (transcriptions, GPS, pace, meditations, metadata, place names, recent walks) are included identically to built-in styles.

**UI — Prompt list:**
- Built-in styles listed first (6 rows)
- Custom styles listed below with a section divider
- "Create Your Own" row at the bottom with "+" icon
- Soft counter below: "1 of 3" in caption style, fog color
- When 3/3 used: row shows "3 of 3 custom styles", add action disabled (no alert, just visually settled)
- Swipe-to-delete and tap-to-edit on custom style rows

**UI — Creation form (sheet):**
- Title text field
- SF Symbol picker: grid of ~20 curated icons (walking, writing, nature, thought-related)
- Instruction text editor (multi-line) with placeholder: "Tell the AI what to do with your walking thoughts..."
- "1 of 3" counter near save button
- Save and Cancel buttons

**Files:**
- New: `Pilgrim/Models/CustomPromptStyleStore.swift`
- New: `Pilgrim/Scenes/Prompts/CustomPromptEditorView.swift`
- Modified: `Pilgrim/Scenes/Prompts/PromptListView.swift`
- Modified: `Pilgrim/Models/PromptGenerator.swift` (add `generateCustom()` method)

---

### 6. Speaking Pace Metadata

Compute words-per-minute from WhisperKit transcription segments, store on VoiceRecording.

**Schema change:** PilgrimV3 adds `_wordsPerMinute: Value.Optional<Double>("wordsPerMinute")` to VoiceRecording entity.

**Migration:** PilgrimV2 → PilgrimV3:
- `.transformEntity` for VoiceRecording (new attribute)
- `.copyEntity` for all other entities (unchanged)

**Computation in TranscriptionService:** After `pipe.transcribe(audioPath:)`:

```swift
let segments = results.flatMap { $0.segments }
guard let first = segments.first, let last = segments.last,
      last.end > first.start else { return nil }
let wordCount = segments.flatMap { $0.words }.count
let durationMinutes = (last.end - first.start) / 60.0
let wpm = Double(wordCount) / durationMinutes
```

Stored via `DataManager.updateVoiceRecordingWPM(uuid:wpm:)`.

**Prompt format:** Appended to each recording's header line:
```
[9:05 AM] [~142 wpm, measured] "The birds are singing..."
[9:12 AM] [~85 wpm, slow/thoughtful] "Something shifted..."
```

**Qualitative labels:**
| WPM range | Label |
|-----------|-------|
| < 100 | slow/thoughtful |
| 100–140 | measured |
| 140–170 | conversational |
| > 170 | rapid/energized |

**Backwards compatibility:** Recordings transcribed before PilgrimV3 have `nil` WPM. Header line omits the pace tag — no backfill needed.

**Files modified:**
- New: `Pilgrim/Models/Data/DataModels/Versions/PilgrimV3.swift`
- Modified: `Pilgrim/Models/TranscriptionService.swift`
- Modified: `Pilgrim/Models/Data/DataManager.swift` (migration chain + updateWPM method)
- Modified: `Pilgrim/Models/Data/DataModels/VoiceRecording.swift` (type alias → PilgrimV3, interface property)
- Modified: `Pilgrim/Protocols/DataInterfaces/VoiceRecordingInterface.swift` (add `wordsPerMinute`)
- Modified: `Pilgrim/Models/PromptGenerator.swift` (format WPM in recording headers)

---

## Data Layer Summary

| Feature | Storage | Source |
|---------|---------|--------|
| Reverse geocoding | None | Route GPS + CLGeocoder (async, best-effort) |
| Pace context | None | Route speed samples |
| Walk-to-walk threading | None | CoreStore query of recent walks |
| Copy + deep links | None | UI-only |
| Custom prompt styles | UserDefaults (JSON) | User input |
| Speaking pace | PilgrimV3: `wordsPerMinute` on VoiceRecording | WhisperKit segments |

One schema migration (PilgrimV3) for one new field. Everything else is computed or UI.

---

## PromptGenerator.generate() — Updated Signature

```swift
static func generate(
    style: PromptStyle,
    recordings: [RecordingContext],
    meditations: [MeditationContext],
    duration: Double,
    distance: Double,
    startDate: Date,
    placeNames: [PlaceContext] = [],
    routeData: [RouteDataSampleInterface] = [],
    recentWalkSnippets: [WalkSnippet] = []
) -> GeneratedPrompt
```

All new parameters default to empty — existing call sites continue to work unchanged.

**buildPrompt() section order:**
1. Preamble (style-specific or generic for custom)
2. `---`
3. Context: metadata line
4. Location (if geocoded)
5. Pace (if route data available)
6. Walking Transcription (with WPM tags on headers)
7. Meditation Sessions (if any)
8. Recent Walk Context (if any)
9. `---`
10. Instruction (style-specific or custom)

---

## Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Geocoding timing | On-the-fly in PromptListView | No storage, always fresh, graceful offline fallback |
| Pace filtering | < 0.3 m/s = stationary | Excludes GPS drift at rest |
| Threading depth | 3 recent walks, 200 chars each | Small prompt footprint, enough for pattern detection |
| Deep link method | Universal links + clipboard | Always works, no undocumented URL schemes |
| Custom style storage | UserDefaults JSON | Lightweight, not walk data, no schema change |
| Custom style cap | 3 maximum | Keeps list manageable, surfaced via soft counter |
| WPM storage | Single Double on VoiceRecording | Word-level timestamps discarded after computation |
| WPM backfill | None | Enrichment, not critical — nil means no tag shown |
| Silence gaps | Removed | Meditation sessions already capture intentional silence |
