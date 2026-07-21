---
date: 2026-07-21
topic: svg-map-glyphs
---

# SVG Glyphs for Whispers and Cairns

## Summary

Replace the SF Symbol glyphs for whispers and cairns with bespoke vector art: one ephemeral wisp master tinted by each mood's guide color, and one cairn designed at its eternal fullness and derived into seven growing states of the same stones. The art reaches every surface that shows a specific whisper or cairn — map, add-a-stone sheet (showing the tier the cairn *becomes*), cairn detail view, and the whisper placement sheet's mood rows. Masters are generated in quiver.ai as SVG; iOS ships first and Android ports from the identical files. This document carries the complete generation prompt set.

---

## Problem Frame

Whispers and cairns are the two presences that carry Pilgrim's meaning on the map — traces walkers leave for each other. Today both render as generic system icons: a tinted `wind` symbol for every whisper, and the same `mountain.2` symbol for every cairn regardless of tier. A faint two-stone cairn and a 108-stone eternal cairn are indistinguishable at map glance, so the tier progression — the heart of the cairn system — is invisible where it matters most. The add-a-stone sheet and cairn detail view repeat the same generic mountain icon, and the whisper placement sheet shows no glyph at all: the moment a walker chooses which energy to leave, nothing shows them the presence they're about to place.

---

## Requirements

**Whisper glyph**
- R1. One wisp master: a single-color silhouette designed for runtime tinting, so each of the 8 mood guide colors renders the same form in its own energy.
- R2. The map's whisper annotation uses the tinted wisp, preserving the existing per-mood color cache behavior.
- R3. Each mood row in the whisper placement sheet shows the wisp tinted in that mood's guide color, so the walker sees exactly what will land on the map.

**Cairn glyphs**
- R4. One cairn visual system: the eternal cairn is designed once, and the seven tier states (faint → eternal) are derived from it so the same stones visibly accumulate across tiers.
- R5. The map's cairn annotation uses the tier's art; tier-appropriate size scaling is preserved so larger tiers still read larger.
- R6. When the add-a-stone sheet opens, it shows the cairn at the tier it *becomes* with the walker's stone added (current stone count + 1 run through the tier thresholds).
- R7. The cairn detail view shows the cairn's current tier art in place of the mountain symbol.

**Art and asset constraints**
- R8. SVG masters use the flat-vector subset importable by both Xcode asset catalogs and Android Vector Asset Studio: paths and groups only — no filters, masks, embedded text, or CSS.
- R9. All art uses fixed palette colors (never adaptive/dynamic colors), matching the map's existing fixed-hex convention.
- R10. Masters live canonically in this repo; pilgrim-android converts the same files via Vector Asset Studio at parity-port time.
- R11. Map sprites are rasterized at display size × screen scale before handing to Mapbox, so pins stay crisp.

**Prompt deliverable**
- R12. The generation prompt set below is the canonical starting point for producing the masters; refinements discovered during generation are recorded back into this document.

---

## Acceptance Examples

- AE1. **Covers R6.** Given a cairn with 6 stones (tier: small → medium boundary at 7), when the add-a-stone sheet opens, the medium-tier art is shown — the walker sees what their stone makes it become.
- AE2. **Covers R6.** Given a cairn with 8 stones (medium; next threshold at 12), when the add-a-stone sheet opens, the medium-tier art is shown — most stones deepen a tier rather than change it.
- AE3. **Covers R6.** Given no existing cairn (starting a new one), the faint-tier art is shown.
- AE4. **Covers R1, R3.** Given the walker taps the gratitude row in the whisper placement sheet, the wisp renders in gratitude's guide color in that row.
- AE5. **Covers R4, R5.** Given a faint cairn and an eternal cairn visible on the same map, they are distinguishable at a glance as the same species of cairn at different ages.

---

## Art Direction & Generation Prompts

**Feeling brief (from the source meditation):** Whispers are ephemeral — subtle as a breath, wearing the color of the energy they carry, exuding love and joy for all who come near. Cairns are permanence — solid stone, and as stones accumulate the pile grows ancient: a sage teaching by just being.

**Shared style directive** (prepend to every prompt):

> Flat vector illustration, wabi-sabi Japanese aesthetic with quiet sumi-e brush spirit. Simple, soft, slightly imperfect shapes. Clean closed paths only — no outlines, no text, no background (transparent), no filters, no masks, no complex gradients. Must read clearly at small icon size.

**Whisper wisp master** (one generation, monochrome for runtime tinting):

> A single ephemeral wisp of breath made visible — one soft continuous ribbon of air curling gently upward, with two or three delicate trailing strands that thin toward dissolving. Weightless, tender, and quietly joyful, like a whispered blessing hanging in the air for whoever comes near. Solid single color (pure black silhouette), flat vector, transparent background. The form must stay legible at 14 pixels.

