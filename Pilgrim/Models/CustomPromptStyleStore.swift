import Foundation

struct CustomPromptStyle: Codable, Identifiable {
    let id: UUID
    var title: String
    var icon: String
    var instruction: String
}

final class CustomPromptStyleStore: ObservableObject {
    static let maxStyles = 3

    @Published private(set) var styles: [CustomPromptStyle]

    private let userDefaultsKey: String

    init(userDefaultsKey: String = "CustomPromptStyles") {
        self.userDefaultsKey = userDefaultsKey
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([CustomPromptStyle].self, from: data) {
            styles = decoded
        } else {
            styles = []
        }
    }

    var canAddMore: Bool { styles.count < Self.maxStyles }

    func save(_ style: CustomPromptStyle) {
        if let index = styles.firstIndex(where: { $0.id == style.id }) {
            styles[index] = style
        } else {
            guard canAddMore else { return }
            styles.append(style)
        }
        persist()
    }

    func delete(_ style: CustomPromptStyle) {
        styles.removeAll { $0.id == style.id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(styles) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
