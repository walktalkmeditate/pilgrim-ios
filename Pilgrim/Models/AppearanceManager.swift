import SwiftUI
import Combine

final class AppearanceManager: ObservableObject {

    @Published private(set) var resolvedScheme: ColorScheme?

    private var cancellables = Set<AnyCancellable>()

    init() {
        resolvedScheme = Self.resolve(UserPreferences.appearanceMode.value)

        UserPreferences.appearanceMode.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self else { return }
                let newScheme = Self.resolve(newValue)
                guard newScheme != self.resolvedScheme else { return }
                self.animateTransition()
                self.resolvedScheme = newScheme
            }
            .store(in: &cancellables)
    }

    private static func resolve(_ raw: String) -> ColorScheme? {
        (AppearanceMode(rawValue: raw) ?? .system).resolvedScheme
    }

    private func animateTransition() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else { return }
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: {}, completion: nil)
    }
}
