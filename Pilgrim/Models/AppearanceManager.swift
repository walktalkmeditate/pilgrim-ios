import SwiftUI
import Combine

final class AppearanceManager: ObservableObject {

    @Published private(set) var resolvedScheme: ColorScheme?
    @Published private(set) var isConstellation: Bool

    private var cancellables = Set<AnyCancellable>()

    init() {
        let initial = Self.resolve(UserPreferences.appearanceMode.value)
        resolvedScheme = initial.scheme
        isConstellation = initial.constellation

        UserPreferences.appearanceMode.publisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newValue in
                guard let self else { return }
                let next = Self.resolve(newValue)
                let schemeChanged = next.scheme != self.resolvedScheme
                let constellationChanged = next.constellation != self.isConstellation
                guard schemeChanged || constellationChanged else { return }
                if schemeChanged { self.animateTransition() }
                self.resolvedScheme = next.scheme
                self.isConstellation = next.constellation
            }
            .store(in: &cancellables)
    }

    private static func resolve(_ raw: String) -> (scheme: ColorScheme?, constellation: Bool) {
        let mode = AppearanceMode(rawValue: raw) ?? .system
        return (mode.resolvedScheme, mode.isConstellation)
    }

    private func animateTransition() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let window = scene.windows.first else { return }
        UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve, animations: {}, completion: nil)
    }
}
