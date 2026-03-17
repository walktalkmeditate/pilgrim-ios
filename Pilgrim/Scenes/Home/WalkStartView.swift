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
    @State private var showButton = false
    @State private var glowScale: CGFloat = 1.0
    @State private var entranceGeneration = 0

    @State private var lunarPhase = LunarPhase.current()

    var body: some View {
        ZStack {
            background
            content
        }
        .onAppear {
            currentQuote = selectedMode.quotes.randomElement() ?? ""
            lunarPhase = LunarPhase.current()
            runEntrance()
        }
        .onChange(of: selectedMode) { _, mode in
            withAnimation(.easeInOut(duration: 0.4)) {
                currentQuote = mode.quotes.randomElement() ?? ""
            }
        }
        .onDisappear {
            entranceGeneration += 1
            breathing = false
            showLogo = false
            showQuote = false
            showMoon = false
            showButton = false
            glowScale = 1.0
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
        }
        .ignoresSafeArea()
    }

    // MARK: - Content

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 40)

            PilgrimLogoView(size: 100, breathing: $breathing)
                .opacity(showLogo ? 1 : 0)
                .scaleEffect(showLogo ? 1.0 : 0.95)
                .padding(.bottom, Constants.UI.Padding.big)

            Text(currentQuote)
                .font(Constants.Typography.displayMedium)
                .foregroundColor(.fog)
                .multilineTextAlignment(.center)
                .opacity(showQuote ? 1 : 0)

            Spacer()

            MoonPhaseView(phase: lunarPhase)
                .opacity(showMoon ? 1 : 0)

            Spacer()

            footprintPair
                .opacity(showButton ? 1 : 0)
                .padding(.bottom, Constants.UI.Padding.normal)

            modeSelector
                .padding(.bottom, Constants.UI.Padding.normal)
                .opacity(showButton ? 1 : 0)

            Button(action: { onStartWalk(selectedMode) }) {
                Text(LS["Welcome.Begin"])
                    .font(Constants.Typography.button)
                    .foregroundColor(.parchment)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(selectedMode.isAvailable ? Color.stone : Color.fog.opacity(0.2))
                    .cornerRadius(Constants.UI.CornerRadius.normal)
            }
            .disabled(!selectedMode.isAvailable)
            .shadow(color: .stone.opacity(selectedMode.isAvailable ? 0.2 : 0), radius: 8, x: 0, y: 3)
            .shadow(color: .stone.opacity(selectedMode.isAvailable ? 0.12 * glowScale : 0), radius: 20 * glowScale, x: 0, y: 0)
            .opacity(showButton ? 1 : 0)
            .offset(y: showButton ? 0 : 20)
            .animation(.easeInOut(duration: 0.3), value: selectedMode.isAvailable)
            .accessibilityLabel("Begin your journey")
        }
        .padding(.horizontal, Constants.UI.Padding.big)
        .padding(.bottom, Constants.UI.Padding.big)
    }

    // MARK: - Footprint Pair

    private var footprintPair: some View {
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
        .accessibilityHidden(true)
    }

    // MARK: - Mode Selector

    private var modeSelector: some View {
        VStack(spacing: Constants.UI.Padding.small) {
            HStack(spacing: Constants.UI.Padding.big) {
                ForEach(WalkMode.allCases, id: \.self) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        VStack(spacing: Constants.UI.Padding.xs) {
                            Text(mode.rawValue.uppercased())
                                .font(Constants.Typography.button)
                                .foregroundColor(mode == selectedMode ? .stone : .fog.opacity(0.3))
                                .fixedSize()
                            Rectangle()
                                .frame(height: 2)
                                .foregroundColor(mode == selectedMode ? .stone : .clear)
                        }
                    }
                }
            }

            Text(selectedMode.isAvailable ? selectedMode.subtitle : "coming soon")
                .font(Constants.Typography.caption)
                .foregroundColor(.fog.opacity(0.5))
                .contentTransition(.opacity)
                .animation(.easeInOut(duration: 0.3), value: selectedMode)
        }
    }

    // MARK: - Entrance

    private func runEntrance() {
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        if reduceMotion {
            showLogo = true
            showQuote = true
            showMoon = true
            showButton = true
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

        withAnimation(.easeOut(duration: 0.5).delay(0.8)) {
            showButton = true
        }

        let generation = entranceGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.3) {
            guard entranceGeneration == generation else { return }
            withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
                glowScale = 1.05
            }
        }
    }
}
