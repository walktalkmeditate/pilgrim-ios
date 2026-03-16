import SwiftUI

struct RouteShapeView: View {
    let routeData: [RouteDataSampleInterface]

    var body: some View {
        GeometryReader { geo in
            let points = projectRoute(in: geo.size)
            if points.count >= 2 {
                Path { path in
                    path.move(to: points[0])
                    for i in 1..<points.count {
                        path.addLine(to: points[i])
                    }
                }
                .stroke(Color.stone, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

                Circle()
                    .fill(Color.moss)
                    .frame(width: 8, height: 8)
                    .position(points[0])

                Circle()
                    .stroke(Color.moss, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
                    .position(points[points.count - 1])
            }
        }
        .padding(Constants.UI.Padding.big)
    }

    private func projectRoute(in size: CGSize) -> [CGPoint] {
        guard routeData.count >= 2 else { return [] }

        var minLat = Double.infinity
        var maxLat = -Double.infinity
        var minLon = Double.infinity
        var maxLon = -Double.infinity

        for sample in routeData {
            if sample.latitude < minLat { minLat = sample.latitude }
            if sample.latitude > maxLat { maxLat = sample.latitude }
            if sample.longitude < minLon { minLon = sample.longitude }
            if sample.longitude > maxLon { maxLon = sample.longitude }
        }

        let latRange = maxLat - minLat
        let lonRange = maxLon - minLon
        guard latRange > 0 || lonRange > 0 else { return [] }

        let padding: CGFloat = 0
        let w = size.width - padding * 2
        let h = size.height - padding * 2

        let scale = min(
            lonRange > 0 ? w / lonRange : .infinity,
            latRange > 0 ? h / latRange : .infinity
        )

        let routeW = lonRange * scale
        let routeH = latRange * scale
        let offsetX = padding + (w - routeW) / 2
        let offsetY = padding + (h - routeH) / 2

        let step = max(1, routeData.count / 200)
        var points: [CGPoint] = []
        for i in stride(from: 0, to: routeData.count, by: step) {
            let s = routeData[i]
            let x = offsetX + (s.longitude - minLon) * scale
            let y = offsetY + (maxLat - s.latitude) * scale
            points.append(CGPoint(x: x, y: y))
        }

        let last = routeData[routeData.count - 1]
        let lastPoint = CGPoint(
            x: offsetX + (last.longitude - minLon) * scale,
            y: offsetY + (maxLat - last.latitude) * scale
        )
        if points.last != lastPoint {
            points.append(lastPoint)
        }

        return points
    }
}
