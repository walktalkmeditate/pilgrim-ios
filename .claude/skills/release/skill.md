---
name: release
description: Pilgrim iOS release management — readiness checks, version bumping, changelog generation, App Store submission, and post-release coordination. Use when preparing, shipping, or managing app releases.
user_invocable: true
---

# Pilgrim Release Manager

Manage the full release lifecycle for the Pilgrim iOS app.

## Subcommands

The user may invoke `/release` with an optional subcommand:
- `/release check` — readiness audit
- `/release prepare` — bump version, generate changelog, commit
- `/release ship` — archive, upload via the GHA workflow
- `/release whatsnew` — draft the App Store "What's New" text (4000-char field)
- `/release tag` — **after Apple approves**, cut the GitHub Release with a curated narrative changelog
- `/release` (no subcommand) — guided full release flow

### Two release-notes artifacts, two commands

Do not conflate these. They have different audiences and formats:

| Artifact | Audience | Length | Command | File |
|---|---|---|---|---|
| **App Store "What's New"** | End users browsing the App Store | 4000 chars max, aim for 200-400 | `/release whatsnew` | `build/whatsnew.txt` |
| **GitHub Release body** | Developers, power users, press | Long-form narrative, no cap | `/release tag` | `build/changelog.md` |

## `/release check` — Readiness Audit

Run a comprehensive pre-release check:

1. Run `scripts/release.sh check` to validate build, tests, and lint
2. Read `Pilgrim.xcodeproj/project.pbxproj` to confirm version and build numbers
3. Check for uncommitted changes via `git status`
4. Check that `Pilgrim/PrivacyInfo.xcprivacy` exists and is in the Xcode project
5. Verify `Pilgrim/Support Files/Info.plist` has no deprecated or incorrect values
6. Check for any TODO or FIXME in recently changed files
7. Report findings in a clear pass/fail checklist

## `/release prepare` — Prepare Release

Prepares the repo for a release. **Does NOT bump the build number locally** — the GHA Release workflow auto-increments the build number as part of its pipeline, and a local bump is wasted (the workflow increments past it, leaving a dangling build number in git history). This happened on 2026-04-08 with build 42.

1. Ask the user what type of release this is:
   - **Patch** (1.0.x) — bug fixes only
   - **Minor** (1.x.0) — new features, backwards compatible
   - **Major** (x.0.0) — breaking changes or major milestone
2. Determine the new version number from current `MARKETING_VERSION` in pbxproj
3. If the marketing version is changing, update `MARKETING_VERSION` in the pbxproj (both Debug and Release configurations for the Pilgrim target). Do NOT touch `CURRENT_PROJECT_VERSION` — GHA handles it.
4. Generate a changelog from commits since the last tag:
   ```bash
   git log $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD --oneline --no-merges
   ```
5. Show the changelog to the user for review
6. If the marketing version changed in step 3, commit with message: `release: prepare v{version}`. If only the changelog was reviewed (no pbxproj changes), skip the commit — there's nothing to commit.

## `/release ship` — Ship Release via GHA

**Do not run `scripts/release.sh archive/export/upload` locally** — the local machine lacks the iOS Distribution signing cert. The canonical release path is the GHA `Release` workflow, which archives, exports, signs, uploads to App Store Connect, bumps the build number, commits back to main, and tags.

1. Run `scripts/release.sh check` first (tests, lint, readiness) — abort if it fails
2. Ensure the release prep commit (if any) is pushed to main
3. Ask the user to confirm the target version (e.g., `1.2.0`) before triggering
4. Trigger the GHA Release workflow:
   ```bash
   gh workflow run release.yml --ref main -f version=X.Y.Z
   ```
5. Watch the run:
   ```bash
   gh run list --workflow=release.yml --limit 3
   gh run watch <run-id>
   ```
6. After the workflow succeeds:
   - Fast-forward local main: `git pull --ff-only origin main` (the workflow pushed a `release: bump build [skip ci]` commit)
   - The build appears in App Store Connect → Build Uploads, status "Processing"
7. Remind the user to:
   - Fill in App Store Connect metadata (screenshots, description, "What's New" — see `/release whatsnew`)
   - Submit for App Review
   - **Do NOT run `/release tag` until Apple actually approves.** We've jumped ahead before and had to delete a tag. Wait for the approval email / App Store Connect status change.

## `/release whatsnew` — App Store "What's New" Text

For the App Store Connect version record "What's New in This Version" field (4000-char limit). This is NOT the GitHub Release body — see `/release tag` for that.

