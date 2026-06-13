import Foundation
import CryptoKit

final class WeatherKitREST {

    static let shared = WeatherKitREST()
    private init() {}

    private var keyID: String? {
        Bundle.main.infoDictionary?["WeatherKitKeyID"] as? String
    }

    private var teamID: String? {
        Bundle.main.infoDictionary?["WeatherKitTeamID"] as? String
    }

    private var privateKeyPEM: String? {
        guard let b64 = Bundle.main.infoDictionary?["WeatherKitPrivateKey"] as? String,
              let data = Data(base64Encoded: b64) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    var isConfigured: Bool {
        keyID != nil && teamID != nil && privateKeyPEM != nil
    }

    func fetchCurrent(latitude: Double, longitude: Double) async -> WeatherSnapshot? {
        guard let jwt = try? createJWT() else {
            print("[WeatherKitREST] JWT creation failed")
            return nil
        }

        let urlStr = "https://weatherkit.apple.com/api/v1/weather/en/\(latitude)/\(longitude)?dataSets=currentWeather"
        guard let url = URL(string: urlStr) else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(jwt)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return nil }

            guard httpResponse.statusCode == 200 else {
                let body = String(data: data, encoding: .utf8) ?? ""
                print("[WeatherKitREST] HTTP \(httpResponse.statusCode): \(body)")
                return nil
            }

            return try parseResponse(data)
        } catch {
            print("[WeatherKitREST] Failed: \(error)")
            return nil
        }
    }

    private func createJWT() throws -> String {
        guard let keyID, let teamID, let pem = privateKeyPEM else {
            throw WeatherKitRESTError.notConfigured
        }

        let privateKey = try P256.Signing.PrivateKey(pemRepresentation: pem)
        let serviceID = "org.walktalkmeditate.pilgrim.weather"

        let header = "{\"alg\":\"ES256\",\"kid\":\"\(keyID)\",\"id\":\"\(teamID).\(serviceID)\"}"
        let now = Int(Date().timeIntervalSince1970)
        let payload = "{\"iss\":\"\(teamID)\",\"iat\":\(now),\"exp\":\(now + 3600),\"sub\":\"\(serviceID)\"}"

        let headerB64 = Data(header.utf8).base64URLEncoded
        let payloadB64 = Data(payload.utf8).base64URLEncoded
        let signingInput = Data("\(headerB64).\(payloadB64)".utf8)

        let signature = try privateKey.signature(for: signingInput)
        let signatureB64 = signature.rawRepresentation.base64URLEncoded

        return "\(headerB64).\(payloadB64).\(signatureB64)"
    }

    private func parseResponse(_ data: Data) throws -> WeatherSnapshot? {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            print("[WeatherKitREST] Not valid JSON")
            return nil
        }

        guard let currentWeather = json["currentWeather"] as? [String: Any] else {
            print("[WeatherKitREST] No currentWeather in response")
            return nil
        }

        guard let conditionCode = currentWeather["conditionCode"] as? String else {
            print("[WeatherKitREST] No conditionCode")
            return nil
        }

        let tempValue: Double
        if let t = currentWeather["temperature"] as? Double {
            tempValue = t
        } else if let td = currentWeather["temperature"] as? [String: Any], let tv = td["value"] as? Double {
            tempValue = tv
        } else {
            print("[WeatherKitREST] No temperature")
            return nil
        }

        let humidityValue = currentWeather["humidity"] as? Double ?? 0

        let windSpeed: Double
        if let windDict = currentWeather["windSpeed"] as? [String: Any],
           let ws = windDict["value"] as? Double {
            windSpeed = ws / 3.6
        } else {
            windSpeed = 0
        }

        let condition = mapConditionCode(conditionCode, windSpeed: windSpeed)
        return WeatherSnapshot(
            condition: condition,
            temperature: tempValue,
            humidity: humidityValue,
            windSpeed: windSpeed
        )
    }

    private func mapConditionCode(_ code: String, windSpeed: Double) -> WeatherCondition {
        if windSpeed > 10 { return .wind }

        switch code {
        case "Clear", "MostlyClear", "Hot":
            return .clear
        case "PartlyCloudy":
            return .partlyCloudy
        case "Cloudy", "MostlyCloudy":
            return .overcast
        case "Drizzle":
            return .lightRain
        case "Rain":
            return windSpeed > 5 ? .heavyRain : .lightRain
        case "HeavyRain":
            return .heavyRain
        case "Thunderstorms", "TropicalStorm", "Hurricane", "IsolatedThunderstorms", "ScatteredThunderstorms", "StrongStorms":
            return .thunderstorm
        case "Snow", "Flurries", "Sleet", "FreezingRain", "Blizzard", "HeavySnow", "FreezingDrizzle", "BlowingSnow", "WintryMix":
            return .snow
        case "Foggy":
            return .fog
        case "Windy", "Breezy":
            return .wind
        case "Haze", "Smoky", "BlowingDust":
            return .haze
        default:
            return .clear
        }
    }

    enum WeatherKitRESTError: Error {
        case notConfigured
    }
}

private extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
