# General Settings Page Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a General settings subpage with condensed Units toggle and Permissions status, restructure SettingsView with footer.

**Architecture:** New `GeneralSettingsView` with a `PermissionStatusViewModel` to read system permission APIs directly. Updated `SettingsView` replaces Units/About with a NavigationLink + attention dot + footer.

**Tech Stack:** SwiftUI, CoreLocation, AVFoundation, CoreMotion, XCTest

**Spec:** `docs/superpowers/specs/2026-03-16-general-settings-design.md`

---

## File Structure

| File | Action | Responsibility |
|------|--------|----------------|
| `Pilgrim/Scenes/Settings/GeneralSettingsView.swift` | Create | Units section + Permissions section UI |
| `Pilgrim/Scenes/Settings/PermissionStatusViewModel.swift` | Create | Read system permission APIs, expose four-state status per permission, handle request/openSettings actions |
| `Pilgrim/Scenes/Settings/SettingsView.swift` | Rewrite | General NavigationLink with attention dot, Audio section, footer |
| `UnitTests/PermissionStatusViewModelTests.swift` | Create | Test status mapping, attention dot logic |

**Note:** New `.swift` files must be added to the Xcode project target membership. After creating each new file, add it to the appropriate target in `Pilgrim.xcodeproj/project.pbxproj` (app target for `Pilgrim/` files, test target for `UnitTests/` files). The build step will fail if this is missed, confirming the file needs to be added.

---

## Chunk 1: PermissionStatusViewModel

### Task 1: PermissionStatusViewModel — tests and implementation

**Files:**
- Create: `UnitTests/PermissionStatusViewModelTests.swift`
- Create: `Pilgrim/Scenes/Settings/PermissionStatusViewModel.swift`

- [ ] **Step 1: Write the PermissionStatusViewModel with PermissionState enum and status reading**

Create `Pilgrim/Scenes/Settings/PermissionStatusViewModel.swift`:

```swift
import SwiftUI
import CoreLocation
import AVFoundation
import CoreMotion

enum PermissionState {
    case granted, notDetermined, denied, restricted
}

class PermissionStatusViewModel: ObservableObject {

    @Published var locationState: PermissionState = .notDetermined
    @Published var microphoneState: PermissionState = .notDetermined
    @Published var motionState: PermissionState = .notDetermined

    private let permissionManager = PermissionManager.standard

    var needsAttention: Bool {
        let location = locationState
        let microphone = microphoneState
        return (location == .denied || location == .notDetermined)
            || (microphone == .denied || microphone == .notDetermined)
    }

    init() {
        refresh()
    }

    func refresh() {
        locationState = Self.readLocationState()
        microphoneState = Self.readMicrophoneState()
        motionState = Self.readMotionState()
    }

    func requestLocation() {
        permissionManager.checkLocationPermission { [weak self] (_: PermissionManager.LocationPermissionStatus) in
            self?.refresh()
        }
    }

    func requestMicrophone() {
        permissionManager.checkMicrophonePermission { [weak self] _ in
            self?.refresh()
        }
    }

    func requestMotion() {
        permissionManager.checkMotionPermission { [weak self] _ in
            self?.refresh()
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    static func readLocationState() -> PermissionState {
        switch CLLocationManager().authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    static func readMicrophoneState() -> PermissionState {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: return .granted
        case .undetermined: return .notDetermined
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    static func readMotionState() -> PermissionState {
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        @unknown default: return .denied
        }
    }
}
```

- [ ] **Step 2: Write tests for PermissionStatusViewModel**

Create `UnitTests/PermissionStatusViewModelTests.swift`:

