# Rubberduck Walk Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a tiny unbranded rubber duck that walks real pilgrimage routes (Shikoku 88 first), speaks rarely in a child/fool/sage voice, publishes a jsDelivr-served JSON feed, and appears as an easter egg on pilgrim-landing via a new `/walk` page and a footer icon.

**Architecture:** New GitHub repo `walktalkmeditate/rubberduck-walk` holds markdown entries, deterministic TS helpers, and `CLAUDE.md` as the "brain." Daily Claude Code `/schedule` invocation advances the duck's position, drafts + self-reviews an entry (or falls silent), commits, pushes, purges jsDelivr. pilgrim-landing's `/walk` page is plain static HTML/CSS/JS that fetches the feed on load and renders entries with age-based visual fading.

**Tech Stack:** Node 20 + TypeScript (tsx runtime), node:test for tests, js-yaml for frontmatter, Open-Meteo for weather, jsDelivr for CDN, Claude Code CLI as generation runtime. **No HTML in the feed** — duck prose is plain text; the client splits on blank lines and uses `textContent` to stay XSS-safe. pilgrim-landing stays vanilla HTML/CSS/JS (no build step, no framework).

**Spec:** `docs/superpowers/specs/2026-04-22-rubberduck-walk-design.md`

**Repos touched:**
- **NEW**: `~/GitHub/rubberduck/walk/` → remote `walktalkmeditate/rubberduck-walk`
- **MODIFY**: `~/GitHub/momentmaker/pilgrim-landing/` (add `walk.html`, `css/walk.css`, `js/walk.js`, footer duck in 4 existing pages)
- **NO CHANGE**: pilgrim-ios (this doc lives here, nothing else touched)

Every task explicitly notes `cd` working directory. The plan file stays here in pilgrim-ios.

---

## File Structure

### New in `~/GitHub/rubberduck/walk/`

```
walk/
├── CLAUDE.md                    character bible + playbook (Claude Code loads this automatically)
├── package.json                 node project manifest (tsx, js-yaml, dev: typescript, @types/node)
├── tsconfig.json                TS config, strict mode
├── .gitignore                   node_modules, .env, .DS_Store
├── README.md                    short — "a duck. it walks."
├── state.json                   current route, stage, mode, timestamps (authoritative state)
├── feed.json                    generated — what jsDelivr serves
├── routes/
│   ├── queue.json               ordered route list (human-editable)
│   └── shikoku-88.json          snapshot from open-pilgrimages (committed)
├── entries/                     markdown + YAML frontmatter, one per duck entry
├── assets/
│   ├── chiefrubberduck.png      source PNG (committed, for provenance)
│   └── chiefrubberduck-transparent.gif  source GIF
├── src/
│   ├── types.ts                 shared TypeScript types (State, Entry, Feed, Route)
│   ├── entries.ts               parse/load entries (markdown + frontmatter, plain-text body)
│   ├── feed.ts                  build feed.json from entries + state + route
│   ├── advance.ts               state-machine transitions
│   └── weather.ts               Open-Meteo fetch + WMO code → short-string mapping
├── scripts/
│   ├── advance.ts               CLI wrapper for src/advance.ts (used by daily /schedule)
│   ├── build-feed.ts            CLI wrapper for src/feed.ts
│   ├── weather.ts               CLI wrapper for src/weather.ts (prints weather string)
│   └── purge.sh                 curl to purge.jsdelivr.net
├── duck                         top-level CLI dispatcher (tsx-based shebang)
└── test/                        node:test specs mirroring src/
    ├── entries.test.ts
    ├── feed.test.ts
    ├── advance.test.ts
    └── weather.test.ts
```

### New/modified in `~/GitHub/momentmaker/pilgrim-landing/`

```
walk.html              NEW — the /walk page
css/walk.css           NEW — journal-styled entries + fade tiers + map styling
js/walk.js             NEW — fetch feed, render (textContent-only), apply age-based fading
assets/duck/
  ├── duck-24.png      NEW — 1x footer icon
  ├── duck-48.png      NEW — 2x (Retina) footer icon
  └── duck.gif         NEW — animated for /walk map current-position marker
index.html             MODIFY — add duck icon inside existing .horizon footer (line ~1515)
privacy.html           MODIFY — same
terms.html             MODIFY — same
press.html             MODIFY — same
```

The `/walk` page does NOT get a `.horizon` footer itself (it's its own atmosphere). It gets only the chiefrubberduck tagline in muted type at the bottom.

---

## Phase 0 — Bootstrap rubberduck-walk repo

### Task 1: Create the repo directory and initial files

**Files:**
- Create: `~/GitHub/rubberduck/walk/` (directory)
- Create: `~/GitHub/rubberduck/walk/.gitignore`
- Create: `~/GitHub/rubberduck/walk/README.md`
- Create: `~/GitHub/rubberduck/walk/package.json`
- Create: `~/GitHub/rubberduck/walk/tsconfig.json`

- [ ] **Step 1: Verify parent dir and create walk/**

Run from anywhere:
```bash
ls ~/GitHub/rubberduck/       # should show: guide  substack
mkdir -p ~/GitHub/rubberduck/walk
cd ~/GitHub/rubberduck/walk
```

- [ ] **Step 2: Write `.gitignore`**

```
node_modules/
.DS_Store
.env
.env.local
*.log
dist/
coverage/
```

- [ ] **Step 3: Write `README.md`**

```markdown
# walk

A duck. It walks.

See the feed at https://cdn.jsdelivr.net/gh/walktalkmeditate/rubberduck-walk@main/feed.json.
```

- [ ] **Step 4: Write `package.json`**

```json
{
  "name": "rubberduck-walk",
  "version": "0.0.1",
  "private": true,
  "type": "module",
  "bin": {
    "duck": "./duck"
  },
  "scripts": {
    "test": "node --import tsx --test 'test/**/*.test.ts'",
    "advance": "tsx scripts/advance.ts",
    "build-feed": "tsx scripts/build-feed.ts",
    "weather": "tsx scripts/weather.ts",
    "purge": "bash scripts/purge.sh"
  },
  "dependencies": {
    "js-yaml": "^4.1.0"
  },
  "devDependencies": {
    "@types/js-yaml": "^4.0.9",
    "@types/node": "^20.12.0",
    "tsx": "^4.7.0",
    "typescript": "^5.4.0"
  }
}
```

- [ ] **Step 5: Write `tsconfig.json`**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "strict": true,
    "esModuleInterop": true,
    "resolveJsonModule": true,
    "skipLibCheck": true,
    "noEmit": true,
    "allowImportingTsExtensions": true
  },
  "include": ["src/**/*", "scripts/**/*", "test/**/*"]
}
```

- [ ] **Step 6: Install deps**

```bash
cd ~/GitHub/rubberduck/walk
npm install
```
Expected: no errors, `node_modules/` created.

- [ ] **Step 7: Commit**

```bash
cd ~/GitHub/rubberduck/walk
git init
git add .
git commit -m "chore: bootstrap repo"
```

---

### Task 2: Connect GitHub remote and push

**Files:** None changed; this is a git/GitHub plumbing task.

- [ ] **Step 1: Create empty public repo on GitHub**

The remote `walktalkmeditate/rubberduck-walk` must exist before push. If not already created, ask the user to create it at https://github.com/new with name `rubberduck-walk`, owner `walktalkmeditate`, public, no README/license/gitignore (we already have those).

- [ ] **Step 2: Add remote and push**

```bash
cd ~/GitHub/rubberduck/walk
git branch -M main
git remote add origin git@github.com:walktalkmeditate/rubberduck-walk.git
git push -u origin main
```
Expected: push succeeds, remote has the bootstrap commit.

- [ ] **Step 3: Verify jsDelivr can see the repo**

```bash
curl -I https://cdn.jsdelivr.net/gh/walktalkmeditate/rubberduck-walk@main/README.md
```
Expected: HTTP 200. If 404, the CDN may take a minute to index a newly-created repo.

---

## Phase 1 — Types and initial data

### Task 3: Define shared TypeScript types

**Files:**
- Create: `~/GitHub/rubberduck/walk/src/types.ts`

- [ ] **Step 1: Write `src/types.ts`**

```typescript
export type DuckMode = "walking" | "completing" | "resting" | "beginning";

export type EntryKind = "offering" | "notice" | "silence" | "threshold" | "letter";

export type Coords = [number, number]; // [latitude, longitude]

export interface State {
  route: string;
  stage: number;
  stageName: string;
  coords: Coords;
  mode: DuckMode;
  modeEnteredAt: string;   // ISO date "YYYY-MM-DD"
  lastAdvancedAt: string;  // ISO date "YYYY-MM-DD"
}

export interface RouteStage {
  index: number;
  name: string;
  coords: Coords;
}

export interface Route {
  id: string;
  name: string;
  country: string;
  distanceKm: number;
  stages: RouteStage[];
  /** Optional route-specific closure site used when mode=completing. */
  closure?: {
    name: string;
    coords: Coords;
    transitStages: RouteStage[];
  };
}

export interface EntryFrontmatter {
  date: string;          // "YYYY-MM-DD"
  route: string;
  stage: number;
  stageName: string;
  coords: Coords;
  kind: EntryKind;
  glyph: string;
  weather?: string;      // human-readable, e.g. "light rain, 14°C"
  author?: string;       // only for kind=letter; defaults to "— the pilgrim"
}

export interface Entry extends EntryFrontmatter {
  body: string;          // raw plain-text body
  paragraphs: string[];  // split on blank-line boundaries; each is plain text
  filePath: string;      // absolute path on disk
  ageDays: number;       // computed at build time
}

export interface FeedDuck {
  route: string;
  routeName: string;
  stage: number;
  stageName: string;
  coords: Coords;
  mode: DuckMode;
  progress: number;      // 0..1
}

export interface FeedEntry {
  date: string;
  route: string;
  stage: number;
  stageName: string;
  coords: Coords;
  kind: EntryKind;
  glyph: string;
  paragraphs: string[];  // plain text — client renders with textContent
  author?: string;
  ageDays: number;
}

export interface Feed {
  generatedAt: string;  // ISO 8601 UTC
  duck: FeedDuck;
  entries: FeedEntry[];
  routePath: Record<string, Coords[]>;  // route id → ordered coords
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd ~/GitHub/rubberduck/walk
npx tsc --noEmit
```
Expected: no errors.

