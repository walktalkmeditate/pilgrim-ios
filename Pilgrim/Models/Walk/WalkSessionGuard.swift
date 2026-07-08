import Foundation
import UIKit
import CoreLocation
import Combine
import AVFoundation

class WalkSessionGuard {

    static weak var active: WalkSessionGuard?

    weak var builder: WalkBuilder?
    weak var locationManagement: LocationManagement?
    weak var viewModel: ActiveWalkViewModel?

    private var checkpointTimer: Timer?
    private var currentTier: PowerTier = .normal
    private let tierSubject = CurrentValueSubject<PowerTier, Never>(.normal)
    private var cancellables: [AnyCancellable] = []

    /// Announces tier changes to consumers that adapt their own cadence
    /// (seek pulse clock). Observation only — GPS power stays routed through
    /// this guard exclusively (AF14).
    var powerTierPublisher: AnyPublisher<PowerTier, Never> { tierSubject.eraseToAnyPublisher() }
    private var walkUUID: UUID?
    private var checkpointCount = 0

    static let tag = "[SessionGuard]"

    /// Provisional (in-flight) recordings — the ones created by
    /// `VoiceRecordingManagement.checkpointVoiceRecording()` — are the only
    /// voice recordings with a nil UUID in our pipeline. Finalized recordings
    /// get a UUID in `finalizeRecording()`; orphan-reconnected recordings get
    /// one in `reconnectOrphanedRecordings`. Kept as a static helper so both
    /// the checkpoint log site and the recovery sanitization loop share the
    /// same definition of "in-flight."
    static func isProvisional(_ recording: VoiceRecordingInterface) -> Bool {
        recording.uuid == nil
    }

    // MARK: - Power Tiers

    enum PowerTier: Equatable, CustomStringConvertible {
        case normal
        case meditation
        case low
        case critical

        var checkpointInterval: TimeInterval {
            switch self {
            case .normal:     return 30
            case .meditation: return 60
            case .low:        return 15
            case .critical:   return 10
            }
        }

        var gpsAccuracy: CLLocationAccuracy {
            switch self {
            case .normal:     return kCLLocationAccuracyBest
            case .meditation: return 100
            case .low:        return kCLLocationAccuracyNearestTenMeters
            case .critical:   return kCLLocationAccuracyNearestTenMeters
            }
        }

        var distanceFilter: CLLocationDistance {
            switch self {
            case .normal:     return kCLDistanceFilterNone
            case .meditation: return 50
            case .low:        return 10
            case .critical:   return 10
            }
        }

        var description: String {
            switch self {
            case .normal:     return "normal"
            case .meditation: return "meditation"
            case .low:        return "low"
            case .critical:   return "critical"
            }
        }
    }

    // MARK: - Lifecycle

    func start() {
        Self.active = self

        let battery = UIDevice.current.batteryLevel
        let thermal = ProcessInfo.processInfo.thermalState
        print("\(Self.tag) START — battery: \(String(format: "%.0f%%", battery * 100)), thermal: \(Self.thermalName(thermal))")

        UIDevice.current.isBatteryMonitoringEnabled = true

        // Main delivery is load-bearing (AF12): thermal notifications post on a
        // background thread, and recalculateTier reschedules the checkpoint
        // Timer — a timer installed on a runloop-less GCD worker never fires,
        // silently ending crash-recovery checkpointing for the rest of the walk.
        NotificationCenter.default.publisher(for: UIDevice.batteryLevelDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recalculateTier() }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: ProcessInfo.thermalStateDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recalculateTier() }
            .store(in: &cancellables)