1. Get commits since the last tag:
   ```bash
   git log $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD --oneline --no-merges
   ```
2. Read the commit messages and categorize changes into user-facing language
3. Draft "What's New" text in Pilgrim's voice — concise, warm, no marketing speak
4. Format for App Store (4000 character limit, but aim for 200-400 chars — 2-3 short paragraphs)
5. Present to the user for review and copy
6. Optionally save to `build/whatsnew.txt` so `scripts/release.sh changelog` will pick it up on the next run

Example tone:
```
Quieter walks, smoother paths.

- Breathing animation now pauses when you leave the app
- Walk history loads more gracefully
- Fixed a timing issue with voice transcription

Walk well.
```

## `/release tag` — Cut the GitHub Release (post-approval)

**Precondition: Apple has approved the release and it is either "Pending Developer Release" or already live on the App Store.** If the release is still in review, stop and tell the user to come back after approval — an approved release tag on GitHub that later gets rejected is embarrassing and has happened before.

This is a **curation task**, not just a mechanical tag-and-push. The output is a narrative GitHub Release body that reads like a product story, not a commit dump. The auto-generated output from `scripts/release.sh changelog` is the raw material — the AI's job is to turn it into prose.

### Steps

1. **Verify approval state.** Ask the user to confirm Apple approved the release. Optionally check:
   ```bash
   gh release list --limit 3
   git tag --sort=-creatordate | head -3
   ```
   to see where we left off. If a tag for this version already exists, stop.

2. **Confirm tag position.** Default to tagging at `HEAD` of `main`. Only tag at an earlier commit if the user explicitly asks — post-build doc/CI commits are legitimate parts of the version and the tag is a historical marker, not a reproducible-build receipt.

3. **Generate the raw changelog** as starting material:
   ```bash
   scripts/release.sh changelog
   ```
   This writes `build/changelog.md` in a flat feat/fix bullet format. Read it.

4. **Read the commit history directly too** — the script only picks up commits with conventional-commit prefixes (`feat:`, `fix:`, `style:`), which misses `docs:`, `chore:`, `refactor:`, merge commits, and commits without a type prefix. Some of those can still be release-relevant:
   ```bash
   git log $(git describe --tags --abbrev=0 2>/dev/null)..HEAD --oneline --no-merges
   ```

5. **Curate into narrative format.** OVERWRITE `build/changelog.md` with a curated version following the template below. This is the work:
   - **Collapse intra-feature iteration.** If a feature was developed over 15 commits (initial + bug fixes + lint fixes + design iterations), the release notes should list it as ONE headline feature with a prose description, not 15 bullets. The 1.2.0 whispers/cairns feature is the canonical example — it went through ~20 commits during PR #26 development, but the release notes describe it as two paragraphs.
   - **Separate user-visible from internal.** Ruthlessly. If a fix only helps CI, lint, or internal refactoring, it goes under "Behind the scenes" (or is dropped entirely). Only put fixes in the main "Fixes" section if a user would notice.
   - **Rewrite terse commit messages into prose.** "render map annotations above route line" → "Map pins render above the route line." "compact cairn preview in stone placement sheet" → drop it, internal UI iteration.
   - **Group by narrative, not by commit-type label.** Headline features get H3 sections with descriptive names. Small additions go under a generic "Other" subheading.
   - **No duplicate H1.** GitHub renders the release title as its own H1 above the body, so do NOT start `build/changelog.md` with `# Pilgrim X.Y.Z`. Start with the thematic italic subtitle or the intro paragraph.

6. **Show the curated notes to the user** before tagging. Expect edits. Iterate.

7. **Create the tag and push:**
   ```bash
   git tag -a v{version} -m "Release v{version} — {subtitle}"
   git push origin v{version}
   ```

8. **Create the GitHub Release** using the curated file:
   ```bash
   gh release create v{version} \
     --title "Pilgrim {version} — {subtitle}" \
     --notes-file build/changelog.md
   ```
   (`scripts/release.sh` also has `cmd_tag` which will use `build/changelog.md` automatically if it exists, so `scripts/release.sh tag v{version}` would also work — but the direct `gh` call is clearer about intent during a guided flow.)

