import SwiftUI

struct PracticeSummaryHeader: View {
    let walkCount: Int
    let totalDistanceMeters: Double
    let totalMeditationSeconds: TimeInterval
    var firstWalkDate: Date?

    @State private var statPhase = 0
    @State private var isImperial = UserPreferences.distanceMeasurementType.safeValue == .miles
    @ObservedObject private var counterService = CollectiveCounterService.shared

    var body: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            HStack(spacing: Constants.UI.Padding.xs) {
                Text(seasonLabel)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                Image(systemName: seasonSymbol)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
                    .opacity(0.3)
            }

            if walkCount > 0 {
                Text(currentStatLine)
                    .font(Constants.Typography.body)
                    .foregroundColor(.stone)
                    .contentTransition(.numericText())
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            statPhase = (statPhase + 1) % 3
                        }
                    }
            }

            if let stats = counterService.stats, stats.totalWalks > 0 {
                VStack(spacing: 4) {
                    Text(stats.pilgrimageProgress.message)
                        .font(Constants.Typography.caption.italic())
                        .foregroundColor(.stone)
                    Text(collectiveStatsLine(stats))
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                }
                .padding(.top, 4)
                .transition(.opacity)
            }

            if let milestone = counterService.milestone {
                Text(milestone.message)
                    .font(Constants.Typography.body.italic())
                    .foregroundColor(.stone)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Constants.UI.Padding.big)
                    .padding(.vertical, Constants.UI.Padding.small)
                    .background(Color.moss.opacity(0.08))
                    .cornerRadius(Constants.UI.Padding.small)
                    .padding(.top, Constants.UI.Padding.small)
                    .transition(.opacity)
                    .onAppear {
                        playMilestoneBell()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                            withAnimation { counterService.milestone = nil }
                        }
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Constants.UI.Padding.big)
        .task { await counterService.fetch() }
        .animation(.easeInOut(duration: 0.5), value: counterService.milestone?.number)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            isImperial = UserPreferences.distanceMeasurementType.safeValue == .miles
        }
    }

    private func playMilestoneBell() {
        guard UserPreferences.soundsEnabled.value else { return }
        guard let bellId = UserPreferences.walkStartBellId.value,
              let asset = AudioManifestService.shared.asset(byId: bellId) else { return }
        BellPlayer.shared.play(asset, volume: 0.4)
    }

    private func collectiveStatsLine(_ stats: CollectiveCounterService.CollectiveStats) -> String {
        let dist = isImperial ? stats.totalDistanceKm * 0.621371 : stats.totalDistanceKm
        let unit = isImperial ? "mi" : "km"
        let walks = stats.totalWalks.formatted()
        let distStr = String(format: "%.0f", dist)
        return "\(walks) walks \u{00B7} \(distStr) \(unit)"
    }

    // MARK: - Cycling Stats

    private var currentStatLine: String {
        switch statPhase {
        case 1:
            return meditationStatLine
        case 2:
            return walkingSinceLine
        default:
            return statsLine
        }
    }

    private var statsLine: String {
        let distKm = totalDistanceMeters / 1000
        let dist = isImperial ? distKm * 0.621371 : distKm
        let unit = isImperial ? "mi" : "km"
        return "\(walkCount) walks \u{00B7} \(String(format: "%.0f", dist)) \(unit)"
    }

    private var meditationStatLine: String {
        guard totalMeditationSeconds > 0 else { return "No meditation yet" }
        let hours = Int(totalMeditationSeconds) / 3600
        let minutes = (Int(totalMeditationSeconds) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m in stillness"
        }
        return "\(minutes)m in stillness"
    }

    private var walkingSinceLine: String {
        guard let date = firstWalkDate else { return statsLine }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return "Walking since \(formatter.string(from: date))"
    }

    // MARK: - Season

    private var seasonLabel: String {
        let hemisphereHint: Double = (UserPreferences.hemisphereOverride.value ?? 1) >= 0 ? 1 : -1
        let season = SealTimeHelpers.season(for: Date(), latitude: hemisphereHint)
        let year = Calendar.current.component(.year, from: Date())
        return "\(season) \(year)"
    }

    private var seasonSymbol: String {
        let hemisphereHint: Double = (UserPreferences.hemisphereOverride.value ?? 1) >= 0 ? 1 : -1
        let season = SealTimeHelpers.season(for: Date(), latitude: hemisphereHint)
        switch season {
        case "Spring": return "leaf.fill"
        case "Summer": return "sun.max.fill"
        case "Autumn": return "wind"
        default:       return "snowflake"
        }
    }
}
