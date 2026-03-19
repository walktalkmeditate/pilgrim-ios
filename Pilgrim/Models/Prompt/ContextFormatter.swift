import Foundation

enum ContextFormatter {

    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static let distanceFormatter: MeasurementFormatter = {
        let f = MeasurementFormatter()
        f.unitOptions = .naturalScale
        f.numberFormatter.maximumFractionDigits = 1
        return f
    }()

    static func formatRecordings(_ recordings: [RecordingContext]) -> String {
        return recordings.map { item in
            var header = "[\(timeFormatter.string(from: item.timestamp))]"
            if let start = item.startCoordinate {
                header += " [GPS: \(formatCoord(start.lat, start.lon))"
                if let end = item.endCoordinate, end.lat != start.lat || end.lon != start.lon {
                    header += " → \(formatCoord(end.lat, end.lon))"
                }
                header += "]"
            }
            if let wpm = item.wordsPerMinute {
                header += " [~\(Int(wpm)) wpm, \(speakingPaceLabel(wpm))]"
            }
            return "\(header) \(item.text)"
        }.joined(separator: "\n\n")
    }

    static func formatPlaceNames(_ places: [PlaceContext]) -> String? {
        guard !places.isEmpty else { return nil }
        let start = places.first { $0.role == .start }
        let end = places.first { $0.role == .end }
        if let start = start, let end = end {
            return "**Location:** Started near \(start.name) → ended near \(end.name)"
        } else if let start = start {
            return "**Location:** Near \(start.name)"
        }
        return nil
    }

    static func formatMeditations(_ meditations: [MeditationContext]) -> String? {
        guard !meditations.isEmpty else { return nil }
        let lines = meditations.map { m in
            let durationSec = Int(m.duration)
            let durationStr = durationSec < 60 ? "\(durationSec) sec" : "\(durationSec / 60) min \(durationSec % 60) sec"
            return "[\(timeFormatter.string(from: m.startDate)) – \(timeFormatter.string(from: m.endDate))] Meditated for \(durationStr)"
        }
        return lines.joined(separator: "\n")
    }

    static func formatPaceContext(speeds: [Double]) -> String? {
        let moving = speeds.filter { $0 >= 0.3 }
        guard moving.count >= 10 else { return nil }
        let avgSpeed = moving.reduce(0, +) / Double(moving.count)
        guard let minSpeed = moving.min(), let maxSpeed = moving.max() else { return nil }
        let avgPace = formatPace(metersPerSecond: avgSpeed)
        let slowPace = formatPace(metersPerSecond: minSpeed)
        let fastPace = formatPace(metersPerSecond: maxSpeed)
        return "**Pace:** Average \(avgPace) (range: \(fastPace)–\(slowPace))"
    }

    static func formatRecentWalks(_ snippets: [WalkSnippet]) -> String? {
        guard !snippets.isEmpty else { return nil }
        let lines = snippets.map { snippet in
            let dateStr = shortDateFormatter.string(from: snippet.date)
            let weatherStr = snippet.weatherCondition
                .flatMap { WeatherCondition(rawValue: $0)?.label.lowercased() }
                .map { " in \($0)" } ?? ""
            if let place = snippet.placeName {
                return "[\(dateStr) – \(place)\(weatherStr)] \"\(snippet.transcriptionPreview)\""
            }
            return "[\(dateStr)\(weatherStr)] \"\(snippet.transcriptionPreview)\""
        }
        return "**Recent Walk Context (for continuity):**\n\n" + lines.joined(separator: "\n\n")
    }

    static func formatWeather(_ walk: WalkInterface) -> String? {
        guard let conditionStr = walk.weatherCondition,
              let condition = WeatherCondition(rawValue: conditionStr),
              let temp = walk.weatherTemperature else { return nil }

        let imperial = UserPreferences.distanceMeasurementType.safeValue == .miles
        var parts = [condition.label, WeatherSnapshot.formatTemperature(temp, imperial: imperial)]

        if let humidity = walk.weatherHumidity {
            parts.append("humidity \(Int(humidity * 100))%")
        }

        if let wind = walk.weatherWindSpeed {
            parts.append(WeatherSnapshot.describeWind(wind))
        }

        return "Weather: \(parts.joined(separator: ", "))"
    }

    static func formatMetadata(duration: Double, distance: Double, startDate: Date, lunarPhase: LunarPhase? = nil) -> String {
        let durationMin = Int(duration / 60)
        let distanceStr = distanceFormatter.string(from: Measurement(value: distance, unit: UnitLength.meters))
        let timeOfDay = timeOfDayDescription(startDate)

        let lunar = lunarPhase ?? LunarPhase.current(date: startDate)
        return "Walk duration: \(durationMin) minutes | Distance: \(distanceStr) | Time: \(timeOfDay) on \(dateTimeFormatter.string(from: startDate)) | Moon: \(lunar.name) (\(Int(round(lunar.illumination * 100)))% illumination)"
    }

    static func timeOfDayDescription(_ date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5..<9: return "early morning"
        case 9..<12: return "morning"
        case 12..<14: return "midday"
        case 14..<17: return "afternoon"
        case 17..<20: return "evening"
        default: return "night"
        }
    }

    static func speakingPaceLabel(_ wpm: Double) -> String {
        switch wpm {
        case ..<100: return "slow/thoughtful"
        case 100..<140: return "measured"
        case 140..<170: return "conversational"
        default: return "rapid/energized"
        }
    }

    static func formatCoord(_ lat: Double, _ lon: Double) -> String {
        String(format: "%.5f, %.5f", lat, lon)
    }

    static func formatPace(metersPerSecond: Double) -> String {
        guard metersPerSecond > 0 else { return "—" }
        let usesMiles = Locale.current.measurementSystem == .us
        let metersPerUnit: Double = usesMiles ? 1609.34 : 1000.0
        let label = usesMiles ? "min/mi" : "min/km"
        let secondsPerUnit = metersPerUnit / metersPerSecond
        let minutes = Int(secondsPerUnit) / 60
        let seconds = Int(secondsPerUnit) % 60
        return String(format: "%d:%02d %@", minutes, seconds, label)
    }

    static func formatCelestial(_ snapshot: CelestialSnapshot) -> String {
        let systemLabel = snapshot.system == .tropical ? "Tropical" : "Sidereal"
        var parts: [String] = []

        for position in snapshot.positions {
            let zodiac = snapshot.system == .tropical ? position.tropical : position.sidereal
            var entry = "\(position.planet.name) in \(zodiac.sign.name) (\(Int(zodiac.degree))\u{00B0})"
            if position.isRetrograde {
                entry += " Rx"
            }
            parts.append(entry)
        }

        var line = "**Celestial Context (\(systemLabel)):** \(parts.joined(separator: " | "))"

        line += " | Hour of \(snapshot.planetaryHour.planet.name)"

        if let dominant = snapshot.elementBalance.dominant {
            line += " | \(dominant.rawValue.capitalized) predominates"
        }

        let ingresses = snapshot.ingressPlanets
        for ingress in ingresses {
            let zodiac = snapshot.system == .tropical ? ingress.tropical : ingress.sidereal
            line += " | \(ingress.planet.name) enters \(zodiac.sign.name)"
        }

        if let marker = snapshot.seasonalMarker {
            line += " — \(marker.name)"
        }

        return line
    }
}
