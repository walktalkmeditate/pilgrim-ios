# Oblique voice + prompt relevance — design

**Date:** 2026-08-27
**Status:** Design — awaiting user review
**Origin:** John Vervaeke, *Intelligence, Rationality, Wisdom and Spirituality* (transcript reviewed 2026-08-26). The talk's core thesis — *relevance realization*, the meta-problem of ignoring almost everything and zeroing in on what matters — is structurally what the Thought Threads dossier already does. This spec applies the talk's specific findings to a new prompt voice and to three defects in the existing prompts.

Related: [Thought Threads design](2026-08-22-thought-threads-design.md).

---

## Principles

These govern every decision below. They are derived from the source talk and are binding on implementation.

1. **Never instruct a reframe with no content attached.** Weber et al. 1981 gave people the nine-dot problem, waited until they were stuck, then told them "think outside the box, go beyond the square." It helped nobody. A *specific, concrete, structurally-grounded* alternative reading is a different thing and transfers fine — Vervaeke hands his audience the parity reframe for the mutilated chessboard outright and they have the aha. The ban is on contentless instruction, not on interpretation.

2. **Relevance must be supplied from outside similarity.** Goodman 1972: any two things share indefinitely many true properties (a lawn mower and a plum both have rounded edges, contain carbon, weigh more than a paperclip). An LLM asked to find connections will always find them, they will always sound insightful, and they will be arbitrary. Deterministic on-device computation is what supplies the relevance criterion; the model may interpret those invariants and may not invent new ones.

3. **Two layers, split by capability.** Layer 1 (on-device, deterministic) does *relevance realization* — what is actually invariant across this walker's history. Layer 2 (the model) does *aspectualization* — what frame that invariant reveals. Neither can do the other's job: the model has no access to history, and the device cannot see-as.

4. **Every heuristic has a matching cost.** The no-free-lunch theorem is formally proved: a heuristic that improves performance on some distribution degrades it by an equal area elsewhere. Each sense and each directive is a heuristic. Firing rate measures only the upside.

5. **Rules do not specify their own conditions of application.** "Be kind" applies one way to a puppy, another to an adult child, another to a partner at a funeral; fixing that with more rules gives infinite regress. The response contract is a rule pile at up to 7 lines on a rich walk. **Accretion budget: any change that grows the contract must justify the slot.** This spec adds exactly one contract line (Workstream 2) and removes one always-on firing rule (Workstream 4).

6. **Chunking bounds what is held.** Working memory is ~4 items. `DossierSenses.lineCap = 3` already respects this; `Unchanged:` inherits the same cap.

---

## Workstream 1 — Oblique

A seventh `PromptStyle` that reads what has **not** moved across the walker's history, and names the frame the walker has been looking *through* rather than *at*.

### Why this voice can exist at all

Vervaeke's mechanism for escaping a bad frame is the **notice-invariance heuristic** (Kaplan & Simon 1990): find what stayed the same across your failed attempts, and change that. He then names why nobody applies it:

> in order to apply it, you have to keep good track of your failures. And you have to be really willing to look at them very carefully. You don't like to do that. I don't like to do that.

Thought Threads *is* that record — the same person returning to the same unresolved thing, across weeks, in their own voice, with the linguistic texture of each return preserved. No journal, no chat session, and no wearable holds this. Oblique is the payoff for having built Threads.

### Division of labour

**Layer 1 — deterministic, on-device, enters the prompt as context:**

```
**Unchanged:**
'father' and 'money' have appeared in 4 of 4 walks together, never apart.
'work' has returned across 5 walks; salience steady, marker profile flat.
Every walk where 'money' appears is obligation-dominant ('should' ×14 avg).
```

**Layer 2 — the model, what the walker reads:**

> *You've walked with your father five times this month. Money came too, every single time — you have never once set out with one and left the other at home. And both arrive the same way, as things owed.*
>
> *Four of these walks you framed as being about money. It may be that money was never the subject.*

### Architecture

New file `Pilgrim/Models/Threads/DossierSensesInvariance.swift`, extending `DossierSenses` exactly as `DossierSensesTracks.swift` does. New entry point `DossierSenses.invarianceLines(input:) -> [String]`, parallel to `lines(input:)`, under the same binding purity contract: no `DataManager`, no `CoreStore`, no singleton access, and `Date()` is never called — time arrives as data.

