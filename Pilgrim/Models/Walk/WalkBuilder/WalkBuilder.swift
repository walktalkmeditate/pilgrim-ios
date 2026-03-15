//
//  WalkBuilder.swift
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

public class WalkBuilder: ApplicationStateObserver {
    
    // MARK: Public

    /// The current status of this `WalkBuilder` instance.
    public var status: Status { statusRelay.value }

    public var statusPublisher: AnyPublisher<WalkBuilder.Status, Never> { statusRelay.eraseToAnyPublisher() }
    public var startDatePublisher: AnyPublisher<Date?, Never> { startDateRelay.eraseToAnyPublisher() }
    public var pausesPublisher: AnyPublisher<[TempWalkPause], Never> { pausesRelay.eraseToAnyPublisher() }
    public var locationsPublisher: AnyPublisher<[TempRouteDataSample], Never> { locationsRelay.eraseToAnyPublisher() }
    public var voiceRecordingsPublisher: AnyPublisher<[TempVoiceRecording], Never> { voiceRecordingsRelay.eraseToAnyPublisher() }
    public var meditateDurationPublisher: AnyPublisher<Double, Never> { meditateDurationRelay.eraseToAnyPublisher() }
    public var activityIntervalsPublisher: AnyPublisher<[TempActivityInterval], Never> { activityIntervalsRelay.eraseToAnyPublisher() }
    public var altitudesPublisher: AnyPublisher<[AltitudeManagement.AltitudeSample], Never> { altitudesRelay.eraseToAnyPublisher() }
    public var isSuspendedPublisher: AnyPublisher<Bool, Never> { suspensionRelay.eraseToAnyPublisher() }
    public var resetPublisher: AnyPublisher<WalkInterface?, Never> { resetRelay.eraseToAnyPublisher() }

    /// Requests a transition to the given status, validated against the current state.
    public func setStatus(_ newStatus: Status) {
        validateTransition(to: newStatus) { isValid in
            guard isValid else { return }
            self.statusRelay.accept(newStatus)
        }
    }
    
    // MARK: - Internal
    
    /// Indicating the type and last time when a walk was paused by the user or the app.
    private var lastPause: (type: WalkPause.PauseType, startingAt: Date)?
    /// Holds a reference to the types of walk builder components still preparing to record.
    private var preparingComponents: [WalkBuilderComponent.Type] = []

    /// Called when a walk snapshot is created after stopping.
    public var onSnapshotCreated: ((TempWalk) -> Void)?

    /// Closures that run synchronously before snapshot creation to flush component state.
    private var preSnapshotFlushActions: [() -> Void] = []

    /// Register a closure to run synchronously before createSnapshot.
    public func registerPreSnapshotFlush(_ action: @escaping () -> Void) {
        preSnapshotFlushActions.append(action)
    }

    /// Write voice recordings directly to the builder's relay, bypassing the async pipeline.
    public func flushVoiceRecordings(_ recordings: [TempVoiceRecording]) {
        voiceRecordingsRelay.accept(recordings)
    }

    /// Write meditate duration directly to the builder's relay, bypassing the async pipeline.
    public func flushMeditateDuration(_ duration: Double) {
        meditateDurationRelay.accept(duration)
    }

    /// Write activity intervals directly to the builder's relay, bypassing the async pipeline.
    public func flushActivityIntervals(_ intervals: [TempActivityInterval]) {
        activityIntervalsRelay.accept(intervals)
    }

    /// Write locations directly to the builder's relay, bypassing the async pipeline.
    public func flushLocations(_ locations: [TempRouteDataSample], distance: Double) {
        locationsRelay.accept(locations)
        distanceRelay.accept(distance)
    }

    /// Write steps directly to the builder's relay, bypassing the async pipeline.
    public func flushSteps(_ steps: Int?) {
        stepsRelay.accept(steps)
    }
    
    // MARK: - Initialisation
    
    /**
     Initialises a `WalkBuilder` instance.
     - parameter workoutType: the type of walk to record; defaults to `.walking`
     */
    public init(workoutType: Walk.WalkType = .walking) {
        self.workoutTypeRelay = CurrentValueRelay(workoutType)
        
        self.prepareBindings()
        self.startObservingApplicationState()
    }
    
