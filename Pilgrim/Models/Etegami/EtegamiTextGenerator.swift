import Foundation

enum EtegamiTextGenerator {

    enum PrimaryActivity { case walking, meditation, voice }

    static func generate(
        intention: String?,
        reflection: String?,
        season: String,
        timeOfDay: String,
        durationMinutes: Int,
        moonPhaseName: String?,
        weatherCondition: String?,
        primaryActivity: PrimaryActivity
    ) -> String {
        if let intention = intention, !intention.isEmpty { return intention }
        if let reflection = reflection, !reflection.isEmpty { return reflection }
        return generateHaiku(
            season: season, timeOfDay: timeOfDay,
            durationMinutes: durationMinutes,
            moonPhaseName: moonPhaseName,
            weatherCondition: weatherCondition,
            primaryActivity: primaryActivity
        )
    }

    private static func generateHaiku(
        season: String, timeOfDay: String,
        durationMinutes: Int, moonPhaseName: String?,
        weatherCondition: String?, primaryActivity: PrimaryActivity
    ) -> String {
        let line1 = "\(season.lowercased()) \(timeOfDay.lowercased()) walk"

        let durationText: String
        if durationMinutes < 60 {
            durationText = durationMinutes == 1 ? "1 minute" : "\(durationMinutes) minutes"
        } else {
            let hours = durationMinutes / 60
            let mins = durationMinutes % 60
            let hourText = hours == 1 ? "1 hour" : "\(hours) hours"
            if mins > 0 {
                let minText = mins == 1 ? "1 minute" : "\(mins) minutes"
                durationText = "\(hourText) \(minText)"
            } else {
                durationText = hourText
            }
        }

        let activityText: String
        switch primaryActivity {
        case .walking:    activityText = "in silence"
        case .meditation: activityText = "in stillness"
        case .voice:      activityText = "in reflection"
        }
        let line2 = "\(durationText) \(activityText)"

        let line3: String
        if let moon = moonPhaseName {
            line3 = "under \(moon.lowercased())"
        } else if let weather = weatherCondition?.lowercased(), weather != "clear" {
            line3 = "through the \(weather)"
        } else {
            line3 = "along the trail"
        }

        return "\(line1)\n\(line2)\n\(line3)"
    }
}