`DossierSenses.Input` gains one field:

```swift
let historicalContexts: [TranscriptContext]
```

wired from the fetch `ThreadsDossierBuilder` **already performs** to feed `ThreadsDossierFormatter.dossier(allContexts:)`. This is a widened hand-off, not a new query. No new build-time fetch cost.

`ActivityContext` gains `var unchangedBlock: String?`, following the existing `var threadsDossier: String?` pattern (set post-construction by the builder).

**Critical constraint:** `PromptGenerator.generateAll` maps one `ActivityContext` across `PromptStyle.allCases`, and `resolvedDerivations` computes language detection and directives once for all styles. PR #65's perf wave established this single-pass property. Therefore `unchangedBlock` is **built once** with the rest of the dossier and merely *emitted* by `PromptAssembler` when the voice requests it. Per-voice variation happens at assembly time, never at dossier-build time.

`PromptStyle` gains `case oblique` — title "Oblique", description "What has not moved". Icon chosen at implementation against the rendered picker; candidates `arrow.trianglehead.branch`, `circle.dotted`, `eyeglasses`.

### The four shipping signals

All thresholds below are **starting values, subject to revision at the field gate**, following the precedent of `ThemeExtractor.minimumMentions` and the `questionDensity` cut. Priority order is declaration order in the `Invariant` enum, matching the `Sense.allCases` convention. Cap 3 lines.

| # | Signal | Fires when | Inputs |
|---|---|---|---|
| 1 | **Fused themes** | Two themes' walk-sets are identical or one nests in the other, across ≥3 shared walks, and the nested set has ≥3 members | `threads` (existing) |
| 2 | **Unmoved return** | ≥3 appearances, `salienceDirection == .steady`, and marker profile variance below threshold across appearances | `threads` + `historicalContexts` (new) |
| 3 | **Frame constancy** | One `ModalFamily` is dominant in every walk where the theme appears, across ≥3 walks | `threads` + `historicalContexts` (new) |
| 4 | **Place-frame lock** | Same theme within the same 150m cluster (`placeClusterRadius`) across ≥3 walks | `threads` + `fixes` (existing) |

Feasibility is confirmed: `ThreadAppearance` carries `recordingUUID`, `walkUUID`, `date`, `mentionCount`, and `salience`, so both the marker lookup (`historicalContexts` keyed by `recordingUUID`) and the place lookup (`fixes[recordingUUID]`) resolve. `ThreadsDossierBuilder.resolveFixes` already takes `threads:` and populates fixes for thread appearances, not just current recordings.

Signal 2's "marker profile variance" is defined as: coefficient of variation across appearances of absolutist rate, first-person rate, and sentiment, **each ≤ 0.20** (starting value), computed only over appearances whose context clears `ThreadsDossierFormatter.densityFloorWords` (100). At least 3 appearances must clear that floor. Appearances below it are excluded, not counted as flat — a short recording is not evidence of sameness. Sentiment CV is computed on the shifted range `sentiment + 1.0` to keep the denominator away from zero, since NLTagger sentiment spans −1…1 and a mean near zero would make raw CV explode.

Signal 3 reuses `MarkerLexicons.ModalFamily` (`possibility`, `obligation`, `counterfactual`, `tentative`, `intention`, `desire`) and the existing per-context `markers.modalCounts`. Dominance is per-walk mode, mirroring the `weatherWeave` majority→mode fix from PR #71 that killed the cloud tautologies.

**Held dark behind a flag** — `DossierSensesInvariance.pendingFieldGate = true`, mirroring `ThreadIntentionSuggestions.pendingFieldGate`:

| # | Signal | Fires when |
|---|---|---|
| 5 | **Unarrived intention** | An intention was set around a lemma on ≥3 walks and that lemma's thread is still `.steady` |

This is the most confronting line the app could produce — it says, in effect, *you have deliberately tried and nothing moved*. The engine ships with tests; the flag flips only after the field gate judges it on real history.

### Availability

