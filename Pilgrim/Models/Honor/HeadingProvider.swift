import Combine
import CoreLocation
import Foundation

protocol HeadingProviding: AnyObject {
    /// True heading in degrees, nil until the compass has settled; on the main queue.
    var headingPublisher: AnyPublisher<Double?, Never> { get }
    func start()
    func stop()
}

/// The compass behind the direction tick on a Way card. Its own manager,
/// not the walk's: heading updates are a separate subscription from
/// location, and this one lives only while a Way is being honored — the
/// engine starts it and teardown stops it.
final class HeadingProvider: NSObject, HeadingProviding, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private let subject = CurrentValueSubject<Double?, Never>(nil)
    private var running = false

    var headingPublisher: AnyPublisher<Double?, Never> { subject.eraseToAnyPublisher() }

    override init() {
        super.init()
        manager.delegate = self
        manager.headingFilter = 3
    }

    deinit { manager.stopUpdatingHeading() }

    func start() {
        guard !running, CLLocationManager.headingAvailable() else { return }
        running = true
        manager.startUpdatingHeading()
    }

    func stop() {
        guard running else { return }
        running = false
        manager.stopUpdatingHeading()
        subject.send(nil)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        // A negative accuracy means the compass is not calibrated; the tick
        // hides rather than point somewhere wrong.
        guard newHeading.headingAccuracy >= 0 else { subject.send(nil); return }
        let heading = newHeading.trueHeading >= 0 ? newHeading.trueHeading : newHeading.magneticHeading
        subject.send(heading)
    }
}
