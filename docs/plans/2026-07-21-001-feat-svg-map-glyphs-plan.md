---
title: "feat: SVG glyphs for whispers and cairns"
type: feat
status: completed
date: 2026-07-21
origin: docs/brainstorms/2026-07-21-svg-map-glyphs-requirements.md
---

# feat: SVG glyphs for whispers and cairns

## Summary

Introduce the app's first vector assets: eight quiver.ai-generated SVG masters (one whisper wisp, seven cairn tier states derived from one eternal master) imported into the asset catalog, rasterized through a new `MapGlyphImageBuilder` that mirrors the existing `PhotoMarkerImageBuilder` pattern, and wired into the map's annotation pipeline plus three sheet surfaces. Becoming-tier logic (stone count + 1 through the existing thresholds) lands test-first alongside the add-a-stone sheet.

---

## Problem Frame

Whispers and cairns — the map's two presences — render as generic SF Symbols, so a two-stone cairn and a 108-stone eternal cairn are indistinguishable at glance, and the whisper placement sheet never shows the presence being placed. Full framing in the origin document.

---

## Requirements

Carried from origin (see origin: docs/brainstorms/2026-07-21-svg-map-glyphs-requirements.md):

**Whisper glyph**
- R1. One wisp master: single-color silhouette for runtime tinting across the 8 mood guide colors.
- R2. Map whisper annotation uses the tinted wisp, preserving per-mood color cache behavior.
- R3. Whisper placement sheet mood rows show the wisp in that mood's guide color.

**Cairn glyphs**
- R4. One cairn visual system: seven tier states derived from a single eternal master.
- R5. Map cairn annotation uses tier art with tier-appropriate size progression.
- R6. Add-a-stone sheet shows the tier the cairn *becomes* with the walker's stone (count + 1).
- R7. Cairn detail view shows the current tier's art.

**Art and asset constraints**
- R8. Masters use the flat-vector SVG subset importable by Xcode asset catalogs and Android Vector Asset Studio.
- R9. Fixed palette colors only — never adaptive (map fixed-hex convention).
- R10. Masters live canonically in this repo; Android converts at parity-port time.
- R11. Map sprites rasterized at display size × screen scale.

**Prompt deliverable**
- R12. Generation prompts in origin are canonical; refinements recorded back there.

**Origin acceptance examples:** AE1–AE3 (becoming tier, covers R6), AE4 (mood row tint, covers R1/R3), AE5 (tier distinguishability, covers R4/R5).

---

## Scope Boundaries

Carried from origin: waypoints, photo pins, seek glyphs, and generic cairn iconography (walk-options toggle, elevation profile) keep SF Symbols; journal scenery cairns keep their own style; no glyph animation; Android implementation is a separate parity port consuming the same masters.

### Deferred to Follow-Up Work

- Deleting dead `CairnTier.circleRadius` / `.opacity` (research confirmed nothing consumes them): tiny cleanup, separate commit or fold into a later tidy pass — not load-bearing for this plan.
- pilgrim-android port via `/ios-parity` after this ships.

---

## Context & Research

### Relevant Code and Patterns

