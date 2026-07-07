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

    /// Title of the single seek setup question (R2).
    static let seekDurationTitle = NSLocalizedString(
        "seek.duration.title",
        value: "How long do you have?",
        comment: "Title of the seek setup sheet asking how long the walker has for the walk."
    )

    /// Seek duration preset: 30 minutes.
    static let seekDuration30Min = NSLocalizedString(
        "seek.duration.30min",
        value: "30 minutes",
        comment: "Seek duration preset label for a 30-minute walk."
    )

    /// Seek duration preset: 1 hour.
    static let seekDuration1Hour = NSLocalizedString(
        "seek.duration.1hour",
        value: "1 hour",
        comment: "Seek duration preset label for a one-hour walk."
    )

    /// Seek duration preset: 2 hours.
    static let seekDuration2Hours = NSLocalizedString(
        "seek.duration.2hours",
        value: "2 hours",
        comment: "Seek duration preset label for a two-hour walk."
    )

    /// Seek duration preset: 3 hours.
    static let seekDuration3Hours = NSLocalizedString(
        "seek.duration.3hours",
        value: "3 hours",
        comment: "Seek duration preset label for a three-hour walk."
    )

    /// One-time safety framing shown under the duration presets (R21).
    static let seekSafetyCaption = NSLocalizedString(
        "seek.safety.caption",
        value: "Never trespass, and let your own judgment walk above the pulse. Any clearing may be released — seek anew.",
        comment: "Caption shown once, on the first seek only, framing safety: no trespassing, personal judgment outranks the guidance, and any clearing can be rerolled."
    )

    /// Confirmation button on the seek duration sheet.
    static let seekBegin = NSLocalizedString(
        "seek.begin",
        value: "Begin",
        comment: "Button confirming the chosen seek duration and starting the setup ritual."
    )

    /// Gentle line shown when precise location is declined for a seek.
    static let seekAccuracyDeclined = NSLocalizedString(
        "seek.accuracy.declined",
        value: "Seeking needs your precise location to sense the clearings. Wander is always open.",
        comment: "Alert message when the walker declines temporary full-accuracy location for a seek; they are returned home where Wander remains available."
    )

    /// Gentle line shown when no accurate GPS fix arrives during the
    /// breath transition (U7 GPS-lock timeout).
    static let seekGPSTimeout = NSLocalizedString(
        "seek.gps.timeout",
        value: "The sky hasn't answered yet. Try again under more open sky — Wander is always open.",
        comment: "Alert message when GPS cannot deliver an accurate fix in time to begin a seek; the walker is returned home to try again."
    )

    /// Header of the seek-only section in the in-walk options sheet (R11).
    static let seekSectionTitle = NSLocalizedString(
        "seek.section.title",
        value: "Seek",
        comment: "Caption-style header of the seek-only section in the in-walk options sheet."
    )

    /// Sonar enable toggle row in the in-walk options sheet (R11).
    static let seekSonarTitle = NSLocalizedString(
        "seek.sonar.title",
        value: "Sonar",
        comment: "Label of the toggle controlling the seek sonar ping sound."
    )

    /// Sonar volume slider row in the in-walk options sheet (R11).
    static let seekSonarVolumeTitle = NSLocalizedString(
        "seek.sonar.volume",
        value: "Sonar Volume",
        comment: "Label of the slider controlling the seek sonar ping volume."
    )

    /// The reroll action row (R17).
    static let seekAnewTitle = NSLocalizedString(
        "seek.anew.title",
        value: "Seek Anew",
        comment: "Options-sheet row that regenerates the remaining clearings of a seek; used whenever a way feels closed."
    )

    /// Subtitle of the disabled reroll row after the final reveal (R17).
    static let seekAnewCompleteSubtitle = NSLocalizedString(
        "seek.anew.complete",
        value: "The seeking is complete",
        comment: "Subtitle of the disabled Seek Anew row after the final clearing has been revealed."
    )

    /// Header of the seek story section on the walk summary (R19).
    static let seekSummaryHeader = NSLocalizedString(
        "seek.summary.header",
        value: "The Seeking",
        comment: "Header of the walk-summary section telling the story of a seek walk."
    )

    /// R19: the note counts only reached clearings — one unknown found.
    static let seekSummaryFoundOne = NSLocalizedString(
        "seek.summary.found.one",
        value: "One unknown found",
        comment: "Walk-summary note for a seek where one clearing was reached. Must never mention a total or use 'X of Y' phrasing."
    )

    /// R19: the note counts only reached clearings — two unknowns found.
    static let seekSummaryFoundTwo = NSLocalizedString(
        "seek.summary.found.two",
        value: "Two unknowns found",
        comment: "Walk-summary note for a seek where two clearings were reached. Must never mention a total or use 'X of Y' phrasing."
    )

    /// R19: the note counts only reached clearings — three unknowns found.
    static let seekSummaryFoundThree = NSLocalizedString(
        "seek.summary.found.three",
        value: "Three unknowns found",
        comment: "Walk-summary note for a seek where three clearings were reached. Must never mention a total or use 'X of Y' phrasing."
    )

    /// R19 fallback beyond three reached clearings; %d is the reached count.
    static let seekSummaryFoundManyFormat = NSLocalizedString(
        "seek.summary.found.many",
        value: "%d unknowns found",
        comment: "Walk-summary note for a seek where more than three clearings were reached; %d is the count of reached clearings, never a total."
    )

    /// Closing group for signs marked outside every clearing (R19).
    static let seekSummaryAlongTheWay = NSLocalizedString(
        "seek.summary.along_the_way",
        value: "Along the way",
        comment: "Label of the walk-summary group gathering signs marked outside every reached clearing."
    )

    /// Single photo in a clearing's sign line.
    static let seekSummarySignPhotoOne = NSLocalizedString(
        "seek.summary.sign.photo.one",
        value: "a photo",
        comment: "Sign count fragment for one photo in a seek summary clearing group."
    )

    /// Multiple photos in a clearing's sign line; %d is the count.
    static let seekSummarySignPhotosFormat = NSLocalizedString(
        "seek.summary.sign.photo.many",
        value: "%d photos",
        comment: "Sign count fragment for several photos in a seek summary clearing group; %d is the count."
    )

    /// Single voice note in a clearing's sign line.
    static let seekSummarySignVoiceOne = NSLocalizedString(
        "seek.summary.sign.voice.one",
        value: "a voice note",
        comment: "Sign count fragment for one voice recording in a seek summary clearing group."
    )

    /// Multiple voice notes in a clearing's sign line; %d is the count.
    static let seekSummarySignVoicesFormat = NSLocalizedString(
        "seek.summary.sign.voice.many",
        value: "%d voice notes",
        comment: "Sign count fragment for several voice recordings in a seek summary clearing group; %d is the count."
    )

    /// Single waypoint mark in a clearing's sign line.
    static let seekSummarySignMarkOne = NSLocalizedString(
        "seek.summary.sign.mark.one",
        value: "a mark",
        comment: "Sign count fragment for one waypoint mark in a seek summary clearing group."
    )

    /// Multiple waypoint marks in a clearing's sign line; %d is the count.
    static let seekSummarySignMarksFormat = NSLocalizedString(
        "seek.summary.sign.mark.many",
        value: "%d marks",
        comment: "Sign count fragment for several waypoint marks in a seek summary clearing group; %d is the count."
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

        /// A `String` pointing to the file in which the localised strings of the given `LSSourceType` are located.
        fileprivate var tableName: String {
            switch self {
            case .appStrings:
                return "Localizable"
            case .infoPlist:
                return "InfoPlist"
            }
        }

        /// The `Bundle` that is to be used in case a string is not localised for the current language
        fileprivate var fallbackBundle: Bundle {
            switch self {
            case .appStrings:
                return Bundle(path: Bundle.main.path(forResource: "Base", ofType: "lproj")!)!
            case .infoPlist:
                return Bundle(path: Bundle.main.path(forResource: "en", ofType: "lproj")!)!
            }
        }
        
    }
    
}
