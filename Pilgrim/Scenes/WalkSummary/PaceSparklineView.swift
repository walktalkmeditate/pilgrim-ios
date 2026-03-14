import SwiftUI

struct PaceSparklineView: View {

    let routeData: [RouteDataSampleInterface]
    let startDate: Date
    let endDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let label = averagePaceLabel {
                Text(label)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }

            GeometryReader { geo in
                let points = sparklinePoints(in: geo.size)
                if points.count >= 2 {
                    ZStack {
                        fillPath(points: points, height: geo.size.height)
                        linePath(points: points)
                    }
                }
            }
        }
    }

    private func fillPath(points: [CGPoint], height: CGFloat) -> some View {
        Path { path in
            path.move(to: CGPoint(x: points[0].x, y: height))
            for point in points { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: points.last!.x, y: height))
            path.closeSubpath()
        }
        .fill(
            LinearGradient(
                colors: [Color.stone.opacity(0.12), Color.stone.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private func linePath(points: [CGPoint]) -> some View {
        Path { path in
            path.move(to: points[0])
            for point in points.dropFirst() { path.addLine(to: point) }
        }
        .stroke(Color.stone.opacity(0.45), lineWidth: 1.5)
    }

    private func sparklinePoints(in size: CGSize) -> [CGPoint] {
        let samples = routeData
            .filter { $0.speed > 0.3 }
            .sorted { $0.timestamp < $1.timestamp }
        guard samples.count >= 3 else { return [] }

        let total = max(1, startDate.distance(to: endDate))
        let step = max(1, samples.count / 50)
        var buckets: [(fraction: CGFloat, speed: Double)] = []

        for i in stride(from: 0, to: samples.count, by: step) {
            let end = min(i + step, samples.count)
            let window = samples[i..<end]
            let avgSpeed = window.map(\.speed).reduce(0, +) / Double(window.count)
            let midSample = window[window.startIndex + window.count / 2]
            let fraction = CGFloat(startDate.distance(to: midSample.timestamp) / total)
            buckets.append((Swift.min(Swift.max(fraction, 0), 1), avgSpeed))
        }

        guard let maxSpeed = buckets.map(\.speed).max(), maxSpeed > 0 else { return [] }

        return buckets.map { item in
            CGPoint(
                x: item.fraction * size.width,
                y: size.height * (1 - CGFloat(item.speed / maxSpeed) * 0.85)
            )
        }
    }

    private var averagePaceLabel: String? {
        let speeds = routeData.filter { $0.speed > 0.3 }.map(\.speed)
        guard !speeds.isEmpty else { return nil }
        let avg = speeds.reduce(0, +) / Double(speeds.count)
        return "Pace \(formatPace(avg)) /km"
    }

    private func formatPace(_ metersPerSecond: Double) -> String {
        guard metersPerSecond > 0 else { return "--" }
        let secondsPerKm = 1000.0 / metersPerSecond
        let minutes = Int(secondsPerKm) / 60
        let seconds = Int(secondsPerKm) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

