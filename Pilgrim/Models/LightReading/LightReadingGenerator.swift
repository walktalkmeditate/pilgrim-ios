import Foundation

enum LightReadingGenerator {

    static func generate(for walk: WalkInterface) -> LightReading {
        let seed = seedFor(walk: walk)
        var rng = SeededGenerator(seed: seed)
        let features = extractFeatures(from: walk)

        if let reading = evaluateLunarEclipse(features: features, rng: &rng) { return reading }
        if let reading = evaluateSupermoon(features: features, rng: &rng) { return reading }
        if let reading = evaluateSeasonalMarker(features: features, rng: &rng) { return reading }
        if let reading = evaluateMeteorShowerPeak(features: features, rng: &rng) { return reading }
        if let reading = evaluateFullMoon(features: features, rng: &rng) { return reading }
        if let reading = evaluateNewMoon(features: features, rng: &rng) { return reading }
        if let reading = evaluateDeepNight(features: features, rng: &rng) { return reading }
        if let reading = evaluateSunriseSunset(features: features, rng: &rng) { return reading }
        if let reading = evaluateGoldenHour(features: features, rng: &rng) { return reading }
        if let reading = evaluateTwilight(features: features, rng: &rng) { return reading }

        return evaluateMoonPhase(features: features, rng: &rng)
    }

    // MARK: - Features

    private struct Features {
        let walkDate: Date
        let latitude: Double?
        let longitude: Double?
        let illumination: Double
        let phase: CelestialCalculator.LunarPhase
        let horizon: SolarHorizon.HorizonTimes?
        let solarAltitude: Double?
        let T: Double
    }

    private static func extractFeatures(from walk: WalkInterface) -> Features {
        let walkDate = walk.startDate
        let latitude = walk.routeData.first?.latitude
        let longitude = walk.routeData.first?.longitude

        let jd = CelestialCalculator.julianDayNumber(from: walkDate)
        let T = CelestialCalculator.julianCenturies(from: jd)
        let illumination = CelestialCalculator.lunarIllumination(T: T)
        let phase = CelestialCalculator.lunarPhaseName(for: walkDate)

        var horizon: SolarHorizon.HorizonTimes?
        var altitude: Double?
        if let lat = latitude, let lon = longitude {
            horizon = SolarHorizon.compute(date: walkDate, latitude: lat, longitude: lon)
            altitude = SolarHorizon.solarAltitude(date: walkDate, latitude: lat, longitude: lon)
        }

        return Features(
            walkDate: walkDate,
            latitude: latitude,
            longitude: longitude,
            illumination: illumination,
            phase: phase,
            horizon: horizon,
            solarAltitude: altitude,
            T: T
        )
    }

    // MARK: - Tier evaluators

    private static func evaluateLunarEclipse(features: Features, rng: inout SeededGenerator) -> LightReading? {
        guard let event = AstronomicalEvents.eclipse(on: features.walkDate) else { return nil }
        let template = pickTemplate(for: .lunarEclipse, rng: &rng)
        let sentence = fillTemplate(template.text, values: [
            "pct": String(Int((event.magnitude * 100).rounded()))
        ])
        return LightReading(sentence: sentence, tier: .lunarEclipse, symbolName: "moon.circle.fill")
    }

    private static func evaluateSupermoon(features: Features, rng: inout SeededGenerator) -> LightReading? {
        guard let event = AstronomicalEvents.supermoon(near: features.walkDate) else { return nil }
        let template = pickTemplate(for: .supermoon, rng: &rng)
        let sentence = fillTemplate(template.text, values: [
            "month": monthName(for: event.date),
            "year": yearString(for: event.date),
            "distanceKm": String(event.distanceKm),
            "pct": String(Int((features.illumination * 100).rounded()))
        ])
        return LightReading(sentence: sentence, tier: .supermoon, symbolName: "moon.stars.fill")
    }

    private static func evaluateSeasonalMarker(features: Features, rng: inout SeededGenerator) -> LightReading? {
        let sunLon = CelestialCalculator.solarLongitude(T: features.T)
        guard let marker = CelestialCalculator.seasonalMarker(sunLongitude: sunLon) else { return nil }
        let template = LightReadingTemplates.seasonalMarkerTemplate(for: marker)
        return LightReading(sentence: template.text, tier: .seasonalMarker, symbolName: symbolForMarker(marker))
    }

    private static func evaluateMeteorShowerPeak(features: Features, rng: inout SeededGenerator) -> LightReading? {
        guard let shower = AstronomicalEvents.meteorShower(on: features.walkDate) else { return nil }
        let template = pickTemplate(for: .meteorShowerPeak, rng: &rng)
        let sentence = fillTemplate(template.text, values: [
            "showerName": shower.name,
            "zhr": String(shower.zhr)
        ])
        return LightReading(sentence: sentence, tier: .meteorShowerPeak, symbolName: "sparkles")
    }

    private static func evaluateFullMoon(features: Features, rng: inout SeededGenerator) -> LightReading? {
        guard features.illumination >= 0.95 else { return nil }
        let template = pickTemplate(for: .fullMoon, rng: &rng)
        let sentence = fillTemplate(template.text, values: [
            "pct": String(Int((features.illumination * 100).rounded())),
            "month": monthName(for: features.walkDate)
        ])
        return LightReading(sentence: sentence, tier: .fullMoon, symbolName: "moon.stars.fill")
    }

