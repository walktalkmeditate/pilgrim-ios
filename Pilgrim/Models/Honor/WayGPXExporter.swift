#if DEBUG
import Foundation

/// Xcode's Core Location simulation reads only <wpt> elements and paces
/// timed waypoints at the speed their timestamps dictate. One <wpt> per
/// route point, in order; moment ids ride on the nearest route point's
/// <name> so nothing hops the simulator off the Way.
enum WayGPXExporter {

    static func gpx(for way: Way) -> Data {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        var names: [Int: [String]] = [:]
        for moment in way.moments {
            let target = moment.frac * Double(max(way.route.count - 1, 0))
            names[Int(target.rounded()), default: []].append(moment.id)
        }
        var lines = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<gpx version=\"1.1\" creator=\"Pilgrim\" xmlns=\"http://www.topografix.com/GPX/1/1\">"
        ]
        for (index, point) in way.route.enumerated() {
            lines.append("  <wpt lat=\"\(point.lat)\" lon=\"\(point.lon)\">")
            if let alt = point.alt { lines.append("    <ele>\(Int(alt.rounded()))</ele>") }
            lines.append("    <time>\(formatter.string(from: way.departedAt.addingTimeInterval(point.t)))</time>")
            if let ids = names[index] { lines.append("    <name>\(ids.joined(separator: " "))</name>") }
            lines.append("  </wpt>")
        }
        lines.append("</gpx>")
        return Data(lines.joined(separator: "\n").utf8)
    }
}
#endif
