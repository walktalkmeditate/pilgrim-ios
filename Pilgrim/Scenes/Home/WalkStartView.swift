import SwiftUI

struct WalkStartView: View {

    let onStartWalk: (WalkMode) -> Void

    @State private var selectedMode: WalkMode = .wander
    @State private var currentQuote: String = ""
    @State private var breathing = false
    @State private var ambientOffset: CGSize = .zero

    @State private var showLogo = false
    @State private var showQuote = false
    @State private var showMoon = false
    @State private var glowScale: CGFloat = 1.0
    @State private var entranceGeneration = 0
    @State private var activeMode: WalkMode = .wander
    @State private var footprintVisible = true
    @State private var transitionGeneration = 0
    @State private var seekFloatOffset: CGFloat = 0
    @State private var collectivePulse = false
    @ObservedObject private var counterService = CollectiveCounterService.shared
    @State private var footprintBreathScale: CGFloat = 1.0
    @State private var togetherDriftOffset: CGSize = .zero
    @State private var togetherCompanionsVisible = false

    @State private var lunarPhase = LunarPhase.current()

    private let haptic = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        ZStack {
            background
            content
        }
        .onAppear {
            currentQuote = selectedMode.quotes.randomElement() ?? ""
            lunarPhase = LunarPhase.current()
            breathing = true
            runEntrance()
        }
        .onChange(of: selectedMode) { _, mode in
            withAnimation(.easeInOut(duration: 0.4)) {
                currentQuote = mode.quotes.randomElement() ?? ""
            }
        }
        .onChange(of: selectedMode) { _, newMode in
            if UIAccessibility.isReduceMotionEnabled {
                withAnimation(.linear(duration: 0.2)) {
                    activeMode = newMode
                }
                return
            }
            transitionGeneration += 1
            let gen = transitionGeneration
            withAnimation(.easeIn(duration: 0.3)) {
                footprintVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                guard transitionGeneration == gen else { return }
                activeMode = newMode
                haptic.impactOccurred()
                withAnimation(.easeOut(duration: 0.3)) {
                    footprintVisible = true
                }
            }
        }
        .onDisappear {
            entranceGeneration += 1
            breathing = false
            showLogo = false
            showQuote = false
            showMoon = false
            glowScale = 1.0
            transitionGeneration += 1
            footprintVisible = true
            activeMode = .wander
            seekFloatOffset = 0
            footprintBreathScale = 1.0
            togetherDriftOffset = .zero
            togetherCompanionsVisible = false
        }
    }

    // MARK: - Background

    private var timeOfDay: (tint: Color, opacity: Double) {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5...7:   return (.orange, 0.03)
        case 8...15:  return (.yellow, 0.02)
        case 16...19: return (.orange, 0.04)
        default:      return (.blue, 0.02)
        }
    }

    private var background: some View {
        let tod = timeOfDay
        return ZStack {
            Color.parchment
            tod.tint.opacity(tod.opacity)
            if !UIAccessibility.isReduceMotionEnabled {
                RadialGradient(
                    colors: [tod.tint.opacity(tod.opacity * 1.5), Color.clear],
                    center: UnitPoint(
                        x: 0.5 + ambientOffset.width,
                        y: 0.5 + ambientOffset.height
                    ),
                    startRadius: 50,
                    endRadius: 300
                )
                .onAppear {
                    withAnimation(
                        .easeInOut(duration: 15)
                        .repeatForever(autoreverses: true)
                    ) {
                        ambientOffset = CGSize(width: 0.15, height: 0.1)
                    }
                }
            }
            modeAtmosphere
        }
        .ignoresSafeArea()
    }

    private var modeAtmosphere: some View {
        Group {
            switch selectedMode {
            case .wander:
                Color.clear
            case .together:
                Color.dawn.opacity(0.01)
            case .seek:
                Color.fog.opacity(0.01)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: selectedMode)
    }

    // MARK: - Content

    @Environment(\.dynamicTypeSize) private var homeTypeSize

    private var isHomeLargeText: Bool {
        homeTypeSize >= .accessibility2
    }

    private var content: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    Spacer(minLength: isHomeLargeText ? 16 : 40)

                    PilgrimLogoView(size: isHomeLargeText ? 60 : 100, breathing: $breathing)
                        .scaleEffect(collectivePulse ? 1.03 : 1.0)
                        .shadow(color: .stone.opacity(collectivePulse ? 0.3 : 0), radius: collectivePulse ? 12 : 0)
                        .animation(
                            collectivePulse
                                ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true)
                                : .default,
                            value: collectivePulse
                        )
                        .opacity(showLogo ? 1 : 0)
                        .scaleEffect(showLogo ? 1.0 : 0.95)
                        .padding(.bottom, Constants.UI.Padding.big)
                        .onReceive(counterService.$stats) { stats in
                            if let stats, stats.walkedInLastHour, !collectivePulse {
                                collectivePulse = true
                            }
                        }

                    Text(currentQuote)
                        .font(Constants.Typography.displayMedium)
                        .foregroundColor(.fog)
                        .multilineTextAlignment(.center)
                        .minimumScaleFactor(0.5)
                        .lineLimit(isHomeLargeText ? 3 : 4)
                        .opacity(showQuote ? 1 : 0)

                    if !isHomeLargeText {
                        Spacer(minLength: 20)

                        MoonPhaseView(phase: lunarPhase)
                            .opacity(showMoon ? 1 : 0)

                        Spacer(minLength: 20)
                    } else {
                        Spacer(minLength: 16)
                    }
                }
            }

            modeSelector
                .padding(.bottom, Constants.UI.Padding.normal)

            Button(action: { onStartWalk(selectedMode) }) {
                Text(selectedMode.buttonLabel)
                    .font(Constants.Typography.button)
                    .minimumScaleFactor(0.8)
                    .lineLimit(1)
                    .foregroundColor(.parchment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(selectedMode.isAvailable ? Color.stone : Color.fog.opacity(0.2))
                    .cornerRadius(Constants.UI.CornerRadius.normal)
                    .contentTransition(.interpolate)
            }
            .disabled(!selectedMode.isAvailable)
            .shadow(color: .stone.opacity(selectedMode.isAvailable ? 0.2 : 0), radius: 8, x: 0, y: 3)
            .shadow(color: .stone.opacity(selectedMode.isAvailable ? 0.12 * glowScale : 0), radius: 20 * glowScale, x: 0, y: 0)
            .animation(.easeInOut(duration: 0.3), value: selectedMode.isAvailable)
            .accessibilityLabel("Begin your journey")
            .accessibilityIdentifier("start_walk_button")
        }
        .padding(.horizontal, Constants.UI.Padding.big)
        .padding(.bottom, Constants.UI.Padding.big)
    }

    // MARK: - Footprint Display

    @ViewBuilder
    private func footprintForMode(_ mode: WalkMode) -> some View {
        let isActive = mode == activeMode
        Group {
            switch mode {
            case .wander: wanderFootprints
            case .together: togetherFootprints
            case .seek: seekFootprints
            }
        }
        .frame(width: 60, height: 50)
        .scaleEffect(isActive && footprintVisible ? footprintBreathScale : (isActive ? 1.08 : 0.92))
        .opacity(isActive && footprintVisible ? 1.0 : 0.0)
        .accessibilityHidden(true)
    }

    private var wanderFootprints: some View {
        HStack(spacing: 2) {
            FootprintShape()
                .fill(Color.ink.opacity(0.08))
                .frame(width: 16, height: 26)
                .scaleEffect(x: -1)
                .rotationEffect(.degrees(-12))
            FootprintShape()
                .fill(Color.ink.opacity(0.06))
                .frame(width: 16, height: 26)
                .rotationEffect(.degrees(12))
        }
    }

    private var togetherFootprints: some View {
        ZStack {
            HStack(spacing: 2) {
                FootprintShape()
                    .fill(Color.ink.opacity(0.06))
                    .frame(width: 14, height: 22)
                    .scaleEffect(x: -1)
                    .rotationEffect(.degrees(-18))
                FootprintShape()
                    .fill(Color.ink.opacity(0.05))
                    .frame(width: 14, height: 22)
                    .rotationEffect(.degrees(6))
            }
            .offset(
                x: -14 + togetherDriftOffset.width,
                y: -10 + togetherDriftOffset.height
            )
            .opacity(togetherCompanionsVisible ? 1 : 0)

            HStack(spacing: 2) {
                FootprintShape()
                    .fill(Color.ink.opacity(0.05))
                    .frame(width: 14, height: 22)
                    .scaleEffect(x: -1)
                    .rotationEffect(.degrees(8))
                FootprintShape()
                    .fill(Color.ink.opacity(0.04))
                    .frame(width: 14, height: 22)
                    .rotationEffect(.degrees(-16))
            }
            .offset(
                x: 12 - togetherDriftOffset.width,
                y: -8 - togetherDriftOffset.height
            )
            .opacity(togetherCompanionsVisible ? 1 : 0)

            HStack(spacing: 2) {
                FootprintShape()
                    .fill(Color.ink.opacity(0.10))
                    .frame(width: 16, height: 26)
                    .scaleEffect(x: -1)
                    .rotationEffect(.degrees(-12))
                FootprintShape()
                    .fill(Color.ink.opacity(0.08))
                    .frame(width: 16, height: 26)
                    .rotationEffect(.degrees(12))
            }
        }
        .frame(width: 60, height: 50)
        .onAppear {
            if UIAccessibility.isReduceMotionEnabled {
                togetherCompanionsVisible = true
                return
            }
            withAnimation(.easeOut(duration: 0.3).delay(0.1)) {
                togetherCompanionsVisible = true
            }
            withAnimation(.easeInOut(duration: 6.0).repeatForever(autoreverses: true)) {
                togetherDriftOffset = CGSize(width: 1, height: 0.5)
            }
        }
        .onDisappear {
            togetherDriftOffset = .zero
            togetherCompanionsVisible = false
        }
    }

    private var seekFootprints: some View {
        HStack(spacing: 2) {
            FootprintShape()
                .fill(Color.ink.opacity(0.10))
                .frame(width: 16, height: 26)
                .scaleEffect(x: -1)
                .rotationEffect(.degrees(-12))

            dissolvingDots
                .frame(width: 16, height: 30)
                .rotationEffect(.degrees(12))
                .offset(y: seekFloatOffset)
                .onAppear {
                    guard !UIAccessibility.isReduceMotionEnabled else { return }
                    withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                        seekFloatOffset = -2
                    }
                }
                .onDisappear {
                    seekFloatOffset = 0
                }
        }
    }

    private var dissolvingDots: some View {
        Canvas { context, size in
            let dots: [(x: CGFloat, y: CGFloat, r: CGFloat, a: Double)] = [
                (0.5, 0.85, 2.5, 0.08),
                (0.3, 0.65, 2.0, 0.07),
                (0.7, 0.55, 2.0, 0.06),
                (0.4, 0.38, 1.5, 0.04),
                (0.6, 0.20, 1.5, 0.03),
                (0.5, 0.05, 1.0, 0.02)
            ]
            for dot in dots {
                let rect = CGRect(
                    x: size.width * dot.x - dot.r,
                    y: size.height * dot.y - dot.r,
                    width: dot.r * 2,
                    height: dot.r * 2
                )
                context.fill(Circle().path(in: rect), with: .color(.ink.opacity(dot.a)))
            }
        }
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            HStack(spacing: Constants.UI.Padding.small) {
                ForEach(WalkMode.allCases, id: \.self) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        VStack(spacing: Constants.UI.Padding.small) {
                            footprintForMode(mode)

                            VStack(spacing: Constants.UI.Padding.xs) {
                                Text(mode.rawValue.uppercased())
                                    .font(Constants.Typography.button)
                                    .foregroundColor(mode == selectedMode ? .stone : .fog.opacity(0.3))
                                    .lineLimit(1)
                                trailUnderline(for: mode)
                                    .frame(height: 2)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)

            Text(selectedMode.isAvailable ? selectedMode.subtitle : "coming soon")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog.opacity(0.5))
                .minimumScaleFactor(0.7)
                .lineLimit(1)
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: selectedMode)
        }
    }

    @ViewBuilder
    private func trailUnderline(for mode: WalkMode) -> some View {
        if mode == selectedMode {
            switch mode {
            case .wander:
                LinearGradient(
                    colors: [.stone, .stone.opacity(0.2)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            case .together:
                LinearGradient(
                    colors: [.stone.opacity(0.3), .stone, .stone.opacity(0.3)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            case .seek:
                LinearGradient(
                    colors: [.stone.opacity(0.2), .stone],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        } else {
            Color.clear
        }
    }

    // MARK: - Entrance

    private func runEntrance() {
        if UIAccessibility.isReduceMotionEnabled {
            showLogo = true
            showQuote = true
            showMoon = true
            breathing = true
            return
        }

        withAnimation(.easeOut(duration: 0.5)) {
            showLogo = true
        }
        breathing = true

        withAnimation(.easeOut(duration: 0.5).delay(0.4)) {
            showQuote = true
        }

        withAnimation(.easeOut(duration: 0.5).delay(0.6)) {
            showMoon = true
        }

        let generation = entranceGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            guard entranceGeneration == generation else { return }
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                glowScale = 1.05
                footprintBreathScale = 1.01
            }
        }
    }
}
