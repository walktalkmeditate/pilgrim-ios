import SwiftUI
import CoreStore

struct AboutView: View {

    @State private var breathing = false
    @State private var totalDistance: Double = 0
    @State private var walkCount: Int = 0
    @State private var firstWalkDate: Date?
    @State private var hasWalks = false
    @State private var statMode: StatMode = .distance
    @State private var safariURL: IdentifiableURL?
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                hero
                divider
                pillars
                divider
                if hasWalks {
                    statsWhisper
                    footprintTrail
                    divider
                }
                openSource
                divider
                motto
                seasonalVignette
                version
            }
            .padding(.horizontal, Constants.UI.Padding.big)
        }
        .scrollContentBackground(.hidden)
        .background(Color.parchment)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("About")
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
            }
        }
        .onAppear {
            if !reduceMotion {
                breathing = true
            }
        }
        .task {
            await loadWalkData()
        }
        .sheet(item: $safariURL) { item in
            SafariView(url: item.url)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            PilgrimLogoView(size: 80, animated: !reduceMotion, breathing: $breathing)
                .padding(.top, Constants.UI.Padding.big + Constants.UI.Padding.normal)

            Text("Every walk is a\nsmall pilgrimage.")
                .font(Constants.Typography.displayMedium.italic())
                .multilineTextAlignment(.center)
                .foregroundColor(.ink)

            Text("Walking is how we think, process, and return to ourselves. Pilgrim is a quiet companion for the path \u{2014} no leaderboards, no metrics, just you and the walk.")
                .font(Constants.Typography.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.fog)
                .padding(.horizontal, Constants.UI.Padding.normal)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Constants.UI.Padding.big)
        .sectionAppear(index: 0, appeared: appeared, reduceMotion: reduceMotion)
    }

    // MARK: - Pillars

    private var pillars: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.normal) {
            Text("walk \u{00B7} talk \u{00B7} meditate")
                .font(Constants.Typography.caption)
                .tracking(3)
                .foregroundColor(.stone)
                .frame(maxWidth: .infinity)
                .padding(.top, Constants.UI.Padding.small)

            pillarRow(
                icon: "figure.walk",
                tint: .moss,
                title: "walk",
                description: "Walking as practice, not transit. Side by side, step by step \u{2014} strengthening the physical body."
            )

            pillarRow(
                icon: "quote.bubble.fill",
                tint: .dawn,
                title: "talk",
                description: "Deep reflection and connection, not small talk. Ask and share your unique perspective of reality."
            )

            pillarRow(
                icon: "moon.stars.fill",
                tint: .stone,
                title: "meditate",
                description: "Seek the peace and calmness within. Harmonize your being with the group and the environment."
            )
        }
        .padding(.vertical, Constants.UI.Padding.normal)
        .sectionAppear(index: 1, appeared: appeared, reduceMotion: reduceMotion)
    }

    private func pillarRow(icon: String, tint: Color, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: Constants.UI.Padding.normal - Constants.UI.Padding.xs) {
            Circle()
                .fill(tint.opacity(Constants.UI.Opacity.light))
                .frame(width: 36, height: 36)
                .overlay {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(tint)
                }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Constants.Typography.heading)
                    .foregroundColor(.ink)
                Text(description)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
            .padding(.top, Constants.UI.Padding.small)
        }
    }

    // MARK: - Stats Whisper

    private var statsWhisper: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                statMode = statMode.next
            }
        } label: {
            VStack(spacing: Constants.UI.Padding.xs) {
                Group {
                    switch statMode {
                    case .distance:
                        Text(formatDistance(totalDistance))
                    case .count:
                        Text("\(walkCount)")
                    case .since:
                        Text(formatSinceDate(firstWalkDate))
                    }
                }
                .font(Constants.Typography.statValue)
                .foregroundColor(.stone)
                .contentTransition(.numericText())

                Group {
                    switch statMode {
                    case .distance:
                        Text("walked with Pilgrim")
                    case .count:
                        Text(walkCount == 1 ? "walk taken" : "walks taken")
                    case .since:
                        Text("walking since")
                    }
                }
                .font(Constants.Typography.caption.italic())
                .foregroundColor(.fog)
                .contentTransition(.numericText())
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, Constants.UI.Padding.big)
        .frame(maxWidth: .infinity)
        .sectionAppear(index: 2, appeared: appeared, reduceMotion: reduceMotion)
    }

    // MARK: - Footprint Trail

    private var footprintTrail: some View {
        HStack(spacing: Constants.UI.Padding.normal) {
            ForEach(0..<4, id: \.self) { index in
                FootprintShape()
                    .fill(Color.stone.opacity(0.08 + Double(index) * 0.04))
                    .frame(width: 12, height: 18)
                    .scaleEffect(x: index.isMultiple(of: 2) ? 1 : -1)
                    .rotationEffect(.degrees(index.isMultiple(of: 2) ? -10 : 10))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, Constants.UI.Padding.normal)
    }

    // MARK: - Open Source

    private var openSource: some View {
        VStack(alignment: .leading, spacing: Constants.UI.Padding.normal - Constants.UI.Padding.xs) {
            Text("OPEN SOURCE")
                .font(Constants.Typography.caption)
                .tracking(2)
                .foregroundColor(.stone.opacity(0.6))
                .padding(.top, Constants.UI.Padding.big)

            Text("Pilgrim is free and open source. No accounts, no tracking, no data leaves your device. Built as part of the walk \u{00B7} talk \u{00B7} meditate project.")
                .font(Constants.Typography.body)
                .foregroundColor(.ink)

            linkRow(
                icon: "globe",
                label: "walktalkmeditate.org",
                url: URL(string: "https://walktalkmeditate.org")!
            )

            linkRow(
                icon: "chevron.left.forwardslash.chevron.right",
                label: "Source code on GitHub",
                url: URL(string: "https://github.com/walktalkmeditate/pilgrim-ios")!
            )
        }
        .padding(.bottom, Constants.UI.Padding.big)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sectionAppear(index: 3, appeared: appeared, reduceMotion: reduceMotion)
    }

    private func linkRow(icon: String, label: String, url: URL) -> some View {
        Button {
            safariURL = IdentifiableURL(url: url)
        } label: {
            HStack(spacing: Constants.UI.Padding.small) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 24, alignment: .center)
                Text(label)
                    .font(Constants.Typography.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12))
                    .opacity(Constants.UI.Opacity.medium)
            }
            .foregroundColor(.stone)
            .padding(.vertical, Constants.UI.Padding.small + Constants.UI.Padding.xs)
        }
    }

    // MARK: - Motto

    private var motto: some View {
        VStack(spacing: 0) {
            Text("Slow and chill is the motto.\nRelax and release is the practice.\nPeace and harmony is the way.")
                .font(Constants.Typography.body.italic())
                .multilineTextAlignment(.center)
                .foregroundColor(.stone)
                .lineSpacing(8)
        }
        .padding(.vertical, Constants.UI.Padding.big + Constants.UI.Padding.normal)
        .frame(maxWidth: .infinity)
        .sectionAppear(index: 4, appeared: appeared, reduceMotion: reduceMotion)
    }

    // MARK: - Seasonal Vignette

    private var seasonalVignette: some View {
        SceneryItemView(type: .tree, tintColor: .stone, size: 40, walkDate: Date())
            .frame(width: 40, height: 40)
            .opacity(Constants.UI.Opacity.medium)
            .frame(maxWidth: .infinity)
            .padding(.bottom, Constants.UI.Padding.normal)
    }

    // MARK: - Version

    private var version: some View {
        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")
            .font(Constants.Typography.caption)
            .foregroundColor(.fog.opacity(0.3))
            .frame(maxWidth: .infinity)
            .padding(.bottom, Constants.UI.Padding.big)
    }

    // MARK: - Divider

    private var divider: some View {
        LinearGradient(
            colors: [.clear, Color.stone.opacity(0.2), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(maxWidth: .infinity)
        .frame(height: 1)
    }

    // MARK: - Data

    private func loadWalkData() async {
        do {
            let walks = try DataManager.dataStack.fetchAll(
                From<Walk>().orderBy(.ascending(\._startDate))
            )
            let total = walks.reduce(0.0) { $0 + $1.distance }
            await MainActor.run {
                totalDistance = total
                walkCount = walks.count
                firstWalkDate = walks.first?.startDate
                hasWalks = !walks.isEmpty
                withAnimation(reduceMotion ? nil : .easeInOut(duration: Constants.UI.Motion.appear)) {
                    appeared = true
                }
            }
        } catch {
            await MainActor.run {
                appeared = true
            }
        }
    }

    // MARK: - Formatting

    private func formatDistance(_ meters: Double) -> String {
        let isMiles = UserPreferences.distanceMeasurementType.safeValue == .miles
        if isMiles {
            let miles = meters / 1609.344
            if miles >= 1 {
                return String(format: "%.1f mi", miles)
            }
            return String(format: "%.0f ft", meters * 3.28084)
        }
        if meters >= 1000 {
            return String(format: "%.1f km", meters / 1000)
        }
        return String(format: "%.0f m", meters)
    }

    private func formatSinceDate(_ date: Date?) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM yyyy"
        return formatter.string(from: date)
    }
}

// MARK: - Helpers

private enum StatMode {
    case distance, count, since

    var next: StatMode {
        switch self {
        case .distance: return .count
        case .count: return .since
        case .since: return .distance
        }
    }
}

private struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

private struct SectionAppearModifier: ViewModifier {
    let index: Int
    let appeared: Bool
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || appeared ? 1 : 0)
            .offset(y: reduceMotion || appeared ? 0 : 8)
            .animation(
                reduceMotion ? nil : .easeInOut(duration: Constants.UI.Motion.appear).delay(Double(index) * 0.1),
                value: appeared
            )
    }
}

private extension View {
    func sectionAppear(index: Int, appeared: Bool, reduceMotion: Bool) -> some View {
        modifier(SectionAppearModifier(index: index, appeared: appeared, reduceMotion: reduceMotion))
    }
}