- `Pilgrim/Views/PhotoMarkerImageBuilder.swift` + `UnitTests/PhotoMarkerImageBuilderTests.swift` — the image-builder pattern (UIGraphicsImageRenderer, `format.scale = UIScreen.main.scale`) and its test analog. The new builder mirrors both.
- `Pilgrim/Views/PilgrimMapView.swift:441–530` — annotation build (`buildPoints`), `cachedSymbolImage`/`renderSFSymbol`, `symbolImageCache` keyed `whisper-RRGGBB` / `cairn-<tier>`; cairn raster size is `12 + tier.rawValue` (12–18pt), `point.iconSize` always `1.0`.
- `Pilgrim/Models/Walk/MapManagement/CairnTier.swift` — `from(stoneCount:)` thresholds 3/7/12/42/77/108. `circleRadius`/`opacity` are dead code (verified: no consumers).
- `Pilgrim/Models/Whisper/WhisperDefinition.swift:23–34` — `WhisperCategory.borderColor`: fixed, non-adaptive UIColor literals for all 8 moods; already the map tint source via `ActiveWalkViewModel.swift:870`.
- `Pilgrim/Scenes/ActiveWalk/StonePlacementSheet.swift` — `existingCairnSection` uses *current* tier (36pt symbol); `newCairnSection` uses a generic dimmed symbol; receives `nearbyCairn: CachedCairn?` (stoneCount available; nil = new cairn).
- `Pilgrim/Models/Cairn/CairnDetailView.swift` — tier-driven `iconName`/`iconSize` (32–68pt)/`iconGradient`, kanji watermark, glow ring (great+), breathing (large+).
- `Pilgrim/Scenes/ActiveWalk/WhisperPlacementSheet.swift:78–132` — `categoryRow` has no glyph today; `Color(category.borderColor)` already tints stroke and play button.
- `Pilgrim/Support Files/Assets.xcassets` — no vector assets exist yet (all PNG triplets, `preserves-vector-representation: false` everywhere); raw-string asset names are the convention; only `close.imageset` is template-rendered.
- Fixed-hex convention for map art: `UIColor(hex:)` (`Pilgrim/Extensions/UIKit/UIColor.swift:5–12`) as used by `PilgrimMapView+SeekFog.swift:49–50`. Note `UIColor.moss`/`.stone` are adaptive — do not use for baked art colors.

### Institutional Learnings

- Simulator has misled on asset rendering before (alternate-icon feedback memory) — verify SVG catalog rendering on device.
- Map colors must be fixed hexes; adaptive colors invert in dark mode and become halos (shadow-color feedback + SeekFog comment).

### External References

- quiver.ai: Arrow 1.1 models, text-to-SVG with up to 4 reference images per request, natural-language edits, layered SVG output, SVG file/code export; free tier ~20 generations/week; optional MCP server at app.quiver.ai/mcp for in-session generation. (docs.quiver.ai)
- Xcode asset catalogs accept SVG with "Preserve Vector Data"; supported subset is static SVG (paths/groups/simple gradients; no filters, masks, CSS, text) — aligns with Android Vector Asset Studio's subset (R8).

---

## Key Technical Decisions

- **Mirror `PhotoMarkerImageBuilder`, don't extend `renderSFSymbol`**: a new `MapGlyphImageBuilder` owns catalog-asset rasterization + caching; the SF Symbol path stays untouched for waypoints/photo pins. Keeps the swap reversible and the builder unit-testable.
- **Wisp tint at rasterization time** via template rendering (`withTintColor`, `.alwaysTemplate` asset config), reusing the existing per-color cache-key scheme (`whisper-RRGGBB`). One monochrome asset, eight runtime tints — no per-mood assets.
- **Cairn art carries its own baked fixed-hex colors** (per R9, following the SeekFog `UIColor(hex:)` convention); rendered `.alwaysOriginal`, no runtime tint.
- **Size progression stays in the raster size** (`12 + tier.rawValue` baseline, tunable per-tier once art exists); `point.iconSize` remains `1.0`; `circleRadius` stays dead (deletion deferred).
- **Becoming tier computed in the sheet** as a private computed property (`CairnTier.from(stoneCount: (nearbyCairn?.stoneCount ?? 0) + 1)`), mirroring `CairnDetailView`'s existing `private var tier` pattern — no model or view-model changes.
- **Raw-string asset names remain the convention** (`whisperWisp`, `cairn-faint` … `cairn-eternal`). The Mapbox raster path is the builder's sole consumer — Mapbox requires a raster `UIImage`; the sheet, detail-view, and mood-row surfaces (U4/U5) reference the catalog assets directly via SwiftUI `Image` with native template tinting, so they depend on U1 only.
- **Quiver derivation workflow**: generate the eternal cairn master and wisp; derive tiers by re-prompting with the master as reference image (natural-language reduction edits), falling back to layer deletion in a vector editor (quiver outputs layered SVG). Refined prompts recorded back into origin (R12).
- **Square masters, view-side sizing**: all 8 SVGs are authored on a square canvas; SwiftUI call sites size them with `.resizable().scaledToFit()` + explicit frame (never `.font(size:)`, which is a no-op on asset images). Resolves origin's aspect-ratio question with one rule for every surface.
- **Accessibility carried explicitly**: SF Symbols provided free VoiceOver descriptions; the custom art must replace them — becoming-tier label in the add-a-stone sheet, tier label on the detail view's hero image, and the mood-row wisp marked decorative (the row already carries the mood name).

