import SwiftUI

struct MeditationView: View {

    let soundManagement: SoundManagement
    let onDismiss: () -> Void

    @State private var phase: BreathPhase = .inhale
    @State private var circleScale: CGFloat = 0.45
    @State private var isActive = true
    @State private var isClosing = false
    @State private var closingPhase: ClosingPhase = .none
    @State private var contentOpacity: Double = 1
    @State private var screenOpacity: Double = 1
    @State private var warmthAmount: Double = 0
    @State private var holdGlow: Double = 0
    @State private var particles: [MeditationParticle] = []
    @State private var rippleRings: [RippleRing] = []
    @StateObject private var clock = SessionClock()
    @StateObject private var soundscapePlayer = SoundscapePlayer.shared

    private var rhythm: BreathRhythm { BreathRhythm.all[UserPreferences.breathRhythm.value] }

    var body: some View {
        ZStack {
            background
            particleLayer
            rippleLayer

            VStack(spacing: 0) {
                Spacer()

                breathingCircle
                    .opacity(closingPhase == .dissolving || closingPhase == .summary || closingPhase == .fadeOut ? 0 : 1)
                    .scaleEffect(closingPhase == .dissolving ? 0.1 : 1)

                if closingPhase == .summary {
                    closingSummary
                        .padding(.top, 32)
                        .transition(.opacity)
                } else {
                    sessionTimer
                        .padding(.top, 24)

                    soundscapeLabel
                        .padding(.top, 8)
                }

                Spacer()

                if !isClosing {
                    doneButton
                        .padding(.bottom, 40)
                        .transition(.opacity)
                }
            }
            .opacity(contentOpacity)
        }
        .opacity(screenOpacity)
        .onAppear {
            startBreathCycle()
            spawnParticles()
        }
        .onDisappear {
            isActive = false
            clock.stop()
        }
        .statusBarHidden()
        .animation(.easeInOut(duration: 1.5), value: closingPhase)
        .animation(.easeInOut(duration: 0.5), value: isClosing)
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color.ink
            Color.orange.opacity(warmthAmount * 0.06)
        }
        .ignoresSafeArea()
        .animation(.linear(duration: 30), value: warmthAmount)
    }

    // MARK: - Particles

    private var particleLayer: some View {
        GeometryReader { geo in
            ForEach(particles) { particle in
                Circle()
                    .fill(Color.parchment.opacity(particle.opacity))
                    .frame(width: particle.size, height: particle.size)
                    .position(
                        x: geo.size.width * particle.x,
                        y: geo.size.height * particle.y
                    )
                    .blur(radius: 1)
            }
        }
        .allowsHitTesting(false)
    }

    private func spawnParticles() {
        for i in 0..<12 {
            let p = MeditationParticle(
                id: i,
                x: CGFloat.random(in: 0.2...0.8),
                y: CGFloat.random(in: 0.2...0.7),
                size: CGFloat.random(in: 2...5),
                opacity: Double.random(in: 0.05...0.2),
                speed: Double.random(in: 0.3...0.8)
            )
            particles.append(p)
        }
        animateParticles()
        startWarmthProgression()
    }

    private func animateParticles() {
        guard isActive else { return }
        withAnimation(.easeInOut(duration: 6).repeatForever(autoreverses: true)) {
            for i in particles.indices {
                particles[i].y -= CGFloat(particles[i].speed) * 0.05
                particles[i].x += CGFloat.random(in: -0.02...0.02)
                particles[i].opacity = Double.random(in: 0.05...0.25)
            }
        }
    }

    private func startWarmthProgression() {
        withAnimation(.linear(duration: 300)) {
            warmthAmount = 1.0
        }
    }

    // MARK: - Ripple Rings

    private var rippleLayer: some View {
        GeometryReader { geo in
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height * 0.35)
            ForEach(rippleRings) { ring in
                Circle()
                    .stroke(Color.moss.opacity(ring.opacity), lineWidth: 0.5)
                    .frame(width: ring.size, height: ring.size)
                    .position(center)
            }
        }
        .allowsHitTesting(false)
    }

    private func emitRipple() {
        let ring = RippleRing(id: UUID(), size: 160 * circleScale, opacity: 0.3)
        rippleRings.append(ring)
        let ringId = ring.id

        withAnimation(.easeOut(duration: 3.0)) {
            if let idx = rippleRings.firstIndex(where: { $0.id == ringId }) {
                rippleRings[idx].size = 400
                rippleRings[idx].opacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            rippleRings.removeAll { $0.id == ringId }
        }
    }

    // MARK: - Breathing Circle

    private var breathingCircle: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.moss.opacity(0.5),
                            Color.moss.opacity(0.15),
                            Color.moss.opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 20,
                        endRadius: 160
                    )
                )
                .frame(width: 320, height: 320)
                .scaleEffect(circleScale)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.moss.opacity(0.7 + holdGlow * 0.2),
                            Color.moss.opacity(0.3 + holdGlow * 0.1)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(circleScale)

            Circle()
                .stroke(Color.moss.opacity(0.25 + holdGlow * 0.15), lineWidth: 1 + holdGlow * 0.5)
                .frame(width: 200, height: 200)
                .scaleEffect(circleScale * 1.3)
                .opacity(Double(circleScale))
        }
    }

    // MARK: - Labels

    @ViewBuilder
    private var soundscapeLabel: some View {
        if let name = selectedSoundscapeName {
            Button {
                soundscapePlayer.toggleMute()
            } label: {
                if soundscapePlayer.isMuted {
                    Text("♪ Paused")
                        .font(.system(.caption, design: .serif))
                        .foregroundColor(Color.fog.opacity(0.2))
                        .strikethrough(color: Color.fog.opacity(0.2))
                } else {
                    Text("♪ \(name)")
                        .font(.system(.caption, design: .serif))
                        .foregroundColor(Color.fog.opacity(0.35))
                }
            }
            .animation(.easeInOut(duration: 0.3), value: soundscapePlayer.isMuted)
        }
    }

    private var selectedSoundscapeName: String? {
        if let playing = soundscapePlayer.currentAsset?.displayName {
            return playing
        }
        if let id = UserPreferences.selectedSoundscapeId.value {
            return AudioManifestService.shared.asset(byId: id)?.displayName
        }
        return nil
    }

    private var sessionTimer: some View {
        Text(formatTime(clock.elapsed))
            .font(.system(.title3, design: .serif).weight(.light))
            .foregroundColor(Color.parchment.opacity(0.4))
            .monospacedDigit()
    }

    // MARK: - Closing Summary

    private static let closingPhrases = [
        "Be at peace",
        "Stillness carries forward",
        "The path continues",
        "Return gently",
        "Carry this calm with you",
    ]

    private var closingSummary: some View {
        VStack(spacing: 16) {
            Text(formatTime(clock.elapsed))
                .font(.system(.largeTitle, design: .serif).weight(.light))
                .foregroundColor(Color.parchment.opacity(0.9))

            Text(Self.closingPhrases.randomElement() ?? "Be at peace")
                .font(.system(.subheadline, design: .serif).italic())
                .foregroundColor(Color.fog.opacity(0.5))
        }
        .padding(.bottom, 48)
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button(action: beginClosingCeremony) {
            Text("Done")
                .font(.system(.subheadline, design: .serif).weight(.light))
                .foregroundColor(Color.parchment.opacity(0.4))
                .padding(.horizontal, 48)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .stroke(Color.parchment.opacity(0.15), lineWidth: 1)
                )
        }
        .disabled(isClosing)
    }

    // MARK: - Closing Ceremony

    private func beginClosingCeremony() {
        guard !isClosing else { return }
        isClosing = true
        isActive = false
        clock.stop()

        soundManagement.onMeditationEnd()

        closingPhase = .dissolving

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            closingPhase = .summary
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            closingPhase = .fadeOut
            withAnimation(.easeInOut(duration: 1.5)) {
                screenOpacity = 0
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
            onDismiss()
        }
    }

    // MARK: - Breath Cycle

    private func startBreathCycle() {
        breathIn()
    }

    private func breathIn() {
        guard isActive else { return }
        phase = .inhale
        withAnimation(.easeInOut(duration: rhythm.inhale)) {
            circleScale = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + rhythm.inhale) {
            self.emitRipple()
            if self.rhythm.holdIn > 0 {
                self.holdAfterInhale()
            } else {
                self.breathOut()
            }
        }
    }

    private func holdAfterInhale() {
        guard isActive else { return }
        phase = .holdIn
        withAnimation(.easeInOut(duration: rhythm.holdIn / 2).repeatForever(autoreverses: true)) {
            holdGlow = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + rhythm.holdIn) {
            withAnimation(.easeInOut(duration: 0.3)) { self.holdGlow = 0 }
            self.breathOut()
        }
    }

    private func breathOut() {
        guard isActive else { return }
        phase = .exhale
        withAnimation(.easeInOut(duration: rhythm.exhale)) {
            circleScale = 0.45
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + rhythm.exhale) {
            if self.rhythm.holdOut > 0 {
                self.holdAfterExhale()
            } else {
                self.breathIn()
            }
        }
    }

    private func holdAfterExhale() {
        guard isActive else { return }
        phase = .holdOut
        withAnimation(.easeInOut(duration: rhythm.holdOut / 2).repeatForever(autoreverses: true)) {
            holdGlow = 0.6
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + rhythm.holdOut) {
            withAnimation(.easeInOut(duration: 0.3)) { self.holdGlow = 0 }
            self.breathIn()
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

// MARK: - Supporting Types

private class SessionClock: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    private let startDate = Date()
    private var timer: Timer?

    init() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.elapsed = Date().timeIntervalSince(self.startDate)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    deinit { stop() }
}

private enum BreathPhase {
    case inhale, holdIn, exhale, holdOut
}

struct BreathRhythm: Identifiable {
    let id: Int
    let name: String
    let label: String
    let inhale: Double
    let holdIn: Double
    let exhale: Double
    let holdOut: Double

    static let all: [BreathRhythm] = [
        BreathRhythm(id: 0, name: "Calm", label: "5 / 7", inhale: 5, holdIn: 0, exhale: 7, holdOut: 0),
        BreathRhythm(id: 1, name: "Equal", label: "4 / 4", inhale: 4, holdIn: 0, exhale: 4, holdOut: 0),
        BreathRhythm(id: 2, name: "Relaxing", label: "4-7-8", inhale: 4, holdIn: 7, exhale: 8, holdOut: 0),
        BreathRhythm(id: 3, name: "Box", label: "4-4-4-4", inhale: 4, holdIn: 4, exhale: 4, holdOut: 4),
        BreathRhythm(id: 4, name: "Coherent", label: "5 / 5", inhale: 5, holdIn: 0, exhale: 5, holdOut: 0),
        BreathRhythm(id: 5, name: "Deep calm", label: "3 / 6", inhale: 3, holdIn: 0, exhale: 6, holdOut: 0),
    ]
}

private enum ClosingPhase {
    case none, dissolving, summary, fadeOut
}

struct MeditationParticle: Identifiable {
    let id: Int
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
    var speed: Double
}

struct RippleRing: Identifiable {
    let id: UUID
    var size: CGFloat
    var opacity: Double
}
