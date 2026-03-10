//
//  PermissionManager.swift
//
//  OutRun
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import CoreLocation
import CoreMotion
import AVFoundation

class PermissionManager: NSObject, CLLocationManagerDelegate {

    static let standard = PermissionManager()

    override init() {
        super.init()
        self.locationManager.delegate = self
    }

    // MARK: Location

    private let locationManager = CLLocationManager()
    private var locationPermissionClosures: [(LocationPermissionStatus) -> Void] = []
    private var motionActivityManager: CMMotionActivityManager?

    var currentLocationStatus: LocationPermissionStatus {
        switch locationManager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .restricted: return .restricted
        case .notDetermined: return .denied
        default: return .denied
        }
    }

    func checkLocationPermission(closure: @escaping (LocationPermissionStatus) -> Void) {
        DispatchQueue.main.async {
            switch self.locationManager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                closure(.granted)
            case .notDetermined:
                let shouldRequest = self.locationPermissionClosures.isEmpty
                self.locationPermissionClosures.append(closure)
                if shouldRequest {
                    self.locationManager.requestWhenInUseAuthorization()
                }
            default:
                closure(.denied)
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            var permissionStatus: LocationPermissionStatus = .denied

            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                permissionStatus = .granted
            case .notDetermined:
                return
            default:
                break
            }

            let closures = self.locationPermissionClosures
            self.locationPermissionClosures = []
            closures.forEach { $0(permissionStatus) }
        }
    }

    enum LocationPermissionStatus {
        case granted, restricted, denied, error
    }

    // MARK: Microphone

    var isMicrophoneGranted: Bool {
        AVAudioSession.sharedInstance().recordPermission == .granted
    }

    func checkMicrophonePermission(closure: @escaping (Bool) -> Void) {
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted:
            closure(true)
        case .undetermined:
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                DispatchQueue.main.async { closure(granted) }
            }
        default:
            closure(false)
        }
    }

    // MARK: Motion

    var isMotionGranted: Bool {
        CMMotionActivityManager.authorizationStatus() == .authorized
    }

    func checkMotionPermission(closure: @escaping (Bool) -> Void) {
        switch CMMotionActivityManager.authorizationStatus() {
        case .authorized:
            closure(true)
        case .notDetermined:
            motionActivityManager = CMMotionActivityManager()
            motionActivityManager?.queryActivityStarting(from: Date(), to: Date(), to: .main) { [weak self] (activity, error) in
                self?.motionActivityManager = nil
                let auth = CMPedometer.authorizationStatus()
                switch auth {
                case .authorized:
                    closure(true)
                default:
                    closure(false)
                }
            }
        default:
            closure(false)
        }
    }

}