---

## Open Questions

### Resolved During Planning

- circleRadius interplay (origin deferred question): none — dead code, size progression designs fresh.
- Template asset vs render-time tint: render-time tint at rasterization, matching the existing cache pipeline.
- Quiver consistent derivation: reference-image + natural-language-edit workflow; vector-editor layer deletion as fallback.
- Sheet aspect-ratio adaptation (origin deferred question): square-canvas masters + `.resizable().scaledToFit()` with explicit frames at every SwiftUI call site.
- Tier-progression device verification data: cairns come only from live API fetches (never demo-seeded), so U3 verifies via a DEBUG-only mock `CachedCairn` injection into `GeoCacheService`.

### Deferred to Implementation

- Exact per-tier raster sizes and sheet layout tuning: depends on how the actual art reads at size — tune on device once U1 assets exist.
- Whether `CairnDetailView`'s kanji watermark/glow ring need repositioning over the new art: judge visually during U5.
- SVG normalization needs (SVGO pass or re-export): depends on quiver's actual output per file.

---

## Implementation Units

### U1. Generate and import the eight SVG masters

**Goal:** The wisp and seven cairn tier assets exist in the asset catalog as the app's first vector assets, verified renderable.

**Requirements:** R1, R4, R8, R9, R10, R12

**Dependencies:** None (art generation is the critical path — start here)

**Files:**
- Create: `Pilgrim/Support Files/Assets.xcassets/glyphs/whisperWisp.imageset` (SVG, preserve-vector-data, template rendering intent)
- Create: `Pilgrim/Support Files/Assets.xcassets/glyphs/cairn-faint.imageset` … `cairn-eternal.imageset` (7 imagesets, SVG, preserve-vector-data, original rendering intent)
- Modify: `docs/brainstorms/2026-07-21-svg-map-glyphs-requirements.md` (record refined prompts per R12)
- Test: `UnitTests/GlyphAssetTests.swift` (new; pbxproj registration per the synthetic-ID convention)

**Approach:**
- Generate in quiver.ai using the origin doc's prompts: wisp (monochrome), eternal cairn master, then tier derivations via reference-image + reduction edits (or layer deletion from the layered SVG). Author every master on a square canvas (see Key Technical Decisions).
- Normalize SVGs if Xcode rejects any feature (SVGO / vector-editor re-export); bake fixed hexes into cairn art.
- Asset catalog additions need no pbxproj changes (the catalog is already a member); only the test file needs registration.
- Legibility acceptance bar: the wisp rendered at 14px must be distinguishable from a plain dot, and adjacent cairn tiers at 12–18px must be tellable apart. If trailing strands or stone texture anti-alias away, the fallback is decided here — thicken the wisp's silhouette / derive a simplified silhouette-weight *map variant* of the cairn art from the same masters (sheets keep the detailed versions). One art system, two weights, only if the small sizes demand it.

**Execution note:** Art curation is human-in-the-loop — expect regeneration rounds; the user judges when the masters match the meditation brief. Optionally connect the quiver MCP (app.quiver.ai/mcp) to generate from the session.

