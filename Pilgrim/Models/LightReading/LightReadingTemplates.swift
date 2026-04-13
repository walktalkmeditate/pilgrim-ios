import Foundation

struct LightReadingTemplate {
    let text: String
}

enum LightReadingTemplates {

    static func templates(for tier: LightReading.Tier) -> [LightReadingTemplate] {
        switch tier {
        case .lunarEclipse:     return lunarEclipse
        case .supermoon:        return supermoon
        case .seasonalMarker:   return seasonalMarker
        case .meteorShowerPeak: return meteorShowerPeak
        case .fullMoon:         return fullMoon
        case .newMoon:          return newMoon
        case .deepNight:        return deepNight
        case .sunriseSunset:    return sunriseSunset
        case .twilight:         return twilight
        case .goldenHour:       return goldenHour
        case .moonPhase:        return moonPhase
        }
    }

    // MARK: - Tier pools

    private static let lunarEclipse: [LightReadingTemplate] = [
        LightReadingTemplate(text: "This walk happened during a total lunar eclipse. The moon turned red."),
        LightReadingTemplate(text: "A lunar eclipse was in progress. The moon moved through Earth's shadow while you walked."),
        LightReadingTemplate(text: "The moon was partially eclipsed during this walk. A piece of Earth's shadow crossed its face."),
        LightReadingTemplate(text: "This walk coincided with a lunar eclipse. The moon dimmed to copper for {minutes} minutes."),
        LightReadingTemplate(text: "Earth stood between the sun and moon while you walked. The eclipse reached its peak at {eclipseDate}."),
    ]

    private static let supermoon: [LightReadingTemplate] = [
        LightReadingTemplate(text: "You walked under the {month} supermoon \u{2014} the full moon at its closest to Earth this orbit."),
        LightReadingTemplate(text: "The moon was {distanceKm} km away when you walked. One of its closest passes of the year."),
        LightReadingTemplate(text: "This was a supermoon night. The moon hung {pct}% illuminated and nearer than usual."),
        LightReadingTemplate(text: "You walked under a supermoon in {month} {year}. The closest full moon in months."),
        LightReadingTemplate(text: "The moon was near perigee during this walk \u{2014} {distanceKm} km out, pulling the tides a little stronger than most nights."),
    ]

    private static let seasonalMarker: [LightReadingTemplate] = [
        LightReadingTemplate(text: "You walked on the spring equinox. The year is beginning its long turn toward warmth."),
        LightReadingTemplate(text: "This walk happened on the summer solstice \u{2014} the longest day of the year."),
        LightReadingTemplate(text: "You walked on the autumn equinox. The year tipping toward winter."),
        LightReadingTemplate(text: "You walked on the winter solstice. The longest night of the year. Light begins to return tomorrow."),
        LightReadingTemplate(text: "This walk fell on Imbolc \u{2014} the old Celtic midpoint between winter solstice and spring. The light is coming back."),
        LightReadingTemplate(text: "You walked on Beltane. The old midpoint between spring and summer, when fires were lit on hillsides."),
        LightReadingTemplate(text: "This walk happened on Lughnasadh \u{2014} the beginning of the harvest season in the old calendar."),
        LightReadingTemplate(text: "You walked on Samhain. The midpoint between autumn equinox and winter solstice, the old year's end."),
    ]

    private static let meteorShowerPeak: [LightReadingTemplate] = [
        LightReadingTemplate(text: "This walk coincided with the peak of the {showerName} \u{2014} up to {zhr} meteors per hour on a clear night."),
        LightReadingTemplate(text: "The {showerName} meteor shower peaked around this walk. Earth was passing through a trail of comet debris."),
        LightReadingTemplate(text: "Your walk happened on the peak night of the {showerName}. Whether or not you looked up, the sky was busy."),
        LightReadingTemplate(text: "The {showerName} were at their peak. Up to {zhr} meteors per hour, if the sky was clear above you."),
        LightReadingTemplate(text: "This walk fell on the peak night of the {showerName} shower. The particles burning above were shed by a comet centuries ago."),
    ]