Oblique requires **both**:
- ≥5 walks with transcribed recordings (history depth), and
- transcribed speech on the **current** walk

The second gate follows from the architecture: `ThreadsDossierFormatter.dossier` returns `nil` when `currentRecordings.isEmpty`, so a silent walk produces no dossier and therefore no `Unchanged:` block. History-only Oblique on a silent walk is a **deferred open question** (§Deferred), not a v1 feature.

In the picker Oblique is **visible but unselectable** until both gates pass, dimmed, with the copy:

> **Oblique** — *Still listening. A few more walks with your voice.*

"Still listening" is true for either failing gate — insufficient history, or no voice on this walk — so one string covers both without lying. It reads as the voice needing to hear more, not as a level to grind, which keeps it clear of the streak-pressure mechanics the app deliberately refuses.

If `hasInsight` is false (no invariant fires despite gates passing), Oblique remains selectable and the assembler omits the `Unchanged:` block; the voice then reads the walk without invariance material. This is the one case where Oblique degrades rather than hides, because the gates already promised availability.

### Voice text

**Preamble (`hasSpeech: true`):**

> This walker keeps a record. Across many walks they have returned, without planning to, to the same few things. What follows includes what has *not* changed across those returns — patterns in their own language that they cannot see, because these are the terms they think in rather than the terms they think about.

**Instruction (`hasSpeech: true`):**

> Work from the invariants named under **Unchanged**. Name what the walker has been treating as fixed — the assumption they have been looking through rather than at — and offer one specific alternative reading of that structure. Be concrete about the shape, not about what it means for their life.

**Response constraints (4 lines):**

1. Build only on the invariants named under **Unchanged** — never assert a pattern that block does not show.
2. Name one thing. An insight that can be carried is single, not a list.
3. Offer a specific alternative reading of the structure; never a contentless instruction to reframe. Do not write "perhaps consider", "try seeing", "from another perspective", or "outside the box".
4. End on the observation. Do not resolve it and do not prescribe an action — the walker does that part.

`hasSpeech: false` variants exist for protocol conformance and are unreachable given the availability gates; they return the `hasSpeech: true` text rather than dead placeholder prose.

### Block placement

Per the approved context-scope decision, Oblique receives the **full** dossier with `Unchanged:` **hoisted** above the context dossier, plus a re-anchor in the closing instruction. Since input cannot be narrowed, the output constraint carries the weight omission would have — constraint 2 above is load-bearing, not stylistic — and the sandwich uses recency to do what deletion would otherwise do.

---

## Workstream 2 — Interpretive keys

**Problem.** The dossier ships rich signals raw and the model guesses. `ThreadsDossierFormatter.markerLine` emits absolutist and first-person percentages; `modalLeanLine` emits `modal lean: obligation — 'should' ×31 (your usual ~8 per walk)`. A model's default read of "should ×31" is *this person is being hard on themselves*. The correct read is entirely different: obligation names the **shape of the frame they were thinking inside**.

**Fix.** One line added to `PromptAssembler.responseContract`, in the threads-dossier branch alongside the existing clinical-language guard:

> Read the absolutist-word share as how fixed the walker's framing was, and self-focus as how far they placed themselves at the centre of it. Read the modal lean as the frame the walker was working inside — obligation means the frame constrained them, counterfactual means they were already replaying alternatives, possibility and tentative mean it was still open, intention means they had settled on a course, and desire means they were naming a want rather than a plan. None of these has a fixed meaning; read each through this walk's intention and practice.

**Emitted per clause, not per dossier — corrected at review, 2026-08-27.** The first draft fired the whole key whenever a dossier was present. But `markerLine` prints "Markers unavailable (non-English recording)" when the recording has no `MarkerPack`, prints raw counts rather than shares below `densityFloorWords` (100), and `modalLeanLine` is silent unless it clears three thresholds — so the key routinely taught a taxonomy the dossier had withheld, handing the model vocabulary with no referent. `responseContract` therefore takes the dossier **text** (`threadsDossier: String?`) rather than a `Bool`, and emits only the clauses whose referents were printed: the share clause when shares appear, a bare-tally variant when only raw counts do, the modal clause only when a modal lean was printed, and no interpretive line at all when the dossier withheld everything. The clinical guard stays unconditional on the dossier's presence — it is the safety line. Still at most one interpretive line, so the accretion budget is unchanged.

