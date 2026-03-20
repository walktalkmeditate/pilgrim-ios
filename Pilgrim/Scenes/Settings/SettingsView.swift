import SwiftUI
import CoreStore

struct SettingsView: View {

    @StateObject private var permissionVM = PermissionStatusViewModel()
    @State private var walkCount = 0
    @State private var totalDistance: Double = 0
    @State private var totalMeditationSeconds: TimeInterval = 0
    @State private var firstWalkDate: Date?
    @State private var hasAppeared = false
    @State private var aboutBreathing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Constants.UI.Padding.big) {
                    pullToRevealTagline
                    PracticeSummaryHeader(
                        walkCount: walkCount,
                        totalDistanceMeters: totalDistance,
                        totalMeditationSeconds: totalMeditationSeconds,
                        firstWalkDate: firstWalkDate
                    )
                    .cardEntrance(hasAppeared: hasAppeared, delay: 0.0, reduceMotion: reduceMotion)
                    PracticeCard()
                        .cardEntrance(hasAppeared: hasAppeared, delay: 0.1, reduceMotion: reduceMotion)
                    AtmosphereCard()
                        .cardEntrance(hasAppeared: hasAppeared, delay: 0.2, reduceMotion: reduceMotion)
                    VoiceCard()
                        .cardEntrance(hasAppeared: hasAppeared, delay: 0.3, reduceMotion: reduceMotion)
                    PermissionsCard(permissionVM: permissionVM)
                        .cardEntrance(hasAppeared: hasAppeared, delay: 0.4, reduceMotion: reduceMotion)
                    DataCard()
                        .cardEntrance(hasAppeared: hasAppeared, delay: 0.5, reduceMotion: reduceMotion)
                    aboutLink
                        .cardEntrance(hasAppeared: hasAppeared, delay: 0.6, reduceMotion: reduceMotion)
                }
                .padding(.horizontal, Constants.UI.Padding.normal)
                .padding(.bottom, Constants.UI.Padding.breathingRoom)
            }
            .coordinateSpace(name: "scroll")
            .background(Color.parchment)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Settings")
                        .font(Constants.Typography.heading)
                        .foregroundColor(.ink)
                }
            }
            .onAppear {
                permissionVM.refresh()
                loadStats()
                if !hasAppeared {
                    if reduceMotion {
                        hasAppeared = true
                    } else {
                        withAnimation(.easeOut(duration: Constants.UI.Motion.appear)) {
                            hasAppeared = true
                        }
                    }
                }
                if !reduceMotion {
                    aboutBreathing = true
                }
            }
        }
    }

    // MARK: - Pull-to-Reveal Tagline

    private var pullToRevealTagline: some View {
        GeometryReader { geo in
            let offset = geo.frame(in: .named("scroll")).minY
            if offset > 40 {
                Text("Every walk is a small pilgrimage.")
                    .font(Constants.Typography.caption)
                    .italic()
                    .foregroundColor(.fog)
                    .opacity(min(Double(offset - 40) / 60, 1.0))
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 0)
    }

    // MARK: - About

    private var aboutLink: some View {
        NavigationLink {
            AboutView()
        } label: {
            HStack {
                PilgrimLogoView(size: 24, animated: !reduceMotion, breathing: $aboutBreathing)
                Text("About Pilgrim")
                    .font(Constants.Typography.body)
                    .foregroundColor(.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(Constants.Typography.caption)
                    .foregroundColor(.fog)
            }
        }
        .settingsCard()
    }

    // MARK: - Stats

    private func loadStats() {
        do {
            let walks = try DataManager.dataStack.fetchAll(
                From<Walk>().orderBy(.ascending(\._startDate))
            )
            walkCount = walks.count
            totalDistance = walks.reduce(0.0) { $0 + $1.distance }
            totalMeditationSeconds = walks.reduce(0.0) { $0 + $1.meditateDuration }
            firstWalkDate = walks.first?.startDate
        } catch {
            walkCount = 0
            totalDistance = 0
            totalMeditationSeconds = 0
            firstWalkDate = nil
        }
    }
}

// MARK: - Card Entrance Animation

private struct CardEntranceModifier: ViewModifier {
    let hasAppeared: Bool
    let delay: Double
    let reduceMotion: Bool

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || hasAppeared ? 1 : 0)
            .offset(y: reduceMotion || hasAppeared ? 0 : 20)
            .animation(
                reduceMotion ? nil : .easeOut(duration: Constants.UI.Motion.appear).delay(delay),
                value: hasAppeared
            )
    }
}

private extension View {
    func cardEntrance(hasAppeared: Bool, delay: Double, reduceMotion: Bool) -> some View {
        modifier(CardEntranceModifier(hasAppeared: hasAppeared, delay: delay, reduceMotion: reduceMotion))
    }
}
