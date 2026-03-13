//
//  PermissionsView.swift
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

struct PermissionsView: View {

    @ObservedObject var viewModel: PermissionsViewModel
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text("Prepare for the journey")
                .font(Constants.Typography.displayMedium)
                .foregroundColor(.stone)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)

            Text("Pilgrim walks best with these")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .padding(.top, Constants.UI.Padding.small)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: Constants.UI.Padding.normal) {
                permissionCard(
                    icon: "location.fill",
                    title: "To walk with you",
                    description: "Track your route, distance, and pace",
                    granted: viewModel.locationGranted,
                    denied: viewModel.locationDenied,
                    shake: viewModel.shakeLocationCard,
                    required: true,
                    action: viewModel.requestLocation,
                    retryAction: viewModel.openSettings
                )

                permissionCard(
                    icon: "mic.fill",
                    title: "To hear your thoughts",
                    description: "Capture voice reflections along the way",
                    granted: viewModel.microphoneGranted,
                    denied: viewModel.microphoneDenied,
                    shake: viewModel.shakeMicrophoneCard,
                    required: true,
                    action: viewModel.requestMicrophone,
                    retryAction: viewModel.openSettings
                )

                permissionCard(
                    icon: "figure.walk",
                    title: "To count your steps",
                    description: "Measure steps as you move",
                    granted: viewModel.motionGranted,
                    denied: false,
                    shake: false,
                    required: false,
                    action: viewModel.requestMotion,
                    retryAction: nil
                )
            }
            .padding(.top, Constants.UI.Padding.big)
            .opacity(appeared ? 1 : 0)

            Spacer()
            Spacer()
        }
        .padding(.horizontal, Constants.UI.Padding.big)
        .background(warmParchment)
        .onAppear {
            viewModel.checkExistingPermissions()
            withAnimation(.easeInOut(duration: Constants.UI.Motion.gentle)) {
                appeared = true
            }
        }
    }

    private var warmParchment: some View {
        ZStack {
            Color.parchment
            Color.yellow.opacity(0.02)
        }
        .ignoresSafeArea()
    }

    private func permissionCard(
        icon: String,
        title: String,
        description: String,
        granted: Bool,
        denied: Bool,
        shake: Bool,
        required: Bool,
        action: @escaping () -> Void,
        retryAction: (() -> Void)?
    ) -> some View {
        VStack(spacing: Constants.UI.Padding.small) {
            HStack(spacing: Constants.UI.Padding.normal) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(.stone)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Constants.UI.Padding.small) {
                        Text(title)
                            .font(Constants.Typography.heading)
                            .foregroundColor(.ink)
                        if !required {
                            Text("(optional)")
                                .font(Constants.Typography.caption)
                                .foregroundColor(.fog)
                        }
                    }
                    Text(description)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }

                Spacer()

                grantButton(
                    granted: granted,
                    denied: denied,
                    required: required,
                    decided: !required && viewModel.motionDecided,
                    action: denied && retryAction != nil ? retryAction! : action
                )
            }
            .padding(Constants.UI.Padding.normal)
            .background(granted ? Color.moss.opacity(0.1) : Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
            .offset(x: shake ? -6 : 0)
            .animation(
                shake
                    ? .default.repeatCount(3, autoreverses: true).speed(6)
                    : .default,
                value: shake
            )

            if denied && required {
                Text("Pilgrim needs this to walk with you")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private func grantButton(
        granted: Bool,
        denied: Bool,
        required: Bool,
        decided: Bool,
        action: @escaping () -> Void
    ) -> some View {
        if granted {
            Image(systemName: "checkmark")
                .foregroundColor(.moss)
                .font(.subheadline.bold())
        } else if !required && decided {
            Text("Skipped")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        } else {
            Button(action: action) {
                Text(denied ? "Settings" : "Grant")
                    .font(.subheadline.bold())
                    .foregroundColor(.stone)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .overlay(
                        Capsule()
                            .stroke(Color.stone, lineWidth: 1.5)
                    )
            }
        }
    }
}