The probes match `ThreadsDossierFormatter`'s own phrasings. That coupling is pinned by a test that runs the real formatter, so a phrasing change fails a test rather than silently suppressing the key on every walk.

The labels ("absolutist-word share", "self-focus") match what `ThreadsDossierFormatter` actually prints, not a paraphrase of it. The key names all six `MarkerLexicons.ModalFamily` cases — `possibility`, `obligation`, `counterfactual`, `tentative`, `intention`, `desire` — not a subset: naming only four invites the model to back-fit an unnamed family (`intention`, `desire`) onto the nearest named one, and `desire` in particular is high-frequency in spoken reflection ("want", "need", "wish"), so an unnamed reading of it would surface often.

The closing clause is Fodor's point: "it will be windy tomorrow" holds its truth while its relevance shifts entirely depending on whether the walker is sailing, flying a kite, or staying in. A first-person spike on a grief walk and on a planning walk are not the same fact.

**Cost.** +1 contract line, zero computation, applies to every dossier-carrying voice. This is the spec's one accretion; Workstream 4 removes an always-on firing rule to partly offset it. Justified because it converts three already-shipping raw signals into readable ones.

The existing clinical-language guard is **retained unchanged** — it is the safety line, and the new line is an interpretive one.

---

## Workstream 3 — Goodman fix on Reflective

**Problem.** `WalkPromptVoices.swift` `ReflectiveVoice.instruction(hasSpeech: true)` asks:

> What connections do you see between the different moments? [...] What contradictions or tensions are present?

Both are unbounded. Per Principle 2 the model will always find connections and will manufacture tension when asked for it, on walks where none exists.

**Fix.** Bind both to the walk's own evidence. Revised instruction:

> Please analyze these walking reflections for patterns, recurring themes, and emotional undercurrents. Where the walk's own record supports it — the stated intention, a word that recurs, a shift in pace — name what connects the moments. Where it does not, say less rather than reaching. Note any genuine tension the record shows, and do not manufacture one. Offer observations that help me understand myself better.

The `hasSpeech: false` variant gets the parallel treatment for its "What patterns do you see?" clause.

**"or marker profile" dropped at review, 2026-08-27.** The first draft's enumeration named the marker profile as licensed evidence. But the threads dossier reaches the prompt only when `UserPreferences.threadsAfterWalks` is on, and `instruction(hasSpeech:)` — unlike `responseContract` — has no way to know whether it did. The enumeration must name only evidence every spoken walk actually carries; the alternative is widening the `PromptVoice` protocol signature, which is a larger call than this fix warrants.

**Cost.** No contract lines. Prose-only change to one voice.

---

## Workstream 4 — `firstVersusLast` gating

**Problem.** In `AttentionDirectives`:

```swift
private static func firstVersusLast(_ context: ActivityContext) -> String? {
    guard context.recordings.count >= 2 else { return nil }
    return "Compare the first recording with the last — measure what changed in the walker between them."
}
```

Unconditional on ≥2 recordings, so it fires on nearly every spoken walk, and it **presupposes its conclusion**. Told to measure what changed, the model finds change — including on walks where nothing did. This is the same defect that killed `questionDensity` at the 2026-08-25 gate: it fires plausibly and is wrong.

**Fix.** Gate on a delta actually reachable from `ActivityContext`.

**Correction (found while planning, 2026-08-27):** an earlier draft of this section named sentiment and absolutist-rate deltas. Those are **not reachable** — `ActivityContext` carries no structured marker data, only `threadsDossier` as a pre-formatted string. Computing them inside `AttentionDirectives` would mean fresh `MarkerAnalyzer` passes per recording, undoing PR #65's single-NLP-pass work. The gate below uses only data already on the context plus two bounded lemma passes.

Fire only when at least one clears its threshold between the **first** and **last** recording:

