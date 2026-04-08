//
//  AppDelegate.swift
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

import UIKit
import Foundation
import CoreStore
import MapboxMaps

class AppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
    
    @Published var appLaunchState: AppLaunchState = .loading
    
    static let lastVersion = UserPreference.Optional<String>(key: "lastVersion", initialValue: "1.0")

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        MapboxMapsOptions.tileStoreUsageMode = .readOnly

        // Clean up any Live Activities left over from a previous session
        // that ended abnormally (crash, force-quit, OOM kill). Any activity
        // alive at app launch is necessarily stale — the walk that created
        // it is no longer running. Without this, walkers see the lock
        // screen Live Activity hang around even though the app thinks the
        // walk is finished.
        WalkActivityManager.shared.endAllStaleActivities()

        // One-time migration: seed bell + soundscape preferences with
        // their initial values for users who have never explicitly set
        // them. Previously these preferences had fallback defaultValues,
        // which made the "None" selection impossible to persist — setting
        // to nil would read back as the default. Removing the fallbacks
        // fixes None, but we still want fresh installs and pre-migration
        // users to get sensible initial choices. Explicit existing
        // selections are preserved.
        let soundscapeMigrationKey = "soundscapeDefaultMigrated_v1"
        if !UserDefaults.standard.bool(forKey: soundscapeMigrationKey) {
            let seeds: [(key: String, initialValue: String)] = [
                ("walkStartBellId", "echo-chime"),
                ("walkEndBellId", "gentle-harp"),
                ("meditationStartBellId", "temple-bell"),
                ("meditationEndBellId", "yoga-chime"),
                ("selectedSoundscapeId", "gentle-stream")
            ]
            for seed in seeds where UserDefaults.standard.object(forKey: seed.key) == nil {
                UserDefaults.standard.set(seed.initialValue, forKey: seed.key)
            }
            UserDefaults.standard.set(true, forKey: soundscapeMigrationKey)
        }

        DataManager.setup(
            completion: { _ in
                
                AudioManifestService.shared.syncIfNeeded()
                VoiceGuideManifestService.shared.syncIfNeeded()
                Task { await CollectiveCounterService.shared.fetch() }

                #if DEBUG
                if CommandLine.arguments.contains("--demo-mode") {
                    self.seedDemoData {
                        self.appLaunchState = .done
                    }
                    return
                }
                #endif

                self.appLaunchState = .done


            }, migration: { _ in

                // show migration screen
                self.appLaunchState = .migration

            }
        )
        
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        if WalkSessionGuard.active != nil {
            print("[SessionGuard] BACKGROUND ENTRY — writing checkpoint")
        }
        WalkSessionGuard.active?.checkpointNow()
        WalkMapImageManager.suspendRenderProcess()
        ApplicationStateObservation.stateChanged(to: .background)
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        WalkMapImageManager.resumeRenderProcess()
        ApplicationStateObservation.stateChanged(to: .foreground)
    }

    func applicationWillTerminate(_ application: UIApplication) {
        if WalkSessionGuard.active != nil {
            print("[SessionGuard] APP TERMINATING — writing final checkpoint")
        }
        WalkSessionGuard.active?.checkpointNow()
        WalkActivityManager.shared.end()
    }

    #if DEBUG
    private func seedDemoData(completion: @escaping () -> Void) {
        UserPreferences.isSetUp.value = true
        DataManager.deleteAll { _, _ in
            ScreenshotDataSeeder.seed { count in
                print("[DemoMode] Seeded \(count) walks")
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }
    #endif

    enum AppLaunchState {
        case loading
        case migration
        case done
    }
}
