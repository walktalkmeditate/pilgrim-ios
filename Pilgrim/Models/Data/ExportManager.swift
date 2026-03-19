import Foundation
import CoreGPX

public class ExportManager {

    static func createGPXFiles(for walks: [WalkInterface], completion: @escaping (_ success: Bool, _ urls: [URL]) -> Void) {
        let completion = safeClosure(from: completion)

        var urls = [URL]()

        for walk in walks {
            let metadata = GPXMetadata()
            metadata.desc = "This GPX-File was created by Pilgrim"
            metadata.time = Date()

            let trackPoints = walk.routeData.map { (sample) -> GPXTrackPoint in
                let trackPoint = GPXTrackPoint()
                trackPoint.latitude = sample.latitude
                trackPoint.longitude = sample.longitude
                trackPoint.elevation = sample.altitude
                trackPoint.time = sample.timestamp
                return trackPoint
            }

            let trackSegement = GPXTrackSegment()
            trackSegement.add(trackpoints: trackPoints)

            let track = GPXTrack()
            track.add(trackSegment: trackSegement)

            let root = GPXRoot(creator: "Pilgrim")
            root.metadata = metadata
            root.add(track: track)

            let fileName = CustomDateFormatting.backupTimeCode(forDate: walk.startDate)
            let directoryUrl = FileManager.default.temporaryDirectory
            let fullURL = directoryUrl.appendingPathComponent(fileName + ".gpx")

            do {
                try root.outputToFile(saveAt: directoryUrl, fileName: fileName)
                urls.append(fullURL)
            } catch {
                print("[ExportManager] Failed to save GPX file")
            }
        }

        completion(true, urls)
    }
}