- **Pace:** `wordsPerMinute` delta ≥ 15% relative (`paceShiftThreshold`). Free — `RecordingContext.wordsPerMinute` is already populated. Skipped when either value is `nil`, and when either recording holds fewer than 25 words (`minimumWordsToJudgePace`).

  **Word floor added at review, 2026-08-27.** The first draft gated pace on the relative delta alone. A short opening note ("Setting out heavy") has a `wordsPerMinute` fixed by the rounding of its own start and end timestamps, so a 15% relative change is trivially cleared and the directive fired on noise. The floor mirrors the subject branch's shape — a floor on each side, sized so the signal is measurable at all. At any plausible speaking rate, 25 words means at least ten seconds of continuous speech.

- **Subject:** overlap coefficient of content-lemma sets (`intersection.count / min(firstLemmas.count, lastLemmas.count)`) ≤ 0.20 (`subjectOverlapCeiling`) — they are no longer talking about the same thing. Costs exactly two `TranscriptNLP.contentLemmas(in:)` passes (first and last recording only, never all N). Requires both recordings to yield ≥ 12 content lemmas (`minimumLemmasToJudgeSubject`), and the longer set to be no more than 3× the shorter (`subjectLengthRatioCeiling`).

  **Not Jaccard.** An earlier draft of this workstream specified Jaccard similarity (`intersection / union`). Jaccard collapses to `|smaller| / |larger|` whenever one lemma set is a subset of the other, which is exactly the shape of a long opening reflection followed by a short closing note on the *same* subject: ~32 unique lemmas in the opening, a 6-lemma closing note drawn entirely from that same vocabulary, Jaccard ≈ 6/32 ≈ 0.19 — under the 0.20 ceiling, so it would fire "shares little vocabulary" on a walk that never left its subject. The overlap coefficient is 1.0 for that same subset case (correctly silent) and still near 0 for genuinely divergent subjects, because it measures how much of the *smaller* recording's vocabulary is accounted for by the larger one, rather than penalizing a short recording for being short relative to a long one.

  **Three subject guards added at review, 2026-08-27.** The first draft's gate was still loose enough to fire on walks that never changed subject:

  1. **Scaffolding is filtered.** `SpokenStoplist.scaffoldLemmas` is subtracted from both sets before intersecting, as `recurringWord` already does. NLTagger tags "think", "know", "want", "keep" as content words; left in, a closing recording made entirely of spoken scaffolding counted eighteen "lemmas", cleared the floor, and shared nothing with the opening.
  2. **The lemma floor rose from 5 to 12,** and now counts content lemmas only. Five sat far below where a lexical-overlap judgment carries information: a sign-off ("heading back down the hill, tired but glad") clears it and scores near-zero overlap. A genuinely divergent long pair measures around 0.06, so there is ample headroom above the higher floor.
  3. **A length-ratio ceiling of 3.0.** Past it, the smaller recording is a thin sample of the walk rather than its second half, and its overlap against a much longer transcript says more about its length than about the subject.

- **Language.** The subject branch runs only when `NLTagger.availableTagSchemes(for: .word, language:)` reports a `.lemma` model for the transcript's detected language, **and** the first and last recordings resolve to the same language. Asked of the OS at runtime rather than hardcoded, so the branch widens on its own as Apple adds lemma models.

  **Added at review, 2026-08-27.** `TranscriptNLP.contentLemmas` falls back to the lowercased surface form when NLTagger has no lemma model, so an inflected language yields a distinct "lemma" per inflection and overlap is depressed systematically. Pilgrim's core audience walks the Camino: French, German, Italian, Portuguese, and Spanish transcripts are a primary case, and every one of them would have read as total divergence. A language switch between the first and last recording guaranteed a false fire outright. Silence is the correct answer when the measurement is not valid — the pace branch is unaffected and still speaks.

When it fires, the directive names *which* signal moved, so the model is pointed at something real rather than asked to hunt:

- Pace: `The walker spoke [faster|more slowly] by the last recording than the first — attend to what moved between them.`
- Subject: `The walker's last recording shares little vocabulary with the first — attend to what moved between them.`

When both clear, pace is reported (declaration order). When neither clears, the directive stays silent and the `maxDirectives` budget goes to a detector with something to say.

**Cost.** Removes one always-on firing rule. Net −1 against the accretion budget.

---

## Workstream 5 — Context policy mechanism

