//
//  WelcomeViewModel.swift
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

import Foundation

class WelcomeViewModel: ObservableObject {
    
    private(set) var setupButtonAction: () -> Void
    
    let titleLineOne = "Welcome to"
    let titleLineTwo = "Pilgrim"
    let features = [
        FeatureViewModel(
            title: "Walk & Record",
            description: "Track your walking journey with GPS and record voice notes along the way.",
            systemImageName: "figure.walk"),
        FeatureViewModel(
            title: "Voice Memories",
            description: "Capture thoughts and reflections as voice recordings pinned to your route.",
            systemImageName: "mic.fill"),
        FeatureViewModel(
            title: "Privacy First",
            description: "All data stays on your device. No accounts, no cloud, no tracking.",
            systemImageName: "lock.shield")
    ]
    let actionButtonTitle = "Begin Setup"
    
    init(setupButtonAction: @escaping () -> Void) {
        self.setupButtonAction = setupButtonAction
    }
}
