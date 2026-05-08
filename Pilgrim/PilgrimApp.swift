//
//  PilgrimApp.swift
//
//  Pilgrim
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
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

@main
struct PilgrimApp: App {
    
    @UIApplicationDelegateAdaptor var delegate: AppDelegate
    @StateObject private var appearanceManager = AppearanceManager()

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootCoordinatorView(viewModel: RootCoordinatorViewModel())
                if appearanceManager.isConstellation {
                    Color(red: 0.039, green: 0.039, blue: 0.071)
                        .opacity(0.35)
                        .ignoresSafeArea()
                        .allowsHitTesting(false)
                    ConstellationOverlay()
                }
            }
            .preferredColorScheme(appearanceManager.resolvedScheme)
        }
    }
}
