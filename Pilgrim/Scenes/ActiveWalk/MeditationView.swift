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
    @State private var fadeOverlay: Double = 0
    @State private var warmthAmount: Double = 0
    @State private var isHolding = false
    @State private var holdIntensity: Double = 0
    @State private var closingPhrase = ""
    @State private var showBreathPicker = false
    @State private var showSoundscapePicker = false
    @State private var selectedRhythmId: Int = UserPreferences.breathRhythm.value
    @State private var breathCount: Int = 0
    @State private var milestoneFlash: Double = 0
    @State private var breathGeneration: Int = 0
    @State private var hasDismissed = false
    @State private var particles: [MeditationParticle] = []
    @State private var rippleRings: [RippleRing] = []
    @StateObject private var clock = SessionClock()
    @ObservedObject private var soundscapePlayer = SoundscapePlayer.shared

    private var rhythm: BreathRhythm {
        guard selectedRhythmId >= 0 && selectedRhythmId < BreathRhythm.all.count else { return BreathRhythm.all[0] }
        return BreathRhythm.all[selectedRhythmId]
    }

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
                    .onLongPressGesture(minimumDuration: 1.0) {
                        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                        showBreathPicker = true
                    }

                if closingPhase == .summary {
                    closingSummary
                        .padding(.top, 32)
                        .transition(.opacity)
                } else {
                    if !rhythm.isNone {
                        breathCountLabel
                            .padding(.top, 16)
                    }

                    sessionTimer
                        .padding(.top, 8)

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
        .overlay(Color.parchment.opacity(fadeOverlay))
        .onAppear {
            startBreathCycle()
            spawnParticles()
        }
        .onDisappear {
            isActive = false
            clock.stop()
        }
        .sheet(isPresented: $showBreathPicker) {
            breathPickerSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.ink.opacity(0.95))
        }
        .sheet(isPresented: $showSoundscapePicker) {
            soundscapePickerSheet
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(Color.ink.opacity(0.95))
        }
        .statusBarHidden()
        .animation(.easeInOut(duration: 1.5), value: closingPhase)
        .animation(.easeInOut(duration: 0.5), value: isClosing)
    }

    // MARK: - Background

    private var background: some View {
        ZStack {
            Color.parchment
            Color.orange.opacity(warmthAmount * 0.06)
        }
        .ignoresSafeArea()
        .animation(.linear(duration: 30), value: warmthAmount)
    }

    // MARK: - Particles

    @State private var particleGlow = false

    private var particleLayer: some View {
        GeometryReader { geo in
            ForEach(particles) { particle in
                Circle()
                    .fill(Color.fog.opacity(particleGlow ? particle.opacity * 1.5 : particle.opacity * 0.5))
                    .frame(width: particle.size, height: particle.size)
                    .position(
                        x: geo.size.width * particle.x,
                        y: geo.size.height * particle.y
                    )
                    .blur(radius: 1)
            }
        }
        .allowsHitTesting(false)
        .animation(.easeInOut(duration: 6).repeatForever(autoreverses: true), value: particleGlow)
    }

    private func spawnParticles() {
        for i in 0..<8 {
            particles.append(MeditationParticle(
                id: i,
                x: CGFloat.random(in: 0.2...0.8),
                y: CGFloat.random(in: 0.25...0.65),
                size: CGFloat.random(in: 2...4),
                opacity: Double.random(in: 0.08...0.2)
            ))
        }
        particleGlow = true
        startWarmthProgression()
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
        guard !rhythm.isNone else { return }
        if rippleRings.count > 3 { rippleRings.removeFirst() }
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

            let glowAmount = isHolding ? holdIntensity : 0

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.moss.opacity(0.7 + glowAmount * 0.2),
                            Color.moss.opacity(0.3 + glowAmount * 0.1)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(circleScale)
                .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isHolding)

            Circle()
                .stroke(Color.moss.opacity(0.25 + glowAmount * 0.15 + milestoneFlash * 0.4), lineWidth: 1 + glowAmount * 0.5 + milestoneFlash * 1.5)
                .frame(width: 200, height: 200)
                .scaleEffect(circleScale * 1.3)
                .opacity(Double(circleScale))
        }
    }

    // MARK: - Labels

    private var breathCountLabel: some View {
        Text("\(breathCount)")
            .font(Constants.Typography.caption)
            .foregroundColor(Color.parchment.opacity(0.15))
            .monospacedDigit()
    }

    @ViewBuilder
    private var soundscapeLabel: some View {
        if let name = selectedSoundscapeName {
            Button {
                soundscapePlayer.toggleMute()
            } label: {
                if soundscapePlayer.isMuted {
                    Text("♪ Paused")
                        .font(Constants.Typography.caption)
                        .foregroundColor(Color.fog.opacity(0.2))
                        .strikethrough(color: Color.fog.opacity(0.2))
                } else {
                    Text("♪ \(name)")
                        .font(Constants.Typography.caption)
                        .foregroundColor(Color.fog.opacity(0.35))
                }
            }
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 1.0).onEnded { _ in
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                    showSoundscapePicker = true
                }
            )
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
            .font(Constants.Typography.statValue)
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
                .font(Constants.Typography.timer)
                .foregroundColor(Color.parchment.opacity(0.9))

            Text(closingPhrase)
                .font(Constants.Typography.body)
                .foregroundColor(Color.fog.opacity(0.5))
        }
        .padding(.bottom, 48)
    }

    // MARK: - Done Button

    private var doneButton: some View {
        Button(action: beginClosingCeremony) {
            Text("Done")
                .font(Constants.Typography.button)
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

    // MARK: - Soundscape Picker

    private var soundscapePickerSheet: some View {
        VStack(spacing: 16) {
            Text("Soundscape")
                .font(Constants.Typography.heading)
                .foregroundColor(Color.parchment.opacity(0.8))
                .padding(.top, 12)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(AudioManifestService.shared.soundscapes) { scape in
                        let isSelected = soundscapePlayer.currentAsset?.id == scape.id
                            || (soundscapePlayer.currentAsset == nil && UserPreferences.selectedSoundscapeId.value == scape.id)
                        Button {
                            UserPreferences.selectedSoundscapeId.value = scape.id
                            if AudioFileStore.shared.isAvailable(scape) {
                                soundscapePlayer.play(scape, volume: Float(UserPreferences.soundscapeVolume.value))
                            }
                            showSoundscapePicker = false
                        } label: {
                            HStack {
                                Text(scape.displayName)
                                    .font(Constants.Typography.body)
                                    .foregroundColor(Color.parchment.opacity(0.9))
                                Spacer()
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundColor(.moss)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                isSelected
                                    ? Color.moss.opacity(0.08)
                                    : Color.clear
                            )
                            .cornerRadius(10)
                        }
                    }

                    Button {
                        soundscapePlayer.stop()
                        UserPreferences.selectedSoundscapeId.value = nil
                        showSoundscapePicker = false
                    } label: {
                        let noneSelected = soundscapePlayer.currentAsset == nil && UserPreferences.selectedSoundscapeId.value == nil
                        HStack {
                            Text("None")
                                .font(Constants.Typography.body)
                                .foregroundColor(Color.parchment.opacity(0.5))
                            Spacer()
                            if noneSelected {
                                Image(systemName: "checkmark")
                                    .font(.caption)
                                    .foregroundColor(.moss)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(noneSelected ? Color.moss.opacity(0.08) : Color.clear)
                        .cornerRadius(10)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Breath Picker

    private var breathPickerSheet: some View {
        VStack(spacing: 16) {
            Text("Breath Rhythm")
                .font(Constants.Typography.heading)
                .foregroundColor(Color.parchment.opacity(0.8))
                .padding(.top, 12)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(BreathRhythm.all) { r in
                        Button {
                            selectedRhythmId = r.id
                            UserPreferences.breathRhythm.value = r.id
                            isActive = false
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                isActive = true
                                startBreathCycle()
                            }
                            showBreathPicker = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        Text(r.name)
                                            .font(Constants.Typography.body)
                                            .foregroundColor(Color.parchment.opacity(0.9))
                                        Text(r.label)
                                            .font(Constants.Typography.caption)
                                            .foregroundColor(Color.fog.opacity(0.4))
                                    }
                                    Text(r.description)
                                        .font(Constants.Typography.caption)
                                        .foregroundColor(Color.fog.opacity(0.35))
                                }
                                Spacer()
                                if selectedRhythmId == r.id {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundColor(.moss)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(
                                selectedRhythmId == r.id
                                    ? Color.moss.opacity(0.08)
                                    : Color.clear
                            )
                            .cornerRadius(10)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    // MARK: - Closing Ceremony

    private func beginClosingCeremony() {
        guard !isClosing else { return }
        isClosing = true
        isActive = false
        clock.stop()
        closingPhrase = Self.closingPhrases.randomElement() ?? "Be at peace"

        soundManagement.onMeditationEnd()

        closingPhase = .dissolving

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            guard self.isClosing else { return }
            self.closingPhase = .summary
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) {
            guard self.isClosing else { return }
            self.closingPhase = .fadeOut
            withAnimation(.easeInOut(duration: 1.5)) {
                self.fadeOverlay = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 6.5) {
            guard self.isClosing, !self.hasDismissed else { return }
            self.hasDismissed = true
            self.onDismiss()
        }
    }

    // MARK: - Breath Cycle

    private func startBreathCycle() {
        breathGeneration += 1
        rippleRings.removeAll()
        isHolding = false

        if rhythm.isNone {
            phase = .inhale
            withAnimation(.easeInOut(duration: 2.0)) {
                circleScale = 0.7
            }
            return
        }
        breathIn()
    }

    private func breathIn() {
        guard isActive else { return }
        let gen = breathGeneration
        if phase == .exhale || phase == .holdOut {
            breathCount += 1
            checkMilestone()
        }
        phase = .inhale
        withAnimation(.easeInOut(duration: rhythm.inhale)) {
            circleScale = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + rhythm.inhale) {
            guard self.isActive, self.breathGeneration == gen else { return }
            self.emitRipple()
            if self.rhythm.holdIn > 0 {
                self.holdAfterInhale()
            } else {
                self.breathOut()
            }
        }
    }

    private static let milestoneSeconds: Set<Int> = [300, 600, 900, 1200, 1800]

    private func checkMilestone() {
        let elapsed = Int(clock.elapsed)
        for m in Self.milestoneSeconds {
            if elapsed >= m && elapsed < m + 20 {
                withAnimation(.easeInOut(duration: 1.5)) { milestoneFlash = 1.0 }
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 1.5)) { self.milestoneFlash = 0 }
                }
                return
            }
        }
    }

    private func holdAfterInhale() {
        guard isActive else { return }
        let gen = breathGeneration
        phase = .holdIn
        holdIntensity = 1.0
        isHolding = true
        DispatchQueue.main.asyncAfter(deadline: .now() + rhythm.holdIn) {
            guard self.isActive, self.breathGeneration == gen else { return }
            self.isHolding = false
            self.breathOut()
        }
    }

    private func breathOut() {
        guard isActive else { return }
        let gen = breathGeneration
        phase = .exhale
        withAnimation(.easeInOut(duration: rhythm.exhale)) {
            circleScale = 0.45
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + rhythm.exhale) {
            guard self.isActive, self.breathGeneration == gen else { return }
            if self.rhythm.holdOut > 0 {
                self.holdAfterExhale()
            } else {
                self.breathIn()
            }
        }
    }

    private func holdAfterExhale() {
        guard isActive else { return }
        let gen = breathGeneration
        phase = .holdOut
        holdIntensity = 0.6
        isHolding = true
        DispatchQueue.main.asyncAfter(deadline: .now() + rhythm.holdOut) {
            guard self.isActive, self.breathGeneration == gen else { return }
            self.isHolding = false
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
    let description: String
    let inhale: Double
    let holdIn: Double
    let exhale: Double
    let holdOut: Double

    var isNone: Bool { inhale == 0 }

    static let all: [BreathRhythm] = [
        BreathRhythm(id: 0, name: "Calm", label: "5 / 7", description: "Long exhale for gentle relaxation", inhale: 5, holdIn: 0, exhale: 7, holdOut: 0),
        BreathRhythm(id: 1, name: "Equal", label: "4 / 4", description: "Balanced and simple", inhale: 4, holdIn: 0, exhale: 4, holdOut: 0),
        BreathRhythm(id: 2, name: "Relaxing", label: "4-7-8", description: "Deep relaxation with held breath", inhale: 4, holdIn: 7, exhale: 8, holdOut: 0),
        BreathRhythm(id: 3, name: "Box", label: "4-4-4-4", description: "Four equal phases for focus", inhale: 4, holdIn: 4, exhale: 4, holdOut: 4),
        BreathRhythm(id: 4, name: "Coherent", label: "5 / 5", description: "Heart rate variability training", inhale: 5, holdIn: 0, exhale: 5, holdOut: 0),
        BreathRhythm(id: 5, name: "Deep calm", label: "3 / 6", description: "Short inhale, slow release", inhale: 3, holdIn: 0, exhale: 6, holdOut: 0),
        BreathRhythm(id: 6, name: "None", label: "—", description: "Still focus point, open meditation", inhale: 0, holdIn: 0, exhale: 0, holdOut: 0),
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
}

struct RippleRing: Identifiable {
    let id: UUID
    var size: CGFloat
    var opacity: Double
}