```swift
import XCTest
@testable import Pilgrim

final class PermissionStatusViewModelTests: XCTestCase {

    func testNeedsAttention_allGranted_returnsFalse() {
        let vm = PermissionStatusViewModel()
        vm.locationState = .granted
        vm.microphoneState = .granted
        vm.motionState = .notDetermined
        XCTAssertFalse(vm.needsAttention)
    }

    func testNeedsAttention_locationDenied_returnsTrue() {
        let vm = PermissionStatusViewModel()
        vm.locationState = .denied
        vm.microphoneState = .granted
        XCTAssertTrue(vm.needsAttention)
    }

    func testNeedsAttention_microphoneNotDetermined_returnsTrue() {
        let vm = PermissionStatusViewModel()
        vm.locationState = .granted
        vm.microphoneState = .notDetermined
        XCTAssertTrue(vm.needsAttention)
    }

    func testNeedsAttention_locationRestricted_returnsFalse() {
        let vm = PermissionStatusViewModel()
        vm.locationState = .restricted
        vm.microphoneState = .granted
        XCTAssertFalse(vm.needsAttention)
    }

    func testNeedsAttention_motionDenied_doesNotAffect() {
        let vm = PermissionStatusViewModel()
        vm.locationState = .granted
        vm.microphoneState = .granted
        vm.motionState = .denied
        XCTAssertFalse(vm.needsAttention)
    }

    func testReadMicrophoneState_returnsValidState() {
        let state = PermissionStatusViewModel.readMicrophoneState()
        XCTAssertTrue([.granted, .notDetermined, .denied].contains(state))
    }

    func testReadMotionState_returnsValidState() {
        let state = PermissionStatusViewModel.readMotionState()
        XCTAssertTrue([.granted, .notDetermined, .denied, .restricted].contains(state))
    }

    func testReadLocationState_returnsValidState() {
        let state = PermissionStatusViewModel.readLocationState()
        XCTAssertTrue([.granted, .notDetermined, .denied, .restricted].contains(state))
    }
}
```

- [ ] **Step 3: Build and run tests**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:UnitTests/PermissionStatusViewModelTests 2>&1 | tail -20
```

Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Scenes/Settings/PermissionStatusViewModel.swift UnitTests/PermissionStatusViewModelTests.swift
git commit -m "feat: add PermissionStatusViewModel with four-state permission reading"
```

---

## Chunk 2: GeneralSettingsView

### Task 2: GeneralSettingsView — Units and Permissions sections

**Files:**
- Create: `Pilgrim/Scenes/Settings/GeneralSettingsView.swift`

- [ ] **Step 1: Create GeneralSettingsView**

Create `Pilgrim/Scenes/Settings/GeneralSettingsView.swift`:

```swift
import SwiftUI

struct GeneralSettingsView: View {

    @StateObject private var permissionVM = PermissionStatusViewModel()
    @State private var isMetric = UserPreferences.distanceMeasurementType.safeValue == .kilometers

    var body: some View {
        List {
            unitsSection
            permissionsSection
        }
        .scrollContentBackground(.hidden)
        .background(Color.parchment)
        .navigationTitle("General")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("General")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .onAppear { permissionVM.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
            permissionVM.refresh()
        }
    }

    // MARK: - Units

    private var unitsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Units")
                        .font(Constants.Typography.body)
                    Spacer()
                    Picker("", selection: $isMetric) {
                        Text("Metric").tag(true)
                        Text("Imperial").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                    .onChange(of: isMetric) { _, metric in
                        applyUnitSystem(metric: metric)
                    }
                }
                Text(isMetric ? "km · min/km · m" : "mi · min/mi · ft")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        } header: {
            Text("Units")
                .font(Constants.Typography.caption)
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        Section {
            permissionRow(
                icon: "location.fill",
                title: "Location",
                subtitle: "Track your route",
                state: permissionVM.locationState,
                onGrant: permissionVM.requestLocation
            )
            permissionRow(
                icon: "mic.fill",
                title: "Microphone",
                subtitle: "Record reflections",
                state: permissionVM.microphoneState,
                onGrant: permissionVM.requestMicrophone
            )
            permissionRow(
                icon: "figure.walk",
                title: "Motion",
                subtitle: "Count your steps",
                state: permissionVM.motionState,
                onGrant: permissionVM.requestMotion
            )
        } header: {
            Text("Permissions")
                .font(Constants.Typography.caption)
        }
    }

    private func permissionRow(
        icon: String,
        title: String,
        subtitle: String,
        state: PermissionState,
        onGrant: @escaping () -> Void
    ) -> some View {
        HStack(spacing: Constants.UI.Padding.normal) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.stone)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Text(subtitle)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }

            Spacer()

            permissionAction(state: state, onGrant: onGrant)
        }
    }

    @ViewBuilder
    private func permissionAction(state: PermissionState, onGrant: @escaping () -> Void) -> some View {
        switch state {
        case .granted:
            Image(systemName: "checkmark")
                .foregroundColor(.moss)
                .font(Constants.Typography.caption)
        case .notDetermined:
            Button("Grant", action: onGrant)
                .font(Constants.Typography.button)
                .foregroundColor(.stone)
        case .denied:
            Button("Settings", action: permissionVM.openSettings)
                .font(Constants.Typography.button)
                .foregroundColor(.stone)
        case .restricted:
            Text("Restricted")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
    }

    // MARK: - Unit System

    private func applyUnitSystem(metric: Bool) {
        if metric {
            UserPreferences.distanceMeasurementType.value = .kilometers
            UserPreferences.altitudeMeasurementType.value = .meters
            UserPreferences.speedMeasurementType.value = .minutesPerLengthUnit(from: .kilometers)
            UserPreferences.weightMeasurementType.value = .kilograms
            UserPreferences.energyMeasurementType.value = .kilojoules
        } else {
            UserPreferences.distanceMeasurementType.value = .miles
            UserPreferences.altitudeMeasurementType.value = .feet
            UserPreferences.speedMeasurementType.value = .minutesPerLengthUnit(from: .miles)
            UserPreferences.weightMeasurementType.value = .pounds
            UserPreferences.energyMeasurementType.value = .kilocalories
        }
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Pilgrim/Scenes/Settings/GeneralSettingsView.swift
git commit -m "feat: add GeneralSettingsView with units toggle and permissions status"
```

