import Foundation

final class IntentionHistoryStore: ObservableObject {
    static let maxIntentions = 5

    @Published private(set) var intentions: [String]

    private let userDefaultsKey: String

    init(userDefaultsKey: String = "IntentionHistory") {
        self.userDefaultsKey = userDefaultsKey
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            intentions = decoded
        } else {
            intentions = []
        }
    }

    func add(_ intention: String) {
        let trimmed = intention.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        intentions.removeAll { $0 == trimmed }
        intentions.insert(trimmed, at: 0)

        if intentions.count > Self.maxIntentions {
            intentions = Array(intentions.prefix(Self.maxIntentions))
        }

        persist()
    }

    func clear() {
        intentions = []
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(intentions) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
}