**Test scenarios:**
- Happy path: `UIImage(named:)` returns non-nil for all 8 asset names (catches catalog/name wiring drift; loops over the canonical name list).
- Verification beyond tests: render each asset once on a real device (simulator has misled on asset behavior before).

**Verification:** All 8 assets resolve in a device build; wisp responds to tint; cairn tiers visibly progress when previewed side by side.

### U2. MapGlyphImageBuilder

**Goal:** A tested builder that turns a glyph request (wisp + tint, or cairn tier) into a correctly sized, cached `UIImage` for Mapbox.

**Requirements:** R1, R4, R11

**Dependencies:** U1 (asset names must exist; tests can use any bundled image until then, but sequencing after U1 keeps it honest)

**Files:**
- Create: `Pilgrim/Views/MapGlyphImageBuilder.swift` (pbxproj registration, app target)
- Test: `UnitTests/MapGlyphImageBuilderTests.swift` (pbxproj registration)

**Approach:**
- API shape: an image for `.whisper(tint: UIColor)` and `.cairn(tier: CairnTier)` at a point size; internally `UIImage(named:)` → `UIGraphicsImageRenderer` with `format.scale = UIScreen.main.scale` → cache keyed by the existing scheme (`whisper-RRGGBB`, `cairn-<tier>`).
- Scale via `image.draw(in: CGRect(origin: .zero, size: requestedSize))` — PhotoMarkerImageBuilder's technique. (`renderSFSymbol`'s `draw(at: .zero)` only works because SymbolConfiguration pre-sizes the symbol; an asset image drawn at `.zero` rasterizes at intrinsic size and fails the R11 dimension test.)
- Wisp path applies tint via template rendering; cairn path renders `.alwaysOriginal`.

**Execution note:** Test-first — the builder is pure and this is the unit where regressions would silently blur or mistint every pin.

**Patterns to follow:**
- `Pilgrim/Views/PhotoMarkerImageBuilder.swift` and its test file (structure, naming, rasterization pattern).
- `PilgrimMapView.symbolImageCache` (cache shape and key discipline).

**Test scenarios:**
- Happy path: builder returns non-nil images for the wisp with each of the 8 mood colors and for all 7 tiers.
- Happy path: output pixel dimensions equal requested point size × screen scale (R11).
- Edge case: repeated request with the same key returns the cached instance (no re-render).
- Edge case: distinct tiers produce distinct cache keys; distinct tints produce distinct keys.
- Error path: unknown/missing asset name degrades to nil without crashing (guards the U1→U2 name contract).

**Verification:** New tests green; no change yet to map behavior.

### U3. Map annotation wiring

**Goal:** Map whispers render the tinted wisp; map cairns render tier art with size progression; everything else untouched.

**Requirements:** R2, R5 (AE5)

**Dependencies:** U1, U2

**Files:**
- Modify: `Pilgrim/Views/PilgrimMapView.swift` (whisper and cairn branches of `buildPoints`)

**Approach:**
- Swap `cachedSymbolImage("wind", …)` and `cachedSymbolImage("mountain.2", …)` calls for `MapGlyphImageBuilder`, preserving cache-key formats and `PointAnnotation.image` naming so annotation managers refresh identically.
- Keep the `12 + tier.rawValue` size baseline; leave a single tuning point for per-tier sizes.
- Waypoint/photo branches and `renderSFSymbol` remain untouched.

**Test scenarios:**
- Test expectation: rendering behavior covered by U2's builder tests; this unit is call-site substitution. Covers AE5 via device verification: a faint and an eternal cairn on one map read as the same cairn at different ages.

**Verification:** On-device: whispers via `--demo-mode` (wisp colors match mood guide colors in light and dark map styles — fixed colors must not shift). Cairns are never demo-seeded (live API only), so verify tier progression via a DEBUG-only mock `CachedCairn` array injected into `GeoCacheService` — a faint and an eternal side by side, checked against **both light and dark Mapbox styles** (the baked fixed hexes lose the adaptive-`.moss` safety net; muted greys must not wash out on the dark basemap).

