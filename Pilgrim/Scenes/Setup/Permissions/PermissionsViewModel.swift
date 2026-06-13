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
    @Published var microphoneDecided = false
    @Published var motionDecided = false
    @Published var shakeLocationCard = false
    @Published var locationPulse = false
    @Published var microphonePulse = false
    @Published var motionPulse = false

    var canTransition: Bool { locationGranted }

    private let permissionManager: PermissionManager?
    private let onComplete: () -> Void
    private let skipInitialCheck: Bool

    /// Injectable so unit tests can assert "bell fired / did not fire"
    /// without touching audio. Production wires the real BellPlayer path.
    private let playBell: () -> Void

    init(
        permissionManager: PermissionManager?,
        onComplete: @escaping () -> Void,
        skipInitialCheck: Bool = false,
        playBell: (() -> Void)? = nil
    ) {
        self.permissionManager = permissionManager
        self.onComplete = onComplete
        self.skipInitialCheck = skipInitialCheck
        self.playBell = playBell ?? PermissionsViewModel.playGrantBell
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
                self.celebrateGrant(.location)
            } else {
                self.handleLocationDenied()
            }
        }
    }

    func requestMicrophone() {
        microphoneDecided = true
        permissionManager?.checkMicrophonePermission { [weak self] granted in
            guard let self else { return }
            if granted {
                self.microphoneGranted = true
                self.microphoneDenied = false
                self.celebrateGrant(.microphone)
            } else {
                self.microphoneDenied = true
            }
        }
    }

    func requestMotion() {
        motionDecided = true
        permissionManager?.checkMotionPermission { [weak self] granted in
            guard let self else { return }
            self.motionGranted = granted
            if granted { self.celebrateGrant(.motion) }
        }
    }

    func handleLocationDenied() {
        locationDenied = true
        shakeLocationCard = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.shakeLocationCard = false
        }
    }

    /// The grant ritual: a one-shot bell (once per permission, persisted) and
    /// checkmark pulse when a permission is granted. The bell honors
    /// `soundsEnabled`; Reduce Motion keeps the (meaningful) bell but skips the
    /// pulse. A subtle success haptic mirrors the welcome flow's footprint
    /// haptics for tactile coherence.
    func celebrateGrant(_ permission: PermissionRitual.Permission) {
        let shouldBell = PermissionRitual.consumeBellGrant(
            for: permission,
            granted: true,
            soundsEnabled: UserPreferences.soundsEnabled.value
        )

        if shouldBell {
            playBell()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }

        guard !UIAccessibility.isReduceMotionEnabled else { return }
        pulse(permission)
    }

    /// One-shot pulse: flip the flag on (the view springs the checkmark to
    /// 1.15), then off after the grow settles so it springs back to 1.0.
    /// A single bool drives a `.animation(value:)` scale — no @State array
    /// mutated inside a repeating animation (CLAUDE.md resource-safety rule).
    private func pulse(_ permission: PermissionRitual.Permission) {
        setPulse(permission, true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.setPulse(permission, false)
        }
    }

    private func setPulse(_ permission: PermissionRitual.Permission, _ value: Bool) {
        switch permission {
        case .location: locationPulse = value
        case .microphone: microphonePulse = value
        case .motion: motionPulse = value
        }
    }

    private static func playGrantBell() {
        guard let bellId = UserPreferences.meditationEndBellId.value,
              let asset = AudioManifestService.shared.asset(byId: bellId),
              AudioFileStore.shared.isAvailable(asset) else { return }
        BellPlayer.shared.play(asset, volume: 0.5, withHaptic: false)
    }

    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }

    func proceed() {
        microphoneDecided = true
        motionDecided = true
        onComplete()
    }
}
