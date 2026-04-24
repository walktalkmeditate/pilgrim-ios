//
//  LS.swift
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

import Foundation

/// A struct containg only static subscripts and needed enumerations to enable easier localisation.
struct LS {

    /// Banner text shown on the home scroll during solstices.
    static let turningSolsticeBanner = NSLocalizedString(
        "turning.solstice.banner",
        value: "Today the sun stands still",
        comment: "Home-scroll banner text on winter or summer solstice."
    )

    /// Banner text shown on the home scroll during equinoxes.
    static let turningEquinoxBanner = NSLocalizedString(
        "turning.equinox.banner",
        value: "Today, day equals night",
        comment: "Home-scroll banner text on spring or autumn equinox."
    )

    /// Evocative phrase shown on the turning ritual card for the winter solstice.
    static let turningWinterSolsticePhrase = NSLocalizedString(
        "turning.phrase.winter_solstice",
        value: "The longest night. From here, light returns.",
        comment: "Contemplative card body shown when tapping the winter-solstice watermark."
    )

    /// Evocative phrase shown on the turning ritual card for the summer solstice.
    static let turningSummerSolsticePhrase = NSLocalizedString(
        "turning.phrase.summer_solstice",
        value: "The longest day. The wheel begins to turn back toward stillness.",
        comment: "Contemplative card body shown when tapping the summer-solstice watermark."
    )

    /// Evocative phrase shown on the turning ritual card for the spring equinox.
    static let turningSpringEquinoxPhrase = NSLocalizedString(
        "turning.phrase.spring_equinox",
        value: "Light is rising. The thaw.",
        comment: "Contemplative card body shown when tapping the spring-equinox watermark."
    )

    /// Evocative phrase shown on the turning ritual card for the autumn equinox.
    static let turningAutumnEquinoxPhrase = NSLocalizedString(
        "turning.phrase.autumn_equinox",
        value: "Light is fading. The harvest.",
        comment: "Contemplative card body shown when tapping the autumn-equinox watermark."
    )

    /// VoiceOver hint for the tappable kanji watermark on turning days.
    static let turningWatermarkA11yHint = NSLocalizedString(
        "turning.watermark.a11y_hint",
        value: "Opens a contemplative card about today's turning",
        comment: "VoiceOver hint for tapping the faint kanji watermark on the active walk map during a solstice or equinox."
    )


    /**
     Returns a localised string for the provided key and specified source.
     - parameter key: the key pointing to the localised string
     - parameter sourceType: the `LSSourceType` defining which file to get the string from
     - returns: the localised `String`
     */
    public static subscript(_ key: String, sourceType: LSSourceType = .appStrings) -> String {
        
        let errorValue = "NIL"
        var localizedString = Bundle.main.localizedString(forKey: key, value: errorValue, table: sourceType.tableName)
        
        if localizedString == "NIL" {
            localizedString = sourceType.fallbackBundle.localizedString(forKey: key, value: errorValue, table: sourceType.tableName)
        }

        return localizedString
    }
    
    /// Enumeration of possible localised string source types referring to different string tables in the project.
    public enum LSSourceType {
        
        /// Referring to strings used inside the app.
        case appStrings
        /// Referring to strings contained by the info.plist and needed for things like permission descriptions.
        case infoPlist
        /// Referring to strings used in changelogs
        case changelog
        
        /// A `String` pointing to the file in which the localised strings of the given `LSSourceType` are located.
        fileprivate var tableName: String {
            switch self {
            case .appStrings:
                return "Localizable"
            case .infoPlist:
                return "InfoPlist"
            case .changelog:
                return "Changelog"
            }
        }
        
        /// The `Bundle` that is to be used in case a string is not localised for the current language
        fileprivate var fallbackBundle: Bundle {
            switch self {
            case .appStrings:
                return Bundle(path: Bundle.main.path(forResource: "Base", ofType: "lproj")!)!
            case .infoPlist, .changelog:
                return Bundle(path: Bundle.main.path(forResource: "en", ofType: "lproj")!)!
            }
        }
        
    }
    
}
