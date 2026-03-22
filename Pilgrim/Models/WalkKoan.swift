import Foundation

enum WalkKoan {

    static func generate(
        celestial: CelestialSnapshot? = nil,
        weather: WeatherSnapshot? = nil
    ) -> String {
        if let celestial, UserPreferences.celestialAwarenessEnabled.value {
            return celestialKoan(celestial)
        }
        if let weather {
            return weatherKoan(weather)
        }
        return seasonalKoan()
    }

    private static func celestialKoan(_ snapshot: CelestialSnapshot) -> String {
        if let marker = snapshot.seasonalMarker {
            return markerKoan(marker)
        }
        if let sun = snapshot.position(for: .sun) {
            return zodiacKoan(sun.tropical.sign)
        }
        return planetaryHourKoan(snapshot.planetaryHour.planet)
    }

    private static func zodiacKoan(_ sign: ZodiacSign) -> String {
        switch sign {
        case .aries: return "What begins when you begin?"
        case .taurus: return "What already sustains you?"
        case .gemini: return "What wants two answers?"
        case .cancer: return "What feels like home today?"
        case .leo: return "What deserves your full attention?"
        case .virgo: return "What small thing matters most?"
        case .libra: return "Where is the balance?"
        case .scorpio: return "What lies beneath the surface?"
        case .sagittarius: return "Where does curiosity lead?"
        case .capricorn: return "What is worth the climb?"
        case .aquarius: return "What pattern can you break?"
        case .pisces: return "What flows through you?"
        }
    }

    private static func planetaryHourKoan(_ planet: Planet) -> String {
        switch planet {
        case .sun: return "What light are you carrying?"
        case .moon: return "What do you feel but not yet see?"
        case .mercury: return "What message is waiting?"
        case .venus: return "What is beautiful right now?"
        case .mars: return "Where is your energy going?"
        case .jupiter: return "What is more than enough?"
        case .saturn: return "What boundary serves you?"
        }
    }

    private static func markerKoan(_ marker: SeasonalMarker) -> String {
        switch marker {
        case .springEquinox: return "What is ready to emerge?"
        case .summerSolstice: return "What is at its fullest?"
        case .autumnEquinox: return "What can you let fall?"
        case .winterSolstice: return "What grows in the dark?"
        case .imbolc: return "What stirs beneath the surface?"
        case .beltane: return "What are you celebrating?"
        case .lughnasadh: return "What have you harvested?"
        case .samhain: return "What do you honor in passing?"
        }
    }

    private static func weatherKoan(_ weather: WeatherSnapshot) -> String {
        switch weather.condition {
        case .clear: return "What do you see clearly?"
        case .partlyCloudy: return "What is half-revealed?"
        case .overcast: return "What hides in soft light?"
        case .lightRain: return "What does the rain wash away?"
        case .heavyRain: return "What endures the storm?"
        case .thunderstorm: return "What shakes loose?"
        case .snow: return "What lies under the quiet?"
        case .fog: return "What emerges from the mist?"
        case .wind: return "What moves you today?"
        case .haze: return "What becomes clear with distance?"
        }
    }

    private static func seasonalKoan() -> String {
        let month = Calendar.current.component(.month, from: Date())
        let hour = Calendar.current.component(.hour, from: Date())

        if hour < 6 {
            return ["What wakes with you?", "What stirs before dawn?"].randomElement()!
        } else if hour < 10 {
            return ["What will you notice today?", "Where does the path want to go?"].randomElement()!
        } else if hour < 14 {
            return ["What is here right now?", "What are you carrying?"].randomElement()!
        } else if hour < 18 {
            return ["What surprised you today?", "What can you leave behind?"].randomElement()!
        } else {
            return ["What did the day give you?", "What will you remember?"].randomElement()!
        }
    }
}
