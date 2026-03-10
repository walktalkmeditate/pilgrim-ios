import Foundation
import CoreStore
import Combine

class HomeViewModel: ObservableObject {

    @Published private(set) var walks: [Workout] = []
    var onStartWalk: (() -> Void)?

    private var cancellables: [AnyCancellable] = []

    init() {
        loadWalks()
    }

    func loadWalks() {
        do {
            walks = try DataManager.dataStack.fetchAll(
                From<Workout>()
                    .orderBy(.descending(\._startDate))
            )
        } catch {
            print("[HomeViewModel] Failed to fetch walks:", error.localizedDescription)
            walks = []
        }
    }

    func startWalk() {
        onStartWalk?()
    }
}
