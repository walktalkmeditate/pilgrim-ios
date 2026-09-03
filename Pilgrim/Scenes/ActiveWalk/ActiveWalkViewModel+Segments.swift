import CoreLocation
import Foundation

/// The walk's route-colouring derivation and the one duration formatter the
/// stat rows share. Split out of `ActiveWalkViewModel.swift`, which sits near
/// the `file_length` gate.
extension ActiveWalkViewModel {

    func activityType(at timestamp: Date) -> String {
        for interval in meditationIntervals {
            if timestamp >= interval.startDate && timestamp <= interval.endDate {
                return "meditating"
            }
        }
        if let start = meditationStartDate, timestamp >= start {
            return "meditating"
        }
        for recording in completedRecordings {
            if timestamp >= recording.startDate && timestamp <= recording.endDate {
                return "talking"
            }
        }
        if voiceRecordingManagement.isRecording,
           let recStart = voiceRecordingManagement.recordingStartDate,
           timestamp >= recStart {
            return "talking"
        }
        return "walking"
    }

    func buildActivitySegments(from samples: [TempRouteDataSample]) -> [RouteSegment] {
        guard samples.count > 1 else { return [] }

        var segments: [(type: String, indices: [Int])] = []
        var currentType = activityType(at: samples[0].timestamp)
        var currentIndices = [0]

        for i in 1..<samples.count {
            let type = activityType(at: samples[i].timestamp)
            if type == currentType {
                currentIndices.append(i)
            } else {
                currentIndices.append(i)
                segments.append((type: currentType, indices: currentIndices))
                currentType = type
                currentIndices = [i]
            }
        }
        segments.append((type: currentType, indices: currentIndices))

        return segments.map { segment in
            let coords = segment.indices.map { i in
                CLLocationCoordinate2D(latitude: samples[i].latitude, longitude: samples[i].longitude)
            }
            return RouteSegment(coordinates: coords, activityType: segment.type)
        }
    }

    func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