9. **Verify** by opening the release URL returned by `gh release create` and eyeballing the rendered body. Common things to fix:
   - Duplicate H1 (if you forgot step 5's no-H1 rule) → `gh release edit v{version} --notes-file build/changelog.md` after removing the H1 from the file
   - Wrong title → `gh release edit v{version} --title "..."`

### The canonical example: Pilgrim 1.2.0

This is the format. Use it as the template. It's the actual 1.2.0 release body, shipped 2026-04-10, covering the Whispers & Cairns feature.

```markdown
_The path remembers._

This release adds the biggest new feature since Pilgrim launched: walks can now leave traces. Place a whisper or a cairn at a meaningful spot along your route, and feel what other walkers left before you. All anonymous. No accounts. No identities.

## What's new

### Whispers
Twenty-one curated audio gifts across seven moods — presence, wonder, gratitude, compassion, courage, lightness, stillness. Place them anywhere on the map. Walk within 42 meters of any whisper, yours or another walker's, and feel it arrive as a quiet pulse. Each mood has its own guide color.

### Cairns
Place virtual stones at meaningful spots. Start your own or add to a cairn left by someone who passed before you. Seven tiers from faint → small → medium → large → great → sacred → eternal (at 108 stones, the eternal cairn begins to glow). Proximity sensed within 108 meters. Distinct haptic patterns for whispers vs cairns.

### Map-first active walk
The stats panel now collapses into a quiet minimized bar so the map gets the full screen. Your intention mantra stays with you in the minimized state. Apple Maps–style bottom sheet with a peek-hint on walk start that teaches the gesture.

### Home Screen widget
A quiet rotating mantra for your home screen, changing daily. No data access, no configuration, no notifications.

## Fixes
- **Proximity haptics now fire reliably.** The CoreHaptics engine used to deallocate before the pattern finished playing — the whisper/cairn pulse never reached your wrist. Engine lifetime is now managed by a shared host.
- **Cairn timestamps preserved correctly** when stacking stones — `createdAt` is no longer overwritten.
- Share expiry labels now show the actual cached expiry date when reopening a shared walk.
- Map pins render above the route line and ignore taps more than 25 meters from the hit point.
- Whisper audio downloads to the local cache on first play instead of streaming every time.
- CoreStore fetches now run on the main thread.

## Behind the scenes
- CI development-cert cleanup rewritten in Python with proper ECDSA signatures (the previous bash+OpenSSL JWT was producing DER-encoded signatures that Apple's App Store Connect API silently rejected with 401, so the cleanup had been doing nothing for weeks).
- SwiftLint pre-commit hook to catch lint errors before push.
- TestFlight workflow gained an optional `version` input so marketing version bumps happen inline with a build.

---

**Build:** 46
**Minimum iOS:** 18.0
**Privacy manifest:** no data leaves the device. Whispers and cairns are shared anonymously via the Pilgrim collective API (location + metadata only, never identity).
```

### Format notes for future releases

- **Thematic italic subtitle** at the very top (one short line, italic). Pilgrim 1.2.0: *The path remembers.* Pick something that evokes the headline feature.
- **Intro paragraph** that frames what this release IS in 2-4 sentences. Skip marketing speak.
- **H2 `## What's new`** with H3 subsections per headline feature. Each subsection gets a full paragraph of prose, not a bullet list. This is where the curation work shows.
- **H2 `## Fixes`** — user-visible only. Bold the headline fixes (e.g. `**Proximity haptics now fire reliably.**`) and follow with a sentence or two of context if the fix is interesting. Plain bullets for the rest.
- **H2 `## Behind the scenes`** — optional, for interesting CI/infra/tooling work that developers browsing the repo might enjoy. Skip if nothing rises to that bar.
- **Footer separator** (`---`) followed by build metadata (`**Build:**`, `**Minimum iOS:**`, `**Privacy manifest:**`) in bold-label form.
- **Release title:** `Pilgrim {version} — {subtitle}`. The em dash is part of the convention.

## `/release` (no subcommand) — Guided Flow

Walk the user through the full release process interactively:

1. Run the check audit (`/release check`)
2. If issues found, help fix them before continuing
3. Ask about version bump type and prepare the release (`/release prepare`)
4. Ship when ready (`/release ship`)
5. Draft the App Store "What's New" text (`/release whatsnew`)
6. Wait for Apple approval — this is NOT a step the skill can automate. Tell the user to come back with `/release tag` once Apple approves.
7. On return, cut the GitHub Release (`/release tag`)

## Important Notes

- The release script is at `scripts/release.sh` — use it for mechanical build steps
- ExportOptions are at `scripts/ExportOptions.plist` (team ID: YCF2TGZAX8)
- Never force-push or amend commits during release
- Always confirm with the user before uploading to App Store Connect or pushing tags
- The landing page repo is at `../pilgrim-landing` — after a release, consider updating the feature section on pilgrimapp.org and regenerating the active walk screenshot if the UI changed
