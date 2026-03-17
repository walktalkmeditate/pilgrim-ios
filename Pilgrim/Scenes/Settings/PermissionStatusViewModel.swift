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