**Problem (live defect).** `PromptAssembler.assemble` builds one dossier and every voice receives all of it. `JournalingVoice` — whose instruction is *"turn these scattered walking thoughts into a coherent journal entry... preserving my authentic voice"* — currently receives absolutist percentages, sentiment scores, and modal lean lines, which land in an entry the walker rereads years later. `CreativeVoice` is asked for a poem while holding a sentiment score. `GratitudeVoice` receives marker profiles it has no use for.

**Fix.** A declarative per-voice context policy on the `PromptVoice` protocol, using the existing default-implementation extension pattern so `CustomPromptStyle` is unaffected:

```swift
protocol PromptVoice {
    // existing members...
    var contextPolicy: PromptContextPolicy { get }
}

extension PromptVoice {
    var contextPolicy: PromptContextPolicy { .full }
}
```

`PromptContextPolicy` declares which already-computed blocks are emitted. It is a **filter at assembly time on a context built once** — it must not cause any block to be computed per-voice, which would break the `generateAll` single-pass property.

**Applied narrowly in this spec:**

| Voice | Policy |
|---|---|
| Oblique | `.full` + `unchangedBlock` hoisted |
| Creative | `.full` minus marker lines and thread analysis |
| Journaling | `.full` minus marker lines |
| Gratitude | `.full` minus marker lines and thread analysis |
| Contemplative, Reflective, Philosophical | `.full` (unchanged) |

"Minus marker lines" suppresses the per-recording marker line and the modal lean clause from `ThreadsDossierFormatter.dossier` output. The thread section, `Quiet this walk`, and `Noticed:` are governed separately so the suppression is legible rather than all-or-nothing.

**The full six-voice matrix is deferred** (§Deferred). It changes output for every voice and needs its own LLM-readback pass; folding it here would produce a spec that cannot be reviewed coherently.

---

## Non-goals

- `Unchanged:` for voices other than Oblique. It is the differentiator; sharing it collapses Oblique into Reflective.
- Embedding-based theme clustering. Still parked from the Threads field gate, and Principle 2 sharpens the caution: naive nearest-neighbour supplies no relevance criterion. Any future version must be intention-conditioned.
- Reducing `AttentionDirectives.maxDirectives`. There is a real argument the prompts are over-directed (4 directives + 3 `Noticed:` lines + dossier exceeds the chunking bound, and Principle 4 says the added heuristics carry uncounted cost), but this is a field-test question, not an armchair one. Recorded in Deferred.
- Any change to the Threads engine, `ThemeExtractor`, `MarkerAnalyzer`, or schema. `TranscriptContext.schemaVersion` is **not** bumped — no derived-cache semantics change, so the "derived-cache-semantics-are-schema" rule from the build-108 field bug does not trigger.

---

## Testing

**Unit — `DossierSensesInvariance`.** Pure-module tests mirroring `DossierSensesTracks` coverage: one fires/does-not-fire pair per signal, threshold boundary cases, the density-floor exclusion in signal 2, cap-3 truncation, priority ordering, and lemma suppression across signals (a theme named by a higher-ranked invariant never reappears, matching the `used` set belt in `DossierSenses.lines`).

**Unit — availability.** Both gates independently: history-deep + silent walk → unavailable; history-shallow + speech → unavailable; both pass → available; both pass but no invariant fires → available with no block.

**Unit — dark flag.** Signal 5 engine tested directly; `pendingFieldGate = true` verified to suppress it from assembled output.

**Unit — assembler.** Snapshot per voice confirming `unchangedBlock` appears only for Oblique and is hoisted above the context dossier; confirming marker lines are absent for Creative, Journaling, and Gratitude and present for the other three; confirming `CustomPromptStyle` still receives `.full` via the protocol default.

**Unit — directives.** `firstVersusLast` fires on each qualifying delta and stays silent when none clears; the freed budget slot is confirmed to promote a lower-ranked detector.

**Regression.** The existing sentiment per-sentence-averaging pin stays green. Suite baseline is 1388; expect growth, no reductions. Lint baseline is whatever `main` currently reports — confirm before starting and hold it at zero new warnings; the Threads ledger records the adjudicated exceptions.