    private static let fullMoon: [LightReadingTemplate] = [
        LightReadingTemplate(text: "The full moon watched over this walk \u{2014} {pct}% illuminated."),
        LightReadingTemplate(text: "You walked under a full moon. The sky was bright enough to cast shadows."),
        LightReadingTemplate(text: "A nearly full moon lit this walk \u{2014} {pct}% illuminated, bright enough to read by."),
        LightReadingTemplate(text: "The moon was {pct}% illuminated during this walk. Full enough to see the path clearly."),
        LightReadingTemplate(text: "You walked by the light of a full moon in {month}."),
    ]

    private static let newMoon: [LightReadingTemplate] = [
        LightReadingTemplate(text: "This walk happened under the dark of the new moon. Stars at their clearest."),
        LightReadingTemplate(text: "No moon tonight. The sky belonged to the stars."),
        LightReadingTemplate(text: "The moon was new \u{2014} absent from the sky, barely {pct}% illuminated. The dark was complete."),
        LightReadingTemplate(text: "A new moon night. The darkest the sky gets on a cloudless evening."),
        LightReadingTemplate(text: "You walked without the moon. It was new \u{2014} lost in the sun's glare, invisible from Earth."),
    ]

    private static let deepNight: [LightReadingTemplate] = [
        LightReadingTemplate(text: "You walked in astronomical night \u{2014} the sun far enough below the horizon that no twilight remains."),
        LightReadingTemplate(text: "The sky was fully dark during this walk. No sun glow, no moon to speak of."),
        LightReadingTemplate(text: "This walk happened in the deep of the night, past all three layers of twilight."),
        LightReadingTemplate(text: "Astronomical night. The sun was more than 18 degrees below the horizon when you walked."),
        LightReadingTemplate(text: "You walked under a proper dark sky \u{2014} sun well gone, moon absent. The kind of night astronomers wait for."),
    ]

    private static let sunriseSunset: [LightReadingTemplate] = [
        LightReadingTemplate(text: "Your walk began {N} minutes before sunrise. The sun rose at {time}."),
        LightReadingTemplate(text: "The sun rose at {time}, just {N} minutes after this walk started."),
        LightReadingTemplate(text: "You walked into sunrise. The sun cleared the horizon at {time}."),
        LightReadingTemplate(text: "The sun had set at {time}, {N} minutes before this walk ended."),
        LightReadingTemplate(text: "You walked out of sunset. The sun dropped below the horizon at {time}."),
        LightReadingTemplate(text: "This walk began {N} minutes after the sun went down at {time}."),
    ]

    private static let twilight: [LightReadingTemplate] = [
        LightReadingTemplate(text: "You walked through civil twilight \u{2014} the blue hour between day and night."),
        LightReadingTemplate(text: "This walk happened in nautical twilight. The sun was well below the horizon but night had not fully fallen."),
        LightReadingTemplate(text: "You walked through astronomical twilight, the faintest blush of light before true darkness."),
        LightReadingTemplate(text: "The walk was in twilight \u{2014} the sun below the horizon, the sky still holding color."),
        LightReadingTemplate(text: "Civil twilight. The light was dim but the sky still bright enough to navigate without a lamp."),
    ]

    private static let goldenHour: [LightReadingTemplate] = [
        LightReadingTemplate(text: "Golden hour followed you the whole way."),
        LightReadingTemplate(text: "You walked in the last hour of warm light before the sun touched the horizon."),
        LightReadingTemplate(text: "This walk happened in the golden hour \u{2014} the hour around sunrise when the light runs low and warm."),
        LightReadingTemplate(text: "The sun was close to the horizon during this walk. The light was long and amber."),
        LightReadingTemplate(text: "You walked in golden light. The sun was within an hour of rising or setting, casting long shadows."),
    ]

    private static let moonPhase: [LightReadingTemplate] = [
        LightReadingTemplate(text: "You walked under a {phaseName} moon, {pct}% illuminated."),
        LightReadingTemplate(text: "The moon was {phaseName} during this walk \u{2014} {pct}% lit."),
        LightReadingTemplate(text: "A {phaseName} moon was up when you walked. {pct}% of its face in sunlight."),
        LightReadingTemplate(text: "The moon was in its {phaseName} phase \u{2014} {pct}% illuminated."),
        LightReadingTemplate(text: "You walked by {phaseName} moonlight. The moon showed {pct}% of its face."),
    ]
}
