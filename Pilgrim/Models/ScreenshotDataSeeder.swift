#if DEBUG
import Foundation

enum ScreenshotDataSeeder {

    private static let intentions = [
        "Walk slowly today. Notice what you usually miss.",
        "Gratitude for this body that carries me",
        "Let the path decide where we go",
        "Breathe with each step",
        "Be present"
    ]

    private static let transcriptions = [
        "The morning light through the trees was extraordinary. I stopped and just watched it move across the path for a while.",
        "I keep coming back to this idea that walking is thinking. The rhythm of it loosens something in my mind.",
        "Heard a bird I couldn't identify. Something between a whistle and a question. Made me smile.",
        "The wind picked up and I felt completely alive. Not happy or sad, just... present.",
        "There's a bend in the trail where you can see the whole valley. Stood there until my breathing matched the clouds."
    ]

    struct ScreenshotWalk {
        let daysAgo: Int
        let hour: Int
        let distanceMeters: Double
        let durationMinutes: Double
        let steps: Int
        let latitude: Double
        let longitude: Double
        let altitudeBase: Double
        let ascend: Double
        let descend: Double
        let talkMinutes: Double
        let meditateMinutes: Double
        let intention: String?
        let transcription: String?
        let favicon: String?
        let weatherCondition: String?
        let weatherTemperature: Double?
        let weatherHumidity: Double?
        let weatherWindSpeed: Double?
        let routePoints: [(lat: Double, lon: Double, alt: Double)]
    }

    static let walks: [ScreenshotWalk] = [
        ScreenshotWalk(
            daysAgo: 1, hour: 7, distanceMeters: 8200, durationMinutes: 105, steps: 10933,
            latitude: 42.8782, longitude: -8.5448, altitudeBase: 280,
            ascend: 145, descend: 120,
            talkMinutes: 8, meditateMinutes: 15,
            intention: intentions[0],
            transcription: transcriptions[0],
            favicon: "flame",
            weatherCondition: "partlyCloudy", weatherTemperature: 14.5, weatherHumidity: 0.72, weatherWindSpeed: 2.8,
            routePoints: [
                (42.8782, -8.5448, 280), (42.8790, -8.5430, 285), (42.8810, -8.5405, 310),
                (42.8835, -8.5380, 340), (42.8860, -8.5355, 370), (42.8880, -8.5330, 395),
                (42.8895, -8.5300, 410), (42.8910, -8.5270, 390), (42.8930, -8.5240, 365),
                (42.8950, -8.5210, 345), (42.8970, -8.5185, 330), (42.8985, -8.5160, 310)
            ]
        ),
        ScreenshotWalk(
            daysAgo: 4, hour: 6, distanceMeters: 14500, durationMinutes: 195, steps: 19333,
            latitude: 42.9340, longitude: -8.4570, altitudeBase: 220,
            ascend: 280, descend: 245,
            talkMinutes: 22, meditateMinutes: 25,
            intention: intentions[1],
            transcription: transcriptions[1],
            favicon: "star",
            weatherCondition: "clear", weatherTemperature: 18.0, weatherHumidity: 0.55, weatherWindSpeed: 1.2,
            routePoints: [
                (42.9340, -8.4570, 220), (42.9360, -8.4530, 235), (42.9390, -8.4480, 260),
                (42.9420, -8.4420, 290), (42.9455, -8.4360, 340), (42.9480, -8.4300, 380),
                (42.9510, -8.4240, 420), (42.9540, -8.4180, 460), (42.9560, -8.4120, 440),
                (42.9580, -8.4060, 400), (42.9600, -8.4000, 370), (42.9620, -8.3940, 350),
                (42.9640, -8.3880, 330), (42.9660, -8.3820, 310), (42.9675, -8.3760, 290)
            ]
        ),
        ScreenshotWalk(
            daysAgo: 8, hour: 16, distanceMeters: 3800, durationMinutes: 55, steps: 5066,
            latitude: 42.8800, longitude: -8.5440, altitudeBase: 260,
            ascend: 35, descend: 40,
            talkMinutes: 0, meditateMinutes: 20,
            intention: intentions[3],
            transcription: nil,
            favicon: "leaf",
            weatherCondition: "cloudy", weatherTemperature: 11.0, weatherHumidity: 0.85, weatherWindSpeed: 4.5,
            routePoints: [
                (42.8800, -8.5440, 260), (42.8810, -8.5420, 265), (42.8825, -8.5395, 275),
                (42.8840, -8.5370, 285), (42.8850, -8.5350, 290), (42.8840, -8.5330, 280),
                (42.8825, -8.5315, 270), (42.8810, -8.5330, 265), (42.8800, -8.5350, 260)
            ]
        ),
        ScreenshotWalk(
            daysAgo: 12, hour: 9, distanceMeters: 6100, durationMinutes: 82, steps: 8133,
            latitude: 42.9100, longitude: -8.5200, altitudeBase: 310,
            ascend: 95, descend: 110,
            talkMinutes: 12, meditateMinutes: 0,
            intention: intentions[2],
            transcription: transcriptions[2],
            favicon: nil,
            weatherCondition: "clear", weatherTemperature: 16.0, weatherHumidity: 0.60, weatherWindSpeed: 1.8,
            routePoints: [
                (42.9100, -8.5200, 310), (42.9120, -8.5170, 325), (42.9145, -8.5135, 355),
                (42.9170, -8.5100, 380), (42.9190, -8.5065, 395), (42.9210, -8.5030, 370),
                (42.9225, -8.5000, 345), (42.9240, -8.4970, 320), (42.9255, -8.4940, 300),
                (42.9265, -8.4920, 290)
            ]
        ),
        ScreenshotWalk(
            daysAgo: 18, hour: 7, distanceMeters: 11200, durationMinutes: 150, steps: 14933,
            latitude: 42.8650, longitude: -8.5600, altitudeBase: 200,
            ascend: 210, descend: 195,
            talkMinutes: 18, meditateMinutes: 12,
            intention: intentions[4],
            transcription: transcriptions[4],
            favicon: "flame",
            weatherCondition: "partlyCloudy", weatherTemperature: 13.0, weatherHumidity: 0.68, weatherWindSpeed: 3.2,
            routePoints: [
                (42.8650, -8.5600, 200), (42.8670, -8.5560, 215), (42.8700, -8.5510, 240),
                (42.8735, -8.5460, 275), (42.8770, -8.5410, 310), (42.8800, -8.5360, 350),
                (42.8830, -8.5310, 380), (42.8855, -8.5260, 400), (42.8875, -8.5210, 385),
                (42.8895, -8.5160, 360), (42.8910, -8.5110, 335), (42.8925, -8.5060, 310),
                (42.8935, -8.5010, 290)
            ]
        ),
    ]