    // MARK: - Bindings
    
    private func prepareBindings() {
        
        // reacting to status changes
        statusRelay.sink(receiveValue: { [weak self] newStatus in
            guard let self else { return }
            let timestamp = Date()
            
            switch newStatus {
            case .recording: // starting / resuming walk
                if self.startDateRelay.value == nil {
                    self.startDateRelay.accept(timestamp)
                    
                } else if let lastPause = self.lastPause {
                    self.lastPause = nil
                    if lastPause.type == .automatic, lastPause.startingAt.distance(to: timestamp) < 3 {
                        return // to eliminate short auto pauses
                    }
                    let pause = TempWalkPause(uuid: nil, startDate: lastPause.startingAt, endDate: timestamp, pauseType: lastPause.type)
                    let pauses = self.pausesRelay.value + [pause]
                    self.pausesRelay.accept(pauses)
                }
            
            case .paused, .autoPaused: // (auto) pausing walk
                let pauseType = newStatus == .paused ? WalkPause.PauseType.manual : .automatic
                if let lastPauseObject = self.pausesRelay.value.last, lastPauseObject.pauseType == pauseType, lastPauseObject.endDate.distance(to: timestamp) < 3 {
                    // last pause is of same type and under three seconds in the past -> merge
                    self.lastPause = (type: pauseType, startingAt: lastPauseObject.startDate)
                } else {
                    // normal pause will be created
                    self.lastPause = (type: pauseType, startingAt: self.lastPause?.startingAt ?? timestamp)
                }
                
            case .ready: // stopping walk or indicating readiness
                guard self.startDateRelay.value != nil else { return }

                if let lastPause = self.lastPause {
                    let pause = TempWalkPause(uuid: nil, startDate: lastPause.startingAt, endDate: timestamp, pauseType: lastPause.type)
                    let pauses = self.pausesRelay.value + [pause]
                    self.pausesRelay.accept(pauses)
                }

                self.endDateRelay.accept(timestamp)

                self.preSnapshotFlushActions.forEach { $0() }

                if let snapshot = self.createSnapshot() {
                    self.onSnapshotCreated?(snapshot)
                }

                self.reset()
                
            default: // ignore everything else
                break
            }
        }).store(in: &cancellables)
        
    }
    
    // MARK: - Dataflow
    
    /// An Array of cancellables for subscription links to components and custom permanent subscriptions.
    private var cancellables: [AnyCancellable] = []
    
    /// The relay to publish the current status of the `WalkBuilder`.
    private let statusRelay = CurrentValueRelay<WalkBuilder.Status>(.waiting)
    /// The relay to publish the type of walk the `WalkBuilder` is supposed to record.
    private let workoutTypeRelay: CurrentValueRelay<Walk.WalkType>
    /// The relay to publish the date the recorded walk was started.
    private let startDateRelay = CurrentValueRelay<Date?>(nil)
    /// The relay to publish the date the recorded walk was stopped.
    private let endDateRelay = CurrentValueRelay<Date?>(nil)
    /// The relay to publish the distance shared by components.
    private let distanceRelay = CurrentValueRelay<Double>(0)
    /// The relay to publish the steps counted by components.
    private let stepsRelay = CurrentValueRelay<Int?>(nil)
    /// The relay to publish the pauses initiated by the user or by the app automaticallyprivate
    private let pausesRelay = CurrentValueRelay<[TempWalkPause]>([])
    /// The relay to publish the current location regardless of whether it was recorded or not.
    private let currentLocationRelay = CurrentValueRelay<TempRouteDataSample?>(nil)
    /// The relay to publish the recorded locations received from components.
    private let locationsRelay = CurrentValueRelay<[TempRouteDataSample]>([])
    /// The relay to publish the altitudes received from components.
    private let altitudesRelay = CurrentValueRelay<[AltitudeManagement.AltitudeSample]>([])
    /// The relay to publish the heart rate samples received from components.
    private let heartRatesRelay = CurrentValueRelay<[TempHeartRateDataSample]>([])
    /// The relay to publish a components report of isufficient permissions to record the walk.
    private let insufficientPermissionRelay = PassthroughRelay<String>()
    /// The relay to publish a UI suspension command.
    private let uiSuspensionRelay = CurrentValueRelay<Bool>(false)
    /// The relay to publish a suspension command.
    private let suspensionRelay = CurrentValueRelay<Bool>(false)
    /// The relay to publish voice recordings captured during the walk.
    private let voiceRecordingsRelay = CurrentValueRelay<[TempVoiceRecording]>([])
    /// The relay to publish the total meditate duration in seconds.
    private let meditateDurationRelay = CurrentValueRelay<Double>(0)
    /// The relay to publish activity intervals captured during the walk.
    private let activityIntervalsRelay = CurrentValueRelay<[TempActivityInterval]>([])
    /// The relay to publish a reset command.
    private let resetRelay = PassthroughRelay<WalkInterface?>()
    
