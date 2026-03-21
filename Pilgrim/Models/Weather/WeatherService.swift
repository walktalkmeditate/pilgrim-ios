import Foundation
import WeatherKit
import CoreLocation

enum WeatherCondition: String, Codable {
    case clear, partlyCloudy, overcast
    case lightRain, heavyRain, thunderstorm
    case snow, fog, wind, haze

    var icon: String {
        switch self {
        case .clear: return "sun.max.fill"
        case .partlyCloudy: return "cloud.sun.fill"
        case .overcast: return "cloud.fill"
        case .lightRain: return "cloud.drizzle.fill"
        case .heavyRain: return "cloud.heavyrain.fill"
        case .thunderstorm: return "cloud.bolt.fill"
        case .snow: return "cloud.snow.fill"
        case .fog: return "cloud.fog.fill"
        case .wind: return "wind"
        case .haze: return "sun.haze.fill"
        }
    }

    var label: String {
        switch self {
        case .clear: return "Clear"
        case .partlyCloudy: return "Partly cloudy"
        case .overcast: return "Overcast"
        case .lightRain: return "Light rain"
        case .heavyRain: return "Heavy rain"
        case .thunderstorm: return "Thunderstorm"
        case .snow: return "Snow"
        case .fog: return "Foggy"
        case .wind: return "Windy"
        case .haze: return "Hazy"
        }
    }
}

struct WeatherSnapshot: Codable {
    let condition: WeatherCondition
    let temperature: Double
    let humidity: Double
    let windSpeed: Double

    var windDescription: String {
        switch windSpeed {
        case ..<2: return "calm"
        case 2..<5: return "gentle breeze"
        case 5..<10: return "moderate wind"
        case 10..<15: return "strong wind"
        default: return "very strong wind"
        }
    }

    func formattedTemperature(imperial: Bool) -> String {
        Self.formatTemperature(temperature, imperial: imperial)
    }

    static func formatTemperature(_ celsius: Double, imperial: Bool) -> String {
        if imperial {
            return String(format: "%.0f°F", celsius * 9 / 5 + 32)
        }
        return String(format: "%.0f°C", celsius)
    }

    static func describeWind(_ metersPerSecond: Double) -> String {
        switch metersPerSecond {
        case ..<2: return "calm"
        case 2..<5: return "gentle breeze"
        case 5..<10: return "moderate wind"
        case 10..<15: return "strong wind"
        default: return "very strong wind"
        }
    }
}

final class WeatherService {

    static let shared = WeatherService()
    private let service = WeatherKit.WeatherService.shared
    private init() {}

    func fetchCurrent(for location: CLLocation) async -> WeatherSnapshot? {
        do {
            let weather = try await service.weather(for: location, including: .current)
            let windSpeedMS = weather.wind.speed.converted(to: .metersPerSecond).value
            let condition = mapCondition(weather.condition, windSpeed: windSpeedMS)
            let snapshot = WeatherSnapshot(
                condition: condition,
                temperature: weather.temperature.converted(to: .celsius).value,
                humidity: weather.humidity,
                windSpeed: windSpeedMS
            )
            return snapshot
        } catch {
            return await fetchViaREST(location: location)
        }
    }

    private func fetchViaREST(location: CLLocation) async -> WeatherSnapshot? {
        guard WeatherKitREST.shared.isConfigured else {
            print("[WeatherService] REST fallback not configured")
            return nil
        }
        let snapshot = await WeatherKitREST.shared.fetchCurrent(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )
        return snapshot
    }

    private func mapCondition(_ condition: WeatherKit.WeatherCondition, windSpeed: Double) -> WeatherCondition {
        if windSpeed > 10 { return .wind }

        switch condition {
        case .clear, .mostlyClear, .hot:
            return .clear
        case .partlyCloudy:
            return .partlyCloudy
        case .cloudy, .mostlyCloudy:
            return .overcast
        case .drizzle:
            return .lightRain
        case .rain:
            return windSpeed > 5 ? .heavyRain : .lightRain
        case .heavyRain:
            return .heavyRain
        case .thunderstorms, .tropicalStorm, .hurricane, .isolatedThunderstorms, .scatteredThunderstorms, .strongStorms:
            return .thunderstorm
        case .snow, .flurries, .sleet, .freezingRain, .blizzard, .heavySnow, .freezingDrizzle, .blowingSnow, .wintryMix:
            return .snow
        case .foggy:
            return .fog
        case .windy, .breezy:
            return .wind
        case .haze, .smoky, .blowingDust:
            return .haze
        @unknown default:
            return .clear
        }
    }
}
