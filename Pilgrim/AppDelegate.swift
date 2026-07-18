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

        let launchStart = CFAbsoluteTimeGetCurrent()
        func mark(_ stage: String) {
            #if DEBUG
            let dt = (CFAbsoluteTimeGetCurrent() - launchStart) * 1000
            print(String(format: "[LaunchProfile] +%.0fms — %@", dt, stage))
            #endif
        }
        mark("entered didFinishLaunching")

        MapboxMapsOptions.tileStoreUsageMode = .readOnly
        mark("after Mapbox init")

        // Clean up any Live Activities left over from a previous session
        // that ended abnormally (crash, force-quit, OOM kill). Any activity
        // alive at app launch is necessarily stale — the walk that created
        // it is no longer running. Without this, walkers see the lock
        // screen Live Activity hang around even though the app thinks the
        // walk is finished.
        WalkActivityManager.shared.endAllStaleActivities()
        mark("after endAllStaleActivities")

        // One-time migration: seed bell + soundscape preferences with
        // their initial values for users who have never explicitly set
        // them. Previously these preferences had fallback defaultValues,
        // which made the "None" selection impossible to persist — setting
        // to nil would read back as the default. Removing the fallbacks
        // fixes None, but we still want fresh installs and pre-migration
        // users to get sensible initial choices. Explicit existing
        // selections are preserved.
        //
        // Writes go directly to UserDefaults rather than through
        // `UserPreferences.X.value = Y`, because this runs before any
        // UserPreferences static members are touched. The
        // `UserPreference._Base.publisher` is created lazily on first
        // access of the static let, at which point it reads the current
        // UserDefaults value — so it picks up the migrated seeds
        // automatically without needing to go through `set()`.
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
        mark("after soundscape migration")

        #if DEBUG
        Self.parseTurningStubLaunchArg()
        #endif

        DataManager.setup(
            completion: { _ in
                mark("DataManager.setup completion fired")

                // Demo-mode seeds walks before showing the UI — keep it
                // ahead of `.done` so the welcome flow renders against a
                // populated DB.
                #if DEBUG
                if CommandLine.arguments.contains("--demo-mode") {
                    self.seedDemoData {
                        self.appLaunchState = .done
                    }
                    return
                }
                #endif

                // Flip `.done` IMMEDIATELY so WelcomeView can render. The
                // post-setup work below (recording recovery, manifest
                // syncs, collective counter) is all fire-and-forget and
                // does not need to gate the UI.
                self.appLaunchState = .done
                mark("appLaunchState = .done (WelcomeView can render)")

                self.startLaunchRecordingCleanup()

                // Manifest-service init is intentionally cheap (issue #42):
                // the first `.shared` touch used to burn ~880ms of
                // main-thread disk I/O + JSON decode here, mid welcome
                // entrance. The local-manifest/bootstrap loads now run in
                // each service's detached initial-load task; syncIfNeeded
                // awaits that load before comparing against the remote.
                // Each service prints a "[LaunchProfile] … manifest ready"
                // mark when its catalog lands.
                AudioManifestService.shared.syncIfNeeded()
                VoiceGuideManifestService.shared.syncIfNeeded()
                WhisperManifestService.shared.syncIfNeeded()
                CollectiveRouteCatalogService.shared.syncIfNeeded()
                Task { await CollectiveCounterService.shared.fetch() }
                mark("post-setup fire-and-forgets dispatched")


            }, migration: { _ in

                // show migration screen
                self.appLaunchState = .migration

            }
        )
        
        return true
    }

    /// Launch cleanup ordering (AF2): the orphan sweep runs only once BOTH
    /// path recovery has finished AND any crashed-walk checkpoint has been
    /// recovered (WalkSessionGuard resolves the gate from MainCoordinator).
    /// The no-checkpoint fast path keeps the sweep alive for
    /// onboarding/migration sessions where MainCoordinator never constructs.
    ///
    /// Skipped under XCTest: the shared-singleton sweep enumerates the real
    /// Documents/Recordings tree on the production stack, which races recovery
    /// unit tests that write fixture audio into that same process-global
    /// directory (same reasoning as parseTurningStubLaunchArg). The shipping
    /// app never loads XCTestCase, so this guard is inert in production.
    private func startLaunchRecordingCleanup() {
        guard NSClassFromString("XCTestCase") == nil else { return }

        RecordingPathRecovery.run {
            OrphanSweepGate.shared.notePathRecoveryComplete()
        }
        if !FileManager.default.fileExists(atPath: WalkSessionGuard.checkpointFileURL().path) {
            OrphanSweepGate.shared.noteWalkRecoveryResolved()
        }
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

    /// Parses `--turning-stub <name>` from the launch args and sets
    /// `TurningDayService.testingDate` so every turning query returns the
    /// stubbed marker for visual QA. Names: `winter-solstice`,
    /// `summer-solstice`, `spring-equinox`, `autumn-equinox`. No-op if
    /// the arg is absent or unrecognized. DEBUG-only.
    static func parseTurningStubLaunchArg() {
        // Bail out under XCTest — Xcode's test action inherits launch args
        // from the run action, which would otherwise poison every unit test
        // that exercises TurningDayService. Detected via the NSClassFromString
        // check (XCTestCase is loaded into the test host process, not the app).
        guard NSClassFromString("XCTestCase") == nil else { return }

        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--turning-stub"),
              idx + 1 < args.count else { return }
        let name = args[idx + 1]
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: Date())
        var components = DateComponents()
        components.year = year
        components.hour = 12
        components.timeZone = TimeZone(identifier: "UTC")
        switch name {
        case "winter-solstice":
            components.month = 12
            components.day = 21
        case "summer-solstice":
            components.month = 6
            components.day = 20
        case "spring-equinox":
            components.month = 3
            components.day = 20
        case "autumn-equinox":
            components.month = 9
            components.day = 22
        default:
            print("[TurningStub] unknown stub: \(name) — expected winter-solstice / summer-solstice / spring-equinox / autumn-equinox")
            return
        }
        guard let date = calendar.date(from: components) else { return }
        TurningDayService.testingDate = date
        print("[TurningStub] turningForToday() will return \(name) (\(date))")
    }
    #endif

    enum AppLaunchState {
        case loading
        case migration
        case done
    }
}