    /// A type containing all input data needed to establish a data flow.
    public struct Input {
        let readiness: AnyPublisher<WalkBuilderComponentStatus, Never>?
        let insufficientPermission: AnyPublisher<String, Never>?
        let workoutType: AnyPublisher<Walk.WalkType, Never>?
        let statusSuggestion: AnyPublisher<WalkBuilder.Status, Never>?
        let distance: AnyPublisher<Double, Never>?
        let steps: AnyPublisher<Int?, Never>?
        let currentLocation: AnyPublisher<TempRouteDataSample?, Never>?
        let locations: AnyPublisher<[TempRouteDataSample], Never>?
        let altitudes: AnyPublisher<[AltitudeManagement.AltitudeSample], Never>?
        let heartRates: AnyPublisher<[TempHeartRateDataSample], Never>?
        let voiceRecordings: AnyPublisher<[TempVoiceRecording], Never>?
        let meditateDuration: AnyPublisher<Double, Never>?

        public init(
            readiness: AnyPublisher<WalkBuilderComponentStatus, Never>? = nil,
            insufficientPermission: AnyPublisher<String, Never>? = nil,
            workoutType: AnyPublisher<Walk.WalkType, Never>? = nil,
            statusSuggestion: AnyPublisher<WalkBuilder.Status, Never>? = nil,
            distance: AnyPublisher<Double, Never>? = nil,
            steps: AnyPublisher<Int?, Never>? = nil,
            currentLocation: AnyPublisher<TempRouteDataSample?, Never>? = nil,
            locations: AnyPublisher<[TempRouteDataSample], Never>? = nil,
            altitudes: AnyPublisher<[AltitudeManagement.AltitudeSample], Never>? = nil,
            heartRates: AnyPublisher<[TempHeartRateDataSample], Never>? = nil,
            voiceRecordings: AnyPublisher<[TempVoiceRecording], Never>? = nil,
            meditateDuration: AnyPublisher<Double, Never>? = nil
        ) {
            self.readiness = readiness
            self.insufficientPermission = insufficientPermission
            self.workoutType = workoutType
            self.statusSuggestion = statusSuggestion
            self.distance = distance
            self.steps = steps
            self.currentLocation = currentLocation
            self.locations = locations
            self.altitudes = altitudes
            self.heartRates = heartRates
            self.voiceRecordings = voiceRecordings
            self.meditateDuration = meditateDuration
        }
    }
    
    /// A type containing all output data needed to establish a data flow.
    public struct Output {
        let status: AnyPublisher<WalkBuilder.Status, Never>
        let workoutType: AnyPublisher<Walk.WalkType, Never>
        let startDate: AnyPublisher<Date?, Never>
        let endDate: AnyPublisher<Date?, Never>
        let distance: AnyPublisher<Double, Never>
        let steps: AnyPublisher<Int?, Never>
        let pauses: AnyPublisher<[TempWalkPause], Never>
        let currentLocation: AnyPublisher<TempRouteDataSample?, Never>
        let locations: AnyPublisher<[TempRouteDataSample], Never>
        let altitudes: AnyPublisher<[AltitudeManagement.AltitudeSample], Never>
        let heartRates: AnyPublisher<[TempHeartRateDataSample], Never>
        let voiceRecordings: AnyPublisher<[TempVoiceRecording], Never>
        let meditateDuration: AnyPublisher<Double, Never>
        let insufficientPermission: AnyPublisher<String, Never>
        let isUISuspended: AnyPublisher<Bool, Never>
        let isSuspended: AnyPublisher<Bool, Never>
        let onReset: AnyPublisher<WalkInterface?, Never>
    }
    
