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

struct PermissionCardConfig {
    let icon: String
    let title: String
    let description: String
    let granted: Bool
    let denied: Bool
    let shake: Bool
    let required: Bool
    let action: () -> Void
    let retryAction: (() -> Void)?
}

struct PermissionsView: View {

    @ObservedObject var viewModel: PermissionsViewModel
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            Text(LS["Permissions.Headline"])
                .font(Constants.Typography.displayMedium)
                .foregroundColor(.stone)
                .multilineTextAlignment(.center)
                .opacity(appeared ? 1 : 0)

            Text(LS["Permissions.Subtitle"])
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
                .padding(.top, Constants.UI.Padding.small)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: Constants.UI.Padding.normal) {
                permissionCard(PermissionCardConfig(
                    icon: "location.fill",
                    title: LS["Permissions.Location.Title"],
                    description: LS["Permissions.Location.Description"],
                    granted: viewModel.locationGranted,
                    denied: viewModel.locationDenied,
                    shake: viewModel.shakeLocationCard,
                    required: true,
                    action: viewModel.requestLocation,
                    retryAction: viewModel.openSettings
                ))

                permissionCard(PermissionCardConfig(
                    icon: "mic.fill",
                    title: LS["Permissions.Microphone.Title"],
                    description: LS["Permissions.Microphone.Description"],
                    granted: viewModel.microphoneGranted,
                    denied: viewModel.microphoneDenied,
                    shake: viewModel.shakeMicrophoneCard,
                    required: true,
                    action: viewModel.requestMicrophone,
                    retryAction: viewModel.openSettings
                ))

                permissionCard(PermissionCardConfig(
                    icon: "figure.walk",
                    title: LS["Permissions.Motion.Title"],
                    description: LS["Permissions.Motion.Description"],
                    granted: viewModel.motionGranted,
                    denied: false,
                    shake: false,
                    required: false,
                    action: viewModel.requestMotion,
                    retryAction: nil
                ))
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

    private func permissionCard(_ config: PermissionCardConfig) -> some View {
        VStack(spacing: Constants.UI.Padding.small) {
            HStack(spacing: Constants.UI.Padding.normal) {
                Image(systemName: config.icon)
                    .font(.title2)
                    .foregroundColor(.stone)
                    .frame(width: 32)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Constants.UI.Padding.small) {
                        Text(config.title)
                            .font(Constants.Typography.heading)
                            .foregroundColor(.ink)
                        if !config.required {
                            Text(LS["Permissions.Motion.Optional"])
                                .font(Constants.Typography.caption)
                                .foregroundColor(.fog)
                        }
                    }
                    Text(config.description)
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }

                Spacer()

                grantButton(
                    granted: config.granted,
                    denied: config.denied,
                    required: config.required,
                    decided: !config.required && viewModel.motionDecided,
                    action: config.denied && config.retryAction != nil ? config.retryAction! : config.action
                )
            }
            .padding(Constants.UI.Padding.normal)
            .background(config.granted ? Color.moss.opacity(0.1) : Color.parchmentSecondary)
            .cornerRadius(Constants.UI.CornerRadius.normal)
            .offset(x: config.shake ? -6 : 0)
            .animation(
                config.shake
                    ? .default.repeatCount(3, autoreverses: true).speed(6)
                    : .default,
                value: config.shake
            )

            if config.denied && config.required {
                Text(LS["Permissions.Required.Hint"])
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
            Text(LS["Permissions.Skipped"])
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        } else {
            Button(action: action) {
                Text(denied ? LS["Permissions.Settings"] : LS["Permissions.Grant"])
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
