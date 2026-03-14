#if DEBUG
import Foundation

enum DebugDataSeeder {

    struct WalkSpec {
        let daysAgo: Int
        let hour: Int
        let distanceMeters: Double
        let durationMinutes: Double
        let latitude: Double
        let longitude: Double
        let talkMinutes: Double
        let meditateMinutes: Double

        init(daysAgo: Int, hour: Int, distanceMeters: Double, durationMinutes: Double,
             latitude: Double, longitude: Double,
             talkMinutes: Double = 0, meditateMinutes: Double = 0) {
            self.daysAgo = daysAgo; self.hour = hour
            self.distanceMeters = distanceMeters; self.durationMinutes = durationMinutes
            self.latitude = latitude; self.longitude = longitude
            self.talkMinutes = talkMinutes; self.meditateMinutes = meditateMinutes
        }
    }

    static let walks: [WalkSpec] = [
        // Winter — January/February
        WalkSpec(daysAgo: 430, hour: 10, distanceMeters: 2100, durationMinutes: 35, latitude: 35.6762, longitude: 139.6503, meditateMinutes: 5),
        WalkSpec(daysAgo: 415, hour: 8, distanceMeters: 1500, durationMinutes: 25, latitude: 35.6762, longitude: 139.6503),
        WalkSpec(daysAgo: 400, hour: 14, distanceMeters: 3200, durationMinutes: 55, latitude: 35.6762, longitude: 139.6503, talkMinutes: 8),
        WalkSpec(daysAgo: 390, hour: 11, distanceMeters: 1800, durationMinutes: 40, latitude: 35.6762, longitude: 139.6503, meditateMinutes: 10),

        // Spring — March/April
        WalkSpec(daysAgo: 370, hour: 7, distanceMeters: 4500, durationMinutes: 70, latitude: 35.0116, longitude: 135.7681, talkMinutes: 12, meditateMinutes: 8),
        WalkSpec(daysAgo: 355, hour: 9, distanceMeters: 5200, durationMinutes: 80, latitude: 35.0116, longitude: 135.7681),
        WalkSpec(daysAgo: 345, hour: 6, distanceMeters: 8000, durationMinutes: 120, latitude: 35.0116, longitude: 135.7681, talkMinutes: 15, meditateMinutes: 10),
        WalkSpec(daysAgo: 335, hour: 8, distanceMeters: 3800, durationMinutes: 60, latitude: 35.0116, longitude: 135.7681, meditateMinutes: 15),
        WalkSpec(daysAgo: 320, hour: 7, distanceMeters: 6500, durationMinutes: 100, latitude: 34.6937, longitude: 135.5023, talkMinutes: 20),

        // Summer — June/July
        WalkSpec(daysAgo: 290, hour: 5, distanceMeters: 12000, durationMinutes: 180, latitude: 34.6937, longitude: 135.5023, talkMinutes: 25, meditateMinutes: 15),
        WalkSpec(daysAgo: 275, hour: 6, distanceMeters: 15000, durationMinutes: 220, latitude: 34.6937, longitude: 135.5023, talkMinutes: 30),
        WalkSpec(daysAgo: 265, hour: 16, distanceMeters: 3500, durationMinutes: 50, latitude: 34.6937, longitude: 135.5023),
        WalkSpec(daysAgo: 255, hour: 7, distanceMeters: 9800, durationMinutes: 150, latitude: 34.6937, longitude: 135.5023, meditateMinutes: 20),
        WalkSpec(daysAgo: 245, hour: 5, distanceMeters: 18000, durationMinutes: 280, latitude: 34.6937, longitude: 135.5023, talkMinutes: 35, meditateMinutes: 25),
        WalkSpec(daysAgo: 235, hour: 8, distanceMeters: 7200, durationMinutes: 110, latitude: 43.0618, longitude: 141.3545, talkMinutes: 10),

        // Autumn — September/October
        WalkSpec(daysAgo: 200, hour: 9, distanceMeters: 6000, durationMinutes: 105, latitude: 43.0618, longitude: 141.3545, meditateMinutes: 20),
        WalkSpec(daysAgo: 185, hour: 10, distanceMeters: 4200, durationMinutes: 75, latitude: 43.0618, longitude: 141.3545, talkMinutes: 8),
        WalkSpec(daysAgo: 170, hour: 14, distanceMeters: 2800, durationMinutes: 50, latitude: 43.0618, longitude: 141.3545),
        WalkSpec(daysAgo: 160, hour: 8, distanceMeters: 10500, durationMinutes: 165, latitude: 43.0618, longitude: 141.3545, talkMinutes: 18, meditateMinutes: 12),
        WalkSpec(daysAgo: 150, hour: 7, distanceMeters: 5500, durationMinutes: 90, latitude: 35.6762, longitude: 139.6503, meditateMinutes: 15),

        // Late autumn/early winter
        WalkSpec(daysAgo: 130, hour: 11, distanceMeters: 3000, durationMinutes: 55, latitude: 35.6762, longitude: 139.6503, talkMinutes: 10),
        WalkSpec(daysAgo: 115, hour: 10, distanceMeters: 4800, durationMinutes: 80, latitude: 35.6762, longitude: 139.6503, meditateMinutes: 10),
        WalkSpec(daysAgo: 100, hour: 9, distanceMeters: 2200, durationMinutes: 40, latitude: 35.6762, longitude: 139.6503),

        // Recent
        WalkSpec(daysAgo: 80, hour: 10, distanceMeters: 3500, durationMinutes: 60, latitude: 35.6762, longitude: 139.6503, talkMinutes: 8, meditateMinutes: 8),
        WalkSpec(daysAgo: 65, hour: 8, distanceMeters: 5000, durationMinutes: 85, latitude: 35.0116, longitude: 135.7681, meditateMinutes: 12),
        WalkSpec(daysAgo: 50, hour: 7, distanceMeters: 7500, durationMinutes: 115, latitude: 35.0116, longitude: 135.7681, talkMinutes: 15),
        WalkSpec(daysAgo: 35, hour: 9, distanceMeters: 4000, durationMinutes: 65, latitude: 35.0116, longitude: 135.7681),
        WalkSpec(daysAgo: 20, hour: 6, distanceMeters: 11000, durationMinutes: 170, latitude: 34.6937, longitude: 135.5023, talkMinutes: 22, meditateMinutes: 18),
        WalkSpec(daysAgo: 10, hour: 8, distanceMeters: 6200, durationMinutes: 95, latitude: 34.6937, longitude: 135.5023, talkMinutes: 12),
        WalkSpec(daysAgo: 5, hour: 7, distanceMeters: 8500, durationMinutes: 130, latitude: 34.6937, longitude: 135.5023, meditateMinutes: 20),
        WalkSpec(daysAgo: 2, hour: 9, distanceMeters: 3200, durationMinutes: 55, latitude: 34.6937, longitude: 135.5023, talkMinutes: 6),
        WalkSpec(daysAgo: 1, hour: 10, distanceMeters: 4500, durationMinutes: 70, latitude: 34.6937, longitude: 135.5023, talkMinutes: 10, meditateMinutes: 8),
    ]