### U4. Becoming tier and the add-a-stone sheet

**Goal:** The add-a-stone sheet shows the cairn at the tier it becomes with the walker's stone; tier math is pinned by tests.

**Requirements:** R6 (AE1, AE2, AE3)

**Dependencies:** U1 (art); tier tests independent

**Files:**
- Modify: `Pilgrim/Scenes/ActiveWalk/StonePlacementSheet.swift`
- Test: `UnitTests/CairnTierTests.swift` (new; pbxproj registration)

**Approach:**
- Private computed `becomingTier` in the sheet: `CairnTier.from(stoneCount: (nearbyCairn?.stoneCount ?? 0) + 1)` — nil cairn yields faint (AE3) without special-casing.
- `existingCairnSection` and `newCairnSection` both show the becoming tier's asset in place of the mountain symbols, sized `.resizable().scaledToFit()` + frame (`.font(size:)` is a no-op on asset images).
- `newCairnSection`'s ghost treatment: the current `.foregroundColor(.stone.opacity(0.4))` tint no-ops on `.alwaysOriginal` art — use view-level `.opacity(0.4)` on the Image so "not yet placed" still reads differently from an existing cairn.
- Accessibility: the becoming-tier art is the only carrier of that state — give it `.accessibilityLabel` naming the tier it becomes (e.g. "Becomes a medium cairn").

**Execution note:** Test-first for the tier math (thresholds and becoming semantics) before touching the view.

**Test scenarios:**
- Covers AE1. Happy path: stone count 6 → becoming tier medium (crosses the 7 threshold).
- Covers AE2. Happy path: stone count 8 → becoming tier medium (no threshold crossed).
- Covers AE3. Edge case: no cairn (count 0 semantics) → becoming tier faint.
- Edge case: threshold boundaries — counts 2→small, 6→medium, 11→large, 41→great, 76→sacred, 107→eternal (each `count + 1` crossing), plus 107+1=108 exactly hits eternal.
- Happy path: `CairnTier.from(stoneCount:)` threshold table pinned directly (3/7/12/42/77/108) — first direct coverage of this function.

**Verification:** Sheet shows becoming art for existing and new cairns on device; tests green.

### U5. Cairn detail view and whisper mood rows

**Goal:** Tapping a cairn shows its tier's art; choosing a whisper mood shows the wisp in that mood's color.

**Requirements:** R3 (AE4), R7

**Dependencies:** U1

**Files:**
- Modify: `Pilgrim/Models/Cairn/CairnDetailView.swift`
- Modify: `Pilgrim/Scenes/ActiveWalk/WhisperPlacementSheet.swift`

**Approach:**
- Detail view: replace `Image(systemName: iconName)` with the tier asset; keep per-tier `iconSize` values but switch the sizing mechanism to `.resizable().scaledToFit().frame(width: iconSize, height: iconSize)` (`.font()` only sizes symbol images); keep glow ring, breathing, kanji watermark; drop `iconGradient` (art carries its own color). Give the hero image an `.accessibilityLabel` naming the tier.
- Mood rows: insert the wisp image between the play/stop button and the mood label in the existing `HStack`, template-rendered, tinted `Color(category.borderColor)`, ~20pt frame; mark it `.accessibilityHidden(true)` (the row already carries the mood name).

**Test scenarios:**
- Test expectation: none — pure view composition over already-tested assets and tint accessors. Covers AE4 via device verification: each mood row's wisp matches that mood's guide color.

**Verification:** Device pass over all 7 tiers in the detail view (glow/breathing intact) and all 8 mood rows; dark-mode check that nothing shifts.

---

## Sources & References

- Origin: docs/brainstorms/2026-07-21-svg-map-glyphs-requirements.md (requirements, acceptance examples, art prompts)
- Research: repo pattern scan 2026-07-21 (asset catalog state, dead circleRadius, fixed-vs-adaptive color audit)