---

## Chunk 3: SettingsView rewrite

### Task 3: Rewrite SettingsView — General link, attention dot, footer

**Files:**
- Modify: `Pilgrim/Scenes/Settings/SettingsView.swift`

- [ ] **Step 1: Rewrite SettingsView**

Replace the entire contents of `Pilgrim/Scenes/Settings/SettingsView.swift` with:

```swift
import SwiftUI

struct SettingsView: View {

    @StateObject private var permissionVM = PermissionStatusViewModel()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        GeneralSettingsView()
                    } label: {
                        HStack {
                            Text("General")
                                .font(Constants.Typography.body)
                            Spacer()
                            if permissionVM.needsAttention {
                                Circle()
                                    .fill(Color.rust)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        SoundSettingsView()
                    } label: {
                        HStack {
                            Text("Sounds")
                                .font(Constants.Typography.body)
                            Spacer()
                            Text(UserPreferences.soundsEnabled.value ? "On" : "Off")
                                .font(Constants.Typography.caption)
                                .foregroundColor(.fog)
                        }
                    }

                    NavigationLink {
                        TalkSettingsView()
                    } label: {
                        Text("Talks")
                            .font(Constants.Typography.body)
                    }
                } header: {
                    Text("Audio")
                        .font(Constants.Typography.caption)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.parchment)
            .safeAreaInset(edge: .bottom) {
                footer
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                }
            }
            .onAppear { permissionVM.refresh() }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                permissionVM.refresh()
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 4) {
            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog.opacity(0.3))
            Text("crafted with intention")
                .font(Constants.Typography.body.italic())
                .foregroundColor(.fog.opacity(0.25))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Constants.UI.Padding.breathingRoom)
        .padding(.bottom, Constants.UI.Padding.normal)
    }
}
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator build 2>&1 | tail -5
```

Expected: BUILD SUCCEEDED

- [ ] **Step 3: Run all tests to verify nothing broke**

Run:
```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -workspace Pilgrim.xcworkspace -scheme Pilgrim -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' 2>&1 | tail -20
```

Expected: All tests PASS.

- [ ] **Step 4: Commit**

```bash
git add Pilgrim/Scenes/Settings/SettingsView.swift
git commit -m "feat: restructure SettingsView with General link, attention dot, and footer"
```
