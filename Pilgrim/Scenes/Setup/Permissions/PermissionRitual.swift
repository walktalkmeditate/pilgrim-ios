//
//  PermissionRitual.swift
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

import Foundation

/// The "grant ritual" decisions for the permission screen: whether the
/// celebratory bell should sound when a permission is granted, and the
/// once-per-grant persistence that prevents it from replaying when the user
/// re-enters onboarding or relaunches.
///
/// The decision is a pure function so the bell-once-per-grant logic and the
/// `soundsEnabled` gate can be unit-tested without UserDefaults or audio.
enum PermissionRitual {

    enum Permission: String, CaseIterable {
        case location
        case microphone
        case motion
    }

    /// Should the grant bell fire for this permission right now?
    ///
    /// Pure: every input is passed in. The bell sounds only when the
    /// permission was just granted, the user keeps sounds on, and the bell
    /// hasn't already been played for this permission on a previous pass.
    static func shouldPlayBell(
        granted: Bool,
        soundsEnabled: Bool,
        alreadyPlayed: Bool
    ) -> Bool {
        granted && soundsEnabled && !alreadyPlayed
    }

    // MARK: - Persistence
    //
    // One Optional<Bool> flag per permission, no defaultValue: nil means
    // "bell never played", `true` means "already played". A defaultValue
    // would make the nil state unreadable (the UserPreference.Optional
    // trap), and there is no meaningful nil-is-valid choice to preserve here
    // beyond "not yet played" — which absence already represents.

    private static func bellPlayedPreference(for permission: Permission) -> UserPreference.Optional<Bool> {
        UserPreference.Optional<Bool>(key: "permissionBellPlayed.\(permission.rawValue)")
    }

    static func hasPlayedBell(for permission: Permission) -> Bool {
        bellPlayedPreference(for: permission).value ?? false
    }

    static func markBellPlayed(for permission: Permission) {
        bellPlayedPreference(for: permission).value = true
    }

    /// Decide using the persisted flag, then mark it played if the bell will
    /// fire — so a second grant event for the same permission reads
    /// `alreadyPlayed == true` and stays silent.
    static func consumeBellGrant(
        for permission: Permission,
        granted: Bool,
        soundsEnabled: Bool
    ) -> Bool {
        let shouldPlay = shouldPlayBell(
            granted: granted,
            soundsEnabled: soundsEnabled,
            alreadyPlayed: hasPlayedBell(for: permission)
        )
        if shouldPlay {
            markBellPlayed(for: permission)
        }
        return shouldPlay
    }
}