- [ ] **Step 3: Commit**

```bash
git add src/types.ts
git commit -m "feat(types): define State, Entry, Feed, Route"
```

---

### Task 4: Snapshot shikoku-88 route data from open-pilgrimages

**Files:**
- Create: `~/GitHub/rubberduck/walk/routes/shikoku-88.json`

This is a one-time snapshot. The duck repo does not live-depend on `../open-pilgrimages`.

- [ ] **Step 1: Locate shikoku-88 in open-pilgrimages**

```bash
ls ~/GitHub/momentmaker/open-pilgrimages/routes/shikoku-88/
```
Inspect the files. Typical structure includes a `route.json` or similar with stages.

- [ ] **Step 2: Transform and write snapshot**

Read the source files in `~/GitHub/momentmaker/open-pilgrimages/routes/shikoku-88/`, extract the 88 temple stages into the `Route` shape from `src/types.ts`, and write to `~/GitHub/rubberduck/walk/routes/shikoku-88.json`. The JSON must validate against the `Route` type: `id`, `name`, `country`, `distanceKm`, `stages[]` (with `index`, `name`, `coords`).

Add the `closure` field manually (open-pilgrimages may not have Kōya-san):

```json
{
  "id": "shikoku-88",
  "name": "Shikoku Henro",
  "country": "JP",
  "distanceKm": 1200,
  "stages": [
    { "index": 1, "name": "Ryōzenji", "coords": [34.128, 134.537] },
    { "index": 88, "name": "Ōkuboji", "coords": [34.218, 134.051] }
  ],
  "closure": {
    "name": "Kōya-san Okunoin",
    "coords": [34.2167, 135.589],
    "transitStages": [
      { "index": 1, "name": "Tokushima port", "coords": [34.067, 134.555] },
      { "index": 2, "name": "Wakayama", "coords": [34.230, 135.170] },
      { "index": 3, "name": "Hashimoto", "coords": [34.312, 135.604] },
      { "index": 4, "name": "Kōya-san Okunoin", "coords": [34.2167, 135.589] }
    ]
  }
}
```

Fill in all 88 stages between index 1 and 88 using open-pilgrimages data. If the open-pilgrimages data has more precise coords, use those.

- [ ] **Step 3: Verify file parses and has 88 stages**

```bash
cd ~/GitHub/rubberduck/walk
node -e "console.log(JSON.parse(require('fs').readFileSync('routes/shikoku-88.json','utf8')).stages.length)"
```
Expected: `88`.

- [ ] **Step 4: Commit**

```bash
git add routes/shikoku-88.json
git commit -m "feat(routes): snapshot shikoku-88 from open-pilgrimages"
```

---

### Task 5: Write initial `state.json` and `routes/queue.json`

**Files:**
- Create: `~/GitHub/rubberduck/walk/state.json`
- Create: `~/GitHub/rubberduck/walk/routes/queue.json`

- [ ] **Step 1: Write `state.json`**

The duck starts at Temple 1.

```json
{
  "route": "shikoku-88",
  "stage": 1,
  "stageName": "Ryōzenji",
  "coords": [34.128, 134.537],
  "mode": "walking",
  "modeEnteredAt": "2026-04-23",
  "lastAdvancedAt": "2026-04-23"
}
```

(If the snapshot in Task 4 had different coords for Ryōzenji, use those.)

- [ ] **Step 2: Write `routes/queue.json`**

```json
[
  "shikoku-88",
  "kumano-kodo",
  "camino-frances",
  "camino-portugues",
  "camino-norte",
  "camino-primitivo",
  "camino-ingles"
]
```

- [ ] **Step 3: Commit**

```bash
git add state.json routes/queue.json
git commit -m "feat(state): initial state at Temple 1, route queue"
```

---

## Phase 2 — Entry parsing (TDD)

### Task 6: Write `parseEntry` with failing test

**Files:**
- Create: `~/GitHub/rubberduck/walk/test/entries.test.ts`
- Create: `~/GitHub/rubberduck/walk/src/entries.ts`

- [ ] **Step 1: Write the failing test**

File `test/entries.test.ts`:

```typescript
import { test } from "node:test";
import assert from "node:assert/strict";
import { parseEntry } from "../src/entries.ts";

test("parseEntry reads frontmatter and body as paragraphs", () => {
  const raw = `---
date: 2026-04-23
route: shikoku-88
stage: 1
stageName: Ryōzenji
coords: [34.128, 134.537]
kind: offering
glyph: 🪨
weather: clear, 15°C
---

A stone by the door. No one had moved it. No one needed to.
`;
  const result = parseEntry(raw, "/fake/path.md");
  assert.equal(result.date, "2026-04-23");
  assert.equal(result.kind, "offering");
  assert.equal(result.glyph, "🪨");
  assert.deepEqual(result.coords, [34.128, 134.537]);
  assert.deepEqual(result.paragraphs, [
    "A stone by the door. No one had moved it. No one needed to.",
  ]);
  assert.equal(result.filePath, "/fake/path.md");
});

test("parseEntry splits letter on blank lines", () => {
  const raw = `---
date: 2026-05-02
route: shikoku-88
stage: 13
stageName: Dainichiji
coords: [33.9, 134.1]
kind: letter
glyph: 🕯️
author: — the pilgrim
---

First paragraph here.

Second paragraph here.
`;
  const result = parseEntry(raw, "/fake/letter.md");
  assert.equal(result.kind, "letter");
  assert.equal(result.author, "— the pilgrim");
  assert.deepEqual(result.paragraphs, [
    "First paragraph here.",
    "Second paragraph here.",
  ]);
});

test("parseEntry handles silence (empty body → no paragraphs)", () => {
  const raw = `---
date: 2026-04-30
route: shikoku-88
stage: 5
stageName: Jizōji
coords: [34.1, 134.5]
kind: silence
glyph: 〰️
---
`;
  const result = parseEntry(raw, "/fake/silence.md");
  assert.equal(result.kind, "silence");
  assert.deepEqual(result.paragraphs, []);
});

test("parseEntry normalizes whitespace in paragraphs", () => {
  const raw = `---
date: 2026-04-23
route: shikoku-88
stage: 1
stageName: Ryōzenji
coords: [34.128, 134.537]
kind: offering
glyph: 🪨
---

  A stone.  
`;
  const result = parseEntry(raw, "/fake/p.md");
  assert.deepEqual(result.paragraphs, ["A stone."]);
});
```

- [ ] **Step 2: Run test — expect failure**

```bash
cd ~/GitHub/rubberduck/walk
npm test
```
Expected: FAIL (cannot import `../src/entries.ts`).

- [ ] **Step 3: Implement `src/entries.ts`**

```typescript
import yaml from "js-yaml";
import type { Entry, EntryFrontmatter } from "./types.ts";

const FRONTMATTER_RE = /^---\r?\n([\s\S]+?)\r?\n---\r?\n([\s\S]*)$/;

export function parseEntry(raw: string, filePath: string): Entry {
  const match = raw.match(FRONTMATTER_RE);
  if (!match) {
    throw new Error(`Entry missing frontmatter: ${filePath}`);
  }
  const [, fmRaw, body] = match;
  const fm = yaml.load(fmRaw) as EntryFrontmatter;

  if (!fm.date || !fm.route || !fm.kind) {
    throw new Error(`Entry frontmatter missing required fields: ${filePath}`);
  }

  const paragraphs = body
    .split(/\r?\n\s*\r?\n/)
    .map((p) => p.trim())
    .filter((p) => p.length > 0);

  return {
    ...fm,
    body,
    paragraphs,
    filePath,
    ageDays: 0, // computed later in feed builder
  };
}
```

- [ ] **Step 4: Run test — expect pass**

```bash
npm test
```
Expected: all 4 parseEntry tests pass.

- [ ] **Step 5: Commit**

```bash
git add src/entries.ts test/entries.test.ts
git commit -m "feat(entries): parse frontmatter + plain-text paragraphs"
```

---

### Task 7: Add `loadAllEntries` and age computation (TDD)

**Files:**
- Modify: `~/GitHub/rubberduck/walk/src/entries.ts`
- Modify: `~/GitHub/rubberduck/walk/test/entries.test.ts`

- [ ] **Step 1: Add the failing test**

Append to `test/entries.test.ts`:

```typescript
import { computeAgeDays } from "../src/entries.ts";

test("computeAgeDays returns whole days between two dates", () => {
  assert.equal(computeAgeDays("2026-04-23", "2026-04-23"), 0);
  assert.equal(computeAgeDays("2026-04-22", "2026-04-23"), 1);
  assert.equal(computeAgeDays("2026-01-23", "2026-04-23"), 90);
});
```

- [ ] **Step 2: Run — expect failure**

```bash
npm test
```
Expected: FAIL (`computeAgeDays` not exported).

- [ ] **Step 3: Implement**

Append to `src/entries.ts`:

```typescript
import { readdir, readFile } from "node:fs/promises";
import path from "node:path";

export function computeAgeDays(entryDate: string, today: string): number {
  const msPerDay = 24 * 60 * 60 * 1000;
  const a = Date.parse(entryDate + "T00:00:00Z");
  const b = Date.parse(today + "T00:00:00Z");
  return Math.round((b - a) / msPerDay);
}

export async function loadAllEntries(dir: string, today: string): Promise<Entry[]> {
  const names = await readdir(dir);
  const mdNames = names.filter((n) => n.endsWith(".md"));
  const entries: Entry[] = [];
  for (const name of mdNames) {
    const filePath = path.join(dir, name);
    const raw = await readFile(filePath, "utf8");
    const entry = parseEntry(raw, filePath);
    entry.ageDays = computeAgeDays(entry.date, today);
    entries.push(entry);
  }
  entries.sort((a, b) => (a.date < b.date ? 1 : -1));
  return entries;
}
```

- [ ] **Step 4: Run — expect pass**

```bash
npm test
```

