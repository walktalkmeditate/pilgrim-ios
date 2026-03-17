# General Settings Page

## Summary

Add a General settings subpage containing a condensed Units toggle and a Permissions status section. Restructure the main SettingsView to replace the About section with a subtle footer.

## Motivation

- Users who chose "Allow Once" for location during setup have no way to see or manage permission status after setup completes
- Users who skipped the optional Motion permission have no way to enable it later
- The Units section takes 4 rows for what is effectively a binary toggle
- The About section wastes a full List section on a single version string

## Design

### SettingsView (updated)

Two sections (General, Audio) plus a centered footer. The About section is removed entirely.

```
┌─────────────────────────────────────┐
│ General                     ●    ›  │
├─────────────────────────────────────┤
│ Sounds                    On     ›  │
│ Talks                            ›  │
└─────────────────────────────────────┘

                  1.2.0
          crafted with intention
```

- **General row**: NavigationLink to `GeneralSettingsView`. Shows a small attention dot (rust color) if any required permission (Location, Microphone) is not granted. No dot when all permissions are satisfied. Permissions in `.restricted` state do not trigger the dot (user cannot resolve them).
- **Footer**: Version number in `Constants.Typography.caption`, `.fog.opacity(0.3)`. Tagline "crafted with intention" in `Constants.Typography.body` italic, `.fog.opacity(0.25)`. Both centered. `breathingRoom` padding above.

### GeneralSettingsView (new)

Two sections: Units and Permissions.

#### Units Section

Single row with segmented picker and a live subtitle:

```
Units
┌─────────────────────────────────────┐
│ Units    [Metric | Imperial]        │
│ km · min/km · m                     │
└─────────────────────────────────────┘
```

- Segmented picker toggles between Metric and Imperial
- Subtitle updates live: "km · min/km · m" (metric) or "mi · min/mi · ft" (imperial)
- Subtitle styled as `Constants.Typography.caption`, `.fog` color
- Applies the same `applyUnitSystem(metric:)` logic currently in `SettingsView`

#### Permissions Section

Three rows, one per permission. Each row has: SF Symbol icon, title, subtitle explaining purpose, and a status indicator.

```
Permissions
┌─────────────────────────────────────┐
│ 📍 Location           ✓ Granted    │
│    Track your route                 │
│ 🎤 Microphone         ✓ Granted    │
│    Record reflections               │
│ 🚶 Motion              Grant ›     │
│    Count your steps                 │
└─────────────────────────────────────┘
```

**Permission row states:**

| State | Right side | Tap action |
|-------|-----------|------------|
| Granted | Checkmark in `.moss` | None (not interactive) |
| Not determined | "Grant" button in `.stone` | Trigger system permission prompt |
| Denied | "Settings" button in `.stone` | Open iOS Settings via `UIApplication.openSettingsURLString` |
| Restricted | "Restricted" label in `.fog` | None (not interactive) |

All four states apply to all three permissions. The existing `PermissionManager.currentLocationStatus` conflates `.notDetermined` with `.denied` — the view must read `CLLocationManager().authorizationStatus` directly to distinguish them. For microphone, use `AVAudioSession.sharedInstance().recordPermission` (.undetermined / .denied / .granted). For motion, use `CMMotionActivityManager.authorizationStatus()` (.notDetermined / .denied / .authorized / .restricted).

**Icons** (SF Symbols, matching setup screen):
- Location: `location.fill`
- Microphone: `mic.fill`
- Motion: `figure.walk`

**Subtitles** (caption style, fog color):
- Location: "Track your route"
- Microphone: "Record reflections"
- Motion: "Count your steps"

**Live status updates**: Permission status is checked on `onAppear` and when the app returns to foreground (via `NotificationCenter` for `UIApplication.willEnterForegroundNotification`), so if a user goes to iOS Settings and changes a permission, the view updates when they come back.

## Files

| File | Action |
|------|--------|
| `Pilgrim/Scenes/Settings/GeneralSettingsView.swift` | Create |
| `Pilgrim/Scenes/Settings/SettingsView.swift` | Rewrite — remove Units and About sections, add General NavigationLink with attention dot, add footer |
| `Pilgrim/Models/PermissionManager.swift` | No changes — view reads system APIs directly for granular status |

## Dependencies

- `PermissionManager.standard` for checking/requesting permissions
- `UserPreferences` for unit system state
- `Constants.Typography` and semantic colors for styling
- Existing localization keys from setup (or inline English strings for permission subtitles)

## Out of Scope

- HealthKit sync toggle (separate feature)
- Changing the initial setup flow
- Wiring `insufficientPermission` publisher to walk UI (separate bug fix)
