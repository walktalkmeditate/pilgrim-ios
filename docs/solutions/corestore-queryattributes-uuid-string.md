---
title: CoreStore queryAttributes returns UUID columns as raw strings, not UUID
date: 2026-08-25
category: data
module: DataManager
problem_type: bug
component: query
severity: high
applies_when:
  - "Writing a `queryAttributes`/`NSDictionary` fetch that selects a UUID attribute"
  - "Decoding a snapshot query's `row[\"id\"]` (or any UUID column) into a Swift `UUID`"
tags: [corestore, queryattributes, uuid, coredata, silent-failure, threads]
---

# CoreStore queryAttributes returns UUID columns as raw strings, not UUID

## Context
Three DataManager snapshot functions (`voiceRecordingWalkIndex`,
`transcribedRecordingsSnapshot`, `voiceRecordingPaceIndex`) each cast a
`queryAttributes` row's `"id"` column with `row["id"] as? UUID`. The cast
never succeeds. Every one of these functions returned empty or dropped every
row, silently — no crash, no error, just an empty snapshot as if the store
held nothing. The bug shipped, survived two review rounds inside the same PR
(#66, feat/thought-threads-stage3), and was only caught when a snapshot's
row count didn't match seeded fixture data in a new test
(`test_transcribedRecordingsSnapshot_returnsTranscribedRecordings`,
9529fff) — the same cast bug had already been found and fixed once earlier
in the same PR for `voiceRecordingWalkIndex` (c1844c3), and still recurred
twice more.

## Guidance
CoreStore's `UUID: QueryableAttributeType` conformance declares
`cs_rawAttributeType = .stringAttributeType`. That means a `queryAttributes`
fetch — which returns raw `NSDictionary` rows straight from SQLite, bypassing
CoreData's managed-object attribute bridging — hands back the column as a
plain `String`, never a bridged `UUID`/`NSUUID`. `row["id"] as? UUID` is not
a defensive cast against a rare failure; it is a cast that can only ever
fail. It compiles clean, warns nothing, and returns `nil` for every row,
every time.

Never write `row["someUUIDColumn"] as? UUID`. Decode through one shared
helper instead:

```swift
static func rowUUID(_ raw: Any?) -> UUID? {
    (raw as? String).flatMap(UUID.init(uuidString:))
}
```

Every `queryAttributes` fetch that selects a UUID column in this codebase
(`DataManager+VoiceRecording.swift`, `DataManager+Query.swift`) must decode
that column through `rowUUID`, not a bare cast. Grep for `queryAttributes`
when reviewing or adding a new snapshot query, and check every `row["..."]`
line it feeds — a `Date`/`Double`/`String` cast in the same row is fine
(CoreStore round-trips those natively); a UUID column is the one that lies.

## Why This Matters
This class of bug is uniquely dangerous because it degrades gracefully into
looking correct: `try? dataStack.queryAttributes(...)` returns `[]` on a
genuine fetch failure AND `compactMap { row["id"] as? UUID ... }` returns
`[]` when every row's cast fails — both paths produce an empty array with no
distinguishing signal. A snapshot silently returning nothing reads as "no
data yet," not "broken," so it can ship, get reviewed twice, and still slip
through — nothing crashes, no test exercised real seeded rows against the
snapshot until 9529fff added one. The concrete cost here: `ThreadsBackfill`
depended on `transcribedRecordingsSnapshot`, so before this fix it swept
zero recordings on every device, unconditionally.

## When to Apply
- Any time you add a `queryAttributes` fetch (`NSDictionary.self` select)
  that includes a `UUID`-typed CoreStore attribute.
- Reviewing a PR that touches `DataManager+*.swift` snapshot/index
  functions.
- Debugging a snapshot, index, or count that reads as unexpectedly empty
  when the underlying CoreData rows clearly exist.

## Related
- `Pilgrim/Models/Data/DataManager+VoiceRecording.swift` (`rowUUID`,
  `transcribedRecordingsSnapshot`, `voiceRecordingPaceIndex`,
  `voiceRecordingWalkIndex`)
- `Pilgrim/Models/Data/DataManager+Query.swift` (`walkSensesSnapshot`)
- Commits c1844c3 and 9529fff (PR #66, feat/thought-threads-stage3) — the
  three-function fix wave
- `UnitTests/VoiceRecordingPersistenceTests.swift` — the seeded-row
  regression tests added alongside the fix
