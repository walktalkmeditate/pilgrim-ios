import SwiftUI

struct MeditationView: View {

    let onDismiss: () -> Void

    @State private var phase: BreathPhase = .inhale
    @State private var circleScale: CGFloat = 0.45
    @State private var isActive = true
    @StateObject private var clock = SessionClock()

    private let inhaleSeconds: Double = 4
    private let exhaleSeconds: Double = 4

    var body: some View {
        ZStack {
            Color.ink.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                breathingCircle
                    .padding(.bottom, 48)

                breathLabel
                    .padding(.bottom, 12)

                sessionTimer
                    .padding(.bottom, 48)

                Spacer()

                doneButton
                    .padding(.bottom, 40)
            }
        }
        .onAppear { startBreathCycle() }
        .onDisappear {
            isActive = false
            clock.stop()
        }
        .statusBarHidden()
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
                            Color.moss.opacity(0.7),
                            Color.moss.opacity(0.3)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 80
                    )
                )
                .frame(width: 160, height: 160)
                .scaleEffect(circleScale)

            Circle()
                .stroke(Color.moss.opacity(0.25), lineWidth: 1)
                .frame(width: 200, height: 200)
                .scaleEffect(circleScale * 1.3)
                .opacity(Double(circleScale))
        }
    }

    // MARK: - Labels

    private var breathLabel: some View {
        Text(phase.label)
            .font(.system(.title3, design: .serif).weight(.light))
            .foregroundColor(Color.parchment.opacity(0.7))
            .animation(.easeInOut(duration: 0.6), value: phase)
    }

    private var sessionTimer: some View {
        Text(formatTime(clock.elapsed))
            .font(.system(.body, design: .serif))
            .foregroundColor(Color.fog)
            .monospacedDigit()
    }

    private var doneButton: some View {
        Button(action: onDismiss) {
            Text("Done")
                .font(Constants.Typography.button)
                .foregroundColor(Color.parchment)
                .padding(.horizontal, 48)
                .padding(.vertical, 14)
                .background(
                    Capsule()
                        .fill(Color.stone.opacity(0.85))
                )
        }
    }

    // MARK: - Breath Cycle

    private func startBreathCycle() {
        breathIn()
    }

    private func breathIn() {
        guard isActive else { return }
        phase = .inhale
        withAnimation(.easeInOut(duration: inhaleSeconds)) {
            circleScale = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + inhaleSeconds) {
            breathOut()
        }
    }

    private func breathOut() {
        guard isActive else { return }
        phase = .exhale
        withAnimation(.easeInOut(duration: exhaleSeconds)) {
            circleScale = 0.45
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + exhaleSeconds) {
            breathIn()
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds))
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

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
    case inhale, exhale

    var label: String {
        switch self {
        case .inhale: return "Breathe in"
        case .exhale: return "Breathe out"
        }
    }
}
