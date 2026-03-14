//
//  PermissionsViewModel.swift
//
//  Pilgrim
//  Copyright (C) 2025-2026 Walk Talk Meditate contributors
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

import SwiftUI

class PermissionsViewModel: ObservableObject {

    @Published var locationGranted = false
    @Published var microphoneGranted = false
    @Published var motionGranted = false
    @Published var locationDenied = false
    @Published var microphoneDenied = false
    @Published var motionDecided = false
    @Published var shakeLocationCard = false
    @Published var shakeMicrophoneCard = false

    var canTransition: Bool { locationGranted && microphoneGranted }

    private let permissionManager: PermissionManager?
    private let onComplete: () -> Void
    private let skipInitialCheck: Bool

    init(permissionManager: PermissionManager?, onComplete: @escaping () -> Void, skipInitialCheck: Bool = false) {
        self.permissionManager = permissionManager
        self.onComplete = onComplete
        self.skipInitialCheck = skipInitialCheck
    }

    func checkExistingPermissions() {
        guard !skipInitialCheck, let pm = permissionManager else { return }
        locationGranted = pm.currentLocationStatus == .granted
        microphoneGranted = pm.isMicrophoneGranted
        motionGranted = pm.isMotionGranted
        if motionGranted { motionDecided = true }
    }

    func requestLocation() {
        permissionManager?.checkLocationPermission { [weak self] status in
            guard let self else { return }
            if status == .granted {
                self.locationGranted = true
                self.locationDenied = false
            } else {
                self.handleLocationDenied()
            }
        }
    }

    func requestMicrophone() {
        permissionManager?.checkMicrophonePermission { [weak self] granted in
            guard let self else { return }
            if granted {
                self.microphoneGranted = true
                self.microphoneDenied = false
            } else {
                self.handleMicrophoneDenied()
            }
        }
    }

    func requestMotion() {
        motionDecided = true
        permissionManager?.checkMotionPermission { [weak self] granted in
            self?.motionGranted = granted
        }
    }

    func handleLocationDenied() {
        locationDenied = true
        shakeLocationCard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.shakeLocationCard = false
        }
    }

    func handleMicrophoneDenied() {
        microphoneDenied = true
        shakeMicrophoneCard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.shakeMicrophoneCard = false
        }
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    func proceed() {
        motionDecided = true
        onComplete()
    }
}
