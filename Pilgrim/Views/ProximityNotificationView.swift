import SwiftUI

struct ProximityNotificationView: View {

    let message: String
    let onDismiss: () -> Void

    @State private var isVisible = false

    var body: some View {
        if isVisible {
            HStack(spacing: Constants.UI.Padding.small) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(.stone)
                    .accessibilityHidden(true)

                Text(message)
                    .font(Constants.Typography.caption)
                    .foregroundColor(.ink.opacity(0.8))
                    .lineLimit(1)
            }
            .accessibilityElement(children: .combine)
            .padding(.horizontal, Constants.UI.Padding.normal)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Constants.UI.CornerRadius.normal)
                    .fill(Color.parchment.opacity(0.95))
                    .shadow(color: .ink.opacity(0.08), radius: 8, y: 2)
            )
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    func show() -> Self {
        var view = self
        view._isVisible = State(initialValue: true)
        return view
    }
}

struct ProximityNotificationModifier: ViewModifier {

    @Binding var event: ProximityNotificationEvent?
    @State private var isShowing = false
    @State private var generation = 0

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if isShowing, let event {
                ProximityNotificationView(
                    message: event.message,
                    onDismiss: { dismiss() }
                )
                .show()
                .padding(.top, Constants.UI.Padding.big)
            }
        }
        .onChange(of: event?.id) { _, _ in
            guard event != nil else { return }
            generation += 1
            let gen = generation
            withAnimation(.easeInOut(duration: 0.3)) {
                isShowing = true
            }
            Task {
                try? await Task.sleep(for: .seconds(5))
                guard generation == gen else { return }
                dismiss()
            }
        }
    }

    private func dismiss() {
        withAnimation(.easeInOut(duration: 0.3)) {
            isShowing = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            event = nil
        }
    }
}

struct ProximityNotificationEvent: Equatable {
    let id: UUID
    let message: String

    static func whisper() -> Self {
        ProximityNotificationEvent(id: UUID(), message: "A whisper lingers nearby\u{2026}")
    }

    static func cairn(stoneCount: Int) -> Self {
        let tier = CairnTier.from(stoneCount: stoneCount)
        let detail: String
        switch tier {
        case .faint, .small:
            detail = "A cairn stands nearby\u{2026}"
        case .medium, .large:
            detail = "A cairn of \(stoneCount) stones stands nearby\u{2026}"
        case .great, .sacred:
            detail = "A great cairn of \(stoneCount) stones\u{2026}"
        case .eternal:
            detail = "An eternal cairn of \(stoneCount) stones\u{2026}"
        }
        return ProximityNotificationEvent(id: UUID(), message: detail)
    }

    /// Surfaced when a whisper placement attempt fails (server rejected the
    /// request, network was down, etc.). The placement sheet has already
    /// dismissed by the time we know — without this banner the failure is
    /// invisible to the user. Wabi-sabi tone: no "Error", no exclamation,
    /// suggests the natural metaphor and points at retry.
    static func whisperPlaceFailed() -> Self {
        ProximityNotificationEvent(id: UUID(), message: "The whisper didn\u{2019}t take root. Try again.")
    }
}

extension View {
    func proximityNotification(event: Binding<ProximityNotificationEvent?>) -> some View {
        modifier(ProximityNotificationModifier(event: event))
    }
}
