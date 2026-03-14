import SwiftUI
import MapKit

struct ActiveWalkView: View {

    @ObservedObject var viewModel: ActiveWalkViewModel
    @State private var showStopConfirmation = false
    @State private var showMeditation = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ZStack(alignment: .bottom) {
                    mapSection(height: geometry.size.height * 0.6)
                    LinearGradient(
                        colors: [.clear, .parchment],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 40)
                }

                statsSection
                Spacer(minLength: 0)
                controlsSection
            }
        }
        .background(Color.parchment)
        .ignoresSafeArea(edges: .top)
        .alert("End Walk?", isPresented: $showStopConfirmation) {
            Button("End Walk", role: .destructive) { viewModel.stop() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will save your walk and show the summary.")
        }
        .fullScreenCover(isPresented: $showMeditation) {
            MeditationView {
                viewModel.endMeditation()
                showMeditation = false
            }
        }
    }

    private func mapSection(height: CGFloat) -> some View {
        let overlays: [MKOverlay] = viewModel.routeOverlays
        return MapView(
            showsUserLocation: .constant(true),
            userTrackingMode: .constant(.follow),
            overlays: .constant(overlays)
        )
        .frame(height: height)
    }

    private var statsSection: some View {
        VStack(spacing: Constants.UI.Padding.normal) {
            VStack(spacing: 4) {
                Text(viewModel.duration)
                    .font(Constants.Typography.timer)
                    .foregroundColor(.ink)

                if let name = viewModel.currentSoundscapeName {
                    Text("♪ \(name)")
                        .font(Constants.Typography.caption)
                        .foregroundColor(.fog)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.5), value: viewModel.currentSoundscapeName)

            if viewModel.paceHistory.count > 2 {
                LivePaceSparklineView(values: viewModel.paceHistory)
                    .frame(height: 28)
                    .padding(.horizontal, Constants.UI.Padding.big)
                    .transition(.opacity)
            }

            HStack(spacing: Constants.UI.Padding.big) {
                StatItem(label: "Distance", value: viewModel.distance)
                StatItem(label: "Steps", value: viewModel.steps)
                StatItem(label: "Speed", value: viewModel.speed)
            }

            HStack(spacing: Constants.UI.Padding.big) {
                TimeMetricItem(label: "Walk", value: viewModel.walkTime, icon: "figure.walk",
                               isActive: !viewModel.isRecordingVoice && !viewModel.isMeditating)
                TimeMetricItem(label: "Talk", value: viewModel.talkTime, icon: "waveform",
                               isActive: viewModel.isRecordingVoice)
                TimeMetricItem(label: "Meditate", value: viewModel.meditateTime, icon: "brain.head.profile",
                               isActive: viewModel.isMeditating)
            }
        }
        .padding(.vertical, Constants.UI.Padding.normal)
        .padding(.horizontal, Constants.UI.Padding.normal)
    }

    private var micButton: some View {
        Button(action: { viewModel.toggleVoiceRecording() }) {
            VStack(spacing: 6) {
                if viewModel.isRecordingVoice {
                    AudioWaveformView(level: viewModel.audioLevel)
                        .frame(width: 36, height: 24)
                } else {
                    Image(systemName: "mic")
                        .font(.title)
                }
                Text(viewModel.isRecordingVoice ? "Stop" : "Record")
                    .font(Constants.Typography.caption)
            }
            .foregroundColor(viewModel.isRecordingVoice ? .rust : .stone)
            .frame(width: 72, height: 72)
            .background(
                Circle()
                    .stroke(viewModel.isRecordingVoice ? Color.rust : Color.stone, lineWidth: 2)
            )
        }
    }

    private var controlsSection: some View {
        HStack(spacing: Constants.UI.Padding.big) {
            switch viewModel.status {
            case .waiting:
                SwiftUI.ProgressView()
                    .tint(.stone)
                    .frame(maxWidth: .infinity)
            case .ready:
                outlinedButton("Start", systemImage: "play.fill", color: .moss) {
                    viewModel.startRecording()
                }
            case .recording, .paused, .autoPaused:
                outlinedButton("Meditate", systemImage: "brain.head.profile", color: .moss) {
                    viewModel.startMeditation()
                    showMeditation = true
                }
                micButton
                outlinedButton("Stop", systemImage: "stop.fill", color: .rust) {
                    showStopConfirmation = true
                }
            }
        }
        .padding(Constants.UI.Padding.normal)
        .padding(.bottom, Constants.UI.Padding.normal)
    }

    private func outlinedButton(_ title: String, systemImage: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                Text(title)
                    .font(Constants.Typography.caption)
            }
            .foregroundColor(color)
            .frame(width: 72, height: 72)
            .background(
                Circle()
                    .stroke(color, lineWidth: 2)
            )
        }
    }
}

struct TimeMetricItem: View {
    let label: String
    let value: String
    let icon: String
    var isActive: Bool = false

    @State private var pulseScale: CGFloat = 1.0

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if isActive {
                    Circle()
                        .fill(activeColor.opacity(0.15))
                        .frame(width: 22, height: 22)
                        .scaleEffect(pulseScale)
                        .onAppear {
                            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                                pulseScale = 1.5
                            }
                        }
                        .onDisappear { pulseScale = 1.0 }
                }
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(isActive ? activeColor : .stone)
            }
            Text(value)
                .font(Constants.Typography.statValue)
                .foregroundColor(.ink)
            Text(label)
                .font(Constants.Typography.statLabel)
                .foregroundColor(.fog)
        }
        .frame(maxWidth: .infinity)
        .animation(.easeInOut(duration: 0.3), value: isActive)
    }

    private var activeColor: Color {
        switch label {
        case "Talk": return .rust
        case "Meditate": return .moss
        default: return .stone
        }
    }
}

struct LivePaceSparklineView: View {
    let values: [Double]

    var body: some View {
        GeometryReader { geo in
            let filtered = values.filter { $0 > 0 }
            if filtered.count > 1 {
                let maxVal = filtered.max() ?? 1
                let minVal = filtered.min() ?? 0
                let range = max(maxVal - minVal, 0.5)

                Path { path in
                    for (i, val) in filtered.enumerated() {
                        let x = geo.size.width * CGFloat(i) / CGFloat(filtered.count - 1)
                        let normalized = (val - minVal) / range
                        let y = geo.size.height * (1 - CGFloat(normalized))
                        if i == 0 {
                            path.move(to: CGPoint(x: x, y: y))
                        } else {
                            path.addLine(to: CGPoint(x: x, y: y))
                        }
                    }
                }
                .stroke(Color.stone.opacity(0.4), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(Constants.Typography.statValue)
                .foregroundColor(.ink)
            Text(label)
                .font(Constants.Typography.statLabel)
                .foregroundColor(.fog)
        }
        .frame(maxWidth: .infinity)
    }
}

struct AudioWaveformView: View {

    let level: Float

    private let barCount = 5
    private let barWeights: [Float] = [0.6, 0.8, 1.0, 0.8, 0.6]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.rust)
                    .frame(width: 4, height: barHeight(for: index))
            }
        }
        .animation(.easeOut(duration: 0.08), value: level)
    }

    private func barHeight(for index: Int) -> CGFloat {
        let weight = CGFloat(barWeights[index])
        let amplitude = CGFloat(level) * weight
        let minHeight: CGFloat = 4
        let maxHeight: CGFloat = 24
        return minHeight + amplitude * (maxHeight - minHeight)
    }
}
