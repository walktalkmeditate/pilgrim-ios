# Auto-Detect Units — Design Spec

## Summary

Auto-detect the user's region at first launch and set metric/imperial units accordingly. Update the units label in settings to include temperature.

## Motivation

A pilgrimage app used internationally should just know the right units. Someone walking the Camino shouldn't have to dig into settings to switch from miles to kilometers. And now that the app collects weather data, the units label should reflect temperature.

## Design

### Auto-Detect at First Launch

During the setup flow, right before `UserPreferences.isSetUp` is set to `true` (in `BreathTransitionView`), call the existing `applyUnitSystem(metric:)` logic with the value of `Locale.current.usesMetricSystem`.

- No new UI in the setup flow
- No new preference keys
- Reuses the same unit-setting logic that `GeneralSettingsView.applyUnitSystem()` already uses
- Sets all 5 measurement preferences at once: distance, altitude, speed, weight, energy
- First launch only — never overrides an existing user preference
- The Settings toggle will show the correct selection from the start

The `applyUnitSystem` logic currently lives as a private method on `GeneralSettingsView`. It needs to be extracted to a shared location (e.g., a static method on a utility or on `UserPreferences` itself) so both the setup flow and settings view can call it.

### Updated Units Label

Change the units label in `GeneralSettingsView` from:

- Metric: `km · min/km · m`
- Imperial: `mi · min/mi · ft`

To:

- Metric: `km · min/km · m · °C`
- Imperial: `mi · min/mi · ft · °F`

Temperature remains tied to the metric/imperial toggle — no separate temperature preference. This matches the current behavior where `formattedTemperature(imperial:)` derives its boolean from the distance preference.

## Scope

### In scope

- Extract `applyUnitSystem(metric:)` to a shared location
- Call it during setup with `Locale.current.usesMetricSystem`
- Update units label strings to include temperature

### Out of scope

- Separate temperature preference (tied to metric/imperial toggle)
- Wind speed units (displayed qualitatively, no numeric conversion needed)
- Units selection step in the setup flow
- Re-detecting locale after first launch
- Formalizing a `temperatureMeasurementType` preference

## Risks

- **Locale edge cases**: `Locale.current.usesMetricSystem` returns `false` only for US, Liberia, and Myanmar locales. UK users get metric (correct for distance/altitude, but they colloquially use miles). This is an acceptable trade-off — the user can always change it in settings.
