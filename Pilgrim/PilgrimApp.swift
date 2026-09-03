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
    @StateObject private var rootViewModel = RootCoordinatorViewModel()

    /// A link tapped on a cold launch arrives before `MainTabView` exists to
    /// hear the notification below — held here so its `onAppear` can claim
    /// it once the launch gate (`RootCoordinatorView`'s `appLaunchState`)
    /// finally mounts the tab view.
    @MainActor static var pendingShareId: String?

    var body: some Scene {
        WindowGroup {
            ZStack {
                RootCoordinatorView(viewModel: rootViewModel)
                if appearanceManager.isConstellation {
                    ConstellationOverlay()
                }
            }
            .environmentObject(appearanceManager)
            .preferredColorScheme(appearanceManager.resolvedScheme)
            .onOpenURL { url in Self.route(url) }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                if let url = activity.webpageURL { Self.route(url) }
            }
        }
    }

    /// Broadcast rather than routed directly: `MainTabView` owns the
    /// coordinator, and a link arriving before setup finishes has no
    /// `MainTabView` mounted to hear it. Stashing the id in `pendingShareId`
    /// too means that cold-launch case isn't just broadcast into silence —
    /// `MainTabView.onAppear` drains it once mounted.
    @MainActor
    private static func route(_ url: URL) {
        guard let id = HonorLink.parse(url) else { return }
        pendingShareId = id
        NotificationCenter.default.post(name: .pilgrimOpenWay, object: nil, userInfo: ["shareId": id])
    }
}
