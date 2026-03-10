//
//  SetupPermissionsView.swift
//
//  OutRun
//  Copyright (C) 2022 Tim Fraedrich <timfraedrich@icloud.com>
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

struct SetupPermissionsView: View {
    
    @Binding private var canContinue: Bool
    
    @State private var grantedLocationAccess = false
    @State private var grantedMicrophoneAccess = false
    @State private var grantedMotionAccess = false

    var body: some View {
        SetupStepBaseView(
            headline: "Permissions",
            description: "Pilgrim needs location access to track your route and microphone access to record voice notes."
        ) {
            VStack(spacing: Constants.UI.Padding.small) {

                PermissionView(
                    title: "Location",
                    subtitle: "Track your walking route",
                    granted: $grantedLocationAccess) {
                    } showPermissionMenu: {
                        PermissionManager.standard.checkLocationPermission { status in
                            grantedLocationAccess = status == .granted
                        }
                    }

                PermissionView(
                    title: "Microphone",
                    subtitle: "Record voice notes along the way",
                    granted: $grantedMicrophoneAccess) {
                    } showPermissionMenu: {
                        PermissionManager.standard.checkMicrophonePermission { granted in
                            grantedMicrophoneAccess = granted
                        }
                    }

                PermissionView(
                    title: "Motion",
                    subtitle: "Count your steps (optional)",
                    granted: $grantedMotionAccess) {
                    } showPermissionMenu: {
                        PermissionManager.standard.checkMotionPermission { granted in
                            grantedMotionAccess = granted
                        }
                    }

            }.padding(.top, Constants.UI.Padding.big)
        }
        .onAppear { checkExistingPermissions() }
        .onChange(of: shouldContinue) { shouldContinue in
            canContinue = shouldContinue
        }
    }

    private var shouldContinue: Bool { grantedLocationAccess }
    
    init(canContinue: Binding<Bool>) {
        self._canContinue = canContinue
    }

    private func checkExistingPermissions() {
        let pm = PermissionManager.standard
        grantedLocationAccess = pm.currentLocationStatus == .granted
        grantedMicrophoneAccess = pm.isMicrophoneGranted
        grantedMotionAccess = pm.isMotionGranted
    }
}

struct SetupPermissionsView_Previews: PreviewProvider {
    static var previews: some View {
        SetupPermissionsView(canContinue: .constant(false))
    }
}