    static func seed(completion: @escaping (Int) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        var savedCount = 0
        let total = walks.count

        for (index, spec) in walks.enumerated() {
            guard let startDate = calendar.date(byAdding: .day, value: -spec.daysAgo, to: now),
                  let adjustedStart = calendar.date(bySettingHour: spec.hour, minute: Int.random(in: 0...45), second: 0, of: startDate) else {
                savedCount += 1
                if savedCount == total { completion(total) }
                continue
            }

            let endDate = adjustedStart.addingTimeInterval(spec.durationMinutes * 60)

            let routeData: [TempRouteDataSample] = spec.routePoints.enumerated().map { pointIndex, point in
                let fraction = Double(pointIndex) / Double(max(1, spec.routePoints.count - 1))
                let timestamp = adjustedStart.addingTimeInterval(spec.durationMinutes * 60 * fraction)
                return TempRouteDataSample(
                    uuid: nil,
                    timestamp: timestamp,
                    latitude: point.lat,
                    longitude: point.lon,
                    altitude: point.alt,
                    horizontalAccuracy: Double.random(in: 3...8),
                    verticalAccuracy: Double.random(in: 2...5),
                    speed: spec.distanceMeters / (spec.durationMinutes * 60) + Double.random(in: -0.3...0.3),
                    direction: Double.random(in: 0..<360)
                )
            }

            var voiceRecordings: [TempV4.VoiceRecording] = []
            if spec.talkMinutes > 0 {
                let talkStart = adjustedStart.addingTimeInterval(spec.durationMinutes * 60 * 0.25)
                let talkEnd = talkStart.addingTimeInterval(spec.talkMinutes * 60)
                voiceRecordings.append(TempVoiceRecording(
                    uuid: nil,
                    startDate: talkStart,
                    endDate: talkEnd,
                    duration: spec.talkMinutes * 60,
                    fileRelativePath: "demo/recording-\(index).m4a",
                    transcription: spec.transcription
                ))
            }

            var activityIntervals: [TempV4.ActivityInterval] = []
            if spec.meditateMinutes > 0 {
                let medStart = adjustedStart.addingTimeInterval(spec.durationMinutes * 60 * 0.55)
                let medEnd = medStart.addingTimeInterval(spec.meditateMinutes * 60)
                activityIntervals.append(TempActivityInterval(
                    uuid: nil,
                    activityType: .meditation,
                    startDate: medStart,
                    endDate: medEnd
                ))
            }

            let walk = NewWalk(
                workoutType: .walking,
                distance: spec.distanceMeters,
                steps: spec.steps,
                startDate: adjustedStart,
                endDate: endDate,
                isRace: false,
                comment: spec.intention,
                isUserModified: false,
                finishedRecording: true,
                heartRates: [],
                routeData: routeData,
                pauses: [],
                workoutEvents: [],
                voiceRecordings: voiceRecordings,
                activityIntervals: activityIntervals,
                weatherCondition: spec.weatherCondition,
                weatherTemperature: spec.weatherTemperature,
                weatherHumidity: spec.weatherHumidity,
                weatherWindSpeed: spec.weatherWindSpeed
            )
            walk.favicon = spec.favicon

            DataManager.saveWalk(object: walk) { _, _, _ in
                savedCount += 1
                if savedCount == total {
                    completion(total)
                }
            }
        }
    }
}
#endif