**DEBUG harness.** Extend the `--senses-field-report` pattern with `--invariance-field-report`, evaluating every invariant uncapped across all walks with transcribed recordings, printing per-signal firing rates and every emitted line. Same discipline as the senses harness: evaluate only, never write defaults, never consume real state.

---

## Field gate

Binding before **external** release. Internal TestFlight may precede it.

1. **Firing-rate pass** on real device history via `--invariance-field-report`. Judge degeneration (fires on nearly every walk) and dead signals (nearly never), per signal. Same known limitations as the senses harness: it skips stale-context self-heal and ignores the `threadsAfterWalks` toggle.

2. **Harm check — new, and required by Principle 4.** The existing harness measures firing rate, which is the upside only; the no-free-lunch theorem guarantees a matching downside that firing rate is structurally blind to. For a sample of walks, generate the Oblique reflection **with** and **without** the `Unchanged:` block and human-rate which is better. A signal that fires often and makes reflections worse is the failure mode `questionDensity` only escaped because it was loud. This check applies to Workstream 2 as well — interpretive keys with and without.

3. **LLM-readback QA.** Paste real Oblique prompts, including elevated marker profiles, into ChatGPT/Claude. Iterate until: no clinical language, no contentless reframe instruction, no invented invariant, one thing named rather than a list. Confirm the model does not smuggle the pivot back in through a closing question.

4. **Signal 5 judgement.** Decide on `pendingFieldGate` for the unarrived intention only after 1–3 pass, and only on real history.

5. **Record outcomes** in this document's Deferred section before any Stage-2 work.

---

## Deferred / open questions

- **Full six-voice context matrix.** Mechanism ships here; broad application needs its own spec and readback pass.
- **History-only Oblique on silent walks.** Would require an `Unchanged:` build path independent of `currentRecordings.isEmpty`. Deferred as YAGNI; revisit if walkers ask for it.
- **`maxDirectives` reduction / shared directive+sense budget.** Field-test question. Principle 4 and Principle 6 both suggest 7+ pointers is past the peak.
- **Hoisting "do not summarize the walk back to the walker; they were there"** from `ContemplativeVoice` into the shared contract. It is Cherniak's relevant-implication point and every voice needs it; hoisting replaces rather than adds, so it fits the accretion budget. Cut from this spec only for scope.
- **Output chunk cap** ("at most three things worth carrying") for Reflective, Philosophical, and Gratitude — not Creative or Journaling, where the output is not a list of observations.
- **Direction-aware `recurringWord`.** `ThreadStore.salienceDirection` already knows rising/steady/fading; the directive currently says "it may be doing quiet work" for all three.
- **Icon choice** for Oblique, decided against the rendered picker.
- **Non-English walks.** `markerLine` already degrades to "Markers unavailable (non-English recording)"; signals 2 and 3 will therefore never fire for them, while 1 and 4 still can. Whether that asymmetry is acceptable, or Oblique should gate on marker availability, is unresolved.

---

## Risks

1. **Oblique collapses into Reflective.** Mitigated by the anchoring constraint (build only on `Unchanged:`), by Reflective's Goodman fix pulling it toward evidence-bound observation, and by the picker copy. Verified at readback.
2. **Invented invariants.** The highest-severity failure: an LLM told to stitch a meta-frame is maximally Goodman-exposed. Mitigated by constraint 1 and checked explicitly at readback.
3. **Small-N noise.** Co-occurrence over 3 walks is thin. Thresholds are starting values and the gate is the arbiter, per the `questionDensity` precedent.
4. **Invasiveness.** "You have never spoken about X without Y" is a large claim about a person. Signal 5 is dark for exactly this reason; the Honest intensity level was chosen deliberately over Unflinching.
5. **Build-time cost.** No new fetches, but signals 2 and 3 iterate `historicalContexts` per thread. The honest budget is ~0.3s median cold (context loading + sense math, with a 2.66s outlier already on the optimization list). Invariance math must be measured against that, memoized on the same key, and kept off-main.
6. **Picker gate reads as gamification.** Mitigated by copy register — "Still listening" frames the voice as needing to hear more, not as an unlock. Revisit if it lands wrong on device.
