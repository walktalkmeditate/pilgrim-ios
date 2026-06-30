//
//  LocationManagement.swift
//
//  Pilgrim
//  Copyright (C) 2020 Tim Fraedrich <timfraedrich@icloud.com>
//  Copyright (C) 2025-2026 Walk Talk Meditate contributors
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import CoreLocation
import Combine
import CombineExt

/// A `WalkBuilderComponent` to manage everything location related
public class LocationManagement: NSObject, WalkBuilderComponent, CLLocationManagerDelegate {
    
    /// An instance of `CLLocationManager` used as the data source for locations.
    private var locationManager: CLLocationManager = CLLocationManager()
    /// The minimum horizontal accuracy a location is supposed to have to be recorded; if `nil` the user does not want locations to be checked for accuracy.
    private var desiredAccuracy: Double?
    /// The average horizontal accuracy of incoming locations while recording.
    private var averageAccuracy: Double = 0
    /// An array of altitude samples provided by the `WalkBuilder`.
    private var altitudeData: [AltitudeManagement.AltitudeSample] = []
    /// Weak reference to the builder for pre-snapshot flush.
    private weak var builder: WalkBuilder?

    /// Canonical recorded route, appended in place so per-sample cost stays
    /// amortized O(1) (AF9/AF46). The relay-based `locationsRelay` channel
    /// now only carries full-array events (reset/recovery seeding and
    /// explicit syncs); per-sample growth is published through
    /// `sampleAppendedPublisher`. Main-confined: CLLocationManager delivers
    /// on the run loop it was created on (main), and all sync points
    /// (checkpoint timer, pre-snapshot flush, reset binder) run on main.
    private(set) var recordedSamples: [TempRouteDataSample] = []
    
    /**
     Checks a `CLLocation` for appropriate horizontal accuracy based on user preferences and gathered data
     - parameter location: the `CLLocation` that is supposed to be checked
     - returns: a boolean whether the `CLLocation` is appropriate for use or not
     */
    private func checkForAppropriateAccuracy(_ location: CLLocation) -> Bool {
        guard let desiredAccuracy = self.desiredAccuracy else { return true }
        return location.horizontalAccuracy < 100 && location.horizontalAccuracy <= desiredAccuracy
    }
    
    /**
     Updates `desiredAccuracy` from the averageAccuracy of past and new location values
     - parameter locations: the new locations to retrieve accuracy values from
     */
    private func updateDesiredAccuracy(from locations: [CLLocation]) {

        guard UserPreferences.gpsAccuracy.value == nil, !locations.isEmpty else { return }

        var averageAccuracy: Double = 0
        for (index, location) in locations.enumerated() {
            let index = Double(index)
            averageAccuracy = ( averageAccuracy * index + location.horizontalAccuracy ) / ( index + 1 )
        }

        let globalCount = Double(min(self.recordedSamples.count, 9))
        let localCount = Double(locations.count)
        
        self.averageAccuracy = (self.averageAccuracy * globalCount + averageAccuracy * localCount) / (globalCount + localCount)
        self.desiredAccuracy = min(self.averageAccuracy.rounded(decimalPlaces: -1, rule: .up), 20)
    }
    
    /**
     Refines the provided location with altitude data.
     - parameter location: the location that is supposed to be refined
     - returns: the refined location
     */
    private func refineLocation(_ location: CLLocation) -> CLLocation {
        guard let firstAltitude = recordedSamples.first?.altitude, let relativeAltitude = altitudeData.last(where: { $0.timestamp < location.timestamp })?.altitude else { return location }
        return location.replacing(altitude: firstAltitude + relativeAltitude)
    }
    
    // MARK: - Dataflow
    
    /// An Array of cancellables for binding to the walk builder.
    private var cancellables: [AnyCancellable] = []
    
