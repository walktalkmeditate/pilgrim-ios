import SwiftUI

struct ActivityListView: View {

    let startDate: Date
    let endDate: Date
    let voiceRecordings: [VoiceRecordingInterface]
    let activityIntervals: [ActivityIntervalInterface]

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.small) {
            HStack {
                Image(systemName: "list.bullet")
                    .foregroundColor(.stone)
                Text("Activities")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
                Spacer()
            }

            ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                HStack(spacing: Constants.UI.Padding.small) {
                    Image(systemName: entry.icon)
                        .font(.caption)
                        .foregroundColor(.white)
                        .frame(width: 24, height: 24)
                        .background(entry.color)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name)
                            .font(Constants.Typography.heading)
                            .foregroundColor(.ink)
                        Text(entry.timeRange)
                            .font(Constants.Typography.caption)
                            .foregroundColor(.fog)
                    }

                    Spacer()

                    Text(entry.formattedDuration)
                        .font(Constants.Typography.statLabel)
                        .foregroundColor(.fog)
                        .monospacedDigit()
                }
                .padding(.vertical, Constants.UI.Padding.xs)
            }
        }
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    private struct ActivityEntry {
        let name: String
        let icon: String
        let color: Color
        let start: Date
        let duration: TimeInterval
        let timeRange: String
        let formattedDuration: String
    }

    private var entries: [ActivityEntry] {
        var result: [ActivityEntry] = []

        for recording in voiceRecordings {
            result.append(ActivityEntry(
                name: "Talk",
                icon: "waveform",
                color: .rust,
                start: recording.startDate,
                duration: recording.duration,
                timeRange: "\(Self.timeFormatter.string(from: recording.startDate)) – \(Self.timeFormatter.string(from: recording.endDate))",
                formattedDuration: formatDuration(recording.duration)
            ))
        }

        for interval in activityIntervals where interval.activityType == .meditation {
            result.append(ActivityEntry(
                name: "Meditate",
                icon: "brain.head.profile",
                color: .dawn,
                start: interval.startDate,
                duration: interval.duration,
                timeRange: "\(Self.timeFormatter.string(from: interval.startDate)) – \(Self.timeFormatter.string(from: interval.endDate))",
                formattedDuration: formatDuration(interval.duration)
            ))
        }

        return result.sorted { $0.start < $1.start }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}