    private static func evaluateNewMoon(features: Features, rng: inout SeededGenerator) -> LightReading? {
        guard features.illumination <= 0.05 else { return nil }
        let template = pickTemplate(for: .newMoon, rng: &rng)
        let sentence = fillTemplate(template.text, values: [
            "pct": String(Int((features.illumination * 100).rounded()))
        ])
        return LightReading(sentence: sentence, tier: .newMoon, symbolName: "circle")
    }

    private static func evaluateDeepNight(features: Features, rng: inout SeededGenerator) -> LightReading? {
        guard let altitude = features.solarAltitude, altitude <= -18.0 else { return nil }
        guard features.illumination <= 0.10 else { return nil }
        let template = pickTemplate(for: .deepNight, rng: &rng)
        return LightReading(sentence: template.text, tier: .deepNight, symbolName: "sparkle")
    }

    private static func evaluateSunriseSunset(features: Features, rng: inout SeededGenerator) -> LightReading? {
        guard let horizon = features.horizon,
              let sunrise = horizon.sunrise,
              let sunset = horizon.sunset else { return nil }
        let walkDate = features.walkDate
        let sunriseDelta = abs(walkDate.timeIntervalSince(sunrise))
        let sunsetDelta = abs(walkDate.timeIntervalSince(sunset))
        let thirtyMin: TimeInterval = 30 * 60
        guard sunriseDelta <= thirtyMin || sunsetDelta <= thirtyMin else { return nil }
        let isSunrise = sunriseDelta <= sunsetDelta
        let edge = isSunrise ? sunrise : sunset
        let delta = isSunrise ? sunriseDelta : sunsetDelta
        let minutes = Int((delta / 60).rounded())
        let subPool = isSunrise ? LightReadingTemplates.sunriseTemplates() : LightReadingTemplates.sunsetTemplates()
        precondition(!subPool.isEmpty, "sunrise/sunset sub-pool empty")
        let template = subPool[Int(rng.next() % UInt64(subPool.count))]
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let timeString = formatter.string(from: edge)
        let sentence = fillTemplate(template.text, values: [
            "N": String(minutes),
            "time": timeString
        ])
        let symbol = isSunrise ? "sunrise" : "sunset"
        return LightReading(sentence: sentence, tier: .sunriseSunset, symbolName: symbol)
    }

    private static func evaluateTwilight(features: Features, rng: inout SeededGenerator) -> LightReading? {
        guard let altitude = features.solarAltitude else { return nil }
        // twilight: altitude in [-18, -6), goldenHour owns the -6° boundary
        guard altitude >= -18.0 && altitude < -6.0 else { return nil }
        let template = pickTemplate(for: .twilight, rng: &rng)
        return LightReading(sentence: template.text, tier: .twilight, symbolName: "sun.horizon")
    }

    private static func evaluateGoldenHour(features: Features, rng: inout SeededGenerator) -> LightReading? {
        guard let altitude = features.solarAltitude else { return nil }
        // goldenHour: altitude in [-6, +6], inclusive on both ends; twilight stops at -6
        guard altitude >= -6.0 && altitude <= 6.0 else { return nil }
        let template = pickTemplate(for: .goldenHour, rng: &rng)
        return LightReading(sentence: template.text, tier: .goldenHour, symbolName: "sun.haze")
    }

    private static func evaluateMoonPhase(features: Features, rng: inout SeededGenerator) -> LightReading {
        let template = pickTemplate(for: .moonPhase, rng: &rng)
        let sentence = fillTemplate(template.text, values: [
            "phaseName": features.phase.displayName,
            "pct": String(Int((features.illumination * 100).rounded()))
        ])
        return LightReading(sentence: sentence, tier: .moonPhase, symbolName: "moon.fill")
    }

    // MARK: - Template picking

    private static func pickTemplate(for tier: LightReading.Tier, rng: inout SeededGenerator) -> LightReadingTemplate {
        let templates = LightReadingTemplates.templates(for: tier)
        precondition(!templates.isEmpty, "Tier \(tier) has no templates")
        let index = Int(rng.next() % UInt64(templates.count))
        return templates[index]
    }

    // MARK: - Placeholder filling

    private static func fillTemplate(_ template: String, values: [String: String]) -> String {
        var result = template
        for (key, value) in values {
            result = result.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return result
    }

    // MARK: - Seasonal helpers

    private static func symbolForMarker(_ marker: SeasonalMarker) -> String {
        switch marker {
        case .springEquinox, .autumnEquinox: return "circle.lefthalf.filled"
        case .summerSolstice: return "sun.max"
        case .winterSolstice: return "moon.fill"
        case .imbolc, .beltane, .lughnasadh, .samhain: return "circle.dashed"
        }
    }

    // MARK: - Date formatting helpers

    private static func monthName(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "LLLL"
        return formatter.string(from: date)
    }

    private static func yearString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy"
        return formatter.string(from: date)
    }

    // MARK: - Seed

    private static func seedFor(walk: WalkInterface) -> UInt64 {
        if let uuid = walk.uuid {
            return LightReading.stableSeed(from: uuid)
        }
        return UInt64(bitPattern: Int64(walk.startDate.timeIntervalSince1970))
    }
}