    /**
     Tranforms the provided inputs to an output establishing a data flow between this WalkBuilder and the caller of this function.
     - parameter input: the input provided to the walk builder
     - returns: the output to provide the caller with the necessary data
     */
    public func tranform(_ input: WalkBuilder.Input) -> Output {
        
        input.readiness?.sink(receiveValue: readinessBinder).store(in: &cancellables)
        input.statusSuggestion?.sink(receiveValue: statusSuggestionBinder).store(in: &cancellables)
        input.insufficientPermission?.sink(receiveValue: insufficientPermissionRelay.accept).store(in: &cancellables)
        input.distance?.sink(receiveValue: distanceRelay.accept).store(in: &cancellables)
        input.steps?.sink(receiveValue: stepsRelay.accept).store(in: &cancellables)
        input.currentLocation?.sink(receiveValue: currentLocationRelay.accept).store(in: &cancellables)
        input.locations?.sink(receiveValue: locationsRelay.accept).store(in: &cancellables)
        input.altitudes?.sink(receiveValue: altitudesRelay.accept).store(in: &cancellables)
        input.heartRates?.sink(receiveValue: heartRatesRelay.accept).store(in: &cancellables)
        input.voiceRecordings?.sink(receiveValue: voiceRecordingsRelay.accept).store(in: &cancellables)
        input.meditateDuration?.sink(receiveValue: meditateDurationRelay.accept).store(in: &cancellables)

        return Output(
            status: statusRelay.asBackgroundPublisher(),
            workoutType: workoutTypeRelay.asBackgroundPublisher(),
            startDate: startDateRelay.asBackgroundPublisher(),
            endDate: endDateRelay.asBackgroundPublisher(),
            distance: distanceRelay.asBackgroundPublisher(),
            steps: stepsRelay.asBackgroundPublisher(),
            pauses: pausesRelay.asBackgroundPublisher(),
            currentLocation: currentLocationRelay.asBackgroundPublisher(),
            locations: locationsRelay.asBackgroundPublisher(),
            altitudes: altitudesRelay.asBackgroundPublisher(),
            heartRates: heartRatesRelay.asBackgroundPublisher(),
            voiceRecordings: voiceRecordingsRelay.asBackgroundPublisher(),
            meditateDuration: meditateDurationRelay.asBackgroundPublisher(),
            insufficientPermission: insufficientPermissionRelay.asBackgroundPublisher(),
            isUISuspended: uiSuspensionRelay.asBackgroundPublisher(),
            isSuspended: suspensionRelay.asBackgroundPublisher(),
            onReset: resetRelay.asBackgroundPublisher()
        )
    }
    
    /// A closure to update the readiness status of components.
    private var readinessBinder: (WalkBuilderComponentStatus) -> Void {
        return { [weak self] status in
            guard let self else { return }
            guard !self.statusRelay.value.isActiveStatus else { return }
            switch status {
            case .preparing(let preparingType):
                guard !self.preparingComponents.contains(where: { $0 == preparingType }) else { return }
                self.preparingComponents.append(preparingType)
            case .ready(let preparingType):
                self.preparingComponents.removeAll(where: { $0 == preparingType })
            }
            let isReadyToRecord = self.preparingComponents.isEmpty
            let newStatus: Status = isReadyToRecord ? .ready : .waiting
            self.validateTransition(to: newStatus) { isValid in
                guard isValid else { return }
                self.statusRelay.accept(newStatus)
            }
        }
    }
    
    /// A closure to enable components to suggest a new status.
    private var statusSuggestionBinder: (WalkBuilder.Status) -> Void {
        return { [weak self] status in
            guard let self else { return }
            self.validateTransition(to: status) { (isValid) in
                guard isValid else { return }
                self.statusRelay.accept(status)
            }
        }
    }
    
    // MARK: - Create Snapshot