        viewModel?.$isMeditating
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.recalculateTier() }
            .store(in: &cancellables)

        recalculateTier()
        restartTimer()
    }

    /// Tears down timers/observers/power adjustments but leaves the
    /// checkpoint file on disk. The checkpoint must outlive the save
    /// transaction: the walk-end flow calls this, then deletes the file via
    /// `WalkSessionGuard.deleteCheckpointFile()` only inside the
    /// `DataManager.saveWalk` success callback. A failed save keeps the
    /// checkpoint so `recoverIfNeeded` restores the walk on next launch.
    func stop() {
        print("\(Self.tag) STOP — wrote \(checkpointCount) checkpoints during session")
        checkpointTimer?.invalidate()
        checkpointTimer = nil
        cancellables.removeAll()
        locationManagement?.restoreDefaultPower()
        UIDevice.current.isBatteryMonitoringEnabled = false
        Self.active = nil
    }

    /// User-discard path (walk cancel): tears down AND removes the
    /// checkpoint — the user explicitly threw the walk away, so there is
    /// nothing to recover.
    func stopAndCleanup() {
        stop()
        Self.deleteCheckpointFile()
    }

    deinit {
        checkpointTimer?.invalidate()
        print("\(Self.tag) DEINIT")
    }

    // MARK: - Checkpointing

    /// Serializes all checkpoint file I/O. Encoding the full walk and
    /// writing a multi-MB file every 10–30 s on the main thread was a
    /// recurring stall that got worse precisely when the device was already
    /// struggling (AF13). `deleteCheckpointFile` runs `sync` on this same
    /// queue so a deletion ordered after a write can never be overtaken by
    /// that write resurrecting a saved walk's checkpoint.
    private static let checkpointIOQueue = DispatchQueue(label: "WalkSessionGuard.checkpointIO", qos: .utility)

    func checkpointNow() {
        // The builder's locations relay no longer receives per-sample
        // growth (AF9/AF46) — pull the canonical route in before
        // snapshotting so the checkpoint stays complete.
        locationManagement?.syncRouteToBuilder()

        guard let builder, let snapshot = builder.createCheckpointSnapshot() else {
            print("\(Self.tag) CHECKPOINT SKIPPED — no builder or no start date")
            return
        }

        if let viewModel {
            let intervals = viewModel.checkpointActivityIntervals()
            snapshot.replaceActivityIntervals(intervals)

            if let inflightTalk = viewModel.voiceRecordingManagement.checkpointVoiceRecording() {
                snapshot.appendVoiceRecordings([inflightTalk])
            }
        }

        if walkUUID == nil {
            walkUUID = Self.extractRecordingDirectoryUUID(from: snapshot) ?? UUID()
        }

        guard let resolvedUUID = walkUUID else { return }
        let checkpoint = WalkCheckpoint(walkUUID: resolvedUUID, walk: snapshot)
        let tier = currentTier

        // Snapshot capture stays on main (above); the encode + atomic write
        // move to the utility queue. The snapshot is freshly built and never
        // mutated after this point, so handing it off is safe.
        Self.checkpointIOQueue.async { [weak self] in
            do {
                let data = try JSONEncoder().encode(checkpoint)
                let url = Self.checkpointFileURL()
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url, options: .atomic)
                #if DEBUG
                self?._test_onCheckpointPersisted?(Thread.isMainThread)
                #endif
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.checkpointCount += 1
                    let talkFlag = snapshot.voiceRecordings.contains(where: Self.isProvisional) ? " (inflight)" : ""
                    print("\(Self.tag) CHECKPOINT #\(self.checkpointCount) — tier: \(tier), routes: \(snapshot.routeData.count), pauses: \(snapshot.pauses.count), recordings: \(snapshot.voiceRecordings.count)\(talkFlag), intervals: \(snapshot.activityIntervals.count), size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
                }
            } catch {
                print("\(Self.tag) CHECKPOINT WRITE FAILED: \(error)")
            }
        }
    }

    // MARK: - Tier Management

    private func recalculateTier() {
        #if DEBUG
        _test_onRecalculateTier?()
        let batteryLevel = _test_batteryLevelOverride ?? UIDevice.current.batteryLevel
        #else
        let batteryLevel = UIDevice.current.batteryLevel
        #endif
        let thermalState = ProcessInfo.processInfo.thermalState
        let isMeditating = viewModel?.isMeditating ?? false

        let newTier: PowerTier
        if (batteryLevel >= 0 && batteryLevel <= 0.05) || thermalState == .serious || thermalState == .critical {
            newTier = .critical
        } else if batteryLevel >= 0 && batteryLevel <= 0.20 {
            newTier = .low
        } else if isMeditating {
            newTier = .meditation
        } else {
            newTier = .normal
        }

        guard newTier != currentTier else { return }
        let oldTier = currentTier
        currentTier = newTier
        tierSubject.send(newTier)
        print("\(Self.tag) TIER \(oldTier) → \(newTier) — battery: \(String(format: "%.0f%%", batteryLevel * 100)), thermal: \(Self.thermalName(thermalState)), meditating: \(isMeditating), interval: \(newTier.checkpointInterval)s, gps: \(Self.accuracyName(newTier.gpsAccuracy))")
        applyTier(newTier)
    }

    private func applyTier(_ tier: PowerTier) {
        restartTimer()

        guard let locationManagement else { return }
        if tier == .normal {
            locationManagement.restoreDefaultPower()
        } else {
            locationManagement.adjustPower(accuracy: tier.gpsAccuracy, distanceFilter: tier.distanceFilter)
        }
    }

    private func restartTimer() {
        checkpointTimer?.invalidate()
        checkpointTimer = Timer.scheduledTimer(
            withTimeInterval: currentTier.checkpointInterval,
            repeats: true
        ) { [weak self] _ in
            self?.checkpointNow()
        }
    }

    // MARK: - File I/O

    static func checkpointFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("walk_checkpoint.json")
    }

    /// Runs `sync` on the checkpoint I/O queue so the deletion is ordered
    /// after any in-flight checkpoint write — otherwise a write dispatched
    /// just before walk end could land after the post-save cleanup and
    /// resurrect a checkpoint for an already-saved walk. The wait is bounded
    /// by at most one pending encode+write and happens once per walk end.
    static func deleteCheckpointFile() {
        checkpointIOQueue.sync {
            let url = checkpointFileURL()
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            do {
                try FileManager.default.removeItem(at: url)
                print("\(tag) CLEANUP — checkpoint file deleted")
            } catch {
                print("\(tag) CLEANUP FAILED: \(error), retrying in 1s")
                checkpointIOQueue.asyncAfter(deadline: .now() + 1) {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    // MARK: - Recovery

    // Crash recovery lives in WalkSessionGuard+Recovery.swift.

    // MARK: - Test Hooks

    #if DEBUG
    /// Observes each tier recalculation so dispatch tests can prove the
    /// battery/thermal sinks deliver on the main thread (AF12 regression).
    var _test_onRecalculateTier: (() -> Void)?
    /// Stands in for `UIDevice.current.batteryLevel` so tier tests can
    /// simulate low-battery walks (AF14).
    var _test_batteryLevelOverride: Float?
    /// Fires after each checkpoint file write with `Thread.isMainThread`,
    /// proving the encode+write moved off the main thread (AF13).
    var _test_onCheckpointPersisted: ((Bool) -> Void)?
    #endif

    // MARK: - Formatting Helpers

    private static func thermalName(_ state: ProcessInfo.ThermalState) -> String {
        switch state {
        case .nominal:  return "nominal"
        case .fair:     return "fair"
        case .serious:  return "serious"
        case .critical: return "critical"
        @unknown default: return "unknown"
        }
    }

    private static func accuracyName(_ accuracy: CLLocationAccuracy) -> String {
        if accuracy == kCLLocationAccuracyBest { return "best" }
        if accuracy == kCLLocationAccuracyNearestTenMeters { return "10m" }
        return "\(Int(accuracy))m"
    }
}
