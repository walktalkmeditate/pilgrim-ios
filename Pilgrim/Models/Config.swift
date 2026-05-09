//
//  Config.swift
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
import StoreKit

enum Config {
    
    static var releaseStatus: ReleaseStatus {
        if Config.isDebug || Config.isRunOnSimulator {
            return ReleaseStatus.debug
        } else if /*Config.hasMobileProvision &&*/ Config.hasSanboxReceipt {
            return ReleaseStatus.beta
        } else {
            return ReleaseStatus.release
        }
    }
    
    static var version: String {
        return Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "error"
    }
    
    static let versions: [String] = ["1.0", "1.1", "1.1.1", "1.1.2", "1.2", "1.2.1", "1.2.2"]
    
    static var changeLogs: [String:String] = [
        "1.2.2" : LS["Changelog_1.2.2", .changelog]
    ]
    
    static var isDarkModeEnabled: Bool {
        return UITraitCollection.current.userInterfaceStyle == .dark
    }
    
    enum ReleaseStatus: String {
        case debug, beta, release
    }
    
    /// A boolean indicating whether the app is run in debug mode
    static var isDebug: Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }
    
    /// A boolean indicating whether the app is run on a simulator
    static var isRunOnSimulator: Bool {
        #if targetEnvironment(simulator)
            return true
        #else
            return false
        #endif
    }
    
    /// A boolean indicating wheather the app bundle contains a certain file generated when building and packaging an App for App Store Connect
    static var hasMobileProvision: Bool {
        return (Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") != nil)
    }
    
    /// A boolean indicating whether or not the receipt provided through by the App Store was generated for a sandbox / non-release environment; in other words: it indicates if the app was downloaded through another way than the App Store
    /// (including TestFlight). Populated asynchronously from `AppTransaction.shared` at launch via `warmSandboxReceiptCache`. Defaults to `false`
    /// (treat as release) until the cache is warmed — only used by the Settings release-status row, which re-renders on read.
    nonisolated(unsafe) private static var cachedSandboxReceipt: Bool = false

    static var hasSanboxReceipt: Bool {
        cachedSandboxReceipt
    }

    /// Call once at app launch. Safe to call on background tasks. The
    /// `AppTransaction.shared` call may briefly hit the network the first
    /// time the app runs after install, then caches in StoreKit.
    static func warmSandboxReceiptCache() async {
        guard let verification = try? await AppTransaction.shared else { return }
        let transaction: AppTransaction
        switch verification {
        case .verified(let value), .unverified(let value, _):
            transaction = value
        }
        cachedSandboxReceipt = transaction.environment == .sandbox
    }

    enum Audio {
        static let r2BaseURL = URL(string: "https://cdn.pilgrimapp.org/audio")!
        static let manifestURL = URL(string: "https://cdn.pilgrimapp.org/audio/manifest.json")!
    }

    enum VoiceGuide {
        static let manifestURL = URL(string: "https://cdn.pilgrimapp.org/voiceguide/manifest.json")!
        static let baseURL = URL(string: "https://cdn.pilgrimapp.org/voiceguide")!
    }

    enum Whisper {
        static let manifestURL = URL(string: "https://cdn.pilgrimapp.org/audio/whisper/manifest.json")!
        static let cdnBaseURL = URL(string: "https://cdn.pilgrimapp.org/audio/whisper")!
    }

    enum Web {
        static let viewer = URL(string: "https://view.pilgrimapp.org")!
        static let editor = URL(string: "https://edit.pilgrimapp.org")!
    }

}