    public func createCheckpointSnapshot() -> TempWalk? {
        guard let start = startDateRelay.value else { return nil }

        return NewWalk(
            workoutType: workoutTypeRelay.value,
            distance: distanceRelay.value,
            steps: stepsRelay.value,
            startDate: start,
            endDate: Date(),
            isRace: false,
            comment: nil,
            isUserModified: false,
            finishedRecording: false,
            heartRates: [],
            routeData: locationsRelay.value,
            pauses: pausesRelay.value,
            workoutEvents: [],
            voiceRecordings: voiceRecordingsRelay.value,
            activityIntervals: activityIntervalsRelay.value
        )
    }

    /**
     Creates a snapshot of the walk currently under construction.
     - returns: a `TempWalk` constructed from the recorded data; will be `nil` when start or end cannot be determined
     */
    private func createSnapshot() -> TempWalk? {

        guard let start = startDateRelay.value, let end = endDateRelay.value else { return nil }

        return NewWalk(
            workoutType: workoutTypeRelay.value,
            distance: distanceRelay.value,
            steps: stepsRelay.value,
            startDate: start,
            endDate: end,
            isRace: false,
            comment: nil,
            isUserModified: false,
            finishedRecording: true,
            heartRates: [],
            routeData: locationsRelay.value,
            pauses: pausesRelay.value,
            workoutEvents: [],
            voiceRecordings: voiceRecordingsRelay.value,
            activityIntervals: activityIntervalsRelay.value
        )
    }
    
    // MARK: - Preparation
    
    /// Resets the `WalkBuilder` and it's components and prepares them for another recording.
    private func reset() {

        statusRelay.accept(.waiting)
        startDateRelay.accept(nil)
        endDateRelay.accept(nil)
        distanceRelay.accept(0)
        stepsRelay.accept(nil)
        currentLocationRelay.accept(nil)
        locationsRelay.accept([])
        altitudesRelay.accept([])
        heartRatesRelay.accept([])
        pausesRelay.accept([])
        voiceRecordingsRelay.accept([])
        meditateDurationRelay.accept(0)
        activityIntervalsRelay.accept([])
        lastPause = nil
        resetRelay.accept(nil)
    }
    
    /**
     Continues a walk by setting up the `WalkBuilder` and its components like they are recording.
     - parameter snapshot: the snapshot made of the continued walk
     */
    public func continueWalk(from snapshot: TempWalk) {
        
        startDateRelay.accept(snapshot.startDate)
        endDateRelay.accept(nil)
        pausesRelay.accept(snapshot.pauses.map { TempWalkPause(uuid: $0.uuid, startDate: $0.startDate, endDate: $0.endDate, pauseType: $0.pauseType) })
        lastPause = (type: .manual, startingAt: snapshot.endDate)
        resetRelay.accept(snapshot)
        self.validateTransition(to: .recording) { isValid in
            guard isValid else { return }
            self.statusRelay.accept(.recording)
        }
    }
    
    // MARK: - Validation
    
    /**
     Validates the transition to a new status
     - parameter newStatus: the new status the `WalkBuilder` is supposed to take on
     - parameter closure: the closure being performed with a boolean indicating if the transition is valid as an argument; the closure will not be called if the status is equal to the current one
     */
    private func validateTransition(to newStatus: WalkBuilder.Status, closure: (Bool) -> Void) {
        let oldStatus = self.statusRelay.value
        guard oldStatus != newStatus else { return }
        
        var isValid = false
        
        switch newStatus {
        case .recording: isValid = oldStatus != .waiting
        case .paused: isValid = [.recording, .autoPaused].contains(oldStatus)
        case .waiting: isValid = oldStatus == .ready
        case .ready: isValid = true
        case .autoPaused: isValid = oldStatus == .recording
        }
        
        closure(isValid)
    }
    
    // MARK: - ApplicationStateObserver
    
    /// Implementation of the `ApplicationStateObserver` protocol sending a suspension command to all subscribers when not recording to save battery life.
    func didUpdateApplicationState(to state: ApplicationState) {
        self.uiSuspensionRelay.accept(state == .background)
        guard !self.statusRelay.value.isActiveStatus else { return }
        self.suspensionRelay.accept(state == .background)
    }
    
}
