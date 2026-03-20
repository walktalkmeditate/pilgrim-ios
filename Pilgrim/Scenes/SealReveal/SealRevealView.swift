import SwiftUI
import UIKit

struct SealRevealView: View {

    let walk: WalkInterface
    let onDismiss: () -> Void
    let onShareSeal: (UIImage) -> Void

    @State private var phase: AnimationPhase = .hidden
    @State private var autoDismissTask: Task<Void, Never>?
    @State private var cachedSealImage: UIImage?

    private enum AnimationPhase {
        case hidden, pressing, revealed
    }

    private let sealSize: CGFloat = 220
    private let haptic = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        ZStack {
            Color.parchment
                .opacity(0.95)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            sealImageView
                .scaleEffect(scale)
                .opacity(opacity)
                .shadow(
                    color: .black.opacity(shadowOpacity),
                    radius: 12, x: 0, y: 6
                )
                .onTapGesture { shareSeal() }
        }
        .onAppear { startAnimation() }
        .onDisappear { autoDismissTask?.cancel() }
    }

    @ViewBuilder
    private var sealImageView: some View {
        if let image = cachedSealImage {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: sealSize, height: sealSize)
        }
    }

    private var scale: CGFloat {
        switch phase {
        case .hidden:   return 1.2
        case .pressing: return 0.95
        case .revealed: return 1.0
        }
    }

    private var opacity: Double {
        phase == .hidden ? 0 : 1
    }

    private var shadowOpacity: Double {
        phase == .revealed ? 0.25 : 0
    }

    // MARK: - Animation

    private func startAnimation() {
        cachedSealImage = SealGenerator.generate(for: walk, size: 512)
        haptic.prepare()

        withAnimation(.easeIn(duration: 0.2)) {
            phase = .pressing
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            haptic.impactOccurred()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                phase = .revealed
            }
        }

        autoDismissTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await MainActor.run { dismiss() }
        }
    }

    private func dismiss() {
        autoDismissTask?.cancel()
        onDismiss()
    }

    private func shareSeal() {
        autoDismissTask?.cancel()
        guard let image = cachedSealImage else { return }
        onShareSeal(image)
    }
}