**Cairn master** (one generation — the eternal cairn; tiers derived from it):

> A sacred stone cairn: many rounded, weathered river stones stacked in a gently tapering pile, ancient and patient. Muted grey stone tones with soft moss-green patches settled into the crevices, and a faint warm glow rising from within the pile's heart. A braided sacred straw rope (shimenawa) wraps the broad base stone, hung with two or three small white zigzag paper streamers (shide) — this cairn has been recognized as holy by those who passed. Wabi-sabi flat vector — each stone slightly imperfect, the stack organic rather than geometric. The cairn feels like a sage: still, wise, teaching by being. Transparent background.

**Tier derivation guide** (edit the master down, or use as variation prompts — same stones throughout):

| Tier | Stones (threshold) | State of the same cairn |
|---|---|---|
| Faint | 1–2 | One or two pale stones resting together — barely a mark, almost shy |
| Small | 3+ | The first true stack: three stones balanced, intention visible |
| Medium | 7+ | A stable little pile; the base stones settle and darken slightly |
| Large | 12+ | A fuller stack with a broadening base; first hint of moss in one crevice |
| Great | 42+ | Broad and grounded; moss established, edges weathered soft — aged by nature, no rope yet |
| Sacred | 77+ | Consecrated: the shimenawa rope and shide streamers appear; moss and lichen spread, stones darkened by years, the faintest glow beginning deep inside |
| Eternal | 108+ | The full master — rope kept, and the warm glow from within fully alive |

The final three tiers escalate deliberately: great is aged by nature, sacred is consecrated by people, eternal is lit from within. Tiers faint through great carry no rope — consecration arrives at sacred.

Exact hex values are matched to the app's fixed map palette at import time; the prompts speak in color language and the vector editor speaks in hexes.

**Generation log (2026-07-21):** the workflow inverted productively — the *sacred* generation (warm umber-stone palette, established moss greens, shimenawa + shide) surpassed the original grey-toned base master and became the style master; all other tiers were regenerated from it as the reference image, with eternal derived *upward* (fuller pile + fully alive glow). Import normalization applied mechanically: CSS classes inlined, aura discs removed below sacred, glow gradients made edge-transparent, canvases squared.

---

## Success Criteria

- A walker glancing at the map can tell a young cairn from an ancient one without tapping — the tier story is finally visible where it lives.
- The whisper and cairn surfaces feel like the meditation described them: ephemeral color-borne energy vs. accumulating stone permanence.
- The same 8 SVG masters (1 wisp + 7 cairn states) import cleanly into both the Xcode asset catalog and Android Vector Asset Studio with no per-platform redrawing.
- Planning can proceed without inventing product behavior — surfaces, becoming-tier logic, and art direction are all specified here.

---

## Scope Boundaries

- Waypoint icons, photo pins, and seek glyphs keep their current rendering — they are markers, not presences.
- Generic cairn iconography (walk-options toggle, elevation profile icon) keeps SF Symbols; only surfaces showing a *specific* cairn change.
- The journal's drawn scenery cairns keep their own style — the map art stands alone.
- No glyph animation in this pass.
- Android implementation is a separate parity port (`/ios-parity`), consuming the same masters; this document governs iOS.

---

## Key Decisions

- One wisp form tinted per mood, over eight distinct forms: color remains the sole carrier of each mood's energy, and the map stays quiet.
- One growing cairn derived into seven states, over seven independent artworks: continuity of the same stones is the sage metaphor, and it guarantees the tiers read as one cairn aging.
- The add-a-stone sheet shows the *becoming* tier, not the current one: the walker sees what their stone makes.
- Masters live in this repo as the parity anchor; Android converts at port time rather than maintaining a shared design repo.

---

## Dependencies / Assumptions

- quiver.ai output is assumed to be clean flat vector; if a generation uses unsupported SVG features, an SVGO pass or vector-editor re-export normalizes it (unverified until first generation).
- Xcode asset catalog SVG import and "Preserve Vector Data" behave as documented for these files — verify on first import, on device (simulator rendering has misled before).
- The Mapbox pipeline (UIImage-based annotation images, per-variant caching) is confirmed present in the codebase and unchanged by this work.

---

## Outstanding Questions

### Deferred to Planning

- [Affects R5][Technical] Whether tier size progression uses per-tier rasterization sizes, Mapbox `iconSize`, or both — and how it interacts with the existing `circleRadius` tier scaling.
- [Affects R1][Technical] Whether the wisp ships as a template asset (asset-catalog render-as-template) or is tinted at render time like the current symbol pipeline.
- [Affects R6, R7][Technical] How the sheets' layouts adapt to the art's aspect ratio versus the current square symbol slots.
- [Affects R12][Needs research] Whether quiver.ai supports seeded/consistent regeneration well enough to derive tiers by prompt variation, or whether tier derivation happens purely in a vector editor from the eternal master.
