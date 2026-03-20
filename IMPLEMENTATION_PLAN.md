# App Store Screenshot Automation — Phase 1

## Goal
Automated, repeatable screenshot capture of all key app screens with beautiful demo data, runnable with a single command.

## Phases
- [x] Phase 1: Demo mode infrastructure (launch arg, ScreenshotDataSeeder)
- [x] Phase 2: Add accessibility identifiers for UI test navigation
- [x] Phase 3: Create ScreenshotTests UI test target
- [x] Phase 4: Screenshot capture tests for all static screens
- [ ] Phase 5: Add UI test target in Xcode and verify

## Key Decisions
- Demo mode: `--demo-mode` launch argument, checked in AppDelegate
- Data: Custom `ScreenshotDataSeeder` (not DebugDataSeeder) with 5 curated, beautiful walks
- Guard: `#if DEBUG` on all demo code
- Output: `build/screenshots/` (gitignored)
- UI test target: `ScreenshotTests` (separate from UnitTests)
- Accessibility: Add identifiers only where needed for navigation

## Screens to Capture
1. Path tab (WalkStartView) — walk start with mode selector
2. Journal tab (HomeView) — walk history with multiple entries
3. Walk Summary — tap first walk, capture detail view
4. Settings — scrolled to show practice summary + cards

## Status
**Currently in Phase 1** — Building demo mode infrastructure