    /// The relay to publish the status of readiness to the walk builder.
    private let readinessRelay = CurrentValueRelay<WalkBuilderComponentStatus>(.preparing(LocationManagement.self))
    /// The relay to publish that insufficient permission was granted to the walk builder.
    private let insufficientPermissionRelay = PassthroughRelay<String>()
    /// The relay to publish the distance travelled to the walk builder.
    private let distanceRelay = CurrentValueRelay<Double>(0)
    /// The relay to publish the current location to the walk builder.
    private let currentLocationRelay = CurrentValueRelay<TempRouteDataSample?>(nil)
    /// The relay to publish all recorded locations to the walk builder.
    /// Carries full-array events only (reset/recovery seeding) — per-sample
    /// growth flows through `sampleAppendedRelay` instead (AF9/AF46).
    private let locationsRelay = CurrentValueRelay<[TempRouteDataSample]>([])
    /// Publishes each sample appended to the route together with the route's
    /// total count after the append, so consumers can detect (and recover
    /// from) any interleaving with full-array events.
    private let sampleAppendedRelay = PassthroughRelay<(sample: TempRouteDataSample, totalCount: Int)>()

    /// Per-sample route growth. Delivered synchronously on the main thread
    /// from the CLLocationManager delegate.
    var sampleAppendedPublisher: AnyPublisher<(sample: TempRouteDataSample, totalCount: Int), Never> {
        sampleAppendedRelay.eraseToAnyPublisher()
    }
    
    // MARK: Binders

    /// Binds altititude updates to this component.
    private var altitudesBinder: ([AltitudeManagement.AltitudeSample]) -> Void {
        return { [weak self] altitudes in
            guard let self else { return }
            self.altitudeData = altitudes
        }
    }
    
    /// Binds suspension events to this component.
    private var isSuspendedBinder: (Bool) -> Void {
        return { [weak self] isSuspended in
            guard let self else { return }
            if isSuspended {
                self.locationManager.stopUpdatingLocation()
            } else {
                self.locationManager.startUpdatingLocation()
            }
        }
    }
    
    /// Binds reset events to this component.
    private var onResetBinder: (WalkInterface?) -> Void {
        return { [weak self] snapshot in
            guard let self else { return }
            self.recordedSamples = snapshot?.routeData.map { .init(from: $0) } ?? []
            self.locationsRelay.accept(self.recordedSamples)
            self.distanceRelay.accept(snapshot?.distance ?? 0)
            self.locationManager.startUpdatingLocation()
        }
    }
    
    
    // MARK: - Power Adjustment

    private var baseAccuracy: CLLocationAccuracy = kCLLocationAccuracyBest
    private var baseDistanceFilter: CLLocationDistance = kCLDistanceFilterNone

    public func adjustPower(accuracy: CLLocationAccuracy, distanceFilter: CLLocationDistance) {
        locationManager.desiredAccuracy = accuracy
        locationManager.distanceFilter = distanceFilter
    }

    public func restoreDefaultPower() {
        locationManager.desiredAccuracy = baseAccuracy
        locationManager.distanceFilter = baseDistanceFilter
    }

    #if DEBUG
    /// Lets tests observe the accuracy actually applied to the location
    /// manager, proving the battery tier survives meditation (AF14).
    var _test_appliedAccuracy: CLLocationAccuracy { locationManager.desiredAccuracy }
    #endif

    // MARK: WalkBuilderComponent

    public required init(builder: WalkBuilder) {
        super.init()
        self.builder = builder
        self.bind(builder: builder)
        prepare()

        // [weak builder] breaks the self-retain cycle (AF8): the closure lives
        // in builder.preSnapshotFlushActions, so a strong capture would keep
        // the builder — and a cancelled walk's entire route — alive forever.
        builder.registerPreSnapshotFlush { [weak self] in
            self?.syncRouteToBuilder()
        }
    }

