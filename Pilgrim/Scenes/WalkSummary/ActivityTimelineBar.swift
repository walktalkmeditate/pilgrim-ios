import SwiftUI

struct ActivityTimelineBar: View {

    let startDate: Date
    let endDate: Date
    let activeDuration: Double
    let voiceRecordings: [VoiceRecordingInterface]
    let activityIntervals: [ActivityIntervalInterface]
    let routeData: [RouteDataSampleInterface]
    var onSegmentTapped: ((_ start: Date, _ end: Date) -> Void)?
    var onSegmentDeselected: (() -> Void)?

    @State private var showRelativeTime = true
    @State private var selectedSegmentId: Int?

    var body: some View {
        VStack(spacing: Constants.UI.Padding.xs) {
            GeometryReader { geo in
                let totalWidth = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.moss.opacity(0.4))
                        .frame(height: 16)

                    ForEach(segments.filter { $0.type == .meditating }) { segment in
                        segmentRect(segment, totalWidth: totalWidth, height: 16)
                    }

                    ForEach(segments.filter { $0.type == .talking }) { segment in
                        segmentRect(segment, totalWidth: totalWidth, height: 10)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onEnded { value in
                            handleTap(at: value.location.x, totalWidth: totalWidth)
                        }
                )
            }
            .frame(height: 16)

            if let selected = selectedSegment {
                selectedTooltip(selected)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack {
                Text(formattedStartTime)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .contentTransition(.numericText())
                Spacer()
                Text(formattedEndTime)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .contentTransition(.numericText())
            }
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showRelativeTime.toggle()
                }
            }

            if routeData.count >= 3 {
                PaceSparklineView(routeData: routeData, startDate: startDate, endDate: endDate)
                    .frame(height: 40)
            }

            HStack(spacing: Constants.UI.Padding.normal) {
                legendDot(color: .moss, label: "Walk")
                legendDot(color: .rust, label: "Talk")
                legendDot(color: .dawn, label: "Meditate")
                Spacer()
            }
        }
        .padding(Constants.UI.Padding.normal)
        .background(Color.parchmentSecondary)
        .cornerRadius(Constants.UI.CornerRadius.normal)
    }

    // MARK: - Segment Rendering

    private func segmentRect(_ segment: Segment, totalWidth: CGFloat, height: CGFloat) -> some View {
        let width = max(2, segment.widthFraction * totalWidth)
        let isSelected = selectedSegmentId == segment.id

        return ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(segment.type.color.opacity(isSelected ? 0.95 : 0.7))

            if isSelected {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(segment.type.color, lineWidth: 1.5)
            }

        }
        .frame(width: width, height: height)
        .clipped()
        .offset(x: segment.startFraction * totalWidth)
    }

    private func selectedTooltip(_ segment: Segment) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(segment.type.color)
                .frame(width: 8, height: 8)
            Text(segment.type.label)
                .font(Constants.Typography.caption)
                .foregroundColor(.ink)
            Text(formatCompactDuration(segment.duration))
                .font(Constants.Typography.caption)
                .fontWeight(.medium)
                .foregroundColor(.fog)

            if !showRelativeTime {
                Text(Self.timeFormatter.string(from: segment.startDate))
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
    }

    // MARK: - Tap Handling

    private func handleTap(at x: CGFloat, totalWidth: CGFloat) {
        let fraction = x / totalWidth

        if let tapped = segments.first(where: { seg in
            fraction >= seg.startFraction && fraction <= seg.startFraction + seg.widthFraction
        }) {
            if selectedSegmentId == tapped.id {
                withAnimation(.easeInOut(duration: 0.2)) { selectedSegmentId = nil }
                onSegmentDeselected?()
            } else {
                withAnimation(.easeInOut(duration: 0.2)) { selectedSegmentId = tapped.id }
                onSegmentTapped?(tapped.startDate, tapped.endDate)
            }
        } else if selectedSegmentId != nil {
            withAnimation(.easeInOut(duration: 0.2)) { selectedSegmentId = nil }
            onSegmentDeselected?()
        }
    }

    // MARK: - Time Labels

    private var formattedStartTime: String {
        showRelativeTime ? "0:00" : Self.timeFormatter.string(from: startDate)
    }

    private var formattedEndTime: String {
        if showRelativeTime {
            return formatRelativeDuration(endDate.timeIntervalSince(startDate))
        }
        return Self.timeFormatter.string(from: endDate)
    }

    // MARK: - Helpers

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(Constants.Typography.caption)
                .foregroundColor(.fog)
        }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()

    private func formatCompactDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total < 60 { return "\(total)s" }
        return "\(total / 60)m"
    }

    private func formatRelativeDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Segment Model

    private struct Segment: Identifiable {
        let id: Int
        let type: SegmentType
        let startFraction: CGFloat
        let widthFraction: CGFloat
        let startDate: Date
        let endDate: Date

        var duration: TimeInterval { endDate.timeIntervalSince(startDate) }

        enum SegmentType {
            case walking, talking, meditating

            var color: Color {
                switch self {
                case .walking: return .moss
                case .talking: return .rust
                case .meditating: return .dawn
                }
            }

            var label: String {
                switch self {
                case .walking: return "Walk"
                case .talking: return "Talk"
                case .meditating: return "Meditate"
                }
            }
        }
    }

    private var totalDuration: TimeInterval {
        max(1, startDate.distance(to: endDate))
    }

    private var selectedSegment: Segment? {
        guard let id = selectedSegmentId else { return nil }
        return segments.first { $0.id == id }
    }

    private var segments: [Segment] {
        var result: [Segment] = []
        var nextId = 0

        for interval in activityIntervals where interval.activityType == .meditation {
            let start = max(0, startDate.distance(to: interval.startDate)) / totalDuration
            let width = interval.duration / totalDuration
            result.append(Segment(
                id: nextId, type: .meditating,
                startFraction: start, widthFraction: width,
                startDate: interval.startDate, endDate: interval.endDate
            ))
            nextId += 1
        }

        for recording in voiceRecordings {
            let start = max(0, startDate.distance(to: recording.startDate)) / totalDuration
            let width = recording.duration / totalDuration
            result.append(Segment(
                id: nextId, type: .talking,
                startFraction: start, widthFraction: width,
                startDate: recording.startDate, endDate: recording.endDate
            ))
            nextId += 1
        }

        return result.sorted { $0.startFraction < $1.startFraction }
    }
}
