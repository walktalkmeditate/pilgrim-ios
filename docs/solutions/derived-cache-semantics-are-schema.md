---
title: Changing how derived data is computed is a schema change, even when the stored shape doesn't move
date: 2026-08-25
category: data
module: Threads
problem_type: bug
component: cache
severity: high
applies_when:
  - "Changing a filter, threshold, or extraction rule that feeds a persisted, recomputable cache"
  - "Writing or reviewing a one-time backfill/re-arm sweep over stored derived data"
  - "Deciding whether a freshness check should use existence or something stronger"
tags: [schema-versioning, cache-invalidation, backfill, threads, transcript-context]
---

# Changing how derived data is computed is a schema change, even when the stored shape doesn't move

## Context
Build 108 shipped `ThemeExtractor` changed to filter themes down to nouns
only (dropping verb/adjective scaffolding like "was"/"can" and stoplisted
nouns like "thing"/"way"). `TranscriptContext.currentSchemaVersion` stayed
at 1 — the `Codable` shape hadn't changed, so nothing flagged it as a
version bump. But every previously-analyzed recording's stored themes were
now semantically stale: computed under the OLD extractor's rules. Nothing in
the read or backfill path checked when or how a stored context was derived,
only whether one existed:

- `TranscriptContextStore.hasContext` was a bare `FileManager.fileExists`.
- `loadAll()` decoded and returned every file on disk unconditionally.
- `ThreadsBackfill.runIfNeeded`'s per-recording skip was
  `where !store.hasContext(for: item.uuid)` — existence, not freshness.

The backfill's own re-arm mechanism (a new `completedKey`, forcing
`isComplete` false so the sweep runs again) was necessary but not
sufficient: the sweep ran, but its stale-item skip used existence, so it
skipped every already-analyzed recording — the exact recordings whose
themes needed to change. Stale verb/adjective themes and stoplisted nouns
resurfaced in the dossier, and the moon line burned its lunation budget
naming "was" as that month's top theme.

## Guidance
**If a change alters what a persisted derived-data file MEANS — not just
what shape it's stored in — that is a schema change.** Treat it identically
to a `Codable` shape change:

1. **Bump the schema version constant** even if no field was added, removed,
   or retyped. The version's job is "was this computed under today's rules,"
   not "does this decode."
2. **Make every freshness check version-aware, end to end** — not just the
   one obvious read path. In this codebase that meant three places, not one:
   - The primary reader (`context(for:matching:)`) — already checked
     `schemaVersion` before this bug; the one place that got it right from
     the start.
   - The bulk reader (`loadAll()`) — must filter to the current version, so
     every consumer (threads, dossier, suggestions) is blind to stale files
     automatically, with no per-caller opt-in.
   - The re-arm/backfill sweep's stale-item skip — must ask "is this
     current," not "does this exist." A bare existence check here is the
     dangerous one: it looks like a freshness guard, compiles fine, and
     silently reads as "already handled" for data that is stale by the very
     definition the schema bump just established.
3. **Existence checks that legitimately mean existence should stay.** Not
   every `hasContext`-style call is wrong — self-heal confirmation ("did my
   save actually land") and deletion assertions ("is it gone") genuinely
   want bare existence. Add a second, explicitly-named freshness check
   (`hasCurrentContext`) alongside the existence one rather than overloading
   one function's meaning contextually — a caller should not have to know
   which "mode" `hasContext` is in.
4. **A stale-version file that no longer has a live counterpart (the
   recording was deleted) still needs pruning**, not just invisibility. An
   orphan-sweep that only prunes among current-schema contexts (because it
   reads through the now-filtering `loadAll`) will never see a stale-version
   orphan at all — it needs its own unfiltered enumeration to find those
   files and delete them.

## Why This Matters
A cache whose freshness check is "does a file exist" cannot express "this
file is wrong" — only "this file is present or absent." Every re-arm
mechanism built on top of that (a renamed completion key, a reset flag) can
force the sweep to run again, but if the per-item skip inside that sweep
still asks the wrong question, the sweep runs and changes nothing for the
data that actually needs to change. The bug was invisible in code review
because the re-arm key rename LOOKED like the fix — `ThreadsBackfill`'s
history already had two prior renames (V1→V2, V2→V3) that were genuinely
sufficient, because those bugs were about the sweep never running at all,
not about a per-item skip that runs but chooses wrong. The third rename
looked identical in the diff and was not.

## When to Apply
- Any extractor, threshold, filter, or heuristic change to code that feeds
  a persisted, recomputable cache (this repo: `TranscriptContext`, but the
  principle generalizes to any local derived-data store).
- Writing or reviewing a backfill/re-arm sweep: check whether its
  "already handled" test can distinguish stale from current, not just
  present from absent.
- Deciding between adding a new freshness-aware method versus overloading
  an existing existence check — prefer the former; keep existence checks
  honestly named.

## Related
- `Pilgrim/Models/Threads/TranscriptContext.swift`
  (`currentSchemaVersion`)
- `Pilgrim/Models/Threads/TranscriptContextStore.swift` (`hasContext` vs.
  `hasCurrentContext`, `loadAll` vs. `loadAllIncludingStaleVersions`)
- `Pilgrim/Models/Threads/ThreadsBackfill.swift` (`completedKey`,
  `performLegacyHygiene`, `pruneStaleOrphans`)
- Build 108 field bug (confirmed on device): stale verb/adjective themes
  and stoplisted nouns surviving the V3 re-arm, moon line burning its
  budget on "was"
- `docs/solutions/corestore-queryattributes-uuid-string.md` — a sibling
  lesson from the same feature area about a freshness/correctness check
  that looked right but wasn't