    /// Writes the canonical route and distance into the builder's relays.
    /// The relay channel no longer carries per-sample growth (AF9/AF46), so
    /// snapshot consumers must sync explicitly: the pre-snapshot flush does
    /// it at walk end, and `WalkSessionGuard.checkpointNow` does it before
    /// each checkpoint snapshot.
    func syncRouteToBuilder() {
        builder?.flushLocations(recordedSamples, distance: distanceRelay.value)
    }
    
    public func bind(builder: WalkBuilder) {

        let input = Input(
            readiness: readinessRelay.asBackgroundPublisher(),
            insufficientPermission: insufficientPermissionRelay.asBackgroundPublisher(),
            distance: distanceRelay.asBackgroundPublisher(),
            currentLocation: currentLocationRelay.asBackgroundPublisher(),
            locations: locationsRelay.asBackgroundPublisher()
        )

        _ = builder.tranform(input)

        builder.altitudesPublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: altitudesBinder)
            .store(in: &cancellables)
        builder.isSuspendedPublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: isSuspendedBinder)
            .store(in: &cancellables)
        builder.resetPublisher
            .receive(on: DispatchQueue.main)
            .sink(receiveValue: onResetBinder)
            .store(in: &cancellables)
        builder.statusPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                guard let self, status.isActiveStatus else { return }
                self.locationManager.startUpdatingLocation()
                if self.recordedSamples.isEmpty, let current = self.currentLocationRelay.value {
                    self.appendRouteSample(current)
                }
            }
            .store(in: &cancellables)
    }

    private func appendRouteSample(_ sample: TempRouteDataSample) {
        recordedSamples.append(sample)
        sampleAppendedRelay.accept((sample: sample, totalCount: recordedSamples.count))
    }
    
    public func prepare() {
        
        if UserPreferences.gpsAccuracy.value != -1 {
            self.desiredAccuracy = UserPreferences.gpsAccuracy.value ?? 20
        }
        
        self.locationManager.delegate = self
        self.locationManager.desiredAccuracy = kCLLocationAccuracyBest
        self.locationManager.allowsBackgroundLocationUpdates = true
        self.locationManager.activityType = .fitness
        self.locationManager.showsBackgroundLocationIndicator = true
        self.locationManager.requestWhenInUseAuthorization()
        self.locationManager.pausesLocationUpdatesAutomatically = false
        self.locationManager.startUpdatingLocation()

        self.baseAccuracy = self.locationManager.desiredAccuracy
        self.baseDistanceFilter = self.locationManager.distanceFilter
    }
    
    // MARK: - CLLocationManagerDelegate
    
    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        updateDesiredAccuracy(from: locations)

        let status = builder?.status ?? .waiting

        guard status.isActiveStatus else {
            if let lastLocation = locations.last {
                currentLocationRelay.accept(lastLocation.asTemp)
            }
            let isReady = locations.contains { checkForAppropriateAccuracy($0) }
            let newStatus: WalkBuilderComponentStatus = isReady ? .ready(LocationManagement.self) : .preparing(LocationManagement.self)

            guard readinessRelay.value != newStatus else { return }
            readinessRelay.accept(newStatus)
            return
        }

        let shouldUpdateDistance = !status.isPausedStatus

        for location in locations {
            let isFirst = recordedSamples.isEmpty
            guard isFirst || checkForAppropriateAccuracy(location) else { continue }

            let location = refineLocation(location)
            let sample = location.asTemp
            let previousSample = recordedSamples.last
            appendRouteSample(sample)
            currentLocationRelay.accept(sample)

            guard shouldUpdateDistance, let lastLocation = previousSample else { continue }
            let newDistance = location.distance(from: lastLocation.clLocation) + distanceRelay.value
            distanceRelay.accept(newDistance)
        }
    }
    
    public func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("LocationManagement] CLLocationManager failed with error:", error.localizedDescription)
    }
    
    public func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        guard ![.authorizedAlways, .authorizedWhenInUse].contains(status) else { return }
        insufficientPermissionRelay.accept(LS["Setup.Permission.Location.Error"])
    }
}
