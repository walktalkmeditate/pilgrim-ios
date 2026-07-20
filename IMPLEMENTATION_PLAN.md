# AI Prompt Richness Upgrades

Scope agreed in conversation: make generated AI prompts data-aware and richer.
Model bump (tiny → base) already landed on this branch.

## Stage 1: Response contracts
**Goal**: Every prompt ends with a "How to respond" contract — per-voice output
constraints plus shared lines (respond in the walker's language, never invent
details, honor multi-voice transcripts as conversation).
**Success Criteria**: Contract section present in all 6 styles + custom styles;
shared lines conditional on speech; per-voice constraints distinct.
**Tests**: PromptResponseContractTests — shared lines, per-voice markers,
custom style inclusion, silent-walk conditionality.
**Status**: Complete

## Stage 2: Attention directives
**Goal**: Pure pattern detection over ActivityContext emitting up to 4 specific
"Attend to:" directives (pace shift across thirds, sustained stillness beyond
meditation, intention word echo, recurring word, first-vs-last recording).
**Success Criteria**: Directives appear only when their pattern is present;
capped at 4; assembler section omitted when none fire.
**Tests**: AttentionDirectivesTests — one per detector (fires + doesn't fire),
cap, assembler integration.
**Status**: Complete

## Stage 3: Walk-character preamble + custom style dedupe
**Goal**: Assembler-level walk character note (long/brief, night/early-morning,
full moon, meditated) woven into every style's preamble; CustomPromptStyle
stops hardcoding a duplicate preamble and shares the standard one.
**Success Criteria**: Distinct walks produce distinct preamble notes for the
same style; custom styles inherit preamble improvements automatically.
**Tests**: WalkCharacterTests — trait detection boundaries; note appears in
built-in and custom prompts.
**Status**: Complete

## Stage 4: Practice lexicon + seek story
**Goal**: ActivityContext learns the walk's mode (wander/seek). Assembler emits
"About this practice" explaining the mode's ritual grammar in Pilgrim's own
vocabulary; seek walks include the seek story (arrivals with time-of-day,
zero-arrival seeks honored).
**Success Criteria**: Seek walks explain the seed/clearings surrender; wander
walks get one sentence; prompt list derives mode from walk events.
**Tests**: PracticeLexiconTests — mode sentences, arrival story, zero-arrival.
**Status**: Not Started

## Stage 5: Body data injection
**Goal**: Pauses (count/total/longest), ascent/descent, and time-of-day
crossing (began afternoon → ended night) reach the prompt context.
**Success Criteria**: Sections appear only when meaningful (pauses exist,
elevation > 10 m, time-of-day actually crossed).
**Tests**: ContextFormatter tests for each formatter + threshold cases.
**Status**: Not Started