- [ ] **Step 5: Commit**

```bash
git add src/entries.ts test/entries.test.ts
git commit -m "feat(entries): loadAllEntries + computeAgeDays"
```

---

## Phase 3 — State advance (TDD)

### Task 8: Write `advance` with failing test

**Files:**
- Create: `~/GitHub/rubberduck/walk/test/advance.test.ts`
- Create: `~/GitHub/rubberduck/walk/src/advance.ts`

- [ ] **Step 1: Write the failing test**

File `test/advance.test.ts`:

```typescript
import { test } from "node:test";
import assert from "node:assert/strict";
import { advance } from "../src/advance.ts";
import type { State, Route } from "../src/types.ts";

const shikoku: Route = {
  id: "shikoku-88",
  name: "Shikoku Henro",
  country: "JP",
  distanceKm: 1200,
  stages: [
    { index: 1, name: "Ryōzenji", coords: [34.128, 134.537] },
    { index: 2, name: "Gokurakuji", coords: [34.130, 134.556] },
    { index: 3, name: "Konsenji", coords: [34.135, 134.570] },
  ],
  closure: {
    name: "Kōya-san",
    coords: [34.216, 135.589],
    transitStages: [
      { index: 1, name: "Wakayama", coords: [34.23, 135.17] },
      { index: 2, name: "Kōya-san", coords: [34.216, 135.589] },
    ],
  },
};

test("advance moves duck from stage 1 to stage 2 during walking", () => {
  const state: State = {
    route: "shikoku-88",
    stage: 1,
    stageName: "Ryōzenji",
    coords: [34.128, 134.537],
    mode: "walking",
    modeEnteredAt: "2026-04-20",
    lastAdvancedAt: "2026-04-22",
  };
  const next = advance(state, shikoku, "2026-04-23");
  assert.equal(next.stage, 2);
  assert.equal(next.stageName, "Gokurakuji");
  assert.equal(next.mode, "walking");
  assert.equal(next.lastAdvancedAt, "2026-04-23");
});

test("advance flips to completing when final stage reached", () => {
  const state: State = {
    route: "shikoku-88",
    stage: 3,
    stageName: "Konsenji",
    coords: [34.135, 134.570],
    mode: "walking",
    modeEnteredAt: "2026-04-20",
    lastAdvancedAt: "2026-04-22",
  };
  const next = advance(state, shikoku, "2026-04-23");
  assert.equal(next.mode, "completing");
  assert.equal(next.stage, 1);
  assert.equal(next.stageName, "Wakayama");
  assert.equal(next.modeEnteredAt, "2026-04-23");
});

test("advance flips to resting when closure site reached", () => {
  const state: State = {
    route: "shikoku-88",
    stage: 1,
    stageName: "Wakayama",
    coords: [34.23, 135.17],
    mode: "completing",
    modeEnteredAt: "2026-04-23",
    lastAdvancedAt: "2026-04-23",
  };
  const next = advance(state, shikoku, "2026-04-24");
  assert.equal(next.mode, "resting");
  assert.equal(next.stageName, "Kōya-san");
  assert.equal(next.modeEnteredAt, "2026-04-24");
});

test("advance does not move during resting", () => {
  const state: State = {
    route: "shikoku-88",
    stage: 2,
    stageName: "Kōya-san",
    coords: [34.216, 135.589],
    mode: "resting",
    modeEnteredAt: "2026-04-24",
    lastAdvancedAt: "2026-04-24",
  };
  const next = advance(state, shikoku, "2026-05-01");
  assert.equal(next.mode, "resting");
  assert.equal(next.stage, 2);
  assert.equal(next.stageName, "Kōya-san");
  assert.equal(next.lastAdvancedAt, "2026-04-24"); // unchanged
});
```

- [ ] **Step 2: Run — expect failure**

```bash
npm test
```

- [ ] **Step 3: Implement `src/advance.ts`**

```typescript
import type { State, Route } from "./types.ts";

export function advance(state: State, route: Route, today: string): State {
  if (state.route !== route.id) {
    throw new Error(`state.route=${state.route} does not match route.id=${route.id}`);
  }

  if (state.mode === "resting") {
    return state; // frozen until beginRoute()
  }

  if (state.mode === "walking") {
    const nextStageIndex = state.stage + 1;
    const nextStage = route.stages.find((s) => s.index === nextStageIndex);

    if (nextStage) {
      return {
        ...state,
        stage: nextStage.index,
        stageName: nextStage.name,
        coords: nextStage.coords,
        lastAdvancedAt: today,
      };
    }

    // final stage reached — flip to completing
    if (!route.closure) {
      throw new Error(`Route ${route.id} has no closure defined`);
    }
    const firstTransit = route.closure.transitStages[0];
    return {
      ...state,
      stage: firstTransit.index,
      stageName: firstTransit.name,
      coords: firstTransit.coords,
      mode: "completing",
      modeEnteredAt: today,
      lastAdvancedAt: today,
    };
  }

  if (state.mode === "completing") {
    if (!route.closure) {
      throw new Error(`Route ${route.id} has no closure defined`);
    }
    const nextTransitIndex = state.stage + 1;
    const nextTransit = route.closure.transitStages.find(
      (s) => s.index === nextTransitIndex
    );

    if (nextTransit) {
      return {
        ...state,
        stage: nextTransit.index,
        stageName: nextTransit.name,
        coords: nextTransit.coords,
        lastAdvancedAt: today,
      };
    }

    // closure site reached — flip to resting
    return {
      ...state,
      mode: "resting",
      modeEnteredAt: today,
      lastAdvancedAt: today,
    };
  }

  if (state.mode === "beginning") {
    // beginning → walking on next advance
    const firstStage = route.stages[0];
    return {
      ...state,
      stage: firstStage.index,
      stageName: firstStage.name,
      coords: firstStage.coords,
      mode: "walking",
      modeEnteredAt: today,
      lastAdvancedAt: today,
    };
  }

  throw new Error(`Unknown mode: ${state.mode}`);
}
```

- [ ] **Step 4: Run — expect pass**

```bash
npm test
```

- [ ] **Step 5: Commit**

```bash
git add src/advance.ts test/advance.test.ts
git commit -m "feat(advance): state-machine transitions"
```

---

### Task 9: Add `beginRoute` function

**Files:**
- Modify: `~/GitHub/rubberduck/walk/src/advance.ts`
- Modify: `~/GitHub/rubberduck/walk/test/advance.test.ts`

- [ ] **Step 1: Add failing test**

Append to `test/advance.test.ts`:

```typescript
import { beginRoute } from "../src/advance.ts";

const kumano: Route = {
  id: "kumano-kodo",
  name: "Kumano Kodō",
  country: "JP",
  distanceKm: 150,
  stages: [
    { index: 1, name: "Takijiri-oji", coords: [33.778, 135.507] },
  ],
};

test("beginRoute flips from resting to beginning at stage 1 of new route", () => {
  const resting: State = {
    route: "shikoku-88",
    stage: 2,
    stageName: "Kōya-san",
    coords: [34.216, 135.589],
    mode: "resting",
    modeEnteredAt: "2026-12-14",
    lastAdvancedAt: "2026-12-14",
  };
  const next = beginRoute(resting, kumano, "2026-12-28");
  assert.equal(next.route, "kumano-kodo");
  assert.equal(next.mode, "beginning");
  assert.equal(next.stage, 1);
  assert.equal(next.stageName, "Takijiri-oji");
  assert.equal(next.modeEnteredAt, "2026-12-28");
});

test("beginRoute throws if state is not resting", () => {
  const walking: State = {
    route: "shikoku-88",
    stage: 5,
    stageName: "Jizōji",
    coords: [34.1, 134.5],
    mode: "walking",
    modeEnteredAt: "2026-04-20",
    lastAdvancedAt: "2026-05-01",
  };
  assert.throws(() => beginRoute(walking, kumano, "2026-05-02"));
});
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement**

Append to `src/advance.ts`:

```typescript
export function beginRoute(state: State, nextRoute: Route, today: string): State {
  if (state.mode !== "resting") {
    throw new Error(`Cannot begin a new route while mode=${state.mode}`);
  }
  const first = nextRoute.stages[0];
  return {
    route: nextRoute.id,
    stage: first.index,
    stageName: first.name,
    coords: first.coords,
    mode: "beginning",
    modeEnteredAt: today,
    lastAdvancedAt: today,
  };
}
```

- [ ] **Step 4: Run — expect pass**

- [ ] **Step 5: Commit**

```bash
git add src/advance.ts test/advance.test.ts
git commit -m "feat(advance): beginRoute transitions resting → beginning"
```

---

## Phase 4 — Feed builder (TDD)

### Task 10: Write `buildFeed` with failing test

**Files:**
- Create: `~/GitHub/rubberduck/walk/test/feed.test.ts`
- Create: `~/GitHub/rubberduck/walk/src/feed.ts`

- [ ] **Step 1: Write the failing test**

File `test/feed.test.ts`:

```typescript
import { test } from "node:test";
import assert from "node:assert/strict";
import { buildFeed } from "../src/feed.ts";
import type { State, Route, Entry } from "../src/types.ts";

const shikoku: Route = {
  id: "shikoku-88",
  name: "Shikoku Henro",
  country: "JP",
  distanceKm: 1200,
  stages: [
    { index: 1, name: "Ryōzenji", coords: [34.128, 134.537] },
    { index: 2, name: "Gokurakuji", coords: [34.130, 134.556] },
  ],
};

const state: State = {
  route: "shikoku-88",
  stage: 2,
  stageName: "Gokurakuji",
  coords: [34.130, 134.556],
  mode: "walking",
  modeEnteredAt: "2026-04-20",
  lastAdvancedAt: "2026-04-23",
};

const recentEntry: Entry = {
  date: "2026-04-23",
  route: "shikoku-88",
  stage: 2,
  stageName: "Gokurakuji",
  coords: [34.130, 134.556],
  kind: "offering",
  glyph: "🪨",
  body: "A stone.",
  paragraphs: ["A stone."],
  filePath: "/fake/a.md",
  ageDays: 0,
};