    static func seed(completion: @escaping (Int) -> Void) {
        let calendar = Calendar.current
        let now = Date()
        var savedCount = 0
        let total = walks.count

        for spec in walks {
            guard let startDate = calendar.date(byAdding: .day, value: -spec.daysAgo, to: now),
                  let adjustedStart = calendar.date(bySettingHour: spec.hour, minute: 0, second: 0, of: startDate) else {
                savedCount += 1
                if savedCount == total { completion(total) }
                continue
            }

            let endDate = adjustedStart.addingTimeInterval(spec.durationMinutes * 60)

            let routeSample = TempRouteDataSample(
                uuid: nil,
                timestamp: adjustedStart,
                latitude: spec.latitude,
                longitude: spec.longitude,
                altitude: 50 + Double.random(in: -30...100),
                horizontalAccuracy: 5,
                verticalAccuracy: 3,
                speed: spec.distanceMeters / (spec.durationMinutes * 60),
                direction: Double.random(in: 0..<360)
            )

            var voiceRecordings: [TempV4.VoiceRecording] = []
            if spec.talkMinutes > 0 {
                let talkStart = adjustedStart.addingTimeInterval(spec.durationMinutes * 60 * 0.2)
                let talkEnd = talkStart.addingTimeInterval(spec.talkMinutes * 60)
                voiceRecordings.append(TempVoiceRecording(
                    uuid: nil,
                    startDate: talkStart,
                    endDate: talkEnd,
                    duration: spec.talkMinutes * 60,
                    fileRelativePath: "debug/talk-\(spec.daysAgo).m4a",
                    transcription: nil
                ))
            }

            var activityIntervals: [TempV4.ActivityInterval] = []
            if spec.meditateMinutes > 0 {
                let medStart = adjustedStart.addingTimeInterval(spec.durationMinutes * 60 * 0.6)
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
                steps: Int(spec.distanceMeters / 0.75),
                startDate: adjustedStart,
                endDate: endDate,
                isRace: false,
                comment: nil,
                isUserModified: false,
                finishedRecording: true,
                heartRates: [],
                routeData: [routeSample],
                pauses: [],
                workoutEvents: [],
                voiceRecordings: voiceRecordings,
                activityIntervals: activityIntervals
            )

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
