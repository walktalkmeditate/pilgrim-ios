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
- `/release ship` — archive, upload, tag, push
- `/release notes` — generate App Store "What's New" text
- `/release` (no subcommand) — guided full release flow

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
   - Fill in App Store Connect metadata (screenshots, description, "What's New")
   - Submit for App Review
   - Do NOT create a GitHub release or git tag until Apple approves — we've jumped ahead before and had to delete

## `/release notes` — Generate App Store Notes

1. Get commits since the last tag:
   ```bash
   git log $(git describe --tags --abbrev=0 2>/dev/null || git rev-list --max-parents=0 HEAD)..HEAD --oneline --no-merges
   ```
2. Read the commit messages and categorize changes into user-facing language
3. Draft "What's New" text in Pilgrim's voice — concise, warm, no marketing speak
4. Format for App Store (4000 character limit, but aim for 2-3 short paragraphs)
5. Present to the user for review and copy

Example tone:
```
Quieter walks, smoother paths.

- Breathing animation now pauses when you leave the app
- Walk history loads more gracefully
- Fixed a timing issue with voice transcription

Walk well.
```

## `/release` (no subcommand) — Guided Flow

Walk the user through the full release process interactively:

1. Run the check audit
2. If issues found, help fix them before continuing
3. Ask about version bump type and prepare the release
4. Ship when ready
5. Generate release notes
6. Offer to create a GitHub Release with the notes

## Important Notes

- The release script is at `scripts/release.sh` — use it for mechanical build steps
- ExportOptions are at `scripts/ExportOptions.plist` (team ID: YCF2TGZAX8)
- Never force-push or amend commits during release
- Always confirm with the user before uploading to App Store Connect or pushing tags
- The landing page repo is at `../pilgrim-landing` — after a release, consider updating the "Coming soon" text on pilgrimapp.org
