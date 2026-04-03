import Foundation
import CoreLocation
import Combine

final class ProximityDetectionService {

    static let whisperRadius: CLLocationDistance = 42
    static let cairnRadius: CLLocationDistance = 108

    private var targets: Set<ProximityTarget> = []
    private var notifiedTargetIDs: Set<String> = []
    private var cancellables: [AnyCancellable] = []

    let proximityEvents = PassthroughSubject<ProximityEvent, Never>()

    func updateTargets(_ newTargets: Set<ProximityTarget>) {
        targets = newTargets
    }

    func bindToLocation(_ locationPublisher: AnyPublisher<TempRouteDataSample?, Never>) {
        cancellables.removeAll()

        locationPublisher
            .compactMap { $0 }
            .throttle(for: .seconds(5), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] sample in
                self?.checkProximity(to: sample)
            }
            .store(in: &cancellables)
    }

    func resetSession() {
        notifiedTargetIDs.removeAll()
    }

    func suppressTarget(id: String) {
        notifiedTargetIDs.insert(id)
    }

    private func checkProximity(to sample: TempRouteDataSample) {
        let userLocation = CLLocation(latitude: sample.latitude, longitude: sample.longitude)

        for target in targets {
            let targetLocation = CLLocation(
                latitude: target.coordinate.latitude,
                longitude: target.coordinate.longitude
            )
            let distance = userLocation.distance(from: targetLocation)

            if distance <= target.radius {
                guard !notifiedTargetIDs.contains(target.id) else { continue }
                notifiedTargetIDs.insert(target.id)
                proximityEvents.send(ProximityEvent(
                    target: target,
                    distance: distance,
                    direction: .entered
                ))
            } else if notifiedTargetIDs.contains(target.id), distance > target.radius * 1.2 {
                notifiedTargetIDs.remove(target.id)
                proximityEvents.send(ProximityEvent(
                    target: target,
                    distance: distance,
                    direction: .exited
                ))
            }
        }
    }
}
