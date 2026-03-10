//
//  AppDelegate.swift
//
//  Pilgrim
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
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

class AppDelegate: UIResponder, UIApplicationDelegate, ObservableObject {
    
    @Published var appLaunchState: AppLaunchState = .loading
    
    static let lastVersion = UserPreference.Optional<String>(key: "lastVersion", initialValue: "1.0")

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        
        DataManager.setup(
            completion: { error in
                
                self.appLaunchState = .done

                // check permissions
                // show changelog
                //
                
                // self.checkPermissionStatus(controller: controller) {
                //     guard UserPreferences.isSetUp.value else { return }
                //     HealthStoreManager.setupObservers()
                //
                //     if AppDelegate.lastVersion.value != Config.version && AppDelegate.lastVersion.value != nil {
                //
                //         if let changeLog = Config.changeLogs[Config.version] {
                //             // show changelog
                //         }
                //
                //         AppDelegate.lastVersion.value = Config.version
                //
                //     } else if AppDelegate.lastVersion.value == nil {
                //         AppDelegate.lastVersion.value = Config.version
                //     }
                // }

            }, migration: { progress in

                // show migration screen
                self.appLaunchState = .migration

            }
        )
        
        return true
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        WalkMapImageManager.suspendRenderProcess()
        ApplicationStateObservation.stateChanged(to: .background)
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        WalkMapImageManager.resumeRenderProcess()
        ApplicationStateObservation.stateChanged(to: .foreground)
    }

    func applicationWillTerminate(_ application: UIApplication) {}

    enum AppLaunchState {
        case loading
        case migration
        case done
    }
}

