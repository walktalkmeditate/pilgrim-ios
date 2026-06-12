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
    private var cancellables: [AnyCancellable] = []
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

    func checkpointNow() {
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

        do {
            let data = try JSONEncoder().encode(checkpoint)
            let url = Self.checkpointFileURL()
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: url, options: .atomic)
            checkpointCount += 1
            let talkFlag = snapshot.voiceRecordings.contains(where: Self.isProvisional) ? " (inflight)" : ""
            print("\(Self.tag) CHECKPOINT #\(checkpointCount) — tier: \(currentTier), routes: \(snapshot.routeData.count), pauses: \(snapshot.pauses.count), recordings: \(snapshot.voiceRecordings.count)\(talkFlag), intervals: \(snapshot.activityIntervals.count), size: \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))")
        } catch {
            print("\(Self.tag) CHECKPOINT WRITE FAILED: \(error)")
        }
    }

    // MARK: - Tier Management

    private func recalculateTier() {
        #if DEBUG
        _test_onRecalculateTier?()
        #endif
        let batteryLevel = UIDevice.current.batteryLevel
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

    static func deleteCheckpointFile() {
        let url = checkpointFileURL()
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            print("\(tag) CLEANUP — checkpoint file deleted")
        } catch {
            print("\(tag) CLEANUP FAILED: \(error), retrying in 1s")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                try? FileManager.default.removeItem(at: url)
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