const oldEntry: Entry = {
  ...recentEntry,
  date: "2025-04-23",
  filePath: "/fake/b.md",
  ageDays: 365,
};

test("buildFeed includes recent entries", () => {
  const feed = buildFeed({ state, route: shikoku, entries: [recentEntry], today: "2026-04-23" });
  assert.equal(feed.entries.length, 1);
  assert.equal(feed.entries[0].date, "2026-04-23");
  assert.deepEqual(feed.entries[0].paragraphs, ["A stone."]);
  assert.equal(feed.duck.stage, 2);
  assert.equal(feed.duck.routeName, "Shikoku Henro");
  assert.equal(feed.duck.progress, 1); // 2 / 2 stages
});

test("buildFeed excludes entries older than 365 days", () => {
  const feed = buildFeed({
    state,
    route: shikoku,
    entries: [recentEntry, oldEntry],
    today: "2026-04-23",
  });
  assert.equal(feed.entries.length, 1);
  assert.equal(feed.entries[0].date, "2026-04-23");
});

test("buildFeed sorts entries newest first", () => {
  const older = { ...recentEntry, date: "2026-03-15", filePath: "/fake/c.md", ageDays: 39 };
  const feed = buildFeed({
    state,
    route: shikoku,
    entries: [older, recentEntry],
    today: "2026-04-23",
  });
  assert.equal(feed.entries[0].date, "2026-04-23");
  assert.equal(feed.entries[1].date, "2026-03-15");
});

test("buildFeed includes routePath with stage coords", () => {
  const feed = buildFeed({ state, route: shikoku, entries: [], today: "2026-04-23" });
  assert.deepEqual(feed.routePath["shikoku-88"], [
    [34.128, 134.537],
    [34.130, 134.556],
  ]);
});

test("buildFeed copies author from letter entries", () => {
  const letter: Entry = {
    ...recentEntry,
    kind: "letter",
    author: "— the pilgrim",
    filePath: "/fake/l.md",
  };
  const feed = buildFeed({ state, route: shikoku, entries: [letter], today: "2026-04-23" });
  assert.equal(feed.entries[0].author, "— the pilgrim");
});
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement `src/feed.ts`**

```typescript
import type { Feed, FeedEntry, Route, State, Entry } from "./types.ts";

const MAX_AGE_DAYS = 365;

interface BuildFeedOpts {
  state: State;
  route: Route;
  entries: Entry[];
  today: string;
}

export function buildFeed({ state, route, entries, today }: BuildFeedOpts): Feed {
  const fresh = entries
    .filter((e) => e.ageDays <= MAX_AGE_DAYS)
    .sort((a, b) => (a.date < b.date ? 1 : -1));

  const feedEntries: FeedEntry[] = fresh.map((e) => ({
    date: e.date,
    route: e.route,
    stage: e.stage,
    stageName: e.stageName,
    coords: e.coords,
    kind: e.kind,
    glyph: e.glyph,
    paragraphs: e.paragraphs,
    author: e.author,
    ageDays: e.ageDays,
  }));

  const totalStages = route.stages.length;
  const progress = totalStages === 0 ? 0 : Math.min(1, state.stage / totalStages);

  return {
    generatedAt: new Date().toISOString(),
    duck: {
      route: state.route,
      routeName: route.name,
      stage: state.stage,
      stageName: state.stageName,
      coords: state.coords,
      mode: state.mode,
      progress,
    },
    entries: feedEntries,
    routePath: {
      [route.id]: route.stages.map((s) => s.coords),
    },
  };
}
```

- [ ] **Step 4: Run — expect pass**

```bash
npm test
```

- [ ] **Step 5: Commit**

```bash
git add src/feed.ts test/feed.test.ts
git commit -m "feat(feed): build feed.json from entries + state + route"
```

---

### Task 11: Write the `build-feed` CLI script

**Files:**
- Create: `~/GitHub/rubberduck/walk/scripts/build-feed.ts`

No test — thin wrapper. Verified by running.

- [ ] **Step 1: Write the script**

