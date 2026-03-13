import SwiftUI

struct ActivityInsightsView: View {

    let talkDuration: Double
    let activeDuration: Double
    let activityIntervals: [ActivityIntervalInterface]

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundColor(.stone)
                Text("Insights")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
                Spacer()
            }

            if let meditationInsight = meditationInsight {
                insightRow(text: meditationInsight)
            }
            if let talkInsight = talkInsight {
                insightRow(text: talkInsight)
            }
        }
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    private func insightRow(text: String) -> some View {
        Text(text)
            .font(Constants.Typography.body)
            .foregroundColor(.fog)
    }

    private var meditationIntervals: [ActivityIntervalInterface] {
        activityIntervals.filter { $0.activityType == .meditation }
    }

    private var meditationInsight: String? {
        let intervals = meditationIntervals
        guard !intervals.isEmpty else { return nil }
        let longest = intervals.map { $0.duration }.max() ?? 0
        let longestFormatted = formatCompactDuration(longest)
        if intervals.count == 1 {
            return "Meditated once for \(longestFormatted)"
        }
        return "Meditated \(intervals.count) times (longest: \(longestFormatted))"
    }

    private func formatCompactDuration(_ seconds: Double) -> String {
        let total = Int(seconds)
        if total < 60 { return "\(total) sec" }
        let m = total / 60
        let s = total % 60
        if s == 0 { return "\(m) min" }
        return "\(m) min \(s) sec"
    }

    private var talkInsight: String? {
        guard talkDuration > 0, activeDuration > 0 else { return nil }
        let pct = Int((talkDuration / activeDuration) * 100)
        return "Talked for \(pct)% of the walk"
    }
}
