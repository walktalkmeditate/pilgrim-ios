import SwiftUI

extension InkScrollView {

    func lunarMarkers(positions: [CalligraphyPathRenderer.DotPosition], viewportWidth: CGFloat) -> some View {
        let markers = computeLunarMarkers(positions: positions, viewportWidth: viewportWidth)
        return ForEach(markers, id: \.id) { marker in
            LunarMarkerDot(isFullMoon: marker.illumination > 0.5)
                .frame(width: 10, height: 10)
                .position(x: marker.x, y: marker.y)
                .accessibilityHidden(true)
        }
    }

    struct LunarMarkerDot: View {
        let isFullMoon: Bool
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            let moonColor = colorScheme == .dark
                ? Color(red: 0.85, green: 0.82, blue: 0.72)
                : Color(red: 0.55, green: 0.58, blue: 0.65)
            Circle()
                .fill(isFullMoon ? moonColor.opacity(colorScheme == .dark ? 0.6 : 0.4) : Color.clear)
                .overlay(
                    Circle()
                        .stroke(moonColor.opacity(colorScheme == .dark ? 0.7 : 0.5), lineWidth: isFullMoon ? 0 : 1)
                )
        }
    }

    struct LunarMarker: Identifiable {
        let id: String
        let x: CGFloat
        let y: CGFloat
        let illumination: Double
        let isWaxing: Bool
    }

    func computeLunarMarkers(positions: [CalligraphyPathRenderer.DotPosition], viewportWidth: CGFloat) -> [LunarMarker] {
        guard snapshots.count >= 2 else { return [] }

        let earliestDate = snapshots.map(\.startDate).min()!
        let latestDate = snapshots.map(\.startDate).max()!
        let lunarEvents = findLunarEvents(from: earliestDate, to: latestDate)

        var markers: [LunarMarker] = []

        for event in lunarEvents {
            guard let (posA, posB, fraction) = interpolatePosition(for: event.date, positions: positions) else { continue }
            let y = posA.yOffset + CGFloat(fraction) * (posB.yOffset - posA.yOffset)
            let midX = posA.center.x + CGFloat(fraction) * (posB.center.x - posA.center.x)
            let markerX: CGFloat = midX > viewportWidth / 2 ? midX - 20 : midX + 20

            markers.append(LunarMarker(
                id: "lunar-\(markers.count)",
                x: markerX,
                y: y,
                illumination: event.illumination,
                isWaxing: event.isWaxing
            ))
        }

        return markers
    }

    private struct LunarEvent {
        let date: Date
        let illumination: Double
        let isWaxing: Bool
    }

    private func findLunarEvents(from start: Date, to end: Date) -> [LunarEvent] {
        let calendar = Calendar.current
        let halfCycle = 14.76
        var events: [LunarEvent] = []
        var checkDate = start

        while checkDate <= end {
            let phase = LunarPhase.current(date: checkDate)
            let isNearNew = phase.age < 1.5 || phase.age > 28.0
            let isNearFull = abs(phase.age - 14.76) < 1.5

            if isNearNew || isNearFull {
                let peakDate = refinePeak(near: checkDate, isFullMoon: isNearFull)
                let peakPhase = LunarPhase.current(date: peakDate)
                events.append(LunarEvent(date: peakDate, illumination: peakPhase.illumination, isWaxing: peakPhase.isWaxing))
                checkDate = calendar.date(byAdding: .day, value: Int(halfCycle) - 1, to: checkDate)!
            } else {
                checkDate = calendar.date(byAdding: .day, value: 1, to: checkDate)!
            }
        }

        return events
    }

    private func refinePeak(near date: Date, isFullMoon: Bool) -> Date {
        var bestDate = date
        var bestScore = isFullMoon
            ? LunarPhase.current(date: date).illumination
            : 1.0 - LunarPhase.current(date: date).illumination

        for hourOffset in stride(from: -36.0, through: 36.0, by: 6.0) {
            let candidate = date.addingTimeInterval(hourOffset * 3600)
            let phase = LunarPhase.current(date: candidate)
            let score = isFullMoon ? phase.illumination : 1.0 - phase.illumination
            if score > bestScore {
                bestScore = score
                bestDate = candidate
            }
        }

        return bestDate
    }

    func interpolatePosition(for date: Date, positions: [CalligraphyPathRenderer.DotPosition]) -> (CalligraphyPathRenderer.DotPosition, CalligraphyPathRenderer.DotPosition, Double)? {
        for i in 0..<(snapshots.count - 1) {
            guard i + 1 < positions.count else { continue }
            let dateA = snapshots[i].startDate
            let dateB = snapshots[i + 1].startDate
            let earlier = min(dateA, dateB)
            let later = max(dateA, dateB)

            if date >= earlier && date <= later {
                let totalInterval = later.timeIntervalSince(earlier)
                let fraction = totalInterval > 0
                    ? date.timeIntervalSince(earlier) / totalInterval
                    : 0.5
                let adjustedFraction = dateA < dateB ? fraction : 1.0 - fraction
                return (positions[i], positions[i + 1], adjustedFraction)
            }
        }
        return nil
    }
}