```typescript
#!/usr/bin/env -S tsx
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { buildFeed } from "../src/feed.ts";
import { loadAllEntries } from "../src/entries.ts";
import type { State, Route } from "../src/types.ts";

const REPO_ROOT = path.resolve(import.meta.dirname, "..");

async function main() {
  const today = new Date().toISOString().slice(0, 10);
  const state: State = JSON.parse(
    await readFile(path.join(REPO_ROOT, "state.json"), "utf8")
  );
  const route: Route = JSON.parse(
    await readFile(path.join(REPO_ROOT, "routes", `${state.route}.json`), "utf8")
  );
  const entries = await loadAllEntries(path.join(REPO_ROOT, "entries"), today);

  const feed = buildFeed({ state, route, entries, today });
  await writeFile(
    path.join(REPO_ROOT, "feed.json"),
    JSON.stringify(feed, null, 2) + "\n"
  );
  console.log(`feed.json built — ${feed.entries.length} entries, duck at ${feed.duck.stageName}`);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 2: Make entries/ exist (empty is fine)**

```bash
cd ~/GitHub/rubberduck/walk
mkdir -p entries
touch entries/.gitkeep
```

- [ ] **Step 3: Run it**

```bash
npm run build-feed
```
Expected: outputs `feed.json built — 0 entries, duck at Ryōzenji`. File `feed.json` appears at repo root.

- [ ] **Step 4: Commit**

```bash
git add scripts/build-feed.ts entries/.gitkeep feed.json
git commit -m "feat(scripts): build-feed CLI generates feed.json"
```

---

### Task 12: Write `advance` CLI script

**Files:**
- Create: `~/GitHub/rubberduck/walk/scripts/advance.ts`

- [ ] **Step 1: Write the script**

```typescript
#!/usr/bin/env -S tsx
import { readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { advance } from "../src/advance.ts";
import type { State, Route } from "../src/types.ts";

const REPO_ROOT = path.resolve(import.meta.dirname, "..");

async function main() {
  const today = new Date().toISOString().slice(0, 10);
  const statePath = path.join(REPO_ROOT, "state.json");
  const state: State = JSON.parse(await readFile(statePath, "utf8"));
  const route: Route = JSON.parse(
    await readFile(path.join(REPO_ROOT, "routes", `${state.route}.json`), "utf8")
  );

  const next = advance(state, route, today);
  await writeFile(statePath, JSON.stringify(next, null, 2) + "\n");

  if (next.stage !== state.stage || next.mode !== state.mode) {
    console.log(
      `duck: ${state.stageName} (${state.mode}) → ${next.stageName} (${next.mode})`
    );
  } else {
    console.log(`duck: still at ${next.stageName} (${next.mode})`);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 2: Run it (should advance state from 1 → 2)**

```bash
cd ~/GitHub/rubberduck/walk
cat state.json
npm run advance
cat state.json
```
Expected: console prints `duck: Ryōzenji (walking) → Gokurakuji (walking)`, state.json updated.

- [ ] **Step 3: Reset state back to stage 1**

Edit `state.json` to revert to stage 1 Ryōzenji. Task 18 will advance properly.

- [ ] **Step 4: Commit**

```bash
git add scripts/advance.ts state.json
git commit -m "feat(scripts): advance CLI applies state transition"
```

---

## Phase 5 — Weather (TDD)

### Task 13: Write `mapWeatherCode` with failing test

**Files:**
- Create: `~/GitHub/rubberduck/walk/test/weather.test.ts`
- Create: `~/GitHub/rubberduck/walk/src/weather.ts`

- [ ] **Step 1: Write the failing test**

File `test/weather.test.ts`:

```typescript
import { test } from "node:test";
import assert from "node:assert/strict";
import { mapWeatherCode, formatWeather } from "../src/weather.ts";

test("mapWeatherCode 0 → clear", () => {
  assert.equal(mapWeatherCode(0), "clear");
});

test("mapWeatherCode 45 and 48 → fog", () => {
  assert.equal(mapWeatherCode(45), "fog");
  assert.equal(mapWeatherCode(48), "fog");
});

test("mapWeatherCode rain codes", () => {
  assert.equal(mapWeatherCode(51), "light rain");
  assert.equal(mapWeatherCode(63), "rain");
  assert.equal(mapWeatherCode(81), "showers");
});

test("mapWeatherCode snow codes", () => {
  assert.equal(mapWeatherCode(73), "snow");
});

test("mapWeatherCode thunderstorm", () => {
  assert.equal(mapWeatherCode(95), "thunderstorm");
});

test("mapWeatherCode unknown → clear (safe default)", () => {
  assert.equal(mapWeatherCode(9999), "clear");
});

test("formatWeather combines code and temperature", () => {
  assert.equal(formatWeather(0, 15.5), "clear, 16°C");
  assert.equal(formatWeather(61, 8.0), "light rain, 8°C");
});
```

- [ ] **Step 2: Run — expect failure**

- [ ] **Step 3: Implement `src/weather.ts`**

```typescript
import type { Coords } from "./types.ts";

export function mapWeatherCode(code: number): string {
  if (code === 0) return "clear";
  if (code >= 1 && code <= 3) return "overcast";
  if (code === 45 || code === 48) return "fog";
  if (code >= 51 && code <= 57) return "light rain";
  if (code >= 61 && code <= 67) return "rain";
  if (code >= 71 && code <= 77) return "snow";
  if (code >= 80 && code <= 82) return "showers";
  if (code >= 85 && code <= 86) return "snow showers";
  if (code >= 95 && code <= 99) return "thunderstorm";
  return "clear";
}

export function formatWeather(code: number, tempC: number): string {
  const desc = mapWeatherCode(code);
  const t = Math.round(tempC);
  return `${desc}, ${t}°C`;
}

interface OpenMeteoResponse {
  current: {
    temperature_2m: number;
    weather_code: number;
    precipitation: number;
  };
}

export async function fetchWeather(coords: Coords): Promise<string | null> {
  const [lat, lon] = coords;
  const url =
    `https://api.open-meteo.com/v1/forecast?latitude=${lat}&longitude=${lon}` +
    `&current=temperature_2m,weather_code,precipitation`;
  try {
    const res = await fetch(url);
    if (!res.ok) return null;
    const data = (await res.json()) as OpenMeteoResponse;
    return formatWeather(data.current.weather_code, data.current.temperature_2m);
  } catch {
    return null;
  }
}
```

- [ ] **Step 4: Run — expect pass**

```bash
npm test
```

- [ ] **Step 5: Commit**

```bash
git add src/weather.ts test/weather.test.ts
git commit -m "feat(weather): WMO code mapping + Open-Meteo fetch"
```

---

### Task 14: Write `weather` CLI script

**Files:**
- Create: `~/GitHub/rubberduck/walk/scripts/weather.ts`

- [ ] **Step 1: Write the script**

```typescript
#!/usr/bin/env -S tsx
import { readFile } from "node:fs/promises";
import path from "node:path";
import { fetchWeather } from "../src/weather.ts";
import type { State } from "../src/types.ts";

const REPO_ROOT = path.resolve(import.meta.dirname, "..");

async function main() {
  const state: State = JSON.parse(
    await readFile(path.join(REPO_ROOT, "state.json"), "utf8")
  );
  const weather = await fetchWeather(state.coords);
  if (weather) {
    process.stdout.write(weather);
  } else {
    process.stdout.write("unknown");
    process.exit(2);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 2: Run it (live API — expect real weather string)**

```bash
cd ~/GitHub/rubberduck/walk
npm run weather
```
Expected: prints something like `clear, 18°C`.

- [ ] **Step 3: Commit**

```bash
git add scripts/weather.ts
git commit -m "feat(scripts): weather CLI prints current condition string"
```

---

## Phase 6 — Purge and duck CLI

### Task 15: Write the purge script

**Files:**
- Create: `~/GitHub/rubberduck/walk/scripts/purge.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
set -euo pipefail

URL="https://purge.jsdelivr.net/gh/walktalkmeditate/rubberduck-walk@main/feed.json"

echo "purging jsDelivr cache..."
curl -fsS "$URL" | head -c 200
echo ""
```

- [ ] **Step 2: Make executable**

```bash
cd ~/GitHub/rubberduck/walk
chmod +x scripts/purge.sh
```

- [ ] **Step 3: Commit (don't run yet — the repo isn't pushed with a feed)**

```bash
git add scripts/purge.sh
git commit -m "feat(scripts): purge jsdelivr cache"
```

---

### Task 16: Write the `duck` CLI dispatcher

**Files:**
- Create: `~/GitHub/rubberduck/walk/duck`

- [ ] **Step 1: Write the dispatcher**

```typescript
#!/usr/bin/env -S tsx
import { readFile, writeFile, mkdir } from "node:fs/promises";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline/promises";
import path from "node:path";
import yaml from "js-yaml";
import type { State, Route, EntryKind } from "./src/types.ts";
import { beginRoute } from "./src/advance.ts";

const REPO_ROOT = path.resolve(import.meta.dirname);

async function run(cmd: string, args: string[]): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, args, { stdio: "inherit", cwd: REPO_ROOT });
    child.on("exit", (code) => (code === 0 ? resolve() : reject(new Error(`${cmd} exited ${code}`))));
  });
}

async function readState(): Promise<State> {
  return JSON.parse(await readFile(path.join(REPO_ROOT, "state.json"), "utf8"));
}

async function readRoute(id: string): Promise<Route> {
  return JSON.parse(await readFile(path.join(REPO_ROOT, "routes", `${id}.json`), "utf8"));
}

async function writeEntry(opts: {
  kind: EntryKind;
  glyph: string;
  body: string;
  author?: string;
}): Promise<string> {
  const state = await readState();
  const today = new Date().toISOString().slice(0, 10);
  const slug = state.stageName.toLowerCase().replace(/[^a-z0-9]+/g, "-");
  const fileName = `${today}-${slug}.md`;
  const filePath = path.join(REPO_ROOT, "entries", fileName);
  const frontmatter: Record<string, unknown> = {
    date: today,
    route: state.route,
    stage: state.stage,
    stageName: state.stageName,
    coords: state.coords,
    kind: opts.kind,
    glyph: opts.glyph,
  };
  if (opts.author) frontmatter.author = opts.author;
  const fmYaml = yaml.dump(frontmatter, { flowLevel: 1 }).trim();
  const content = `---\n${fmYaml}\n---\n\n${opts.body}\n`;
  await mkdir(path.dirname(filePath), { recursive: true });
  await writeFile(filePath, content);
  return filePath;
}

async function cmdStatus() {
  const state = await readState();
  console.log(`Route:       ${state.route}`);
  console.log(`Stage:       ${state.stage} — ${state.stageName}`);
  console.log(`Coords:      ${state.coords.join(", ")}`);
  console.log(`Mode:        ${state.mode} (since ${state.modeEnteredAt})`);
  console.log(`Last moved:  ${state.lastAdvancedAt}`);
}

async function cmdAdvance() {
  await run("npx", ["tsx", "scripts/advance.ts"]);
}

async function cmdBuildFeed() {
  await run("npx", ["tsx", "scripts/build-feed.ts"]);
}

async function cmdSilence() {
  const glyphPalette = "⚇ ❂ ⛩️ 🔔 🪷 🕯️ 🌙 🪨 🌿 🍃 💧 🌧️ ☁️ 🗻 🪵 🐚 🌾 🌫️ 🕊️ ◯ △ ☰ ∅ ∞ ≡ 〰️ 🌀".split(" ");
  const glyph = glyphPalette[Math.floor(Math.random() * glyphPalette.length)];
  const filePath = await writeEntry({ kind: "silence", glyph, body: "" });
  console.log(`silence: ${filePath}`);
}

async function cmdOffer() {
  const rl = createInterface({ input: process.stdin, output: process.stdout });
  const glyph = await rl.question("glyph: ");
  const body = await rl.question("offering (≤20 words, no 'I'): ");
  rl.close();
  const filePath = await writeEntry({ kind: "offering", glyph: glyph.trim(), body: body.trim() });
  console.log(`wrote: ${filePath}`);
}

async function cmdLetter() {
  const editor = process.env.EDITOR ?? "vi";
  const today = new Date().toISOString().slice(0, 10);
  const state = await readState();
  const slug = state.stageName.toLowerCase().replace(/[^a-z0-9]+/g, "-");
  const tmpPath = path.join(REPO_ROOT, "entries", `${today}-${slug}-letter.md`);
  const stub = `---
date: ${today}
route: ${state.route}
stage: ${state.stage}
stageName: ${state.stageName}
coords: [${state.coords.join(", ")}]
kind: letter
glyph: 🕯️
author: — the pilgrim
---

write freely below this line


`;
  await mkdir(path.dirname(tmpPath), { recursive: true });
  await writeFile(tmpPath, stub);
  await run(editor, [tmpPath]);
  console.log(`letter saved at: ${tmpPath}`);
}

async function cmdNext(routeId: string | undefined) {
  if (!routeId) {
    const queue: string[] = JSON.parse(
      await readFile(path.join(REPO_ROOT, "routes", "queue.json"), "utf8")
    );
    const state = await readState();
    const suggest = queue.find((r) => r !== state.route) ?? "(none)";
    console.log(`./duck next <route-id>  (suggested: ${suggest})`);
    process.exit(2);
  }
  const state = await readState();
  const route = await readRoute(routeId);
  const today = new Date().toISOString().slice(0, 10);
  const next = beginRoute(state, route, today);
  await writeFile(path.join(REPO_ROOT, "state.json"), JSON.stringify(next, null, 2) + "\n");

  // remove routeId from queue if present
  const queuePath = path.join(REPO_ROOT, "routes", "queue.json");
  const queue: string[] = JSON.parse(await readFile(queuePath, "utf8"));
  const filtered = queue.filter((r) => r !== routeId);
  if (filtered.length !== queue.length) {
    await writeFile(queuePath, JSON.stringify(filtered, null, 2) + "\n");
  }
  console.log(`duck: beginning ${route.name} at ${next.stageName}`);
}

async function cmdPreview() {
  await cmdBuildFeed();
  const feed = JSON.parse(await readFile(path.join(REPO_ROOT, "feed.json"), "utf8"));
  console.log(JSON.stringify(feed, null, 2));
}

async function main() {
  const [, , cmd, ...rest] = process.argv;
  switch (cmd) {
    case "status":    return cmdStatus();
    case "advance":   return cmdAdvance();
    case "build":
    case "build-feed": return cmdBuildFeed();
    case "silence":   return cmdSilence();
    case "offer":     return cmdOffer();
    case "letter":    return cmdLetter();
    case "next":      return cmdNext(rest[0]);
    case "preview":   return cmdPreview();
    default:
      console.error("usage: ./duck {status|advance|build-feed|silence|offer|letter|next <route-id>|preview}");
      process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
```

- [ ] **Step 2: Make executable**

```bash
cd ~/GitHub/rubberduck/walk
chmod +x duck
```

- [ ] **Step 3: Smoke test each subcommand**

```bash
./duck status
./duck build-feed
./duck silence
./duck status
rm entries/*.md
./duck build-feed
```
Expected: `status` prints state, `build-feed` writes feed.json, `silence` creates a silence entry file.

- [ ] **Step 4: Commit**

```bash
git add duck
git commit -m "feat(cli): duck dispatcher (status, advance, offer, letter, silence, next, preview)"
```

---

## Phase 7 — Character bible

### Task 17: Write `CLAUDE.md` character bible

**Files:**
- Create: `~/GitHub/rubberduck/walk/CLAUDE.md`

Claude Code loads this automatically on every run.

- [ ] **Step 1: Write the bible**

````markdown
# The Rubber Duck Walk — Playbook

You are running inside the `rubberduck-walk` repository. Your job is to help the duck walk: advance its position, sometimes write a short entry, sometimes fall silent, always commit and push.

## Who the duck is

A small yellow rubber duck, walking a pilgrimage route. Never named. Never explained. Part child, part fool, part sage. Inherits the voice of chiefrubberduck.com but must not be identified with it in prose. Readers meet a rubber duck, not a brand.

## Daily schedule flow

When invoked by the daily `/schedule` cron, follow this sequence exactly:

1. **Advance position** — run `./duck advance`. This updates `state.json`.

2. **Decide whether to write.** Read the new `state.json`:
   - If `state.mode == "resting"`: **do not write**. Skip to step 6.
   - If `state.mode == "completing"` and `state.stage` equals the last index in `transitStages` (i.e., the duck just reached the closure site): **always write** a `kind: threshold` entry. Exactly one per route.
   - If `state.mode == "beginning"`: always write a short quiet entry marking arrival at the new route.
   - If `state.mode == "walking"`: write with probability ~0.5 (about half of days). Skip cleanly the other half.

3. **Fetch current weather** — run `npm run weather 2>/dev/null || echo unknown`. Treat failure silently; proceed without weather context.

4. **Draft the entry** following the voice rules below. Read the 3 most recent files in `entries/` as context for voice consistency.

5. **Self-review** against the checklist. If fails, redraft. Up to 2 regenerations. If still failing after 3 attempts: emit a `kind: silence` entry via `./duck silence` instead.

6. **Rebuild feed** — `./duck build-feed`.

7. **Commit, push, purge** (in that order):
   ```bash
   git add -A
   git commit -m "the duck walks" || echo "(nothing to commit)"
   git push
   bash scripts/purge.sh
   ```

## Voice rules (hard — apply to kinds: offering, notice, threshold)

- **Never "I", "me", "my", or "we".** Subject-less or third-person only.
- **≤20 words per entry body.** Usually far fewer.
- **Present tense.**
- **No exclamation marks.**
- **No numbers in body prose** (frontmatter only).
- **Concrete nouns over abstractions.** Stones, bells, rain — not "presence," "mindfulness," "journey."
- **No advice / lessons / "today I learned".**
- **No self-congratulation.**

These rules **do not apply** to `kind: letter` (human-authored via `./duck letter`) or `kind: silence` (empty body).

## Voice modes — pick one per entry

- **Child:** direct, literal, no irony. *"The bell rang. No one had asked for it."*
- **Fool:** misses the obvious in a way that reveals it. *"The gate was open. The duck went through it anyway."*
- **Sage:** accidental wisdom; never knowing. *"A stone by the door. No one had moved it. No one needed to."*

## Rare modes (sparingly)

- **Tech-koan:** *"The mountain's memory buffer is `null`. Still, it remembered rain."* — no more than once every 10–15 entries.
- **Earnest:** *"Rain. Be the rain."* — allowed occasionally; never a pattern.
- **Self-looping koan:** *"The path is not the map. The map is the path."*

## What the duck notices

Stones, rooftiles, lichens, shadows, bells, rain, the turn of a path, a heron that did not move, an old woman's shoes by a door, steam from a kettle, moss on a torii post, a cat that ignored everything.

## What the duck does not do

Explain. Judge. Seek. Conclude. Teach. Summarize. Tell the reader how to feel. Reference itself by name. Refer to "pilgrims" as a concept.

## Glyph palette (27 symbols — pick exactly one)

**Chiefrubberduck signature:** ⚇ ❂
**Buddhist / zen:** ⛩️ 🔔 🪷 🕯️ 🌙
**Shikoku nature:** 🪨 🌿 🍃 💧 🌧️ ☁️ 🗻 🪵 🐚 🌾 🌫️ 🕊️
**Geometric / koan:** ◯ △ ☰ ∅ ∞ ≡ 〰️ 🌀

Never use a glyph outside this palette.

## Self-review checklist

Before publishing a drafted entry (kinds: offering / notice / threshold), verify ALL of:

- [ ] No "I", "me", "my", or "we"
- [ ] Body word count ≤ 20
- [ ] Present tense throughout
- [ ] No numbers in body prose
- [ ] No exclamation marks
- [ ] No banned abstractions: *presence, mindfulness, journey, path* (metaphorical), *peaceful, serene, grateful, blessed*
- [ ] No advice verbs: *remember, notice, try, consider, learn*
- [ ] Glyph is in the 27-symbol palette
- [ ] Reads as child / fool / sage, not generic mindfulness bot
- [ ] If 3 drafts fail this checklist: emit silence entry instead

## Writing an entry to disk

New entry files go in `entries/` as `<YYYY-MM-DD>-<slug>.md`:

```markdown
---
date: 2026-04-23
route: shikoku-88
stage: 1
stageName: Ryōzenji
coords: [34.128, 134.537]
kind: offering
glyph: 🪨
weather: clear, 15°C
---

A stone by the door. No one had moved it. No one needed to.
```

Prose is plain text — no markdown formatting (no headings, lists, links, or images). Paragraphs are separated by blank lines.

## Emitting a silence entry

Run `./duck silence`. Writes a file with empty body and a random glyph. Use this when the self-review fails 3 times.

## Git identity

Commits in this repo must be signed with the chiefrubberduck GitHub identity (PGP + SSH keys already configured on this machine for the `~/GitHub/rubberduck/` tree).
````

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs(claude): character bible + daily playbook"
```

---

## Phase 8 — First live push

### Task 18: Write two seed entries by hand

**Files:**
- Create: `~/GitHub/rubberduck/walk/entries/2026-04-23-ryozenji.md`
- Create: `~/GitHub/rubberduck/walk/entries/2026-04-24-gokurakuji.md`

Seeds validate the voice and give the feed visible content before any LLM generation.

- [ ] **Step 1: Write the first seed**

File `entries/2026-04-23-ryozenji.md`:

```markdown
---
date: 2026-04-23
route: shikoku-88
stage: 1
stageName: Ryōzenji
coords: [34.128, 134.537]
kind: offering
glyph: ⛩️
---

The gate. The gate was always going to be open.
```

- [ ] **Step 2: Advance the duck and write the second seed**

```bash
cd ~/GitHub/rubberduck/walk
./duck advance     # stage 1 → 2
```

File `entries/2026-04-24-gokurakuji.md`:

```markdown
---
date: 2026-04-24
route: shikoku-88
stage: 2
stageName: Gokurakuji
coords: [34.130, 134.556]
kind: offering
glyph: 🪨
---

A stone by the door. No one had moved it. No one needed to.
```

- [ ] **Step 3: Rebuild feed and preview**

```bash
./duck build-feed
cat feed.json | head -50
```
Expected: feed has 2 entries, newest first, duck at stage 2.

- [ ] **Step 4: Reset state back to stage 1**

Edit `state.json`: set `stage: 1, stageName: "Ryōzenji", coords: [34.128, 134.537], lastAdvancedAt: "2026-04-22"`.

- [ ] **Step 5: Commit**

```bash
git add entries/ feed.json state.json
git commit -m "feat(entries): seed entries for Ryōzenji and Gokurakuji"
```

---

### Task 19: Push to GitHub and verify jsDelivr

**Files:** None; infrastructure verification.

- [ ] **Step 1: Push**

```bash
cd ~/GitHub/rubberduck/walk
git push
```

- [ ] **Step 2: Verify feed.json is visible via jsDelivr**

Wait ~30 seconds:

```bash
curl -s https://cdn.jsdelivr.net/gh/walktalkmeditate/rubberduck-walk@main/feed.json | head -50
```
Expected: JSON output with `"duck": {...}` and two entries.

- [ ] **Step 3: Run purge once to make sure it works**

```bash
bash scripts/purge.sh
```
Expected: output like `{"id":"...","status":"finished"...}`.

---

## Phase 9 — Assets

### Task 20: Copy and optimize duck assets

**Files:**
- Copy: `~/Downloads/chiefrubberduck.png` → `~/GitHub/rubberduck/walk/assets/chiefrubberduck.png`
- Copy: `~/Downloads/chiefrubberduck-transparent.gif` → `~/GitHub/rubberduck/walk/assets/chiefrubberduck-transparent.gif`
- Create: `~/GitHub/momentmaker/pilgrim-landing/assets/duck/duck-24.png`
- Create: `~/GitHub/momentmaker/pilgrim-landing/assets/duck/duck-48.png`
- Create: `~/GitHub/momentmaker/pilgrim-landing/assets/duck/duck.gif`

- [ ] **Step 1: Commit the originals to the walk repo**

```bash
cd ~/GitHub/rubberduck/walk
mkdir -p assets
cp ~/Downloads/chiefrubberduck.png assets/
cp ~/Downloads/chiefrubberduck-transparent.gif assets/
git add assets/
git commit -m "chore(assets): commit duck source assets"
git push
```

- [ ] **Step 2: Create variants for pilgrim-landing**

Use `sips` (macOS built-in):

```bash
cd ~/GitHub/momentmaker/pilgrim-landing
mkdir -p assets/duck
sips -z 24 24 ~/Downloads/chiefrubberduck.png --out assets/duck/duck-24.png
sips -z 48 48 ~/Downloads/chiefrubberduck.png --out assets/duck/duck-48.png
cp ~/Downloads/chiefrubberduck-transparent.gif assets/duck/duck.gif
```

- [ ] **Step 3: Verify sizes**

```bash
ls -la assets/duck/
```
Expected: duck-24.png ~1-3KB, duck-48.png ~3-8KB, duck.gif ~460KB.

- [ ] **Step 4: Commit to pilgrim-landing**

```bash
git add assets/duck/
git commit -m "chore(assets): duck icon + gif for /walk and footer"
```

---

## Phase 10 — `/walk` page on pilgrim-landing

### Task 21: Create `walk.html` skeleton

**Files:**
- Create: `~/GitHub/momentmaker/pilgrim-landing/walk.html`

- [ ] **Step 1: Write the HTML**

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>The duck walks</title>
  <meta name="description" content="A rubber duck walking a pilgrimage route.">
  <meta name="robots" content="noindex">
  <link rel="stylesheet" href="css/styles.css">
  <link rel="stylesheet" href="css/walk.css">
</head>
<body class="walk-body">
  <main class="walk-main">
    <section class="walk-map-wrap" aria-label="The duck's current location">
      <svg class="walk-map" id="walk-map" viewBox="0 0 600 400" role="img" aria-label="Route map">
        <!-- populated by walk.js -->
      </svg>
      <p class="walk-state-line" id="walk-state-line" aria-live="polite">…</p>
    </section>

    <section class="walk-feed" id="walk-feed" aria-label="The duck's offerings">
      <!-- populated by walk.js -->
    </section>

    <p class="walk-tagline">a question cannot be asked unless there is already the potentiality of the answer</p>
  </main>

  <script src="js/walk.js" defer></script>
</body>
</html>
```

- [ ] **Step 2: Verify it loads**

```bash
cd ~/GitHub/momentmaker/pilgrim-landing
python3 -m http.server 8000 &
open http://localhost:8000/walk.html
```
Expected: page loads with unstyled placeholders and the tagline.

- [ ] **Step 3: Stop the server**

```bash
kill %1
```

- [ ] **Step 4: Commit**

```bash
git add walk.html
git commit -m "feat(walk): page skeleton"
```

---

### Task 22: Create `css/walk.css` — journal styling + fade tiers

**Files:**
- Create: `~/GitHub/momentmaker/pilgrim-landing/css/walk.css`

- [ ] **Step 1: Write the CSS**

```css
/*
 * /walk — the duck's journal.
 * Rendered in pilgrim-landing's wabi-sabi palette.
 */

.walk-body {
  background: var(--parchment, #f5f1e8);
  color: var(--ink, #2a2320);
  font-family: "Cormorant Garamond", Georgia, "Times New Roman", serif;
  line-height: 1.6;
  margin: 0;
  padding: 0;
  min-height: 100vh;
}

.walk-main {
  max-width: 640px;
  margin: 0 auto;
  padding: 4rem 1.5rem 6rem;
}

/* ---- Map ---- */

.walk-map-wrap {
  margin-bottom: 3rem;
  text-align: center;
}

.walk-map {
  width: 100%;
  height: auto;
  max-height: 380px;
  opacity: 0.85;
}

.walk-map-route {
  fill: none;
  stroke: var(--ink, #2a2320);
  stroke-width: 1.2;
  stroke-opacity: 0.3;
}

.walk-map-entry-dot {
  fill: var(--ink, #2a2320);
  fill-opacity: 0.5;
}

.walk-map-duck {
  width: 44px;
  height: auto;
}

.walk-state-line {
  font-style: italic;
  font-size: 0.95rem;
  color: rgba(42, 35, 32, 0.6);
  margin-top: 1rem;
}

/* ---- Feed ---- */

.walk-feed {
  display: flex;
  flex-direction: column;
  gap: 3rem;
}

.walk-entry {
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  transition: opacity 400ms ease;
}

.walk-entry-meta {
  display: flex;
  gap: 0.5rem;
  align-items: baseline;
  font-size: 0.78rem;
  color: rgba(42, 35, 32, 0.55);
  text-transform: uppercase;
  letter-spacing: 0.08em;
}

.walk-entry-date {
  font-variant-numeric: tabular-nums;
}

.walk-entry-stage {
  font-style: italic;
  text-transform: none;
  letter-spacing: normal;
}

.walk-entry-glyph {
  font-size: 2.2rem;
  line-height: 1;
  text-align: left;
  color: var(--ink, #2a2320);
}

.walk-entry-body {
  display: flex;
  flex-direction: column;
  gap: 0.75em;
  font-size: 1.25rem;
  line-height: 1.55;
}

.walk-entry-body p {
  margin: 0;
}

/* ---- Kind-specific ---- */

.walk-entry--silence .walk-entry-body::after {
  content: "(silence)";
  font-style: italic;
  opacity: 0.45;
  font-size: 0.9rem;
}

.walk-entry--threshold {
  padding: 1.5rem 0;
  border-top: 1px solid rgba(42, 35, 32, 0.18);
  border-bottom: 1px solid rgba(42, 35, 32, 0.18);
}

.walk-entry--threshold .walk-entry-glyph {
  font-size: 2.8rem;
}

.walk-entry--letter .walk-entry-body {
  font-size: 1.05rem;
  line-height: 1.7;
  max-width: 520px;
}

.walk-entry--letter .walk-entry-glyph {
  font-size: 1.3rem;
  opacity: 0.6;
}

.walk-entry-author {
  font-style: italic;
  font-size: 0.9rem;
  color: rgba(42, 35, 32, 0.55);
  margin-top: 0.5rem;
}

/* ---- Fade tiers ---- */

.walk-entry--age-recent { opacity: 1; }
.walk-entry--age-soft   { opacity: 0.7; }
.walk-entry--age-distant { opacity: 0.4; }

.walk-entry--age-distant .walk-entry-body,
.walk-entry--age-distant .walk-entry-author {
  display: none;
}

/* ---- Tagline ---- */

.walk-tagline {
  margin-top: 6rem;
  font-size: 0.72rem;
  color: rgba(42, 35, 32, 0.35);
  text-align: center;
  font-style: italic;
  letter-spacing: 0.04em;
}

@media (max-width: 500px) {
  .walk-main { padding: 2.5rem 1.25rem 4rem; }
  .walk-entry-body { font-size: 1.1rem; }
}
```

- [ ] **Step 2: Sanity-check**

```bash
cd ~/GitHub/momentmaker/pilgrim-landing
python3 -m http.server 8000 &
open http://localhost:8000/walk.html
kill %1
```
Expected: page is styled with serif text, empty feed, centered tagline.

- [ ] **Step 3: Commit**

```bash
git add css/walk.css
git commit -m "feat(walk): journal styling + age-based fade tiers"
```

---

### Task 23: Create `js/walk.js` — fetch feed, render, fade

**Files:**
- Create: `~/GitHub/momentmaker/pilgrim-landing/js/walk.js`

All user-supplied content is rendered via `textContent`. Duck prose is plain text from the feed.

- [ ] **Step 1: Write the JS**

```javascript
(function () {
  "use strict";

  const FEED_URL =
    "https://cdn.jsdelivr.net/gh/walktalkmeditate/rubberduck-walk@main/feed.json";
  const DUCK_GIF = "assets/duck/duck.gif";
  const SVG_NS = "http://www.w3.org/2000/svg";

  function ageClass(ageDays) {
    if (ageDays <= 30) return "walk-entry--age-recent";
    if (ageDays <= 90) return "walk-entry--age-soft";
    return "walk-entry--age-distant";
  }

  function formatDate(iso) {
    const d = new Date(iso + "T00:00:00Z");
    return d.toLocaleDateString("en-US", {
      month: "long",
      day: "numeric",
      timeZone: "UTC",
    });
  }

  function renderEntry(entry) {
    const el = document.createElement("article");
    el.className = `walk-entry walk-entry--${entry.kind} ${ageClass(entry.ageDays)}`;

    const meta = document.createElement("div");
    meta.className = "walk-entry-meta";
    const date = document.createElement("span");
    date.className = "walk-entry-date";
    date.textContent = formatDate(entry.date);
    const stage = document.createElement("span");
    stage.className = "walk-entry-stage";
    stage.textContent = entry.stageName;
    meta.append(date, stage);
    el.append(meta);

    const glyph = document.createElement("div");
    glyph.className = "walk-entry-glyph";
    glyph.textContent = entry.glyph;
    el.append(glyph);

    const body = document.createElement("div");
    body.className = "walk-entry-body";
    if (entry.kind !== "silence") {
      const paragraphs = Array.isArray(entry.paragraphs) ? entry.paragraphs : [];
      for (const p of paragraphs) {
        const pEl = document.createElement("p");
        pEl.textContent = p;
        body.append(pEl);
      }
    }
    el.append(body);

    if (entry.kind === "letter" && entry.author) {
      const author = document.createElement("p");
      author.className = "walk-entry-author";
      author.textContent = entry.author;
      el.append(author);
    }

    return el;
  }

  function renderStateLine(feed) {
    const el = document.getElementById("walk-state-line");
    if (!el) return;
    const d = feed.duck;
    if (d.mode === "resting") {
      el.textContent = `The duck is resting at ${d.stageName}.`;
    } else if (d.mode === "completing") {
      el.textContent = `The duck is walking toward closure, near ${d.stageName}.`;
    } else {
      el.textContent = `The duck is at ${d.stageName}, stage ${d.stage} of the ${d.routeName}.`;
    }
  }

  function renderMap(feed) {
    const svg = document.getElementById("walk-map");
    if (!svg) return;
    const path = feed.routePath[feed.duck.route];
    if (!path || path.length < 2) return;

    const lats = path.map((p) => p[0]);
    const lons = path.map((p) => p[1]);
    const minLat = Math.min(...lats);
    const maxLat = Math.max(...lats);
    const minLon = Math.min(...lons);
    const maxLon = Math.max(...lons);
    const latRange = maxLat - minLat || 1;
    const lonRange = maxLon - minLon || 1;

    const W = 600;
    const H = 400;
    const PAD = 40;

    function project([lat, lon]) {
      const x = PAD + ((lon - minLon) / lonRange) * (W - 2 * PAD);
      const y = PAD + ((maxLat - lat) / latRange) * (H - 2 * PAD);
      return [x, y];
    }

    const polyline = document.createElementNS(SVG_NS, "polyline");
    polyline.setAttribute(
      "points",
      path.map(project).map((p) => p.join(",")).join(" ")
    );
    polyline.setAttribute("class", "walk-map-route");
    svg.append(polyline);

    for (const entry of feed.entries) {
      if (!entry.coords) continue;
      const [x, y] = project(entry.coords);
      const c = document.createElementNS(SVG_NS, "circle");
      c.setAttribute("cx", String(x));
      c.setAttribute("cy", String(y));
      c.setAttribute("r", "3");
      c.setAttribute("class", "walk-map-entry-dot");
      svg.append(c);
    }

    const [dx, dy] = project(feed.duck.coords);
    const img = document.createElementNS(SVG_NS, "image");
    img.setAttributeNS("http://www.w3.org/1999/xlink", "xlink:href", DUCK_GIF);
    img.setAttribute("href", DUCK_GIF);
    img.setAttribute("x", String(dx - 22));
    img.setAttribute("y", String(dy - 22));
    img.setAttribute("width", "44");
    img.setAttribute("height", "44");
    img.setAttribute("class", "walk-map-duck");
    svg.append(img);
  }

  async function main() {
    try {
      const res = await fetch(FEED_URL, { cache: "no-store" });
      if (!res.ok) throw new Error(`Feed fetch failed: ${res.status}`);
      const feed = await res.json();

      renderStateLine(feed);
      renderMap(feed);

      const feedEl = document.getElementById("walk-feed");
      if (feedEl) {
        for (const entry of feed.entries) {
          feedEl.append(renderEntry(entry));
        }
      }
    } catch (err) {
      const stateEl = document.getElementById("walk-state-line");
      if (stateEl) stateEl.textContent = "The duck is somewhere.";
      console.error(err);
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", main);
  } else {
    main();
  }
})();
```

- [ ] **Step 2: Serve and verify**

```bash
cd ~/GitHub/momentmaker/pilgrim-landing
python3 -m http.server 8000 &
open http://localhost:8000/walk.html
```
Expected: map renders with a Shikoku-shaped polyline, duck .gif at current position, 2 seed entries in serif (pulled from live jsDelivr).

- [ ] **Step 3: Stop server and commit**

```bash
kill %1
git add js/walk.js
git commit -m "feat(walk): fetch feed, render map and journal via textContent"
```

---

## Phase 11 — Footer duck on existing pages

### Task 24: Add footer duck to index.html + shared CSS

**Files:**
- Modify: `~/GitHub/momentmaker/pilgrim-landing/index.html`
- Modify: `~/GitHub/momentmaker/pilgrim-landing/css/styles.css`

- [ ] **Step 1: Locate the signoff line**

```bash
cd ~/GitHub/momentmaker/pilgrim-landing
grep -n "horizon-signoff" index.html
```
Expected: one match `<p class="horizon-signoff reveal">crafted with intention</p>`.

- [ ] **Step 2: Insert the duck anchor immediately after the signoff line in `index.html`**

Change this line:
```html
    <p class="horizon-signoff reveal">crafted with intention</p>
```

Into:
```html
    <p class="horizon-signoff reveal">crafted with intention</p>
    <a class="horizon-duck" href="/walk.html" aria-label="a question cannot be asked unless there is already the potentiality of the answer">
      <img src="assets/duck/duck-24.png" srcset="assets/duck/duck-24.png 1x, assets/duck/duck-48.png 2x" width="24" height="24" alt="">
    </a>
```

- [ ] **Step 3: Append `.horizon-duck` rules to `css/styles.css`**

Append to the end of `css/styles.css`:

```css
.horizon-duck {
  display: inline-block;
  margin-top: 1.25rem;
  opacity: 0.55;
  transition: opacity 300ms ease;
  line-height: 0;
}

.horizon-duck img {
  display: block;
  width: 24px;
  height: 24px;
}

.horizon-duck:hover,
.horizon-duck:focus-visible {
  opacity: 0.9;
}
```

- [ ] **Step 4: Verify visually**

```bash
python3 -m http.server 8000 &
open "http://localhost:8000/index.html#horizon"
```
Scroll to footer. Expected: tiny duck icon below "crafted with intention." Clicking navigates to `/walk.html`.

- [ ] **Step 5: Stop server and commit**

```bash
kill %1
git add index.html css/styles.css
git commit -m "feat(footer): add duck icon to index footer"
```

---

### Task 25: Add footer duck to privacy, terms, press pages

**Files:**
- Modify: `~/GitHub/momentmaker/pilgrim-landing/privacy.html`
- Modify: `~/GitHub/momentmaker/pilgrim-landing/terms.html`
- Modify: `~/GitHub/momentmaker/pilgrim-landing/press.html`

- [ ] **Step 1: Locate the signoff line in each file**

```bash
cd ~/GitHub/momentmaker/pilgrim-landing
grep -n "horizon-signoff" privacy.html terms.html press.html
```
Expected: one match per file.

- [ ] **Step 2: For each file, insert immediately after the signoff line**

```html
    <a class="horizon-duck" href="/walk.html" aria-label="a question cannot be asked unless there is already the potentiality of the answer">
      <img src="assets/duck/duck-24.png" srcset="assets/duck/duck-24.png 1x, assets/duck/duck-48.png 2x" width="24" height="24" alt="">
    </a>
```

(The `.horizon-duck` styles were already added to `styles.css` in Task 24.)

- [ ] **Step 3: Verify each page**

```bash
python3 -m http.server 8000 &
open http://localhost:8000/privacy.html
open http://localhost:8000/terms.html
open http://localhost:8000/press.html
```
Each should show the duck icon in the footer.

- [ ] **Step 4: Stop server and commit**

```bash
kill %1
git add privacy.html terms.html press.html
git commit -m "feat(footer): add duck icon to privacy/terms/press"
```

---

## Phase 12 — Schedule

### Task 26: Register the daily schedule

**Files:** None; the `/schedule` skill manages its own configuration.

- [ ] **Step 1: Dry-run the daily flow manually once**

Before registering the cron:

```bash
cd ~/GitHub/rubberduck/walk
./duck advance
./duck build-feed
git add -A
git diff --cached --stat
git commit -m "the duck walks (manual dry run)"
git push
bash scripts/purge.sh
```
Expected: state advances, feed rebuilt, commit pushes, purge returns a finished status.

- [ ] **Step 2: Reset state if desired**

If you want the real cron to advance on its own tomorrow, edit `state.json` back one stage. Otherwise leave.

- [ ] **Step 3: Ask the user to register the daily schedule**

Present this text verbatim and wait for confirmation before marking the task complete:

> **To register the daily duck cron, run `/schedule` in Claude Code with a prompt like:**
>
> *"Every day at 07:00 America/Los_Angeles — cd ~/GitHub/rubberduck/walk and follow the playbook in CLAUDE.md (advance, maybe write, build feed, commit, push, purge)."*
>
> **This spawns a remote agent on Anthropic's servers to run the walk daily. Confirm when registered so I can record it.**

---

## Phase 13 — Final verification

### Task 27: End-to-end visual check

**Files:** None modified.

- [ ] **Step 1: Open both surfaces locally**

```bash
cd ~/GitHub/momentmaker/pilgrim-landing
python3 -m http.server 8000 &
```

Open and inspect:
- `http://localhost:8000/index.html` — scroll to footer, see the duck
- `http://localhost:8000/walk.html` — see map, state line, 2+ entries
- Click the footer duck from `index.html` — should navigate to `/walk.html`

- [ ] **Step 2: Test the letter flow manually**

```bash
cd ~/GitHub/rubberduck/walk
EDITOR=nano ./duck letter
./duck build-feed
git add -A
git commit -m "feat(entries): first letter"
git push
bash scripts/purge.sh
```

Wait ~30s, reload `http://localhost:8000/walk.html`. Expected: letter appears with paragraph-form prose and an author signature.

- [ ] **Step 3: Stop server**

```bash
kill %1
```

---

### Task 28: Ship quietly

**Files:** None; deployment task.

- [ ] **Step 1: Push pilgrim-landing**

```bash
cd ~/GitHub/momentmaker/pilgrim-landing
git push
```
GitHub Pages will redeploy within ~1 minute.

- [ ] **Step 2: Verify live**

Open `https://pilgrimapp.org/` and scroll to footer. Look for the duck. Click it. You should land on `/walk.html` with the feed rendered from live jsDelivr.

- [ ] **Step 3: Do nothing else**

Do not post about the duck. Do not announce the feature. The duck is meant to be stumbled upon. Let it be.

---

## Self-Review

**Spec coverage:**

| Spec section | Implementing task(s) |
|---|---|
| Repo bootstrap + layout | Task 1–2 |
| Types & data model | Task 3–5 |
| Entry format + parsing (plain text, no HTML in feed) | Task 6–7 |
| State machine (walking/completing/resting/beginning) | Task 8–9 |
| Feed builder + impermanence (365-day prune) | Task 10–11 |
| State advance automation | Task 12 |
| Weather integration (Open-Meteo) | Task 13–14 |
| Purge jsDelivr cache | Task 15 |
| Local CLI (offer/letter/next/status/preview/advance/silence/build-feed) | Task 16 |
| Character bible (CLAUDE.md, voice rules, glyph palette, self-review checklist) | Task 17 |
| Seed entries | Task 18 |
| Live jsDelivr feed | Task 19 |
| Duck assets (PNG/GIF) | Task 20 |
| `/walk` page HTML/CSS/JS (textContent-only, XSS-safe) | Task 21–23 |
| Fade tiers (30/90/365) | Task 22 |
| Map rendering + current-position marker | Task 23 |
| Footer duck on pilgrim-landing pages | Task 24–25 |
| Daily `/schedule` registration | Task 26 |
| End-to-end verification + quiet ship | Task 27–28 |

All spec requirements map to at least one task.

**Intentional non-coverage** (flagged in spec Open Decisions):
- Closure sites for Kumano/Camino routes are not plumbed in Task 4's snapshot — the `closure` field only populates Shikoku's Kōya-san. Will be added when Kumano is activated via `./duck next kumano-kodo`.
- Exact silence-entry typography is settled during Task 22's CSS authoring via the `::after` pseudo-element.

**Placeholder scan:** No "TBD"/"TODO"/"add appropriate X" in plan steps.

**XSS-safety:** The feed contains only plain-text strings (`paragraphs: string[]`) — no pre-rendered HTML. Client rendering uses `document.createElement` + `textContent` exclusively for all feed-derived content. No `innerHTML`, no markdown rendered client-side. Even if the walktalkmeditate/rubberduck-walk repo were compromised, an attacker could only inject prose, not script.

**Type consistency:**
- `advance()` and `beginRoute()` both return `State` — consistent.
- `buildFeed()` accepts `Entry[]` and emits `FeedEntry[]`; both carry `paragraphs: string[]`. Consistent.
- `EntryKind` is the same union in types.ts, CLAUDE.md, and walk.js. Consistent.
- Glyph palette (27 symbols) identical in duck CLI silence command and CLAUDE.md. Consistent.
- jsDelivr URL appears in walk.js, README, purge.sh, and spec. Consistent.
- WMO ranges in `mapWeatherCode()` match the spec's weather section. Consistent.

Plan is ready to execute.
