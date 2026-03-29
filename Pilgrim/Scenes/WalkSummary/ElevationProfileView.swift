import SwiftUI

struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.stone)
            Text(value)
                .font(Constants.Typography.statValue)
                .foregroundColor(.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(title)
                .font(Constants.Typography.statLabel)
                .foregroundColor(.fog)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }
}

struct ElevationProfileView: View {
    let altitudes: [Double]
    let minAlt: Double
    let maxAlt: Double

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let range = max(maxAlt - minAlt, 1)
                let step = max(1, altitudes.count / Int(geo.size.width))
                let sampled = stride(from: 0, to: altitudes.count, by: step).map { altitudes[$0] }

                ZStack(alignment: .bottom) {
                    Path { path in
                        guard sampled.count > 1 else { return }
                        let w = geo.size.width
                        let h = geo.size.height

                        path.move(to: CGPoint(x: 0, y: h))
                        for (i, alt) in sampled.enumerated() {
                            let x = w * CGFloat(i) / CGFloat(sampled.count - 1)
                            let y = h * (1 - CGFloat((alt - minAlt) / range))
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                        path.addLine(to: CGPoint(x: w, y: h))
                        path.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [Color.stone.opacity(0.3), Color.stone.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    Path { path in
                        guard sampled.count > 1 else { return }
                        let w = geo.size.width
                        let h = geo.size.height

                        for (i, alt) in sampled.enumerated() {
                            let x = w * CGFloat(i) / CGFloat(sampled.count - 1)
                            let y = h * (1 - CGFloat((alt - minAlt) / range))
                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                    }
                    .stroke(Color.stone.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                }
            }

            HStack {
                Text(formatElevation(minAlt))
                Spacer()
                Image(systemName: "mountain.2")
                    .font(Constants.Typography.caption)
                Spacer()
                Text(formatElevation(maxAlt))
            }
            .font(Constants.Typography.caption)
            .foregroundColor(.fog)
        }
    }

    private func formatElevation(_ meters: Double) -> String {
        let pref = UserPreferences.altitudeMeasurementType.safeValue
        if pref == .feet {
            return String(format: "%.0f ft", meters * 3.28084)
        }
        return String(format: "%.0f m", meters)
    }
}
