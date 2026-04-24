import SwiftUI

struct TimeMetricItem: View {
    let label: String
    let value: String
    let icon: String
    var isActive: Bool = false

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(isActive ? .rust : .stone)
            Text(value)
                .font(Constants.Typography.statValue)
                .foregroundColor(.ink)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text(label)
                .font(Constants.Typography.statLabel)
                .foregroundColor(.fog)
                .minimumScaleFactor(0.7)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

struct LivePaceSparklineView: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let filtered = values.filter { $0 > 0 }
            if filtered.count > 1 {
                let maxVal = filtered.max() ?? 1
                let minVal = filtered.min() ?? 0
                let range = max(maxVal - minVal, 0.5)

                Path { path in
                    for (i, val) in filtered.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(filtered.count - 1)
                        let normalized = (val - minVal) / range
                        let y = geo.size.height * (1 - CGFloat(normalized))
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.stone.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct AudioWaveformView: View {

    let level: Float

    private let barCount = 5
    private let barWeights: [Float] = [0.6, 0.8, 1.0, 0.8, 0.6]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.rust)
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let weight = CGFloat(barWeights[index])
        let amplitude = CGFloat(level) * weight
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 24
        return minHeight + amplitude * (maxHeight - minHeight)
    }
}
